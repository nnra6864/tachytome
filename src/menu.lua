local mp      = require 'mp'
local common  = require 'src.common'
local state   = require 'src.state'
local actions = require 'src.actions'
local menus   = require 'src.menus'
local notify  = require 'src.notify'
local render  = require 'src.render'
local theme   = require 'src.theme'
local easing  = require 'src.easing'
local lang    = require 'src.lang'
local ui      = require 'src.ui'

local M             = {}
local menu_active   = false
local menu_overlay  = mp.create_osd_overlay("ass-events")
local root_level    = { rows = {}, map = {} }
local path          = {}
local active_rows   = {}
local active_map    = {}
local active_prefix = ""
local resume_row    = nil
local bound_names   = {}
local esc_back      = false
local flashes       = {}
local flash_timer   = nil
local pending_row   = nil
local flash_frame   = 0.003
local load_menu
local reload

local function resolve_easing(val, name)
    local fn = easing.parse(val)
    if not fn then
        fn = easing.parse("linear")
        notify.show(lang.t("warn_unknown_easing", { where = name, value = tostring(val) }), false, "warn")
    end
    return fn
end

local function resolve_duration(val, fallback)
    local n = tonumber(val)
    if n == nil or n < 0 then return fallback end
    return n
end

local flash_spec = {}
local start_spec = {}

local function load_specs()
    flash_spec = {
        in_d  = state.opts.flash_in_duration,
        in_e  = resolve_easing(state.opts.flash_in_easing, "flash_in_easing"),
        out_d = state.opts.flash_out_duration,
        out_e = resolve_easing(state.opts.flash_out_easing, "flash_out_easing")
    }

    start_spec = {
        in_d  = resolve_duration(state.opts.start_in_duration, flash_spec.in_d),
        in_e  = state.opts.start_in_easing ~= "" and resolve_easing(state.opts.start_in_easing, "start_in_easing") or flash_spec.in_e,
        out_d = resolve_duration(state.opts.start_out_duration, flash_spec.out_d),
        out_e = state.opts.start_out_easing ~= "" and resolve_easing(state.opts.start_out_easing, "start_out_easing") or flash_spec.out_e
    }

    flash_spec.total = flash_spec.in_d + flash_spec.out_d
    start_spec.total = start_spec.in_d + start_spec.out_d
end

load_specs()

local function v(val) return string.format("%s%s%s", theme.c("value_color"), tostring(val), theme.reset()) end

local function toggle(val)
    if val then return string.format("%s%s%s", theme.c("on_color"), state.opts.on_text, theme.reset()) end
    return string.format("%s%s%s", theme.c("off_color"), state.opts.off_text, theme.reset())
end

local items = {
    {
        name      = "mark_in",
        label_key = "menu_mark_in",
        get_val   = function() return v(actions.get_mark_in_display()) end,
        action    = function() actions.mark(0) end,
        keep_open = true
    },
    {
        name      = "mark_out",
        label_key = "menu_mark_out",
        get_val   = function() return v(actions.get_mark_out_display()) end,
        action    = function() actions.mark(1) end,
        keep_open = true
    },
    {
        name      = "goto",
        label_key = "menu_goto",
        action    = function() actions.goto_prompt(M.open) end,
        keep_open = false
    },
    {
        name      = "set_mark_in",
        label_key = "menu_set_mark_in",
        action    = function() actions.set_mark(0, M.open) end,
        keep_open = false
    },
    {
        name      = "set_mark_out",
        label_key = "menu_set_mark_out",
        action    = function() actions.set_mark(1, M.open) end,
        keep_open = false
    },
    {
        name      = "encoder",
        label_key = "menu_encoder",
        get_val   = function() return v(state.opts.video_encoder) end,
        action    = function() actions.select_encoder(M.open) end,
        keep_open = false
    },
    {
        name      = "quality",
        label_key = "menu_quality",
        get_val   = function() return v(state.opts.quality) end,
        action    = function() actions.set_quality(M.open) end,
        keep_open = false
    },
    {
        name      = "fps",
        label_key = "menu_fps",
        get_val   = function() return v(actions.get_fps_display()) end,
        action    = function() actions.set_fps(M.open) end,
        keep_open = false
    },
    {
        name      = "keyframes",
        label_key = "menu_keyframes",
        get_val   = function() return v(actions.get_keyframes_display()) end,
        action    = function() actions.set_keyframes(M.open) end,
        keep_open = false
    },
    {
        name      = "preset",
        label_key = "menu_preset",
        get_val   = function() return v(state.opts.preset) end,
        action    = function() actions.set_preset(M.open) end,
        keep_open = false
    },
    {
        name      = "lossless_cut",
        label_key = "menu_lossless_cut",
        get_val   = function() return toggle(state.opts.lossless_cut) end,
        action    = actions.toggle_lossless,
        keep_open = true
    },
    {
        name      = "accurate_cut",
        label_key = "menu_accurate_cut",
        get_val   = function() return toggle(state.opts.accurate_cut) end,
        action    = actions.toggle_accurate,
        keep_open = true
    },
    {
        name      = "combine_audio",
        label_key = "menu_combine_audio",
        get_val   = function() return toggle(state.opts.combine_audio) end,
        action    = actions.toggle_combine_audio,
        keep_open = true
    },
    {
        name      = "first_audio_only",
        label_key = "menu_first_audio_only",
        get_val   = function() return toggle(state.opts.first_audio_only) end,
        action    = actions.toggle_first_audio_only,
        keep_open = true
    },
    {
        name      = "effects",
        label_key = "menu_effects",
        get_val   = function()
            local list = actions.get_effects_display()
            if list == "" then return toggle(state.effects_enabled) end
            return toggle(state.effects_enabled) .. " " .. v(theme.escape(list))
        end,
        action    = function() actions.effects_menu(M.open) end,
        keep_open = false
    },
    {
        name      = "space_replacement",
        label_key = "menu_space_replacement",
        get_val   = function() return v(theme.escape(actions.get_space_replacement_display())) end,
        action    = function() actions.set_space_replacement(M.open) end,
        keep_open = false
    },
    {
        name      = "path",
        label_key = "menu_path",
        get_val   = function() return v(theme.escape(actions.get_final_path_display())) end,
        action    = function() actions.set_path(M.open) end,
        keep_open = false
    },
    {
        name      = "trash_source",
        label_key = "menu_trash_source",
        get_val   = function() return toggle(state.opts.trash_source) end,
        action    = actions.toggle_trash_source,
        keep_open = true
    },
    {
        name      = "render",
        label_key = "menu_render",
        action    = function() actions.start_render(M.open) end,
        keep_open = false
    },
    {
        name      = "render_queue",
        label_key = "menu_render_queue",
        action    = function() actions.manage_queue(M.open) end,
        keep_open = false
    },
    {
        name      = "render_pause",
        label_key = "menu_render_pause",
        get_val   = function() return toggle(render.is_paused()) end,
        action    = function() actions.toggle_render_pause() end,
        keep_open = true
    },
    {
        name      = "trash_source_now",
        label_key = "menu_trash_source_now",
        action    = function() actions.trash_source(M.open) end,
        keep_open = false
    },
    {
        name      = "stats",
        label_key = "menu_stats",
        get_val   = function() return toggle(actions.stats_visible) end,
        action    = actions.toggle_stats,
        keep_open = true
    },
    {
        name      = "menu_preset",
        label_key = "menu_menu_preset",
        get_val   = function() return v(theme.escape(state.opts.selected_menu)) end,
        action    = function() actions.select_menu(load_menu, M.open) end,
        keep_open = false
    },
    {
        name      = "configs",
        label_key = "menu_configs",
        get_val   = function() return v(theme.escape(actions.get_configs_display())) end,
        action    = function() actions.select_configs(reload, M.open) end,
        keep_open = false
    },
    {
        name      = "language",
        label_key = "menu_language",
        get_val   = function()
            local val = state.opts.language
            if val == "auto" then val = val .. " (" .. lang.code .. ")" end
            return v(theme.escape(val))
        end,
        action    = function() actions.select_language(M.open) end,
        keep_open = false
    },
    {
        name      = "update",
        label_key = "menu_update",
        action    = function() actions.update(M.open) end,
        keep_open = false
    },
    {
        name      = "close",
        label_key = "menu_close",
        action    = function() end,
        keep_open = false
    }
}

local items_by_name = {}
for _, item in ipairs(items) do items_by_name[item.name] = item end

local function row_label(row)
    if row.label then
        if row.label.key and lang.has(row.label.key) then return lang.t(row.label.key) end
        if row.label.text ~= "" then return row.label.text end
    end
    if row.item then return lang.t(row.item.label_key) end
    if lang.has("submenu_" .. row.action) then return lang.t("submenu_" .. row.action) end
    return (row.action:gsub("_", " "):gsub("^%l", string.upper))
end

local function prune_shadowed(map)
    local shadowed = {}
    for seq in pairs(map) do
        local prefix = seq:match("^(.*)-[^-]*$")
        while prefix do
            if map[prefix] then
                shadowed[#shadowed + 1] = seq
                break
            end
            prefix = prefix:match("^(.*)-[^-]*$")
        end
    end
    for _, seq in ipairs(shadowed) do
        notify.show(lang.t("warn_unreachable_seq", { seq = seq, prefix = seq:match("^(.*)-[^-]*$") }), false, "warn")
        local row = map[seq]
        for i = #row.keys, 1, -1 do
            if row.keys[i] == seq then table.remove(row.keys, i) end
        end
        map[seq] = nil
    end
end

local function build_level(tree)
    local rows = {}
    local map  = {}
    for _, row in ipairs(tree) do
        if row.separator then
            rows[#rows + 1] = row
        else
            local known = true
            if row.rows then
                row.level = build_level(row.rows)
                known     = #row.level.rows > 0
            elseif items_by_name[row.action] then
                row.item = items_by_name[row.action]
            else
                known = false
                notify.show(lang.t("warn_unknown_action", { action = row.action, keys = table.concat(row.keys, ",") }), false, "warn")
            end
            if known then
                rows[#rows + 1] = row
                for _, seq in ipairs(row.keys) do map[seq] = row end
            end
        end
    end
    prune_shadowed(map)

    local level   = { rows = {}, map = map }
    local sep     = false
    local visible = 0
    for _, row in ipairs(rows) do
        if row.separator then
            sep = visible > 0
        elseif #row.keys > 0 and row.hidden then
            level.rows[#level.rows + 1] = row
        elseif #row.keys > 0 then
            visible = visible + 1
            if sep then level.rows[#level.rows + 1] = { separator = true } end
            sep = false
            level.rows[#level.rows + 1] = row
        end
    end
    return level
end

local function find_path(level, action, trail)
    for _, row in ipairs(level.rows) do
        if row.item and row.action == action then return row, trail end
        if row.level then
            trail[#trail + 1] = row
            local found = find_path(row.level, action, trail)
            if found then return found, trail end
            trail[#trail] = nil
        end
    end
    return nil, nil
end

local function sync_level()
    local level   = #path > 0 and path[#path].level or root_level
    active_rows   = level.rows
    active_map    = level.map
    active_prefix = ""
end

load_menu = function()
    root_level = build_level(menus.active())
    path       = {}
    if resume_row then
        local found, trail = find_path(root_level, resume_row.action, {})
        if pending_row then pending_row = found end
        resume_row = found
        path       = trail or {}
    end
    sync_level()
end

reload = function()
    menus.load()
    load_specs()
    load_menu()
end

load_menu()

local function seq_matches(seq)
    if active_prefix == "" then return false end
    if seq:sub(1, #active_prefix) ~= active_prefix then return false end
    return seq:sub(#active_prefix + 1, #active_prefix + 1) == "-"
end

local function render_seq(seq, base)
    if not seq_matches(seq) then
        return base .. seq
    end
    return theme.c("flash_color") .. active_prefix .. base .. seq:sub(#active_prefix + 1)
end

local function flash_progress(fl)
    local t    = mp.get_time() - fl.at
    local spec = fl.spec
    if t <= 0 then return 0 end
    if t < spec.in_d then return spec.in_e(t / spec.in_d) end
    if spec.out_d <= 0 then return 0 end
    local u = (t - spec.in_d) / spec.out_d
    if u >= 1 then return 0 end
    return 1 - spec.out_e(u)
end

local function draw()
    local title = " < " .. theme.escape(lang.t("menu_title"))
    for _, row in ipairs(path) do
        title = title .. " " .. theme.escape(state.opts.menu_path_separator) .. " " .. theme.escape(row_label(row))
    end
    local text = string.format("%s%s%s%s%s > %s\\N\\N", theme.align(7), theme.f(), theme.b(true), theme.c("text_color"), title, theme.b(false))
    local max_key_len   = 0
    local max_label_len = 0

    for _, row in ipairs(active_rows) do
        if not row.separator and not row.hidden and #row.keys > 0 then
            local key_str = table.concat(row.keys, ",")
            local label   = row_label(row)
            if #key_str > max_key_len then max_key_len = #key_str end
            if row.item and row.item.get_val and common.text_len(label) > max_label_len then max_label_len = common.text_len(label) end
        end
    end

    for _, row in ipairs(active_rows) do
        if row.separator then
            text = text .. "\\N"
        elseif #row.keys > 0 and not row.hidden then
            local label   = row_label(row)
            local key_str = table.concat(row.keys, ",")
            local key_pad = string.rep("\\h", max_key_len - #key_str)
            local base    = theme.c("text_color")
            local fl      = flashes[row]
            if fl then
                local p = flash_progress(fl)
                if p > 0 then base = theme.mix(state.opts.text_color, state.opts.flash_color, p) end
            end
            local key_txt = nil
            local matched = false
            for _, seq in ipairs(row.keys) do
                key_txt = key_txt and key_txt .. base .. "," .. render_seq(seq, base) or render_seq(seq, base)
                if seq_matches(seq) then matched = true end
            end

            local line = string.format("%s%s%s -> %s", key_pad, key_txt, base, theme.escape(label))
            local dim  = active_prefix ~= "" and not matched

            if dim then line = theme.a("66") .. line end

            if row.item and row.item.get_val then
                local val_pad = string.rep("\\h", max_label_len - common.text_len(label) + 1)
                line = line .. val_pad .. "> " .. row.item.get_val()
            end

            if dim then line = line .. theme.a("00") end

            text = text .. line .. "\\N"
        end
    end

    if esc_back then
        text = text .. ui.tooltip({ { "Esc", "back" } })
    end

    menu_overlay.data = text
    menu_overlay:update()
end

local function stop_flash()
    flashes = {}
    if flash_timer then
        flash_timer:kill()
        flash_timer = nil
    end
end

local function flash_tick()
    local now = mp.get_time()
    for row, fl in pairs(flashes) do
        if now >= fl.at + fl.spec.total then flashes[row] = nil end
    end
    if not next(flashes) and flash_timer then
        flash_timer:kill()
        flash_timer = nil
    end
    if menu_active then draw() end
end

local function start_flash(row, delay, spec)
    if spec.total <= 0 then return end
    flashes[row] = { at = mp.get_time() + (delay or 0), spec = spec }
    if not flash_timer then
        flash_timer = mp.add_periodic_timer(flash_frame, flash_tick)
    end
end

local function start_cascade()
    if start_spec.total <= 0 then return end
    local stagger = math.max(0, state.opts.start_stagger)
    local i = 0
    for _, row in ipairs(active_rows) do
        if not row.separator and not row.hidden and #row.keys > 0 then
            start_flash(row, i * stagger, start_spec)
            i = i + 1
        end
    end
end

local function level_keys(prefix)
    local keys = {}
    for seq in pairs(active_map) do
        local rest = nil
        if prefix == "" then
            rest = seq
        elseif seq:sub(1, #prefix + 1) == prefix .. "-" then
            rest = seq:sub(#prefix + 2)
        end
        if rest then
            local part = rest:match("^[^-]*")
            if part ~= "" then keys[part] = true end
        end
    end
    return keys
end

local bind_level
local fire

local function handle_key(key)
    local seq = active_prefix == "" and key or active_prefix .. "-" .. key
    local row = active_map[seq]
    if row then
        fire(row)
    else
        active_prefix = seq
        bind_level()
        draw()
    end
end

local function cancel_prefix()
    active_prefix = ""
    bind_level()
    draw()
end

local function go_back()
    if active_prefix ~= "" then
        active_prefix = active_prefix:match("^(.*)-[^-]*$") or ""
    elseif #path > 0 then
        table.remove(path)
        sync_level()
    else
        return
    end
    bind_level()
    draw()
end

local function unbind_all()
    for _, name in ipairs(bound_names) do mp.remove_key_binding(name) end
    bound_names = {}
end

local function bind_key(key, name, fn)
    mp.add_forced_key_binding(key, name, fn)
    bound_names[#bound_names + 1] = name
end

fire = function(row)
    if row.level then
        path[#path + 1] = row
        sync_level()
        bind_level()
        draw()
        return
    end
    local item = row.item
    if not item then return end
    if not item.keep_open then
        M.close()
        resume_row = row
    end
    if flash_spec.total > 0 then pending_row = row end
    item.action()
    if menu_active then
        pending_row   = nil
        resume_row    = nil
        active_prefix = ""
        bind_level()
        start_flash(row, nil, flash_spec)
        draw()
    elseif not state.ui_owner then
        pending_row = nil
        resume_row  = nil
    end
end

bind_level = function()
    unbind_all()
    esc_back = false
    local continuations = level_keys(active_prefix)
    for key in pairs(continuations) do
        bind_key(key, "menu-" .. key, function() handle_key(key) end)
    end
    if (active_prefix ~= "" or #path > 0) and not continuations["ESC"] then
        bind_key("ESC", "menu-back", go_back)
        esc_back = true
    end
    if active_prefix ~= "" then
        for key in pairs(level_keys("")) do
            if not continuations[key] and key ~= "ESC" then
                bind_key(key, "menu-root-" .. key, cancel_prefix)
            end
        end
    end
end

function M.close()
    if not menu_active then return end
    menu_active    = false
    state.ui_owner = nil
    active_prefix  = ""
    stop_flash()
    menu_overlay:remove()
    unbind_all()
end

function M.open()
    if state.ui_owner and state.ui_owner ~= "menu" then
        return notify.show(lang.t("menu_busy"))
    end
    if menu_active then M.close() return end
    menu_active    = true
    state.ui_owner = "menu"
    if not resume_row then path = {} end
    resume_row     = nil
    sync_level()
    ui.clear_osd()
    bind_level()
    if pending_row then
        start_flash(pending_row, nil, flash_spec)
        pending_row = nil
    else
        start_cascade()
    end
    draw()
end

function M.refresh()
    if menu_active then draw() end
end

return M
