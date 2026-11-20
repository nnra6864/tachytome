local state = require 'src.state'
local lang  = require 'src.lang'

local M = {}

M.modes   = { "fit", "cover", "stretch", "crop" }
M.scalers = { "fast_bilinear", "bilinear", "bicubic", "bicublin", "neighbor", "area", "gauss", "sinc", "lanczos", "spline" }

local function set_of(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

local modes   = set_of(M.modes)
local scalers = set_of(M.scalers)

local function number(text)
    local n = tonumber(text)
    if n and n > 0 then return n end
    return nil
end

local function size(token)
    local w, h = token:match("^(%d+)x(%d+)$")
    if w then
        w = number(w)
        h = number(h)
        return w and h and { kind = "box", w = w, h = h }
    end
    local n = token:match("^(%d*%.?%d+)x$")
    if n then
        n = number(n)
        return n and { kind = "scale", n = n }
    end
    n = token:match("^(%d*%.?%d+)%%$")
    if n then
        n = number(n)
        return n and { kind = "scale", n = n / 100 }
    end
    n = token:match("^(%d+)w$")
    if n then
        n = number(n)
        return n and { kind = "width", n = n }
    end
    n = token:match("^(%d+)[hp]$")
    if n then
        n = number(n)
        return n and { kind = "height", n = n }
    end
    local a, b = token:match("^(%d*%.?%d+):(%d*%.?%d+)$")
    if a then
        a = number(a)
        b = number(b)
        return a and b and { kind = "aspect", n = a / b }
    end
    return nil
end

function M.parse(text, mode)
    local layers = {}
    for token in text:gmatch("%S+") do
        local word  = token:lower()
        local layer = size(word)
        local last  = layers[#layers]
        if layer then
            layer.token         = token
            layers[#layers + 1] = layer
        elseif last and modes[word] then
            last.mode  = word
            last.token = last.token .. " " .. token
        elseif last and scalers[word] then
            last.scaler = word
            last.token  = last.token .. " " .. token
        else
            return nil, token
        end
    end
    for _, layer in ipairs(layers) do layer.mode = layer.mode or mode end
    return layers
end

function M.snapshot()
    local o = state.opts
    if not modes[o.resolution_mode] then return nil, lang.t("resolution_unknown", { token = o.resolution_mode }) end
    if not scalers[o.scaler_down] then return nil, lang.t("resolution_unknown", { token = o.scaler_down }) end
    if not scalers[o.scaler_up] then return nil, lang.t("resolution_unknown", { token = o.scaler_up }) end
    local layers, bad = M.parse(o.resolution, o.resolution_mode)
    if not layers then return nil, lang.t("resolution_unknown", { token = bad }) end
    if #layers == 0 then return nil end
    return {
        layers      = layers,
        scaler_down = o.scaler_down,
        scaler_up   = o.scaler_up,
        pad_color   = o.pad_color
    }
end

local function even(x)
    return math.max(2, math.floor(x / 2 + 0.5) * 2)
end

local function floor_even(x)
    return math.max(2, math.floor(x / 2) * 2)
end

local function ceil_even(x)
    return math.max(2, math.ceil(x / 2) * 2)
end

local function offset(space)
    return math.floor(space / 4) * 2
end

local function aspect_box(mode, r, w, h)
    local wide = w / h > r
    if mode == "fit" then
        if wide then return w, ceil_even(w / r) end
        return ceil_even(h * r), h
    elseif mode == "stretch" then
        return even(h * r), h
    end
    if wide then return floor_even(h * r), h end
    return w, floor_even(w / r)
end

function M.filters(res, src_w, src_h, sar)
    local out = {}
    local w   = src_w
    local h   = src_h

    local function scale(sw, sh, scaler)
        if sw == w and sh == h then return end
        scaler        = scaler or (sw * sh < w * h and res.scaler_down or res.scaler_up)
        out[#out + 1] = string.format("scale=%d:%d:flags=%s", sw, sh, scaler)
        w             = sw
        h             = sh
    end

    local function crop(cw, ch)
        if cw == w and ch == h then return end
        out[#out + 1] = string.format("crop=%d:%d:%d:%d", cw, ch, offset(w - cw), offset(h - ch))
        w             = cw
        h             = ch
    end

    if sar and sar ~= 1 then scale(even(w * sar), h) end

    for _, layer in ipairs(res.layers) do
        local mode = layer.mode
        local tw, th
        if layer.kind == "scale" then
            tw, th, mode = even(w * layer.n), even(h * layer.n), "stretch"
        elseif layer.kind == "width" then
            tw, th, mode = even(layer.n), even(h * layer.n / w), "stretch"
        elseif layer.kind == "height" then
            tw, th, mode = even(w * layer.n / h), even(layer.n), "stretch"
        elseif layer.kind == "aspect" then
            tw, th = aspect_box(mode, layer.n, w, h)
            if mode == "cover" then mode = "crop" end
        else
            tw, th = even(layer.w), even(layer.h)
        end

        if mode == "stretch" then
            scale(tw, th, layer.scaler)
        elseif mode == "crop" then
            if tw > w or th > h then
                return nil, lang.t("resolution_too_big", { token = layer.token, size = string.format("%dx%d", w, h) })
            end
            crop(tw, th)
        elseif mode == "cover" then
            local s = math.max(tw / w, th / h)
            scale(ceil_even(w * s), ceil_even(h * s), layer.scaler)
            crop(tw, th)
        else
            local s = math.min(tw / w, th / h)
            scale(math.min(tw, even(w * s)), math.min(th, even(h * s)), layer.scaler)
            if tw ~= w or th ~= h then
                out[#out + 1] = string.format("pad=%d:%d:%d:%d:color=%s", tw, th, offset(tw - w), offset(th - h), res.pad_color)
                w             = tw
                h             = th
            end
        end
    end

    if #out > 0 then out[#out + 1] = "setsar=1" end
    return out, w, h
end

return M
