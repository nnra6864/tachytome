local mp    = require 'mp'
local utils = require 'mp.utils'

local M = {}

local keyframe_cache     = {}
local keyframe_pending   = {}
local keyframe_listeners = {}
local keyframe_window    = 60
local interval_cache     = {}
local interval_pending   = {}
local interval_query     = {"-select_streams", "v:0", "-read_intervals", "%+60", "-show_entries", "packet=pts_time,flags", "-of", "csv=p=0"}
local cached_platform    = nil
local cached_state_dir   = nil

function M.get_platform()
    if cached_platform then return cached_platform end
    local is_windows = package.config:sub(1,1) == '\\'
    if is_windows then
        cached_platform = "windows"
    else
        local uname = utils.subprocess({args = {"uname", "-s"}, cancellable = false})
        if uname.status == 0 and uname.stdout and uname.stdout:match("Darwin") then
            cached_platform = "macos"
        else
            cached_platform = "linux"
        end
    end
    return cached_platform
end

function M.get_state_dir()
    if cached_state_dir then return cached_state_dir end
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
        path = os.getenv("XDG_STATE_HOME") or ""
        if path == "" then
            path = utils.join_path(os.getenv("HOME") or "~", ".local/state")
        end
        path = utils.join_path(path, "tachytome")
    end

    path = M.expand_path(path)
    M.ensure_dir(path)
    cached_state_dir = path
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

function M.ensure_dir(path)
    local info = utils.file_info(path)
    if info and info.is_dir then return end
    local platform = M.get_platform()
    if platform == "windows" then
        utils.subprocess({args = {"cmd", "/d", "/c", "mkdir", (path:gsub("/", "\\"))}, cancellable = false})
    else
        utils.subprocess({args = {"mkdir", "-p", path}, cancellable = false})
    end
end

function M.get_conf_dir()
    return mp.command_native({"expand-path", "~~/script-opts/tachytome"})
end

function M.file_exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

M.containers = { "mkv", "mp4", "webm", "mov", "m4v", "avi", "ts", "flv", "wmv", "mka", "opus", "ogg", "oga", "m4a", "mp3", "aac", "flac", "wav" }

local known_exts = {}
for _, ext in ipairs(M.containers) do known_exts[ext] = true end

local function replace_spaces(name, replacement)
    return (name:gsub(" ", (replacement:gsub("%%", "%%%%"))))
end

local function dir_key(dir)
    if not dir:match("^[/\\]") and not dir:match("^%a:[/\\]") then dir = utils.join_path(utils.getcwd() or "", dir) end
    return (dir:gsub("[/\\]+", "/"):gsub("/%./", "/"):gsub("/%.$", ""):gsub("/$", ""))
end

local function resolve_absolute_path_base(custom, opts, input_path, container)
    if not input_path or input_path == "" then return "" end

    local input_dir   = utils.split_path(input_path)
    local input_name  = input_path:match("([^/\\]+)$") or ""
    local base_name   = input_name:match("^(.*)%.[^%.]+$") or input_name
    local default_ext = container or (opts.container ~= "" and opts.container or (input_name:match("^.+(%..+)$") or ".mkv"))
    if default_ext:sub(1,1) ~= "." then default_ext = "." .. default_ext end

    local base_output_dir = (opts.output_dir == "") and input_dir or M.expand_path(opts.output_dir)
    if not base_output_dir:match("[/\\]$") then base_output_dir = base_output_dir .. "/" end

    local function suffix(dir)
        return dir_key(dir) == dir_key(input_dir) and opts.suffix or ""
    end

    if not custom or custom == "" then
        return utils.join_path(base_output_dir, replace_spaces(base_name .. suffix(base_output_dir), opts.space_replacement) .. default_ext)
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
        target_name = base_name .. suffix(target_dir) .. default_ext
    else
        local user_ext = target_name:match("%.([a-zA-Z0-9]+)$")
        if not (user_ext and known_exts[user_ext:lower()]) then
            target_name = target_name .. default_ext
        end
    end

    return utils.join_path(target_dir, replace_spaces(target_name, opts.space_replacement))
end

function M.resolve_absolute_path(custom, opts, container)
    return resolve_absolute_path_base(custom, opts, mp.get_property("path"), container)
end

local function path_under(path, dir, windows)
    if not dir or dir == "" then return nil end
    dir = dir:gsub("[/\\]+$", "")
    local head = path:sub(1, #dir)
    if windows then
        head = head:gsub("/", "\\"):lower()
        dir  = dir:gsub("/", "\\"):lower()
    end
    local rest = path:sub(#dir + 1)
    if head ~= dir or not rest:match("^[/\\]") then return nil end
    return rest
end

function M.typed_path(typed, input_path, container)
    local path = M.expand_path(typed)
    if not path:match("^[/\\]") and not path:match("^%a:[/\\]") then
        path = utils.join_path(utils.split_path(input_path), (path:gsub("^%.[/\\]", "")))
    end
    local ext = path:match("%.([a-zA-Z0-9]+)$")
    if container and not (ext and known_exts[ext:lower()]) then path = path .. "." .. container end
    return path
end

function M.display_path(path, input_path)
    if not path or path == "" then return "" end
    local windows    = M.get_platform() == "windows"
    local home       = os.getenv(windows and "USERPROFILE" or "HOME")
    local input_dir  = (input_path and input_path ~= "") and utils.split_path(input_path) or nil
    local best       = path
    local candidates = {
        { prefix = ".", rest = path_under(path, input_dir, windows) },
        { prefix = "~", rest = path_under(path, home, windows) },
    }
    for _, c in ipairs(candidates) do
        if c.rest and M.text_len(c.prefix .. c.rest) < M.text_len(best) then best = c.prefix .. c.rest end
    end
    if windows then best = best:gsub("/", "\\") end
    return best
end

function M.same_path(a, b)
    if not a or not b then return false end
    a = a:gsub("[/\\]+", "/")
    b = b:gsub("[/\\]+", "/")
    if M.get_platform() ~= "linux" then
        a = a:lower()
        b = b:lower()
    end
    return a == b
end

function M.text_len(s)
    return select(2, s:gsub("[^\128-\191]", ""))
end

function M.format_bytes(bytes)
    if not bytes or bytes == 0 then return "0B" end
    if bytes < 0 then return "-" .. M.format_bytes(-bytes) end
    if bytes < 1024 then return bytes .. "B" end
    if bytes < 1048576 then return string.format("%.2fKB", bytes / 1024) end
    if bytes < 1073741824 then return string.format("%.2fMB", bytes / 1048576) end
    return string.format("%.2fGB", bytes / 1073741824)
end

function M.format_time(seconds)
    local ms = math.floor(seconds * 1000 + 0.5)
    local h  = math.floor(ms / 3600000)
    local m  = math.floor((ms % 3600000) / 60000)
    local s  = (ms % 60000) / 1000
    return string.format("%02d:%02d:%06.3f", h, m, s)
end

function M.format_duration(seconds)
    seconds = seconds or 0
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

function M.replace_file(src, dst)
    local ok, err = os.rename(src, dst)
    if not ok then
        os.remove(dst)
        ok, err = os.rename(src, dst)
    end
    return ok, err
end

function M.read_json_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return utils.parse_json(content)
end

function M.write_json_file(path, data)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(utils.format_json(data))
    f:close()
    return true
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

function M.ffprobe_get_json(file, args)
    local raw = M.ffprobe_get(file, args)
    if not raw then return nil end
    return utils.parse_json(raw)
end

function M.get_creation_time(file)
    local creation_time = M.ffprobe_get(file, {"-show_entries", "format_tags=creation_time", "-of", "csv=p=0"})
    if not creation_time then
        local info = utils.file_info(file)
        if info and info.mtime then creation_time = os.date("%Y-%m-%dT%H:%M:%S", info.mtime) end
    end
    return creation_time
end

local function keyframe_query(t, window)
    local from = string.format("%.3f%%%.3f", math.max(0, t - window), t + 0.1)
    return {"-select_streams", "v:0", "-read_intervals", from, "-show_entries", "packet=pts_time,flags", "-of", "csv=p=0"}
end

local function last_keyframe(raw, t)
    local best = nil
    for line in (raw or ""):gmatch("[^\r\n]+") do
        local pts, flags = line:match("^(.-),(.*)$")
        local k          = tonumber(pts)
        if k and flags:find("K", 1, true) and k <= t + 0.0005 and (not best or k > best) then best = k end
    end
    return best
end

local function keyframe_marks(file)
    local info = utils.file_info(file)
    if not info then return nil end
    local cached = keyframe_cache[file]
    if not cached or cached.mtime ~= info.mtime or cached.size ~= info.size then
        cached               = { mtime = info.mtime, size = info.size, marks = {} }
        keyframe_cache[file] = cached
    end
    return cached.marks
end

local function parse_interval(raw)
    local last, interval
    for line in (raw or ""):gmatch("[^\r\n]+") do
        local pts, flags = line:match("^(.-),(.*)$")
        local t = tonumber(pts)
        if t and flags:find("K", 1, true) then
            if last and t > last then interval = math.max(interval or 0, t - last) end
            if not last or t > last then last = t end
        end
    end
    return interval
end

local function cached_interval(file, info)
    local cached = interval_cache[file]
    if cached and cached.mtime == info.mtime and cached.size == info.size then return cached end
    return nil
end

function M.get_keyframe_interval(file)
    local info = utils.file_info(file)
    if not info then return nil end

    local cached = cached_interval(file, info)
    if cached then return cached.interval end

    local interval = parse_interval(M.ffprobe_get(file, interval_query))
    interval_cache[file] = { interval = interval, mtime = info.mtime, size = info.size }
    return interval
end

function M.peek_keyframe_interval(file)
    local info   = utils.file_info(file)
    local cached = info and cached_interval(file, info)
    if not cached then return nil, false end
    return cached.interval, true
end

function M.probe_keyframe_interval(file, on_done)
    local info = utils.file_info(file)
    if not info or cached_interval(file, info) or interval_pending[file] then return end
    interval_pending[file] = true

    local cmd = {"ffprobe", "-v", "error"}
    for _, v in ipairs(interval_query) do table.insert(cmd, v) end
    table.insert(cmd, file)
    mp.command_native_async({
        name           = "subprocess",
        args           = cmd,
        playback_only  = false,
        capture_stdout = true
    }, function(_, result)
        interval_pending[file] = nil
        local raw = result and result.status == 0 and result.stdout or nil
        interval_cache[file] = { interval = parse_interval(raw), mtime = info.mtime, size = info.size }
        if on_done then on_done() end
    end)
end

function M.nearest_keyframe_at_or_before(file, t)
    local marks = keyframe_marks(file)
    if not marks then return nil end
    local key = string.format("%.3f", t)
    if marks[key] ~= nil then return marks[key] or nil end

    local window = keyframe_window
    local found  = last_keyframe(M.ffprobe_get(file, keyframe_query(t, window)), t)
    while not found and t - window > 0 do
        window = window * 4
        found  = last_keyframe(M.ffprobe_get(file, keyframe_query(t, window)), t)
    end
    marks[key] = found or false
    return found
end

function M.keyframe_dts(file, t)
    local marks = keyframe_marks(file)
    local key   = string.format("dts%.3f", t)
    if marks and marks[key] ~= nil then return marks[key] or nil end
    local from  = string.format("%.3f%%+#64", math.max(0, t - 0.001))
    local raw   = M.ffprobe_get(file, {"-select_streams", "v:0", "-read_intervals", from, "-show_entries", "packet=pts_time,dts_time,flags", "-of", "csv=p=0"})
    local found = nil
    for line in (raw or ""):gmatch("[^\r\n]+") do
        local pts, dts, flags = line:match("^(.-),(.-),(.*)$")
        if not found and flags and flags:find("K", 1, true) and tonumber(pts) and math.abs(tonumber(pts) - t) < 0.0005 then
            found = tonumber(dts)
        end
    end
    if marks then marks[key] = found or false end
    return found
end

function M.listen_keyframes(name, fn)
    keyframe_listeners[name] = fn
end

function M.probe_keyframe_before(file, t)
    local marks = keyframe_marks(file)
    if not marks then return nil, false end
    local key = string.format("%.3f", t)
    if marks[key] ~= nil then return marks[key] or nil, false end

    local pending = file .. "|" .. key
    if keyframe_pending[pending] then return nil, true end
    keyframe_pending[pending] = true

    local function attempt(window)
        local cmd = {"ffprobe", "-v", "error"}
        for _, v in ipairs(keyframe_query(t, window)) do table.insert(cmd, v) end
        table.insert(cmd, file)
        mp.command_native_async({
            name           = "subprocess",
            args           = cmd,
            playback_only  = false,
            capture_stdout = true
        }, function(_, result)
            local found = last_keyframe(result and result.status == 0 and result.stdout or nil, t)
            if not found and t - window > 0 then return attempt(window * 4) end
            keyframe_pending[pending] = nil
            marks[key]                = found or false
            for _, fn in pairs(keyframe_listeners) do fn() end
        end)
    end
    attempt(keyframe_window)
    return nil, true
end

function M.resolve_mark_in(mark, lossless, file)
    if not lossless then return mark end
    if not file then return mark end
    return M.nearest_keyframe_at_or_before(file, mark) or mark
end

function M.peek_mark_in(mark, lossless, file)
    if not lossless or not file then return mark, false end
    local found, pending = M.probe_keyframe_before(file, mark)
    return found or mark, pending
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
    return utils.join_path(M.get_state_dir(), "history.json")
end

function M.read_history()
    local parsed = M.read_json_file(M.get_history_path())
    if type(parsed) == "table" then return parsed end
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
    M.write_json_file(M.get_history_path(), history_table)
end

return M
