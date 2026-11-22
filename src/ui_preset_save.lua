local file_lines   = require 'src.file_lines'
local preset_files = require 'src.preset_files'
local ui_input     = require 'src.ui_input'
local ui_list      = require 'src.ui_list'
local ui_confirm   = require 'src.ui_confirm'
local state        = require 'src.state'
local notify       = require 'src.notify'
local lang         = require 'src.lang'

local M = {}

local last = {}

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function comment_lines(desc)
    local out = {}
    for part in (desc .. "\n"):gmatch("(.-)\n") do
        part          = part:gsub("%s+$", "")
        out[#out + 1] = part == "" and "#" or "# " .. part
    end
    return out
end

function M.show(opts)
    local kind  = opts.kind
    local chain = trim(opts.chain or "")
    local sep   = state.opts.menu_path_separator
    local title = string.format("%s %s %s", opts.title, sep, lang.t("presets_new"))
    local name  = nil
    local file  = nil
    local ask_name
    local ask_file

    local function done()
        if opts.on_done then opts.on_done() end
    end

    if chain == "" then
        notify.show(lang.t("presets_nothing"), true, "warn")
        return done()
    end

    local function uses(token)
        for t in chain:gmatch("%S+") do
            if t:lower() == token then return true end
        end
        return false
    end

    local function find(f)
        for _, p in ipairs(kind.all()) do
            if p.file == f and p.name == name then return p end
        end
        return nil
    end

    local function name_error(input)
        local n = trim(input):lower()
        if n == "" then return nil end
        if not kind.valid_name(n) then return lang.t("presets_bad_name", { name = n }) end
        if uses(n) then return lang.t("presets_self", { name = n }) end
        return nil
    end

    local function file_error(input)
        local f = trim(input)
        if f == "" then return nil end
        if not preset_files.valid_file(f) then return lang.t("presets_bad_file", { name = f }) end
        if file_lines.read(preset_files.path(f, kind.ext)) then return lang.t("presets_file_exists", { file = f .. "." .. kind.ext }) end
        return nil
    end

    local function write(desc, existing)
        local path       = preset_files.path(file, kind.ext)
        local lines, eol = file_lines.read(path)
        local line       = name .. " = " .. chain
        lines            = lines or {}
        if existing then
            if preset_files.definition(lines[existing.line] or "", false) ~= name then
                notify.show(lang.t("presets_changed", { file = file .. "." .. kind.ext }), true, "warn")
                kind.reload()
                return done()
            end
            lines[existing.line] = line
            if desc ~= "" then
                local top = preset_files.comment_above(lines, existing.line, existing.line) or existing.line
                for i = existing.line - 1, top, -1 do table.remove(lines, i) end
                for i, c in ipairs(comment_lines(desc)) do table.insert(lines, top + i - 1, c) end
            end
        else
            if #lines > 0 and not file_lines.blank(lines[#lines]) then lines[#lines + 1] = "" end
            if desc ~= "" then
                for _, c in ipairs(comment_lines(desc)) do lines[#lines + 1] = c end
            end
            lines[#lines + 1] = line
        end
        if not file_lines.write(path, lines, eol) then
            notify.show(lang.t("presets_write_failed", { file = file .. "." .. kind.ext }), true, "error")
            return done()
        end
        last[kind.ext] = file
        kind.reload()
        notify.show(lang.t("presets_saved", { name = file .. "/" .. name }), true)
        done()
    end

    local function current_comment(existing)
        if not existing then return nil end
        local lines = file_lines.read(preset_files.path(file, kind.ext)) or {}
        if not preset_files.comment_above(lines, existing.line, existing.line) then return nil end
        return table.concat(preset_files.description(lines, existing.line, true), "\n")
    end

    local function ask_desc(existing, back)
        ui_input.show({
            title       = string.format("%s %s %s", title, sep, lang.t("presets_description")),
            current     = current_comment(existing),
            hint        = lang.t(existing and "presets_hint_keep" or "presets_hint_desc"),
            allow_space = true,
            multiline   = true,
            on_cancel   = back,
            on_submit   = function(input)
                write(trim(input), existing)
            end
        })
    end

    local function pick_file(f)
        file = f
        if uses((f .. "/" .. name):lower()) then
            notify.show(lang.t("presets_self", { name = f .. "/" .. name }), true, "warn")
            return ask_file()
        end
        local existing = find(f)
        if not existing then return ask_desc(nil, ask_file) end
        ui_confirm.show(lang.t("presets_replace", { name = f .. "/" .. name }), existing.chain, function()
            ask_desc(existing, ask_file)
        end, ask_file)
    end

    local function ask_new_file()
        ui_input.show({
            title     = string.format("%s %s %s", title, sep, lang.t("presets_new_file")),
            hint      = lang.t("presets_hint_file", { ext = kind.ext }),
            preview   = function(input) return file_error(input) or "" end,
            on_cancel = ask_file,
            on_submit = function(input)
                local f   = trim(input)
                local err = f == "" and lang.t("presets_bad_file", { name = f }) or file_error(f)
                if err then
                    notify.show(err, true, "warn")
                    return ask_new_file()
                end
                file = f
                ask_desc(nil, ask_new_file)
            end
        })
    end

    ask_file = function()
        local files = {}
        if last[kind.ext] then
            for _, f in ipairs(preset_files.list(kind.ext)) do
                if f == last[kind.ext] then files[1] = f end
            end
        end
        for _, f in ipairs(preset_files.list(kind.ext)) do
            if f ~= files[1] then files[#files + 1] = f end
        end
        local count = #files
        files[#files + 1] = lang.t("presets_new_file")

        local function detail(i)
            local p = i <= count and find(files[i])
            return p and lang.t("presets_replaces", { chain = p.chain }) or ""
        end

        ui_list.show(string.format("%s %s %s", title, sep, lang.t("presets_file")), files, nil, function(val, i)
            if i > count then return ask_new_file() end
            pick_file(val)
        end, ask_name, { detail = detail, action = "save" })
    end

    ask_name = function()
        ui_input.show({
            title     = string.format("%s %s %s", title, sep, lang.t("presets_name")),
            hint      = kind.name_hint,
            preview   = function(input) return name_error(input) or "" end,
            on_cancel = done,
            on_submit = function(input)
                local n   = trim(input):lower()
                local err = n == "" and lang.t("presets_bad_name", { name = n }) or name_error(n)
                if err then
                    notify.show(err, true, "warn")
                    return ask_name()
                end
                name = n
                ask_file()
            end
        })
    end

    ask_name()
end

return M
