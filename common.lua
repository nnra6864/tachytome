local mp = require 'mp'
local utils = require 'mp.utils'

local M = {}

function M.notify(msg, show_osd, type)
    if type == "warn" then
        mp.msg.warn(msg)
    elseif type == "error" then
        mp.msg.error(msg)
    else
        mp.msg.info(msg)
    end
    if show_osd then
        mp.set_osd_ass(0, 0, "") -- Prevents overlapping by clearing stats screens
        mp.osd_message(msg, 3)
    end
end

function M.get_platform()
    local is_windows = package.config:sub(1,1) == '\\'
    if is_windows then return "windows" end
    local uname = utils.subprocess({args = {"uname", "-s"}, cancellable = false})
    if uname.status == 0 and uname.stdout:match("Darwin") then return "macos" end
    return "linux"
end

function M.expand_path(path)
    if not path then return "" end
    if path:match("^~") then
        local home = M.get_platform() == "windows" and os.getenv("USERPROFILE") or os.getenv("HOME")
        return path:gsub("^~", home or "~")
    end
    return path
end

function M.check_cmd(args)
    local res = utils.subprocess({args = args, cancellable = false})
    if res.status == 0 and res.stdout and res.stdout:match("%S") then
        return true, res.stdout:gsub("[\r\n]+$", "")
    end
    return false, nil
end

function M.check_ffmpeg(platform)
    if platform == "windows" then
        return M.check_cmd({"cmd", "/c", "where", "ffmpeg"})
    else
        return M.check_cmd({"sh", "-c", "command -v ffmpeg"})
    end
end

function M.check_trash(platform)
    if platform == "linux" then
        return M.check_cmd({"sh", "-c", "command -v trash-put"})
    elseif platform == "windows" then
        return M.check_cmd({"powershell", "-NoProfile", "-Command", "Get-Command -Name trash -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source"})
    elseif platform == "macos" then
        return M.check_cmd({"sh", "-c", "command -v trash"})
    end
    return false, nil
end

function M.ensure_dir(path)
    local platform = M.get_platform()
    if platform == "windows" then
        utils.subprocess({args = {"powershell", "-NoProfile", "-Command", "New-Item -ItemType Directory -Force -Path '" .. path:gsub("'", "''") .. "'"}, cancellable = false})
    else
        utils.subprocess({args = {"mkdir", "-p", path}, cancellable = false})
    end
end

function M.resolve_absolute_path(custom, opts)
    local input_path = mp.get_property("path")
    if not input_path then return "" end
    
    local input_dir = utils.split_path(input_path)
    local base_name = mp.get_property("filename/no-ext") or ""
    
    local default_ext = opts.container ~= "" and opts.container or (mp.get_property("filename"):match("^.+(%..+)$") or ".mkv")
    if default_ext:sub(1,1) ~= "." then default_ext = "." .. default_ext end

    if not custom or custom == "" then
        local base = (opts.output_dir == "") and input_dir or M.expand_path(opts.output_dir)
        if not base:match("[/\\]$") then base = base .. "/" end
        return utils.join_path(base, (base_name .. opts.suffix):gsub(" ", opts.space_replacement) .. default_ext)
    end

    local custom_mod = custom
    if custom_mod:match("^%./") then
        custom_mod = input_dir .. custom_mod:sub(3)
    end

    local target_dir, target_name
    if custom_mod:match("[/\\]") then
        target_dir, target_name = custom_mod:match("^(.*[/\\])([^/\\]*)$")
    else
        target_dir = (opts.output_dir == "") and input_dir or M.expand_path(opts.output_dir)
        target_name = custom_mod
    end

    target_dir = M.expand_path(target_dir)
    if not target_dir:match("[/\\]$") then target_dir = target_dir .. "/" end
    
    if target_name == "" then 
        target_name = base_name .. opts.suffix .. default_ext
    else
        local known_exts = {
            [".mkv"]=true, [".mp4"]=true, [".webm"]=true, [".avi"]=true,
            [".mov"]=true, [".m4v"]=true, [".ts"]=true, [".flv"]=true,
            [".wmv"]=true, [".mp3"]=true, [".ogg"]=true, [".aac"]=true,
            [".mka"]=true, [".opus"]=true
        }
        local user_ext = target_name:match("(%.[a-zA-Z0-9]+)$")
        if not (user_ext and known_exts[user_ext:lower()]) then
            target_name = target_name .. default_ext
        end
    end
    target_name = target_name:gsub(" ", opts.space_replacement)

    return utils.join_path(target_dir, target_name)
end

function M.format_bytes(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    if bytes < 1024 then return bytes .. " B" end
    if bytes < 1048576 then return string.format("%.2f KB", bytes / 1024) end
    if bytes < 1073741824 then return string.format("%.2f MB", bytes / 1048576) end
    return string.format("%.2f GB", bytes / 1073741824)
end

function M.format_time(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%06.3f", h, m, s)
end

function M.format_duration(seconds)
    if not seconds or seconds == 0 then return "0s" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

function M.ffprobe_get(file, args)
    local cmd = {"ffprobe", "-v", "error"}
    for _, v in ipairs(args) do table.insert(cmd, v) end
    table.insert(cmd, file)
    local res = utils.subprocess({args = cmd, cancellable = false})
    if res.status == 0 and res.stdout then
        local clean = res.stdout:gsub("[\r\n]+$", "")
        if clean ~= "" then return clean end
    end
    return nil
end

function M.trash_file(file_path, trash_path, callback)
    if not file_path or not trash_path then
        if callback then callback(false) end
        return
    end
    
    mp.command_native_async({
        name = "subprocess",
        args = {trash_path, file_path},
        playback_only = false
    }, function(success, result, error)
        local is_success = (result and result.status == 0)
        if callback then callback(is_success) end
    end)
end

return M
