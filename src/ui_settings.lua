local mp          = require 'mp'
local common      = require 'src.common'
local conf        = require 'src.conf'
local effects     = require 'src.effects'
local resolution  = require 'src.resolution'
local tracks      = require 'src.tracks'
local menus       = require 'src.menus'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local notify      = require 'src.notify'
local ui          = require 'src.ui'
local ui_input    = require 'src.ui_input'
local ui_list     = require 'src.ui_list'
local ui_choice   = require 'src.ui_choice'

local M = {}

local bindings = { "set-up", "set-down", "set-j", "set-k", "set-enter", "set-unset", "set-unset-all", "set-load", "set-save", "set-search", "set-esc" }
local groups   = {
    effects_enabled    = "effects",
    effects_presets    = "effects",
    resolution_enabled = "resolution",
    resolution         = "resolution",
    tracks             = "tracks"
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function snapshot()
    return {
        opts               = copy(state.opts),
        effects            = copy(state.effects),
        effects_enabled    = state.effects_enabled,
        resolution         = state.resolution,
        resolution_enabled = state.resolution_enabled,
        tracks             = state.tracks
    }
end

local function restore(snap)
    for k, v in pairs(snap.opts) do state.opts[k] = v end
    state.effects            = copy(snap.effects)
    state.effects_enabled    = snap.effects_enabled
    state.resolution         = snap.resolution
    state.resolution_enabled = snap.resolution_enabled
    state.tracks             = snap.tracks
end

local function effect_name(inst)
    local p = effects.preset(inst.name)
    if p and effects.preset(p.name) == p then return p.name end
    return inst.name
end

local function current()
    local vals = {}
    for key, val in pairs(state.opts) do vals[key] = conf.format(val) end
    local names = {}
    for _, inst in ipairs(state.effects) do names[#names + 1] = effect_name(inst) end
    vals.effects_enabled    = conf.format(state.effects_enabled)
    vals.effects_presets    = table.concat(names, ",")
    vals.resolution_enabled = conf.format(state.resolution_enabled)
    vals.resolution         = state.resolution
    vals.tracks             = state.tracks
    return vals
end

local function shown(val)
    if val == "" then return "\"\"" end
    return val
end

local choices = {
    selected_menu = function() return menus.names() end,
    language      = function()
        local codes = { "auto" }
        for _, code in ipairs(lang.available()) do codes[#codes + 1] = code end
        return codes
    end
}

function M.show(name, enabled, pickers, on_close)
    local keys    = conf.keys()
    local known   = {}
    local own     = conf.file_options(name)
    local values  = {}
    local touched = {}
    local start   = snapshot()
    local live    = current()
    local cleared = {}
    local cursor  = 1
    for _, key in ipairs(keys) do known[key] = true end
    for key in pairs(own) do cleared[key] = false end
    local inherited = conf.resolve(name, cleared)
    local effective = conf.resolve(name, values)

    local function value(key)
        if values[key] ~= nil then return values[key] or nil end
        return own[key]
    end

    local function dirty()
        return next(values) ~= nil
    end

    local function set(key, val)
        if val == (own[key] or false) then
            values[key] = nil
        else
            values[key] = val
        end
        touched[key] = true
    end

    local function push(list, all)
        local seed = {}
        for key in pairs(list) do
            local edited = all or values[key] ~= nil
            if edited then
                state.opts[key] = effective[key]
            else
                state.opts[key] = start.opts[key]
            end
            local group = groups[key]
            if group then seed[group] = seed[group] or edited end
        end
        if seed.effects then
            effects.seed()
        elseif seed.effects == false then
            state.effects         = copy(start.effects)
            state.effects_enabled = start.effects_enabled
        end
        if seed.resolution then
            resolution.seed()
        elseif seed.resolution == false then
            state.resolution         = start.resolution
            state.resolution_enabled = start.resolution_enabled
        end
        if seed.tracks then
            tracks.reset()
        elseif seed.tracks == false then
            state.tracks = start.tracks
        end
        if list.language then lang.load() end
    end

    local function apply_live()
        effective = conf.resolve(name, values)
        push(touched, false)
    end

    local function revert()
        restore(start)
        if touched.language then lang.load() end
        touched = {}
    end

    local open

    local function save(after)
        if not conf.save_options(name, values) then
            notify.show(lang.t("settings_save_failed", { name = name }), true, "error")
            return open()
        end
        own    = conf.file_options(name)
        values = {}
        notify.show(lang.t("settings_saved", { name = name }))
        local function keep()
            start   = snapshot()
            touched = {}
            after()
        end
        if enabled then return keep() end
        ui_choice.show(lang.t("settings_enable", { name = name }), common.display_path(conf.main_path()), {
            { key = "1", alt = "ENTER", label = lang.t("choice_yes") },
            { key = "2", label = lang.t("choice_no") }
        }, 2, function(idx)
            if idx == 1 then
                for _, c in ipairs(conf.configs) do
                    if c.name == name then c.enabled = true end
                end
                conf.write_configs(conf.configs)
                enabled   = true
                effective = conf.resolve(name, values)
                push(own, true)
                notify.show(lang.t("configs_applied", { list = name }))
                return keep()
            end
            revert()
            after()
        end)
    end

    open = function()
        local ov     = mp.create_osd_overlay("ass-events")
        local active = true
        local search

        ui.clear_osd()
        state.ui_owner = "settings"

        local function teardown()
            active         = false
            state.ui_owner = nil
            search.close()
            ov:remove()
            for _, b in ipairs(bindings) do mp.remove_key_binding(b) end
        end

        local function finish()
            if on_close then on_close() end
        end

        local function visible()
            return ui.visible(#keys, function(i) return search.keep(keys[i]) end)
        end

        local function value_text(key, val)
            local swatch = key:find("_color$") and theme.swatch(val)
            if swatch then return swatch end
            return string.format("%s%s", theme.c("value_color"), theme.escape(shown(val)))
        end

        local function row_text(key)
            local val = value(key)
            local eff = conf.format(effective[key])
            if not val then
                return string.format("%s%s %s", theme.c("dim_text_color"), theme.escape(key), value_text(key, eff))
            end
            local mark = values[key] ~= nil and "*" or ""
            local over = eff ~= val and string.format(" %s%s", theme.c("warning_color"), theme.escape(lang.t("settings_overridden", { value = shown(eff) }))) or ""
            return string.format("%s%s %s%s", theme.escape(key), mark, value_text(key, val), over)
        end

        local function draw()
            if not active then return end
            local vis = visible()
            if #vis > 0 and ui.position(vis, cursor) == 0 then cursor = vis[1] end
            local body = ui.list(#vis, ui.position(vis, cursor), function(k) return row_text(keys[vis[k]]) end)
            if #vis == 0 then
                body = search.empty()
            else
                body = body .. ui.dim_lines(conf.describe(keys[cursor]))
            end

            local title = lang.t("settings_editor", { name = name .. ".conf" }) .. (dirty() and " *" or "")
            local hints = search.hints({ { "Up/Down", "navigate" }, { "Enter", "edit" }, { "u", "unset" }, { "U", "unset_all" }, { "l", "load_current" }, { "s", "save" }, { "/", "search" }, { "Esc", "close" } })
            ov.data = search.title(title) .. "\\N" .. body .. ui.tooltip(hints)
            ov:update()
        end

        local function move_cursor(delta)
            cursor = ui.step(visible(), cursor, delta)
            draw()
        end

        local function changed(key, val)
            set(key, val)
            apply_live()
        end

        local function edit()
            if #visible() == 0 then return end
            local key = keys[cursor]
            local cur = value(key) or conf.format(effective[key])
            if type(conf.default(key)) == "boolean" then
                changed(key, conf.format(cur ~= "yes"))
                return draw()
            end

            teardown()
            if pickers[key] then
                local before = current()
                local snap   = snapshot()
                return pickers[key](function()
                    local after = current()
                    restore(snap)
                    for k, v in pairs(after) do
                        if known[k] and v ~= before[k] then set(k, v) end
                    end
                    apply_live()
                    open()
                end)
            end
            if choices[key] then
                return ui_list.show(key, choices[key](), cur, function(val)
                    changed(key, val)
                    open()
                end, open)
            end
            ui_input.show({
                title       = key,
                current     = cur,
                allow_space = true,
                on_cancel   = open,
                on_submit   = function(input)
                    local conv = conf.parse_value(key, input)
                    if conv == nil then
                        notify.show(lang.t("settings_invalid", { key = key, value = input }), true, "warn")
                    else
                        changed(key, conf.format(conv))
                    end
                    open()
                end
            })
        end

        local function unset()
            if #visible() == 0 then return end
            changed(keys[cursor], false)
            draw()
        end

        local function unset_all()
            for _, key in ipairs(keys) do
                if value(key) then set(key, false) end
            end
            apply_live()
            draw()
        end

        local function load_current()
            local count = 0
            for _, key in ipairs(keys) do
                local val = value(key)
                if live[key] ~= conf.format(inherited[key]) and live[key] ~= val then
                    set(key, live[key])
                    count = count + 1
                elseif live[key] == conf.format(inherited[key]) and val and val ~= live[key] then
                    set(key, false)
                    count = count + 1
                end
            end
            apply_live()
            notify.show(lang.t("settings_loaded", { count = count }))
            draw()
        end

        local function close()
            if search.filtering() then return search.clear() end
            teardown()
            if not dirty() then return finish() end
            ui_choice.show(lang.t("settings_unsaved", { name = name .. ".conf" }), "", {
                { key = "1", alt = "ENTER", label = lang.t("choice_save") },
                { key = "2", label = lang.t("choice_discard") },
                { key = "3", label = lang.t("choice_cancel") }
            }, 3, function(idx)
                if idx == 1 then
                    save(finish)
                elseif idx == 2 then
                    values = {}
                    revert()
                    finish()
                else
                    open()
                end
            end)
        end

        search = list_search.new({
            prefix = "set",
            labels = function() return keys end,
            redraw = draw,
            move   = move_cursor,
            pick   = function(i)
                cursor = i
                draw()
            end
        })

        mp.add_forced_key_binding("UP", "set-up", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "set-down", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "set-j", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "set-k", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "set-enter", edit)
        mp.add_forced_key_binding("u", "set-unset", unset)
        mp.add_forced_key_binding("U", "set-unset-all", unset_all)
        mp.add_forced_key_binding("l", "set-load", load_current)
        mp.add_forced_key_binding("s", "set-save", function()
            if not dirty() then return end
            teardown()
            save(open)
        end)
        mp.add_forced_key_binding("/", "set-search", search.start)
        mp.add_forced_key_binding("ESC", "set-esc", close)
        draw()
    end

    open()
end

return M
