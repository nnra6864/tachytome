local mp    = require 'mp'
local theme = require 'src.theme'
local lang  = require 'src.lang'
local edit  = require 'src.text_edit'
local ui    = require 'src.ui'

local M = {}

local prompt = "/ "

local function found_in(label, query)
    return label:lower():find(query, 1, true) ~= nil
end

function M.matches(labels, text)
    local query  = text:lower()
    local found  = {}
    local exacts = {}
    for i, label in ipairs(labels) do
        local low = label:lower()
        if low ~= "" and (low == query or low:match("[^/]*$") == query) then exacts[#exacts + 1] = i end
        if low ~= "" and found_in(low, query) then found[#found + 1] = i end
    end
    return found, #exacts == 1 and exacts[1] or nil
end

function M.new(opts)
    local s      = {}
    local layers = edit.create_layers()
    local prefix = opts.prefix .. "-search"
    local query  = ""
    local pos    = 0
    local typing = false

    local function stop()
        if not typing then return end
        typing = false
        edit.remove_bindings(prefix)
        edit.remove_char_bindings(prefix)
        for _, name in ipairs({ "enter", "esc", "up", "down" }) do mp.remove_key_binding(prefix .. "-" .. name) end
        edit.remove_layers(layers)
    end

    local function apply(fn)
        query, pos = fn(query, pos)
        opts.redraw()
    end

    function s.clear()
        stop()
        query = ""
        pos   = 0
        opts.redraw()
    end

    function s.close()
        stop()
        query = ""
        pos   = 0
    end

    local function submit()
        if query == "" then return s.clear() end
        local found, exact = M.matches(opts.labels(), query)
        if #found == 0 then return end
        local pick = exact or (#found == 1 and found[1]) or nil
        stop()
        if pick then
            query = ""
            pos   = 0
            opts.pick(pick)
        else
            opts.redraw()
        end
    end

    function s.start()
        if typing then return end
        typing = true
        edit.add_bindings(prefix, apply)
        edit.add_char_bindings(prefix, function(c)
            apply(function(t, p) return edit.insert(t, p, c) end)
        end, true)
        mp.add_forced_key_binding("ENTER", prefix .. "-enter", submit)
        mp.add_forced_key_binding("ESC", prefix .. "-esc", s.clear)
        mp.add_forced_key_binding("UP", prefix .. "-up", function()
            stop()
            opts.move(-1)
        end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", prefix .. "-down", function()
            stop()
            opts.move(1)
        end, {repeatable = true})
        opts.redraw()
    end

    function s.filtering()
        return query ~= ""
    end

    function s.keep(label)
        return query == "" or (label ~= "" and found_in(label, query:lower()))
    end

    function s.hints(hints)
        if not typing then return hints end
        return { { "Enter", "confirm" }, { "Up/Down", "navigate" }, { "Esc", "cancel" } }
    end

    function s.title(text)
        local head = ui.title(text)
        if not typing and query == "" then return head end
        if typing then
            local hidden = theme.b(true) .. theme.escape(text) .. theme.b(false) .. "\\N" .. prompt
            edit.render(layers, theme.align(7) .. theme.f(), hidden, query, pos)
        end
        return string.format("%s\\N%s%s%s%s%s%s", head, theme.f(), theme.c("text_color"), prompt, theme.c("value_color"), theme.escape(query), theme.reset())
    end

    function s.empty()
        return ui.dim(lang.t("search_none"))
    end

    return s
end

return M
