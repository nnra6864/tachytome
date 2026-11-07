local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'
local lang  = require 'src.lang'
local ui    = require 'src.ui'

local M = {}

function M.show(title, body, choices, esc_index, on_pick)
    ui.clear_osd()
    state.ui_owner = "dialog"

    local ov       = mp.create_osd_overlay("ass-events")
    local active   = true
    local bindings = {}

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
    end

    local function bind(key, idx)
        local name = "choice-" .. key
        bindings[#bindings + 1] = name
        mp.add_forced_key_binding(key, name, function()
            cleanup()
            if on_pick then on_pick(idx) end
        end)
    end

    local rows = {}
    for i, choice in ipairs(choices) do
        local keys = { choice.key }
        if choice.alt then keys[#keys + 1] = choice.alt end
        if i == esc_index then keys[#keys + 1] = "ESC" end
        rows[i] = { keys = table.concat(keys, ","), label = choice.label }
        for _, key in ipairs(keys) do bind(key, i) end
    end

    local body_lines = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do body_lines[#body_lines + 1] = ui.dim(line) end

    ov.data = string.format("%s%s%s%s%s%s%s\\N%s", theme.align(7), theme.f(), theme.c("warning_color"), theme.escape(title), theme.reset(),
        table.concat(body_lines), theme.f(), ui.rows(rows))
    ov:update()
end

function M.show_exists(display_name, on_rename, on_overwrite, on_cancel)
    M.show(lang.t("render_exists"), display_name, {
        { key = "1", label = lang.t("choice_rename") },
        { key = "2", label = lang.t("choice_overwrite") },
        { key = "3", label = lang.t("choice_cancel") }
    }, 3, function(idx)
        if idx == 1 then
            if on_rename then on_rename() end
        elseif idx == 2 then
            if on_overwrite then on_overwrite() end
        elseif on_cancel then
            on_cancel()
        end
    end)
end

return M
