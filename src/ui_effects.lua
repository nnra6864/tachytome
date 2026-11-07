local mp        = require 'mp'
local effects   = require 'src.effects'
local ui_input  = require 'src.ui_input'
local state     = require 'src.state'
local notify    = require 'src.notify'
local theme     = require 'src.theme'
local lang      = require 'src.lang'
local ui        = require 'src.ui'

local M = {}

function M.show(on_close)
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local cursor = 1
    local rows   = {}

    local function remove_bindings()
        mp.remove_key_binding("fx-up")
        mp.remove_key_binding("fx-down")
        mp.remove_key_binding("fx-j")
        mp.remove_key_binding("fx-k")
        mp.remove_key_binding("fx-enter")
        mp.remove_key_binding("fx-d")
        mp.remove_key_binding("fx-esc")
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        remove_bindings()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function rebuild_rows()
        rows = { { kind = "toggle" } }
        local file = nil
        for _, p in ipairs(effects.list()) do
            if p.file ~= file then
                file            = p.file
                rows[#rows + 1] = { kind = "header", file = file }
            end
            rows[#rows + 1] = { kind = "preset", preset = p }
        end
    end

    local function draw()
        local body = ui.list(#rows, cursor, function(i)
            local row = rows[i]
            if row.kind == "toggle" then
                local val = state.effects_enabled
                    and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                    or  string.format("%s%s", theme.c("off_color"), state.opts.off_text)
                return string.format("%s > %s", theme.escape(lang.t("effects_enabled")), val)
            elseif row.kind == "header" then
                return string.format("%s%s", theme.c("dim_text_color"), theme.escape(row.file))
            end
            local marker = effects.instance(row.preset.id) and string.format(" %s%s", theme.c("on_color"), state.opts.on_text) or ""
            return string.format("\\h%s%s", theme.escape(row.preset.label), marker)
        end)
        local hints = { { "Up/Down", "navigate" }, { "Enter", "toggle" }, { "d", "edit" }, { "Esc", "close" } }
        ov.data = ui.title(lang.t("menu_effects")) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function set_enabled(enabled)
        state.effects_enabled = enabled
        if enabled and state.opts.lossless_cut then
            state.opts.lossless_cut = false
            notify.show(lang.t("value_set", { label = lang.t("menu_lossless_cut"), value = lang.t("value_off") }))
        end
        notify.show(lang.t("value_set", { label = lang.t("menu_effects"), value = lang.t(enabled and "effects_on" or "effects_off") }))
    end

    local open_ui
    local prompt_params

    local function apply_instance(name, params)
        local inst = effects.instance(name)
        if inst then
            inst.params = params
        else
            state.effects[#state.effects + 1] = { name = name, params = params }
        end
        notify.show(lang.t("effects_added", { name = effects.label(name) }))
    end

    prompt_params = function(p, params, idx)
        local prompts = {}
        if p.d then prompts[#prompts + 1] = { key = "d", label = lang.t("effects_duration"), default = params.d or p.d } end
        if p.params then
            for _, prm in ipairs(p.params) do
                local curve = effects.is_curve(prm.default)
                prompts[#prompts + 1] = {
                    key     = prm.key,
                    label   = prm.key,
                    hint    = curve and lang.t("hint_easing") or nil,
                    curve   = curve,
                    default = params[prm.key] or prm.default
                }
            end
        end

        if idx > #prompts then
            apply_instance(p.id, params)
            open_ui()
            return
        end

        local pr = prompts[idx]
        ui_input.show({
            title     = string.format("%s %s %s", p.label, state.opts.menu_path_separator, pr.label),
            current   = pr.default,
            hint      = pr.hint,
            on_cancel = open_ui,
            on_submit = function(input)
                if input == "" then input = tostring(pr.default) end
                local num     = tonumber(input)
                local numeric = type(pr.default) == "number"
                local ok      = false
                if pr.key == "d" then
                    ok = num ~= nil and num > 0
                elseif pr.curve then
                    ok = effects.is_curve(input)
                elseif numeric then
                    ok = num ~= nil
                else
                    ok = input ~= ""
                end
                if ok then
                    params[pr.key] = numeric and num or input
                    prompt_params(p, params, idx + 1)
                else
                    notify.show(lang.t("value_invalid", { label = pr.label, value = input }), true, "warn")
                    open_ui()
                end
            end
        })
    end

    local function toggle_preset(p)
        for i, inst in ipairs(state.effects) do
            if inst.name == p.id then
                table.remove(state.effects, i)
                notify.show(lang.t("effects_removed", { name = p.label }))
                draw()
                return
            end
        end
        apply_instance(p.id, {})
        draw()
    end

    local function edit_preset(p)
        local inst   = effects.instance(p.id)
        local params = {}
        if inst then
            for k, val in pairs(inst.params) do params[k] = val end
        end
        teardown()
        prompt_params(p, params, 1)
    end

    local function bind()
        local function move(delta)
            local target = cursor + delta
            while rows[target] and rows[target].kind == "header" do target = target + delta end
            if rows[target] then cursor = target; draw() end
        end

        local function move_up() move(-1) end
        local function move_down() move(1) end

        mp.add_forced_key_binding("UP", "fx-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "fx-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("j", "fx-j", move_down, {repeatable = true})
        mp.add_forced_key_binding("k", "fx-k", move_up, {repeatable = true})

        mp.add_forced_key_binding("ENTER", "fx-enter", function()
            local row = rows[cursor]
            if not row then return end
            if row.kind == "toggle" then
                set_enabled(not state.effects_enabled)
                draw()
            else
                toggle_preset(row.preset)
            end
        end)

        mp.add_forced_key_binding("d", "fx-d", function()
            local row = rows[cursor]
            if row and row.kind == "preset" then edit_preset(row.preset) end
        end)

        mp.add_forced_key_binding("ESC", "fx-esc", cleanup)
    end

    open_ui = function()
        rebuild_rows()
        if cursor > #rows then cursor = #rows end

        ui.clear_osd()

        active        = true
        state.ui_owner = "effects"
        bind()
        draw()
    end

    open_ui()
end

return M
