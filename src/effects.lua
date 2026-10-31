local notify = require 'src.notify'
local state  = require 'src.state'
local common = require 'src.common'
local easing = require 'src.easing'

local M = {}

-- TODO: document the effect preset config (script-opts/tachytome-effects.conf)

local TWEEN_RATE   = 30
local MAX_TWEENS   = 120
local GAIN_RATE    = 60
local MAX_GAINS    = 120
local GAIN_STEP    = 1 / 256
local BLACK_FRAMES = 2
local AUDIO_CHUNK  = 256
local MAX_BLUR     = 1024
local MAX_TMIX     = 1023

local presets = {}

local timed_atoms = {
    vfade    = true,
    afade    = true,
    ramp     = true,
    vanimate = true,
    aanimate = true
}

local function preset_index(name)
    for i, p in ipairs(presets) do
        if p.name == name then return i end
    end
    return nil
end

local function upsert(preset)
    local idx = preset_index(preset.name)
    if idx then
        presets[idx] = preset
    else
        presets[#presets + 1] = preset
    end
end

local function curve_fn(ctx, name)
    if not name or name == "" then return nil end
    local fn = easing.parse(name)
    if fn then return fn end
    notify.show("effect '" .. ctx.effect .. "': unknown easing '" .. name .. "', using linear", false, "warn")
    return easing.parse("linear")
end

local function next_name(ctx)
    ctx.count = ctx.count + 1
    return "fx" .. ctx.count
end

local function make_tween(ctx, from, to, curve)
    return {
        fn   = curve or easing.parse("linear"),
        from = from,
        to   = to,
        st   = ctx.st,
        d    = ctx.d
    }
end

local function numeric_tween(ctx, from, to, curve)
    local a = tonumber(from)
    local b = tonumber(to)
    if a and b and ctx.d > 0 then return make_tween(ctx, a, b, curve_fn(ctx, curve)) end
    notify.show("effect '" .. ctx.effect .. "': animation needs numeric values and a duration", false, "warn")
    return nil
end

local function tween_value(tw, u)
    local v = tw.from + (tw.to - tw.from) * tw.fn(u)
    if tw.min and v < tw.min then return tw.min end
    if tw.max and v > tw.max then return tw.max end
    return v
end

local function tween_cmds(tw, target, option)
    local n    = math.max(1, math.min(MAX_TWEENS, math.ceil(tw.d * TWEEN_RATE)))
    local cmds = {}
    local prev = tween_value(tw, 0)
    for i = 1, n do
        local val = tween_value(tw, i / n)
        cmds[#cmds + 1] = string.format("%.4f-%.4f [expr] %s %s %.6g*(1-TI)+%.6g*TI",
            tw.st + (i - 1) * tw.d / n, tw.st + i * tw.d / n, target, option, prev, val)
        prev = val
    end
    cmds[#cmds + 1] = string.format("%.4f [enter] %s %s %.6g", tw.st + tw.d, target, option, tw.to)
    return table.concat(cmds, ";")
end

local function tween_enable(tw, idle)
    local parts = {}
    if tw.from == idle then parts[#parts + 1] = string.format("gte(t,%.4f)", tw.st) end
    if tw.to == idle then parts[#parts + 1] = string.format("lt(t,%.4f)", tw.st + tw.d) end
    if #parts == 0 then return "" end
    return string.format(":enable='%s'", table.concat(parts, "*"))
end

local function blur_filter(name, angle, amount)
    local axis = angle % 180
    if axis == 0 then
        return string.format("gblur@%s=sigma=%.6g:sigmaV=0", name, amount), "gblur@" .. name, "sigma"
    end
    if axis == 90 then
        return string.format("gblur@%s=sigma=0:sigmaV=%.6g", name, amount), "gblur@" .. name, "sigmaV"
    end
    return string.format("dblur@%s=angle=%.6g:radius=%.6g", name, angle % 360, amount), "dblur@" .. name, "radius"
end

local function gain_exprs(gain, full_range)
    local luma = full_range and "val*%.4f" or "(val-minval)*%.4f+minval"
    return string.format(luma, gain),
        string.format("(val-(maxval+minval)/2)*%.4f+(maxval+minval)/2", gain)
end

local function gain_cmds(tw, target, full_range)
    local n    = math.max(1, math.min(MAX_GAINS, math.ceil(tw.d * GAIN_RATE)))
    local cmds = {}
    local last = tween_value(tw, 0)
    for i = 1, n do
        local gain = tween_value(tw, i / n)
        if i == n or math.abs(gain - last) >= GAIN_STEP then
            local y, c = gain_exprs(gain, full_range)
            cmds[#cmds + 1] = string.format("%.4f [enter] %s y %s,[enter] %s u %s,[enter] %s v %s",
                tw.st + i * tw.d / n, target, y, target, c, target, c)
            last = gain
        end
    end
    return table.concat(cmds, ";")
end

local function fade_tween(ctx, curve)
    local from = ctx.dir == "in" and 0 or 1
    local tw   = make_tween(ctx, from, 1 - from, curve)
    tw.min     = 0
    return tw
end

local function hold_black(ctx, tw)
    local hold = math.min(ctx.frame * BLACK_FRAMES, tw.d / 2)
    tw.d = tw.d - hold
    if ctx.dir == "in" then tw.st = tw.st + hold end
end

local atom_builders = {}

function atom_builders.vfade(ctx, args)
    local tw     = fade_tween(ctx, curve_fn(ctx, args[1]))
    local name   = next_name(ctx)
    local target = "lutyuv@" .. name
    local y, c   = gain_exprs(tw.from, ctx.full_range)
    hold_black(ctx, tw)
    ctx.vf[#ctx.vf + 1] = string.format("sendcmd=c='%s',%s=y=%s:u=%s:v=%s%s",
        gain_cmds(tw, target, ctx.full_range), target, y, c, c, tween_enable(tw, 1))
end

function atom_builders.afade(ctx, args)
    local curve = curve_fn(ctx, args[1])
    if not curve then
        ctx.af[#ctx.af + 1] = string.format("afade=t=%s:st=%.3f:d=%.3f:curve=qsin", ctx.dir, ctx.st, ctx.d)
        return
    end
    local tw     = fade_tween(ctx, curve)
    local target = "volume@" .. next_name(ctx)
    ctx.af[#ctx.af + 1] = string.format("asetnsamples=n=%d:p=0,asendcmd=c='%s',%s=%.6g%s",
        AUDIO_CHUNK, tween_cmds(tw, target, "volume"), target, tw.from, tween_enable(tw, 1))
end

function atom_builders.ramp(ctx, args)
    local tw = numeric_tween(ctx, args[1], args[2], args[4])
    if not tw then return end
    tw.from = math.max(0, math.min(MAX_BLUR, tw.from))
    tw.to   = math.max(0, math.min(MAX_BLUR, tw.to))
    tw.min  = 0
    tw.max  = MAX_BLUR

    local filter, target, option = blur_filter(next_name(ctx), tonumber(args[3]) or 0, tw.from)
    ctx.vf[#ctx.vf + 1] = string.format("sendcmd=c='%s',%s%s",
        tween_cmds(tw, target, option), filter, tween_enable(tw, 0))
end

function atom_builders.blur(ctx, args)
    local amount = math.min(MAX_BLUR, tonumber(args[1]) or 0)
    if amount <= 0 then return end
    local filter = blur_filter(next_name(ctx), tonumber(args[2]) or 0, amount)
    if ctx.d > 0 then
        filter = filter .. string.format(":enable='gte(t,%.4f)*lt(t,%.4f)'", ctx.st, ctx.st + ctx.d)
    end
    ctx.vf[#ctx.vf + 1] = filter
end

function atom_builders.tmix(ctx, args)
    local frames = math.floor(tonumber(args[1]) or 0)
    if frames >= 2 then
        ctx.vf[#ctx.vf + 1] = string.format("tmix=frames=%d", math.min(frames, MAX_TMIX))
    end
end

function atom_builders.vanimate(ctx, args)
    local tw = numeric_tween(ctx, args[3], args[4], args[5])
    if tw then ctx.vf[#ctx.vf + 1] = string.format("sendcmd=c='%s'", tween_cmds(tw, args[1], args[2])) end
end

function atom_builders.aanimate(ctx, args)
    local tw = numeric_tween(ctx, args[3], args[4], args[5])
    if tw then ctx.af[#ctx.af + 1] = string.format("asendcmd=c='%s'", tween_cmds(tw, args[1], args[2])) end
end

function atom_builders.video(ctx, args)
    ctx.vf[#ctx.vf + 1] = args[1]
end

function atom_builders.audio(ctx, args)
    ctx.af[#ctx.af + 1] = args[1]
end

local function fill(template, vars)
    return (template:gsub("{([%w_]+)}", function(k)
        if vars[k] ~= nil then return tostring(vars[k]) end
        return "{" .. k .. "}"
    end))
end

function M.preset(name)
    local idx = preset_index(name)
    if idx then return presets[idx] end
    return nil
end

function M.list()
    return presets
end

function M.instance(name)
    for _, inst in ipairs(state.effects) do
        if inst.name == name then return inst end
    end
    return nil
end

function M.snapshot()
    local copy = {}
    for _, inst in ipairs(state.effects) do
        local params = {}
        for k, v in pairs(inst.params) do params[k] = v end
        copy[#copy + 1] = { name = inst.name, params = params }
    end
    return copy
end

function M.is_curve(value)
    return easing.parse(value) ~= nil
end

function M.build_filters(instances, duration, offset, media)
    local ctx = {
        vf         = {},
        af         = {},
        count      = 0,
        full_range = media.full_range,
        frame      = media.fps and 1 / media.fps or 0
    }

    for _, inst in ipairs(instances) do
        local p = M.preset(inst.name)
        if p then
            ctx.effect = p.name
            ctx.d      = math.min(tonumber(inst.params.d) or p.d or 0, duration)

            local vars = {
                d        = string.format("%.3f", ctx.d),
                duration = string.format("%.3f", duration)
            }
            for _, prm in ipairs(p.params) do
                vars[prm.key] = inst.params[prm.key] or prm.default
            end

            for _, atom in ipairs(p.atoms) do
                local rel = atom.anchor == "end" and math.max(0, duration - ctx.d) or 0

                ctx.st  = offset + rel
                ctx.dir = atom.anchor == "end" and "out" or "in"
                vars.st = string.format("%.3f", ctx.st)

                local args = {}
                for _, raw in ipairs(atom.args) do args[#args + 1] = fill(raw, vars) end
                atom_builders[atom.type](ctx, args)
            end
        end
    end

    return ctx.vf, ctx.af
end

local function join_parens(words, first)
    local out = words[first]
    if not out then return nil, first end
    local i = first
    while out:find("(", 1, true) and not out:match("%)$") and i < #words do
        i   = i + 1
        out = out .. " " .. words[i]
    end
    return out, i
end

local function arg_list(words, first, max)
    local args = {}
    local i    = first
    while i <= #words and #args < max do
        local val
        val, i = join_parens(words, i)
        args[#args + 1] = val
        i = i + 1
    end
    return args
end

local function add_atom(current, atom_type, args)
    current.atoms[#current.atoms + 1] = { type = atom_type, args = args, anchor = current.anchor }
end

local function finish_effect(current)
    if #current.atoms == 0 then
        notify.show("empty effect: " .. current.name, false, "warn")
        return
    end
    for _, atom in ipairs(current.atoms) do
        if timed_atoms[atom.type] then current.d = current.d or 1 end
    end
    upsert(current)
end

local function parse_effects_file(path)
    local f = io.open(path, "r")
    if not f then return end

    local current = nil
    for line in f:lines() do
        local content = line:gsub("\r$", "")
        local hash = content:find("#", 1, true)
        if hash then content = content:sub(1, hash - 1) end
        content = content:match("^%s*(.-)%s*$")
        if content ~= "" then
            local words = {}
            for w in content:gmatch("%S+") do words[#words + 1] = w end
            local head = words[1]

            if current then
                if head == "end" and #words == 1 then
                    finish_effect(current)
                    current = nil
                elseif head == "label" and #words > 1 then
                    current.label = content:match("^%s*label%s+(.+)$")
                elseif head == "anchor" and (words[2] == "start" or words[2] == "end") then
                    current.anchor = words[2]
                elseif head == "duration" and tonumber(words[2]) and tonumber(words[2]) > 0 then
                    current.d = tonumber(words[2])
                elseif head == "param" and words[2] and words[3] then
                    local val = content:match("^%s*param%s+%S+%s+(.-)%s*$")
                    current.params[#current.params + 1] = { key = words[2], default = tonumber(val) or val }
                elseif head == "fade" then
                    local curve = content:match("^%s*fade%s+(.-)%s*$")
                    add_atom(current, "vfade", { curve })
                    add_atom(current, "afade", { curve })
                elseif (head == "vfade" or head == "afade") then
                    add_atom(current, head, { content:match("^%s*" .. head .. "%s+(.-)%s*$") })
                elseif head == "ramp" and #words >= 3 then
                    add_atom(current, "ramp", arg_list(words, 2, 4))
                elseif head == "blur" and #words >= 2 then
                    add_atom(current, "blur", arg_list(words, 2, 2))
                elseif head == "tmix" and #words >= 2 then
                    add_atom(current, "tmix", arg_list(words, 2, 1))
                elseif (head == "vanimate" or head == "aanimate") and #words >= 5 then
                    add_atom(current, head, arg_list(words, 2, 5))
                elseif (head == "video" or head == "audio") and #words > 1 then
                    add_atom(current, head, { content:match("^%s*" .. head .. "%s+(.+)$") })
                else
                    notify.show("invalid line in effect '" .. current.name .. "': " .. content, false, "warn")
                end
            elseif head == "effect" and #words == 2 then
                current = {
                    name   = words[2],
                    label  = words[2],
                    anchor = "start",
                    params = {},
                    atoms  = {}
                }
            else
                notify.show("invalid effects line: " .. content, false, "warn")
            end
        end
    end
    f:close()

    if current then notify.show("unclosed effect: " .. current.name, false, "warn") end
end

local function seed_from_opts()
    local names = {}
    local raw   = state.opts.effects_presets or ""
    for entry in raw:gmatch("[^,]+") do
        local name = entry:match("^%s*(.-)%s*$")
        if name ~= "" then names[#names + 1] = name end
    end
    if state.opts.effects_enabled then
        state.effects_enabled = true
        state.opts.lossless_cut = false
    end
    for _, name in ipairs(names) do
        if M.preset(name) then
            if not M.instance(name) then
                state.effects[#state.effects + 1] = { name = name, params = {} }
            end
        else
            notify.show("unknown preset in effects_presets: " .. name, false, "warn")
        end
    end
end

parse_effects_file(common.ensure_default_conf("tachytome-effects.conf"))
seed_from_opts()

function M.label(name)
    local p = M.preset(name)
    return p and p.label or name
end

return M
