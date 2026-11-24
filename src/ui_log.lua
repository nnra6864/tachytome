local mp     = require 'mp'
local common = require 'src.common'
local state  = require 'src.state'
local notify = require 'src.notify'
local lang   = require 'src.lang'
local ui     = require 'src.ui'

local M = {}

local visible_lines = 20
local wrap_width    = 110

local function wrap(lines)
    local out = {}
    for _, line in ipairs(lines) do
        if common.text_len(line) <= wrap_width then
            out[#out + 1] = line
        else
            local chunk = ""
            for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                chunk = chunk .. char
                if common.text_len(chunk) >= wrap_width then
                    out[#out + 1] = chunk
                    chunk         = ""
                end
            end
            if chunk ~= "" then out[#out + 1] = chunk end
        end
    end
    return out
end

function M.show(title, lines, path, on_close)
    ui.clear_osd()
    state.ui_owner = "log"

    local ov       = mp.create_osd_overlay("ass-events")
    local shown    = wrap(lines)
    local top      = 1
    local bindings = {}

    local function bind(key, name, fn, opts)
        bindings[#bindings + 1] = name
        mp.add_forced_key_binding(key, name, fn, opts)
    end

    local function close()
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
        if on_close then on_close() end
    end

    local function draw()
        local last = math.min(#shown, top + visible_lines - 1)
        local page = {}
        if top > 1 then page[1] = "..." end
        for i = top, last do page[#page + 1] = shown[i] end
        if last < #shown then page[#page + 1] = "..." end
        local where = lang.t("log_lines", { from = top, to = last, count = #shown })
        local hints = ui.tooltip({ { "Up/Down", "scroll" }, { "PgUp/PgDn", "page" }, { "c", "copy" }, { "Esc", "close" } })
        ov.data = ui.title(title) .. (path and ui.dim(common.display_path(path)) or "") .. ui.dim(where) .. ui.dim_lines(page) .. "\\N" .. hints
        ov:update()
    end

    local function move(delta)
        top = math.max(1, math.min(#shown - visible_lines + 1, top + delta))
        draw()
    end

    local function copy()
        local ok = mp.set_property("clipboard/text", table.concat(lines, "\n"))
        if ok then
            notify.show(lang.t("log_copied"), true)
        else
            notify.show(lang.t("log_copy_failed", { path = path or "" }), true, "warn")
        end
    end

    bind("UP", "log-up", function() move(-1) end, {repeatable = true})
    bind("DOWN", "log-down", function() move(1) end, {repeatable = true})
    bind("k", "log-k", function() move(-1) end, {repeatable = true})
    bind("j", "log-j", function() move(1) end, {repeatable = true})
    bind("PGUP", "log-pgup", function() move(-visible_lines) end, {repeatable = true})
    bind("PGDWN", "log-pgdwn", function() move(visible_lines) end, {repeatable = true})
    bind("HOME", "log-home", function() move(-#shown) end)
    bind("END", "log-end", function() move(#shown) end)
    bind("c", "log-copy", copy)
    bind("ESC", "log-esc", close)
    draw()
end

return M
