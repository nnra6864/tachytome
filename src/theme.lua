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

function M.glow()
    local size = tonumber(state.opts.glow_size) or 0
    if size <= 0 then return "" end

    local blur = tonumber(state.opts.glow_blur) or 0.5
    if blur < 0 then blur = 0 end
    if blur > 1 then blur = 1 end
    blur = blur * size

    local h = state.opts.glow_color
    if type(h) ~= "string" then return string.format("{\\bord%s}{\\blur%s}{\\3c&HFFFFFF&}", tostring(size), tostring(blur)) end
    h = h:gsub("#", "")

    if #h == 6 then
        return string.format("{\\bord%s}{\\blur%s}{\\3c&H%s%s%s&}", tostring(size), tostring(blur), h:sub(5,6), h:sub(3,4), h:sub(1,2))
    end
    if #h == 8 then
        local alpha = tonumber("0x" .. h:sub(7,8))
        if alpha then
            return string.format("{\\bord%s}{\\blur%s}{\\3c&H%s%s%s&}{\\3a&H%02X&}", tostring(size), tostring(blur), h:sub(5,6), h:sub(3,4), h:sub(1,2), 255 - alpha)
        end
        return string.format("{\\bord%s}{\\blur%s}{\\3c&H%s%s%s&}", tostring(size), tostring(blur), h:sub(5,6), h:sub(3,4), h:sub(1,2))
    end
    return string.format("{\\bord%s}{\\blur%s}{\\3c&HFFFFFF&}", tostring(size), tostring(blur))
end

function M.f(small)
    local size = small and state.opts.small_font_size or state.opts.font_size
    return string.format("{\\fnmonospace}{\\fs%d}%s", size, M.glow())
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
