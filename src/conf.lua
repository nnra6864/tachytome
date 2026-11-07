local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'

local M = {
    builtin_path = utils.join_path(mp.get_script_directory() or "", "tachytome.conf"),
    user_path    = nil,
    menu_lines   = { builtin = {}, user = {} }
}

local identifier = "tachytome"

local function typeconv(default, val)
    if type(default) == "boolean" then
        if val == "yes" then return true end
        if val == "no" then return false end
        return nil
    end
    if type(default) == "number" then return tonumber(val) end
    return val
end

local function set_opt(opts, key, val, where)
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
end

local function parse_file(path, name, opts)
    local menu_lines = {}
    local f = io.open(path, "r")
    if not f then return menu_lines end

    local depth = 0
    local n     = 0
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
            set_opt(opts, line:sub(1, eq - 1), line:sub(eq + 1), where)
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
    return menu_lines
end

local function apply_script_opts(opts)
    local prefix = identifier .. "-"
    for key, val in pairs(mp.get_property_native("options/script-opts") or {}) do
        if key:sub(1, #prefix) == prefix then
            set_opt(opts, key:sub(#prefix + 1), val, "script-opts:")
        end
    end
end

function M.read_options(opts)
    M.user_path          = common.ensure_default_conf("tachytome.conf", "tachytome.conf", true)
    M.menu_lines.builtin = parse_file(M.builtin_path, "tachytome.conf (builtin)", opts)
    M.menu_lines.user    = parse_file(M.user_path, M.user_path, opts)
    apply_script_opts(opts)
end

local function read_lines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do lines[#lines + 1] = line:gsub("\r$", "") end
    f:close()
    return lines
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

function M.write_option(key, val)
    if not M.user_path then return false end
    local entry = key .. "=" .. tostring(val)
    local lines = read_lines(M.user_path)

    local found = false
    for i, line in ipairs(lines) do
        if line:sub(1, #key + 1) == key .. "=" then
            lines[i] = entry
            found    = true
            break
        end
    end

    if not found then
        local block = builtin_block(key)
        block[#block + 1] = entry
        block[#block + 1] = ""
        for i = #block, 1, -1 do table.insert(lines, 1, block[i]) end
    end

    common.ensure_dir(common.get_conf_dir())
    local f = io.open(M.user_path, "w")
    if not f then
        mp.msg.warn("Failed to write " .. key .. " to " .. M.user_path)
        return false
    end
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    return true
end

return M
