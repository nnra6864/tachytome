local mp     = require 'mp'
local common = require 'src.common'
local state  = require 'src.state'
local theme  = require 'src.theme'
local lang   = require 'src.lang'

local M = {}

local bindings = { "cfg-up", "cfg-down", "cfg-cj", "cfg-ck", "cfg-move-up", "cfg-move-down", "cfg-K", "cfg-J", "cfg-enter", "cfg-esc" }

function M.show(configs, on_apply, on_close)
    local ov      = mp.create_osd_overlay("ass-events")
    local active  = true
    local cursor  = 1
    local changed = false
    local rows    = {}
    for i, c in ipairs(configs) do rows[i] = { name = c.name, enabled = c.enabled, exists = c.exists } end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    state.ui_owner = "configs"

    local function teardown()
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
    end

    local function close()
        if not active then return end
        teardown()
        if changed then
            if on_apply then on_apply(rows) end
        elseif on_close then
            on_close()
        end
    end

    local function draw()
        local text = string.format("%s%s%s%s%s\\N%s%s\\N\\N",
            theme.align(7), theme.f(), theme.b(true), lang.t("configs_title"), theme.b(false), theme.f(true), lang.t("tooltip_configs"))

        if #rows == 0 then
            text = text .. theme.c("dim_text_color") .. theme.escape(lang.t("configs_empty", { dir = common.display_path(common.get_conf_dir()) }))
        end

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#rows, start_idx + 14)
        if end_idx - start_idx < 14 then start_idx = math.max(1, end_idx - 14) end

        if start_idx > 1 then text = text .. "\\h\\h...\\N" end

        for i = start_idx, end_idx do
            local row     = rows[i]
            local prefix  = (i == cursor) and string.format("%s\\h> ", theme.c("value_color")) or "\\h\\h"
            local val     = row.enabled
                and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                or  string.format("%s%s", theme.c("off_color"), state.opts.off_text)
            local missing = row.exists and "" or string.format(" %s%s", theme.c("warning_color"), lang.t("configs_missing"))
            text = text .. string.format("%s%s%s %s%s%s\\N", theme.c("text_color"), prefix, theme.escape(row.name), val, missing, theme.reset())
        end

        if end_idx < #rows then text = text .. "\\h\\h...\\N" end

        ov.data = text
        ov:update()
    end

    local function move_cursor(delta)
        local target = cursor + delta
        if target < 1 or target > #rows then return end
        cursor = target
        draw()
    end

    local function move_row(delta)
        local target = cursor + delta
        if target < 1 or target > #rows then return end
        rows[cursor], rows[target] = rows[target], rows[cursor]
        cursor  = target
        changed = true
        draw()
    end

    local function toggle()
        local row = rows[cursor]
        if not row then return end
        row.enabled = not row.enabled
        changed     = true
        draw()
    end

    mp.add_forced_key_binding("UP", "cfg-up", function() move_cursor(-1) end, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "cfg-down", function() move_cursor(1) end, {repeatable = true})
    mp.add_forced_key_binding("ctrl+j", "cfg-cj", function() move_cursor(1) end, {repeatable = true})
    mp.add_forced_key_binding("ctrl+k", "cfg-ck", function() move_cursor(-1) end, {repeatable = true})
    mp.add_forced_key_binding("shift+UP", "cfg-move-up", function() move_row(-1) end, {repeatable = true})
    mp.add_forced_key_binding("shift+DOWN", "cfg-move-down", function() move_row(1) end, {repeatable = true})
    mp.add_forced_key_binding("K", "cfg-K", function() move_row(-1) end, {repeatable = true})
    mp.add_forced_key_binding("J", "cfg-J", function() move_row(1) end, {repeatable = true})
    mp.add_forced_key_binding("ENTER", "cfg-enter", toggle)
    mp.add_forced_key_binding("ESC", "cfg-esc", close)
    draw()
end

return M
