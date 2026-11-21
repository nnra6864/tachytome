local utils      = require 'mp.utils'
local common     = require 'src.common'
local file_lines = require 'src.file_lines'

local M = {}

function M.path(file, ext)
    return utils.join_path(common.get_conf_dir(), file .. "." .. ext)
end

function M.list(ext)
    local files = {}
    for _, name in ipairs(utils.readdir(common.get_conf_dir(), "files") or {}) do
        local file = name:match("^(.+)%." .. ext .. "$")
        if file then files[#files + 1] = file end
    end
    table.sort(files)
    return files
end

function M.valid_file(name)
    return name:match("^[^%s/\\=#\"]+$") ~= nil
end

function M.strip(line)
    return (line:gsub("#.*$", "")):match("^%s*(.-)%s*$")
end

function M.definition(line, block)
    local body = M.strip(line)
    local rest = body:match("^disabled%s+([^=%s].*)$")
    local text = rest or body
    local name = nil
    if block then
        name = text:match("^effect%s+(%S+)$")
    else
        name = text:match("^([^%s=/]+)%s*=")
    end
    return name and name:lower(), rest ~= nil
end

local function paragraph(lines, first, last)
    local top = first
    while file_lines.comment(lines[top - 1]) do top = top - 1 end
    return top, file_lines.blank(lines[top - 1]) and file_lines.blank(lines[last + 1])
end

function M.comment_above(lines, first, last)
    local top, alone = paragraph(lines, first, last)
    if alone and top < first then return top end
    return nil
end

function M.span(lines, first, last)
    local top, alone = paragraph(lines, first, last)
    if not alone then return first, last end
    if lines[last + 1] then
        last = last + 1
    elseif lines[top - 1] then
        top = top - 1
    end
    return top, last
end

return M
