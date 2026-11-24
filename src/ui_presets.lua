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
local ui_choice    = require 'src.ui_choice'

local M = {}

local UNDO_TIME = 5

local bindings = { "up", "down", "j", "k", "tab", "d", "u", "reset", "search", "esc" }
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
        end, ui.tip_lines(descs))
        if #vis == 0 then body = search.filtering() and search.empty() or ui.dim(lang.t("presets_none")) end
        local row   = #nav > 0 and rows[cursor]
        local hints = { { "Up/Down", "navigate" }, { "Tab/0-9", "toggle" } }
        if not (row and row.kind == "preset" and row.preset.file == preset_files.builtin) then hints[#hints + 1] = { "d", "delete" } end
        if undo then hints[#hints + 1] = { "u", "undo" } end
        hints[#hints + 1] = { "R", "reset" }
        hints[#hints + 1] = { "/", "search" }
        hints[#hints + 1] = { "Esc", "back" }
        if row and row.kind == "preset" then body = body .. ui.tips(descs[row.preset]) end
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
        if p.file == preset_files.builtin then
            local ok, failed = preset_files.set_state(p, kind.ext, p.disabled)
            if not ok then return notify.show(lang.t("presets_write_failed", { file = failed }), true, "error") end
            notify.show(lang.t(p.disabled and "presets_enabled" or "presets_disabled", { name = full_name(p) }))
            return reload()
        end
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

    local function remember(files, done)
        forget_undo()
        undo  = { files = files, done = done }
        timer = mp.add_timeout(UNDO_TIME, function()
            timer = nil
            undo  = nil
            if active then draw() end
        end)
    end

    local function delete_preset(p)
        if p.file == preset_files.builtin then
            notify.show(lang.t("presets_builtin", { name = full_name(p) }), true, "warn")
            return draw()
        end
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
        remember({ { path = path, file = p.file, before = before, after = after, eol = eol } }, lang.t("presets_restored", { name = full_name(p) }))
        notify.show(lang.t(after and "presets_deleted" or "presets_deleted_file", { name = full_name(p), file = file_name(p.file) }), true)
        reload()
    end

    local function undo_delete()
        if not undo then return end
        local entry = undo
        forget_undo()
        for _, f in ipairs(entry.files) do
            if not file_lines.same(file_lines.read(f.path), f.after) then
                notify.show(lang.t("presets_undo_changed", { file = file_name(f.file) }), true, "warn")
                return draw()
            end
        end
        for _, f in ipairs(entry.files) do
            if not file_lines.write(f.path, f.before, f.eol) then
                notify.show(lang.t("presets_write_failed", { file = file_name(f.file) }), true, "error")
                return reload()
            end
        end
        notify.show(entry.done, true)
        reload()
    end

    local bind

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

    local function resume()
        active         = true
        state.ui_owner = "presets"
        bind()
        reload()
    end

    local function remove_files(files)
        local entries = {}
        local names   = {}
        for _, file in ipairs(files) do
            local path       = path_of(file)
            local lines, eol = file_lines.read(path)
            os.remove(path)
            entries[#entries + 1] = { path = path, file = file, before = lines or {}, eol = eol }
            names[#names + 1]     = file_name(file)
        end
        resume()
        remember(entries, lang.t("presets_reset_undone"))
        notify.show(lang.t("presets_reset_done", { list = table.concat(names, ", ") }), true)
        draw()
    end

    local function reset_lines(files)
        local lines = {}
        local back  = { on = {}, off = {} }
        for _, file in ipairs(files) do
            lines[#lines + 1] = file_name(file) .. ":"
            for _, p in ipairs(kind.all()) do
                if p.file == file then lines[#lines + 1] = "  " .. label(p) end
            end
        end
        for _, p in ipairs(kind.all()) do
            if p.file == preset_files.builtin and not p.disabled ~= not p.builtin_disabled then
                local list = p.builtin_disabled and back.off or back.on
                list[#list + 1] = "  " .. full_name(p)
            end
        end
        for _, side in ipairs({ "on", "off" }) do
            if #back[side] > 0 then lines[#lines + 1] = lang.t("presets_reset_" .. side) end
            for _, line in ipairs(back[side]) do lines[#lines + 1] = line end
        end
        return lines
    end

    local function reset()
        local files    = preset_files.list(kind.ext)
        local has_user = false
        for _, file in ipairs(files) do
            if file == preset_files.user then has_user = true end
        end
        if #files == 0 then
            notify.show(lang.t("presets_reset_none"), true)
            return draw()
        end
        local choices = {}
        local actions = {}
        if has_user then
            choices[#choices + 1] = { label = lang.t("presets_reset_user", { file = file_name(preset_files.user) }) }
            actions[#choices]     = function() remove_files({ preset_files.user }) end
        end
        if #files > (has_user and 1 or 0) then
            choices[#choices + 1] = { label = lang.t("presets_reset_all", { ext = kind.ext }) }
            actions[#choices]     = function() remove_files(files) end
        end
        choices[#choices + 1] = { label = lang.t("choice_cancel") }
        for i, choice in ipairs(choices) do choice.key = tostring(i) end
        choices[1].alt = "ENTER"
        local lines = reset_lines(files)
        teardown()
        ui_choice.show(lang.t("presets_reset"), "", choices, #choices, function(idx)
            if actions[idx] then return actions[idx]() end
            resume()
        end, lines)
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

    bind = function()
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
        mp.add_forced_key_binding("R", "presets-reset", reset)
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
