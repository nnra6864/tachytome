local M = {
    current = "2.0.0"
}

function M.parse(name)
    local s = name:match("^v?(%d[%.%d]*)$")
    if not s or s:find("%.%.") or s:sub(-1) == "." then return nil end
    local nums = {}
    for n in s:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    return nums
end

function M.newer(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return #a > #b
end

function M.compare(a, b)
    local pa, pb = M.parse(a), M.parse(b)
    if not pa or not pb then return 0 end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

return M
