local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local state  = require 'src.state'
local lang   = require 'src.lang'

local M = {}

M.modes   = { "fit", "cover", "stretch", "crop" }
M.scalers = { "lanczos", "spline", "bicubic", "area", "bilinear", "neighbor", "fast_bilinear", "bicublin", "gauss", "sinc" }

local history_path = utils.join_path(common.get_state_dir(), "resolution_history.json")
local odd_sizes    = { av1 = true, nv_h264 = true }

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

function M.parse(text)
    local layers = {}
    for token in text:gmatch("%S+") do
        local word  = token:lower()
        local layer = size(word)
        local last  = layers[#layers]
        if layer then
            layer.size          = token
            layers[#layers + 1] = layer
        elseif last and modes[word] then
            last.mode = word
        elseif last and scalers[word] then
            last.scaler = word
        else
            return nil, token
        end
    end
    return layers
end

function M.layer_text(layer)
    local parts = { layer.size }
    if layer.mode then parts[#parts + 1] = layer.mode end
    if layer.scaler then parts[#parts + 1] = layer.scaler end
    return table.concat(parts, " ")
end

function M.format(layers)
    local parts = {}
    for _, layer in ipairs(layers) do parts[#parts + 1] = M.layer_text(layer) end
    return table.concat(parts, " ")
end

function M.keeps_aspect(layer)
    return layer.kind == "scale" or layer.kind == "width" or layer.kind == "height"
end

function M.step(encoder)
    return odd_sizes[tostring(encoder):lower()] and 1 or 2
end

function M.seed()
    state.resolution         = state.opts.resolution
    state.resolution_enabled = state.opts.resolution_enabled
    if state.resolution_enabled then state.opts.lossless_cut = false end
end

function M.build(text)
    local o = state.opts
    for _, val in ipairs({ o.scaler_down, o.scaler_up }) do
        if not scalers[val] then return nil, lang.t("resolution_unknown", { token = val }) end
    end
    if not modes[o.resolution_mode] then return nil, lang.t("resolution_unknown", { token = o.resolution_mode }) end
    local layers, bad = M.parse(text)
    if not layers then return nil, lang.t("resolution_unknown", { token = bad }) end
    for _, layer in ipairs(layers) do
        layer.token = M.layer_text(layer)
        layer.mode  = layer.mode or o.resolution_mode
    end
    return {
        layers      = layers,
        scaler_down = o.scaler_down,
        scaler_up   = o.scaler_up,
        pad_color   = o.pad_color
    }
end

function M.snapshot()
    if not state.resolution_enabled then return nil end
    local res, err = M.build(state.resolution)
    if not res then return nil, err end
    if #res.layers == 0 then return nil end
    return res
end

local function snap(x, step)
    return math.max(2, math.floor(x / step + 0.5) * step)
end

local function snap_down(x, step)
    return math.max(2, math.floor(x / step) * step)
end

local function snap_up(x, step)
    return math.max(2, math.ceil(x / step) * step)
end

local function offset(space)
    return math.floor(space / 4) * 2
end

local function aspect_box(mode, r, w, h, step)
    local wide = w / h > r
    if mode == "fit" then
        if wide then return snap_up(w, step), snap_up(w / r, step) end
        return snap_up(h * r, step), snap_up(h, step)
    elseif mode == "stretch" then
        return snap(h * r, step), snap(h, step)
    end
    if wide then return snap_down(h * r, step), snap_down(h, step) end
    return snap_down(w, step), snap_down(w / r, step)
end

function M.filters(res, src_w, src_h, sar, step)
    local out   = {}
    local steps = {}
    local w     = src_w
    local h     = src_h
    local used  = nil

    local function snapped(x)
        return snap(x, step)
    end

    local function scale(sw, sh, scaler)
        if sw == w and sh == h then return end
        used          = scaler or (sw * sh < w * h and res.scaler_down or res.scaler_up)
        out[#out + 1] = string.format("scale=%d:%d:flags=%s", sw, sh, used)
        w             = sw
        h             = sh
    end

    local function crop(cw, ch)
        if cw == w and ch == h then return end
        out[#out + 1] = string.format("crop=%d:%d:%d:%d", cw, ch, offset(w - cw), offset(h - ch))
        w             = cw
        h             = ch
    end

    if sar and sar ~= 1 then scale(snapped(w * sar), h) end
    steps.source = { w = w, h = h }

    for _, layer in ipairs(res.layers) do
        local mode = layer.mode
        local tw, th
        used = nil
        if layer.kind == "scale" then
            tw, th, mode = snapped(w * layer.n), snapped(h * layer.n), "stretch"
        elseif layer.kind == "width" then
            tw, th, mode = snapped(layer.n), snapped(h * layer.n / w), "stretch"
        elseif layer.kind == "height" then
            tw, th, mode = snapped(w * layer.n / h), snapped(layer.n), "stretch"
        elseif layer.kind == "aspect" then
            tw, th = aspect_box(mode, layer.n, w, h, step)
            if mode == "cover" then mode = "crop" end
        else
            tw, th = snapped(layer.w), snapped(layer.h)
        end

        if mode == "stretch" then
            scale(tw, th, layer.scaler)
        elseif mode == "crop" then
            if tw > w or th > h then
                return nil, lang.t("resolution_too_big", { token = layer.token, size = string.format("%dx%d", w, h) }), steps
            end
            crop(tw, th)
        elseif mode == "cover" then
            local s = math.max(tw / w, th / h)
            scale(snap_up(w * s, step), snap_up(h * s, step), layer.scaler)
            crop(tw, th)
        else
            local s = math.min(tw / w, th / h)
            scale(math.min(tw, snapped(w * s)), math.min(th, snapped(h * s)), layer.scaler)
            if tw ~= w or th ~= h then
                out[#out + 1] = string.format("pad=%d:%d:%d:%d:color=%s", tw, th, offset(tw - w), offset(th - h), res.pad_color)
                w             = tw
                h             = th
            end
        end
        steps[#steps + 1] = { w = w, h = h, scaler = used }
    end

    if #out > 0 then out[#out + 1] = "setsar=1" end
    return out, nil, steps
end

function M.source()
    local p = mp.get_property_native("video-params")
    if not p or not p.w or not p.h then return nil end
    local par = tonumber(p.par) or 1
    if (tonumber(p.rotate) or 0) % 180 == 90 then return { w = p.h, h = p.w, sar = 1 / par } end
    return { w = p.w, h = p.h, sar = par }
end

function M.trace(text)
    local res, err = M.build(text)
    if not res then return nil, err end
    local src = M.source()
    if not src then return nil end
    local _, ferr, steps = M.filters(res, src.w, src.h, src.sar, M.step(state.opts.video_encoder))
    return steps, ferr
end

function M.dims(s)
    return string.format("%dx%d", s.w, s.h)
end

function M.output(text)
    local steps, err = M.trace(text)
    if err then return nil, err end
    if not steps or #steps == 0 then return nil end
    return M.dims(steps[#steps])
end

function M.describe(text)
    local steps, err = M.trace(text)
    if err then return err end
    if not steps then return "" end
    local last = steps[#steps] or steps.source
    return string.format("%s -> %s", M.dims(steps.source), M.dims(last))
end

M.history = common.read_json_file(history_path)
if type(M.history) ~= "table" then M.history = {} end

function M.remember(text)
    if text == "" then return end
    common.add_to_history(M.history, text)
    common.write_json_file(history_path, M.history)
end

M.seed()

return M
