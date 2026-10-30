-- TODO: document the keymap config syntax in README
local state  = require 'src.state'
local notify = require 'src.notify'

local M = {}

local builtin = {
    i     = "mark_in",
    o     = "mark_out",
    I     = "goto_in",
    O     = "goto_out",
    g     = "goto",
    e     = "encoder",
    q     = "quality",
    F     = "fps",
    P     = "preset",
    l     = "lossless_cut",
    a     = "accurate_cut",
    c     = "combine_audio",
    A     = "first_audio_only",
    t     = "trash_source",
    _     = "space_replacement",
    p     = "path",
    ENTER = "render",
    R     = "render_pause",
    r     = "render_queue",
    d     = "trash_source_now",
    s     = "stats",
    ESC   = "close"
}

local presets = {}
local flats   = {}

local function warn(msg)
    notify.show(msg, false, "warn")
end

local function valid_seq(seq)
    if seq == "" or seq:find("^-") or seq:find("-$") or seq:find("--", 1, true) then
        return false
    end
    return true
end

local function parse_line(line, current)
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    local head = words[1]

    if current then
        if head == "end" and #words == 1 then return nil end
        if head == "base" then
            if #words == 2 then
                current.base = words[2]
            else
                warn("invalid base line in keymap '" .. current.name .. "'")
            end
            return current
        end
        if #words == 2 and valid_seq(words[1]) then
            current.entries[#current.entries + 1] = { seq = words[1], action = words[2] }
            return current
        end
        warn("invalid line in keymap '" .. current.name .. "': " .. line)
        return current
    end

    if head == "keymap" then
        if #words == 2 then
            return { name = words[2], base = nil, entries = {} }
        end
        if #words == 3 and valid_seq(words[2]) then
            flats[#flats + 1] = { seq = words[2], action = words[3] }
        else
            warn("invalid keymap line: " .. line)
        end
        return nil
    end

    if head then warn("invalid keymap line: " .. line) end
    return nil
end

local function parse_conf()
    local f = io.open(state.conf_path, "r")
    if not f then return end

    local current = nil
    for line in f:lines() do
        local content = line:gsub("\r$", "")
        local hash = content:find("#", 1, true)
        if hash then content = content:sub(1, hash - 1) end
        content = content:match("^%s*(.-)%s*$")
        if content ~= "" then
            if not current and content:find("=", 1, true) then
                -- regular option line, handled by mp.options
            else
                local result = parse_line(content, current)
                if current and result == nil then
                    if current.name == "builtin" then
                        warn("keymap name 'builtin' is reserved")
                    else
                        if presets[current.name] then
                            warn("keymap '" .. current.name .. "' redefined")
                        end
                        presets[current.name] = current
                    end
                end
                current = result
            end
        end
    end
    f:close()

    if current then warn("unclosed keymap: " .. current.name) end
end

local function copy_builtin()
    local map = {}
    for seq, action in pairs(builtin) do map[seq] = action end
    return map
end

local function apply_entry(map, entry)
    if entry.action == "none" or entry.action == "ignore" then
        map[entry.seq] = nil
    else
        map[entry.seq] = entry.action
    end
end

local function resolve(name, visited)
    if name == "builtin" then
        return copy_builtin()
    end

    if name == "default" then
        local map = copy_builtin()
        local p = presets.default
        if p then
            if p.base and p.base ~= "default" and p.base ~= "builtin" then
                warn("keymap 'default' ignores base '" .. p.base .. "'")
            end
            for _, entry in ipairs(p.entries) do apply_entry(map, entry) end
        end
        return map
    end

    if visited[name] then
        warn("keymap base cycle at: " .. name)
        return copy_builtin()
    end
    visited[name] = true

    local p = presets[name]
    if not p then
        warn("keymap not defined: " .. name)
        return resolve("default", {})
    end

    local map = p.base and resolve(p.base, visited) or {}
    for _, entry in ipairs(p.entries) do apply_entry(map, entry) end
    return map
end

function M.active()
    local map = resolve(state.opts.selected_keymap, {})
    for _, entry in ipairs(flats) do apply_entry(map, entry) end
    return map
end

parse_conf()

return M
