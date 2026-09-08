local mp     = require 'mp'
local notify = require 'src.notify'
local state  = require 'src.state'
local theme  = require 'src.theme'

local M = {}

local overlay          = mp.create_osd_overlay("ass-events")
local active           = false
local input            = ""
local current_callback = nil

local key_mappings   = { ["SPACE"] = " " }
local standard_chars = "0123456789:.dhmsf%+-"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    overlay.data = string.format("%s%s%sGo to > %s%s%s_%s%s\\N%s(Enter to seek, Esc to cancel)",
        theme.align(7), theme.f(), theme.c("text_color"),
        theme.c("value_color"), input, theme.a("FF"), theme.a("00"), theme.reset(), theme.f(true)
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
    if current_callback then pcall(current_callback) end
end

local function seek_to(seconds, relative, exact)
    if not seconds then return end
    local mode = relative and "relative" or "absolute"
    if exact then mode = mode .. "+exact" end
    mp.commandv("osd-bar", "seek", seconds, mode)
end

local function parse_duration(str)
    if str == "" then return nil end

    if str:sub(-2) == 'ms' then return tonumber(str:sub(1, -3)) / 1000 end
    if str:sub(-1) == 's'  then return tonumber(str:sub(1, -2)) end
    if str:sub(-1) == 'm'  then return tonumber(str:sub(1, -2)) * 60 end
    if str:sub(-1) == 'h'  then return tonumber(str:sub(1, -2)) * 3600 end
    if str:sub(-1) == 'd'  then return tonumber(str:sub(1, -2)) * 86400 end
    if str:sub(-1) == 'f'  then return nil end

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

    return tonumber(str)
end

local function parse_and_seek()
    local str = input:lower():gsub("%s+", "")
    if str == "" then cleanup(); return end

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
    if str == "" then cleanup(); return end

    if str:sub(-1) == '%' then
        local num = tonumber(str:sub(1, -2))
        if num then
            if relative then
                local duration = mp.get_property_number("duration")
                if duration and duration > 0 then
                    seek_to(sign * duration * num / 100, true)
                else
                    notify.show("Cannot jump by percent: duration unknown.", true, "warn")
                end
            else
                mp.commandv("seek", num, "absolute-percent")
            end
        end
    elseif str:sub(-1) == 'f' then
        local num = tonumber(str:sub(1, -2))
        if num then
            local fps = mp.get_property_number("container-fps") or mp.get_property_number("container-fps-approx")
            if fps and fps > 0 then
                seek_to(sign * num / fps, relative, true)
            else
                notify.show("Cannot jump frames: FPS unknown.", true, "warn")
            end
        end
    else
        local seconds = parse_duration(str)
        if seconds then seek_to(sign * seconds, relative) end
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

function M.show(on_complete)
    if active or not mp.get_property("seekable") then return end
    active           = true
    state.ui_owner   = "goto"
    input            = ""
    current_callback = on_complete

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    render()

    mp.add_forced_key_binding("BS", "goto-bs", backspace, {repeatable=true})
    mp.add_forced_key_binding("ENTER", "goto-enter", parse_and_seek)
    mp.add_forced_key_binding("ESC", "goto-esc", cleanup)

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "goto-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
end

return M
