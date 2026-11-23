local mp          = require 'mp'
local common      = require 'src.common'
local conf        = require 'src.conf'
local file_lines  = require 'src.file_lines'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local notify      = require 'src.notify'
local ui          = require 'src.ui'
local ui_input    = require 'src.ui_input'
local ui_confirm  = require 'src.ui_confirm'
local ui_choice   = require 'src.ui_choice'

local M = {}

local UNDO_TIME = 5

local bindings = { "cfg-up", "cfg-down", "cfg-j", "cfg-k", "cfg-move-up", "cfg-move-down", "cfg-K", "cfg-J", "cfg-tab", "cfg-enter", "cfg-new", "cfg-rename", "cfg-delete", "cfg-reset", "cfg-undo", "cfg-search", "cfg-esc" }

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

local function options_of(name)
    local vals = conf.file_options(name)
    local out  = {}
    for _, key in ipairs(conf.keys()) do
        if vals[key] then out[#out + 1] = string.format("%s %s", key, vals[key] == "" and "\"\"" or vals[key]) end
    end
    return out
end

local function copy_rows(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = { name = row.name, enabled = row.enabled, exists = row.exists, pinned = row.pinned } end
    return out
end

function M.show(configs, on_apply, on_close, on_edit)
    local rows    = { { name = "user", enabled = true, exists = true, pinned = true } }
    local changed = false
    local undo    = nil
    local timer   = nil
    local refresh = nil
    for _, c in ipairs(configs) do rows[#rows + 1] = { name = c.name, enabled = c.enabled, exists = c.exists } end

    local function forget_undo()
        if timer then timer:kill() end
        timer = nil
        undo  = nil
    end

    local function taken(name, except)
        local low = name:lower()
        for _, row in ipairs(rows) do
            if row.name:lower() == low and row ~= except then return true end
        end
        return false
    end

    local function name_error(name, except)
        local err = conf.config_name_error(name)
        if err then return lang.t(err, { name = name }) end
        if taken(name, except) then return lang.t("configs_exists", { name = name }) end
        return nil
    end

    local open

    local function ask_name(title, current, except, on_name, back)
        ui_input.show({
            title     = title,
            current   = current,
            hint      = lang.t("configs_hint_name"),
            preview   = function(input) return trim(input) ~= "" and name_error(trim(input), except) or "" end,
            on_cancel = back,
            on_submit = function(input)
                local name = trim(input):gsub("%.conf$", "")
                local err  = name_error(name, except)
                if name == "" or err then
                    if err then notify.show(err, true, "warn") end
                    return ask_name(title, current, except, on_name, back)
                end
                on_name(name)
            end
        })
    end

    open = function(cursor)
        local ov     = mp.create_osd_overlay("ass-events")
        local active = true
        local search

        ui.clear_osd()
        state.ui_owner = "configs"

        local function teardown()
            active         = false
            refresh        = nil
            state.ui_owner = nil
            search.close()
            ov:remove()
            for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
        end

        local function list()
            local out = {}
            for i = 2, #rows do out[#out + 1] = rows[i] end
            return out
        end

        local function close()
            if not active then return end
            teardown()
            forget_undo()
            if not changed then
                if on_close then on_close() end
                return
            end
            if on_apply then on_apply(list()) end
        end

        local function labels()
            local out = {}
            for i, row in ipairs(rows) do out[i] = row.name end
            return out
        end

        local function visible()
            return ui.visible(#rows, function(i) return search.keep(rows[i].name) end)
        end

        local function draw()
            local vis = visible()
            if #vis > 0 and ui.position(vis, cursor) == 0 then cursor = vis[1] end
            local body = ui.list(#vis, ui.position(vis, cursor), function(k)
                local row     = rows[vis[k]]
                local val     = row.pinned and string.format("%s%s", theme.c("dim_text_color"), theme.escape(lang.t("configs_always")))
                    or row.enabled and string.format("%s%s", theme.c("on_color"), state.opts.on_text)
                    or string.format("%s%s", theme.c("off_color"), state.opts.off_text)
                local missing = row.exists and "" or string.format(" %s%s", theme.c("warning_color"), theme.escape(lang.t("configs_missing")))
                return string.format("%s %s%s", theme.escape(row.name), val, missing)
            end)
            if #vis == 0 then body = search.empty() end

            local hints = { { "Up/Down", "navigate" }, { "Tab", "toggle" }, { "Enter", "edit" }, { "Shift+Up/Down", "move" }, { "n", "new" }, { "r", "rename" }, { "d", "delete" }, { "R", "reset" } }
            if undo then hints[#hints + 1] = { "u", "undo" } end
            hints[#hints + 1] = { "/", "search" }
            hints[#hints + 1] = { "Esc", "close" }
            hints = search.hints(hints)
            ov.data = search.title(lang.t("menu_config_manager")) .. "\\N" .. body .. "\\N" .. ui.dim(lang.t("configs_dir", { dir = common.display_path(common.get_conf_dir()) })) .. "\\N" .. ui.tooltip(hints)
            ov:update()
        end

        refresh = draw

        local function move_cursor(delta)
            cursor = ui.step(visible(), cursor, delta)
            draw()
        end

        local function move_row(delta)
            local target = cursor + delta
            if search.filtering() or rows[cursor].pinned or target < 2 or target > #rows then return end
            rows[cursor], rows[target] = rows[target], rows[cursor]
            cursor  = target
            changed = true
            draw()
        end

        local function toggle()
            local row = rows[cursor]
            if not row or #visible() == 0 or row.pinned then return end
            row.enabled = not row.enabled
            changed     = true
            draw()
        end

        local function edit()
            local row = rows[cursor]
            if not row or #visible() == 0 or not on_edit then return end
            teardown()
            on_edit(changed and list() or nil, row)
        end

        local function pinned_warn(row)
            if not row.pinned then return false end
            notify.show(lang.t("configs_pinned", { name = row.name }), true, "warn")
            return true
        end

        local function create()
            teardown()
            ask_name(lang.t("configs_new"), nil, nil, function(name)
                if not conf.create_config(name) then
                    notify.show(lang.t("configs_write_failed", { name = name }), true, "error")
                    return open(cursor)
                end
                rows[#rows + 1] = { name = name, enabled = true, exists = true }
                changed         = true
                notify.show(lang.t("configs_created", { name = name }))
                open(#rows)
            end, function() open(cursor) end)
        end

        local function rename()
            local row = rows[cursor]
            if not row or #visible() == 0 or pinned_warn(row) then return end
            teardown()
            ask_name(lang.t("configs_rename", { name = row.name }), row.name, row, function(name)
                if row.exists and not conf.rename_config(row.name, name) then
                    notify.show(lang.t("configs_write_failed", { name = row.name }), true, "error")
                    return open(cursor)
                end
                notify.show(lang.t("configs_renamed", { from = row.name, to = name }))
                row.name = name
                changed  = true
                open(cursor)
            end, function() open(cursor) end)
        end

        local function delete()
            local row = rows[cursor]
            if not row or #visible() == 0 or pinned_warn(row) then return end
            local body = common.display_path(conf.config_path(row.name))
            if row.exists then
                local set = options_of(row.name)
                body      = body .. "\n" .. (#set > 0 and ui_choice.lines(set) or lang.t("configs_sets_none"))
            end
            teardown()
            ui_confirm.show(lang.t("configs_delete", { name = row.name }), body, function()
                if row.exists and not conf.delete_config(row.name) then
                    notify.show(lang.t("configs_write_failed", { name = row.name }), true, "error")
                    return open(cursor)
                end
                table.remove(rows, cursor)
                changed = true
                notify.show(lang.t("configs_deleted", { name = row.name }))
                open(math.min(cursor, #rows))
            end, function() open(cursor) end)
        end

        local function reset_to(keep_list)
            local files = {}
            local main  = conf.main_path()
            local lines = file_lines.read(main) or {}
            local kept  = {}
            for _, line in ipairs(lines) do
                if keep_list and line:match("^configs=") then kept[#kept + 1] = line end
            end
            files[1] = { path = main, before = lines }
            if not file_lines.write(main, kept) then
                notify.show(lang.t("configs_write_failed", { name = "user" }), true, "error")
                return open(cursor)
            end
            local before_rows = copy_rows(rows)
            if not keep_list then
                for i = #rows, 2, -1 do
                    local path = conf.config_path(rows[i].name)
                    if rows[i].exists then
                        files[#files + 1] = { path = path, before = file_lines.read(path) or {} }
                        os.remove(path)
                    end
                    table.remove(rows, i)
                end
            end
            forget_undo()
            undo    = { files = files, rows = before_rows, changed = changed }
            timer   = mp.add_timeout(UNDO_TIME, function()
                timer = nil
                undo  = nil
                if refresh then refresh() end
            end)
            changed = true
            notify.show(lang.t("configs_reset_done"), true)
            open(1)
        end

        local function reset()
            local has_own = false
            for _, line in ipairs(file_lines.read(conf.main_path()) or {}) do
                if not file_lines.blank(line) and not line:match("^configs=") then has_own = true end
            end
            local choices = {}
            local actions = {}
            if has_own then
                choices[#choices + 1] = { label = lang.t("presets_reset_user", { file = "user.conf" }) }
                actions[#choices]     = function() reset_to(true) end
            end
            if #rows > 1 then
                choices[#choices + 1] = { label = lang.t("configs_reset_all") }
                actions[#choices]     = function() reset_to(false) end
            end
            if #choices == 0 then return notify.show(lang.t("configs_reset_none"), true) end
            choices[#choices + 1] = { label = lang.t("choice_cancel") }
            for i, choice in ipairs(choices) do choice.key = tostring(i) end
            local lines = {}
            local set   = options_of("user")
            if #set > 0 then lines[#lines + 1] = "user.conf: " .. ui_choice.join(set) end
            local names = {}
            for i = 2, #rows do names[#names + 1] = rows[i].name .. ".conf" end
            if #names > 0 then lines[#lines + 1] = lang.t("configs_reset_list", { list = ui_choice.join(names) }) end
            teardown()
            ui_choice.show(lang.t("presets_reset"), table.concat(lines, "\n"), choices, #choices, function(idx)
                if actions[idx] then return actions[idx]() end
                open(cursor)
            end)
        end

        local function undo_reset()
            if not undo then return end
            local entry = undo
            forget_undo()
            for _, f in ipairs(entry.files) do
                if not file_lines.write(f.path, f.before) then
                    notify.show(lang.t("configs_write_failed", { name = f.path }), true, "error")
                    return draw()
                end
            end
            rows    = entry.rows
            changed = entry.changed
            notify.show(lang.t("presets_reset_undone"), true)
            draw()
        end

        search = list_search.new({
            prefix = "cfg",
            labels = labels,
            redraw = draw,
            move   = move_cursor,
            pick   = function(i)
                cursor = i
                toggle()
            end
        })

        mp.add_forced_key_binding("UP", "cfg-up", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "cfg-down", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "cfg-j", function() move_cursor(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "cfg-k", function() move_cursor(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+UP", "cfg-move-up", function() move_row(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+DOWN", "cfg-move-down", function() move_row(1) end, {repeatable = true})
        mp.add_forced_key_binding("K", "cfg-K", function() move_row(-1) end, {repeatable = true})
        mp.add_forced_key_binding("J", "cfg-J", function() move_row(1) end, {repeatable = true})
        mp.add_forced_key_binding("TAB", "cfg-tab", toggle)
        mp.add_forced_key_binding("ENTER", "cfg-enter", edit)
        mp.add_forced_key_binding("n", "cfg-new", create)
        mp.add_forced_key_binding("r", "cfg-rename", rename)
        mp.add_forced_key_binding("d", "cfg-delete", delete)
        mp.add_forced_key_binding("R", "cfg-reset", reset)
        mp.add_forced_key_binding("u", "cfg-undo", undo_reset)
        mp.add_forced_key_binding("/", "cfg-search", search.start)
        mp.add_forced_key_binding("ESC", "cfg-esc", function()
            if search.filtering() then return search.clear() end
            close()
        end)
        draw()
    end

    open(1)
end

return M
