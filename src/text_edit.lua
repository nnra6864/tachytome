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

local bindings = {
    { key = "LEFT",       name = "left",       fn = function(t, p) return t, M.left(t, p) end },
    { key = "RIGHT",      name = "right",      fn = function(t, p) return t, M.right(t, p) end },
    { key = "HOME",       name = "home",       fn = function(t) return t, 0 end },
    { key = "END",        name = "end",        fn = function(t) return t, #t end },
    { key = "ctrl+LEFT",  name = "word-left",  fn = function(t, p) return t, M.word_left(t, p) end },
    { key = "ctrl+RIGHT", name = "word-right", fn = function(t, p) return t, M.word_right(t, p) end },
    { key = "BS",         name = "bs",         fn = M.backspace },
    { key = "ctrl+BS",    name = "word-bs",    fn = M.delete_word }
}

function M.add_bindings(prefix, edit)
    for _, b in ipairs(bindings) do
        mp.add_forced_key_binding(b.key, prefix .. "-" .. b.name, function() edit(b.fn) end, {repeatable=true})
    end
end

function M.remove_bindings(prefix)
    for _, b in ipairs(bindings) do mp.remove_key_binding(prefix .. "-" .. b.name) end
end

local char_keys      = { ["SHARP"] = "#" }
local standard_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:;/\\|()[]~@$%^&*+=<>?'\"!`"
for i = 1, #standard_chars do
    local c = standard_chars:sub(i, i)
    char_keys[c] = c
end

function M.add_char_bindings(prefix, insert, allow_space)
    for key, char in pairs(char_keys) do
        mp.add_forced_key_binding(key, prefix .. "-char-" .. key, function() insert(char) end, {repeatable=true})
    end
    if allow_space then
        mp.add_forced_key_binding("SPACE", prefix .. "-space", function() insert(" ") end, {repeatable=true})
    end
end

function M.remove_char_bindings(prefix)
    for key in pairs(char_keys) do mp.remove_key_binding(prefix .. "-char-" .. key) end
    mp.remove_key_binding(prefix .. "-space")
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

function M.show(text)
    return (theme.escape(text):gsub("\n", "\\N"))
end

function M.render(layers, head, prompt, text, pos)
    local before = M.show(text:sub(1, pos))
    local under  = pos < #text and text:sub(pos + 1, char_end(text, pos)) or ""
    local after  = M.show(text:sub(pos + #under + 1))
    local block  = state.opts.cursor_style == "block"
    local cursor = layer(head, prompt, before, cursor_glyphs[state.opts.cursor_style] or cursor_glyphs.bar, theme.glow("cursor_"), theme.c(cursor_key()), after)
    local char   = (block and under ~= "" and not under:find("^%s$")) and layer(head, prompt, before, under, no_glow, text_color(), after) or nil
    set_layer(layers.cursor, cursor)
    set_layer(layers.char, char)
    return string.format("%s%s%s%s", head, prompt, theme.c("value_color"), M.show(text))
end

return M
