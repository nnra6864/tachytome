local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'

local M = {
    builtin_path = utils.join_path(mp.get_script_directory() or "", "tachytome.conf"),
    user_path    = nil,
    menu_lines   = {},
    configs      = {}
}

local identifier = "tachytome"
local reserved   = { ["tachytome.conf"] = true, ["effects.conf"] = true }
local defaults   = nil
local origins    = {}

local function typeconv(default, val)
    if type(default) == "boolean" then
        if val == "yes" then return true end
        if val == "no" then return false end
        return nil
    end
    if type(default) == "number" then return tonumber(val) end
    return val
end

local function set_opt(opts, key, val, where, origin)
    if opts[key] == nil then
        mp.msg.warn(where .. " unknown key '" .. key .. "', ignoring")
        return
    end
    local conv = typeconv(opts[key], val)
    if conv == nil then
        mp.msg.error(where .. " error converting value '" .. val .. "' for key '" .. key .. "'")
        return
    end
    opts[key] = conv
    if origin then origins[key] = origin end
end

function M.config_path(name)
    return utils.join_path(common.get_conf_dir(), name .. ".conf")
end

local function parse_configs(val)
    local list = {}
    local seen = {}
    for entry in val:gmatch("[^,]+") do
        local name    = entry:match("^%s*(.-)%s*$")
        local enabled = name:sub(1, 1) ~= "!"
        if not enabled then name = name:sub(2):match("^%s*(.-)$") end
        name = name:gsub("%.conf$", "")
        if name ~= "" and not seen[name] and not reserved[name .. ".conf"] then
            seen[name]      = true
            list[#list + 1] = { name = name, enabled = enabled, exists = common.file_exists(M.config_path(name)) }
        end
    end
    return list, seen
end

local function discover_configs(list, seen)
    local found = {}
    for _, file in ipairs(utils.readdir(common.get_conf_dir(), "files") or {}) do
        local name = file:match("^(.+)%.conf$")
        if name and not reserved[file] and not seen[name] then found[#found + 1] = name end
    end
    table.sort(found)
    for _, name in ipairs(found) do
        list[#list + 1] = { name = name, enabled = false, exists = true }
    end
    return list
end

local parse_file

local function load_configs(val, where, opts, chunks)
    local list, seen = parse_configs(val)
    for _, c in ipairs(list) do
        if c.enabled and c.exists then
            parse_file(M.config_path(c.name), c.name .. ".conf", opts, chunks, "config")
        elseif c.enabled then
            mp.msg.warn(where .. " config '" .. c.name .. "' not found at " .. M.config_path(c.name))
        end
    end
    M.configs = discover_configs(list, seen)
end

parse_file = function(path, name, opts, chunks, mode)
    local menu_lines = {}
    chunks[#chunks + 1] = menu_lines
    local f = io.open(path, "r")
    if not f then return end

    local depth        = 0
    local n            = 0
    local configs_seen = false
    for raw in f:lines() do
        n = n + 1
        local line    = raw:gsub("\r$", "")
        local content = line
        local hash    = content:find("#", 1, true)
        if hash then content = content:sub(1, hash - 1) end
        content = content:match("^%s*(.-)%s*$")
        local where = name .. ":" .. n

        local eq = line:find("=", 1, true)
        if depth == 0 and eq and line:sub(1, 1) ~= "#" and not content:find("^menu%s") then
            local key = line:sub(1, eq - 1)
            if key ~= "configs" then
                set_opt(opts, key, line:sub(eq + 1), where, mode ~= "builtin" and { path = path, line = n } or nil)
            elseif mode == "config" then
                mp.msg.warn(where .. " configs only works in " .. M.user_path .. ", ignoring")
            elseif mode == "main" and configs_seen then
                mp.msg.warn(where .. " configs already set, ignoring")
            elseif mode == "main" then
                configs_seen = true
                load_configs(line:sub(eq + 1), where, opts, chunks)
                menu_lines          = {}
                chunks[#chunks + 1] = menu_lines
            end
        elseif content ~= "" or not line:find("%S") then
            menu_lines[#menu_lines + 1] = { text = content, where = where }
            if content:find("{$") then
                depth = depth + 1
            elseif content == "}" and depth > 0 then
                depth = depth - 1
            end
        end
    end
    f:close()

    if mode == "main" and not configs_seen then M.configs = discover_configs({}, {}) end
end

local function apply_script_opts(opts)
    local prefix = identifier .. "-"
    for key, val in pairs(mp.get_property_native("options/script-opts") or {}) do
        if key:sub(1, #prefix) == prefix then
            set_opt(opts, key:sub(#prefix + 1), val, "script-opts:")
        end
    end
end

local function read_lines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do lines[#lines + 1] = line:gsub("\r$", "") end
    f:close()
    return lines
end

local function write_lines(path, lines, key)
    common.ensure_dir(common.get_conf_dir())
    local f = io.open(path, "w")
    if not f then
        mp.msg.warn("Failed to write " .. key .. " to " .. path)
        return false
    end
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    return true
end

local function has_configs_line(path)
    for _, line in ipairs(read_lines(path)) do
        if line:sub(1, 8) == "configs=" then return true end
    end
    return false
end

local function ensure_main_conf()
    local main    = utils.join_path(common.get_conf_dir(), "tachytome.conf")
    local default = M.config_path("default")
    local legacy  = utils.join_path(mp.command_native({"expand-path", "~~/script-opts"}), "tachytome.conf")
    local source  = nil

    if not common.file_exists(default) then
        if common.file_exists(legacy) and not common.file_exists(main) then
            source = legacy
        elseif common.file_exists(main) and not has_configs_line(main) then
            source = main
        end
    end

    if source then
        common.ensure_dir(common.get_conf_dir())
        local ok, err = os.rename(source, default)
        if ok then
            mp.msg.info("Moved config " .. source .. " to " .. default)
        else
            mp.msg.warn("Failed to move config " .. source .. ": " .. tostring(err))
            return main
        end
    elseif common.file_exists(legacy) then
        mp.msg.warn("Ignoring old config " .. legacy .. ", using " .. main)
    elseif not common.file_exists(default) and not common.file_exists(main) then
        common.ensure_default_conf("tachytome.conf", "default.conf", true)
    end

    if source == main or not common.file_exists(main) then
        write_lines(main, { "configs=default" }, "configs")
        mp.msg.info("Generated config at: " .. main)
    end
    return main
end

function M.read_options(opts)
    if defaults then
        for key, val in pairs(defaults) do opts[key] = val end
    else
        defaults = {}
        for key, val in pairs(opts) do defaults[key] = val end
    end
    origins      = {}
    M.menu_lines = {}
    M.configs    = {}
    M.user_path  = ensure_main_conf()
    parse_file(M.builtin_path, "tachytome.conf (builtin)", opts, M.menu_lines, "builtin")
    parse_file(M.user_path, M.user_path, opts, M.menu_lines, "main")
    apply_script_opts(opts)
end

local function builtin_block(key)
    local lines = read_lines(M.builtin_path)
    for i, line in ipairs(lines) do
        if line:sub(1, #key + 1) == key .. "=" then
            local first = i
            while first > 1 and lines[first - 1]:sub(1, 1) == "#" do first = first - 1 end
            local block = {}
            for j = first, i - 1 do block[#block + 1] = lines[j] end
            return block
        end
    end
    return {}
end

local function find_line(lines, key, hint)
    local prefix = key .. "="
    if hint and lines[hint] and lines[hint]:sub(1, #prefix) == prefix then return hint end
    for i = #lines, 1, -1 do
        if lines[i]:sub(1, #prefix) == prefix then return i end
    end
    return nil
end

function M.write_option(key, val)
    if not M.user_path then return false end
    local entry  = key .. "=" .. tostring(val)
    local origin = origins[key]
    local path   = origin and origin.path or M.user_path
    local lines  = read_lines(path)
    local idx    = find_line(lines, key, origin and origin.line)

    if idx then
        lines[idx]   = entry
        origins[key] = { path = path, line = idx }
        return write_lines(path, lines, key)
    end

    path = M.user_path
    for _, c in ipairs(M.configs) do
        if c.enabled and c.exists then
            path = M.config_path(c.name)
            break
        end
    end
    lines = read_lines(path)
    local block = builtin_block(key)
    block[#block + 1] = entry
    block[#block + 1] = ""
    for i = #block, 1, -1 do table.insert(lines, 1, block[i]) end
    for _, o in pairs(origins) do
        if o.path == path then o.line = o.line + #block end
    end
    origins[key] = { path = path, line = #block - 1 }
    return write_lines(path, lines, key)
end

function M.write_configs(list)
    if not M.user_path then return false end
    local names = {}
    for _, c in ipairs(list) do names[#names + 1] = (c.enabled and "" or "!") .. c.name end
    local entry = "configs=" .. table.concat(names, ",")
    local lines = read_lines(M.user_path)

    for i, line in ipairs(lines) do
        if line:sub(1, 8) == "configs=" then
            lines[i] = entry
            return write_lines(M.user_path, lines, "configs")
        end
    end

    if #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
    for _, line in ipairs(builtin_block("configs")) do lines[#lines + 1] = line end
    lines[#lines + 1] = entry
    return write_lines(M.user_path, lines, "configs")
end

return M
