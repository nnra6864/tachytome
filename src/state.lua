local mp      = require 'mp'
local utils   = require 'mp.utils'
local options = require 'mp.options'
local common  = require 'src.common'

local M = {
    opts = {
        output_dir          = "",
        lossless_cut        = false,
        video_encoder       = "av1",
        quality             = 35,
        preset              = 4,
        accurate_cut        = true,
        combine_audio       = false,
        combined_audio_name = "Combined",
        first_audio_only    = false,
        space_replacement   = "_",
        suffix              = " Remuxed",
        container           = "mkv",
        trash_source        = true,
        show_stats_screen   = true,
        show_stats_terminal = true,
        stats_osd_time      = 8,
        font_size           = 16,
        small_font_size     = 10,
        glow_size           = 2.5,
        glow_blur           = 0.5,
        glow_color          = "000000FF",
        text_color          = "FFFFFF",
        dim_text_color      = "E6E6E6",
        value_color         = "00FFFF",
        on_text             = "ON",
        on_color            = "00FF00",
        off_text            = "OFF",
        off_color           = "FF0000",
        flash_color         = "00FFFF",
        warning_color       = "FFFF00",
        error_color         = "FF0000",
        flash_in_duration   = 0.1,
        flash_in_easing     = "easeOutExpo",
        flash_out_duration  = 0.5,
        flash_out_easing    = "easeOutCubic",
        start_stagger       = 0.03,
        start_in_duration   = 0.25,
        start_in_easing     = "easeOutSine",
        start_out_duration  = 0.75,
        start_out_easing    = "easeOutCubic",
        selected_keymap     = "builtin"
    },
    conf_path          = nil,
    custom_output_name = "",
    fps_override       = nil,
    effects_enabled    = false,
    effects            = {},
    mark_in            = 0,
    mark_out           = 0,
    trash_path         = nil,
    ffmpeg_ok          = false,
    path_history       = {},
    ui_owner           = nil
}

local opts_dir  = mp.command_native({"expand-path", "~~/script-opts"})
M.conf_path     = utils.join_path(opts_dir, "tachytome.conf")

local function ensure_config_exists()
    local f = io.open(M.conf_path, "r")
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
    local wf = io.open(M.conf_path, "w")
    if wf then
        wf:write(conf_content)
        wf:close()
        mp.msg.info("Generated default config at: " .. M.conf_path)
    end
end

ensure_config_exists()
options.read_options(M.opts, "tachytome")
M.path_history = common.read_history()

return M
