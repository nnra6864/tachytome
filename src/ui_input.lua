local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'
local lang  = require 'src.lang'
local edit  = require 'src.text_edit'
local ui    = require 'src.ui'

local M = {}

local overlay                 = mp.create_osd_overlay("ass-events")
local layers                  = edit.create_layers()
local active                  = false
local buffer                  = ""
local cursor                  = 0
local current_title           = ""
local current_value           = ""
local current_callback        = nil
local current_cancel_callback = nil
local current_preview         = nil
local current_hint            = nil
local current_multiline       = false

local history      = {}
local history_idx  = 1
local draft_buffer = ""

local function render()
    local hints = { { "Enter", "confirm" }, { "Esc", "cancel" } }
    if #history > 0 then table.insert(hints, 1, { "Up/Down", "history" }) end
    if current_multiline then table.insert(hints, 1, { "Shift+Enter", "new_line" }) end

    local preview     = current_preview and current_preview(buffer) or ""
    local preview_str = preview ~= "" and string.format("\\N%s%s-> %s%s", theme.f(true), theme.c("value_color"), theme.escape(preview), theme.reset()) or ""
    local current_str = current_value ~= "" and ui.dim(lang.t("value_current", { value = current_value })):gsub("\n", "\\N") or ""
    local hint_str    = ui.tip(current_hint)

    local line = edit.render(layers, theme.align(7) .. theme.f() .. theme.c("text_color"), current_title .. " > ", buffer, cursor)
    overlay.data = string.format("%s%s%s%s%s%s", line, theme.reset(), preview_str, current_str, hint_str, ui.tooltip(hints))
    overlay:update()
end

local function remove_overlays()
    overlay:remove()
    edit.remove_layers(layers)
end

local function cleanup_bindings()
    edit.remove_bindings("osd-input")
    mp.remove_key_binding("osd-input-enter")
    mp.remove_key_binding("osd-input-kp-enter")
    mp.remove_key_binding("osd-input-newline")
    mp.remove_key_binding("osd-input-esc")
    mp.remove_key_binding("osd-input-up")
    mp.remove_key_binding("osd-input-down")
    mp.remove_key_binding("osd-input-cj")
    mp.remove_key_binding("osd-input-ck")
    edit.remove_char_bindings("osd-input")
end

local function cancel()
    if not active then return end
    active         = false
    state.ui_owner = nil
    remove_overlays()
    cleanup_bindings()
    if current_cancel_callback then
        local ok, err = pcall(current_cancel_callback)
        if not ok then mp.msg.error(err) end
    end
end

local function confirm()
    if not active then return end
    local res      = buffer
    active         = false
    state.ui_owner = nil
    remove_overlays()
    cleanup_bindings()
    if current_callback then
        local ok, err = pcall(current_callback, res)
        if not ok then mp.msg.error(err) end
    end
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

function M.show(opts)
    if active then return end
    active                  = true
    state.ui_owner          = "input"
    current_title           = opts.title or ""
    current_value           = opts.current and tostring(opts.current) or ""
    current_callback        = opts.on_submit
    current_cancel_callback = opts.on_cancel
    current_preview         = opts.preview
    current_hint            = opts.hint
    current_multiline       = opts.multiline or false
    buffer                  = ""
    cursor                  = 0

    history      = opts.history or {}
    history_idx  = #history + 1
    draft_buffer = ""

    ui.clear_osd()
    render()

    edit.add_bindings("osd-input", apply_edit, function(text)
        if not current_multiline then text = text:gsub("\n", " ") end
        if not opts.allow_space then text = text:gsub(" ", "") end
        return text
    end)
    mp.add_forced_key_binding("ENTER", "osd-input-enter", confirm)
    mp.add_forced_key_binding("KP_ENTER", "osd-input-kp-enter", confirm)
    if current_multiline then mp.add_forced_key_binding("shift+ENTER", "osd-input-newline", function() add_char("\n") end, {repeatable=true}) end
    mp.add_forced_key_binding("ESC", "osd-input-esc", cancel)
    mp.add_forced_key_binding("UP", "osd-input-up", history_up, {repeatable=true})
    mp.add_forced_key_binding("DOWN", "osd-input-down", history_down, {repeatable=true})
    mp.add_forced_key_binding("ctrl+j", "osd-input-cj", history_down, {repeatable=true})
    mp.add_forced_key_binding("ctrl+k", "osd-input-ck", history_up, {repeatable=true})
    edit.add_char_bindings("osd-input", add_char, opts.allow_space)
end

function M.cancel()
    cancel()
end

function M.refresh()
    if active then render() end
end

return M
