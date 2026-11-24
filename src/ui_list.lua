local mp          = require 'mp'
local common      = require 'src.common'
local state       = require 'src.state'
local theme       = require 'src.theme'
local list_search = require 'src.list_search'
local ui          = require 'src.ui'

local M = {}

local bindings = { "list-up", "list-down", "list-j", "list-k", "list-enter", "list-search", "list-esc" }
for i = 1, 10 do bindings[#bindings + 1] = "list-" .. i end

local current = nil

function M.cancel()
    if current then current() end
end

function M.show(title, items, current_val, on_select, on_cancel, opts)
    ui.clear_osd()
    state.ui_owner = "list"
    opts           = opts or {}

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1
    local keys   = opts.keys or {}
    local width  = 0
    local search
    local pick

    if opts.detail then
        for _, item in ipairs(items) do width = math.max(width, common.text_len(item)) end
    end

    for i, item in ipairs(items) do
        if item == current_val then
            cursor = i
            break
        end
    end

    local function teardown()
        active         = false
        state.ui_owner = nil
        current        = nil
        search.close()
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
        for _, key in ipairs(keys) do mp.remove_key_binding("list-key-" .. key[1]) end
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_cancel then on_cancel() end
    end

    local function visible()
        return ui.visible(#items, function(i) return search.keep(items[i]) end)
    end

    local function draw()
        local vis = visible()
        if #vis > 0 and ui.position(vis, cursor) == 0 then cursor = vis[1] end
        local tips = {}
        if opts.describe then
            for i = 1, #items do tips[i] = opts.describe(i) or {} end
        end
        local body = ui.list(#vis, ui.position(vis, cursor), function(k)
            local i      = vis[k]
            local marker = items[i] == current_val and string.format(" %s%s", theme.c("on_color"), state.opts.on_text) or ""
            local detail = ""
            if opts.detail then
                local pad = string.rep("\\h", width - common.text_len(items[i]))
                detail    = string.format("%s\\h\\h%s%s%s", pad, theme.c("dim_text_color"), opts.detail(i), theme.c("text_color"))
            end
            return ui.number_prefix(k) .. theme.escape(items[i]) .. detail .. marker
        end, opts.describe and ui.tip_lines(tips) or nil)
        if #vis == 0 then body = #items == 0 and opts.empty and ui.dim(opts.empty) or search.empty() end
        local hints = { { "Up/Down", "navigate" }, { "0-9/Enter", opts.action or "select" } }
        for _, key in ipairs(keys) do hints[#hints + 1] = { key[1], key[2] } end
        hints[#hints + 1] = { "/", "search" }
        hints[#hints + 1] = { "Esc", "cancel" }
        hints             = search.hints(hints)
        if opts.describe and #vis > 0 then body = body .. ui.tips(tips[cursor]) end
        ov.data = search.title(title) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function move(delta)
        cursor = ui.step(visible(), cursor, delta)
        draw()
    end

    pick = function(i)
        local val = items[i]
        if val == nil then return end
        teardown()
        if on_select then on_select(val, i) end
    end

    search = list_search.new({
        prefix = "list",
        labels = function() return items end,
        redraw = draw,
        move   = move,
        pick   = pick
    })

    local function escape()
        if search.filtering() then return search.clear() end
        cleanup()
    end
    current = cleanup

    mp.add_forced_key_binding("UP", "list-up", function() move(-1) end, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "list-down", function() move(1) end, {repeatable = true})
    mp.add_forced_key_binding("j", "list-j", function() move(1) end, {repeatable = true})
    mp.add_forced_key_binding("k", "list-k", function() move(-1) end, {repeatable = true})
    mp.add_forced_key_binding("ENTER", "list-enter", function()
        if #visible() > 0 then pick(cursor) end
    end)
    for n = 1, 10 do
        mp.add_forced_key_binding(ui.number_key(n), "list-" .. n, function()
            local i = visible()[n]
            if i then pick(i) end
        end)
    end
    for _, key in ipairs(keys) do
        mp.add_forced_key_binding(key[1], "list-key-" .. key[1], function()
            if #visible() == 0 and not key.any then return end
            local i = cursor
            teardown()
            key[3](items[i], i)
        end)
    end
    mp.add_forced_key_binding("/", "list-search", search.start)
    mp.add_forced_key_binding("ESC", "list-esc", escape)
    draw()
end

return M
