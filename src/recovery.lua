local mp        = require 'mp'
local utils     = require 'mp.utils'
local common    = require 'src.common'
local process   = require 'src.process'
local queue     = require 'src.queue'
local state     = require 'src.state'
local notify    = require 'src.notify'
local theme     = require 'src.theme'
local ui_choice = require 'src.ui_choice'

local M = {}

local can_suspend = common.get_platform() ~= "windows"

local orphan_checked_dirs   = {}
local dismissed_temps       = {}
local pending_temp_prompts  = {}
local temp_prompt_scheduled = false

local function is_live_temp_name(name)
    if queue.active and queue.active.temp_file and name == queue.temp_base_name(queue.active.temp_file) then return true end
    for _, q_job in ipairs(queue.jobs) do
        if q_job.temp_file and name == queue.temp_base_name(q_job.temp_file) then return true end
    end
    for _, rec in ipairs(queue.failed) do
        if rec.temp_file and name == queue.temp_base_name(rec.temp_file) then return true end
    end
    return false
end

local function all_queue_referenced_temps()
    local set = {}
    for _, path in ipairs(queue.scan_files()) do
        local parsed = queue.read_file(path)
        if type(parsed) == "table" and type(parsed.items) == "table" then
            for _, it in ipairs(parsed.items) do
                if type(it) == "table" and type(it.temp_file) == "string" then
                    set[queue.temp_base_name(it.temp_file)] = true
                end
            end
        end
    end
    return set
end

local function show_temp_orphan_dialog(entry, on_done)
    local shown = {}
    for i = 1, math.min(#entry.files, 3) do table.insert(shown, entry.files[i]) end
    local extra = (#entry.files > 3) and string.format(" +%d more", #entry.files - 3) or ""
    local body  = string.format("%s%s\\N%s%s", theme.f(true), entry.dir, table.concat(shown, "\\N"), extra)

    ui_choice.show("Interrupted Render Leftovers", body, {
        { key = "1", label = "Delete" },
        { key = "2", label = "Keep" }
    }, 2, function(idx)
        if idx == 1 then
            for _, name in ipairs(entry.files) do
                queue.delete_temp_file(utils.join_path(entry.dir, name))
            end
            notify.show("Deleted leftover temp render file(s).", true)
        else
            for _, name in ipairs(entry.files) do dismissed_temps[name] = true end
            notify.show("Kept leftover temp render file(s).", true)
        end
        if on_done then on_done() end
    end)
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
        if name:sub(1, #queue.temp_prefix) == queue.temp_prefix
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

local function kill_orphan_ffmpeg(item)
    if not can_suspend or type(item.pid_file) ~= "string" then return end

    local f = io.open(item.pid_file, "r")
    if not f then return end
    local pid = tonumber(f:read("*l"))
    f:close()
    os.remove(item.pid_file)

    if not pid then return end
    local comm = process.process_comm(pid)
    if not (comm and comm:find("ffmpeg", 1, true)) then return end

    local args = process.process_args(pid)
    if not (args and item.temp_file and args:find(item.temp_file, 1, true)) then
        mp.msg.warn("Not killing pid " .. tostring(pid) .. ": it is ffmpeg but not this render's process.")
        return
    end

    process.signal_pid(pid, "KILL")
    mp.msg.warn("Killed orphaned ffmpeg from crashed render: " .. tostring(item.final_name))
end

local function collect_orphan_queues()
    local orphans = {}
    for _, path in ipairs(queue.scan_files()) do
        local parsed = queue.read_file(path)
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
                if owner == queue.own_pid and not queue.has_saved then
                    table.insert(orphans, {path = path, owner_pid = owner, items = items})
                elseif owner and process.mpv_alive(owner) then
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
    local owner_str = file.owner_pid and string.format("From a closed/crashed mpv (pid %d)", file.owner_pid) or "From a closed/crashed mpv"
    local names     = {}
    for i, it in ipairs(file.items) do
        if i > 3 then
            table.insert(names, string.format("+%d more", #file.items - 3))
            break
        end
        table.insert(names, string.format("%s [%s]", tostring(it.final_name), tostring(it.status)))
    end
    local body = string.format("%s%s\\N%s", theme.f(true), owner_str, table.concat(names, "\\N"))

    ui_choice.show("Interrupted Renders Found", body, {
        { key = "1", label = "Recover" },
        { key = "2", label = "Discard" },
        { key = "3", label = "Ignore" }
    }, 3, function(idx)
        if idx == 1 then
            if on_recover then on_recover() end
        elseif idx == 2 then
            if on_discard then on_discard() end
        elseif idx == 3 then
            if on_ignore then on_ignore() end
        end
    end)
end

local function adopt_orphan_queue(file)
    local adopted = 0
    for _, it in ipairs(file.items) do
        if it.status == "active" or it.status == "paused" then
            kill_orphan_ffmpeg(it)
        end
        queue.delete_temp_file(it.temp_file)

        if not utils.file_info(it.input_file) then
            notify.show("Skipped recovered render (source missing): " .. tostring(it.final_name), true, "warn")
        elseif (tonumber(it.mark_out) or 0) <= (tonumber(it.mark_in) or 0) then
            notify.show("Skipped recovered render (invalid marks): " .. tostring(it.final_name), true, "warn")
        else
            table.insert(queue.jobs, queue.build_job({
                input_file          = it.input_file,
                output_file         = it.output_file,
                final_name          = it.final_name,
                start_time          = it.mark_in,
                end_time            = it.mark_out,
                input_duration      = it.input_duration,
                input_size          = it.input_size,
                video_encoder       = it.video_encoder,
                quality             = it.quality,
                preset              = it.preset,
                fps_override        = it.fps_override,
                lossless_cut        = it.lossless_cut,
                accurate_cut        = it.accurate_cut,
                combine_audio       = it.combine_audio,
                combined_audio_name = it.combined_audio_name,
                trash_source        = it.trash_source,
                trash_path          = it.trash_path,
                space_replacement   = it.space_replacement,
                show_stats_screen   = it.show_stats_screen,
                show_stats_terminal = it.show_stats_terminal,
                stats_osd_time      = it.stats_osd_time
            }))
            adopted = adopted + 1
        end
    end
    os.remove(file.path)

    if adopted > 0 then
        queue.total_jobs   = queue.total_jobs + adopted
        queue.queue_paused = true
        notify.show("Render queue recovered and paused.", true)
    end
    queue.save()
end

local function discard_orphan_queue(file)
    for _, it in ipairs(file.items) do
        if it.status == "active" or it.status == "paused" then
            kill_orphan_ffmpeg(it)
        end
        queue.delete_temp_file(it.temp_file)
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
