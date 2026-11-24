local mp      = require 'mp'
local utils   = require 'mp.utils'
local common  = require 'src.common'
local builder = require 'src.ffmpeg'
local state   = require 'src.state'

local M = {}

local own_pid    = utils.getpid()
local state_dir  = common.get_state_dir()
local queue_path = utils.join_path(state_dir, "queue-" .. tostring(own_pid) .. ".json")
local queue_tmp  = queue_path .. ".tmp"

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
    local entries = utils.readdir(state_dir)
    if entries then
        for _, name in ipairs(entries) do
            if name:match("^queue%-%d+%.json$") then
                table.insert(files, utils.join_path(state_dir, name))
            end
        end
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
        keyframe_interval   = job.keyframe_interval,
        effects             = job.effects,
        resolution          = job.resolution,
        lossless_cut        = job.lossless_cut,
        accurate_cut        = job.accurate_cut,
        audio_encoder       = job.audio_encoder,
        audio_bitrate       = job.audio_bitrate,
        tracks              = job.tracks,
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
        mark_in           = spec.start_time,
        mark_out          = spec.end_time,
        video_encoder     = spec.video_encoder or state.opts.video_encoder,
        quality           = spec.quality,
        preset            = spec.preset,
        fps_override      = spec.fps_override,
        keyframe_interval = spec.keyframe_interval,
        effects           = spec.effects,
        resolution        = spec.resolution,
        accurate_cut      = spec.accurate_cut,
        lossless_cut      = spec.lossless_cut,
        audio_encoder     = spec.audio_encoder,
        audio_bitrate     = spec.audio_bitrate,
        tracks            = spec.tracks
    }
    local args, out_fps, dropped = builder.build_args(build_opts, spec.input_file, spec.output_file, creation_time)
    if not args then return nil, out_fps end

    local in_info  = utils.file_info(spec.input_file)
    local temp_id  = next_temp_id()
    local duration = (tonumber(spec.end_time) or 0) - (tonumber(spec.start_time) or 0)

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
        start_time          = spec.start_time,
        end_time            = spec.end_time,
        duration            = duration,
        -- output frame count for render progress: exact for encodes (the
        -- fps filter forces CFR), approximate for VFR lossless cuts
        total_frames        = (out_fps and out_fps > 0 and duration > 0) and math.ceil(duration * out_fps) or nil,
        input_duration      = spec.input_duration or 0,
        quality             = spec.quality,
        video_encoder       = spec.video_encoder,
        preset              = spec.preset,
        fps_override        = spec.fps_override,
        keyframe_interval   = spec.keyframe_interval,
        effects             = spec.effects,
        resolution          = spec.resolution,
        lossless_cut        = spec.lossless_cut,
        accurate_cut        = spec.accurate_cut,
        audio_encoder       = spec.audio_encoder,
        audio_bitrate       = spec.audio_bitrate,
        tracks              = spec.tracks,
        show_stats_screen   = spec.show_stats_screen,
        show_stats_terminal = spec.show_stats_terminal,
        stats_osd_time      = spec.stats_osd_time,
        input_size          = (in_info and in_info.size) or spec.input_size or 0,
        dropped_subs        = dropped or 0,
        rename_callback     = spec.rename_callback
    }
end

function M.job_from_item(it)
    return M.build_job({
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
        keyframe_interval   = it.keyframe_interval,
        effects             = it.effects,
        resolution          = it.resolution,
        lossless_cut        = it.lossless_cut,
        accurate_cut        = it.accurate_cut,
        audio_encoder       = it.audio_encoder,
        audio_bitrate       = it.audio_bitrate,
        tracks              = it.tracks,
        trash_source        = it.trash_source,
        trash_path          = it.trash_path,
        space_replacement   = it.space_replacement,
        show_stats_screen   = it.show_stats_screen,
        show_stats_terminal = it.show_stats_terminal,
        stats_osd_time      = it.stats_osd_time
    })
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
