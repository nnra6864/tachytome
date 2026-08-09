local mp    = require 'mp'
local utils = require 'mp.utils'

local M = {}

function M.get_platform()
    local is_windows = package.config:sub(1,1) == '\\'
    if is_windows then return "windows" end
    local uname = utils.subprocess({args = {"uname", "-s"}, cancellable = false})
    if uname.status == 0 and uname.stdout:match("Darwin") then return "macos" end
    return "linux"
end

function M.get_data_dir()
    local platform = M.get_platform()
    local path = ""

    if platform == "windows" then
        path = os.getenv("LOCALAPPDATA") or ""
        if path == "" then path = os.getenv("APPDATA") or "" end
        if path == "" then path = (os.getenv("USERPROFILE") or "") .. "\\AppData\\Local" end
        path = utils.join_path(path, "tachytome")
    elseif platform == "macos" then
        path = utils.join_path(os.getenv("HOME") or "~", "Library/Application Support/tachytome")
    else
        path = os.getenv("XDG_DATA_HOME") or ""
        if path == "" then
            path = utils.join_path(os.getenv("HOME") or "~", ".local/share")
        end
        path = utils.join_path(path, "tachytome")
    end

    path = M.expand_path(path)
    M.ensure_dir(path)
    return path
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
        return M.check_cmd({"which", "ffmpeg"})
    end
end

function M.check_trash(platform)
    if platform == "windows" or platform == "macos" then
        return true, "native"
    elseif platform == "linux" then
        if M.check_cmd({"which", "gio"}) then return true, "gio trash" end
        if M.check_cmd({"which", "trash-put"}) then return true, "trash-put" end
        if M.check_cmd({"which", "trash"}) then return true, "trash" end
    end
    return false, nil
end

function M.ffprobe_get_json(file, args)
    local cmd = {"ffprobe", "-v", "error"}
    for _, v in ipairs(args) do table.insert(cmd, v) end
    table.insert(cmd, file)
    local res = utils.subprocess({args = cmd, cancellable = false})
    if res.status == 0 and res.stdout then
        return utils.parse_json(res.stdout)
    end
    return nil
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

    local base_output_dir = (opts.output_dir == "") and input_dir or M.expand_path(opts.output_dir)
    if not base_output_dir:match("[/\\]$") then base_output_dir = base_output_dir .. "/" end

    if not custom or custom == "" then
        return utils.join_path(base_output_dir, (base_name .. opts.suffix):gsub(" ", opts.space_replacement) .. default_ext)
    end

    local custom_mod = custom
    local explicit_relative = false

    if custom_mod:match("^%./") or custom_mod:match("^%.\\") then
        custom_mod        = input_dir .. custom_mod:sub(3)
        explicit_relative = true
    end

    local target_dir, target_name
    if custom_mod:match("[/\\]") then
        target_dir, target_name = custom_mod:match("^(.*[/\\])([^/\\]*)$")
    else
        target_dir = ""
        target_name = custom_mod
    end

    local function is_absolute(p) return p:match("^/") or p:match("^%a:[/\\]") or p:match("^~") end

    if target_dir == "" then
        target_dir = base_output_dir
    elseif not is_absolute(target_dir) and not explicit_relative then
        target_dir = base_output_dir .. target_dir
    end

    target_dir = M.expand_path(target_dir)
    if not target_dir:match("[/\\]$") then target_dir = target_dir .. "/" end

    if target_name == "" then
        target_name = base_name .. opts.suffix .. default_ext
    else
        local known_exts = {
            [".mkv"]=true, [".mp4"]= true, [".webm"]=true, [".avi"]=true,
            [".mov"]=true, [".m4v"]= true, [".ts"]=  true, [".flv"]=true,
            [".wmv"]=true, [".mp3"]= true, [".ogg"]= true, [".aac"]=true,
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
    if not bytes or bytes == 0 then return "0B" end
    if bytes < 1024 then return bytes .. "B" end
    if bytes < 1048576 then return string.format("%.2fKB", bytes / 1024) end
    if bytes < 1073741824 then return string.format("%.2fMB", bytes / 1048576) end
    return string.format("%.2fGB", bytes / 1073741824)
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
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
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
    if not file_path then
        if callback then callback(false) end
        return
    end

    local platform = M.get_platform()
    local args = {}

    if platform == "windows" then
        local escaped_path = file_path:gsub("'", "''")
        local ps_cmd = string.format("Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s', 'OnlyErrorDialogs', 'SendToRecycleBin')", escaped_path)
        args = {"powershell", "-NoProfile", "-Command", ps_cmd}
    elseif platform == "macos" then
        local escaped_path = file_path:gsub('"', '\\"')
        local osa_cmd = string.format('tell application "Finder" to delete POSIX file "%s"', escaped_path)
        args = {"osascript", "-e", osa_cmd}
    else
        if not trash_path then
            if callback then callback(false) end return
        end
        if trash_path == "gio trash" then
            args = {"gio", "trash", file_path}
        else
            args = {trash_path, file_path}
        end
    end

    mp.command_native_async({
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        local is_success = (result and result.status == 0)
        if callback then callback(is_success) end
    end)
end

function M.get_history_path()
    return utils.join_path(M.get_data_dir(), "history.json")
end

function M.read_history()
    local f = io.open(M.get_history_path(), "r")
    if f then
        local content = f:read("*all")
        f:close()
        local parsed = utils.parse_json(content)
        if type(parsed) == "table" then return parsed end
    end
    return {}
end

function M.add_to_history(history_table, input)
    if history_table[#history_table] == input then return end
    table.insert(history_table, input)
    while #history_table > 100 do
        table.remove(history_table, 1)
    end
end

function M.save_history(history_table)
    local f = io.open(M.get_history_path(), "w")
    if f then
        f:write(utils.format_json(history_table))
        f:close()
    end
end

return M
