local mp       = require 'mp'
local state    = require 'src.state'
local theme    = require 'src.theme'
local lang     = require 'src.lang'
local ui_input = require 'src.ui_input'
local ui       = require 'src.ui'

local M = {}

local bindings = { "list-up", "list-down", "list-j", "list-k", "list-enter", "list-search", "list-esc" }
for i = 1, 10 do bindings[#bindings + 1] = "list-" .. i end

local function sub_title(title, text)
    return string.format("%s %s %s", title, state.opts.menu_path_separator, text)
end

function M.matches(labels, text)
    local query  = text:lower()
    local found  = {}
    local exacts = {}
    for i, label in ipairs(labels) do
        local low = label:lower()
        if low == query or low:match("[^/]*$") == query then exacts[#exacts + 1] = i end
        if low:find(query, 1, true) then found[#found + 1] = i end
    end
    return found, #exacts == 1 and exacts[1] or nil
end

function M.search(title, labels, on_pick, on_cancel, text)
    ui_input.show({
        title       = sub_title(title, lang.t("search_title")),
        text        = text,
        allow_space = true,
        on_cancel   = on_cancel,
        below       = function(input)
            if input == "" then return "" end
            local found = M.matches(labels, input)
            if #found == 0 then return ui.dim(lang.t("search_none")) end
            return theme.f() .. ui.list(#found, 0, function(i) return theme.escape(labels[found[i]]) end)
        end,
        on_submit   = function(input)
            if input == "" then return on_cancel() end
            local found, exact = M.matches(labels, input)
            if exact or #found == 1 then return on_pick(exact or found[1]) end
            if #found == 0 then return M.search(title, labels, on_pick, on_cancel, input) end
            local items = {}
            for i, index in ipairs(found) do items[i] = labels[index] end
            M.show(sub_title(title, input), items, nil, function(_, i) on_pick(found[i]) end, on_cancel)
        end
    })
end

function M.show(title, items, current_val, on_select, on_cancel)
    ui.clear_osd()
    state.ui_owner = "list"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1

    for i, item in ipairs(items) do
        if item == current_val then
            cursor = i
            break
        end
    end

    local function teardown()
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_cancel then on_cancel() end
    end

    local function draw()
        local body = ui.list(#items, cursor, function(i)
            local marker = items[i] == current_val and string.format(" %s%s", theme.c("on_color"), state.opts.on_text) or ""
            return ui.number_prefix(i) .. theme.escape(items[i]) .. marker
        end)
        ov.data = ui.title(title) .. "\\N" .. body .. "\\N" .. ui.tooltip({ { "Up/Down", "navigate" }, { "0-9/Enter", "select" }, { "/", "search" }, { "Esc", "cancel" } })
        ov:update()
    end

    local function move_up()
        cursor = ui.wrap(cursor, -1, #items)
        draw()
    end

    local function move_down()
        cursor = ui.wrap(cursor, 1, #items)
        draw()
    end

    local function pick(i)
        local val = items[i]
        if val == nil then return end
        teardown()
        if on_select then on_select(val, i) end
    end

    local function search()
        teardown()
        M.search(title, items, function(i)
            if on_select then on_select(items[i], i) end
        end, function()
            M.show(title, items, current_val, on_select, on_cancel)
        end)
    end

    mp.add_forced_key_binding("UP", "list-up", move_up, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "list-down", move_down, {repeatable = true})
    mp.add_forced_key_binding("j", "list-j", move_down, {repeatable = true})
    mp.add_forced_key_binding("k", "list-k", move_up, {repeatable = true})
    mp.add_forced_key_binding("ENTER", "list-enter", function() pick(cursor) end)
    for i = 1, 10 do
        mp.add_forced_key_binding(ui.number_key(i), "list-" .. i, function() pick(i) end)
    end
    mp.add_forced_key_binding("/", "list-search", search)
    mp.add_forced_key_binding("ESC", "list-esc", cleanup)
    draw()
end

return M
