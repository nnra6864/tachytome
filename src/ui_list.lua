local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'

local M = {}

function M.show(title, items, current_val, on_select, on_cancel)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1

    for i, item in ipairs(items) do
        if item == current_val then
            cursor = i
            break
        end
    end

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("list-up")
        mp.remove_key_binding("list-down")
        mp.remove_key_binding("list-enter")
        mp.remove_key_binding("list-esc")
        if on_cancel then on_cancel() end
    end

    local function draw()
        local text = string.format("%s%s%s%s%s\\N%s(Up/Down to navigate, Enter to select, Esc to cancel)\\N\\N",
            theme.align(7), theme.f(), theme.b(false), theme.c("text_color"), title, theme.f(false))

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#items, start_idx + 14)
        if end_idx - start_idx < 14 then
            start_idx = math.max(1, end_idx - 14)
        end

        if start_idx > 1 then text = text .. "\\h\\h...\\N" end

        for i = start_idx, end_idx do
            local val      = items[i]
            local prefix   = (i == cursor) and (theme.b(true) .. theme.c("value_color") .. "\\h> ") or theme.b(false) .. "\\h\\h"
            local selected = (val == current_val) and (theme.b(true) .. theme.c("on_color") .. state.opts.on_text) or theme.b(false) .. ""
            text = text .. string.format("%s%s %s%s\\N", prefix, val, selected, theme.reset())
        end

        if end_idx < #items then text = text .. "\\h\\h...\\N" end

        ov.data = text
        ov:update()
    end

    mp.add_forced_key_binding("UP", "list-up", function()
        if cursor > 1 then cursor = cursor - 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("DOWN", "list-down", function()
        if cursor < #items then cursor = cursor + 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("ENTER", "list-enter", function()
        local val = items[cursor]
        active = false
        ov:remove()
        mp.remove_key_binding("list-up")
        mp.remove_key_binding("list-down")
        mp.remove_key_binding("list-enter")
        mp.remove_key_binding("list-esc")
        if on_select then on_select(val) end
    end)

    mp.add_forced_key_binding("ESC", "list-esc", cleanup)
    draw()
end

return M
