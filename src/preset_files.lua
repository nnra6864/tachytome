local mp         = require 'mp'
local utils      = require 'mp.utils'
local common     = require 'src.common'
local file_lines = require 'src.file_lines'
local notify     = require 'src.notify'
local lang       = require 'src.lang'

local M = {
    builtin = "default",
    user    = "user"
}

local builtin_files = {
    res = "tachytome-resolutions.conf",
    trk = "tachytome-tracks.conf",
    eff = "tachytome-effects.conf"
}

function M.builtin_path(ext)
    return utils.join_path(mp.get_script_directory() or "", builtin_files[ext])
end

function M.path(file, ext)
    if file == M.builtin then return M.builtin_path(ext) end
    return utils.join_path(common.get_conf_dir(), file .. "." .. ext)
end

function M.list(ext)
    local files = {}
    for _, name in ipairs(utils.readdir(common.get_conf_dir(), "files") or {}) do
        local file = name:match("^(.+)%." .. ext .. "$")
        if file and file ~= M.builtin then files[#files + 1] = file end
    end
    table.sort(files)
    return files
end

function M.sources(ext)
    local out = { { file = M.builtin, path = M.builtin_path(ext) } }
    for _, file in ipairs(M.list(ext)) do out[#out + 1] = { file = file, path = M.path(file, ext) } end
    return out
end

function M.valid_file(name)
    return name:match("^[^%s/\\=#\"]+$") ~= nil and name:lower() ~= M.builtin
end

function M.state(content, file)
    if file == M.builtin then return nil end
    local name, val = content:match("^" .. M.builtin .. "/([^%s=/]+)%s*=%s*(%a+)$")
    if not name or (val ~= "on" and val ~= "off") then return nil end
    return name:lower(), val == "on"
end

function M.apply_states(presets, states)
    local builtin = {}
    for _, p in ipairs(presets) do
        if p.file == M.builtin then
            p.builtin_disabled = p.disabled
            p.states           = {}
            builtin[p.name]    = p
        end
    end
    for _, s in ipairs(states) do
        local p = builtin[s.name]
        if p then
            p.disabled              = not s.on
            p.states[#p.states + 1] = s
        else
            notify.show(lang.t("warn_not_builtin", { name = M.builtin .. "/" .. s.name, where = s.where }), false, "warn")
        end
    end
end

function M.set_state(p, ext, on)
    local by_file = {}
    for _, s in ipairs(p.states or {}) do
        by_file[s.file] = by_file[s.file] or {}
        table.insert(by_file[s.file], s.line)
    end
    if on == p.builtin_disabled then by_file[M.user] = by_file[M.user] or {} end
    for file, rows in pairs(by_file) do
        local path       = M.path(file, ext)
        local lines, eol = file_lines.read(path)
        lines            = lines or {}
        table.sort(rows, function(a, b) return a > b end)
        for _, n in ipairs(rows) do
            if M.state(M.strip(lines[n] or "")) == p.name then table.remove(lines, n) end
        end
        if file == M.user and on == p.builtin_disabled then
            lines[#lines + 1] = string.format("%s/%s = %s", M.builtin, p.name, on and "on" or "off")
        end
        while #lines > 0 and file_lines.blank(lines[#lines]) do lines[#lines] = nil end
        if #lines == 0 then
            os.remove(path)
        else
            common.ensure_dir(common.get_conf_dir())
            if not file_lines.write(path, lines, eol) then return false, file .. "." .. ext end
        end
    end
    return true
end

function M.find(presets, word, disabled)
    for _, p in ipairs(presets) do
        if p.id:lower() == word and not p.disabled == not disabled then return p end
    end
    for i = #presets, 1, -1 do
        local p = presets[i]
        if p.name == word and not p.disabled == not disabled then return p end
    end
    return nil
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

local function comment_text(line)
    return (line:match("^%s*#(.*)$"):gsub("^ ", ""):gsub("%s+$", ""))
end

function M.description(lines, first, block)
    local i = first - 1
    if not block then
        while not file_lines.blank(lines[i]) and not file_lines.comment(lines[i]) do i = i - 1 end
    end
    local out = {}
    while file_lines.comment(lines[i]) do
        table.insert(out, 1, comment_text(lines[i]))
        i = i - 1
    end
    return out
end

function M.descriptions(presets, ext, block)
    local files = {}
    local out   = {}
    for _, p in ipairs(presets) do
        if p.file and p.line then
            if files[p.file] == nil then files[p.file] = file_lines.read(M.path(p.file, ext)) or false end
            out[p] = files[p.file] and lang.pick(M.description(files[p.file], p.line, block)) or {}
        end
    end
    return out
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
