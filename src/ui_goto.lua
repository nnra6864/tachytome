local mp     = require 'mp'
local common = require 'src.common'
local notify = require 'src.notify'
local state  = require 'src.state'
local theme  = require 'src.theme'
local lang   = require 'src.lang'
local edit   = require 'src.text_edit'
local ui     = require 'src.ui'

local M = {}

local overlay          = mp.create_osd_overlay("ass-events")
local layers           = edit.create_layers()
local active           = false
local input            = ""
local cursor           = 0
local current_callback = nil
local current_options  = {}
local current_place    = nil
local current_title    = ""
local current_error    = nil

local key_mappings   = {}
local standard_chars = "0123456789:.dhmsf%+-[]"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    local rows = {}
    for i, opt in ipairs(current_options) do rows[i] = { keys = opt.key, label = opt.label, value = opt.val } end

    local hints = { { "Enter", current_place and "set" or "seek" }, { "Esc", "cancel" } }
    local line  = edit.render(layers, theme.align(7) .. theme.f() .. theme.c("text_color"), current_title .. " > ", input, cursor)
    local err    = current_error and string.format("\\N%s%s%s%s", theme.f(true), theme.c("warning_color"), theme.escape(current_error), theme.reset()) or ""
    overlay.data = string.format("%s%s%s%s%s", line, theme.reset(), err, ui.rows(rows), ui.tooltip(hints))
    overlay:update()
end

local function cleanup()
    if not active then return end
    active         = false
    state.ui_owner = nil
    overlay:remove()
    edit.remove_layers(layers)
    edit.remove_bindings("goto")
    mp.remove_key_binding("goto-enter")
    mp.remove_key_binding("goto-kp-enter")
    mp.remove_key_binding("goto-esc")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("goto-char-" .. key) end
    for key, _ in pairs(edit.keypad) do mp.remove_key_binding("goto-char-" .. key) end
    for _, opt in ipairs(current_options) do mp.remove_key_binding("goto-opt-" .. opt.key) end
    if current_callback then
        local ok, err = pcall(current_callback)
        if not ok then mp.msg.error(err) end
    end
end

local function seek_to(seconds, relative, exact)
    if not seconds then return end
    local mode = relative and "relative" or "absolute"
    if exact then mode = mode .. "+exact" end
    mp.commandv("osd-bar", "seek", seconds, mode)
end

local unit_factors = { ms = 0.001, s = 1, m = 60, h = 3600, d = 86400 }

local function number(str)
    if str:match("^%d*%.?%d*$") and str:match("%d") then return tonumber(str) end
    return nil
end

local function parse_compound(str)
    local total = 0
    local pos   = 1
    while pos <= #str do
        local num, unit, next_pos = str:match("^([%d%.]+)(%a*)()", pos)
        if not num then return nil end
        local value  = number(num)
        local factor = unit == "" and 1 or unit_factors[unit]
        if not value or not factor then return nil end
        total = total + value * factor
        pos   = next_pos
    end
    return total
end

local function parse_duration(str)
    if str == "" then return nil end

    if str:find(":") then
        local parts = {}
        for part in (str .. ":"):gmatch("(.-):") do
            local value = part == "" and 0 or number(part)
            if not value then return nil end
            parts[#parts + 1] = value
        end
        if #parts > 3 then return nil end

        local h, m, s = 0, 0, 0
        if #parts == 1 then
            s = parts[1]
        elseif #parts == 2 then
            m, s = parts[1], parts[2]
        else
            h, m, s = parts[1], parts[2], parts[3]
        end
        return h * 3600 + m * 60 + s
    end

    return parse_compound(str)
end

local function parse_input(str)
    local base  = nil
    local first = str:sub(1, 1)
    if first == "[" then
        base = common.resolve_mark_in(state.mark_in, state.opts.lossless_cut, mp.get_property("path"))
        str  = str:sub(2)
    elseif first == "]" then
        base = state.mark_out
        str  = str:sub(2)
    end

    local relative = false
    local sign     = 1
    if str:sub(1, 1) == '+' then
        relative = true
        str      = str:sub(2)
    elseif str:sub(1, 1) == '-' then
        relative = true
        sign     = -1
        str      = str:sub(2)
    end

    if str == "" then
        if base then return { kind = "abs", seconds = base } end
        return nil
    end

    if str:sub(-1) == '%' then
        local num = number(str:sub(1, -2))
        if not num then return nil end
        if base or relative then
            local duration = mp.get_property_number("duration")
            if not (duration and duration > 0) then return nil, "goto_no_duration" end
            if base then
                return { kind = "abs", seconds = base + sign * duration * num / 100 }
            end
            return { kind = "delta", seconds = sign * duration * num / 100 }
        end
        return { kind = "percent", value = num }
    end

    if str:sub(-1) == 'f' then
        local num = number(str:sub(1, -2))
        if not num then return nil end
        local fps = mp.get_property_number("container-fps") or mp.get_property_number("container-fps-approx")
        if not (fps and fps > 0) then return nil, "goto_no_fps" end
        if base then
            return { kind = "abs", seconds = base + sign * num / fps, exact = true }
        end
        return { kind = relative and "delta" or "abs", seconds = sign * num / fps, exact = true }
    end

    local seconds = parse_duration(str)
    if not seconds then return nil end
    if base then
        return { kind = "abs", seconds = base + sign * seconds }
    end
    return { kind = relative and "delta" or "abs", seconds = sign * seconds }
end

local function apply_input(t)
    if current_place then
        local seconds  = t.seconds
        local duration = mp.get_property_number("duration")
        if t.kind == "delta" then
            seconds = mp.get_property_number("time-pos", 0) + t.seconds
        elseif t.kind == "percent" then
            if not (duration and duration > 0) then return "goto_no_duration" end
            seconds = duration * t.value / 100
        end
        if seconds < 0 then seconds = 0 end
        if duration and duration > 0 and seconds > duration then seconds = duration end
        if current_place == 0 then
            state.mark_in = seconds
        else
            state.mark_out = seconds
        end
        local label = lang.t(current_place == 0 and "menu_mark_in" or "menu_mark_out")
        notify.show(lang.t("value_set", { label = label, value = common.format_time(seconds) }))
        M.check_marks()
        return
    end

    if t.kind == "percent" then
        mp.commandv("seek", t.value, "absolute-percent")
    else
        seek_to(t.seconds, t.kind == "delta", t.exact)
    end
end

local function parse_and_apply()
    local str = input:lower():gsub("%s+", "")
    if str ~= "" then
        local t, err = parse_input(str)
        if t then err = apply_input(t) end
        if err or not t then
            current_error = lang.t(err or "goto_invalid")
            return render()
        end
    end
    cleanup()
end

local function apply_edit(fn)
    input, cursor = fn(input, cursor)
    current_error = nil
    render()
end

local function add_char(c)
    apply_edit(function(t, p) return edit.insert(t, p, c) end)
end

function M.check_marks()
    if state.mark_in < state.mark_out then return end
    notify.show(lang.t("render_invalid_marks", { mark_in = common.format_time(state.mark_in), mark_out = common.format_time(state.mark_out) }), true, "warn")
end

local function run_option(opt)
    cleanup()
    opt.action()
end

function M.show(on_complete, options, place)
    if active then return end
    if not place and not mp.get_property_bool("seekable") then
        notify.show(lang.t("goto_not_seekable"), true, "warn")
        if on_complete then on_complete() end
        return
    end
    active           = true
    state.ui_owner   = "goto"
    input            = ""
    cursor           = 0
    current_error    = nil
    current_callback = on_complete
    current_place    = place
    current_title    = lang.t(place == 0 and "menu_set_mark_in" or place == 1 and "menu_set_mark_out" or "menu_goto")
    current_options  = {}
    for _, opt in ipairs(options or {}) do
        current_options[#current_options + 1] = { key = opt.key, label = opt.label, val = opt.get_val(), action = opt.action }
    end

    ui.clear_osd()
    render()

    edit.add_bindings("goto", apply_edit, function(text)
        return (text:lower():gsub(".", function(c) return key_mappings[c] and c or "" end))
    end)
    mp.add_forced_key_binding("ENTER", "goto-enter", parse_and_apply)
    mp.add_forced_key_binding("KP_ENTER", "goto-kp-enter", parse_and_apply)
    mp.add_forced_key_binding("ESC", "goto-esc", cleanup)

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "goto-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
    for key, char in pairs(edit.keypad) do
        if key_mappings[char] then mp.add_forced_key_binding(key, "goto-char-" .. key, function() add_char(char) end, {repeatable=true}) end
    end
    for _, opt in ipairs(current_options) do
        mp.add_forced_key_binding(opt.key, "goto-opt-" .. opt.key, function() run_option(opt) end)
    end
end

return M
