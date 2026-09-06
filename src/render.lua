local mp       = require 'mp'
local utils    = require 'mp.utils'
local common   = require 'src.common'
local stats    = require 'src.stats'
local builder  = require 'src.ffmpeg'
local state    = require 'src.state'
local notify   = require 'src.notify'
local theme    = require 'src.theme'
local ui_input = require 'src.ui_input'

local M = {}

local render_queue    = {}
local is_rendering    = false
local total_jobs      = 0
local current_job_num = 0

local active_job  = nil
local current_req = nil

local render_paused = false
local queue_paused  = false

local platform    = common.get_platform()
local can_suspend = platform ~= "windows"

local failed_items = {}

local own_pid           = utils.getpid()
local data_dir          = common.get_data_dir()
local queue_path        = utils.join_path(data_dir, "queue-" .. tostring(own_pid) .. ".json")
local queue_tmp         = queue_path .. ".tmp"
local legacy_queue_path = utils.join_path(data_dir, "queue.json")

local has_saved = false

local stats_ov = mp.create_osd_overlay("ass-events")

local TEMP_PREFIX = ".tachytome_tmp_"

local temp_seq  = 0
local temp_seed = tostring(os.time()) .. "-" .. tostring(math.floor(mp.get_time() * 1000))

local orphan_checked_dirs = {}

local function next_temp_id()
    temp_seq = temp_seq + 1
    return temp_seed .. "-" .. tostring(temp_seq)
end

local function temp_path_for(output_file, temp_id)
    local dir, _ = utils.split_path(output_file)
    local ext    = output_file:match("(%.[a-zA-Z0-9]+)$") or ".mkv"
    return utils.join_path(dir, TEMP_PREFIX .. temp_id .. ext)
end

local function temp_base_name(path)
    local _, base = utils.split_path(path)
    return base
end

local function delete_temp_file(path)
    if not path or not utils.file_info(path) then return end
    local ok, err = os.remove(path)
    if not ok then mp.msg.warn("Could not delete temp render file: " .. tostring(err)) end
end

local function rename_temp_to_final(temp_file, final_file)
    local ok, err = os.rename(temp_file, final_file)
    if not ok then
        os.remove(final_file)
        ok, err = os.rename(temp_file, final_file)
    end
    if not ok then return false, err end
    return true
end

local function is_live_temp_name(name)
    if active_job and active_job.temp_file and name == temp_base_name(active_job.temp_file) then return true end
    for _, q_job in ipairs(render_queue) do
        if q_job.temp_file and name == temp_base_name(q_job.temp_file) then return true end
    end
    for _, rec in ipairs(failed_items) do
        if rec.temp_file and name == temp_base_name(rec.temp_file) then return true end
    end
    return false
end

local function scan_queue_files()
    local files = {}
    local entries = utils.readdir(data_dir)
    if entries then
        for _, name in ipairs(entries) do
            if name:match("^queue%-%d+%.json$") then
                table.insert(files, utils.join_path(data_dir, name))
            end
        end
    end
    if utils.file_info(legacy_queue_path) then
        table.insert(files, legacy_queue_path)
    end
    table.sort(files)
    return files
end

local function read_queue_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return utils.parse_json(content)
end

local function all_queue_referenced_temps()
    local set = {}
    for _, path in ipairs(scan_queue_files()) do
        local parsed = read_queue_file(path)
        if type(parsed) == "table" and type(parsed.items) == "table" then
            for _, it in ipairs(parsed.items) do
                if type(it) == "table" and type(it.temp_file) == "string" then
                    set[temp_base_name(it.temp_file)] = true
                end
            end
        end
    end
    return set
end

local dismissed_temps      = {}
local pending_temp_prompts = {}
local temp_prompt_scheduled = false

local function show_temp_orphan_dialog(entry, on_done)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    state.ui_owner = "dialog"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup_pending()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        mp.remove_key_binding("tmp-1")
        mp.remove_key_binding("tmp-2")
        mp.remove_key_binding("tmp-esc")
    end

    local function keep()
        cleanup_pending()
        for _, name in ipairs(entry.files) do dismissed_temps[name] = true end
        notify.show("Kept leftover temp render file(s).", true)
        if on_done then on_done() end
    end

    local shown = {}
    for i = 1, math.min(#entry.files, 3) do table.insert(shown, entry.files[i]) end
    local extra = (#entry.files > 3) and string.format(" +%d more", #entry.files - 3) or ""

    ov.data = string.format("%s%s%sInterrupted Render Leftovers%s\\N%s%s\\N%s%s\\N\\N[1] Delete\\N[2] Keep",
        theme.align(7), theme.f(), theme.c("warning_color"), theme.reset(),
        theme.f(true), entry.dir, table.concat(shown, "\\N"), extra)
    ov:update()

    mp.add_forced_key_binding("1", "tmp-1", function()
        cleanup_pending()
        for _, name in ipairs(entry.files) do
            delete_temp_file(utils.join_path(entry.dir, name))
        end
        notify.show("Deleted leftover temp render file(s).", true)
        if on_done then on_done() end
    end)
    mp.add_forced_key_binding("2", "tmp-2", keep)
    mp.add_forced_key_binding("ESC", "tmp-esc", keep)
end

local pump_temp_prompts

local function queue_temp_prompt(dir, files)
    table.insert(pending_temp_prompts, {dir = dir, files = files})
    if not temp_prompt_scheduled then
        temp_prompt_scheduled = true
        mp.add_timeout(0.7, pump_temp_prompts)
    end
end

pump_temp_prompts = function()
    temp_prompt_scheduled = false

    if state.ui_owner then
        temp_prompt_scheduled = true
        mp.add_timeout(0.3, pump_temp_prompts)
        return
    end

    local entry = table.remove(pending_temp_prompts, 1)
    if not entry then return end

    show_temp_orphan_dialog(entry, function()
        if not temp_prompt_scheduled then
            temp_prompt_scheduled = true
            mp.add_timeout(0.1, pump_temp_prompts)
        end
    end)
end

function M.check_orphan_temp_files(dir)
    if not dir or dir == "" or orphan_checked_dirs[dir] then return end
    orphan_checked_dirs[dir] = true

    local entries = utils.readdir(dir)
    if not entries then return end

    local referenced = all_queue_referenced_temps()

    local orphans = {}
    for _, name in ipairs(entries) do
        if name:sub(1, #TEMP_PREFIX) == TEMP_PREFIX
            and not is_live_temp_name(name)
            and not referenced[name]
            and not dismissed_temps[name] then
            table.insert(orphans, name)
        end
    end

    if #orphans == 0 then return end

    mp.msg.warn(string.format("Found %d leftover temp render file(s) in %s with no render queue.",
        #orphans, dir))
    queue_temp_prompt(dir, orphans)
end

function M.cancel_render()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    if is_rendering and active_job and current_req then
        active_job.cancelled = true
        mp.abort_async_command(current_req)
    else
        notify.show("No active render to cancel.", true, "warn")
    end
end

local function signal_pid(pid, sig)
    mp.command_native_async({
        name           = "subprocess",
        args           = {"kill", "-" .. sig, tostring(pid)},
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    })
end

local function process_comm(pid)
    if not pid then return nil end
    if platform == "linux" then
        local f = io.open(string.format("/proc/%d/comm", pid), "r")
        if not f then return nil end
        local comm = f:read("*l")
        f:close()
        return comm
    elseif platform == "macos" then
        local res = utils.subprocess({args = {"ps", "-p", tostring(pid), "-o", "comm="}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" then
            return res.stdout:gsub("[\r\n]+$", "")
        end
    elseif platform == "windows" then
        local res = utils.subprocess({args = {"tasklist", "/FI", "PID eq " .. tostring(pid), "/FO", "CSV", "/NH"}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" and not res.stdout:find("INFO:") then
            return res.stdout:match("^\"([^\"]+)\"")
        end
    end
    return nil
end

local function mpv_alive(pid)
    local comm = process_comm(pid)
    return comm ~= nil and comm:lower():find("mpv", 1, true) ~= nil
end

local function process_args(pid)
    if not pid then return nil end
    if platform == "linux" then
        local f = io.open(string.format("/proc/%d/cmdline", pid), "r")
        if not f then return nil end
        local data = f:read("*all")
        f:close()
        if not data or data == "" then return nil end
        return data
    end
    if platform == "macos" then
        local res = utils.subprocess({args = {"ps", "-p", tostring(pid), "-o", "command="}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" then
            return res.stdout:gsub("[\r\n]+$", "")
        end
    end
    return nil
end

local function kill_orphan_ffmpeg(item)
    if not can_suspend or type(item.pid_file) ~= "string" then return end

    local f = io.open(item.pid_file, "r")
    if not f then return end
    local pid = tonumber(f:read("*l"))
    f:close()
    os.remove(item.pid_file)

    if not pid then return end
    local comm = process_comm(pid)
    if not (comm and comm:find("ffmpeg", 1, true)) then return end

    local args = process_args(pid)
    if not (args and item.temp_file and args:find(item.temp_file, 1, true)) then
        mp.msg.warn("Not killing pid " .. tostring(pid) .. ": it is ffmpeg but not this render's process.")
        return
    end

    signal_pid(pid, "KILL")
    mp.msg.warn("Killed orphaned ffmpeg from crashed render: " .. tostring(item.final_name))
end

local function item_from_job(job, status)
    return {
        status              = status,
        input_file          = job.input_file,
        output_file         = job.output_file,
        temp_file           = job.temp_file,
        final_name          = job.final_name,
        mark_in             = job.start_time,
        mark_out            = job.end_time,
        resolved_in         = job.resolved_in,
        video_encoder       = job.video_encoder,
        quality             = job.quality,
        preset              = job.preset,
        fps_override        = job.fps_override,
        lossless_cut        = job.lossless_cut,
        accurate_cut        = job.accurate_cut,
        combine_audio       = job.combine_audio,
        combined_audio_name = job.combined_audio_name,
        trash_source        = job.trash_source,
        trash_path          = job.trash_path,
        space_replacement   = job.space_replacement,
        input_duration      = job.input_duration,
        input_size          = job.input_size,
        show_stats_screen   = job.show_stats_screen,
        show_stats_terminal = job.show_stats_terminal,
        stats_osd_time      = job.stats_osd_time,
        pid_file            = job.pid_file
    }
end

local function save_queue()
    has_saved = true
    local items = {}
    if is_rendering and active_job then
        table.insert(items, item_from_job(active_job, render_paused and "paused" or "active"))
    end
    for _, q_job in ipairs(render_queue) do
        table.insert(items, item_from_job(q_job, "queued"))
    end
    for _, rec in ipairs(failed_items) do
        table.insert(items, rec)
    end

    local f = io.open(queue_tmp, "w")
    if not f then return end
    f:write(utils.format_json({ owner_pid = utils.getpid(), items = items }))
    f:close()

    local ok = os.rename(queue_tmp, queue_path)
    if not ok then
        os.remove(queue_path)
        os.rename(queue_tmp, queue_path)
    end
end

local function read_active_pid()
    if not active_job or not active_job.pid_file then return nil end
    local f = io.open(active_job.pid_file, "r")
    if not f then return nil end
    local pid = tonumber(f:read("*l"))
    f:close()
    return pid
end

function M.is_paused()
    return render_paused or queue_paused
end

function M.toggle_pause()
    if not is_rendering or not active_job then
        queue_paused = not queue_paused
        if queue_paused then
            notify.show("Render queue paused.", true)
        else
            notify.show("Render queue resumed.", true)
            M.process_queue()
        end
        return
    end

    if not can_suspend then
        queue_paused = not queue_paused
        if queue_paused then
            notify.show("Pausing render queue: finishing current file, then holding.", true)
        else
            notify.show("Render queue resumed.", true)
            M.process_queue()
        end
        return
    end

    if render_paused then
        if active_job.paused_pid then
            signal_pid(active_job.paused_pid, "CONT")
            render_paused = false
            queue_paused  = false
            save_queue()
            notify.show("Render resumed: " .. active_job.final_name, true)
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

    signal_pid(pid, "STOP")
    active_job.paused_pid = pid
    render_paused         = true
    queue_paused          = true
    save_queue()
    notify.show("Render paused: " .. active_job.final_name, true)
end

local function is_path_in_use(file_path)
    if utils.file_info(file_path) then return true end
    if is_rendering and active_job and active_job.output_file == file_path then return true end
    for _, q_job in ipairs(render_queue) do
        if q_job.output_file == file_path then return true end
    end
    return false
end

local function queue_job(job, on_complete)
    table.insert(render_queue, job)
    total_jobs = total_jobs + 1
    common.save_history(state.path_history)
    if is_rendering then
        notify.show(string.format("Queued: %s", job.final_name), true)
    elseif queue_paused then
        notify.show(string.format("Queued: %s (queue paused)", job.final_name), true)
    end
    M.process_queue()
    save_queue()
    if on_complete then on_complete() end
end

local function show_exists_dialog(display_name, on_rename, on_overwrite, on_cancel)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    state.ui_owner = "dialog"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        mp.remove_key_binding("ow-1")
        mp.remove_key_binding("ow-2")
        mp.remove_key_binding("ow-3")
    end

    ov.data = string.format("%s%s%sWarning: File already exists!%s\\N%s\\N\\N[1] Rename\\N[2] Overwrite\\N[3] Cancel",
        theme.align(7), theme.f(), theme.c("warning_color"), theme.reset(), display_name)
    ov:update()

    mp.add_forced_key_binding("1", "ow-1", function()
        cleanup()
        if on_rename then on_rename() end
    end)
    mp.add_forced_key_binding("2", "ow-2", function()
        cleanup()
        if on_overwrite then on_overwrite() end
    end)
    mp.add_forced_key_binding("3", "ow-3", function()
        cleanup()
        if on_cancel then on_cancel() end
    end)
end

function M.show_queue_manager(on_close)
    local function rebuild_jobs()
        local new_jobs = {}
        if is_rendering and active_job then
            local active_title = active_job.final_name
            if render_paused then active_title = active_title .. " (Paused)" end
            table.insert(new_jobs, {title = active_title, is_active = true, original_index = 0})
        end
        for i, q_job in ipairs(render_queue) do
            table.insert(new_jobs, {title = q_job.final_name, is_active = false, original_index = i})
        end
        return new_jobs
    end

    local ov            = mp.create_osd_overlay("ass-events")
    local active        = false
    local cursor        = 1
    local refresh_timer = nil
    local jobs          = {}

    local function remove_bindings()
        mp.remove_key_binding("qm-up")
        mp.remove_key_binding("qm-down")
        mp.remove_key_binding("qm-cj")
        mp.remove_key_binding("qm-ck")
        mp.remove_key_binding("qm-enter")
        mp.remove_key_binding("qm-del")
        mp.remove_key_binding("qm-d")
        mp.remove_key_binding("qm-rename")
        mp.remove_key_binding("qm-esc")
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        if refresh_timer then refresh_timer:kill(); refresh_timer = nil end
        ov:remove()
        remove_bindings()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function draw()
        local text = string.format("%s%s%sRender Queue Manager%s\\N%s(Up/Down to navigate, Enter to pause/resume, Del to delete, r to rename, Esc to close)\\N\\N",
            theme.align(7), theme.f(), theme.b(true), theme.b(false), theme.f(true))

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#jobs, start_idx + 14)
        if end_idx - start_idx < 14 then start_idx = math.max(1, end_idx - 14) end

        if start_idx > 1 then text = text .. "\\h\\h...\\N" end

        for i = start_idx, end_idx do
            local job    = jobs[i]
            local prefix = (i == cursor) and string.format("%s\\h> ", theme.c("value_color")) or "\\h\\h"
            local status = job.is_active and string.format("%s" .. state.opts.on_text, theme.c("on_color")) or ""

            text = text .. string.format("%s%s%s %s%s\\N", theme.c("text_color"), prefix, job.title, status, theme.reset())
        end

        if end_idx < #jobs then text = text .. "\\h\\h...\\N" end

        ov.data = text
        ov:update()
    end

    local function refresh()
        if not active then return end
        local new_jobs = rebuild_jobs()
        local changed = false

        if #new_jobs ~= #jobs then
            changed = true
        else
            for i = 1, #jobs do
                if jobs[i].title ~= new_jobs[i].title or jobs[i].is_active ~= new_jobs[i].is_active then
                    changed = true; break
                end
            end
        end

        if changed then
            jobs = new_jobs
            if #jobs == 0 then
                cleanup()
            else
                if cursor > #jobs then cursor = #jobs end
                draw()
            end
        end
    end

    local open_ui

    local function rename_selected()
        local sel = jobs[cursor]
        if not sel then return end

        local q_job = sel.is_active and active_job or render_queue[sel.original_index]
        if not q_job or not q_job.output_file then return end

        local current_output = q_job.output_file

        teardown()

        local function apply_rename(input, new_output)
            local target_dir, fname = utils.split_path(new_output)
            common.ensure_dir(target_dir)

            q_job.output_file = new_output
            q_job.final_name  = fname

            if active_job == q_job then
                notify.show("Active render target: " .. fname, true)
            else
                q_job.args[q_job.output_arg_index] = new_output
                q_job.temp_file                    = temp_path_for(new_output, q_job.temp_id)
                notify.show("Renamed to: " .. fname, true)
            end

            common.add_to_history(state.path_history, input)
            common.save_history(state.path_history)
            save_queue()
        end

        local function prompt_rename()
            ui_input.get_user_input("New Output Path > ", function(input)
                if input == "" then
                    notify.show("Rename cancelled.", true)
                    open_ui()
                    return
                end

                local new_output = common.resolve_absolute_path_for(input, state.opts, q_job.input_file)
                if new_output == "" or new_output == current_output then
                    notify.show("Path unchanged, keeping: " .. q_job.final_name, true)
                    open_ui()
                    return
                end

                if not is_path_in_use(new_output) then
                    apply_rename(input, new_output)
                    open_ui()
                    return
                end

                local _, new_name = utils.split_path(new_output)
                show_exists_dialog(new_name, function()
                    prompt_rename()
                end, function()
                    apply_rename(input, new_output)
                    open_ui()
                end, function()
                    notify.show("Rename cancelled.", true)
                    open_ui()
                end)
            end, current_output, "(Up/Down for history, Enter to confirm, Esc to cancel)", state.path_history, function()
                open_ui()
            end)
        end

        prompt_rename()
    end

    local function bind()
        local function move_up()
            if cursor > 1 then cursor = cursor - 1; draw() end
        end

        local function move_down()
            if cursor < #jobs then cursor = cursor + 1; draw() end
        end

        mp.add_forced_key_binding("UP", "qm-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "qm-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("ctrl+j", "qm-cj", move_down, {repeatable = true})
        mp.add_forced_key_binding("ctrl+k", "qm-ck", move_up, {repeatable = true})

        mp.add_forced_key_binding("ENTER", "qm-enter", function()
            M.toggle_pause()

            jobs = rebuild_jobs()
            if #jobs == 0 then
                cleanup()
            else
                draw()
            end
        end)

        local function delete_selected()
            local job = jobs[cursor]
            if not job then return end

            if job.is_active then
                M.cancel_render()
            else
                table.remove(render_queue, job.original_index)
                total_jobs = total_jobs > 0 and (total_jobs - 1) or 0
                notify.show("Removed from queue: " .. job.title, true)
                save_queue()
            end

            jobs = rebuild_jobs()
            if #jobs == 0 then
                cleanup()
            else
                if cursor > #jobs then cursor = #jobs end
                draw()
            end
        end

        mp.add_forced_key_binding("DEL", "qm-del", delete_selected)
        mp.add_forced_key_binding("d", "qm-d", delete_selected)

        mp.add_forced_key_binding("r", "qm-rename", rename_selected)

        mp.add_forced_key_binding("ESC", "qm-esc", cleanup)
    end

    open_ui = function()
        jobs = rebuild_jobs()
        if #jobs == 0 then
            if on_close then on_close() end
            return notify.show("Render queue is empty.", true, "info")
        end
        if cursor > #jobs then cursor = #jobs end

        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)

        active          = true
        state.ui_owner  = "queue"
        refresh_timer   = mp.add_periodic_timer(0.2, refresh)
        bind()
        draw()
    end

    open_ui()
end

function M.process_queue()
    if is_rendering or queue_paused or #render_queue == 0 then return end

    is_rendering    = true
    render_paused   = false
    current_job_num = current_job_num + 1
    active_job      = table.remove(render_queue, 1)

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
        return (total_jobs > 1) and string.format("[%d/%d] ", current_job_num, total_jobs) or ""
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
            is_rendering  = false
            render_paused = false
            active_job    = nil
            current_req   = nil
            save_queue()
            M.process_queue()
        end

        if active_job.cancelled then
            delete_temp_file(active_job.temp_file)
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

            if #render_queue == 0 then
                total_jobs = 0
                current_job_num = 0
            end

            reset_and_advance()
        end

        if result and result.status == 0 then
            local renamed, rename_err = rename_temp_to_final(active_job.temp_file, active_job.output_file)
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
            delete_temp_file(active_job.temp_file)
            local failed_rec     = item_from_job(active_job, "failed")
            failed_rec.temp_file = nil
            failed_rec.pid_file  = nil
            table.insert(failed_items, failed_rec)
            notify.show("Render failed: " .. active_job.final_name .. ". See console.", true, "error")
            print(result and result.stderr or error)
            reset_and_advance()
        end
    end)

    save_queue()
end

local function verify_and_queue(job, file_path, on_complete)
    if not is_path_in_use(file_path) then
        queue_job(job, on_complete)
        return
    end

    show_exists_dialog(job.final_name, function()
        if job.rename_callback then
            job.rename_callback(function()
                local new_output = common.resolve_absolute_path(state.custom_output_name, state.opts)
                local _, fname   = utils.split_path(new_output)

                job.final_name                 = fname
                job.output_file                = new_output
                job.args[job.output_arg_index] = new_output
                job.temp_file                  = temp_path_for(new_output, job.temp_id)

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

    local duration = opts.mark_out - opts.mark_in
    local creation_time = common.ffprobe_get(input_file, {"-show_entries", "format_tags=creation_time", "-of", "csv=p=0"})
    if not creation_time then
        local info = utils.file_info(input_file)
        if info and info.mtime then creation_time = os.date("%Y-%m-%dT%H:%M:%S", info.mtime) end
    end

    local args = builder.build_args(opts, input_file, output_file, creation_time)
    local in_info = utils.file_info(input_file)
    local temp_id = next_temp_id()

    local resolved_in = opts.mark_in
    if opts.lossless_cut then
        local kf = common.nearest_keyframe_at_or_before(input_file, opts.mark_in)
        if kf then resolved_in = kf end
    end

    local job = {
        args                = args,
        output_arg_index    = #args,
        input_file          = input_file,
        output_file         = output_file,
        temp_id             = temp_id,
        temp_file           = temp_path_for(output_file, temp_id),
        final_name          = final_name,
        trash_source        = opts.trash_source,
        trash_path          = opts.trash_path,
        space_replacement   = opts.space_replacement,
        combined_audio_name = opts.combined_audio_name,
        start_time          = opts.mark_in,
        end_time            = opts.mark_out,
        duration            = duration,
        input_duration      = opts.input_duration or 0,
        quality             = opts.quality,
        video_encoder       = opts.video_encoder,
        preset              = opts.preset,
        fps_override        = opts.fps_override,
        lossless_cut        = opts.lossless_cut,
        accurate_cut        = opts.accurate_cut,
        combine_audio       = opts.combine_audio,
        resolved_in         = resolved_in,
        show_stats_screen   = opts.show_stats_screen,
        show_stats_terminal = opts.show_stats_terminal,
        stats_osd_time      = opts.stats_osd_time,
        input_size          = in_info and in_info.size or 0,
        rename_callback     = opts.rename_callback
    }

    verify_and_queue(job, output_file, opts.on_complete)
end

local function collect_orphan_queues()
    local orphans = {}
    for _, path in ipairs(scan_queue_files()) do
        local parsed = read_queue_file(path)
        if type(parsed) ~= "table" then
            mp.msg.warn("Removing unreadable render queue file: " .. path)
            os.remove(path)
        else
            local items = {}
            if type(parsed.items) == "table" then
                for _, it in ipairs(parsed.items) do
                    if type(it) == "table" and it.status ~= "done" and type(it.input_file) == "string" and type(it.output_file) == "string" then
                        table.insert(items, it)
                    end
                end
            end

            if #items == 0 then
                os.remove(path)
            else
                local owner = tonumber(parsed.owner_pid)
                if owner == own_pid and not has_saved then
                    table.insert(orphans, {path = path, owner_pid = owner, items = items})
                elseif owner and mpv_alive(owner) then
                    mp.msg.info("Render queue is owned by a running mpv instance (pid " .. owner .. "), skipping recovery.")
                else
                    table.insert(orphans, {path = path, owner_pid = owner, items = items})
                end
            end
        end
    end
    return orphans
end

local function show_recover_dialog(file, on_recover, on_discard, on_ignore)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    state.ui_owner = "dialog"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        mp.remove_key_binding("rec-1")
        mp.remove_key_binding("rec-2")
        mp.remove_key_binding("rec-3")
        mp.remove_key_binding("rec-esc")
    end

    local owner_str = file.owner_pid and string.format("From a closed/crashed mpv (pid %d)", file.owner_pid) or "From a closed/crashed mpv"
    local names     = {}
    for i, it in ipairs(file.items) do
        if i > 3 then
            table.insert(names, string.format("+%d more", #file.items - 3))
            break
        end
        table.insert(names, string.format("%s [%s]", tostring(it.final_name), tostring(it.status)))
    end

    ov.data = string.format("%s%s%sInterrupted Renders Found%s\\N%s%s\\N%s\\N\\N[1] Recover\\N[2] Discard\\N[3] Ignore",
        theme.align(7), theme.f(), theme.c("warning_color"), theme.reset(),
        theme.f(true), owner_str, table.concat(names, "\\N"))
    ov:update()

    mp.add_forced_key_binding("1", "rec-1", function()
        cleanup()
        if on_recover then on_recover() end
    end)
    mp.add_forced_key_binding("2", "rec-2", function()
        cleanup()
        if on_discard then on_discard() end
    end)
    mp.add_forced_key_binding("3", "rec-3", function()
        cleanup()
        if on_ignore then on_ignore() end
    end)
    mp.add_forced_key_binding("ESC", "rec-esc", function()
        cleanup()
        if on_ignore then on_ignore() end
    end)
end

local function item_to_job(it)
    local creation_time = common.ffprobe_get(it.input_file, {"-show_entries", "format_tags=creation_time", "-of", "csv=p=0"})
    if not creation_time then
        local info = utils.file_info(it.input_file)
        if info and info.mtime then creation_time = os.date("%Y-%m-%dT%H:%M:%S", info.mtime) end
    end

    local build_opts = {
        mark_in             = it.mark_in,
        mark_out            = it.mark_out,
        video_encoder       = it.video_encoder or state.opts.video_encoder,
        quality             = it.quality,
        preset              = it.preset,
        fps_override        = it.fps_override,
        accurate_cut        = it.accurate_cut,
        lossless_cut        = it.lossless_cut,
        combine_audio       = it.combine_audio,
        combined_audio_name = it.combined_audio_name
    }
    local args    = builder.build_args(build_opts, it.input_file, it.output_file, creation_time)
    local in_info = utils.file_info(it.input_file)
    local temp_id = next_temp_id()

    return {
        args                = args,
        output_arg_index    = #args,
        input_file          = it.input_file,
        output_file         = it.output_file,
        temp_id             = temp_id,
        temp_file           = temp_path_for(it.output_file, temp_id),
        final_name          = it.final_name,
        trash_source        = it.trash_source,
        trash_path          = it.trash_path,
        space_replacement   = it.space_replacement,
        combined_audio_name = it.combined_audio_name,
        start_time          = it.mark_in,
        end_time            = it.mark_out,
        duration            = (tonumber(it.mark_out) or 0) - (tonumber(it.mark_in) or 0),
        input_duration      = it.input_duration or 0,
        quality             = it.quality,
        video_encoder       = it.video_encoder,
        preset              = it.preset,
        fps_override        = it.fps_override,
        lossless_cut        = it.lossless_cut,
        accurate_cut        = it.accurate_cut,
        combine_audio       = it.combine_audio,
        resolved_in         = it.resolved_in,
        show_stats_screen   = it.show_stats_screen,
        show_stats_terminal = it.show_stats_terminal,
        stats_osd_time      = it.stats_osd_time,
        input_size          = (in_info and in_info.size) or it.input_size or 0
    }
end

local function adopt_orphan_queue(file)
    local adopted = 0
    for _, it in ipairs(file.items) do
        if it.status == "active" or it.status == "paused" then
            kill_orphan_ffmpeg(it)
        end
        delete_temp_file(it.temp_file)

        if not utils.file_info(it.input_file) then
            notify.show("Skipped recovered render (source missing): " .. tostring(it.final_name), true, "warn")
        elseif (tonumber(it.mark_out) or 0) <= (tonumber(it.mark_in) or 0) then
            notify.show("Skipped recovered render (invalid marks): " .. tostring(it.final_name), true, "warn")
        else
            table.insert(render_queue, item_to_job(it))
            adopted = adopted + 1
        end
    end
    os.remove(file.path)

    if adopted > 0 then
        total_jobs  = total_jobs + adopted
        queue_paused = true
        notify.show("Render queue recovered and paused.", true)
    end
    save_queue()
end

local function discard_orphan_queue(file)
    for _, it in ipairs(file.items) do
        if it.status == "active" or it.status == "paused" then
            kill_orphan_ffmpeg(it)
        end
        delete_temp_file(it.temp_file)
    end
    os.remove(file.path)
end

local prompt_orphan_queues

local function startup_recovery()
    prompt_orphan_queues(collect_orphan_queues(), 1)
end

prompt_orphan_queues = function(orphans, idx)
    if idx > #orphans then return end

    local file = orphans[idx]
    mp.msg.info(string.format("Found interrupted render queue%s: %d item(s)",
        file.owner_pid and (" from mpv pid " .. tostring(file.owner_pid)) or "", #file.items))

    show_recover_dialog(file, function()
        adopt_orphan_queue(file)
        prompt_orphan_queues(orphans, idx + 1)
    end, function()
        discard_orphan_queue(file)
        prompt_orphan_queues(orphans, idx + 1)
    end, function()
        prompt_orphan_queues(orphans, idx + 1)
    end)
end

mp.add_timeout(0.5, startup_recovery)

return M
