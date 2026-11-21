local mp    = require 'mp'
local state = require 'src.state'

local M = {}

local samples   = 8
local frames    = 6
local min_bar   = 0.005
local cache     = {}
local listeners = {}

local function key(path, a, b)
    return string.format("%s|%.2f|%.2f", path, a, b)
end

local function frame_size()
    local p = mp.get_property_native("video-params")
    if not p or not p.w or not p.h then return nil end
    if (tonumber(p.rotate) or 0) % 180 == 90 then return p.h, p.w end
    return p.w, p.h
end

local function parse(stderr)
    local box = nil
    for x1, x2, y1, y2 in stderr:gmatch("x1:(%-?%d+) x2:(%-?%d+) y1:(%-?%d+) y2:(%-?%d+)") do
        box = { x1 = tonumber(x1), x2 = tonumber(x2), y1 = tonumber(y1), y2 = tonumber(y2) }
    end
    if box and box.x2 > box.x1 and box.y2 > box.y1 then return box end
    return nil
end

local function finish(entry, w, h)
    local u = entry.union
    if not u then
        entry.box = false
    else
        local x1 = u.x1 / w
        local x2 = (u.x2 + 1) / w
        local y1 = u.y1 / h
        local y2 = (u.y2 + 1) / h
        if x1 < min_bar then x1 = 0 end
        if y1 < min_bar then y1 = 0 end
        if x2 > 1 - min_bar then x2 = 1 end
        if y2 > 1 - min_bar then y2 = 1 end
        if x1 == 0 and y1 == 0 and x2 == 1 and y2 == 1 then
            entry.box = false
        else
            entry.box = { x1 = x1, x2 = x2, y1 = y1, y2 = y2 }
        end
    end
    entry.pending = false
    local waiting = entry.waiting
    entry.waiting = {}
    for _, fn in ipairs(waiting) do fn(entry.box) end
    for _, fn in pairs(listeners) do fn() end
end

local function detect(entry, path, a, b, w, h)
    local left = samples
    for i = 1, samples do
        local t = a + (b - a) * (i - 0.5) / samples
        mp.command_native_async({
            name           = "subprocess",
            args           = { "ffmpeg", "-hide_banner", "-nostdin", "-ss", string.format("%.3f", t), "-i", path, "-map", "0:v:0", "-frames:v", tostring(frames), "-vf", "cropdetect=round=2:reset=0:skip=0", "-an", "-sn", "-f", "null", "-" },
            playback_only  = false,
            capture_stderr = true
        }, function(_, result)
            local box = result and result.stderr and parse(result.stderr)
            if box then
                local u = entry.union
                if not u then
                    entry.union = box
                else
                    u.x1 = math.min(u.x1, box.x1)
                    u.x2 = math.max(u.x2, box.x2)
                    u.y1 = math.min(u.y1, box.y1)
                    u.y2 = math.max(u.y2, box.y2)
                end
            end
            left = left - 1
            if left == 0 then finish(entry, w, h) end
        end)
    end
end

local function current()
    local path = mp.get_property("path")
    if not path or not frame_size() then return nil end
    local a = state.mark_in or 0
    local b = state.mark_out or 0
    if b <= a then b = mp.get_property_number("duration", a) end
    return path, a, b
end

function M.peek()
    local path, a, b = current()
    if not path then return false end
    local entry = cache[key(path, a, b)]
    if entry and not entry.pending then return entry.box end
    return nil
end

function M.request(on_done)
    local path, a, b = current()
    local w, h       = frame_size()
    if not path then
        if on_done then on_done(false) end
        return false
    end
    local k     = key(path, a, b)
    local entry = cache[k]
    if not entry then
        entry    = { pending = true, waiting = {} }
        cache[k] = entry
        detect(entry, path, a, b, w, h)
    end
    if entry.pending then
        if on_done then entry.waiting[#entry.waiting + 1] = on_done end
        return nil, true
    end
    if on_done then on_done(entry.box) end
    return entry.box
end

function M.forget()
    local path, a, b = current()
    if not path then return end
    local k = key(path, a, b)
    if cache[k] and not cache[k].pending then cache[k] = nil end
end

function M.listen(name, fn)
    listeners[name] = fn
end

return M
