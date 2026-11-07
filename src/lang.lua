local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local state  = require 'src.state'

local M = {
    code = "en"
}

local lang_dir   = utils.join_path(mp.get_script_directory() or "", "lang")
local fallback   = {}
local strings    = {}
local generation = 0
local listener   = nil

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

local function normalize(tag)
    return (tag:lower():gsub("_", "-"))
end

local function match(text)
    if not text then return nil end
    local codes = {}
    for _, code in ipairs(M.available()) do codes[normalize(code)] = code end
    for word in text:gmatch("[^%s,;:()\"]+") do
        local tag = word:match("^[^.@]+")
        if tag and tag ~= "C" and tag ~= "POSIX" then
            tag = normalize(tag)
            while tag do
                if codes[tag] then return codes[tag] end
                tag = tag:match("^(.+)%-[^-]+$")
            end
        end
    end
    return nil
end

local function env_locale()
    for _, name in ipairs({ "LC_ALL", "LC_MESSAGES", "LANG" }) do
        local val = os.getenv(name)
        if val and val ~= "" then return val end
    end
    return nil
end

local function detect_args()
    local platform = common.get_platform()
    if platform == "windows" then
        return {"powershell", "-NoProfile", "-NonInteractive", "-Command", "(Get-UICulture).Name"}
    elseif platform == "macos" then
        return {"defaults", "read", "-g", "AppleLanguages"}
    end
    return nil
end

local function apply(code)
    M.code  = code
    strings = code ~= "en" and load_file(code) or fallback
end

local function detect()
    local token = generation
    local env   = common.get_platform() ~= "windows" and env_locale()
    if env then return apply(match(env) or "en") end

    apply("en")
    local args = detect_args()
    if not args then return end

    mp.command_native_async({
        name           = "subprocess",
        args           = args,
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result)
        if token ~= generation then return end
        local code = success and result and result.status == 0 and match(result.stdout)
        if not code or code == M.code then return end
        apply(code)
        if listener then listener() end
    end)
end

function M.on_change(fn)
    listener = fn
end

function M.load()
    generation = generation + 1
    local val  = state.opts.language
    if not val or val == "" or val == "auto" then return detect() end
    apply(val)
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
