local mp    = require 'mp'
local state = require 'src.state'
local theme = require 'src.theme'

local M = {}

local separators = "[%s%-_/\\%.,:;%(%)%[%]{}<>]"

local function is_sep(text, i)
    return text:sub(i, i):find(separators) ~= nil
end

local function is_cont(text, i)
    local b = text:byte(i)
    return b ~= nil and b >= 128 and b < 192
end

local function char_end(text, pos)
    local i = pos + 1
    while is_cont(text, i + 1) do i = i + 1 end
    return i
end

function M.left(text, pos)
    if pos <= 0 then return 0 end
    local i = pos
    while i > 1 and is_cont(text, i) do i = i - 1 end
    return i - 1
end

function M.right(text, pos)
    if pos >= #text then return #text end
    return char_end(text, pos)
end

function M.word_left(text, pos)
    local i = pos
    while i > 0 and is_sep(text, i) do i = i - 1 end
    while i > 0 and not is_sep(text, i) do i = i - 1 end
    return i
end

function M.word_right(text, pos)
    local i = pos
    while i < #text and is_sep(text, i + 1) do i = i + 1 end
    while i < #text and not is_sep(text, i + 1) do i = i + 1 end
    return i
end

function M.insert(text, pos, s)
    return text:sub(1, pos) .. s .. text:sub(pos + 1), pos + #s
end

function M.backspace(text, pos)
    local start = M.left(text, pos)
    return text:sub(1, start) .. text:sub(pos + 1), start
end

function M.delete_word(text, pos)
    local start = M.word_left(text, pos)
    return text:sub(1, start) .. text:sub(pos + 1), start
end

function M.delete(text, pos)
    if pos >= #text then return text, pos end
    return text:sub(1, pos) .. text:sub(M.right(text, pos) + 1), pos
end

function M.delete_word_right(text, pos)
    return text:sub(1, pos) .. text:sub(M.word_right(text, pos) + 1), pos
end

function M.delete_to_start(text, pos)
    return text:sub(pos + 1), 0
end

local function home(t) return t, 0 end
local function to_end(t) return t, #t end
local function left(t, p) return t, M.left(t, p) end
local function right(t, p) return t, M.right(t, p) end

local bindings = {
    { key = "LEFT",       name = "left",       fn = left },
    { key = "RIGHT",      name = "right",      fn = right },
    { key = "KP_LEFT",    name = "kp-left",    fn = left },
    { key = "KP_RIGHT",   name = "kp-right",   fn = right },
    { key = "HOME",       name = "home",       fn = home },
    { key = "END",        name = "end",        fn = to_end },
    { key = "KP_HOME",    name = "kp-home",    fn = home },
    { key = "KP_END",     name = "kp-end",     fn = to_end },
    { key = "ctrl+a",     name = "ctrl-a",     fn = home },
    { key = "ctrl+e",     name = "ctrl-e",     fn = to_end },
    { key = "ctrl+LEFT",  name = "word-left",  fn = function(t, p) return t, M.word_left(t, p) end },
    { key = "ctrl+RIGHT", name = "word-right", fn = function(t, p) return t, M.word_right(t, p) end },
    { key = "BS",         name = "bs",         fn = M.backspace },
    { key = "ctrl+BS",    name = "word-bs",    fn = M.delete_word },
    { key = "ctrl+w",     name = "ctrl-w",     fn = M.delete_word },
    { key = "ctrl+u",     name = "ctrl-u",     fn = M.delete_to_start },
    { key = "DEL",        name = "del",        fn = M.delete },
    { key = "KP_DEL",     name = "kp-del",     fn = M.delete },
    { key = "ctrl+DEL",   name = "word-del",   fn = M.delete_word_right }
}

local paste_keys = { "ctrl+v", "ctrl+V", "shift+INS" }

M.keypad = { KP0 = "0", KP1 = "1", KP2 = "2", KP3 = "3", KP4 = "4", KP5 = "5", KP6 = "6", KP7 = "7", KP8 = "8", KP9 = "9", KP_DEC = ".", KP_ADD = "+", KP_SUBTRACT = "-", KP_MULTIPLY = "*", KP_DIVIDE = "/" }

local function clipboard(filter)
    local text = (mp.get_property("clipboard/text") or ""):gsub("\r\n?", "\n"):gsub("^\n+", ""):gsub("\n+$", "")
    if filter then text = filter(text) end
    return text
end

function M.add_bindings(prefix, edit, filter)
    for _, b in ipairs(bindings) do
        mp.add_forced_key_binding(b.key, prefix .. "-" .. b.name, function() edit(b.fn) end, {repeatable=true})
    end
    for _, key in ipairs(paste_keys) do
        mp.add_forced_key_binding(key, prefix .. "-paste-" .. key, function()
            local text = clipboard(filter)
            if text ~= "" then edit(function(t, p) return M.insert(t, p, text) end) end
        end)
    end
end

function M.remove_bindings(prefix)
    for _, b in ipairs(bindings) do mp.remove_key_binding(prefix .. "-" .. b.name) end
    for _, key in ipairs(paste_keys) do mp.remove_key_binding(prefix .. "-paste-" .. key) end
end

function M.add_char_bindings(prefix, insert, allow_space)
    mp.add_forced_key_binding("any_unicode", prefix .. "-chars", function(e)
        if e.event == "up" or not e.key_text or e.key_text:find("%c") then return end
        if e.key_text == " " and not allow_space then return end
        insert(e.key_text)
    end, {repeatable=true, complex=true})
    for key, char in pairs(M.keypad) do
        mp.add_forced_key_binding(key, prefix .. "-" .. key, function() insert(char) end, {repeatable=true})
    end
end

function M.remove_char_bindings(prefix)
    mp.remove_key_binding(prefix .. "-chars")
    for key in pairs(M.keypad) do mp.remove_key_binding(prefix .. "-" .. key) end
end

local function cursor_key()
    return state.opts.cursor_color ~= "" and "cursor_color" or "value_color"
end

local function text_color()
    if state.opts.cursor_text_color ~= "" then return theme.c("cursor_text_color") end
    return theme.invert(cursor_key())
end

local no_glow       = "{\\bord0}{\\shad0}{\\blur0}{\\be0}"
local cursor_glyphs = { bar = "▏", underline = "▁", block = "█" }

M.cursor_styles = { "bar", "underline", "block" }

local function layer(head, prompt, before, glyph, glow, color, after)
    return string.format("%s%s%s%s%s%s%s%s%s%s",
        head, theme.a("FF"), prompt, before, theme.a("00"), glow ~= "" and glow or no_glow, color, theme.escape(glyph), theme.a("FF"), after
    )
end

function M.create_layers()
    local layers = { cursor = mp.create_osd_overlay("ass-events"), char = mp.create_osd_overlay("ass-events") }
    layers.cursor.z = 1
    layers.char.z   = 2
    return layers
end

local function set_layer(overlay, data)
    if data then
        overlay.data = data
        overlay:update()
    else
        overlay:remove()
    end
end

function M.remove_layers(layers)
    layers.cursor:remove()
    layers.char:remove()
end

local function show(text)
    return (theme.escape(text):gsub("\n", "\\N"))
end

local function show_lines(text)
    if not text:find("\n") then return theme.escape(text) end
    local out = {}
    for part in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = part == "" and "\\h" or theme.escape(part) end
    return table.concat(out, "\\N")
end

function M.render(layers, head, prompt, text, pos)
    local before = show(text:sub(1, pos))
    local under  = pos < #text and text:sub(pos + 1, char_end(text, pos)) or ""
    local after  = show(text:sub(pos + #under + 1))
    local block  = state.opts.cursor_style == "block"
    local cursor = layer(head, prompt, before, cursor_glyphs[state.opts.cursor_style] or cursor_glyphs.bar, theme.glow("cursor_"), theme.c(cursor_key()), after)
    local char   = (block and under ~= "" and not under:find("^%s$")) and layer(head, prompt, before, under, no_glow, text_color(), after) or nil
    set_layer(layers.cursor, cursor)
    set_layer(layers.char, char)
    return string.format("%s%s%s%s", head, prompt, theme.c("value_color"), show_lines(text))
end

return M
