local mp = require 'mp'
local M  = {}

local overlay            = mp.create_osd_overlay("ass-events")
local active             = false
local buffer             = ""
local current_prompt     = ""
local current_sub_prompt = ""
local current_callback   = nil
local custom_tooltip     = nil

local history            = {}
local history_idx        = 1
local draft_buffer       = ""

local key_mappings   = { ["SPACE"] = " " }
local standard_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:;/\\|()[]~@#$%^&*+=<>?'\""
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    local tooltip = ""
    if custom_tooltip == false then
        tooltip = ""
    elseif type(custom_tooltip) == "string" then
        tooltip = "\\N{\\fs16}" .. custom_tooltip
    else
        tooltip = "\\N{\\fs16}(Enter to confirm, Esc to cancel)"
    end

    local sub_str = (current_sub_prompt ~= "") and string.format("\\N{\\fs14}{\\alpha&H88&}Current: %s", current_sub_prompt) or ""

    overlay.data = string.format(
        "{\\an7}{\\fnmonospace}%s%s{\\alpha&HFF&}_{\\alpha&H00&}%s%s",
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
    mp.remove_key_binding("osd-input-up")
    mp.remove_key_binding("osd-input-down")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("osd-input-char-" .. key) end
end

local function confirm()
    local res = buffer
    close()
    if current_callback then
        pcall(current_callback, res)
    end
end

local function add_char(c)
    buffer = buffer .. c
    if history_idx <= #history then history_idx = #history + 1 end
    render()
end

local function backspace()
    if #buffer > 0 then
        buffer = buffer:sub(1, -2)
        if history_idx <= #history then history_idx = #history + 1 end
        render()
    end
end

local function history_up()
    if #history == 0 then return end
    if history_idx == #history + 1 then draft_buffer = buffer end
    if history_idx > 1 then
        history_idx = history_idx - 1
        buffer = history[history_idx]
        render()
    end
end

local function history_down()
    if #history == 0 then return end
    if history_idx <= #history then
        history_idx = history_idx + 1
        if history_idx > #history then
            buffer = draft_buffer
        else
            buffer = history[history_idx]
        end
        render()
    end
end

function M.get_user_input(prompt, callback, sub_prompt, tooltip_override, history_list)
    if active then return end
    active             = true
    current_prompt     = prompt or ""
    current_sub_prompt = sub_prompt or ""
    current_callback   = callback
    custom_tooltip     = tooltip_override
    buffer             = ""

    history      = history_list or {}
    history_idx  = #history + 1
    draft_buffer = ""

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    render()

    mp.add_forced_key_binding("BS", "osd-input-bs", backspace, {repeatable=true})
    mp.add_forced_key_binding("ENTER", "osd-input-enter", confirm)
    mp.add_forced_key_binding("ESC", "osd-input-esc", close)
    mp.add_forced_key_binding("UP", "osd-input-up", history_up, {repeatable=true})
    mp.add_forced_key_binding("DOWN", "osd-input-down", history_down, {repeatable=true})

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "osd-input-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
end

return M
