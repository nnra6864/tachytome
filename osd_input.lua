local mp = require 'mp'
local M = {}

local overlay = mp.create_osd_overlay("ass-events")
local active = false
local buffer = ""
local current_prompt = ""
local current_sub_prompt = ""
local current_callback = nil
local hide_help = false

local key_mappings = { ["SPACE"] = " " }
local standard_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:;/\\|()[]~@#$%^&*+=<>?'\""
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    local tooltip = hide_help and "" or "\\N{\\fs16}(Enter to confirm, Esc to cancel)"
    local sub_str = (current_sub_prompt ~= "") and string.format("\\N{\\fs14}{\\alpha&H88&}Current: %s", current_sub_prompt) or ""
    
    overlay.data = string.format(
        "{\\an7}%s%s{\\alpha&HFF&}_{\\alpha&H00&}%s%s",
        current_prompt, buffer, tooltip, sub_str
    )
    overlay:update()
end

local function close()
    if not active then return end
    active = false
    overlay:remove()
    mp.remove_key_binding("osd-input-bs")
    mp.remove_key_binding("osd-input-enter")
    mp.remove_key_binding("osd-input-esc")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("osd-input-char-" .. key) end
end

local function confirm()
    local res = buffer
    close()
    if current_callback then current_callback(res) end
end

local function add_char(c)
    buffer = buffer .. c
    render()
end

local function backspace()
    if #buffer > 0 then
        buffer = buffer:sub(1, -2)
        render()
    end
end

function M.get_user_input(prompt, callback, sub_prompt, hide_tooltip)
    if active then return end
    active = true
    current_prompt = prompt or ""
    current_sub_prompt = sub_prompt or ""
    current_callback = callback
    hide_help = hide_tooltip or false
    buffer = ""
    
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    render()

    mp.add_forced_key_binding("BS", "osd-input-bs", backspace, {repeatable=true})
    mp.add_forced_key_binding("ENTER", "osd-input-enter", confirm)
    mp.add_forced_key_binding("ESC", "osd-input-esc", close)

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "osd-input-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
end

return M
