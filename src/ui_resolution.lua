local mp          = require 'mp'
local common      = require 'src.common'
local resolution  = require 'src.resolution'
local ui_input    = require 'src.ui_input'
local ui_list     = require 'src.ui_list'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local notify      = require 'src.notify'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local ui          = require 'src.ui'

local M = {}

local bindings = { "up", "down", "j", "k", "move-up", "move-down", "J", "K", "enter", "a", "m", "s", "d", "search", "esc" }

function M.set_enabled(enabled)
    state.resolution_enabled = enabled
    if enabled and state.opts.lossless_cut then
        state.opts.lossless_cut = false
        notify.show(lang.t("value_set", { label = lang.t("menu_lossless_cut"), value = lang.t("value_off") }))
    end
    notify.show(lang.t("value_set", { label = lang.t("menu_resolution"), value = lang.t(enabled and "value_on" or "value_off") }))
end

function M.set_chain(text)
    state.resolution = text
    if text ~= "" and not state.resolution_enabled then M.set_enabled(true) end
end

local function splice(list, at, remove, insert)
    local out = {}
    for i = 1, at - 1 do out[#out + 1] = list[i] end
    for _, item in ipairs(insert) do out[#out + 1] = item end
    for i = at + remove, #list do out[#out + 1] = list[i] end
    return out
end

local function pad(text, width)
    return theme.escape(text) .. string.rep("\\h", width - common.text_len(text))
end

function M.show(on_close)
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local cursor = 1
    local rows   = {}
    local layers = {}
    local search
    local open_ui

    local function remove_bindings()
        for _, name in ipairs(bindings) do mp.remove_key_binding("res-" .. name) end
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        remove_bindings()
        search.close()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function rebuild_rows()
        local was = rows[cursor]
        layers    = resolution.parse(state.resolution) or {}
        rows      = { { kind = "toggle" }, { kind = "chain" } }
        for i in ipairs(layers) do rows[#rows + 1] = { kind = "layer", index = i } end

        local list  = resolution.presets()
        local files = {}
        for _, p in ipairs(list) do
            if files[#files] ~= p.file then files[#files + 1] = p.file end
        end
        local file = nil
        for i, p in ipairs(list) do
            if i == 1 then rows[#rows + 1] = { kind = "gap" } end
            if p.file ~= file then
                file            = p.file
                rows[#rows + 1] = { kind = "header", text = #files > 1 and file or lang.t("resolution_presets") }
            end
            rows[#rows + 1] = { kind = "preset", preset = p }
        end

        if was and was.kind == "preset" then
            for i, row in ipairs(rows) do
                if row.preset == was.preset then cursor = i end
            end
        end
        if cursor > #rows then cursor = #rows end
    end

    local function commit(list)
        M.set_chain(resolution.format(list))
        rebuild_rows()
    end

    local function labels()
        local out = {}
        for i, row in ipairs(rows) do out[i] = row.kind == "preset" and row.preset.label or "" end
        return out
    end

    local function visible()
        if not search.filtering() then return ui.visible(#rows, function() return true end) end
        local names = labels()
        local keep  = {}
        for i, row in ipairs(rows) do
            if row.kind == "preset" and search.keep(names[i]) then
                keep[i] = true
                for h = i - 1, 1, -1 do
                    if rows[h].kind == "header" then
                        keep[h] = true
                        break
                    end
                end
            end
        end
        return ui.visible(#rows, function(i) return keep[i] end)
    end

    local function navigable(vis)
        local out = {}
        for _, i in ipairs(vis) do
            if rows[i].kind ~= "header" and rows[i].kind ~= "gap" then out[#out + 1] = i end
        end
        return out
    end

    local function draw()
        local steps, err = resolution.trace(state.resolution)
        local source     = resolution.source()
        steps            = steps or {}

        local vis = visible()
        local nav = navigable(vis)
        if #nav > 0 and ui.position(nav, cursor) == 0 then cursor = nav[1] end

        local current = state.resolution:lower():match("^%s*(.-)%s*$")
        local pwidth  = { 0, 0 }
        for _, row in ipairs(rows) do
            if row.kind == "preset" then
                pwidth[1] = math.max(pwidth[1], common.text_len(row.preset.label))
                pwidth[2] = math.max(pwidth[2], common.text_len(row.preset.chain))
            end
        end

        local o       = state.opts
        local default = o.scaler_down == o.scaler_up and o.scaler_down or o.scaler_down .. "/" .. o.scaler_up
        local cells   = {}
        local width   = { 0, 0, 0 }
        for i, layer in ipairs(layers) do
            local step   = steps[i]
            local mode   = resolution.keeps_aspect(layer) and "-" or (layer.mode or (layer.kind == "preset" and "-" or o.resolution_mode))
            local scaler = layer.scaler or (step and (step.scaler or "-")) or default
            local cell   = { layer.size, mode, scaler }
            for c = 1, 3 do width[c] = math.max(width[c], common.text_len(cell[c])) end
            cells[i] = cell
        end

        local body = ui.list(#vis, ui.position(vis, cursor), function(k)
            local row = rows[vis[k]]
            if row.kind == "gap" then
                return ""
            elseif row.kind == "header" then
                return string.format("%s%s", theme.c("dim_text_color"), theme.escape(row.text))
            elseif row.kind == "preset" then
                local p      = row.preset
                local name   = pad(p.label, pwidth[1])
                local marker = (current == p.label or current == p.id) and string.format(" %s%s", theme.c("on_color"), state.opts.on_text) or ""
                local out    = source and resolution.output(p.label)
                local size   = out and string.format("%s-> %s", theme.c("dim_text_color"), out) or ""
                return string.format("\\h%s\\h\\h%s%s%s\\h\\h%s%s", name, theme.c("dim_text_color"), pad(p.chain, pwidth[2]), theme.c("text_color"), size, marker)
            elseif row.kind == "toggle" then
                local val = state.resolution_enabled
                    and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                    or  string.format("%s%s", theme.c("off_color"), state.opts.off_text)
                return string.format("%s > %s", theme.escape(lang.t("menu_resolution")), val)
            elseif row.kind == "chain" then
                local chain = state.resolution ~= "" and state.resolution or lang.t("value_none")
                return string.format("%s > %s%s", theme.escape(lang.t("resolution_chain")), theme.c("value_color"), theme.escape(chain))
            end

            local layer = layers[row.index]
            local cell  = cells[row.index]
            local step  = steps[row.index]
            local prev  = steps[row.index - 1] or steps.source
            local mode  = pad(cell[2], width[2])
            local sc    = pad(cell[3], width[3])
            mode        = layer.mode and theme.c("value_color") .. mode .. theme.c("text_color") or mode
            sc          = layer.scaler and theme.c("value_color") .. sc .. theme.c("text_color") or sc
            local sizes = ""
            if step and prev then
                sizes = string.format("%s%s -> %s", theme.c("dim_text_color"), resolution.dims(prev), resolution.dims(step))
            elseif err and row.index == #steps + 1 then
                sizes = string.format("%s!", theme.c("error_color"))
            end
            return string.format("\\h%s\\h\\h%s\\h\\h%s\\h\\h%s", pad(cell[1], width[1]), mode, sc, sizes)
        end)

        if #vis == 0 then body = search.empty() end

        local summary = err or (source and resolution.describe(state.resolution) or lang.t("no_video"))
        local head    = search.title(lang.t("menu_resolution"))
        if summary ~= "" and not search.filtering() then head = head .. ui.dim(summary) end

        local row   = rows[cursor]
        local hints = { { "Up/Down", "navigate" }, { "Enter", "edit" }, { "a", "add" }, { "/", "search" }, { "Esc", "close" } }
        if row and row.kind == "preset" then
            hints = { { "Up/Down", "navigate" }, { "Enter", "use" }, { "a", "add" }, { "/", "search" }, { "Esc", "close" } }
        elseif row and row.kind == "layer" then
            hints = { { "Up/Down", "navigate" }, { "Enter", "edit" }, { "a", "add" }, { "m", "mode" }, { "s", "scaler" }, { "d", "delete" }, { "Shift+Up/Down", "move" }, { "/", "search" }, { "Esc", "close" } }
        end
        ov.data = head .. "\\N" .. body .. "\\N" .. ui.tooltip(search.hints(hints))
        ov:update()
    end

    local function prompt(title, current, allow_empty, compose)
        teardown()
        ui_input.show({
            title       = string.format("%s %s %s", lang.t("menu_resolution"), state.opts.menu_path_separator, title),
            current     = current,
            hint        = lang.t("hint_resolution"),
            history     = resolution.history,
            allow_space = true,
            on_cancel   = open_ui,
            preview     = function(input)
                local parsed, bad = resolution.parse(input)
                if not parsed then return lang.t("resolution_unknown", { token = bad }) end
                return resolution.describe(resolution.format(compose(parsed)))
            end,
            on_submit   = function(input)
                local parsed, bad = resolution.parse(input)
                if not parsed then
                    notify.show(lang.t("resolution_unknown", { token = bad }), true, "warn")
                elseif #parsed > 0 or allow_empty then
                    resolution.remember(input)
                    commit(compose(parsed))
                end
                open_ui()
            end
        })
    end

    local function use_preset(p)
        M.set_chain(p.label)
        rebuild_rows()
        draw()
    end

    local function edit_row()
        local row = rows[cursor]
        if not row or #navigable(visible()) == 0 then return end
        if row.kind == "preset" then
            use_preset(row.preset)
        elseif row.kind == "toggle" then
            M.set_enabled(not state.resolution_enabled)
            draw()
        elseif row.kind == "chain" then
            prompt(lang.t("resolution_chain"), state.resolution, true, function(parsed) return parsed end)
        else
            local i = row.index
            prompt(lang.t("resolution_layer"), resolution.layer_text(layers[i]), false, function(parsed) return splice(layers, i, 1, parsed) end)
        end
    end

    local function add_layer()
        local row = rows[cursor]
        local at  = (row and row.kind == "layer") and row.index + 1 or #layers + 1
        if row and row.kind == "preset" then
            if #navigable(visible()) == 0 then return end
            commit(splice(layers, at, 0, resolution.parse(row.preset.label) or {}))
            draw()
            return
        end
        prompt(lang.t("resolution_add"), "", false, function(parsed)
            return splice(layers, at, 0, parsed)
        end)
    end

    local function pick_option(key, options, default)
        local row = rows[cursor]
        if not row or row.kind ~= "layer" then return end
        local layer = layers[row.index]
        if key == "mode" and resolution.keeps_aspect(layer) then return end

        local fallback = lang.t("resolution_default", { value = default })
        local items    = { fallback }
        for _, opt in ipairs(options) do items[#items + 1] = opt end
        local title    = string.format("%s %s %s", lang.t("menu_resolution"), state.opts.menu_path_separator, lang.t("resolution_" .. key))

        teardown()
        ui_list.show(title, items, layer[key] or fallback, function(val)
            layer[key] = val ~= fallback and val or nil
            commit(layers)
            open_ui()
        end, open_ui)
    end

    local function pick_mode()
        pick_option("mode", resolution.modes, state.opts.resolution_mode)
    end

    local function pick_scaler()
        local o = state.opts
        pick_option("scaler", resolution.scalers, o.scaler_down == o.scaler_up and o.scaler_down or o.scaler_down .. "/" .. o.scaler_up)
    end

    local function delete_layer()
        local row = rows[cursor]
        if not row or row.kind ~= "layer" or search.filtering() then return end
        table.remove(layers, row.index)
        commit(layers)
        draw()
    end

    local function move_layer(delta)
        local row = rows[cursor]
        if not row or row.kind ~= "layer" or search.filtering() then return end
        local i, j = row.index, row.index + delta
        if not layers[j] then return end
        layers[i], layers[j] = layers[j], layers[i]
        cursor               = cursor + delta
        commit(layers)
        draw()
    end

    local function move(delta)
        cursor = ui.step(navigable(visible()), cursor, delta)
        draw()
    end

    search = list_search.new({
        prefix = "res",
        labels = labels,
        redraw = draw,
        move   = move,
        pick   = function(i)
            cursor = i
            use_preset(rows[i].preset)
        end
    })

    local function bind()
        mp.add_forced_key_binding("UP", "res-up", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "res-down", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "res-k", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "res-j", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+UP", "res-move-up", function() move_layer(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+DOWN", "res-move-down", function() move_layer(1) end, {repeatable = true})
        mp.add_forced_key_binding("K", "res-K", function() move_layer(-1) end, {repeatable = true})
        mp.add_forced_key_binding("J", "res-J", function() move_layer(1) end, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "res-enter", edit_row)
        mp.add_forced_key_binding("a", "res-a", add_layer)
        mp.add_forced_key_binding("m", "res-m", pick_mode)
        mp.add_forced_key_binding("s", "res-s", pick_scaler)
        mp.add_forced_key_binding("d", "res-d", delete_layer)
        mp.add_forced_key_binding("/", "res-search", search.start)
        mp.add_forced_key_binding("ESC", "res-esc", function()
            if search.filtering() then return search.clear() end
            cleanup()
        end)
    end

    open_ui = function()
        rebuild_rows()
        ui.clear_osd()

        active         = true
        state.ui_owner = "resolution"
        bind()
        draw()
    end

    open_ui()
end

return M
