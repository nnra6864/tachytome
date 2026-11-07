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

local function color(key)
    return theme.c(state.opts[key] ~= "" and key or "value_color")
end

local function glow(prefix)
    local tags = theme.glow(prefix)
    return tags ~= "" and tags or "{\\bord0}{\\shad0}{\\blur0}"
end

local function layer(prefix, before, glyph, glow_prefix, color_key, after)
    return string.format("%s%s%s%s%s%s%s%s%s",
        theme.a("FF"), prefix, before, theme.a("00"), glow(glow_prefix), color(color_key), theme.escape(glyph), theme.a("FF"), after
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

function M.render(layers, prefix, text, pos)
    local before = theme.escape(text:sub(1, pos))
    local under  = pos < #text and text:sub(pos + 1, char_end(text, pos)) or ""
    local after  = theme.escape(text:sub(pos + #under + 1))
    local cursor = layer(prefix, before, state.opts.cursor_char, "cursor_", "cursor_color", after)
    local char   = (under ~= "" and not under:find("^%s$")) and layer(prefix, before, under, "cursor_text_", "cursor_text_color", after) or nil
    set_layer(layers.cursor, cursor)
    set_layer(layers.char, char)
    return string.format("%s%s%s", prefix, theme.c("value_color"), theme.escape(text))
end

return M
