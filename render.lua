local mp = require 'mp'
local utils = require 'mp.utils'
local common = require 'common'
local stats_mod = require 'stats'

local M = {}

local render_queue = {}
local is_rendering = false
local total_jobs = 0
local current_job_num = 0

local active_job = nil
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

function M.process_queue()
    if is_rendering or #render_queue == 0 then return end

    is_rendering = true
    current_job_num = current_job_num + 1
    active_job = table.remove(render_queue, 1)

    common.notify("Render started: " .. active_job.final_name, true)

    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local progress_file = utils.join_path(temp_dir, "tachytome_prog_" .. tostring(math.floor(mp.get_time() * 1000)) .. ".log")
    
    table.insert(active_job.args, "-progress")
    table.insert(active_job.args, progress_file)

    local name_no_ext = active_job.final_name:match("^(.*)%.[^%.]+$") or active_job.final_name
    local progress_overlay = mp.create_osd_overlay("ass-events")

    local function get_queue_str()
        return (total_jobs > 1) and string.format("[%d/%d] ", current_job_num, total_jobs) or ""
    end

    progress_overlay.data = string.format("{\\an9}{\\fs16}{\\alpha&H66&}%sRendering %s: 0%%", get_queue_str(), name_no_ext)
    progress_overlay:update()

    local progress_timer = mp.add_periodic_timer(0.5, function()
        local f = io.open(progress_file, "r")
        if f then
            local content = f:read("*all")
            f:close()
            local time_us = string.match(content, ".*out_time_us=(%d+)")
            if time_us then
                local percent = math.floor((tonumber(time_us) / 1000000) / active_job.duration * 100)
                if percent > 100 then percent = 100 end
                if percent < 0 then percent = 0 end
                progress_overlay.data = string.format("{\\an9}{\\fs16}{\\alpha&H66&}%sRendering %s: %d%%", get_queue_str(), name_no_ext, percent)
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

        -- Handle Cancellation
        if active_job.cancelled then
            os.remove(active_job.output_file)
            common.notify("Render cancelled. File deleted: " .. active_job.final_name, true)
            is_rendering = false
            active_job = nil
            current_req = nil
            M.process_queue()
            return
        end

        local function finish_job()
            local out_info = utils.file_info(active_job.output_file)
            local output_size = out_info and out_info.size or 0

            local msg_console = string.format("Finished: %s\nInput: %s -> Output: %s\nStart: %s | End: %s | CRF: %s",
                active_job.final_name, common.format_bytes(active_job.input_size), common.format_bytes(output_size),
                common.format_time(active_job.start_time), common.format_time(active_job.end_time), active_job.crf)
            
            local msg_osd = msg_console:gsub("\n", "\\N")

            if active_job.show_stats_screen then
                local current_stats = stats_mod.update_stats(
                    active_job.input_size,
                    output_size,
                    active_job.full_input_duration,
                    active_job.duration,
                    render_wall_time
                )
                local lifetime_str_console = stats_mod.get_lifetime_stats_string(current_stats)
                local lifetime_str_osd = lifetime_str_console:gsub("\n", "\\N")
                
                msg_console = msg_console .. "\n--------------------------\n" .. lifetime_str_console
                msg_osd = msg_osd .. "\\N--------------------------\\N" .. lifetime_str_osd
            end

            mp.msg.info("\n" .. msg_console) 
            
            mp.set_osd_ass(0, 0, "{\\an7}" .. msg_osd)
            mp.add_timeout(active_job.stats_osd_time, function() mp.set_osd_ass(0, 0, "") end)
            
            if #render_queue == 0 then
                total_jobs = 0
                current_job_num = 0
            end
            
            is_rendering = false
            active_job = nil
            current_req = nil
            M.process_queue()
        end

        if result and result.status == 0 then
            if active_job.trash_original and active_job.trash_path then
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
            active_job = nil
            current_req = nil
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

    local ov = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("ow-1")
        mp.remove_key_binding("ow-2")
        mp.remove_key_binding("ow-3")
    end

    ov.data = string.format("{\\an7}{\\c&H0000FF&}Warning: File already exists!{\\c&HFFFFFF&}\\N%s\\N\\N[1] Append '%s'\\N[2] Overwrite\\N[3] Cancel", job.final_name, job.overwrite_append)
    ov:update()

    mp.add_forced_key_binding("1", "ow-1", function()
        cleanup()
        local dir, fname = utils.split_path(file_path)
        local n, e = fname:match("^(.*)(%..+)$")
        if not n then n = fname; e = "" end
        
        job.final_name = n .. job.overwrite_append .. e
        job.output_file = utils.join_path(dir, job.final_name)
        
        job.args[#job.args] = job.output_file 

        verify_and_queue(job, job.output_file) 
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

    local output_file = opts.final_output_path
    local target_dir, target_name_ext = utils.split_path(output_file)
    local final_name = target_name_ext
    common.ensure_dir(target_dir)
    
    local duration = opts.mark_out - opts.mark_in

    local creation_time = common.ffprobe_get(input_file, {"-show_entries", "format_tags=creation_time", "-of", "csv=p=0"})
    if not creation_time then
        local info = utils.file_info(input_file)
        if info and info.mtime then creation_time = os.date("%Y-%m-%dT%H:%M:%S", info.mtime) end
    end

    local args = { "ffmpeg", "-y", "-hide_banner" }

    if opts.accurate_cut then
        table.insert(args, "-i") table.insert(args, input_file)
        table.insert(args, "-ss") table.insert(args, tostring(opts.mark_in))
        table.insert(args, "-to") table.insert(args, tostring(opts.mark_out))
    else
        table.insert(args, "-ss") table.insert(args, tostring(opts.mark_in))
        table.insert(args, "-i") table.insert(args, input_file)
        table.insert(args, "-t") table.insert(args, tostring(duration))
    end

    if opts.lossless_cut then
        local codec_args = {
            "-c:v", "copy",
            "-map_metadata", "0",
            "-metadata", "ENCODED_BY=tachytome",
            "-metadata", "TACHYTOME_MODE=Lossless"
        }
        for _, v in ipairs(codec_args) do table.insert(args, v) end

        if creation_time then
            table.insert(args, "-metadata")
            table.insert(args, "creation_time=" .. creation_time)
        end
        
        table.insert(args, "-map") table.insert(args, "0")
        table.insert(args, "-c:a") table.insert(args, "copy")
    else
        local codec_args = {
            "-c:v", "libsvtav1",
            "-preset", tostring(opts.preset),
            "-crf", tostring(opts.crf),
            "-pix_fmt", "yuv420p10le",
            "-svtav1-params", "tune=0:scd=1",
            "-map_metadata", "0",
            "-metadata", "ENCODED_BY=tachytome",
            "-metadata", "TACHYTOME_CRF=" .. tostring(opts.crf),
            "-metadata", "TACHYTOME_PRESET=" .. tostring(opts.preset)
        }
        for _, v in ipairs(codec_args) do table.insert(args, v) end

        if creation_time then
            table.insert(args, "-metadata")
            table.insert(args, "creation_time=" .. creation_time)
        end

        if opts.combine_audio then
            local audio_streams_str = common.ffprobe_get(input_file, {"-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0"})
            local audio_stream_count = 0
            if audio_streams_str then
                _, audio_stream_count = audio_streams_str:gsub("[^\n]+", "")
            end

            if audio_stream_count > 1 then
                local orig_codec = common.ffprobe_get(input_file, {"-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0"})
                local orig_sr = common.ffprobe_get(input_file, {"-select_streams", "a:0", "-show_entries", "stream=sample_rate", "-of", "csv=p=0"})
                local orig_br = common.ffprobe_get(input_file, {"-select_streams", "a:0", "-show_entries", "stream=bit_rate", "-of", "csv=p=0"})

                local encoder = orig_codec
                if orig_codec == "opus" then encoder = "libopus"
                elseif orig_codec == "mp3" then encoder = "libmp3lame"
                elseif orig_codec == "vorbis" then encoder = "libvorbis" end

                local filter_inputs = ""
                for i = 0, audio_stream_count - 1 do filter_inputs = filter_inputs .. string.format("[0:a:%d]", i) end
                local filter_complex = string.format("%samix=inputs=%d:normalize=0[aout]", filter_inputs, audio_stream_count)

                table.insert(args, "-filter_complex") table.insert(args, filter_complex)
                table.insert(args, "-map") table.insert(args, "[aout]")
                table.insert(args, "-map") table.insert(args, "0")

                table.insert(args, "-c:a:0") table.insert(args, encoder)
                if orig_sr and orig_sr ~= "N/A" then table.insert(args, "-ar:0") table.insert(args, orig_sr) end
                if orig_br and orig_br ~= "N/A" then table.insert(args, "-b:a:0") table.insert(args, orig_br) end

                for i = 1, audio_stream_count do
                    table.insert(args, string.format("-c:a:%d", i))
                    table.insert(args, "copy")
                end

                table.insert(args, "-disposition:a:0") table.insert(args, "default")
                table.insert(args, "-metadata:s:a:0") table.insert(args, "TITLE=Combined")
            else
                table.insert(args, "-map") table.insert(args, "0")
                table.insert(args, "-c:a") table.insert(args, "copy")
            end
        else
            table.insert(args, "-map") table.insert(args, "0")
            table.insert(args, "-c:a") table.insert(args, "copy")
        end
    end

    table.insert(args, output_file)
    
    local in_info = utils.file_info(input_file)

    local job = {
        args = args,
        input_file = input_file,
        output_file = output_file,
        final_name = final_name,
        trash_original = opts.trash_original,
        trash_path = opts.trash_path,
        overwrite_append = opts.overwrite_append,
        start_time = opts.mark_in,
        end_time = opts.mark_out,
        duration = duration,
        full_input_duration = opts.full_input_duration or 0,
        crf = (opts.lossless_cut and "Lossless") or tostring(opts.crf),
        show_stats_screen = opts.show_stats_screen,
        stats_osd_time = opts.stats_osd_time,
        input_size = in_info and in_info.size or 0
    }

    verify_and_queue(job, output_file)
end

return M
