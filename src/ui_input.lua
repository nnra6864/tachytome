local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'
local lang  = require 'src.lang'
local edit  = require 'src.text_edit'

local M = {}

local overlay                 = mp.create_osd_overlay("ass-events")
local layers                  = edit.create_layers()
local active                  = false
local buffer                  = ""
local cursor                  = 0
local current_prompt          = ""
local current_sub_prompt      = ""
local current_callback        = nil
local current_cancel_callback = nil
local custom_tooltip          = nil
local current_preview         = nil

local history      = {}
local history_idx  = 1
local draft_buffer = ""

local key_mappings   = { ["SHARP"] = "#" }
local standard_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:;/\\|()[]~@$%^&*+=<>?'\"!`"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    key_mappings[c] = c
end

local function render()
    local tooltip = ""
    if custom_tooltip == false then
        tooltip = ""
    elseif type(custom_tooltip) == "string" then
        tooltip = "\\N" .. theme.f(true) .. custom_tooltip
    else
        tooltip = "\\N" .. theme.f(true) .. lang.t("tooltip_confirm")
    end

    local sub_str = (current_sub_prompt ~= "") and string.format("\\N%s%s%s", theme.f(true), theme.a("88"), lang.t("input_current", { value = theme.escape(current_sub_prompt) })) or ""

    local preview     = current_preview and current_preview(buffer) or ""
    local preview_str = (preview ~= "") and string.format("\\N%s%s%s%s", theme.f(true), theme.c("value_color"), lang.t("input_expanded", { value = theme.escape(preview) }), theme.reset()) or ""

    local line = edit.render(layers, theme.align(7) .. theme.f() .. theme.c("text_color"), current_prompt, buffer, cursor)
    overlay.data = string.format("%s%s%s%s%s", line, theme.reset(), preview_str, tooltip, sub_str)
    overlay:update()
end

local function remove_overlays()
    overlay:remove()
    edit.remove_layers(layers)
end

local function cleanup_bindings()
    edit.remove_bindings("osd-input")
    mp.remove_key_binding("osd-input-enter")
    mp.remove_key_binding("osd-input-esc")
    mp.remove_key_binding("osd-input-up")
    mp.remove_key_binding("osd-input-down")
    mp.remove_key_binding("osd-input-cj")
    mp.remove_key_binding("osd-input-ck")
    mp.remove_key_binding("osd-input-space")
    for key, _ in pairs(key_mappings) do mp.remove_key_binding("osd-input-char-" .. key) end
end

local function cancel()
    if not active then return end
    active         = false
    state.ui_owner = nil
    remove_overlays()
    cleanup_bindings()
    if current_cancel_callback then pcall(current_cancel_callback) end
end

local function confirm()
    if not active then return end
    local res      = buffer
    active         = false
    state.ui_owner = nil
    remove_overlays()
    cleanup_bindings()
    if current_callback then pcall(current_callback, res) end
end

local function apply_edit(fn)
    local text, pos = fn(buffer, cursor)
    if text ~= buffer and history_idx <= #history then history_idx = #history + 1 end
    buffer = text
    cursor = pos
    render()
end

local function add_char(c)
    apply_edit(function(t, p) return edit.insert(t, p, c) end)
end

local function history_up()
    if #history == 0 then return end
    if history_idx == #history + 1 then draft_buffer = buffer end
    if history_idx > 1 then
        history_idx = history_idx - 1
        buffer = history[history_idx]
        cursor = #buffer
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
        cursor = #buffer
        render()
    end
end

function M.get_user_input(prompt, callback, sub_prompt, tooltip_override, history_list, on_cancel, allow_space, preview)
    if active then return end
    active                  = true
    state.ui_owner          = "input"
    current_prompt          = prompt or ""
    current_sub_prompt      = sub_prompt or ""
    current_callback        = callback
    current_cancel_callback = on_cancel
    custom_tooltip          = tooltip_override
    current_preview         = preview
    buffer                  = ""
    cursor                  = 0

    history      = history_list or {}
    history_idx  = #history + 1
    draft_buffer = ""

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    render()

    edit.add_bindings("osd-input", apply_edit)
    mp.add_forced_key_binding("ENTER", "osd-input-enter", confirm)
    mp.add_forced_key_binding("ESC", "osd-input-esc", cancel)
    mp.add_forced_key_binding("UP", "osd-input-up", history_up, {repeatable=true})
    mp.add_forced_key_binding("DOWN", "osd-input-down", history_down, {repeatable=true})
    mp.add_forced_key_binding("ctrl+j", "osd-input-cj", history_down, {repeatable=true})
    mp.add_forced_key_binding("ctrl+k", "osd-input-ck", history_up, {repeatable=true})
    if allow_space then
        mp.add_forced_key_binding("SPACE", "osd-input-space", function() add_char(" ") end, {repeatable=true})
    end

    for key, char in pairs(key_mappings) do
        mp.add_forced_key_binding(key, "osd-input-char-" .. key, function() add_char(char) end, {repeatable=true})
    end
end

return M
