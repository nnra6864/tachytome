local state = require 'src.state'

local M = {}

local function channels(h)
    if type(h) ~= "string" then return nil end
    h = h:gsub("#", "")
    if #h ~= 6 then return nil end
    local r = tonumber(h:sub(1, 2), 16)
    local g = tonumber(h:sub(3, 4), 16)
    local b = tonumber(h:sub(5, 6), 16)
    if not r or not g or not b then return nil end
    return r, g, b
end

local function hex(h)
    local r, g, b = channels(h)
    if not r then return "&HFFFFFF&" end
    return string.format("&H%02X%02X%02X&", b, g, r)
end

function M.c(key)
    local color = state.opts[key] or state.opts.text_color
    return string.format("{\\c%s}", hex(color))
end

function M.mix(ha, hb, t)
    local ar, ag, ab = channels(ha)
    local br, bg, bb = channels(hb)
    if not ar or not br then return "{\\c&HFFFFFF&}" end
    local r = math.max(0, math.min(255, math.floor(ar + (br - ar) * t + 0.5)))
    local g = math.max(0, math.min(255, math.floor(ag + (bg - ag) * t + 0.5)))
    local b = math.max(0, math.min(255, math.floor(ab + (bb - ab) * t + 0.5)))
    return string.format("{\\c&H%02X%02X%02X&}", b, g, r)
end

function M.reset()
    return M.c("text_color")
end

function M.escape(text)
    return (tostring(text):gsub("\\", "\\\226\129\160"):gsub("{", "\\{"))
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
