local mp      = require 'mp'
local state   = require 'src.state'
local actions = require 'src.actions'
local keymap  = require 'src.keymap'
local notify  = require 'src.notify'
local render  = require 'src.render'
local theme   = require 'src.theme'
local easing  = require 'src.easing'

local M             = {}
local menu_active   = false
local menu_overlay  = mp.create_osd_overlay("ass-events")
local active_map    = {}
local active_prefix = ""
local bound_names   = {}
local esc_back      = false
local flashes       = {}
local flash_timer   = nil
local pending_name  = nil
local flash_frame   = 0.003

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

local registry = {
    {
        name = "mark_in",
        label = "Mark In",
        get_val = function() return v(actions.get_mark_in_display()) end,
        action = function() actions.mark(0) end,
        keep_open = true
    },
    {
        name = "mark_out",
        label = "Mark Out",
        get_val = function() return v(actions.get_mark_out_display()) end,
        action = function() actions.mark(1) end,
        keep_open = true
    },

    { separator = true },
    {
        name = "goto_in",
        label = "Go to In",
        action = function() actions.goto_mark(0) end,
        keep_open = true
    },
    {
        name = "goto_out",
        label = "Go to Out",
        action = function() actions.goto_mark(1) end,
        keep_open = true
    },
    {
        name = "goto",
        label = "Go to",
        action = function() actions.goto_prompt(M.open) end,
        keep_open = false
    },

    { separator = true },
    {
        name = "encoder",
        label = "Encoder",
        get_val = function() return v(state.opts.video_encoder) end,
        action = function() actions.select_encoder(M.open) end,
        keep_open = false
    },
    {
        name = "quality",
        label = "Quality",
        get_val = function() return v(state.opts.quality) end,
        action = function() actions.set_quality(M.open) end,
        keep_open = false
    },
    {
        name = "fps",
        label = "FPS",
        get_val = function() return v(actions.get_fps_display()) end,
        action = function() actions.set_fps(M.open) end,
        keep_open = false
    },
    {
        name = "preset",
        label = "Preset",
        get_val = function() return v(state.opts.preset) end,
        action = function() actions.set_preset(M.open) end,
        keep_open = false
    },
    {
        name = "lossless_cut",
        label = "Lossless Cut",
        get_val = function() return state.opts.lossless_cut and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = actions.toggle_lossless,
        keep_open = true
    },
    {
        name = "accurate_cut",
        label = "Accurate Cut",
        get_val = function() return state.opts.accurate_cut and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = actions.toggle_accurate,
        keep_open = true
    },

    { separator = true },
    {
        name = "combine_audio",
        label = "Combine Audio",
        get_val = function() return state.opts.combine_audio and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = actions.toggle_combine_audio,
        keep_open = true
    },
    {
        name = "first_audio_only",
        label = "First Audio Only",
        get_val = function() return state.opts.first_audio_only and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = actions.toggle_first_audio_only,
        keep_open = true
    },

    { separator = true },
    {
        name = "effects",
        label = "Effects",
        get_val = function() return v(actions.get_effects_display()) end,
        action = function() actions.effects_menu(M.open) end,
        keep_open = false
    },

    { separator = true },
    {
        name = "space_replacement",
        label = "Space Replacement",
        get_val = function() return v(theme.escape(actions.get_space_replacement_display())) end,
        action = function() actions.set_space_replacement(M.open) end,
        keep_open = false
    },
    {
        name = "path",
        label = "Path",
        get_val = function() return v(theme.escape(actions.get_final_path())) end,
        action = function() actions.set_path(M.open) end,
        keep_open = false
    },
    {
        name = "trash_source",
        label = "Trash Source",
        get_val = function() return state.opts.trash_source and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = actions.toggle_trash_source,
        keep_open = true
    },

    { separator = true },
    {
        name = "render",
        label = "Render",
        action = function() actions.start_render(M.open) end,
        keep_open = false
    },
    {
        name = "render_queue",
        label = "Render Queue",
        action = function() actions.manage_queue(M.open) end,
        keep_open = false
    },
    {
        name = "render_pause",
        label = "Pause Render",
        get_val = function() return render.is_paused() and on(state.opts.on_text) or off(state.opts.off_text) end,
        action = function() actions.toggle_render_pause() end,
        keep_open = true
    },
    {
        name = "trash_source_now",
        label = "Trash Source Now",
        action = function() actions.trash_source(M.open) end,
        keep_open = false
    },
    {
        name = "stats",
        label = "Toggle Stats",
        action = actions.toggle_stats,
        keep_open = true
    },

    { separator = true },
    {
        name = "close",
        label = "Close",
        action = function() end,
        keep_open = false
    }
}

local defs_by_name = {}
for _, def in ipairs(registry) do
    if not def.separator then defs_by_name[def.name] = def end
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
        notify.show("keymap sequence '" .. seq .. "' unreachable, key '" .. seq:match("^(.*)-[^-]*$") .. "' is bound", false, "warn")
        active_map[seq] = nil
    end
end

local function load_keymap()
    active_map = {}
    for seq, action in pairs(keymap.active()) do
        if defs_by_name[action] then
            active_map[seq] = action
        else
            notify.show("unknown keymap action '" .. action .. "' for key '" .. seq .. "'", false, "warn")
        end
    end
    prune_shadowed()
end

load_keymap()

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
    local seqs_by_action = {}
    for seq, action in pairs(active_map) do
        seqs_by_action[action] = seqs_by_action[action] or {}
        seqs_by_action[action][#seqs_by_action[action] + 1] = seq
    end
    for _, seqs in pairs(seqs_by_action) do table.sort(seqs) end

    local text = string.format("%s%s%s%s < Tachytome > %s\\N\\N", theme.align(7), theme.f(), theme.b(true), theme.c("text_color"), theme.b(false))
    local max_key_len   = 0
    local max_label_len = 0

    for _, def in ipairs(registry) do
        if not def.separator and seqs_by_action[def.name] then
            local key_str = table.concat(seqs_by_action[def.name], ",")
            if #key_str > max_key_len then max_key_len = #key_str end
            if def.get_val and #def.label > max_label_len then max_label_len = #def.label end
        end
    end

    for _, def in ipairs(registry) do
        if def.separator then
            text = text .. "\\N"
        else
            local seqs = seqs_by_action[def.name]
            if seqs then
                local key_str = table.concat(seqs, ",")
                local key_pad = string.rep("\\h", max_key_len - #key_str)
                local base    = theme.c("text_color")
                local fl      = flashes[def.name]
                if fl then
                    local p = flash_progress(fl)
                    if p > 0 then base = theme.mix(state.opts.text_color, state.opts.flash_color, p) end
                end
                local key_txt = nil
                local matched = false
                for _, seq in ipairs(seqs) do
                    key_txt = key_txt and key_txt .. base .. "," .. render_seq(seq, base) or render_seq(seq, base)
                    if seq_matches(seq) then matched = true end
                end

                local line = string.format("%s%s%s -> %s", key_pad, key_txt, base, def.label)
                local dim  = active_prefix ~= "" and not matched

                if dim then line = theme.a("66") .. line end

                if def.get_val then
                    local val_pad = string.rep("\\h", max_label_len - #def.label + 1)
                    line = line .. val_pad .. "> " .. def.get_val()
                end

                if dim then line = line .. theme.a("00") end

                text = text .. line .. "\\N"
            end
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
    for name, fl in pairs(flashes) do
        if now >= fl.at + fl.spec.total then flashes[name] = nil end
    end
    if not next(flashes) and flash_timer then
        flash_timer:kill()
        flash_timer = nil
    end
    if menu_active then draw() end
end

local function start_flash(name, delay, spec)
    if spec.total <= 0 then return end
    flashes[name] = { at = mp.get_time() + (delay or 0), spec = spec }
    if not flash_timer then
        flash_timer = mp.add_periodic_timer(flash_frame, flash_tick)
    end
end

local function start_cascade()
    if start_spec.total <= 0 then return end
    local bound = {}
    for _, action in pairs(active_map) do bound[action] = true end
    local stagger = math.max(0, state.opts.start_stagger)
    local i = 0
    for _, def in ipairs(registry) do
        if not def.separator and bound[def.name] then
            start_flash(def.name, i * stagger, start_spec)
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
    local act = active_map[seq]
    if act then
        fire(act)
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

fire = function(act)
    local def = defs_by_name[act]
    if not def then return end
    if not def.keep_open then M.close() end
    if flash_spec.total > 0 then pending_name = act end
    def.action()
    if menu_active then
        pending_name = nil
        active_prefix = ""
        bind_level()
        start_flash(act, nil, flash_spec)
        draw()
    elseif not state.ui_owner then
        pending_name = nil
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
    if pending_name then
        start_flash(pending_name, nil, flash_spec)
        pending_name = nil
    else
        start_cascade()
    end
    draw()
end

function M.refresh()
    if menu_active then draw() end
end

return M
