local mp = require 'mp'

local M = {}

function M.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a") or ""
    f:close()
    local eol   = text:find("\r\n", 1, true) and "\r\n" or "\n"
    local lines = {}
    for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if text == "" or text:sub(-1) == "\n" then lines[#lines] = nil end
    return lines, eol
end

function M.write(path, lines, eol)
    local f = io.open(path, "wb")
    if not f then
        mp.msg.warn("Failed to write " .. path)
        return false
    end
    eol = eol or "\n"
    f:write(#lines > 0 and table.concat(lines, eol) .. eol or "")
    f:close()
    return true
end

function M.same(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

function M.blank(line)
    return line == nil or line:match("^%s*$") ~= nil
end

function M.comment(line)
    return line ~= nil and line:match("^%s*#") ~= nil
end

return M
