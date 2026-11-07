local mp     = require 'mp'
local common = require 'src.common'
local notify = require 'src.notify'
local state  = require 'src.state'
local theme  = require 'src.theme'

local M = {}

local overlay          = mp.create_osd_overlay("ass-events")
local active           = false
local input            = ""
local current_callback = nil
local current_options  = {}
local current_place    = nil
local current_title    = "Go to"
local current_verb     = "seek"

local key_mappings   = {}
local standard_chars = "0123456789:.dhmsf%+-[]"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    local max_label_len = 0
    for _, opt in ipairs(current_options) do
        if #opt.label > max_label_len then max_label_len = #opt.label end
    end

    local options_str = ""
    for _, opt in ipairs(current_options) do
        local val_pad = string.rep("\\h", max_label_len - #opt.label + 1)
        options_str = options_str .. string.format("\\N%s -> %s%s> %s%s%s",
            opt.key, opt.label, val_pad, theme.c("value_color"), opt.val, theme.reset()
        )
    end

    overlay.data = string.format("%s%s%s%s > %s%s%s_%s%s%s\\N%s(Enter to %s, Esc to cancel)",
        theme.align(7), theme.f(), theme.c("text_color"),
        current_title, theme.c("value_color"), input, theme.a("FF"), theme.a("00"), theme.reset(), options_str, theme.f(true), current_verb
    )
    overlay:update()
end

local function cleanup()
    if not active then return end
    active         = false
    state.ui_owner = nil
    overlay:remove()
    mp.remove_key_binding("goto-bs")
    mp.remove_key_binding("goto-enter")
    mp.remove_key_binding("goto-esc")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("goto-char-" .. key) end
    for _, opt in ipairs(current_options) do mp.remove_key_binding("goto-opt-" .. opt.key) end
    if current_callback then pcall(current_callback) end
end

local function seek_to(seconds, relative, exact)
    if not seconds then return end
    local mode = relative and "relative" or "absolute"
    if exact then mode = mode .. "+exact" end
    mp.commandv("osd-bar", "seek", seconds, mode)
end

local unit_factors = { ms = 0.001, s = 1, m = 60, h = 3600, d = 86400 }

local function parse_compound(str)
    local total = 0
    local pos   = 1
    while pos <= #str do
        local num, unit, next_pos = str:match("^([%d%.]+)(%a*)()", pos)
        if not num then return nil end
        local value  = tonumber(num)
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
        for part in str:gmatch("([%d%.]+)") do
            table.insert(parts, tonumber(part) or 0)
        end
        if #parts == 0 then return nil end

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
    -- TODO: document the [ and ] mark prefixes in README Go To > Prefix
    local base  = nil
    local first = str:sub(1, 1)
    if first == "[" or first == "]" then
        local actions = require 'src.actions'
        base = first == "[" and actions.get_resolved_mark_in() or state.mark_out
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
        local num = tonumber(str:sub(1, -2))
        if not num then return nil end
        if base or relative then
            local duration = mp.get_property_number("duration")
            if not (duration and duration > 0) then
                notify.show("Cannot jump by percent: duration unknown.", true, "warn")
                return nil
            end
            if base then
                return { kind = "abs", seconds = base + sign * duration * num / 100 }
            end
            return { kind = "delta", seconds = sign * duration * num / 100 }
        end
        return { kind = "percent", value = num }
    end

    if str:sub(-1) == 'f' then
        local num = tonumber(str:sub(1, -2))
        if not num then return nil end
        local fps = mp.get_property_number("container-fps") or mp.get_property_number("container-fps-approx")
        if not (fps and fps > 0) then
            notify.show("Cannot jump frames: FPS unknown.", true, "warn")
            return nil
        end
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
            if not (duration and duration > 0) then
                notify.show("Cannot jump by percent: duration unknown.", true, "warn")
                return
            end
            seconds = duration * t.value / 100
        end
        if seconds < 0 then seconds = 0 end
        if duration and duration > 0 and seconds > duration then seconds = duration end
        if current_place == 0 then
            state.mark_in = seconds
            notify.show("In: " .. common.format_time(seconds))
        else
            state.mark_out = seconds
            notify.show("Out: " .. common.format_time(seconds))
        end
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
        local t = parse_input(str)
        if t then apply_input(t) end
    end
    cleanup()
end

local function add_char(c)
    input = input .. c
    render()
end

local function backspace()
    if #input > 0 then
        input = input:sub(1, -2)
        render()
    end
end

local function run_option(opt)
    cleanup()
    opt.action()
end

function M.show(on_complete, options, place)
    if active then return end
    if not place and not mp.get_property_bool("seekable") then
        notify.show("Cannot seek in this file.", true, "warn")
        if on_complete then on_complete() end
        return
    end
    active           = true
    state.ui_owner   = "goto"
    input            = ""
    current_callback = on_complete
    current_place    = place
    current_title    = place == 0 and "Set In" or place == 1 and "Set Out" or "Go to"
    current_verb     = place and "set" or "seek"
    current_options  = {}
    for _, opt in ipairs(options or {}) do
        current_options[#current_options + 1] = { key = opt.key, label = opt.label, val = opt.get_val(), action = opt.action }
    end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    render()

    mp.add_forced_key_binding("BS", "goto-bs", backspace, {repeatable=true})
    mp.add_forced_key_binding("ENTER", "goto-enter", parse_and_apply)
    mp.add_forced_key_binding("ESC", "goto-esc", cleanup)

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "goto-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
    for _, opt in ipairs(current_options) do
        mp.add_forced_key_binding(opt.key, "goto-opt-" .. opt.key, function() run_option(opt) end)
    end
end

return M
