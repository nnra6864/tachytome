local mp     = require 'mp'
local state  = require 'src.state'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local function parse(kind, count)
    local key  = kind .. "_tracks"
    local spec = state.opts[key]:lower():match("^%s*(.-)%s*$")
    local set  = {}
    if spec == "all" then
        for i = 1, count do set[i] = true end
        return set
    end
    for entry in spec:gmatch("[^,]+") do
        local n = tonumber(entry:match("^%s*(%d+)%s*$"))
        if n and n >= 1 then
            set[n] = true
        else
            notify.show(lang.t("tracks_invalid", { key = key, value = entry:match("^%s*(.-)%s*$") }), false, "warn")
        end
    end
    return set
end

function M.list(kind)
    local out = {}
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == kind and not t.external then out[#out + 1] = t end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function M.reset()
    state.tracks = {}
end

function M.selected(kind)
    if not state.tracks[kind] then state.tracks[kind] = parse(kind, #M.list(kind)) end
    return state.tracks[kind]
end

function M.toggle(kind, n)
    local set = M.selected(kind)
    set[n]    = not set[n] or nil
    return set[n] == true
end

function M.indices(kind)
    local count = #M.list(kind)
    local set   = M.selected(kind)
    local out   = {}
    for i = 1, count do
        if set[i] then out[#out + 1] = i end
    end
    if #out == count then return nil end
    return out
end

function M.display(kind)
    local list = M.indices(kind)
    if not list then return lang.t(#M.list(kind) > 0 and "value_all" or "value_none") end
    if #list == 0 then return lang.t("value_none") end
    return table.concat(list, ", ")
end

return M
