local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'
local lang  = require 'src.lang'
local ui    = require 'src.ui'

local M = {}

local list_max      = 6
local visible_lines = 10

function M.join(list)
    if #list <= list_max then return table.concat(list, ", ") end
    local shown = {}
    for i = 1, list_max do shown[i] = list[i] end
    return lang.t("choice_more", { list = table.concat(shown, ", "), count = #list - list_max })
end

function M.show(title, body, choices, esc_index, on_pick, lines)
    ui.clear_osd()
    state.ui_owner = "dialog"

    local ov       = mp.create_osd_overlay("ass-events")
    local active   = true
    local bindings = {}
    local top      = 1
    lines          = lines or {}

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
    end

    local function bind(key, name, fn, opts)
        bindings[#bindings + 1] = name
        mp.add_forced_key_binding(key, name, fn, opts)
    end

    local rows = {}
    for i, choice in ipairs(choices) do
        local keys = {}
        if choice.alt then keys[#keys + 1] = choice.alt end
        if i == esc_index then keys[#keys + 1] = "ESC" end
        keys[#keys + 1] = choice.key
        rows[i] = { keys = table.concat(keys, ","), label = choice.label }
        for _, key in ipairs(keys) do
            bind(key, "choice-" .. key, function()
                cleanup()
                if on_pick then on_pick(i) end
            end)
        end
    end

    local body_lines = {}
    if body ~= "" then
        for line in (body .. "\n"):gmatch("(.-)\n") do body_lines[#body_lines + 1] = ui.dim(line) end
    end

    local scroll = #lines > visible_lines

    local function draw()
        local shown = {}
        if top > 1 then shown[1] = "..." end
        for i = top, math.min(#lines, top + visible_lines - 1) do shown[#shown + 1] = lines[i] end
        if top + visible_lines - 1 < #lines then shown[#shown + 1] = "..." end
        local hints = scroll and "\\N" .. ui.tooltip({ { "Up/Down", "scroll" } }) or ""
        ov.data = string.format("%s%s%s%s%s%s%s\\N%s%s%s", theme.align(7), theme.f(), theme.c("warning_color"), theme.escape(title), theme.reset(),
            table.concat(body_lines), theme.f(), ui.rows(rows), ui.dim_lines(shown), hints)
        ov:update()
    end

    local function move(delta)
        top = math.max(1, math.min(#lines - visible_lines + 1, top + delta))
        draw()
    end

    if scroll then
        bind("UP", "choice-up", function() move(-1) end, {repeatable = true})
        bind("DOWN", "choice-down", function() move(1) end, {repeatable = true})
        bind("k", "choice-k", function() move(-1) end, {repeatable = true})
        bind("j", "choice-j", function() move(1) end, {repeatable = true})
    end
    draw()
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
