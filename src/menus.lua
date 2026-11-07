local state  = require 'src.state'
local conf   = require 'src.conf'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local presets = {}
local order   = {}
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

local function parse_label(text)
    if text == "" then return nil end
    if text:sub(1, 2) == "@@" then return { text = text:sub(2) } end
    if text:sub(1, 1) == "@" then
        local key, rest = text:match("^@(%S*)%s*(.-)$")
        return { key = key, text = rest }
    end
    return { text = text }
end

local function parse_entry(line, where)
    local text       = line
    local add        = false
    local hide       = false
    local word, body = text:match("^(%S+)%s+(%S+%s+%S+.*)$")
    while (word == "add" and not add) or (word == "hide" and not hide) do
        if word == "add" then add = true else hide = true end
        text       = body
        word, body = text:match("^(%S+)%s+(%S+%s+%S+.*)$")
    end

    local seq, action, label = text:match("^(%S+)%s+(%S+)%s*(.-)$")
    local unbind             = action == "none" or action == "ignore"
    local hide_seq           = action == "hide"
    if not seq or not valid_seq(seq) or text:find("{$") or ((unbind or hide_seq) and (add or hide or label ~= "")) then
        warn(lang.t("warn_invalid_menu_line", { where = where, line = line }))
        return nil
    end

    return {
        seq      = seq,
        action   = not unbind and not hide_seq and action or nil,
        add      = add,
        hide     = hide,
        hide_seq = hide_seq,
        label    = parse_label(label)
    }
end

local function parse_submenu(line, where)
    local hide = false
    local body = line:match("^hide%s+(%S+%s+%S+.*)$")
    if body then
        hide = true
        line = body
    end

    local seq, id, label = line:match("^(%S+)%s+(%S+)%s*(.-)%s*{$")
    if not seq or seq == "add" or seq == "hide" or not valid_seq(seq) or id == "none" or id == "ignore" or id == "hide" then
        warn(lang.t("warn_invalid_submenu_line", { where = where, line = line }))
        return nil
    end

    return {
        seq     = seq,
        action  = id,
        add     = false,
        hide    = hide,
        label   = parse_label(label),
        entries = {}
    }
end

local function finish(current, defined)
    if defined[current.name] then
        warn(lang.t("warn_menu_redefined", { name = current.name, where = current.where }))
    end
    defined[current.name] = true
    if not presets[current.name] then order[#order + 1] = current.name end
    presets[current.name] = current
end

local function parse_lines(lines)
    local defined = {}
    local stack   = {}
    for _, ln in ipairs(lines) do
        local text    = ln.text
        local current = stack[#stack]
        if current then
            if text == "}" then
                stack[#stack] = nil
                if #stack == 0 then finish(current, defined) end
            elseif text == "" then
                current.entries[#current.entries + 1] = { separator = true }
            elseif text:find("^base%s") then
                local base = text:match("^base%s+(%S+)$")
                if base and #stack == 1 then
                    current.base = base
                else
                    warn(lang.t("warn_invalid_base_line", { where = ln.where, line = text }))
                end
            elseif text:find("{$") then
                local entry = parse_submenu(text, ln.where)
                if entry then
                    current.entries[#current.entries + 1] = entry
                else
                    entry = { entries = {} }
                end
                stack[#stack + 1] = entry
            else
                local entry = parse_entry(text, ln.where)
                if entry then current.entries[#current.entries + 1] = entry end
            end
        elseif text ~= "" then
            local name = text:match("^menu%s+([^%s{]+)%s*{$")
            local body = text:match("^menu%s+(.+)$")
            if name then
                stack[1] = { name = name, base = nil, entries = {}, where = ln.where }
            elseif body then
                local entry = parse_entry(body, ln.where)
                if entry then flats[#flats + 1] = entry end
            else
                warn(lang.t("warn_invalid_menu_line", { where = ln.where, line = text }))
            end
        end
    end

    if stack[1] then warn(lang.t("warn_unclosed_menu", { name = stack[1].name, where = stack[1].where })) end
end

local function unbind(rows, seq)
    for _, row in ipairs(rows) do
        if row.keys then
            for i = #row.keys, 1, -1 do
                if row.keys[i] == seq then table.remove(row.keys, i) end
            end
        end
    end
end

local function hide(rows, seq)
    for _, row in ipairs(rows) do
        if row.keys then
            for _, key in ipairs(row.keys) do
                if key == seq then row.hidden = true end
            end
        end
    end
end

local function collect(rows, action, submenu, found)
    for _, row in ipairs(rows) do
        if not row.separator then
            if row.action == action and (not submenu or row.rows) then
                found[#found + 1] = { row = row, level = rows }
            end
            if row.rows then collect(row.rows, action, submenu, found) end
        end
    end
    return found
end

local function find_row(rows, action, submenu, name)
    local found = collect(rows, action, submenu, {})
    if #found > 1 then
        warn(lang.t("warn_action_on_several_rows", { name = name, action = action }))
    end
    if found[1] then return found[1].row, found[1].level end
    return nil, rows
end

local function apply(rows, entries, patch, name)
    local pending_sep = false
    for _, entry in ipairs(entries) do
        if entry.separator then
            pending_sep = true
        elseif entry.hide_seq then
            hide(rows, entry.seq)
            pending_sep = false
        else
            local row   = nil
            local level = rows
            if entry.action and (patch or entry.add) then
                row, level = find_row(rows, entry.action, entry.entries ~= nil, name)
            end
            unbind(level, entry.seq)
            if row then
                if entry.add then
                    row.keys[#row.keys + 1] = entry.seq
                else
                    row.keys = { entry.seq }
                end
                if entry.label then row.label = entry.label end
                if entry.hide then row.hidden = true end
                if entry.entries then apply(row.rows, entry.entries, true, name) end
            elseif entry.action then
                if pending_sep and #rows > 0 then rows[#rows + 1] = { separator = true } end
                local new = { keys = { entry.seq }, action = entry.action, label = entry.label, hidden = entry.hide }
                if entry.entries then
                    new.rows = {}
                    apply(new.rows, entry.entries, false, name)
                end
                rows[#rows + 1] = new
            end
            pending_sep = false
        end
    end
end

local function normalize(rows)
    local out = {}
    for _, row in ipairs(rows) do
        if row.separator then
            if #out > 0 and not out[#out].separator then out[#out + 1] = row end
        elseif #row.keys > 0 then
            if row.rows then row.rows = normalize(row.rows) end
            if not row.rows or #row.rows > 0 then out[#out + 1] = row end
        end
    end
    if #out > 0 and out[#out].separator then out[#out] = nil end
    return out
end

local function resolve(name, visited)
    local p = presets[name]
    if not p then
        warn(lang.t("warn_menu_not_defined", { name = name }))
        if name == "default" then return {} end
        return resolve("default", visited)
    end

    if visited[name] then
        warn(lang.t("warn_menu_base_cycle", { name = name }))
        return {}
    end
    visited[name] = true

    local rows = p.base and resolve(p.base, visited) or {}
    apply(rows, p.entries, p.base ~= nil, name)
    return normalize(rows)
end

function M.names()
    return order
end

function M.active()
    local rows = resolve(state.opts.selected_menu, {})
    apply(rows, flats, true, state.opts.selected_menu)
    return normalize(rows)
end

parse_lines(conf.menu_lines.builtin)
parse_lines(conf.menu_lines.user)

return M
