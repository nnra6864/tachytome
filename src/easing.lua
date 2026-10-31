local M = {}

local c1 = 1.70158
local c2 = c1 * 1.525
local c3 = c1 + 1
local c4 = 2 * math.pi / 3
local c5 = 2 * math.pi / 4.5

local function out_bounce(t)
    local n1 = 7.5625
    local d1 = 2.75
    if t < 1 / d1 then return n1 * t * t end
    if t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    end
    if t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

local easings = {
    linear              = function(t) return t end,
    ease_in_quad        = function(t) return t * t end,
    ease_out_quad       = function(t) return 1 - (1 - t) * (1 - t) end,
    ease_in_out_quad    = function(t)
        if t < 0.5 then return 2 * t * t end
        return 1 - (-2 * t + 2) ^ 2 / 2
    end,
    ease_in_cubic       = function(t) return t * t * t end,
    ease_out_cubic      = function(t) return 1 - (1 - t) ^ 3 end,
    ease_in_out_cubic   = function(t)
        if t < 0.5 then return 4 * t * t * t end
        return 1 - (-2 * t + 2) ^ 3 / 2
    end,
    ease_in_quart       = function(t) return t ^ 4 end,
    ease_out_quart      = function(t) return 1 - (1 - t) ^ 4 end,
    ease_in_out_quart   = function(t)
        if t < 0.5 then return 8 * t ^ 4 end
        return 1 - (-2 * t + 2) ^ 4 / 2
    end,
    ease_in_quint       = function(t) return t ^ 5 end,
    ease_out_quint      = function(t) return 1 - (1 - t) ^ 5 end,
    ease_in_out_quint   = function(t)
        if t < 0.5 then return 16 * t ^ 5 end
        return 1 - (-2 * t + 2) ^ 5 / 2
    end,
    ease_in_sine        = function(t) return 1 - math.cos(t * math.pi / 2) end,
    ease_out_sine       = function(t) return math.sin(t * math.pi / 2) end,
    ease_in_out_sine    = function(t) return -(math.cos(math.pi * t) - 1) / 2 end,
    ease_in_expo        = function(t)
        if t == 0 then return 0 end
        return 2 ^ (10 * t - 10)
    end,
    ease_out_expo       = function(t)
        if t == 1 then return 1 end
        return 1 - 2 ^ (-10 * t)
    end,
    ease_in_out_expo    = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        if t < 0.5 then return 2 ^ (20 * t - 10) / 2 end
        return (2 - 2 ^ (-20 * t + 10)) / 2
    end,
    ease_in_circ        = function(t) return 1 - math.sqrt(1 - t * t) end,
    ease_out_circ       = function(t) return math.sqrt(1 - (t - 1) ^ 2) end,
    ease_in_out_circ    = function(t)
        if t < 0.5 then return (1 - math.sqrt(1 - (2 * t) ^ 2)) / 2 end
        return (math.sqrt(1 - (-2 * t + 2) ^ 2) + 1) / 2
    end,
    ease_in_back        = function(t) return c3 * t ^ 3 - c1 * t * t end,
    ease_out_back       = function(t) return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2 end,
    ease_in_out_back    = function(t)
        if t < 0.5 then return (2 * t) ^ 2 * ((c2 + 1) * 2 * t - c2) / 2 end
        return ((2 * t - 2) ^ 2 * ((c2 + 1) * (2 * t - 2) + c2) + 2) / 2
    end,
    ease_in_elastic     = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        return -(2 ^ (10 * t - 10)) * math.sin((10 * t - 10.75) * c4)
    end,
    ease_out_elastic    = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        return 2 ^ (-10 * t) * math.sin((10 * t - 0.75) * c4) + 1
    end,
    ease_in_out_elastic = function(t)
        if t == 0 then return 0 end
        if t == 1 then return 1 end
        if t < 0.5 then return -(2 ^ (20 * t - 10) * math.sin((20 * t - 11.125) * c5)) / 2 end
        return (2 ^ (-20 * t + 10) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
    end,
    ease_in_bounce      = function(t) return 1 - out_bounce(1 - t) end,
    ease_out_bounce     = out_bounce,
    ease_in_out_bounce  = function(t)
        if t < 0.5 then return (1 - out_bounce(1 - 2 * t)) / 2 end
        return (1 + out_bounce(2 * t - 1)) / 2
    end
}

function M.bezier(x1, y1, x2, y2)
    local ax = 1 - 3 * x2 + 3 * x1
    local bx = 3 * x2 - 6 * x1
    local cx = 3 * x1
    local ay = 1 - 3 * y2 + 3 * y1
    local by = 3 * y2 - 6 * y1
    local cy = 3 * y1

    local function x_at(t) return ((ax * t + bx) * t + cx) * t end
    local function dx_at(t) return (3 * ax * t + 2 * bx) * t + cx end
    local function y_at(t) return ((ay * t + by) * t + cy) * t end

    return function(x)
        if x <= 0 then return 0 end
        if x >= 1 then return 1 end
        local t = x
        for _ = 1, 8 do
            local diff = x_at(t) - x
            if math.abs(diff) < 1e-7 then return y_at(t) end
            local slope = dx_at(t)
            if math.abs(slope) < 1e-6 then break end
            t = t - diff / slope
        end
        local lo = 0
        local hi = 1
        while hi - lo > 1e-7 do
            t = (lo + hi) / 2
            if x_at(t) < x then lo = t else hi = t end
        end
        return y_at((lo + hi) / 2)
    end
end

function M.parse(str)
    if type(str) ~= "string" then return nil end
    local args = str:match("^%s*bezier%s*%((.-)%)%s*$")
    if args then
        local x1, y1, x2, y2 = args:match("^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
        x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
        if x1 and y1 and x2 and y2 and x1 >= 0 and x1 <= 1 and x2 >= 0 and x2 <= 1 then
            return M.bezier(x1, y1, x2, y2)
        end
        return nil
    end
    return easings[str]
end

return M
