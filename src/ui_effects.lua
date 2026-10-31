local mp        = require 'mp'
local effects   = require 'src.effects'
local ui_input  = require 'src.ui_input'
local state     = require 'src.state'
local notify    = require 'src.notify'
local theme     = require 'src.theme'

local M = {}

function M.show(on_close)
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local cursor = 1
    local rows   = {}

    local function remove_bindings()
        mp.remove_key_binding("fx-up")
        mp.remove_key_binding("fx-down")
        mp.remove_key_binding("fx-cj")
        mp.remove_key_binding("fx-ck")
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
        for _, p in ipairs(effects.list()) do
            rows[#rows + 1] = { kind = "preset", preset = p }
        end
    end

    local function draw()
        local text = string.format("%s%s%sEffects%s\\N%s(Up/Down to navigate, Enter to toggle/select, d to edit, Esc to close)\\N\\N",
            theme.align(7), theme.f(), theme.b(true), theme.b(false), theme.f(true))

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#rows, start_idx + 14)
        if end_idx - start_idx < 14 then start_idx = math.max(1, end_idx - 14) end

        if start_idx > 1 then text = text .. "\\h\\h...\\N" end

        for i = start_idx, end_idx do
            local row    = rows[i]
            local prefix = (i == cursor) and string.format("%s\\h> ", theme.c("value_color")) or "\\h\\h"
            local line   = nil

            if row.kind == "toggle" then
                local val = state.effects_enabled
                    and string.format("%s%s%s", theme.c("on_color"), state.opts.on_text, theme.reset())
                    or  string.format("%s%s%s", theme.c("off_color"), state.opts.off_text, theme.reset())
                line = string.format("Enabled > %s", val)
            else
                local name    = row.preset.name
                local sel     = effects.instance(name)
                local summary = effects.summary_for(name)
                local marker  = sel
                    and string.format(" %s%s", theme.c("on_color"), state.opts.on_text)
                    or  ""
                line = string.format("%s%s%s", summary, marker, theme.reset())
            end

            text = text .. string.format("%s%s%s%s\\N", theme.c("text_color"), prefix, line, theme.reset())
        end

        if end_idx < #rows then text = text .. "\\h\\h...\\N" end

        ov.data = text
        ov:update()
    end

    local function set_enabled(enabled)
        state.effects_enabled = enabled
        if enabled and state.opts.lossless_cut then
            state.opts.lossless_cut = false
            state.opts.accurate_cut = true
            notify.show("Lossless Cut: '" .. tostring(state.opts.lossless_cut) .. "'")
            notify.show("Accurate Cut: '" .. tostring(state.opts.accurate_cut) .. "'")
        end
        notify.show("Effects: '" .. tostring(state.effects_enabled) .. "'")
    end

    local open_ui
    local prompt_params

    local function apply_instance(name, params)
        for i, inst in ipairs(state.effects) do
            if inst.name == name then
                table.remove(state.effects, i)
                break
            end
        end
        state.effects[#state.effects + 1] = { name = name, params = params }
        notify.show("Effect set: " .. effects.summary_for(name))
    end

    prompt_params = function(p, params, idx)
        local prompts = {}
        if p.d then prompts[#prompts + 1] = { key = "d", label = "Duration (s)", default = params.d or p.d } end
        if p.params then
            for _, prm in ipairs(p.params) do
                prompts[#prompts + 1] = { key = prm.key, label = prm.key, default = params[prm.key] or prm.default }
            end
        end

        if idx > #prompts then
            apply_instance(p.name, params)
            open_ui()
            return
        end

        local pr = prompts[idx]
        ui_input.get_user_input(string.format("%s > ", pr.label), function(input)
            if input == "" then input = tostring(pr.default) end
            local num = tonumber(input)
            if num and num > 0 then
                params[pr.key] = num
                prompt_params(p, params, idx + 1)
            else
                notify.show(string.format("Invalid %s, effect cancelled", pr.label), true, "warn")
                open_ui()
            end
        end, tostring(pr.default), true, nil, function()
            open_ui()
        end)
    end

    local function select_preset(p)
        teardown()
        if effects.instance(p.name) then
            for i, inst in ipairs(state.effects) do
                if inst.name == p.name then
                    table.remove(state.effects, i)
                    break
                end
            end
            notify.show("Effect removed: " .. p.label)
            open_ui()
            return
        end
        prompt_params(p, {}, 1)
    end

    local function edit_preset(p)
        teardown()
        prompt_params(p, {}, 1)
    end

    local function bind()
        local function move_up()
            if cursor > 1 then cursor = cursor - 1; draw() end
        end

        local function move_down()
            if cursor < #rows then cursor = cursor + 1; draw() end
        end

        mp.add_forced_key_binding("UP", "fx-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "fx-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("ctrl+j", "fx-cj", move_down, {repeatable = true})
        mp.add_forced_key_binding("ctrl+k", "fx-ck", move_up, {repeatable = true})

        mp.add_forced_key_binding("ENTER", "fx-enter", function()
            local row = rows[cursor]
            if not row then return end
            if row.kind == "toggle" then
                set_enabled(not state.effects_enabled)
                draw()
            else
                select_preset(row.preset)
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

        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)

        active         = true
        state.ui_owner = "effects"
        bind()
        draw()
    end

    open_ui()
end

return M
