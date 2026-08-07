local mp     = require 'mp'
local common = require 'common'
local state  = require 'state'
local menu   = require 'menu'

local platform             = common.get_platform()
local trash_ok, trash_path = common.check_trash(platform)
state.trash_path           = trash_path
state.ffmpeg_ok            = common.check_ffmpeg(platform)

local function check_dependencies()
    if state.ffmpeg_ok then return end

    if platform == "linux" then
        common.notify("FFmpeg Missing! Please install it via your package manager.", true, "error")
        return
    end

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
            if result and result.status == 0 then
                common.notify("FFmpeg installed successfully! Please restart MPV.", true)
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

    mp.add_forced_key_binding("y",     "inst-y",     confirm_install)
    mp.add_forced_key_binding("ENTER", "inst-enter", confirm_install)
    mp.add_forced_key_binding("n",     "inst-n",     cancel_install)
    mp.add_forced_key_binding("ESC",   "inst-esc",   cancel_install)
end

check_dependencies()

mp.register_event("file-loaded", function()
    state.mark_in = 0
    state.mark_out = mp.get_property_number("duration", 0)
    state.custom_output_name = ""
end)

mp.add_key_binding("ESC", "clear-osd", function()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    mp.commandv("set", "fullscreen", "no")
end)

mp.add_key_binding("ctrl+t", "tachytome-menu", menu.open)
