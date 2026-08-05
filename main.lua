local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local common = require 'common'
local osd_input = require 'osd_input'
local render = require 'render'
local stats = require 'stats'

-- =========================================================
-- CONFIGURATION (MPV STANDARD)
-- =========================================================
local opts = {
    output_dir = "", 
    space_replacement = "_",
    container = "mkv",
    suffix = " Remuxed",
    overwrite_append = "_Remuxed",
    
    accurate_cut = true,
    lossless_cut = false, 
    crf = 30,
    preset = 4,
    combine_audio = false,
    trash_original = true,
    
    show_stats_screen = true,
    stats_osd_time = 8
}
options.read_options(opts, "tachytome")

local custom_output_name = ""

-- =========================================================
-- INITIALIZATION
-- =========================================================
local platform = common.get_platform()
local ffmpeg_ok, ffmpeg_path = common.check_ffmpeg(platform)
if not ffmpeg_ok then common.notify("ffmpeg NOT found", true, "error") end
local trash_ok, trash_path = common.check_trash(platform)
if not trash_ok then common.notify("trash utility NOT found", true, "error") end

local mark_in = 0
local mark_out = mp.get_property_number("duration", 0)

-- This is now the ONLY place where variables are reset
mp.register_event("file-loaded", function()
    mark_in = 0
    mark_out = mp.get_property_number("duration", 0)
    custom_output_name = ""
end)

local function mark(place)
    local time = mp.get_property_number("time-pos", 0)
    if place == 0 then
        mark_in = time
        common.notify("In: " .. string.format("%.3f", time), true)
    elseif place == 1 then
        mark_out = time
        common.notify("Out: " .. string.format("%.3f", time), true)
    end
end

-- =========================================================
-- KEYBINDS
-- =========================================================
mp.add_key_binding("ESC", "clear-osd", function()
    mp.set_osd_ass(0, 0, "") 
    mp.osd_message("", 0)
    mp.commandv("set", "fullscreen", "no")
end)

mp.add_key_binding("ctrl+i", "mark-in",  function() mark(0) end)
mp.add_key_binding("ctrl+o", "mark-out", function() mark(1) end)

mp.add_key_binding("ctrl+l", "toggle-lossless", function()
    opts.lossless_cut = not opts.lossless_cut
    common.notify("Lossless Cut: " .. (opts.lossless_cut and "ON" or "OFF"), true)
end)

mp.add_key_binding("ctrl+a", "toggle-combine-audio", function()
    opts.combine_audio = not opts.combine_audio
    common.notify("Combine Audio: " .. (opts.combine_audio and "ON" or "OFF"), true)
end)

mp.add_key_binding("ctrl+t", "toggle-trash", function()
    opts.trash_original = not opts.trash_original
    common.notify("Trash Original: " .. (opts.trash_original and "ON" or "OFF"), true)
end)

mp.add_key_binding("ctrl+DEL", "trash-current", function()
    local current_file = mp.get_property("path")
    if not current_file then return common.notify("No video loaded", true, "error") end
    if not trash_path then return common.notify("Trash utility not found", true, "error") end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    local ov = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("del-y")
        mp.remove_key_binding("del-n")
        mp.remove_key_binding("del-enter")
        mp.remove_key_binding("del-esc")
    end

    ov.data = string.format("{\\an7}{\\c&H0000FF&}Warning: Move current file to trash?{\\c&HFFFFFF&}\\N%s\\N\\N[y / Enter] Yes\\N[n / Esc] No", current_file)
    ov:update()

    local function confirm_trash()
        cleanup()
        common.trash_file(current_file, trash_path, function(success)
            if success then
                common.notify("Trashed original video", true)
            else
                common.notify("Failed to trash video (File may be in use)", true, "error")
            end
        end)
    end

    local function cancel_trash()
        cleanup()
        common.notify("Trashing cancelled.", true)
    end

    mp.add_forced_key_binding("y", "del-y", confirm_trash)
    mp.add_forced_key_binding("ENTER", "del-enter", confirm_trash)
    
    mp.add_forced_key_binding("n", "del-n", cancel_trash)
    mp.add_forced_key_binding("ESC", "del-esc", cancel_trash)
end)

mp.add_key_binding("ctrl+s", "show-stats", function()
    local msg_console = "Tachytome Lifetime Stats\n--------------------------\n" .. stats.get_lifetime_stats_string()
    local msg_osd = "{\\an7}" .. msg_console:gsub("\n", "\\N")
    
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    mp.set_osd_ass(0, 0, msg_osd)
    mp.add_timeout(opts.stats_osd_time, function() mp.set_osd_ass(0, 0, "") end)
end)

mp.add_key_binding("ctrl+q", "input-crf", function()
    osd_input.get_user_input("CRF (0-63): ", function(input)
        local num = tonumber(input)
        if num and num >= 0 and num <= 63 then
            opts.crf = num
            common.notify("CRF: " .. opts.crf, true)
        else
            common.notify("Invalid CRF, keeping: " .. opts.crf, true, "warn")
        end
    end, tostring(opts.crf), true) 
end)

mp.add_key_binding("ctrl+n", "input-name", function()
    local display_path = custom_output_name ~= "" and custom_output_name or common.resolve_absolute_path("", opts)

    osd_input.get_user_input("Output Name/Path: ", function(input)
        if input ~= "" then
            custom_output_name = common.resolve_absolute_path(input, opts)
            common.notify("Target: " .. custom_output_name, true)
        else
            custom_output_name = ""
            common.notify("Output path reset to default", true)
        end
    end, display_path, true)
end)

mp.add_key_binding("ctrl+shift+s", "cancel-render", function()
    render.cancel_render()
end)

mp.add_key_binding("ctrl+ENTER", "start-render", function()
    local final_output = custom_output_name ~= "" and custom_output_name or common.resolve_absolute_path("", opts)
    
    render.start({
        final_output_path = final_output,
        mark_in = mark_in,
        mark_out = mark_out,
        full_input_duration = mp.get_property_number("duration", 0),
        accurate_cut = opts.accurate_cut,
        lossless_cut = opts.lossless_cut,
        crf = opts.crf,
        preset = opts.preset,
        combine_audio = opts.combine_audio,
        trash_original = opts.trash_original,
        trash_path = trash_path,
        overwrite_append = opts.overwrite_append,
        show_stats_screen = opts.show_stats_screen,
        stats_osd_time = opts.stats_osd_time
    })
end)
