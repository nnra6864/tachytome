local common     = require 'src.common'
local effects    = require 'src.effects'
local resolution = require 'src.resolution'
local tracks     = require 'src.tracks'

local M = {}

local function display_size(s)
    local w = tonumber(s.width)
    local h = tonumber(s.height)
    if not w or not h or w <= 0 or h <= 0 then return nil end
    local sar_n, sar_d = tostring(s.sample_aspect_ratio or ""):match("^(%d+):(%d+)$")
    local sar          = 1
    if sar_n and tonumber(sar_n) > 0 and tonumber(sar_d) > 0 then sar = tonumber(sar_n) / tonumber(sar_d) end
    local rotation = 0
    for _, side in ipairs(s.side_data_list or {}) do
        if side.rotation then rotation = tonumber(side.rotation) or 0 end
    end
    if rotation == 0 and s.tags and s.tags.rotate then rotation = tonumber(s.tags.rotate) or 0 end
    if math.abs(rotation) % 180 == 90 then return { w = h, h = w, sar = 1 / sar } end
    return { w = w, h = h, sar = sar }
end

local function get_media_info(input_file)
    local probe_data = common.ffprobe_get_json(input_file, {
        "-show_streams", "-print_format", "json"
    })

    local info = { audio = {}, video = {} }
    if not probe_data or not probe_data.streams then return info end

    for _, s in ipairs(probe_data.streams) do
        if s.codec_type == "audio" then
            local title = s.tags and (s.tags.title or s.tags.TITLE)
            info.audio[#info.audio + 1] = { codec = s.codec_name, sample_rate = s.sample_rate, bit_rate = s.bit_rate, channels = tonumber(s.channels), title = title }
        elseif s.codec_type == "video" then
            local fps = nil
            if s.avg_frame_rate and s.avg_frame_rate ~= "0/0" and s.avg_frame_rate ~= "N/A" then fps = s.avg_frame_rate end
            info.video[#info.video + 1] = { fps = fps, full_range = s.color_range == "pc", size = display_size(s) }
        end
    end
    return info
end

local audio_encoders = {
    opus   = "libopus",
    aac    = "aac",
    mp3    = "libmp3lame",
    flac   = "flac",
    vorbis = "libvorbis",
    pcm    = "pcm_s16le"
}

local channel_bitrates = { libopus = 256000, aac = 256000 }

local ogg_codecs ={ opus = true, vorbis = true, flac = true }
local wav_codecs = { pcm_s16le = true, pcm_s24le = true, pcm_s32le = true, pcm_f32le = true, pcm_u8 = true }

local audio_formats = {
    mka  = {},
    opus = { encoder = "opus",   codecs = { opus = true }, single = true },
    ogg  = { encoder = "opus",   codecs = ogg_codecs },
    oga  = { encoder = "opus",   codecs = ogg_codecs },
    m4a  = { encoder = "aac",    codecs = { aac = true, alac = true, ac3 = true, eac3 = true } },
    mp3  = { encoder = "mp3",    codecs = { mp3 = true },  single = true },
    aac  = { encoder = "aac",    codecs = { aac = true },  single = true },
    flac = { encoder = "flac",   codecs = { flac = true }, single = true },
    wav  = { encoder = "pcm",    codecs = wav_codecs,      single = true }
}

local function first_mix(out)
    for _, e in ipairs(out) do
        if e.kind == "mix" then return e end
    end
    return out[1]
end

local function select_streams(info, opts, output_file)
    local result, err = tracks.build(opts.tracks or "", #info.audio, #info.video)
    if not result then return nil, err end
    local ext       = (output_file:match("%.([a-zA-Z0-9]+)$") or ""):lower()
    info.format     = audio_formats[ext]
    info.audio_only = info.format ~= nil
    info.single     = info.format ~= nil and info.format.single == true
    info.audio_out  = result.audio
    if info.single and #info.audio_out > 1 then info.audio_out = { first_mix(info.audio_out) } end
    info.has_mix    = (first_mix(info.audio_out) or {}).kind == "mix"
    info.video_pick = {}
    if not info.audio_only then
        for i = 1, #info.video do
            if tracks.kept(result.video, i) then info.video_pick[#info.video_pick + 1] = i - 1 end
        end
    end
    info.a_meta     = info.audio_out[1] and info.audio[tracks.leaf(info.audio_out[1])] or nil
    info.a_choice   = audio_encoders[opts.audio_encoder] and opts.audio_encoder or nil
    info.a_bitrate  = (opts.audio_bitrate or "") ~= "" and opts.audio_bitrate or nil
    info.full_range = false
    info.v_fps      = nil
    info.v_size     = nil
    for k, i in ipairs(info.video_pick) do
        local v = info.video[i + 1]
        if k == 1 then
            info.full_range = v.full_range
            info.v_size     = v.size
        end
        if not info.v_fps then info.v_fps = v.fps end
    end
    return info
end

-- ffprobe reports fps as rationals like "30000/1001"; fps_override is a plain number
local function parse_fps(value)
    if type(value) == "number" then
        if value > 0 then return value end
        return nil
    end
    if type(value) ~= "string" then return nil end
    local num, den = value:match("^(%d+)/(%d+)$")
    if num then
        num = tonumber(num)
        den = tonumber(den)
        if num > 0 and den > 0 then return num / den end
        return nil
    end
    num = tonumber(value)
    if num and num > 0 then return num end
    return nil
end

local function keyframe_frames(value, fps)
    if type(value) ~= "string" or value == "" then return nil end
    local secs = value:match("^([%d%.]+)s$")
    if secs then
        secs = tonumber(secs)
        if not secs or not fps or fps <= 0 then return nil end
        return math.max(1, math.floor(secs * fps + 0.5))
    end
    local frames = tonumber(value:match("^%d+$"))
    if frames and frames > 0 then return frames end
    return nil
end

local function deselect(args, kind, count, keep)
    local kept = {}
    for _, i in ipairs(keep) do kept[i] = true end
    for i = 0, count - 1 do
        if not kept[i] then
            table.insert(args, "-map") table.insert(args, string.format("-0:%s:%d", kind, i))
        end
    end
end

local function map_source(args, media_info, audio)
    table.insert(args, "-map") table.insert(args, media_info.audio_only and "0:a?" or "0")
    deselect(args, "a", #media_info.audio, audio)
    if not media_info.audio_only then deselect(args, "v", #media_info.video, media_info.video_pick) end
end

local function kept_audio(media_info)
    local out = {}
    for _, e in ipairs(media_info.audio_out) do out[#out + 1] = e.n - 1 end
    return out
end

local function audio_encoder(a_meta)
    local encoder = a_meta.codec
    if a_meta.codec     == "opus" then encoder   = "libopus"
    elseif a_meta.codec == "mp3" then encoder    = "libmp3lame"
    elseif a_meta.codec == "vorbis" then encoder = "libvorbis" end
    return encoder
end

local function fits(fmt, codec)
    return not fmt or not fmt.codecs or fmt.codecs[codec] == true
end

local function track_encoder(media_info, meta)
    local fmt    = media_info.format
    local choice = media_info.a_choice
    if choice and fits(fmt, choice == "pcm" and "pcm_s16le" or choice) then return audio_encoders[choice] end
    if fits(fmt, meta.codec) then return nil end
    return audio_encoders[fmt.encoder]
end

local function audio_codec_args(args, media_info, index, meta, force)
    local encoder  = track_encoder(media_info, meta)
    local lossless = meta.codec == "flac" or meta.codec == "alac" or meta.codec:match("^pcm_")
    if not encoder and not force and (not media_info.a_bitrate or lossless) then return end

    local suffix  = string.format(":%d", index)
    local same    = not encoder or encoder == audio_encoder(meta)
    local bitrate = media_info.a_bitrate
    encoder       = encoder or audio_encoder(meta)
    table.insert(args, "-c:a" .. suffix) table.insert(args, encoder)
    if same and meta.sample_rate and meta.sample_rate ~= "N/A" then
        table.insert(args, "-ar" .. suffix) table.insert(args, meta.sample_rate)
    end
    if encoder == "flac" or encoder:match("^pcm_") then return end

    if not bitrate and same and meta.bit_rate and meta.bit_rate ~= "N/A" then bitrate = meta.bit_rate end
    if not bitrate and encoder == "libvorbis" then
        table.insert(args, "-q:a" .. suffix) table.insert(args, "10")
        return
    end
    if not bitrate and encoder == "libmp3lame" then bitrate = "320k" end
    if not bitrate and channel_bitrates[encoder] then bitrate = tostring(channel_bitrates[encoder] * (meta.channels or 2)) end
    if bitrate then
        table.insert(args, "-b:a" .. suffix) table.insert(args, bitrate)
    end
end

local function renamed_chain(chain, suffix)
    return (chain:gsub("@(%w+)", "@%1" .. suffix))
end

local function append_mixes(args, media_info, af_effects)
    local chain = #af_effects > 0 and table.concat(af_effects, ",") or nil
    local out   = media_info.audio_out
    local uses  = {}
    local pads  = {}
    local parts = {}
    local ids   = 0

    local function need(e)
        uses[e] = (uses[e] or 0) + 1
        if uses[e] == 1 and e.kind == "mix" then
            for _, input in ipairs(e.inputs) do need(input) end
        end
    end

    local function label()
        ids = ids + 1
        return "t" .. ids
    end

    local function split(src, e)
        if uses[e] == 1 then
            pads[e] = { src }
            return
        end
        local outs  = {}
        local names = ""
        for _ = 1, uses[e] do
            local l         = label()
            outs[#outs + 1] = l
            names           = names .. "[" .. l .. "]"
        end
        parts[#parts + 1] = string.format("[%s]asplit=%d%s", src, uses[e], names)
        pads[e]           = outs
    end

    local function emit(e)
        if pads[e] then return end
        if e.kind == "source" then return split("0:a:" .. (e.n - 1), e) end
        for _, input in ipairs(e.inputs) do emit(input) end
        local inputs = ""
        for _, input in ipairs(e.inputs) do inputs = inputs .. "[" .. table.remove(pads[input], 1) .. "]" end
        local l           = label()
        parts[#parts + 1] = string.format("%samix=inputs=%d:normalize=0[%s]", inputs, #e.inputs, l)
        split(l, e)
    end

    for _, e in ipairs(out) do
        if e.kind == "mix" or chain then need(e) end
    end

    local maps = {}
    for k, e in ipairs(out) do
        if e.kind == "source" and not chain then
            maps[k] = string.format("0:a:%d", e.n - 1)
        else
            emit(e)
            local pad = table.remove(pads[e], 1)
            if chain then
                parts[#parts + 1] = string.format("[%s]%s[aout%d]", pad, renamed_chain(chain, "t" .. (k - 1)), k)
                pad               = "aout" .. k
            end
            maps[k] = "[" .. pad .. "]"
        end
    end

    table.insert(args, "-filter_complex") table.insert(args, table.concat(parts, ";"))
    map_source(args, media_info, {})
    for k = 1, #out do
        table.insert(args, "-map") table.insert(args, maps[k])
    end

    local default = nil
    for k, e in ipairs(out) do
        local meta = media_info.audio[tracks.leaf(e)]
        local title = e.kind == "mix" and e.name or (chain and meta.title)
        audio_codec_args(args, media_info, k - 1, meta, e.kind == "mix" or chain ~= nil)
        if e.kind == "mix" then default = default or k end
        if title then
            table.insert(args, "-metadata:s:a:" .. (k - 1)) table.insert(args, string.format("TITLE=%s", title))
        end
    end
    for k = 1, #out do
        table.insert(args, "-disposition:a:" .. (k - 1)) table.insert(args, k == default and "default" or "0")
    end
end

local function append_audio_effects(args, media_info, af_effects)
    if not media_info.a_meta then return end
    if #af_effects > 0 then
        table.insert(args, "-af") table.insert(args, table.concat(af_effects, ","))
    end
    for k, i in ipairs(kept_audio(media_info)) do
        audio_codec_args(args, media_info, k - 1, media_info.audio[i + 1], #af_effects > 0)
    end
end

function M.build_args(opts, input_file, output_file, creation_time)
    local media_info, tracks_err = select_streams(get_media_info(input_file), opts, output_file)
    if not media_info then return nil, tracks_err end
    local args     = { "ffmpeg", "-y", "-hide_banner" }
    local duration = opts.mark_out - opts.mark_in
    local out_fps  = nil
    local accurate = opts.accurate_cut or opts.lossless_cut

    local vf_effects = {}
    local af_effects = {}
    if opts.effects then
        local offset = accurate and opts.mark_in or 0
        vf_effects, af_effects = effects.build_filters(opts.effects, duration, offset, {
            full_range = media_info.full_range,
            fps        = parse_fps(opts.fps_override or media_info.v_fps)
        })
    end
    local vf_resolution = {}
    if opts.resolution and media_info.v_size then
        local size         = media_info.v_size
        local step         = resolution.step(opts.video_encoder)
        local filters, err = resolution.filters(opts.resolution, size.w, size.h, size.sar, step)
        if not filters then return nil, err end
        vf_resolution = filters
    end
    local lossless = opts.lossless_cut and #vf_effects == 0 and #af_effects == 0 and #vf_resolution == 0

    local trimmed = accurate and opts.mark_in > 0
    if trimmed then
        if #vf_effects > 0 then table.insert(vf_effects, 1, "trim=start=" .. tostring(opts.mark_in)) end
        if #af_effects > 0 then table.insert(af_effects, 1, "atrim=start=" .. tostring(opts.mark_in)) end
    end
    local at = (trimmed and #vf_effects > 0) and 2 or 1
    for i, f in ipairs(vf_resolution) do table.insert(vf_effects, at + i - 1, f) end

    table.insert(args, "-fflags") table.insert(args, "+genpts")

    local seek_in = opts.mark_in
    if lossless then
        seek_in = common.nearest_keyframe_at_or_before(input_file, opts.mark_in) or opts.mark_in
    end

    if accurate then
        table.insert(args, "-i")  table.insert(args, input_file)
        table.insert(args, "-ss") table.insert(args, tostring(seek_in))
        table.insert(args, "-to") table.insert(args, tostring(opts.mark_out))
    else
        table.insert(args, "-ss") table.insert(args, tostring(opts.mark_in))
        table.insert(args, "-i")  table.insert(args, input_file)
        table.insert(args, "-ss") table.insert(args, "0")
        table.insert(args, "-t")  table.insert(args, tostring(duration))
    end

    table.insert(args, "-avoid_negative_ts") table.insert(args, "make_zero")

    if creation_time then
        table.insert(args, "-metadata")
        table.insert(args, "creation_time=" .. creation_time)
    end

    if lossless then
        out_fps = parse_fps(media_info.v_fps)
        local codec_args = {
            "-c",            "copy",
            "-map_metadata", "0",
            "-metadata",     "ENCODED_BY=tachytome",
            "-metadata",     "TACHYTOME_MODE=Lossless"
        }
        for _, v in ipairs(codec_args) do table.insert(args, v) end
        if media_info.has_mix then
            append_mixes(args, media_info, af_effects)
        else
            map_source(args, media_info, kept_audio(media_info))
            append_audio_effects(args, media_info, af_effects)
        end
    else
        local enc = opts.video_encoder:lower()

        local safe_quality = tonumber(opts.quality) or 30
        if enc == "av1" then safe_quality = math.min(63, math.max(0, safe_quality))
        elseif enc == "nv_av1" then safe_quality = math.min(63, math.max(0, safe_quality))
        elseif enc:match("^intel_") then safe_quality = math.min(51, math.max(1, safe_quality))
        else safe_quality = math.min(51, math.max(0, safe_quality)) end
        local quality_str = tostring(safe_quality)
        local has_video   = #media_info.video_pick > 0
        local fps_value   = has_video and (opts.fps_override or media_info.v_fps) or nil

        local v_filters = {}
        if fps_value then
            out_fps = parse_fps(fps_value)
            v_filters[#v_filters + 1] = "fps=" .. fps_value
        end
        for _, fx in ipairs(vf_effects) do v_filters[#v_filters + 1] = fx end
        if has_video and #v_filters > 0 then
            table.insert(args, "-vf")
            table.insert(args, table.concat(v_filters, ","))
        end

        table.insert(args, "-c") table.insert(args, "copy")
        table.insert(args, "-map_metadata") table.insert(args, "0")
        table.insert(args, "-metadata") table.insert(args, "ENCODED_BY=tachytome")
        table.insert(args, "-metadata") table.insert(args, "TACHYTOME_QUALITY=" .. quality_str)

        if enc == "nv_av1" then
            local hw_args = { "-c:v", "av1_nvenc", "-preset", tostring(opts.preset), "-tune", "hq", "-rc", "vbr", "-cq", quality_str, "-b:v", "0", "-spatial-aq", "1", "-temporal-aq", "1", "-b_ref_mode", "middle", "-rc-lookahead", "32", "-multipass", "fullres", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd_av1" then
            local hw_args = { "-c:v", "av1_amf", "-usage", "transcoding", "-quality", tostring(opts.preset), "-rc", "cqp", "-qp_i", quality_str, "-qp_p", quality_str, "-preanalysis", "1", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel_av1" then
            local hw_args = { "-c:v", "av1_qsv", "-preset", tostring(opts.preset), "-global_quality", quality_str, "-extbrc", "1", "-look_ahead_depth", "32", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "h265" then
            local hw_args = { "-c:v", "libx265", "-preset", tostring(opts.preset), "-crf", quality_str, "-pix_fmt", "yuv420p10le", "-x265-params", "aq-mode=3", "-metadata", "TACHYTOME_PRESET=" .. tostring(opts.preset) }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "nv_h265" then
            local hw_args = { "-c:v", "hevc_nvenc", "-preset", tostring(opts.preset), "-profile:v", "main10", "-tune", "uhq", "-rc", "vbr", "-cq", quality_str, "-b:v", "0", "-spatial-aq", "1", "-temporal-aq", "1", "-b_ref_mode", "middle", "-rc-lookahead", "32", "-multipass", "fullres", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd_h265" then
            local hw_args = { "-c:v", "hevc_amf", "-usage", "transcoding", "-quality", tostring(opts.preset), "-profile:v", "main10", "-rc", "cqp", "-qp_i", quality_str, "-qp_p", quality_str, "-preanalysis", "1", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel_h265" then
            local hw_args = { "-c:v", "hevc_qsv", "-preset", tostring(opts.preset), "-profile:v", "main10", "-global_quality", quality_str, "-extbrc", "1", "-look_ahead_depth", "32", "-pix_fmt", "p010le" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "h264" then
            local hw_args = { "-c:v", "libx264", "-preset", tostring(opts.preset), "-crf", quality_str, "-pix_fmt", "yuv420p", "-x264-params", "aq-mode=3", "-metadata", "TACHYTOME_PRESET=" .. tostring(opts.preset) }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "nv_h264" then
            local hw_args = { "-c:v", "h264_nvenc", "-preset", tostring(opts.preset), "-profile:v", "high", "-tune", "hq", "-rc", "vbr", "-cq", quality_str, "-b:v", "0", "-spatial-aq", "1", "-temporal-aq", "1", "-b_ref_mode", "middle", "-rc-lookahead", "32", "-multipass", "fullres", "-pix_fmt", "yuv420p" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd_h264" then
            local hw_args = { "-c:v", "h264_amf", "-usage", "transcoding", "-quality", tostring(opts.preset), "-profile:v", "high", "-rc", "cqp", "-qp_i", quality_str, "-qp_p", quality_str, "-preanalysis", "1", "-pix_fmt", "yuv420p" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel_h264" then
            local hw_args = { "-c:v", "h264_qsv", "-preset", tostring(opts.preset), "-profile:v", "high", "-global_quality", quality_str, "-extbrc", "1", "-look_ahead_depth", "32", "-pix_fmt", "nv12" }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        else
            local hw_args = { "-c:v", "libsvtav1", "-preset", tostring(opts.preset), "-crf", quality_str, "-pix_fmt", "yuv420p10le", "-svtav1-params", "tune=0:scd=1", "-metadata", "TACHYTOME_PRESET=" .. tostring(opts.preset) }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        end

        local gop = keyframe_frames(opts.keyframe_interval, out_fps)
        if gop then
            table.insert(args, "-g") table.insert(args, tostring(gop))
        end

        if media_info.has_mix then
            append_mixes(args, media_info, af_effects)
        else
            map_source(args, media_info, kept_audio(media_info))
            append_audio_effects(args, media_info, af_effects)
        end
    end

    table.insert(args, output_file)
    return args, out_fps
end

return M
