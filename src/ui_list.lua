local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'
local ui    = require 'src.ui'

local M = {}

local bindings = { "list-up", "list-down", "list-j", "list-k", "list-enter", "list-esc" }

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
            return theme.escape(items[i]) .. marker
        end)
        ov.data = ui.title(title) .. "\\N" .. body .. "\\N" .. ui.tooltip({ { "Up/Down", "navigate" }, { "Enter", "select" }, { "Esc", "cancel" } })
        ov:update()
    end

    local function move_up()
        if cursor > 1 then cursor = cursor - 1; draw() end
    end

    local function move_down()
        if cursor < #items then cursor = cursor + 1; draw() end
    end

    mp.add_forced_key_binding("UP", "list-up", move_up, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "list-down", move_down, {repeatable = true})
    mp.add_forced_key_binding("j", "list-j", move_down, {repeatable = true})
    mp.add_forced_key_binding("k", "list-k", move_up, {repeatable = true})

    mp.add_forced_key_binding("ENTER", "list-enter", function()
        local val = items[cursor]
        teardown()
        if on_select then on_select(val) end
    end)

    mp.add_forced_key_binding("ESC", "list-esc", cleanup)
    draw()
end

return M
