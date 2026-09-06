local mp      = require 'mp'
local utils   = require 'mp.utils'
local common  = require 'src.common'
local builder = require 'src.ffmpeg'
local state   = require 'src.state'

local M = {}

local own_pid           = utils.getpid()
local data_dir          = common.get_data_dir()
local queue_path        = utils.join_path(data_dir, "queue-" .. tostring(own_pid) .. ".json")
local queue_tmp         = queue_path .. ".tmp"
local legacy_queue_path = utils.join_path(data_dir, "queue.json")

local temp_seq  = 0
local temp_seed = tostring(os.time()) .. "-" .. tostring(math.floor(mp.get_time() * 1000))

M.temp_prefix     = ".tachytome_tmp_"
M.jobs            = {}
M.active          = nil
M.failed          = {}
M.is_rendering    = false
M.render_paused   = false
M.queue_paused    = false
M.total_jobs      = 0
M.current_job_num = 0
M.has_saved       = false
M.own_pid         = own_pid

local function next_temp_id()
    temp_seq = temp_seq + 1
    return temp_seed .. "-" .. tostring(temp_seq)
end

function M.temp_path_for(output_file, temp_id)
    local dir, _ = utils.split_path(output_file)
    local ext    = output_file:match("(%.[a-zA-Z0-9]+)$") or ".mkv"
    return utils.join_path(dir, M.temp_prefix .. temp_id .. ext)
end

function M.temp_base_name(path)
    local _, base = utils.split_path(path)
    return base
end

function M.delete_temp_file(path)
    if not path or not utils.file_info(path) then return end
    local ok, err = os.remove(path)
    if not ok then mp.msg.warn("Could not delete temp render file: " .. tostring(err)) end
end

function M.scan_files()
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

function M.read_file(path)
    return common.read_json_file(path)
end

function M.item_from_job(job, status)
    return {
        status              = status,
        input_file          = job.input_file,
        output_file         = job.output_file,
        temp_file           = job.temp_file,
        final_name          = job.final_name,
        mark_in             = job.start_time,
        mark_out            = job.end_time,
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

function M.save()
    M.has_saved = true
    local items = {}
    if M.is_rendering and M.active then
        table.insert(items, M.item_from_job(M.active, M.render_paused and "paused" or "active"))
    end
    for _, q_job in ipairs(M.jobs) do
        table.insert(items, M.item_from_job(q_job, "queued"))
    end
    for _, rec in ipairs(M.failed) do
        table.insert(items, rec)
    end

    if not common.write_json_file(queue_tmp, { owner_pid = utils.getpid(), items = items }) then
        mp.msg.warn("Could not write render queue file: " .. queue_tmp)
        return
    end
    local ok, err = common.replace_file(queue_tmp, queue_path)
    if not ok then
        mp.msg.warn("Could not replace render queue file: " .. tostring(err))
    end
end

function M.build_job(spec)
    local creation_time = common.get_creation_time(spec.input_file)
    local build_opts    = {
        mark_in             = spec.start_time,
        mark_out            = spec.end_time,
        video_encoder       = spec.video_encoder or state.opts.video_encoder,
        quality             = spec.quality,
        preset              = spec.preset,
        fps_override        = spec.fps_override,
        accurate_cut        = spec.accurate_cut,
        lossless_cut        = spec.lossless_cut,
        combine_audio       = spec.combine_audio,
        combined_audio_name = spec.combined_audio_name
    }
    local args    = builder.build_args(build_opts, spec.input_file, spec.output_file, creation_time)
    local in_info = utils.file_info(spec.input_file)
    local temp_id = next_temp_id()

    return {
        args                = args,
        output_arg_index    = #args,
        input_file          = spec.input_file,
        output_file         = spec.output_file,
        temp_id             = temp_id,
        temp_file           = M.temp_path_for(spec.output_file, temp_id),
        final_name          = spec.final_name,
        trash_source        = spec.trash_source,
        trash_path          = spec.trash_path,
        space_replacement   = spec.space_replacement,
        combined_audio_name = spec.combined_audio_name,
        start_time          = spec.start_time,
        end_time            = spec.end_time,
        duration            = (tonumber(spec.end_time) or 0) - (tonumber(spec.start_time) or 0),
        input_duration      = spec.input_duration or 0,
        quality             = spec.quality,
        video_encoder       = spec.video_encoder,
        preset              = spec.preset,
        fps_override        = spec.fps_override,
        lossless_cut        = spec.lossless_cut,
        accurate_cut        = spec.accurate_cut,
        combine_audio       = spec.combine_audio,
        show_stats_screen   = spec.show_stats_screen,
        show_stats_terminal = spec.show_stats_terminal,
        stats_osd_time      = spec.stats_osd_time,
        input_size          = (in_info and in_info.size) or spec.input_size or 0,
        rename_callback     = spec.rename_callback
    }
end

function M.is_path_in_use(file_path)
    if utils.file_info(file_path) then return true end
    if M.is_rendering and M.active and M.active.output_file == file_path then return true end
    for _, q_job in ipairs(M.jobs) do
        if q_job.output_file == file_path then return true end
    end
    return false
end

return M
