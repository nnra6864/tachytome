local common = require 'src.common'

local M = {}

local function get_audio_stream_data(input_file)
    local probe_data = common.ffprobe_get_json(input_file, {
        "-show_streams", "-select_streams", "a", "-print_format", "json"
    })

    if not probe_data or not probe_data.streams then return 0, nil end

    local count = #probe_data.streams
    if count == 0 then return 0, nil end

    local first_stream = probe_data.streams[1]
    local meta = {
        codec       = first_stream.codec_name,
        sample_rate = first_stream.sample_rate,
        bit_rate    = first_stream.bit_rate
    }

    return count, meta
end

function M.build_args(opts, input_file, output_file, creation_time)
    local args     = { "ffmpeg", "-y", "-hide_banner" }
    local duration = opts.mark_out - opts.mark_in

    if opts.accurate_cut then
        table.insert(args, "-i")  table.insert(args, input_file)
        table.insert(args, "-ss") table.insert(args, tostring(opts.mark_in))
        table.insert(args, "-to") table.insert(args, tostring(opts.mark_out))
    else
        table.insert(args, "-ss") table.insert(args, tostring(opts.mark_in))
        table.insert(args, "-i")  table.insert(args, input_file)
        table.insert(args, "-t")  table.insert(args, tostring(duration))
    end

    if creation_time then
        table.insert(args, "-metadata")
        table.insert(args, "creation_time=" .. creation_time)
    end

    if opts.lossless_cut then
        local codec_args = {
            "-c",            "copy",
            "-map",          "0",
            "-map_metadata", "0",
            "-metadata",     "ENCODED_BY=tachytome",
            "-metadata",     "TACHYTOME_MODE=Lossless"
        }
        for _, v in ipairs(codec_args) do table.insert(args, v) end
    else
        local enc = opts.video_encoder:lower()

        local safe_quality = tonumber(opts.quality) or 30
        if enc == "av1" then
            safe_quality = math.min(63, math.max(0, safe_quality))
        elseif enc:match("^intel_") then
            safe_quality = math.min(51, math.max(1, safe_quality))
        else
            safe_quality = math.min(51, math.max(0, safe_quality))
        end
        local quality_str = tostring(safe_quality)

        table.insert(args, "-c") table.insert(args, "copy")
        table.insert(args, "-map_metadata") table.insert(args, "0")
        table.insert(args, "-metadata") table.insert(args, "ENCODED_BY=tachytome")
        table.insert(args, "-metadata") table.insert(args, "TACHYTOME_QUALITY=" .. quality_str)

        if enc == "nv_av1" then
            local hw_args = {
                "-c:v",          "av1_nvenc",
                "-preset",       tostring(opts.preset),
                "-tune",         "hq",
                "-rc",           "vbr",
                "-cq",           quality_str,
                "-b:v",          "0",
                "-spatial_aq",   "1",
                "-temporal_aq",  "1",
                "-rc-lookahead", "32",
                "-multipass",    "fullres",
                "-pix_fmt",      "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd_av1" then
            local hw_args = {
                "-c:v",          "av1_amf",
                "-usage",        "transcoding",
                "-quality",      tostring(opts.preset),
                "-rc",           "cqp",
                "-qp_i",         quality_str,
                "-qp_p",         quality_str,
                "-preanalysis",  "1",
                "-pix_fmt",      "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel_av1" then
            local hw_args = {
                "-c:v",              "av1_qsv",
                "-preset",           tostring(opts.preset),
                "-global_quality",   quality_str,
                "-look_ahead",       "1",
                "-look_ahead_depth", "32",
                "-pix_fmt",          "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "h265" then
            local hw_args = {
                "-c:v",          "libx265",
                "-preset",       tostring(opts.preset),
                "-crf",          quality_str,
                "-pix_fmt",      "yuv420p10le",
                "-x265-params",  "aq-mode=3",
                "-metadata",     "TACHYTOME_PRESET=" .. tostring(opts.preset)
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "nv_h265" then
            local hw_args = {
                "-c:v",          "hevc_nvenc",
                "-preset",       tostring(opts.preset),
                "-profile:v",    "main10",
                "-tune",         "hq",
                "-rc",           "vbr",
                "-cq",           quality_str,
                "-b:v",          "0",
                "-spatial_aq",   "1",
                "-temporal_aq",  "1",
                "-b_ref_mode",   "middle",
                "-rc-lookahead", "32",
                "-multipass",    "fullres",
                "-pix_fmt",      "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd_h265" then
            local hw_args = {
                "-c:v",          "hevc_amf",
                "-usage",        "transcoding",
                "-quality",      tostring(opts.preset),
                "-profile:v",    "main10",
                "-rc",           "cqp",
                "-qp_i",         quality_str,
                "-qp_p",         quality_str,
                "-preanalysis",  "1",
                "-pix_fmt",      "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel_h265" then
            local hw_args = {
                "-c:v",              "hevc_qsv",
                "-preset",           tostring(opts.preset),
                "-profile:v",        "main10",
                "-global_quality",   quality_str,
                "-look_ahead",       "1",
                "-look_ahead_depth", "32",
                "-pix_fmt",          "p010le"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        else
            -- Default to highest efficiency Software AV1
            local hw_args = {
                "-c:v",           "libsvtav1",
                "-preset",        tostring(opts.preset),
                "-crf",           quality_str,
                "-pix_fmt",       "yuv420p10le",
                "-svtav1-params", "tune=0:scd=1",
                "-metadata",      "TACHYTOME_PRESET=" .. tostring(opts.preset)
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        end

        if opts.combine_audio then
            local audio_stream_count, orig_meta = get_audio_stream_data(input_file)

            if audio_stream_count > 1 and orig_meta then
                local encoder = orig_meta.codec
                if orig_meta.codec     == "opus" then encoder   = "libopus"
                elseif orig_meta.codec == "mp3" then encoder    = "libmp3lame"
                elseif orig_meta.codec == "vorbis" then encoder = "libvorbis" end

                local filter_inputs = ""
                for i = 0, audio_stream_count - 1 do filter_inputs = filter_inputs .. string.format("[0:a:%d]", i) end
                local filter_complex = string.format("%samix=inputs=%d:normalize=0[aout]", filter_inputs, audio_stream_count)

                table.insert(args, "-filter_complex") table.insert(args, filter_complex)
                table.insert(args, "-map") table.insert(args, "[aout]")
                table.insert(args, "-map") table.insert(args, "0")

                table.insert(args, "-c:a:0") table.insert(args, encoder)
                if orig_meta.sample_rate and orig_meta.sample_rate ~= "N/A" then
                    table.insert(args, "-ar:0") table.insert(args, orig_meta.sample_rate)
                end
                if orig_meta.bit_rate and orig_meta.bit_rate ~= "N/A" then
                    table.insert(args, "-b:a:0") table.insert(args, orig_meta.bit_rate)
                end

                for i = 1, audio_stream_count do
                    table.insert(args, string.format("-c:a:%d", i))
                    table.insert(args, "copy")
                end

                table.insert(args, "-disposition:a:0") table.insert(args, "default")
                table.insert(args, "-metadata:s:a:0")  table.insert(args, string.format("TITLE=%s", opts.combined_audio_name))
            else
                table.insert(args, "-map") table.insert(args, "0")
            end
        else
            table.insert(args, "-map") table.insert(args, "0")
        end
    end

    table.insert(args, output_file)
    return args
end

return M
