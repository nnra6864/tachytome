local mp      = require 'mp'
local utils   = require 'mp.utils'
local notify  = require 'src.notify'
local state   = require 'src.state'

local M = {}

-- TODO: document the effect preset config (script-opts/tachytome-effects.conf)

local presets = {
    {
        name   = "fade_in",
        label  = "Fade In",
        anchor = "start",
        d      = 0.5,
        video  = "fade=t=in:st={st}:d={d}",
        audio  = "afade=t=in:st={st}:d={d}:curve=qsin"
    },
    {
        name   = "fade_out",
        label  = "Fade Out",
        anchor = "end",
        d      = 0.5,
        video  = "fade=t=out:st={st}:d={d}",
        audio  = "afade=t=out:st={st}:d={d}:curve=qsin"
    },
    {
        name   = "audio_fade_in",
        label  = "Audio Fade In",
        anchor = "start",
        d      = 0.5,
        audio  = "afade=t=in:st={st}:d={d}:curve=qsin"
    },
    {
        name   = "audio_fade_out",
        label  = "Audio Fade Out",
        anchor = "end",
        d      = 0.5,
        audio  = "afade=t=out:st={st}:d={d}:curve=qsin"
    },
    {
        name   = "dir_blur",
        label  = "Directional Blur",
        params = {
            { key = "amount", default = 20 },
            { key = "angle",  default = 0 }
        },
        build  = function(v)
            local passes = string.format("avgblur=sizeX=%s:sizeY=0,avgblur=sizeX=%s:sizeY=0", v.amount, v.amount)
            local a      = math.abs(tonumber(v.angle) or 0) % 180
            if a == 0 then return passes end
            if a == 90 then
                return string.format("avgblur=sizeX=1:sizeY=%s,avgblur=sizeX=1:sizeY=%s", v.amount, v.amount)
            end
            return string.format("rotate=%s*PI/180:ow=iw:oh=ih:c=black,%s,rotate=-%s*PI/180:ow=iw:oh=ih:c=black", a, passes, a)
        end
    },
    {
        name   = "motion_blur",
        label  = "Motion Blur",
        params = {
            { key = "frames", default = 5 }
        },
        build  = function(v)
            return string.format("tmix=frames=%s", v.frames)
        end
    }
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
                    if current.video or current.audio then upsert(current) end
                    current = nil
                elseif head == "video" and #words > 1 then
                    current.video = content:match("^%s*video%s+(.+)$")
                elseif head == "audio" and #words > 1 then
                    current.audio = content:match("^%s*audio%s+(.+)$")
                elseif head == "label" and #words > 1 then
                    current.label = content:match("^%s*label%s+(.+)$")
                elseif head == "anchor" and (words[2] == "start" or words[2] == "end") then
                    current.anchor = words[2]
                elseif head == "duration" and tonumber(words[2]) then
                    local n = tonumber(words[2])
                    if n > 0 then current.d = n end
                elseif head == "param" and words[3] and tonumber(words[3]) then
                    current.params = current.params or {}
                    current.params[#current.params + 1] = { key = words[2], default = tonumber(words[3]) }
                else
                    notify.show("invalid line in effect '" .. current.name .. "': " .. content, false, "warn")
                end
            elseif head == "effect" and words[2] and #words == 2 then
                current = { name = words[2], label = words[2] }
            end
        end
    end
    f:close()

    if current then notify.show("unclosed effect: " .. current.name, false, "warn") end
end

local opts_dir = mp.command_native({"expand-path", "~~/script-opts"})
parse_effects_file(utils.join_path(opts_dir, "tachytome-effects.conf"))

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

local function fill(template, vars)
    return (template:gsub("{(%w+)}", function(k)
        if vars[k] ~= nil then return tostring(vars[k]) end
        return "{" .. k .. "}"
    end))
end

function M.build_filters(instances, duration, offset)
    local vf = {}
    local af = {}

    for _, inst in ipairs(instances) do
        local p = M.preset(inst.name)
        if p then
            local d    = math.min(tonumber(inst.params.d) or p.d or 0, duration)
            local rel  = p.anchor == "end" and math.max(0, duration - d) or 0
            local vars = {
                d        = string.format("%.3f", d),
                st       = string.format("%.3f", offset + rel),
                duration = string.format("%.3f", duration)
            }
            if p.params then
                for _, prm in ipairs(p.params) do
                    vars[prm.key] = tonumber(inst.params[prm.key]) or prm.default
                end
            end
            if p.build then
                local chain = p.build(vars)
                if chain ~= "" then vf[#vf + 1] = chain end
            else
                if p.video then vf[#vf + 1] = fill(p.video, vars) end
                if p.audio then af[#af + 1] = fill(p.audio, vars) end
            end
        end
    end

    return vf, af
end

function M.summary(inst)
    local p = M.preset(inst.name)
    if not p then return inst.name end
    local parts = {}
    if p.d then parts[#parts + 1] = string.format("%gs", tonumber(inst.params.d) or p.d) end
    if p.params then
        for _, prm in ipairs(p.params) do
            parts[#parts + 1] = tostring(tonumber(inst.params[prm.key]) or prm.default)
        end
    end
    if #parts == 0 then return p.label end
    return string.format("%s(%s)", p.label, table.concat(parts, ", "))
end

function M.summary_for(name)
    local inst = M.instance(name)
    local p    = M.preset(name)
    if not p then return name end
    if inst then return M.summary(inst) end
    local parts = {}
    if p.d then parts[#parts + 1] = string.format("%gs", p.d) end
    if p.params then
        for _, prm in ipairs(p.params) do
            parts[#parts + 1] = tostring(prm.default)
        end
    end
    if #parts == 0 then return p.label end
    return string.format("%s(%s)", p.label, table.concat(parts, ", "))
end

return M
