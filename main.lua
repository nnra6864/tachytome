local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local common = require 'common'
local osd_input = require 'osd_input'
local render = require 'render'
local stats = require 'stats'

local opts = {
    output_dir = "", 
    space_replacement = "_",
    container = "mkv",
    suffix = " Remuxed",
    conflict_suffix = " Remuxed",
    accurate_cut = true,
    lossless_cut = false, 
    crf = 30,
    preset = 4,
    combine_audio = false,
    combined_audio_name = "Combined",
    trash_original = true,
    show_stats_screen = true,
    stats_osd_time = 8
}
options.read_options(opts, "tachytome")

local custom_output_name = ""
local platform = common.get_platform()
local trash_ok, trash_path = common.check_trash(platform)
local ffmpeg_ok, ffmpeg_path = common.check_ffmpeg(platform)

if not ffmpeg_ok then 
    if platform == "linux" then
        common.notify("FFmpeg Missing! Please install it via your package manager.", true, "error")
    else
        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)
        local ov = mp.create_osd_overlay("ass-events")
        local active = true

        local function cleanup()
            if not active then return end
            active = false
            ov:remove()
            mp.remove_key_binding("inst-y")
            mp.remove_key_binding("inst-n")
            mp.remove_key_binding("inst-enter")
            mp.remove_key_binding("inst-esc")
        end

        ov.data = "{\\an7}{\\c&H0000FF&}Warning: FFmpeg is missing!{\\c&HFFFFFF&}\\NWould you like to install it automatically?\\N\\N[y / Enter] Yes\\N[n / Esc] No"
        ov:update()

        local function confirm_install()
            cleanup()
            common.notify("Installing FFmpeg... Please wait (this may take a few minutes).", true)
            local args = {}
            if platform == "windows" then
                args = {"cmd", "/c", "winget install ffmpeg --accept-package-agreements --accept-source-agreements"}
            elseif platform == "macos" then
                args = {"sh", "-c", "brew install ffmpeg"}
            end
            mp.command_native_async({ name = "subprocess", args = args, playback_only = false }, function(success, result, error)
                if result and result.status == 0 then common.notify("FFmpeg installed successfully! Please restart MPV.", true)
                else
                    common.notify("Install failed. Check console and install manually.", true, "error")
                    print(result and result.stderr or error)
                end
            end)
        end

        local function cancel_install()
            cleanup()
            common.notify("FFmpeg install skipped. Tachytome will not work.", true, "warn")
        end

        mp.add_forced_key_binding("y", "inst-y", confirm_install)
        mp.add_forced_key_binding("ENTER", "inst-enter", confirm_install)
        mp.add_forced_key_binding("n", "inst-n", cancel_install)
        mp.add_forced_key_binding("ESC", "inst-esc", cancel_install)
    end
end

local mark_in = 0
local mark_out = mp.get_property_number("duration", 0)

mp.register_event("file-loaded", function()
    mark_in = 0
    mark_out = mp.get_property_number("duration", 0)
    custom_output_name = ""
end)

local function mark(place)
    local time = mp.get_property_number("time-pos", 0)
    if place == 0 then
        mark_in = time
        common.notify("In: " .. common.format_time(time), true)
    elseif place == 1 then
        mark_out = time
        common.notify("Out: " .. common.format_time(time), true)
    end
end

mp.add_key_binding("ESC", "clear-osd", function()
    mp.set_osd_ass(0, 0, "") 
    mp.osd_message("", 0)
    mp.commandv("set", "fullscreen", "no")
end)

-- =========================================================
-- UNIFIED MENU LAYER SYSTEM
-- =========================================================
local menu_active = false
local menu_overlay = mp.create_osd_overlay("ass-events")

local function close_menu()
    if not menu_active then return end
    menu_active = false
    menu_overlay:remove()
    local keys = {"i","o","c","l","a","t","q","n","s","x","DEL","ENTER","ESC"}
    for _, k in ipairs(keys) do mp.remove_key_binding("menu-"..k) end
end

local function open_menu()
    if menu_active then close_menu() return end
    menu_active = true
    
    mp.set_osd_ass(0, 0, "") 
    mp.osd_message("", 0)

    local function update_menu()
        -- \an5 centers the overlay (num-pad positioning)
        -- \fnmonospace forces a fixed-width font so your columns align perfectly!
        local text = "{\\an7}{\\fnmonospace}{\\fs18}{\\b1}Tachytome Dashboard{\\b0}\\N\\N"
        local display_name = custom_output_name ~= "" and custom_output_name or "Default"

        local function r(val) return string.format("{\\c&H0000FF&}%s{\\c&HFFFFFF&}", tostring(val)) end
        local function g(val) return string.format("{\\c&H00FF00&}%s{\\c&HFFFFFF&}", tostring(val)) end
        local function b(val) return string.format("{\\c&HFF0000&}%s{\\c&HFFFFFF&}", tostring(val)) end
        local function w(val) return string.format("{\\c&HFFFFFF&}%s{\\c&HFFFFFF&}", tostring(val)) end

        text = text .. string.format("[ i ] Mark In       %s\\N", g(common.format_time(mark_in)))
        text = text .. string.format("[ o ] Mark Out      %s\\N", g(common.format_time(mark_out)))
        text = text .. "\\N"
        text = text .. string.format("[ c ] Accurate Cut  %s\\N", opts.accurate_cut and g("ON") or r("OFF"))
        text = text .. string.format("[ l ] Lossless Cut  %s\\N", opts.lossless_cut and g("ON") or r("OFF"))
        text = text .. string.format("[ a ] Combine Audio %s\\N", opts.combine_audio and g("ON") or r("OFF"))
        text = text .. string.format("[ t ] Trash Source  %s\\N", opts.trash_original and g("ON") or r("OFF"))
        text = text .. string.format("[ q ] Set CRF       %s\\N", g(opts.crf))
        text = text .. string.format("[ n ] Set Output    %s\\N", g(display_name))
        text = text .. "\\N"
        text = text .. "[ x ]   Manage Render Queue\\N"
        text = text .. "[ DEL ] Move Source to Trash\\N"
        text = text .. "[ ENT ] Start Render\\N"
        text = text .. "[ s ]   Show Lifetime Stats\\N"
        text = text .. "\\N"
        text = text .. "[ ESC ] Close Menu"

        menu_overlay.data = text
        menu_overlay:update()
    end

    update_menu()

    local function bind(key, func, stay_open)
        mp.add_forced_key_binding(key, "menu-"..key, function()
            if not stay_open then close_menu() end
            func()
            if stay_open and menu_active then update_menu() end
        end)
    end

    bind("i", function() mark(0) end, false)
    bind("o", function() mark(1) end, false)
    
    bind("c", function() opts.accurate_cut = not opts.accurate_cut end, true)
    bind("l", function() opts.lossless_cut = not opts.lossless_cut end, true)
    bind("a", function() opts.combine_audio = not opts.combine_audio end, true)
    bind("t", function() opts.trash_original = not opts.trash_original end, true)

    bind("q", function()
        osd_input.get_user_input("CRF (0-63): ", function(input)
            local num = tonumber(input)
            if num and num >= 0 and num <= 63 then
                opts.crf = num
                common.notify("CRF: " .. opts.crf, true)
            else
                common.notify("Invalid CRF, keeping: " .. opts.crf, true, "warn")
            end
        end, tostring(opts.crf), true) 
    end, false)

    bind("n", function()
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
    end, false)

    bind("s", function()
        local msg_console = "Tachytome Lifetime Stats\n--------------------------\n" .. stats.get_lifetime_stats_string()
        local msg_osd = "{\\an7}" .. msg_console:gsub("\n", "\\N")
        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)
        mp.set_osd_ass(0, 0, msg_osd)
        mp.add_timeout(opts.stats_osd_time, function() mp.set_osd_ass(0, 0, "") end)
    end, false)

    bind("x", function() render.show_queue_manager() end, false)

    bind("DEL", function()
        local current_file = mp.get_property("path")
        if not current_file then return common.notify("No video loaded", true, "error") end
        if not trash_path then return common.notify("Trash utility not found", true, "error") end

        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)
        local ov = mp.create_osd_overlay("ass-events")
        local active = true

        local function cleanup_trash()
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
            cleanup_trash()
            common.trash_file(current_file, trash_path, function(success)
                if success then common.notify("Trashed original video", true)
                else common.notify("Failed to trash video (File may be in use)", true, "error") end
            end)
        end
        local function cancel_trash()
            cleanup_trash()
            common.notify("Trashing cancelled.", true)
        end

        mp.add_forced_key_binding("y", "del-y", confirm_trash)
        mp.add_forced_key_binding("ENTER", "del-enter", confirm_trash)
        mp.add_forced_key_binding("n", "del-n", cancel_trash)
        mp.add_forced_key_binding("ESC", "del-esc", cancel_trash)
    end, false)

    bind("ENTER", function()
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
            combined_audio_name = opts.combined_audio_name,
            trash_original = opts.trash_original,
            trash_path = trash_path,
            space_replacement = opts.space_replacement,
            conflict_suffix = opts.conflict_suffix,
            show_stats_screen = opts.show_stats_screen,
            stats_osd_time = opts.stats_osd_time
        })
        custom_output_name = "" 
    end, false)

    bind("ESC", function() end, false)
end

mp.add_key_binding("ctrl+t", "tachytome-menu", open_menu)
