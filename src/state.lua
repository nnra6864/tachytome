local mp      = require 'mp'
local utils   = require 'mp.utils'
local options = require 'mp.options'
local common  = require 'src.common'

local M = {
    opts = {
        output_dir          = "",
        video_encoder       = "av1",
        space_replacement   = "_",
        container           = "mkv",
        suffix              = " Remuxed",
        accurate_cut        = true,
        lossless_cut        = false,
        quality             = 30,
        preset              = 4,
        combine_audio       = false,
        combined_audio_name = "Combined",
        trash_source        = true,
        show_stats_screen   = true,
        show_stats_terminal = true,
        stats_osd_time      = 8,
        font_size           = 16,
        small_font_size     = 10,
        text_color          = "B8DEE6",
        dim_text_color      = "8FADB3",
        value_color         = "267180",
        on_text             = "🞜",
        on_color            = "268032",
        off_text            = "🞖",
        off_color           = "802626",
        warning_color       = "808026",
        error_color         = "802626"
    },
    custom_output_name = "",
    mark_in            = 0,
    mark_out           = 0,
    trash_path         = nil,
    ffmpeg_ok          = false,
    path_history       = {}
}

local function ensure_config_exists()
    local opts_dir  = mp.command_native({"expand-path", "~~/script-opts"})
    local user_conf = utils.join_path(opts_dir, "tachytome.conf")

    local f = io.open(user_conf, "r")
    if f then
        f:close()
        return
    end

    local script_dir = mp.get_script_directory()
    if not script_dir then return end

    local repo_conf = utils.join_path(script_dir, "tachytome.conf")
    local rf = io.open(repo_conf, "r")
    if not rf then return end

    local conf_content = rf:read("*all")
    rf:close()

    common.ensure_dir(opts_dir)
    local wf = io.open(user_conf, "w")
    if wf then
        wf:write(conf_content)
        wf:close()
        mp.msg.info("Generated default config at: " .. user_conf)
    end
end

ensure_config_exists()
options.read_options(M.opts, "tachytome")
M.path_history = common.read_history()

return M
