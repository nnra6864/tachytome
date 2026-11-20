local mp          = require 'mp'
local common      = require 'src.common'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local ui          = require 'src.ui'

local M = {}

local bindings = { "cfg-up", "cfg-down", "cfg-j", "cfg-k", "cfg-move-up", "cfg-move-down", "cfg-K", "cfg-J", "cfg-enter", "cfg-search", "cfg-esc" }

function M.show(configs, on_apply, on_close)
    local ov      = mp.create_osd_overlay("ass-events")
    local active  = true
    local cursor  = 1
    local changed = false
    local rows    = {}
    local search
    for i, c in ipairs(configs) do rows[i] = { name = c.name, enabled = c.enabled, exists = c.exists } end

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
        if changed then
            if on_apply then on_apply(rows) end
        elseif on_close then
            on_close()
        end
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
            local val     = row.enabled
                and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                or  string.format("%s%s", theme.c("off_color"), state.opts.off_text)
            local missing = row.exists and "" or string.format(" %s%s", theme.c("warning_color"), theme.escape(lang.t("configs_missing")))
            return string.format("%s %s%s", theme.escape(row.name), val, missing)
        end)
        if #rows == 0 then
            body = ui.dim(lang.t("configs_empty", { dir = common.display_path(common.get_conf_dir()) }))
        elseif #vis == 0 then
            body = search.empty()
        end

        local hints = search.hints({ { "Up/Down", "navigate" }, { "Enter", "toggle" }, { "Shift+Up/Down", "move" }, { "/", "search" }, { "Esc", "apply" } })
        ov.data = search.title(lang.t("menu_configs")) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function move_cursor(delta)
        cursor = ui.step(visible(), cursor, delta)
        draw()
    end

    local function move_row(delta)
        local target = cursor + delta
        if search.filtering() or target < 1 or target > #rows then return end
        rows[cursor], rows[target] = rows[target], rows[cursor]
        cursor  = target
        changed = true
        draw()
    end

    local function toggle()
        local row = rows[cursor]
        if not row or #visible() == 0 then return end
        row.enabled = not row.enabled
        changed     = true
        draw()
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
    mp.add_forced_key_binding("ENTER", "cfg-enter", toggle)
    mp.add_forced_key_binding("/", "cfg-search", search.start)
    mp.add_forced_key_binding("ESC", "cfg-esc", function()
        if search.filtering() then return search.clear() end
        close()
    end)
    draw()
end

return M
