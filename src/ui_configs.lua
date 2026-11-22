local mp          = require 'mp'
local common      = require 'src.common'
local conf        = require 'src.conf'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local notify      = require 'src.notify'
local ui          = require 'src.ui'
local ui_input    = require 'src.ui_input'
local ui_confirm  = require 'src.ui_confirm'

local M = {}

local bindings = { "cfg-up", "cfg-down", "cfg-j", "cfg-k", "cfg-move-up", "cfg-move-down", "cfg-K", "cfg-J", "cfg-tab", "cfg-new", "cfg-rename", "cfg-delete", "cfg-search", "cfg-esc" }

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

function M.show(configs, on_apply, on_close)
    local rows    = { { name = "user", enabled = true, exists = true, pinned = true } }
    local changed = false
    for _, c in ipairs(configs) do rows[#rows + 1] = { name = c.name, enabled = c.enabled, exists = c.exists } end

    local function taken(name, except)
        local low = name:lower()
        for _, row in ipairs(rows) do
            if row.name:lower() == low and row ~= except then return true end
        end
        return false
    end

    local function name_error(name, except)
        local err = conf.config_name_error(name)
        if err then return lang.t(err, { name = name }) end
        if taken(name, except) then return lang.t("configs_exists", { name = name }) end
        return nil
    end

    local open

    local function ask_name(title, current, except, on_name, back)
        ui_input.show({
            title     = title,
            current   = current,
            hint      = lang.t("configs_hint_name"),
            preview   = function(input) return trim(input) ~= "" and name_error(trim(input), except) or "" end,
            on_cancel = back,
            on_submit = function(input)
                local name = trim(input):gsub("%.conf$", "")
                local err  = name_error(name, except)
                if name == "" or err then
                    if err then notify.show(err, true, "warn") end
                    return ask_name(title, current, except, on_name, back)
                end
                on_name(name)
            end
        })
    end

    open = function(cursor)
        local ov     = mp.create_osd_overlay("ass-events")
        local active = true
        local search

        ui.clear_osd()
        state.ui_owner = "configs"

        local function teardown()
            active         = false
            state.ui_owner = nil
            search.close()
            ov:remove()
            for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
        end

        local function close()
            if not active then return end
            teardown()
            if not changed then
                if on_close then on_close() end
                return
            end
            local list = {}
            for i = 2, #rows do list[#list + 1] = rows[i] end
            if on_apply then on_apply(list) end
        end

        local function labels()
            local out = {}
            for i, row in ipairs(rows) do out[i] = row.name end
            return out
        end

        local function visible()
            return ui.visible(#rows, function(i) return search.keep(rows[i].name) end)
        end

        local function draw()
            local vis = visible()
            if #vis > 0 and ui.position(vis, cursor) == 0 then cursor = vis[1] end
            local body = ui.list(#vis, ui.position(vis, cursor), function(k)
                local row     = rows[vis[k]]
                local val     = row.pinned and string.format("%s%s", theme.c("dim_text_color"), theme.escape(lang.t("configs_always")))
                    or row.enabled and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                    or string.format("%s%s", theme.c("off_color"), state.opts.off_text)
                local missing = row.exists and "" or string.format(" %s%s", theme.c("warning_color"), theme.escape(lang.t("configs_missing")))
                return string.format("%s %s%s", theme.escape(row.name), val, missing)
            end)
            if #vis == 0 then body = search.empty() end

            local hints = search.hints({ { "Up/Down", "navigate" }, { "Tab", "toggle" }, { "Shift+Up/Down", "move" }, { "n", "new" }, { "r", "rename" }, { "d", "delete" }, { "/", "search" }, { "Esc", "close" } })
            ov.data = search.title(lang.t("menu_settings_manager")) .. "\\N" .. body .. "\\N" .. ui.dim(lang.t("configs_dir", { dir = common.display_path(common.get_conf_dir()) })) .. ui.tooltip(hints)
            ov:update()
        end

        local function move_cursor(delta)
            cursor = ui.step(visible(), cursor, delta)
            draw()
        end

        local function move_row(delta)
            local target = cursor + delta
            if search.filtering() or rows[cursor].pinned or target < 2 or target > #rows then return end
            rows[cursor], rows[target] = rows[target], rows[cursor]
            cursor  = target
            changed = true
            draw()
        end

        local function toggle()
            local row = rows[cursor]
            if not row or #visible() == 0 or row.pinned then return end
            row.enabled = not row.enabled
            changed     = true
            draw()
        end

        local function pinned_warn(row)
            if not row.pinned then return false end
            notify.show(lang.t("configs_pinned", { name = row.name }), true, "warn")
            return true
        end

        local function create()
            teardown()
            ask_name(lang.t("configs_new"), nil, nil, function(name)
                if not conf.create_config(name) then
                    notify.show(lang.t("configs_write_failed", { name = name }), true, "error")
                    return open(cursor)
                end
                rows[#rows + 1] = { name = name, enabled = true, exists = true }
                changed         = true
                notify.show(lang.t("configs_created", { name = name }))
                open(#rows)
            end, function() open(cursor) end)
        end

        local function rename()
            local row = rows[cursor]
            if not row or #visible() == 0 or pinned_warn(row) then return end
            teardown()
            ask_name(lang.t("configs_rename", { name = row.name }), row.name, row, function(name)
                if row.exists and not conf.rename_config(row.name, name) then
                    notify.show(lang.t("configs_write_failed", { name = row.name }), true, "error")
                    return open(cursor)
                end
                notify.show(lang.t("configs_renamed", { from = row.name, to = name }))
                row.name = name
                changed  = true
                open(cursor)
            end, function() open(cursor) end)
        end

        local function delete()
            local row = rows[cursor]
            if not row or #visible() == 0 or pinned_warn(row) then return end
            teardown()
            ui_confirm.show(lang.t("configs_delete", { name = row.name }), common.display_path(conf.config_path(row.name)), function()
                if row.exists and not conf.delete_config(row.name) then
                    notify.show(lang.t("configs_write_failed", { name = row.name }), true, "error")
                    return open(cursor)
                end
                table.remove(rows, cursor)
                changed = true
                notify.show(lang.t("configs_deleted", { name = row.name }))
                open(math.min(cursor, #rows))
            end, function() open(cursor) end)
        end

        search = list_search.new({
            prefix = "cfg",
            labels = labels,
            redraw = draw,
            move   = move_cursor,
            pick   = function(i)
                cursor = i
                toggle()
            end
        })

        mp.add_forced_key_binding("UP", "cfg-up", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "cfg-down", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "cfg-j", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "cfg-k", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+UP", "cfg-move-up", function() move_row(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+DOWN", "cfg-move-down", function() move_row(1) end, {repeatable = true})
        mp.add_forced_key_binding("K", "cfg-K", function() move_row(-1) end, {repeatable = true})
        mp.add_forced_key_binding("J", "cfg-J", function() move_row(1) end, {repeatable = true})
        mp.add_forced_key_binding("TAB", "cfg-tab", toggle)
        mp.add_forced_key_binding("n", "cfg-new", create)
        mp.add_forced_key_binding("r", "cfg-rename", rename)
        mp.add_forced_key_binding("d", "cfg-delete", delete)
        mp.add_forced_key_binding("/", "cfg-search", search.start)
        mp.add_forced_key_binding("ESC", "cfg-esc", function()
            if search.filtering() then return search.clear() end
            close()
        end)
        draw()
    end

    open(1)
end

return M
