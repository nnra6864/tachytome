local common = require 'common'

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
        -- Prepend global copy to pass-through subtitles and attachments natively
        table.insert(args, "-c") table.insert(args, "copy")
        table.insert(args, "-map_metadata") table.insert(args, "0")
        table.insert(args, "-metadata") table.insert(args, "ENCODED_BY=tachytome")
        table.insert(args, "-metadata") table.insert(args, "TACHYTOME_CRF=" .. tostring(opts.crf))

        -- Video Encoding Hardware Profiles
        local enc = opts.video_encoder:lower()
        if enc == "nvidia" then
            local hw_args = {
                "-c:v",         "av1_nvenc",
                "-preset",      tostring(opts.preset),
                "-tune",        "hq",
                "-rc",          "vbr",
                "-cq",          tostring(opts.crf),
                "-b:v",         "0",
                "-spatial-aq",  "1"
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "amd" then
            local hw_args = {
                "-c:v",         "av1_amf",
                "-usage",       "transcoding",
                "-quality",     tostring(opts.preset),
                "-rc",          "cqp",
                "-qp_i",        tostring(opts.crf),
                "-qp_p",        tostring(opts.crf)
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        elseif enc == "intel" then
            local hw_args = {
                "-c:v",             "av1_qsv",
                "-preset",          tostring(opts.preset),
                "-global_quality",  tostring(opts.crf)
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        else
            -- Default to highest efficiency Software AV1
            local hw_args = {
                "-c:v",           "libsvtav1",
                "-preset",        tostring(opts.preset),
                "-crf",           tostring(opts.crf),
                "-pix_fmt",       "yuv420p10le",
                "-svtav1-params", "tune=0:scd=1",
                "-metadata",      "TACHYTOME_PRESET=" .. tostring(opts.preset)
            }
            for _, v in ipairs(hw_args) do table.insert(args, v) end
        end

        -- Audio logic
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
