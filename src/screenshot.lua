local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local state  = require 'src.state'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local platform   = common.get_platform()
local temp_count = 0

M.formats = { "png", "jpg", "webp", "jxl", "avif" }

local linux_copy = [[
if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null; then wl-copy -t image/png < "$1"
elif command -v xclip >/dev/null; then xclip -selection clipboard -t image/png -i "$1"
else exit 127; fi >/dev/null 2>&1
]]

local function copy_args(path)
    if platform == "windows" then
        local ps_cmd = string.format("Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $i = [System.Drawing.Image]::FromFile('%s'); [System.Windows.Forms.Clipboard]::SetImage($i); $i.Dispose()", (path:gsub("'", "''")))
        return {"powershell", "-NoProfile", "-STA", "-Command", ps_cmd}
    elseif platform == "macos" then
        return {"osascript", "-e", "on run argv", "-e", "set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)", "-e", "end run", path}
    end
    return {"sh", "-c", linux_copy, "sh", path}
end

local function file_name(time)
    local replacement = state.opts.space_replacement
    if replacement:find("%s") then replacement = "_" end
    local name  = mp.get_property("filename/no-ext") or "screenshot"
    local stamp = common.format_time(time):gsub(":", "-")
    name = name:gsub("[\\/:*?\"'`<>|()%[%]{}$&;!#~]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", (replacement:gsub("%%", "%%%%")))
    if name == "" then name = "screenshot" end
    return name .. (replacement ~= "" and replacement or "_") .. stamp
end

local function save_path(time, format)
    local dir  = state.opts.screenshot_dir
    local name = file_name(time)
    local ext  = "." .. format
    if dir ~= "" and not dir:match("[/\\]$") then dir = dir .. "/" end
    local base = common.resolve_absolute_path(dir .. name, state.opts, ext):sub(1, -#ext - 1)
    local path = base .. ext
    local n    = 1
    while common.file_exists(path) do
        n    = n + 1
        path = base .. "_" .. n .. ext
    end
    return path
end

local function temp_path()
    temp_count     = temp_count + 1
    local temp_dir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return utils.join_path(temp_dir, string.format("tachytome_shot_%d_%d.png", mp.get_property_number("pid", 0), temp_count))
end

local function get_format()
    local format = state.opts.screenshot_format:lower()
    if format == "jpeg" then return "jpg" end
    for _, f in ipairs(M.formats) do
        if f == format then return f end
    end
    notify.show(lang.t("value_invalid", { label = "screenshot_format", value = state.opts.screenshot_format }), true, "warn")
    return "png"
end

local function copy(path, temp, saved)
    mp.command_native_async({
        name           = "subprocess",
        args           = copy_args(path),
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        if temp then os.remove(path) end
        local shown = saved and common.display_path(saved, mp.get_property("path")) or nil
        if result and result.status == 0 then
            notify.show(lang.t(saved and "screenshot_saved" or "screenshot_copied", { path = shown }), true)
            return
        end
        local key = (result and result.status == 127 and platform == "linux") and "screenshot_no_tool" or "screenshot_copy_failed"
        notify.show(lang.t(key .. (saved and "_saved" or ""), { path = shown }), true, "warn")
        if result and result.stderr and result.stderr ~= "" then print(result.stderr) end
        if error then print(error) end
    end)
end

local function to_png(saved)
    local temp = temp_path()
    mp.command_native_async({
        name           = "subprocess",
        args           = {"ffmpeg", "-v", "error", "-y", "-i", saved, "-frames:v", "1", "-update", "1", temp},
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        if result and result.status == 0 then return copy(temp, true, saved) end
        os.remove(temp)
        notify.show(lang.t("screenshot_copy_failed_saved", { path = common.display_path(saved, mp.get_property("path")) }), true, "warn")
        if result and result.stderr and result.stderr ~= "" then print(result.stderr) end
        if error then print(error) end
    end)
end

function M.take()
    if not mp.get_property("path") then return notify.show(lang.t("no_video"), true, "warn") end
    local format = get_format()
    local saved  = state.opts.screenshot_save and save_path(mp.get_property_number("time-pos", 0), format) or nil
    local path   = saved or temp_path()
    if saved then common.ensure_dir((utils.split_path(saved))) end
    mp.command_native_async({
        name     = "screenshot-to-file",
        filename = path,
        flags    = state.opts.screenshot_subtitles and "subtitles" or "video"
    }, function(success, result, error)
        if not success then
            if not saved then os.remove(path) end
            notify.show(lang.t(saved and format ~= "png" and "screenshot_save_failed" or "screenshot_failed", { format = format }), true, "error")
            if error then print(error) end
            return
        end
        if saved and format ~= "png" then return to_png(saved) end
        copy(path, not saved, saved)
    end)
end

return M
