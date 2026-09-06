local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'

local M = {}

function M.show(title, body, choices, esc_index, on_pick)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    state.ui_owner = "dialog"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, choice in ipairs(choices) do
            mp.remove_key_binding("choice-" .. choice.key)
        end
        if esc_index then mp.remove_key_binding("choice-esc") end
    end

    local lines = {}
    for _, choice in ipairs(choices) do
        table.insert(lines, string.format("[%s] %s", choice.key, choice.label))
    end

    ov.data = string.format("%s%s%s%s%s\\N%s\\N\\N%s",
        theme.align(7), theme.f(), theme.c("warning_color"), title, theme.reset(), body, table.concat(lines, "\\N"))
    ov:update()

    for i, choice in ipairs(choices) do
        mp.add_forced_key_binding(choice.key, "choice-" .. choice.key, function()
            cleanup()
            if on_pick then on_pick(i) end
        end)
    end

    if esc_index then
        mp.add_forced_key_binding("ESC", "choice-esc", function()
            cleanup()
            if on_pick then on_pick(esc_index) end
        end)
    end
end

function M.show_exists(display_name, on_rename, on_overwrite, on_cancel)
    M.show("Warning: File already exists!", display_name, {
        { key = "1", label = "Rename" },
        { key = "2", label = "Overwrite" },
        { key = "3", label = "Cancel" }
    }, nil, function(idx)
        if idx == 1 then
            if on_rename then on_rename() end
        elseif idx == 2 then
            if on_overwrite then on_overwrite() end
        elseif idx == 3 then
            if on_cancel then on_cancel() end
        end
    end)
end

return M
