local mp    = require 'mp'
local theme = require 'src.theme'

local M = {}

local overlay          = mp.create_osd_overlay("ass-events")
local active           = false
local input            = ""
local current_callback = nil

local key_mappings   = { ["SPACE"] = " " }
local standard_chars = "0123456789:.dhmsf%"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    overlay.data = string.format("%s%s%sGo to: %s%s%s_%s%s\\N%s(Enter to seek, Esc to cancel)",
        theme.align(7), theme.f(), theme.c("text_color"),
        theme.c("value_color"), input, theme.a("FF"), theme.a("00"), theme.reset(), theme.f(true)
    )
    overlay:update()
end

local function cleanup()
    if not active then return end
    active = false
    overlay:remove()
    mp.remove_key_binding("goto-bs")
    mp.remove_key_binding("goto-enter")
    mp.remove_key_binding("goto-esc")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("goto-char-" .. key) end
    if current_callback then pcall(current_callback) end
end

local function parse_and_seek()
    local str = input:lower():gsub("%s+", "")
    if str == "" then cleanup(); return end

    if str:sub(-1) == '%' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("seek", num, "absolute-percent") end
    elseif str:sub(-1) == 'f' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("frame-step"); for _ = 2, num do mp.commandv("frame-step") end end
    elseif str:sub(-2) == 'ms' then
        local num = tonumber(str:sub(1, -3))
        if num then mp.commandv("osd-bar", "seek", num / 1000, "absolute") end
    elseif str:sub(-1) == 's' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("osd-bar", "seek", num, "absolute") end
    elseif str:sub(-1) == 'm' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("osd-bar", "seek", num * 60, "absolute") end
    elseif str:sub(-1) == 'h' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("osd-bar", "seek", num * 3600, "absolute") end
    elseif str:sub(-1) == 'd' then
        local num = tonumber(str:sub(1, -2))
        if num then mp.commandv("osd-bar", "seek", num * 86400, "absolute") end
    else
        if str:find(":") then
            local h, m, s = 0, 0, 0
            local parts = {}
            for part in str:gmatch("([%d%.]+)") do
                table.insert(parts, tonumber(part) or 0)
            end

            if #parts == 1 then
                s = parts[1]
            elseif #parts == 2 then
                m, s = parts[1], parts[2]
            elseif #parts >= 3 then
                h, m, s = parts[1], parts[2], parts[3]
            end
            local seconds = h * 3600 + m * 60 + s
            mp.commandv("osd-bar", "seek", seconds, "absolute")
        else
            -- Direct evaluation for pure numbers (e.g., "1.5" or "15")
            local total = tonumber(str)
            if total then mp.commandv("osd-bar", "seek", total, "absolute") end
        end
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
