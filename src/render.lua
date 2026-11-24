local mp         = require 'mp'
local utils      = require 'mp.utils'
local common     = require 'src.common'
local stats      = require 'src.stats'
local queue      = require 'src.queue'
local state      = require 'src.state'
local notify     = require 'src.notify'
local theme      = require 'src.theme'
local process    = require 'src.process'
local ui_choice  = require 'src.ui_choice'
local ui_confirm = require 'src.ui_confirm'
local tracks     = require 'src.tracks'
local trash      = require 'src.trash'
local lang       = require 'src.lang'

local M = {}

local current_req = nil

local platform    = common.get_platform()
local can_suspend = platform ~= "windows"

local stats_ov    = mp.create_osd_overlay("ass-events")
local stats_timer = nil

local log_dir   = utils.join_path(common.get_state_dir(), "logs")
local log_keep  = 20
local error_max = 120

local function quote(arg)
    if arg:match("^[%w%-%._/:=+,@%%]+$") then return arg end
    return "'" .. arg:gsub("'", "'\\''") .. "'"
end

local error_words = { "error", "invalid", "not supported", "not found", "could not", "cannot", "unable", "failed", "no such", "no capable" }

local function is_error(line)
    local lower = line:lower()
    for _, word in ipairs(error_words) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

local function failure_log(args, stderr)
    local command = {}
    for i, arg in ipairs(args) do command[i] = quote(tostring(arg)) end
    local lines   = { table.concat(command, " "), "" }
    local last    = nil
    local cause   = nil
    local running = false
    for line in (stderr or ""):gmatch("[^\r\n]+") do
        if not line:match("^frame=") and not line:match("^size=") and not line:match("^Conversion failed") then
            lines[#lines + 1] = line
            if line:match("%S") then last = line end
            if line:match("^Press %[q%]") then
                running = true
                cause   = nil
            elseif not cause and is_error(line) then
                cause = line
            end
        end
    end
    if not running then cause = cause or last end
    local shown = (cause or last or lang.t("render_no_error")):gsub("^%[[^%]]*%]%s*", ""):gsub("^%[[^%]]*%]%s*", "")
    if #shown > error_max then shown = shown:sub(1, error_max - 3) .. "..." end
    return lines, shown
end

local function write_log(name, lines)
    common.ensure_dir(log_dir)
    local path = utils.join_path(log_dir, os.date("%Y%m%d-%H%M%S") .. "-" .. name .. ".log")
    local f    = io.open(path, "w")
    if not f then return nil end
    f:write(table.concat(lines, "\n"), "\n")
    f:close()

    local logs = utils.readdir(log_dir, "files") or {}
    table.sort(logs)
    for i = 1, #logs - log_keep do os.remove(utils.join_path(log_dir, logs[i])) end
    return path
end

function M.cancel_render()
    mp.osd_message("", 0)

    if queue.is_rendering and queue.active and current_req then
        queue.active.cancelled = true
        mp.abort_async_command(current_req)
    else
        notify.show(lang.t("render_no_active"), true, "warn")
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
            notify.show(lang.t("queue_paused"), true)
        else
            notify.show(lang.t("queue_resumed"), true)
            M.process_queue()
        end
        return
    end

    if not can_suspend then
        queue.queue_paused = not queue.queue_paused
        if queue.queue_paused then
            notify.show(lang.t("queue_pausing"), true)
        else
            notify.show(lang.t("queue_resumed"), true)
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
            notify.show(lang.t("render_resumed", { name = queue.active.final_name }), true)
        else
            notify.show(lang.t("render_cant_resume"), true, "error")
        end
        return
    end

    local pid = read_active_pid()
    if not pid then
        notify.show(lang.t("render_starting"), true, "warn")
        return
    end

    process.signal_pid(pid, "STOP")
    queue.active.paused_pid = pid
    queue.render_paused     = true
    queue.queue_paused      = true
    queue.save()
    notify.show(lang.t("render_paused", { name = queue.active.final_name }), true)
end

local function queue_job(job, on_complete)
    table.insert(queue.jobs, job)
    queue.total_jobs = queue.total_jobs + 1
    common.save_history(state.path_history)
    if queue.is_rendering then
        notify.show(lang.t("queue_added", { name = job.final_name }), true)
    elseif queue.queue_paused then
        notify.show(lang.t("queue_added_paused", { name = job.final_name }), true)
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

    local temp_dir      = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local file_id       = tostring(queue.own_pid) .. "_" .. tostring(queue.current_job_num)
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

    local name_no_ext      = theme.escape(active_job.final_name:match("^(.*)%.[^%.]+$") or active_job.final_name)
    local progress_overlay = mp.create_osd_overlay("ass-events")

    local function get_queue_str()
        return (queue.total_jobs > 1) and string.format("[%d/%d] ", queue.current_job_num, queue.total_jobs) or ""
    end

    progress_overlay.data = string.format("%s%s%s%s%s", theme.align(9), theme.f(true), theme.a("66"), get_queue_str(), lang.t("render_progress", { name = name_no_ext, percent = 0 }))
    progress_overlay:update()

    notify.show(lang.t("render_started", { name = active_job.final_name }), true)

    local progress_timer = mp.add_periodic_timer(0.5, function()
        local f = io.open(progress_file, "rb")
        if f then
            local size = f:seek("end")
            if size and size > 0 then
                local read_size = math.min(size, 2048)
                f:seek("set", size - read_size)
                local content = f:read("*all")

                local percent = nil

                -- out_time_us is the max dts over not-yet-finished muxer
                -- streams: the stream-copied audio (source timestamps) races
                -- ahead of the encoded video (zeroed timestamps), so it spikes
                -- and then collapses once the audio finishes. frame= (muxed
                -- video packets) is monotonic and time-base-independent, but
                -- needs the output fps; out_time_us remains the fallback.
                if active_job.total_frames then
                    local frame = nil
                    for fr in content:gmatch("frame=(%d+)") do frame = fr end
                    if frame then percent = math.floor(tonumber(frame) / active_job.total_frames * 100) end
                else
                    local time_us = nil
                    for t in content:gmatch("out_time_us=(%d+)") do time_us = t end
                    if time_us then percent = math.floor((tonumber(time_us) / 1000000) / active_job.duration * 100) end
                end

                if percent then
                    if percent > 99 then percent = 99 end
                    if percent < 0 then percent = 0 end
                    progress_overlay.data = string.format("%s%s%s%s%s", theme.align(9), theme.f(true), theme.a("66"), get_queue_str(), lang.t("render_progress", { name = name_no_ext, percent = percent }))
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
            if #queue.jobs == 0 then
                queue.total_jobs      = 0
                queue.current_job_num = 0
            end
            queue.save()
            M.process_queue()
        end

        if active_job.cancelled then
            queue.delete_temp_file(active_job.temp_file)
            notify.show(lang.t("render_cancelled", { name = active_job.final_name }), true)
            reset_and_advance()
            trash.settle(active_job.input_file)
            return
        end

        local function finish_job()
            local output_info = utils.file_info(active_job.output_file)
            local output_size = output_info and output_info.size or 0

            local rendered = {
                input_file      = active_job.input_file,
                input_size      = active_job.input_size,
                input_duration  = active_job.input_duration,
                output_size     = output_size,
                output_duration = active_job.duration,
                render_time     = render_wall_time
            }
            stats.record_render(rendered)
            local msg_body, msg_osd_body, msg_width = stats.get_formatted_stats(rendered)

            local msg_title = active_job.final_name
            local pad_len   = math.max(0, msg_width - common.text_len(msg_title))
            local pad       = string.rep("\\h", pad_len)
            local full_osd  = string.format("%s%s%s%s%s%s%s\\N\\N%s", theme.c("text_color"), theme.align(1), theme.f(false), theme.b(true), theme.escape(msg_title), pad, theme.b(false), msg_osd_body)

            if active_job.show_stats_terminal then
                notify.show("\n" .. msg_title .. "\n" .. msg_body .. "\n", false)
            end
            if active_job.show_stats_screen then
                stats_ov.data = full_osd
                stats_ov:update()
                if stats_timer then stats_timer:kill() end
                stats_timer = mp.add_timeout(active_job.stats_osd_time, function() stats_ov:remove() end)
            end

            reset_and_advance()
        end

        local over_source = common.same_path(active_job.input_file, active_job.output_file)

        local function keep_temp(reason)
            notify.show(lang.t("render_move_failed", { path = active_job.output_file }), true, "error")
            mp.msg.error(reason .. ", rendered file kept at: " .. active_job.temp_file)
            reset_and_advance()
            trash.settle(active_job.input_file)
        end

        local function move_into_place(trashed)
            local renamed, rename_err = common.replace_file(active_job.temp_file, active_job.output_file)
            if not renamed then return keep_temp("Rename failed (" .. tostring(rename_err) .. ")") end

            finish_job()
            if trashed then
                local how = trash.take(active_job.output_file)
                if how or over_source then stats.record_trash(active_job.output_file, how or "after_render") end
            end
            if active_job.trash_source and not over_source then
                trash.request(active_job.input_file, active_job.trash_path, "after_render")
            end
        end

        if result and result.status == 0 then
            if active_job.trash_path and utils.file_info(active_job.output_file) then
                trash.now(active_job.output_file, active_job.trash_path, nil, function(trashed)
                    if not trashed then return keep_temp("Could not trash " .. active_job.output_file) end
                    move_into_place(true)
                end)
            else
                move_into_place(false)
            end
        else
            queue.delete_temp_file(active_job.temp_file)
            local lines, last    = failure_log(active_job.args, result and result.stderr or tostring(error))
            local failed_rec     = queue.item_from_job(active_job, "failed")
            failed_rec.temp_file = nil
            failed_rec.pid_file  = nil
            failed_rec.log       = lines
            failed_rec.log_file  = write_log(active_job.final_name, lines)
            failed_rec.error     = last
            table.insert(queue.failed, failed_rec)
            notify.show(lang.t("render_failed", { name = active_job.final_name, error = last }), true, "error")
            mp.msg.error(table.concat(lines, "\n"))
            reset_and_advance()
        end
    end)

    queue.save()
end

local function remove_failed(rec)
    for i, r in ipairs(queue.failed) do
        if r == rec then return table.remove(queue.failed, i) end
    end
end

local function overwritten(input_file)
    if not queue.overwriter(input_file) then return false end
    local _, name = utils.split_path(input_file)
    notify.show(lang.t("render_source_overwritten", { name = name }), true, "warn")
    return true
end

function M.retry(rec)
    if overwritten(rec.input_file) then return end
    local job, err = queue.job_from_item(rec)
    if not job then return notify.show(err, true, "error") end
    remove_failed(rec)
    queue_job(job)
end

function M.dismiss(rec)
    remove_failed(rec)
    trash.cancel(rec.input_file)
end

function M.confirm_losses(job, on_yes, on_no)
    local report = job.losses
    if #report.losses == 0 then return on_yes() end
    local lines = { lang.t("loss_unsupported", { container = report.container }) }
    for _, loss in ipairs(report.losses) do
        local name = lang.t(loss.key)
        if #loss.details > 0 then name = name .. " (" .. table.concat(loss.details, ", ") .. ")" end
        lines[#lines + 1] = name
    end
    if #report.supported > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = lang.t("loss_supported")
        for _, ext in ipairs(report.supported) do lines[#lines + 1] = ext end
    end
    ui_confirm.show(lang.t("render_losses_title"), job.final_name, on_yes, on_no, lines)
end

function M.show_exists(input_file, output_file, on_rename, on_overwrite, on_cancel)
    local _, name = utils.split_path(output_file)
    local title   = common.same_path(input_file, output_file) and lang.t("render_exists_source") or nil
    local lines   = state.trash_path and { lang.t("render_overwrite_trash") } or {}
    ui_choice.show_exists(name, on_rename, on_overwrite, on_cancel, title, lines)
end

local function verify_and_queue(job, file_path, on_complete)
    if not queue.is_path_in_use(file_path) then
        queue_job(job, on_complete)
        return
    end

    M.show_exists(job.input_file, file_path, function()
        if job.rename_callback then
            job.rename_callback(function()
                local new_output = common.resolve_absolute_path(state.custom_output_name, state.opts, tracks.container())
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
        if on_complete then on_complete() end
    end)
end

function M.start(opts)
    local input_file = mp.get_property("path")
    if not input_file then
        notify.show(lang.t("no_video"), true, "error")
        if opts.on_complete then opts.on_complete() end
        return
    end
    if overwritten(input_file) then
        if opts.on_complete then opts.on_complete() end
        return
    end
    local seek_in = opts.lossless_cut and common.resolve_mark_in(opts.mark_in, true, input_file) or opts.mark_in
    if opts.mark_out <= seek_in then
        local msg = lang.t("render_invalid_marks", { mark_in = common.format_time(seek_in), mark_out = common.format_time(opts.mark_out) })
        notify.show(msg, true, "warn")
        if opts.on_complete then opts.on_complete() end
        return
    end

    local output_file                 = opts.final_output_path
    local target_dir, target_name_ext = utils.split_path(output_file)
    local final_name                  = target_name_ext
    common.ensure_dir(target_dir)

    local job, err = queue.build_job({
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
        keyframe_interval   = opts.keyframe_interval,
        effects             = opts.effects,
        resolution          = opts.resolution,
        lossless_cut        = opts.lossless_cut,
        accurate_cut        = opts.accurate_cut,
        audio_encoder       = opts.audio_encoder,
        audio_bitrate       = opts.audio_bitrate,
        tracks              = opts.tracks,
        trash_source        = opts.trash_source,
        trash_path          = opts.trash_path,
        space_replacement   = opts.space_replacement,
        show_stats_screen   = opts.show_stats_screen,
        show_stats_terminal = opts.show_stats_terminal,
        stats_osd_time      = opts.stats_osd_time,
        rename_callback     = opts.rename_callback
    })
    if not job then
        notify.show(err, true, "error")
        if opts.on_complete then opts.on_complete() end
        return
    end

    M.confirm_losses(job, function()
        verify_and_queue(job, output_file, opts.on_complete)
    end, function()
        if opts.on_complete then opts.on_complete() end
    end)
end

return M
