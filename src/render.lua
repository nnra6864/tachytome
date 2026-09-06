local mp        = require 'mp'
local utils     = require 'mp.utils'
local common    = require 'src.common'
local stats     = require 'src.stats'
local queue     = require 'src.queue'
local state     = require 'src.state'
local notify    = require 'src.notify'
local theme     = require 'src.theme'
local process   = require 'src.process'
local ui_choice = require 'src.ui_choice'

local M = {}

local current_req = nil

local platform    = common.get_platform()
local can_suspend = platform ~= "windows"

local stats_ov = mp.create_osd_overlay("ass-events")

function M.cancel_render()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    if queue.is_rendering and queue.active and current_req then
        queue.active.cancelled = true
        mp.abort_async_command(current_req)
    else
        notify.show("No active render to cancel.", true, "warn")
    end
end

function M.is_paused()
    return queue.render_paused or queue.queue_paused
end

local function read_active_pid()
    if not queue.active or not queue.active.pid_file then return nil end
    local f = io.open(queue.active.pid_file, "r")
    if not f then return nil end
    local pid = tonumber(f:read("*l"))
    f:close()
    return pid
end

function M.toggle_pause()
    if not queue.is_rendering or not queue.active then
        queue.queue_paused = not queue.queue_paused
        if queue.queue_paused then
            notify.show("Render queue paused.", true)
        else
            notify.show("Render queue resumed.", true)
            M.process_queue()
        end
        return
    end

    if not can_suspend then
        queue.queue_paused = not queue.queue_paused
        if queue.queue_paused then
            notify.show("Pausing render queue: finishing current file, then holding.", true)
        else
            notify.show("Render queue resumed.", true)
            M.process_queue()
        end
        return
    end

    if queue.render_paused then
        if queue.active.paused_pid then
            process.signal_pid(queue.active.paused_pid, "CONT")
            queue.render_paused = false
            queue.queue_paused  = false
            queue.save()
            notify.show("Render resumed: " .. queue.active.final_name, true)
        else
            notify.show("Cannot resume render.", true, "error")
        end
        return
    end

    local pid = read_active_pid()
    if not pid then
        notify.show("Render is still starting, try again shortly.", true, "warn")
        return
    end

    process.signal_pid(pid, "STOP")
    queue.active.paused_pid = pid
    queue.render_paused     = true
    queue.queue_paused      = true
    queue.save()
    notify.show("Render paused: " .. queue.active.final_name, true)
end

local function queue_job(job, on_complete)
    table.insert(queue.jobs, job)
    queue.total_jobs = queue.total_jobs + 1
    common.save_history(state.path_history)
    if queue.is_rendering then
        notify.show(string.format("Queued: %s", job.final_name), true)
    elseif queue.queue_paused then
        notify.show(string.format("Queued: %s (queue paused)", job.final_name), true)
    end
    M.process_queue()
    queue.save()
    if on_complete then on_complete() end
end

function M.process_queue()
    if queue.is_rendering or queue.queue_paused or #queue.jobs == 0 then return end

    queue.is_rendering    = true
    queue.render_paused   = false
    queue.current_job_num = queue.current_job_num + 1
    queue.active          = table.remove(queue.jobs, 1)

    local active_job = queue.active

    local temp_dir      = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local file_id       = tostring(math.floor(mp.get_time() * 1000))
    local progress_file = utils.join_path(temp_dir, "tachytome_prog_" .. file_id .. ".log")
    local pid_file      = utils.join_path(temp_dir, "tachytome_pid_" .. file_id .. ".log")
    active_job.pid_file = pid_file

    active_job.args[active_job.output_arg_index] = active_job.temp_file

    table.insert(active_job.args, "-progress")
    table.insert(active_job.args, progress_file)

    local launch_args = active_job.args
    if can_suspend then
        launch_args = {"sh", "-c", 'echo $$ > "$1"; shift; exec "$@"', "tachytome", pid_file}
        for _, v in ipairs(active_job.args) do table.insert(launch_args, v) end
    end

    local name_no_ext      = active_job.final_name:match("^(.*)%.[^%.]+$") or active_job.final_name
    local progress_overlay = mp.create_osd_overlay("ass-events")

    local function get_queue_str()
        return (queue.total_jobs > 1) and string.format("[%d/%d] ", queue.current_job_num, queue.total_jobs) or ""
    end

    progress_overlay.data = string.format("%s%s%s%sRendering %s: 0%%", theme.align(9), theme.f(true), theme.a("66"), get_queue_str(), name_no_ext)
    progress_overlay:update()

    notify.show("Render started: " .. active_job.final_name, true)

    local progress_timer = mp.add_periodic_timer(0.5, function()
        local f = io.open(progress_file, "rb")
        if f then
            local size = f:seek("end")
            if size and size > 0 then
                local read_size = math.min(size, 2048)
                f:seek("set", size - read_size)
                local content = f:read("*all")

                local time_us = nil
                for t in content:gmatch("out_time_us=(%d+)") do time_us = t end

                if time_us then
                    local percent = math.floor((tonumber(time_us) / 1000000) / active_job.duration * 100)
                    if percent > 99 then percent = 99 end
                    if percent < 0 then percent = 0 end
                    progress_overlay.data = string.format("%s%s%s%sRendering %s: %d%%", theme.align(9), theme.f(true), theme.a("66"), get_queue_str(), name_no_ext, percent)
                    progress_overlay:update()
                end
            end
            f:close()
        end
    end)

    local render_start_time = mp.get_time()

    current_req = mp.command_native_async({
        name = "subprocess",
        args = launch_args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        local render_wall_time = mp.get_time() - render_start_time

        if progress_timer then progress_timer:kill() end
        if progress_overlay then progress_overlay:remove() end
        os.remove(progress_file)
        os.remove(pid_file)

        local function reset_and_advance()
            queue.is_rendering  = false
            queue.render_paused = false
            queue.active        = nil
            current_req         = nil
            queue.save()
            M.process_queue()
        end

        if active_job.cancelled then
            queue.delete_temp_file(active_job.temp_file)
            notify.show("Render cancelled: " .. active_job.final_name, true)
            reset_and_advance()
            return
        end

        local function finish_job()
            local output_info = utils.file_info(active_job.output_file)
            local output_size = output_info and output_info.size or 0

            stats.update_stats(active_job.input_size, output_size, active_job.input_duration, active_job.duration, render_wall_time)
            local msg_body, msg_osd_body, msg_width = stats.get_formatted_stats({
                source_space    = active_job.input_size,
                output_space    = output_size,
                source_duration = active_job.input_duration,
                output_duration = active_job.duration,
                render_time     = render_wall_time
            })

            local msg_title = active_job.final_name
            local pad_len   = math.max(0, msg_width - #msg_title)
            local pad       = string.rep("\\h", pad_len)
            local full_osd  = string.format("%s%s%s%s%s%s%s\\N\\N%s", theme.c("text_color"), theme.align(1), theme.f(false), theme.b(true), msg_title, pad, theme.b(false), msg_osd_body)

            if active_job.show_stats_terminal then
                notify.show("\n" .. msg_title .. "\n" .. msg_body .. "\n", false)
            end
            if active_job.show_stats_screen then
                stats_ov.data = full_osd
                stats_ov:update()
                mp.add_timeout(active_job.stats_osd_time, function() stats_ov:remove() end)
            end

            if #queue.jobs == 0 then
                queue.total_jobs = 0
                queue.current_job_num = 0
            end

            reset_and_advance()
        end

        if result and result.status == 0 then
            local renamed, rename_err = common.replace_file(active_job.temp_file, active_job.output_file)
            if not renamed then
                notify.show("Render finished but could not be moved to: " .. active_job.output_file, true, "error")
                mp.msg.error("Rename failed (" .. tostring(rename_err) .. "), rendered file kept at: " .. active_job.temp_file)
                reset_and_advance()
                return
            end

            if active_job.trash_source and active_job.trash_path then
                common.trash_file(active_job.input_file, active_job.trash_path, function(t_success)
                    if not t_success then notify.show("Failed to trash original", true, "warn") end
                    finish_job()
                end)
            else
                finish_job()
            end
        else
            queue.delete_temp_file(active_job.temp_file)
            local failed_rec     = queue.item_from_job(active_job, "failed")
            failed_rec.temp_file = nil
            failed_rec.pid_file  = nil
            table.insert(queue.failed, failed_rec)
            notify.show("Render failed: " .. active_job.final_name .. ". See console.", true, "error")
            print(result and result.stderr or error)
            reset_and_advance()
        end
    end)

    queue.save()
end

local function verify_and_queue(job, file_path, on_complete)
    if not queue.is_path_in_use(file_path) then
        queue_job(job, on_complete)
        return
    end

    ui_choice.show_exists(job.final_name, function()
        if job.rename_callback then
            job.rename_callback(function()
                local new_output = common.resolve_absolute_path(state.custom_output_name, state.opts)
                local _, fname   = utils.split_path(new_output)

                job.final_name                 = fname
                job.output_file                = new_output
                job.args[job.output_arg_index] = new_output
                job.temp_file                  = queue.temp_path_for(new_output, job.temp_id)

                verify_and_queue(job, new_output, on_complete)
            end)
        end
    end, function()
        queue_job(job, on_complete)
    end, function()
        notify.show("Render cancelled.", true)
        if on_complete then on_complete() end
    end)
end

function M.start(opts)
    local input_file = mp.get_property("path")
    if not input_file then
        notify.show("No video loaded", true, "error")
        if opts.on_complete then opts.on_complete() end
        return
    end
    if opts.mark_out <= opts.mark_in then
        notify.show("Invalid marks", true, "error")
        if opts.on_complete then opts.on_complete() end
        return
    end

    local output_file                 = opts.final_output_path
    local target_dir, target_name_ext = utils.split_path(output_file)
    local final_name                  = target_name_ext
    common.ensure_dir(target_dir)

    local resolved_in = opts.mark_in
    if opts.lossless_cut then
        local kf = common.nearest_keyframe_at_or_before(input_file, opts.mark_in)
        if kf then resolved_in = kf end
    end

    local job = queue.build_job({
        input_file          = input_file,
        output_file         = output_file,
        final_name          = final_name,
        start_time          = opts.mark_in,
        end_time            = opts.mark_out,
        input_duration      = opts.input_duration,
        video_encoder       = opts.video_encoder,
        quality             = opts.quality,
        preset              = opts.preset,
        fps_override        = opts.fps_override,
        lossless_cut        = opts.lossless_cut,
        accurate_cut        = opts.accurate_cut,
        combine_audio       = opts.combine_audio,
        combined_audio_name = opts.combined_audio_name,
        trash_source        = opts.trash_source,
        trash_path          = opts.trash_path,
        space_replacement   = opts.space_replacement,
        resolved_in         = resolved_in,
        show_stats_screen   = opts.show_stats_screen,
        show_stats_terminal = opts.show_stats_terminal,
        stats_osd_time      = opts.stats_osd_time,
        rename_callback     = opts.rename_callback
    })

    verify_and_queue(job, output_file, opts.on_complete)
end

return M
