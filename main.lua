local mp = require 'mp'

local script_dir = mp.get_script_directory()
if script_dir then package.path = package.path .. ";" .. script_dir .. "/src/?.lua" end

local common     = require 'src.common'
local state      = require 'src.state'
local menu       = require 'src.menu'
local notify     = require 'src.notify'
local ui_confirm = require 'src.ui_confirm'

local platform             = common.get_platform()
local trash_ok, trash_path = common.check_trash(platform)
state.trash_path           = trash_path
state.ffmpeg_ok            = common.check_ffmpeg(platform)

local function check_dependencies()
    if state.ffmpeg_ok then return end

    if platform == "linux" then
        notify.show("FFmpeg Missing! Please install it via your package manager.", true, "error")
        return
    end

    ui_confirm.show("FFmpeg is missing!", "Would you like to install it automatically?", function()
        notify.show("Installing FFmpeg... Please wait (this may take a few minutes).", true)
        local args = {}
        if platform == "windows" then
            args = {"cmd", "/c", "winget install ffmpeg --accept-package-agreements --accept-source-agreements"}
        elseif platform == "macos" then
            args = {"sh", "-c", "brew install ffmpeg"}
        end
        mp.command_native_async({
            name = "subprocess",
            args = args,
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true
        }, function(success, result, error)
            if result and result.status == 0 then
                notify.show("FFmpeg installed successfully! Please restart MPV.", true)
            else
                notify.show("Install failed. Check logs and install manually.", true, "error")
                print(result and result.stderr or error)
            end
        end)
    end, function()
        notify.show("FFmpeg install skipped. Tachytome will not work.", true, "warn")
    end)
end

check_dependencies()

mp.register_event("file-loaded", function()
    state.mark_in = 0
    state.mark_out = mp.get_property_number("duration", 0)
    state.custom_output_name = ""
    menu.refresh()
end)

mp.add_key_binding("ESC", "clear-osd", function()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    mp.commandv("set", "fullscreen", "no")
end)

mp.add_key_binding("t", "tachytome-menu", menu.open)
