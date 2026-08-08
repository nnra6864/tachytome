local state = require 'src.state'

local M = {}

local function hex(h)
    if type(h) ~= "string" then return "&HFFFFFF&" end
    h = h:gsub("#", "")
    if #h ~= 6 then return "&HFFFFFF&" end
    return string.format("&H%s%s%s&", h:sub(5,6), h:sub(3,4), h:sub(1,2))
end

function M.c(key)
    local color = state.opts[key] or state.opts.text_color
    return string.format("{\\c%s}", hex(color))
end

function M.reset()
    return M.c("text_color")
end

function M.f(small)
    local size = small and state.opts.small_font_size or state.opts.font_size
    return string.format("{\\fnmonospace}{\\fs%d}", size)
end

function M.a(alpha_hex)
    return string.format("{\\alpha&H%s&}", alpha_hex)
end

function M.b(bold)
    return string.format("{\\b%d}", bold and 1 or 0)
end

function M.align(pos)
    return string.format("{\\an%d}", pos)
end

return M
