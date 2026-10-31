local common = require 'src.common'
local effects = require 'src.effects'

local M = {}

local function get_media_info(input_file)
    local probe_data = common.ffprobe_get_json(input_file, {
        "-show_streams", "-print_format", "json"
    })

    local info = { audio_count = 0, a_meta = nil, v_fps = nil, full_range = false, has_range = false }
    if not probe_data or not probe_data.streams then return info end

    for _, s in ipairs(probe_data.streams) do
        if s.codec_type == "audio" then
            info.audio_count = info.audio_count + 1
            if not info.a_meta then
                info.a_meta = { codec = s.codec_name, sample_rate = s.sample_rate, bit_rate = s.bit_rate }
            end
        elseif s.codec_type == "video" then
            if not info.has_range then
                info.has_range  = true
                info.full_range = s.color_range == "pc"
            end
            if not info.v_fps and s.avg_frame_rate and s.avg_frame_rate ~= "0/0" and s.avg_frame_rate ~= "N/A" then
                info.v_fps = s.avg_frame_rate
            end
        end
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

local function deselect_extra_audio(args, audio_count)
    for i = 1, audio_count - 1 do
        table.insert(args, "-map") table.insert(args, string.format("-0:a:%d", i))
    end
end

local function audio_encoder(a_meta)
    local encoder = a_meta.codec
    if a_meta.codec     == "opus" then encoder   = "libopus"
    elseif a_meta.codec == "mp3" then encoder    = "libmp3lame"
    elseif a_meta.codec == "vorbis" then encoder = "libvorbis" end
    return encoder
end

local function audio_codec_args(args, media_info, index)
    local suffix = index and string.format(":%d", index) or ""
    table.insert(args, "-c:a" .. suffix) table.insert(args, audio_encoder(media_info.a_meta))
    if media_info.a_meta.sample_rate and media_info.a_meta.sample_rate ~= "N/A" then
        table.insert(args, "-ar" .. suffix) table.insert(args, media_info.a_meta.sample_rate)
    end
    if media_info.a_meta.bit_rate and media_info.a_meta.bit_rate ~= "N/A" then
        table.insert(args, "-b:a" .. suffix) table.insert(args, media_info.a_meta.bit_rate)
    end
end

local function renamed_chain(chain, suffix)
    return (chain:gsub("@(%w+)", "@%1" .. suffix))
end

local function append_combine_audio(args, opts, media_info, af_effects, reencode_copies)
    local chain = #af_effects > 0 and table.concat(af_effects, ",") or nil

    if chain and not opts.first_audio_only then
        local parts  = {}
        local inputs = ""
        for i = 0, media_info.audio_count - 1 do
            parts[#parts + 1] = string.format("[0:a:%d]asplit=2[m%d][c%d]", i, i, i)
            inputs           = inputs .. string.format("[m%d]", i)
        end
        local mix = string.format("%samix=inputs=%d:normalize=0", inputs, media_info.audio_count)
        parts[#parts + 1] = mix .. "," .. renamed_chain(chain, "mix") .. "[aout0]"
        for i = 0, media_info.audio_count - 1 do
            parts[#parts + 1] = string.format("[c%d]%s[aout%d]", i, renamed_chain(chain, "t" .. i), i + 1)
        end

        table.insert(args, "-filter_complex") table.insert(args, table.concat(parts, ";"))
        table.insert(args, "-map") table.insert(args, "[aout0]")
        for i = 1, media_info.audio_count do
            table.insert(args, "-map") table.insert(args, string.format("[aout%d]", i))
        end
        table.insert(args, "-map") table.insert(args, "0")
        table.insert(args, "-map") table.insert(args, "-0:a")
    else
        local filter_inputs = ""
        for i = 0, media_info.audio_count - 1 do filter_inputs = filter_inputs .. string.format("[0:a:%d]", i) end
        local mix            = string.format("%samix=inputs=%d:normalize=0", filter_inputs, media_info.audio_count)
        if chain then mix = mix .. "," .. chain end

        table.insert(args, "-filter_complex") table.insert(args, mix .. "[aout]")
        table.insert(args, "-map") table.insert(args, "[aout]")
        table.insert(args, "-map") table.insert(args, "0")
        if opts.first_audio_only then
            table.insert(args, "-map") table.insert(args, "-0:a")
        end
    end

    audio_codec_args(args, media_info, 0)

    if not opts.first_audio_only then
        for i = 1, media_info.audio_count do
            if reencode_copies or chain then
                audio_codec_args(args, media_info, i)
            else
                table.insert(args, string.format("-c:a:%d", i))
                table.insert(args, "copy")
            end
        end
    end

    table.insert(args, "-disposition:a:0") table.insert(args, "default")
    table.insert(args, "-metadata:s:a:0")  table.insert(args, string.format("TITLE=%s", opts.combined_audio_name))
end

local function append_audio_effects(args, media_info, af_effects, force)
    if (#af_effects == 0 and not force) or not media_info.a_meta then return end
    if #af_effects > 0 then
        table.insert(args, "-af") table.insert(args, table.concat(af_effects, ","))
    end
    audio_codec_args(args, media_info, nil)
end

function M.build_args(opts, input_file, output_file, creation_time)
    local args       = { "ffmpeg", "-y", "-hide_banner" }
    local duration   = opts.mark_out - opts.mark_in
    local media_info = get_media_info(input_file)
    local out_fps    = nil
    local accurate   = opts.accurate_cut or opts.lossless_cut

    local vf_effects = {}
    local af_effects = {}
    if opts.effects then
        local offset = accurate and opts.mark_in or 0
        vf_effects, af_effects = effects.build_filters(opts.effects, duration, offset, {
            full_range = media_info.full_range,
            fps        = parse_fps(opts.fps_override or media_info.v_fps)
        })
    end
    local lossless = opts.lossless_cut and #vf_effects == 0 and #af_effects == 0

    if accurate and opts.mark_in > 0 then
        if #vf_effects > 0 then table.insert(vf_effects, 1, "trim=start=" .. tostring(opts.mark_in)) end
        if #af_effects > 0 then table.insert(af_effects, 1, "atrim=start=" .. tostring(opts.mark_in)) end
    end

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
        table.insert(args, "-t")  table.insert(args, tostring(duration))
    end

    table.insert(args, "-avoid_negative_ts") table.insert(args, "make_zero")

    if creation_time then
        table.insert(args, "-metadata")
        table.insert(args, "creation_time=" .. creation_time)
    end

    if lossless then
        out_fps = parse_fps(media_info.v_fps)
        if opts.combine_audio and media_info.audio_count > 1 and media_info.a_meta then
            local codec_args = {
                "-c",            "copy",
                "-map_metadata", "0",
                "-metadata",     "ENCODED_BY=tachytome",
                "-metadata",     "TACHYTOME_MODE=Lossless"
            }
            for _, v in ipairs(codec_args) do table.insert(args, v) end
            append_combine_audio(args, opts, media_info, af_effects, false)
        else
            local codec_args = {
                "-c",            "copy",
                "-map",          "0",
                "-map_metadata", "0",
                "-metadata",     "ENCODED_BY=tachytome",
                "-metadata",     "TACHYTOME_MODE=Lossless"
            }
            for _, v in ipairs(codec_args) do table.insert(args, v) end
            if opts.first_audio_only then deselect_extra_audio(args, media_info.audio_count) end
        end
    else
        local enc = opts.video_encoder:lower()

        local safe_quality = tonumber(opts.quality) or 30
        if enc == "av1" then safe_quality = math.min(63, math.max(0, safe_quality))
        elseif enc == "nv_av1" then safe_quality = math.min(63, math.max(0, safe_quality))
        elseif enc:match("^intel_") then safe_quality = math.min(51, math.max(1, safe_quality))
        else safe_quality = math.min(51, math.max(0, safe_quality)) end
        local quality_str = tostring(safe_quality)
        local fps_value   = opts.fps_override or media_info.v_fps

        local v_filters = {}
        if fps_value then
            out_fps = parse_fps(fps_value)
            v_filters[#v_filters + 1] = "fps=" .. fps_value
        end
        for _, fx in ipairs(vf_effects) do v_filters[#v_filters + 1] = fx end
        if #v_filters > 0 then
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

        if opts.combine_audio then
            if media_info.audio_count > 1 and media_info.a_meta then
                append_combine_audio(args, opts, media_info, af_effects, not accurate)
            else
                table.insert(args, "-map") table.insert(args, "0")
                append_audio_effects(args, media_info, af_effects, not accurate)
            end
        elseif opts.first_audio_only then
            table.insert(args, "-map") table.insert(args, "0")
            deselect_extra_audio(args, media_info.audio_count)
            append_audio_effects(args, media_info, af_effects, not accurate)
        else
            table.insert(args, "-map") table.insert(args, "0")
            append_audio_effects(args, media_info, af_effects, not accurate)
        end
    end

    table.insert(args, output_file)
    return args, out_fps
end

return M
