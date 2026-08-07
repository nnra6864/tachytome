local options = require 'mp.options'

local M = {
    opts = {
        output_dir          = "",
        space_replacement   = "_",
        container           = "mkv",
        suffix              = " Remuxed",
        conflict_suffix     = " Remuxed",
        accurate_cut        = true,
        lossless_cut        = false,
        crf                 = 30,
        preset              = 4,
        combine_audio       = false,
        combined_audio_name = "Combined",
        trash_original      = true,
        show_stats_screen   = true,
        stats_osd_time      = 8
    },
    custom_output_name = "",
    mark_in            = 0,
    mark_out           = 0,
    trash_path         = nil,
    ffmpeg_ok          = false
}

options.read_options(M.opts, "tachytome")
return M
