local mp           = require 'mp'
local common       = require 'src.common'
local file_lines   = require 'src.file_lines'
local preset_files = require 'src.preset_files'
local list_search  = require 'src.list_search'
local state        = require 'src.state'
local notify       = require 'src.notify'
local theme        = require 'src.theme'
local lang         = require 'src.lang'
local ui           = require 'src.ui'

local M = {}

local UNDO_TIME = 5

local bindings = { "up", "down", "j", "k", "tab", "d", "u", "search", "esc" }
for i = 1, 10 do bindings[#bindings + 1] = tostring(i) end

function M.show(opts)
    local kind   = opts.kind
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local cursor = 1
    local rows   = {}
    local descs  = {}
    local width  = 0
    local undo   = nil
    local timer  = nil
    local search

    local function file_name(file)
        return file .. "." .. kind.ext
    end

    local function path_of(file)
        return preset_files.path(file, kind.ext)
    end

    local function label(p)
        return kind.label and kind.label(p) or p.name
    end

    local function full_name(p)
        return p.file .. "/" .. label(p)
    end

    local function rebuild()
        rows       = {}
        width      = 0
        descs      = preset_files.descriptions(kind.all(), kind.ext, kind.block)
        local file = nil
        for _, p in ipairs(kind.all()) do
            if p.file ~= file then
                file            = p.file
                rows[#rows + 1] = { kind = "header", file = file }
            end
            rows[#rows + 1] = { kind = "preset", preset = p }
            width           = math.max(width, common.text_len(label(p)))
        end
        if cursor > #rows then cursor = #rows end
        if rows[cursor] and rows[cursor].kind == "header" then
            cursor = rows[cursor + 1] and rows[cursor + 1].kind == "preset" and cursor + 1 or cursor - 1
        end
        if cursor < 1 then cursor = 1 end
    end

    local function labels()
        local out = {}
        for i, row in ipairs(rows) do out[i] = row.kind == "preset" and full_name(row.preset) or "" end
        return out
    end

    local function visible()
        local names = labels()
        local keep  = {}
        for i, row in ipairs(rows) do
            if row.kind == "preset" and search.keep(names[i]) then
                keep[i] = true
                for h = i - 1, 1, -1 do
                    if rows[h].kind == "header" then
                        keep[h] = true
                        break
                    end
                end
            end
        end
        return ui.visible(#rows, function(i) return keep[i] end)
    end

    local function navigable(vis)
        local out = {}
        for _, i in ipairs(vis) do
            if rows[i].kind == "preset" then out[#out + 1] = i end
        end
        return out
    end

    local function draw()
        local vis    = visible()
        local nav    = navigable(vis)
        local toggle = math.max(common.text_len(state.opts.on_text), common.text_len(state.opts.off_text))
        if #nav > 0 and ui.position(nav, cursor) == 0 then cursor = nav[1] end
        local body = ui.list(#vis, ui.position(vis, cursor), function(k)
            local row = rows[vis[k]]
            if row.kind == "header" then
                return string.format("%s%s", theme.c("dim_text_color"), theme.escape(row.file))
            end
            local p      = row.preset
            local name   = label(p)
            local text   = p.disabled and state.opts.off_text or state.opts.on_text
            local value  = string.format("%s%s%s", theme.c(p.disabled and "off_color" or "on_color"), text, string.rep("\\h", toggle - common.text_len(text)))
            local detail = kind.detail and string.format("\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(kind.detail(p))) or ""
            local pad    = string.rep("\\h", width - common.text_len(name))
            return string.format("%s%s%s\\h\\h%s%s", ui.number_prefix(ui.position(nav, vis[k])), theme.escape(name), pad, value, detail)
        end)
        if #vis == 0 then body = search.filtering() and search.empty() or ui.dim(lang.t("presets_none")) end
        local hints = { { "Up/Down", "navigate" }, { "Tab/0-9", "toggle" }, { "d", "delete" } }
        if undo then hints[#hints + 1] = { "u", "undo" } end
        hints[#hints + 1] = { "/", "search" }
        hints[#hints + 1] = { "Esc", "back" }
        local row = #nav > 0 and rows[cursor]
        if row and row.kind == "preset" then body = body .. ui.dim_lines(descs[row.preset]) end
        ov.data = search.title(opts.title) .. "\\N" .. body .. "\\N" .. ui.tooltip(search.hints(hints))
        ov:update()
    end

    local function reload()
        kind.reload()
        rebuild()
        draw()
    end

    local function read_preset(p)
        local path, name, off = path_of(p.file), nil, nil
        local lines, eol      = file_lines.read(path)
        if lines and lines[p.line] then name, off = preset_files.definition(lines[p.line], kind.block) end
        local closed = not kind.block or (lines and lines[p.last] and preset_files.strip(lines[p.last]) == "end")
        if name ~= p.name:lower() or off ~= (p.disabled == true) or not closed then
            notify.show(lang.t("presets_changed", { file = file_name(p.file) }), true, "warn")
            reload()
            return nil
        end
        return path, lines, eol
    end

    local function write(path, p, lines, eol)
        if file_lines.write(path, lines, eol) then return true end
        notify.show(lang.t("presets_write_failed", { file = file_name(p.file) }), true, "error")
        return false
    end

    local function toggle_preset(p)
        local path, lines, eol = read_preset(p)
        if not path then return end
        if p.disabled then
            lines[p.line] = lines[p.line]:gsub("^(%s*)disabled%s+", "%1", 1)
        else
            lines[p.line] = lines[p.line]:gsub("^(%s*)", "%1disabled ", 1)
        end
        if not write(path, p, lines, eol) then return end
        notify.show(lang.t(p.disabled and "presets_enabled" or "presets_disabled", { name = full_name(p) }))
        reload()
    end

    local function file_empty(file)
        for _, p in ipairs(kind.all()) do
            if p.file == file then return false end
        end
        return true
    end

    local function forget_undo()
        if timer then timer:kill() end
        timer = nil
        undo  = nil
    end

    local function delete_preset(p)
        local path, lines, eol = read_preset(p)
        if not path then return end
        local before = {}
        for i, line in ipairs(lines) do before[i] = line end
        local top, last = preset_files.span(lines, p.line, kind.block and p.last or p.line)
        for i = last, top, -1 do table.remove(lines, i) end
        if not write(path, p, lines, eol) then return end
        kind.reload()
        local after = lines
        if file_empty(p.file) then
            os.remove(path)
            after = nil
        end
        forget_undo()
        undo  = { path = path, before = before, after = after, eol = eol, name = full_name(p), file = p.file }
        timer = mp.add_timeout(UNDO_TIME, function()
            timer = nil
            undo  = nil
            if active then draw() end
        end)
        notify.show(lang.t(after and "presets_deleted" or "presets_deleted_file", { name = undo.name, file = file_name(p.file) }), true)
        reload()
    end

    local function undo_delete()
        if not undo then return end
        local entry = undo
        forget_undo()
        if not file_lines.same(file_lines.read(entry.path), entry.after) then
            notify.show(lang.t("presets_undo_changed", { file = file_name(entry.file) }), true, "warn")
            return draw()
        end
        if not file_lines.write(entry.path, entry.before, entry.eol) then
            notify.show(lang.t("presets_write_failed", { file = file_name(entry.file) }), true, "error")
            return draw()
        end
        notify.show(lang.t("presets_restored", { name = entry.name }), true)
        reload()
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        forget_undo()
        search.close()
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding("presets-" .. name) end
    end

    local function cleanup()
        if not active then return end
        teardown()
        if opts.on_close then opts.on_close() end
    end

    local function move(delta)
        cursor = ui.step(navigable(visible()), cursor, delta)
        draw()
    end

    local function selected()
        local row = rows[cursor]
        if row and row.kind == "preset" and #navigable(visible()) > 0 then return row.preset end
        return nil
    end

    search = list_search.new({
        prefix = "presets",
        labels = labels,
        redraw = draw,
        move   = move,
        pick   = function(i)
            cursor = i
            toggle_preset(rows[i].preset)
        end
    })

    local function bind()
        local function move_up() move(-1) end
        local function move_down() move(1) end

        mp.add_forced_key_binding("UP", "presets-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "presets-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("j", "presets-j", move_down, {repeatable = true})
        mp.add_forced_key_binding("k", "presets-k", move_up, {repeatable = true})
        mp.add_forced_key_binding("TAB", "presets-tab", function()
            local p = selected()
            if p then toggle_preset(p) end
        end)
        for n = 1, 10 do
            mp.add_forced_key_binding(ui.number_key(n), "presets-" .. n, function()
                local i = navigable(visible())[n]
                if not i then return end
                cursor = i
                toggle_preset(rows[i].preset)
            end)
        end
        mp.add_forced_key_binding("d", "presets-d", function()
            local p = selected()
            if p then delete_preset(p) end
        end)
        mp.add_forced_key_binding("u", "presets-u", undo_delete)
        mp.add_forced_key_binding("/", "presets-search", search.start)
        mp.add_forced_key_binding("ESC", "presets-esc", function()
            if search.filtering() then return search.clear() end
            cleanup()
        end)
    end

    ui.clear_osd()
    rebuild()
    active         = true
    state.ui_owner = "presets"
    bind()
    draw()
end

return M
