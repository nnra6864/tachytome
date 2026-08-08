local mp        = require 'mp'
local utils     = require 'mp.utils'
local common    = require 'common'
local stats_mod = require 'stats'
local builder   = require 'ffmpeg_builder'
local osd_input = require 'osd_input'

local M = {}

local render_queue    = {}
local is_rendering    = false
local total_jobs      = 0
local current_job_num = 0

local active_job  = nil
local current_req = nil

function M.cancel_render()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    if is_rendering and active_job and current_req then
        active_job.cancelled = true
        mp.abort_async_command(current_req)
    else
        common.notify("No active render to cancel.", true, "warn")
    end
end

function M.show_queue_manager(on_close)
    local jobs = {}
    if is_rendering and active_job then
        table.insert(jobs, {title = active_job.final_name, is_active = true, original_index = 0})
    end
    for i, job in ipairs(render_queue) do
        table.insert(jobs, {title = job.final_name, is_active = false, original_index = i})
    end

    if #jobs == 0 then
        if on_close then on_close() end
        return common.notify("Render queue is empty.", true, "info")
    end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    local ov = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("qm-up")
        mp.remove_key_binding("qm-down")
        mp.remove_key_binding("qm-enter")
        mp.remove_key_binding("qm-esc")

        if on_close then on_close() end
    end

    local function draw()
        local text = "{\\an7}{\\fnmonospace}{\\fs18}{\\b1}Render Queue Manager{\\b0}\\N(Up/Down to navigate, Enter to cancel/remove, Esc to close)\\N\\N"

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#jobs, start_idx + 14)
        if end_idx - start_idx < 14 then
            start_idx = math.max(1, end_idx - 14)
        end

        if start_idx > 1 then text = text .. "  ...\\N" end

        for i = start_idx, end_idx do
            local job    = jobs[i]
            local prefix = (i == cursor) and "{\\c&H00FFFF&}➤ " or "  "
            local status = job.is_active and "{\\c&H00FF00&}[Rendering]" or "{\\c&HAAAAAA&}[Queued]"

            local line = string.format("%s%s %s", prefix, job.title, status)
            text       = text .. line .. "{\\c&HFFFFFF&}\\N"
        end

        if end_idx < #jobs then text = text .. "  ...\\N" end

        ov.data = text
        ov:update()
    end

    mp.add_forced_key_binding("UP", "qm-up", function()
        if cursor > 1 then cursor = cursor - 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("DOWN", "qm-down", function()
        if cursor < #jobs then cursor = cursor + 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("ENTER", "qm-enter", function()
        local job = jobs[cursor]
        if job.is_active then
            M.cancel_render()
        else
            table.remove(render_queue, job.original_index)
            common.notify("Removed from queue: " .. job.title, true)
        end
        cleanup()
    end)

    mp.add_forced_key_binding("ESC", "qm-esc", cleanup)

    draw()
end

function M.process_queue()
    if is_rendering or #render_queue == 0 then return end

    is_rendering    = true
    current_job_num = current_job_num + 1
    active_job      = table.remove(render_queue, 1)

    local temp_dir      = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local progress_file = utils.join_path(temp_dir, "tachytome_prog_" .. tostring(math.floor(mp.get_time() * 1000)) .. ".log")

    table.insert(active_job.args, "-progress")
    table.insert(active_job.args, progress_file)

    local name_no_ext      = active_job.final_name:match("^(.*)%.[^%.]+$") or active_job.final_name
    local progress_overlay = mp.create_osd_overlay("ass-events")

    local function get_queue_str()
        return (total_jobs > 1) and string.format("[%d/%d] ", current_job_num, total_jobs) or ""
    end

    progress_overlay.data = string.format("{\\an9}{\\fnmonospace}{\\fs16}{\\alpha&H66&}%sRendering %s: 0%%", get_queue_str(), name_no_ext)
    progress_overlay:update()

    common.notify("Render started: " .. active_job.final_name, true)

    local progress_timer = mp.add_periodic_timer(0.5, function()
        local f = io.open(progress_file, "rb")
        if f then
            local size = f:seek("end")
            local read_size = math.min(size, 2048)
            f:seek("set", size - read_size)
            local content = f:read("*all")
            f:close()

            local time_us = nil
            for t in content:gmatch("out_time_us=(%d+)") do
                time_us = t
            end

            if time_us then
                local percent = math.floor((tonumber(time_us) / 1000000) / active_job.duration * 100)
                if percent > 100 then percent = 100 end
                if percent < 0 then percent = 0 end
                progress_overlay.data = string.format("{\\an9}{\\fnmonospace}{\\fs16}{\\alpha&H66&}%sRendering %s: %d%%", get_queue_str(), name_no_ext, percent)
                progress_overlay:update()
            end
        end
    end)

    local render_start_time = mp.get_time()

    current_req = mp.command_native_async({
        name = "subprocess",
        args = active_job.args,
        playback_only = false,
    }, function(success, result, error)

        local render_wall_time = mp.get_time() - render_start_time

        if progress_timer then progress_timer:kill() end
        if progress_overlay then progress_overlay:remove() end
        os.remove(progress_file)

        if active_job.cancelled then
            local remove_success, err = os.remove(active_job.output_file)
            if not remove_success then
                mp.msg.warn("Could not delete cancelled file. It may be locked: " .. tostring(err))
            end
            common.notify("Render cancelled. File deleted: " .. active_job.final_name, true)

            is_rendering = false
            active_job   = nil
            current_req  = nil
            M.process_queue()
            return
        end

        local function finish_job()
            local out_info = utils.file_info(active_job.output_file)
            local output_size = out_info and out_info.size or 0

            local msg_console = string.format("Finished: %s\nInput: %s -> Output: %s\nStart: %s | End: %s | Quality: %s | Time: %s",
                active_job.final_name, common.format_bytes(active_job.input_size), common.format_bytes(output_size),
                common.format_time(active_job.start_time), common.format_time(active_job.end_time), active_job.quality,
                common.format_duration(render_wall_time))

            local msg_osd = msg_console:gsub("\n", "\\N")

            local current_stats = stats_mod.update_stats(
                active_job.input_size,
                output_size,
                active_job.full_input_duration,
                active_job.duration,
                render_wall_time
            )

            local stats_str_console, lifetime_str_osd = stats_mod.get_formatted_stats(current_stats)

            if active_job.show_stats_terminal then
                msg_console = msg_console .. "\n--------------------------\n"   .. stats_str_console
            end

            if active_job.show_stats_screen then
                msg_osd = msg_osd .. "\\N--------------------------\\N" .. lifetime_str_osd
            end

            mp.msg.info("\n" .. msg_console)

            mp.set_osd_ass(0, 0, "{\\an7}{\\fnmonospace}" .. msg_osd)
            mp.add_timeout(active_job.stats_osd_time, function() mp.set_osd_ass(0, 0, "") end)

            if #render_queue == 0 then
                total_jobs = 0
                current_job_num = 0
            end

            is_rendering = false
            active_job   = nil
            current_req  = nil
            M.process_queue()
        end

        if result and result.status == 0 then
            if active_job.trash_source and active_job.trash_path then
                common.trash_file(active_job.input_file, active_job.trash_path, function(t_success)
                    if not t_success then common.notify("Failed to trash original", true, "warn") end
                    finish_job()
                end)
            else
                finish_job()
            end
        else
            common.notify("Render failed: " .. active_job.final_name .. ". See console.", true, "error")
            print(result and result.stderr or error)
            is_rendering = false
            active_job   = nil
            current_req  = nil
            M.process_queue()
        end
    end)
end

local function verify_and_queue(job, file_path)
    if not utils.file_info(file_path) then
        table.insert(render_queue, job)
        total_jobs = total_jobs + 1
        if is_rendering then common.notify(string.format("Queued: %s", job.final_name), true) end
        M.process_queue()
        return
    end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("ow-1")
        mp.remove_key_binding("ow-2")
        mp.remove_key_binding("ow-3")
    end

    ov.data = string.format("{\\an7}{\\fnmonospace}{\\c&H0000FF&}Warning: File already exists!{\\c&HFFFFFF&}\\N%s\\N\\N[1] Rename\\N[2] Overwrite\\N[3] Cancel", job.final_name)
    ov:update()

    mp.add_forced_key_binding("1", "ow-1", function()
        cleanup()
        local dir, fname = utils.split_path(file_path)
        local n, e       = fname:match("^(.*)(%..+)$")
        if not n then n  = fname; e = "" end

        osd_input.get_user_input("Enter new name: ", function(input)
            if input and input ~= "" then
                local new_final = (input .. e):gsub(" ", job.space_replacement)
                job.final_name = new_final
                job.output_file = utils.join_path(dir, new_final)

                job.args[#job.args] = job.output_file
                verify_and_queue(job, job.output_file)
            else
                common.notify("Render cancelled.", true)
            end
        end, n, true)
    end)

    mp.add_forced_key_binding("2", "ow-2", function()
        cleanup()
        table.insert(render_queue, job)
        total_jobs = total_jobs + 1
        M.process_queue()
    end)

    mp.add_forced_key_binding("3", "ow-3", function()
        cleanup()
        common.notify("Render cancelled.", true)
    end)
end

function M.start(opts)
    local input_file = mp.get_property("path")
    if not input_file then return common.notify("No video loaded", true, "error") end
    if opts.mark_out <= opts.mark_in then return common.notify("Invalid marks", true, "error") end

    local output_file                 = opts.final_output_path
    local target_dir, target_name_ext = utils.split_path(output_file)
    local final_name                  = target_name_ext
    common.ensure_dir(target_dir)

    local duration = opts.mark_out - opts.mark_in

    local creation_time = common.ffprobe_get(input_file, {"-show_entries", "format_tags=creation_time", "-of", "csv=p=0"})
    if not creation_time then
        local info = utils.file_info(input_file)
        if info and info.mtime then creation_time = os.date("%Y-%m-%dT%H:%M:%S", info.mtime) end
    end

    local args = builder.build_args(opts, input_file, output_file, creation_time)

    local in_info = utils.file_info(input_file)

    local job = {
        args                = args,
        input_file          = input_file,
        output_file         = output_file,
        final_name          = final_name,
        trash_source        = opts.trash_source,
        trash_path          = opts.trash_path,
        space_replacement   = opts.space_replacement,
        combined_audio_name = opts.combined_audio_name,
        start_time          = opts.mark_in,
        end_time            = opts.mark_out,
        duration            = duration,
        full_input_duration = opts.full_input_duration or 0,
        quality             = (opts.lossless_cut and "Lossless") or tostring(opts.quality),
        show_stats_screen   = opts.show_stats_screen,
        show_stats_terminal = opts.show_stats_terminal,
        stats_osd_time      = opts.stats_osd_time,
        input_size          = in_info and in_info.size or 0
    }

    verify_and_queue(job, output_file)
end

return M
