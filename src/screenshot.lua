local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local conf   = require 'src.conf'
local state  = require 'src.state'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local platform   = common.get_platform()
local temp_count = 0
local active     = 0
local originals  = {}

M.formats = { "png", "jpg", "webp", "jxl", "avif" }

local mimes = {
    png  = "image/png",
    jpg  = "image/jpeg",
    webp = "image/webp",
    jxl  = "image/jxl",
    avif = "image/avif"
}

local mac_classes = {
    png = "«class PNGf»",
    jpg = "«class JPEG»"
}

local windows_formats = {
    png = true,
    jpg = true
}

local encoder_options = {
    "screenshot_tag_colorspace",
    "screenshot_high_bit_depth",
    "screenshot_jpeg_quality",
    "screenshot_jpeg_source_chroma",
    "screenshot_png_compression",
    "screenshot_png_filter",
    "screenshot_webp_lossless",
    "screenshot_webp_quality",
    "screenshot_webp_compression",
    "screenshot_jxl_distance",
    "screenshot_jxl_effort",
    "screenshot_avif_encoder",
    "screenshot_avif_pixfmt",
    "screenshot_avif_opts",
    "screenshot_sw"
}

local linux_copy = [[
if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null; then wl-copy -t "$2" < "$1"
elif command -v xclip >/dev/null; then xclip -selection clipboard -t "$2" -i "$1"
else exit 127; fi >/dev/null 2>&1
]]

local function property(key)
    return (key:gsub("_", "-"))
end

local function apply_options()
    if active == 0 then
        for _, key in ipairs(encoder_options) do originals[key] = mp.get_property(property(key)) end
    end
    active = active + 1
    for _, key in ipairs(encoder_options) do
        local value = conf.format(state.opts[key])
        if not mp.set_property(property(key), value) then
            notify.show(lang.t("value_invalid", { label = key, value = value }), true, "warn")
        end
    end
end

local function restore_options()
    active = active - 1
    if active > 0 then return end
    for _, key in ipairs(encoder_options) do
        if originals[key] then mp.set_property(property(key), originals[key]) end
    end
    originals = {}
end

local function can_copy(format)
    if platform == "windows" then return windows_formats[format] == true end
    if platform == "macos" then return mac_classes[format] ~= nil end
    return true
end

local function copy_args(path, format)
    if platform == "windows" then
        local ps_cmd = string.format("Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $i = [System.Drawing.Image]::FromFile('%s'); [System.Windows.Forms.Clipboard]::SetImage($i); $i.Dispose()", (path:gsub("'", "''")))
        return {"powershell", "-NoProfile", "-STA", "-Command", ps_cmd}
    elseif platform == "macos" then
        return {"osascript", "-e", "on run argv", "-e", "set the clipboard to (read (POSIX file (item 1 of argv)) as " .. mac_classes[format] .. ")", "-e", "end run", path}
    end
    return {"sh", "-c", linux_copy, "sh", path, mimes[format]}
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
    local ext  = "." .. format
    if dir ~= "" and not dir:match("[/\\]$") then dir = dir .. "/" end
    local base = common.resolve_absolute_path(dir .. file_name(time), state.opts, ext):sub(1, -#ext - 1)
    local path = base .. ext
    local n    = 1
    while common.file_exists(path) do
        n    = n + 1
        path = base .. "_" .. n .. ext
    end
    return path
end

local function temp_path(format)
    temp_count     = temp_count + 1
    local temp_dir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    return utils.join_path(temp_dir, string.format("tachytome_shot_%d_%d.%s", mp.get_property_number("pid", 0), temp_count, format))
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

local function copy(path, saved, format)
    local shown = saved and common.display_path(path, mp.get_property("path")) or nil
    if not can_copy(format) then
        return notify.show(lang.t("screenshot_cant_copy_saved", { format = format, path = shown }), true, "warn")
    end
    mp.command_native_async({
        name           = "subprocess",
        args           = copy_args(path, format),
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        if not saved then os.remove(path) end
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

function M.take()
    if not mp.get_property("path") then return notify.show(lang.t("no_video"), true, "warn") end
    local format = get_format()
    local saved  = state.opts.screenshot_save
    if not saved and not can_copy(format) then
        return notify.show(lang.t("screenshot_cant_copy", { format = format }), true, "warn")
    end
    local path = saved and save_path(mp.get_property_number("time-pos", 0), format) or temp_path(format)
    if saved then common.ensure_dir((utils.split_path(path))) end
    apply_options()
    mp.command_native_async({
        name     = "screenshot-to-file",
        filename = path,
        flags    = state.opts.screenshot_subtitles and "subtitles" or "video"
    }, function(success, result, error)
        restore_options()
        if not success then
            if not saved then os.remove(path) end
            notify.show(lang.t("screenshot_failed", { format = format }), true, "error")
            if error then print(error) end
            return
        end
        copy(path, saved, format)
    end)
end

return M
