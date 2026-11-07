local mp    = require 'mp'
local utils = require 'mp.utils'
local state = require 'src.state'

local M = {
    code = "en"
}

local lang_dir = utils.join_path(mp.get_script_directory() or "", "lang")
local fallback = {}
local strings  = {}

local function load_file(code)
    local ok, tbl = pcall(dofile, utils.join_path(lang_dir, code .. ".lua"))
    if ok and type(tbl) == "table" then return tbl end
    mp.msg.warn("Failed to load language '" .. code .. "': " .. tostring(tbl))
    return nil
end

function M.available()
    local codes = {}
    for _, name in ipairs(utils.readdir(lang_dir, "files") or {}) do
        local code = name:match("^(.+)%.lua$")
        if code then codes[#codes + 1] = code end
    end
    table.sort(codes)
    return codes
end

function M.resolve(val)
    if not val or val == "" or val == "auto" then return "en" end
    return val
end

function M.load()
    M.code  = M.resolve(state.opts.language)
    strings = M.code ~= "en" and load_file(M.code) or fallback
end

function M.has(key)
    return strings[key] ~= nil or fallback[key] ~= nil
end

function M.t(key, vars)
    local text = strings[key] or fallback[key] or key
    if not vars then return text end
    return (text:gsub("{([%w_]+)}", function(k)
        if vars[k] ~= nil then return tostring(vars[k]) end
    end))
end

fallback = load_file("en") or {}
M.load()

return M
