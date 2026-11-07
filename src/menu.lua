local mp      = require 'mp'
local state   = require 'src.state'
local actions = require 'src.actions'
local menus   = require 'src.menus'
local notify  = require 'src.notify'
local render  = require 'src.render'
local theme   = require 'src.theme'
local easing  = require 'src.easing'

local M             = {}
local menu_active   = false
local menu_overlay  = mp.create_osd_overlay("ass-events")
local active_rows   = {}
local active_map    = {}
local active_prefix = ""
local bound_names   = {}
local esc_back      = false
local flashes       = {}
local flash_timer   = nil
local pending_row   = nil
local flash_frame   = 0.003
local load_menu

local function resolve_easing(val, name)
    local fn = easing.parse(val)
    if not fn then
        fn = easing.parse("linear")
        notify.show("unknown " .. name .. " '" .. tostring(val) .. "', using linear", false, "warn")
    end
    return fn
end

local function resolve_duration(val, fallback)
    local n = tonumber(val)
    if n == nil or n < 0 then return fallback end
    return n
end

local flash_spec = {
    in_d  = state.opts.flash_in_duration,
    in_e  = resolve_easing(state.opts.flash_in_easing, "flash_in_easing"),
    out_d = state.opts.flash_out_duration,
    out_e = resolve_easing(state.opts.flash_out_easing, "flash_out_easing")
}

local start_spec = {
    in_d  = resolve_duration(state.opts.start_in_duration, flash_spec.in_d),
    in_e  = state.opts.start_in_easing ~= "" and resolve_easing(state.opts.start_in_easing, "start_in_easing") or flash_spec.in_e,
    out_d = resolve_duration(state.opts.start_out_duration, flash_spec.out_d),
    out_e = state.opts.start_out_easing ~= "" and resolve_easing(state.opts.start_out_easing, "start_out_easing") or flash_spec.out_e
}

flash_spec.total = flash_spec.in_d + flash_spec.out_d
start_spec.total = start_spec.in_d + start_spec.out_d

local function off(val) return string.format("%s%s%s", theme.c("off_color"), tostring(val), theme.reset()) end
local function on(val) return string.format("%s%s%s", theme.c("on_color"),   tostring(val), theme.reset()) end
local function v(val) return string.format("%s%s%s", theme.c("value_color"), tostring(val), theme.reset()) end

local items = {
    {
        name      = "mark_in",
        label_key = "mark_in",
        label     = "Mark In",
        get_val   = function() return v(actions.get_mark_in_display()) end,
        action    = function() actions.mark(0) end,
        keep_open = true
    },
    {
        name      = "mark_out",
        label_key = "mark_out",
        label     = "Mark Out",
        get_val   = function() return v(actions.get_mark_out_display()) end,
        action    = function() actions.mark(1) end,
        keep_open = true
    },
    {
        name      = "goto",
        label_key = "goto",
        label     = "Go to",
        action    = function() actions.goto_prompt(M.open) end,
        keep_open = false
    },
    -- TODO: document Set In and Set Out and their binds in the README menu table
    {
        name      = "set_mark_in",
        label_key = "set_mark_in",
        label     = "Set In",
        action    = function() actions.set_mark(0, M.open) end,
        keep_open = false
    },
    {
        name      = "set_mark_out",
        label_key = "set_mark_out",
        label     = "Set Out",
        action    = function() actions.set_mark(1, M.open) end,
        keep_open = false
    },
    {
        name      = "encoder",
        label_key = "encoder",
        label     = "Encoder",
        get_val   = function() return v(state.opts.video_encoder) end,
        action    = function() actions.select_encoder(M.open) end,
        keep_open = false
    },
    {
        name      = "quality",
        label_key = "quality",
        label     = "Quality",
        get_val   = function() return v(state.opts.quality) end,
        action    = function() actions.set_quality(M.open) end,
        keep_open = false
    },
    {
        name      = "fps",
        label_key = "fps",
        label     = "FPS",
        get_val   = function() return v(actions.get_fps_display()) end,
        action    = function() actions.set_fps(M.open) end,
        keep_open = false
    },
    {
        name      = "preset",
        label_key = "preset",
        label     = "Preset",
        get_val   = function() return v(state.opts.preset) end,
        action    = function() actions.set_preset(M.open) end,
        keep_open = false
    },
    {
        name      = "lossless_cut",
        label_key = "lossless_cut",
        label     = "Lossless Cut",
        get_val   = function() return state.opts.lossless_cut and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = actions.toggle_lossless,
        keep_open = true
    },
    {
        name      = "accurate_cut",
        label_key = "accurate_cut",
        label     = "Accurate Cut",
        get_val   = function() return state.opts.accurate_cut and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = actions.toggle_accurate,
        keep_open = true
    },
    {
        name      = "combine_audio",
        label_key = "combine_audio",
        label     = "Combine Audio",
        get_val   = function() return state.opts.combine_audio and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = actions.toggle_combine_audio,
        keep_open = true
    },
    {
        name      = "first_audio_only",
        label_key = "first_audio_only",
        label     = "First Audio Only",
        get_val   = function() return state.opts.first_audio_only and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = actions.toggle_first_audio_only,
        keep_open = true
    },
    {
        name      = "effects",
        label_key = "effects",
        label     = "Effects",
        get_val   = function() return v(actions.get_effects_display()) end,
        action    = function() actions.effects_menu(M.open) end,
        keep_open = false
    },
    {
        name      = "space_replacement",
        label_key = "space_replacement",
        label     = "Space Replacement",
        get_val   = function() return v(theme.escape(actions.get_space_replacement_display())) end,
        action    = function() actions.set_space_replacement(M.open) end,
        keep_open = false
    },
    {
        name      = "path",
        label_key = "path",
        label     = "Path",
        get_val   = function() return v(theme.escape(actions.get_final_path())) end,
        action    = function() actions.set_path(M.open) end,
        keep_open = false
    },
    {
        name      = "trash_source",
        label_key = "trash_source",
        label     = "Trash Source",
        get_val   = function() return state.opts.trash_source and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = actions.toggle_trash_source,
        keep_open = true
    },
    {
        name      = "render",
        label_key = "render",
        label     = "Render",
        action    = function() actions.start_render(M.open) end,
        keep_open = false
    },
    {
        name      = "render_queue",
        label_key = "render_queue",
        label     = "Render Queue",
        action    = function() actions.manage_queue(M.open) end,
        keep_open = false
    },
    {
        name      = "render_pause",
        label_key = "render_pause",
        label     = "Pause Render",
        get_val   = function() return render.is_paused() and on(state.opts.on_text) or off(state.opts.off_text) end,
        action    = function() actions.toggle_render_pause() end,
        keep_open = true
    },
    {
        name      = "trash_source_now",
        label_key = "trash_source_now",
        label     = "Trash Source Now",
        action    = function() actions.trash_source(M.open) end,
        keep_open = false
    },
    {
        name      = "stats",
        label_key = "stats",
        label     = "Toggle Stats",
        action    = actions.toggle_stats,
        keep_open = true
    },
    {
        name      = "menu_preset",
        label_key = "menu_preset",
        label     = "Menu",
        get_val   = function() return v(theme.escape(state.opts.selected_menu)) end,
        action    = function() actions.select_menu(load_menu, M.open) end,
        keep_open = false
    },
    {
        name      = "update",
        label_key = "update",
        label     = "Update",
        action    = function() actions.update(M.open) end,
        keep_open = false
    },
    {
        name      = "close",
        label_key = "close",
        label     = "Close",
        action    = function() end,
        keep_open = false
    }
}

local items_by_name = {}
for _, item in ipairs(items) do items_by_name[item.name] = item end

local function text_len(s)
    return select(2, s:gsub("[^\128-\191]", ""))
end

local function row_label(row)
    if row.label and row.label.text ~= "" then return row.label.text end
    return row.item.label
end

local function prune_shadowed()
    local shadowed = {}
    for seq in pairs(active_map) do
        local prefix = seq:match("^(.*)-[^-]*$")
        while prefix do
            if active_map[prefix] then
                shadowed[#shadowed + 1] = seq
                break
            end
            prefix = prefix:match("^(.*)-[^-]*$")
        end
    end
    for _, seq in ipairs(shadowed) do
        notify.show("menu sequence '" .. seq .. "' unreachable, key '" .. seq:match("^(.*)-[^-]*$") .. "' is bound", false, "warn")
        local row = active_map[seq]
        for i = #row.keys, 1, -1 do
            if row.keys[i] == seq then table.remove(row.keys, i) end
        end
        active_map[seq] = nil
    end
end

load_menu = function()
    local rows = {}
    active_map = {}
    for _, row in ipairs(menus.active()) do
        if row.separator then
            rows[#rows + 1] = row
        elseif items_by_name[row.action] then
            row.item = items_by_name[row.action]
            rows[#rows + 1] = row
            for _, seq in ipairs(row.keys) do active_map[seq] = row end
        else
            notify.show("unknown menu action '" .. row.action .. "' for key '" .. table.concat(row.keys, ",") .. "'", false, "warn")
        end
    end
    prune_shadowed()

    active_rows    = {}
    local sep      = false
    local remapped = nil
    for _, row in ipairs(rows) do
        if row.separator then
            sep = #active_rows > 0
        elseif #row.keys > 0 then
            if sep then active_rows[#active_rows + 1] = { separator = true } end
            sep = false
            active_rows[#active_rows + 1] = row
            if pending_row and not remapped and row.action == pending_row.action then remapped = row end
        end
    end
    if pending_row then pending_row = remapped end
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
    local text = string.format("%s%s%s%s < Tachytome > %s\\N\\N", theme.align(7), theme.f(), theme.b(true), theme.c("text_color"), theme.b(false))
    local max_key_len   = 0
    local max_label_len = 0

    for _, row in ipairs(active_rows) do
        if not row.separator and #row.keys > 0 then
            local key_str = table.concat(row.keys, ",")
            local label   = row_label(row)
            if #key_str > max_key_len then max_key_len = #key_str end
            if row.item.get_val and text_len(label) > max_label_len then max_label_len = text_len(label) end
        end
    end

    for _, row in ipairs(active_rows) do
        if row.separator then
            text = text .. "\\N"
        elseif #row.keys > 0 then
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

            if row.item.get_val then
                local val_pad = string.rep("\\h", max_label_len - text_len(label) + 1)
                line = line .. val_pad .. "> " .. row.item.get_val()
            end

            if dim then line = line .. theme.a("00") end

            text = text .. line .. "\\N"
        end
    end

    if active_prefix ~= "" and esc_back then
        text = text .. "\\N" .. theme.f(true) .. theme.c("dim_text_color") .. "(ESC to go back)"
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
        if not row.separator and #row.keys > 0 then
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
    if active_prefix == "" then return end
    active_prefix = active_prefix:match("^(.*)-[^-]*$") or ""
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
    local item = row.item
    if not item then return end
    if not item.keep_open then M.close() end
    if flash_spec.total > 0 then pending_row = row end
    item.action()
    if menu_active then
        pending_row   = nil
        active_prefix = ""
        bind_level()
        start_flash(row, nil, flash_spec)
        draw()
    elseif not state.ui_owner then
        pending_row = nil
    end
end

bind_level = function()
    unbind_all()
    esc_back = false
    local continuations = level_keys(active_prefix)
    for key in pairs(continuations) do
        bind_key(key, "menu-" .. key, function() handle_key(key) end)
    end
    if active_prefix ~= "" then
        if not continuations["ESC"] then
            bind_key("ESC", "menu-back", go_back)
            esc_back = true
        end
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
        return notify.show("A Tachytome menu is already open.")
    end
    if menu_active then M.close() return end
    menu_active    = true
    state.ui_owner = "menu"
    active_prefix  = ""
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
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
