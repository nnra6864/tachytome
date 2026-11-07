local mp            = require 'mp'
local common        = require 'src.common'
local effects       = require 'src.effects'
local ui_input      = require 'src.ui_input'
local ui_list       = require 'src.ui_list'
local ui_confirm    = require 'src.ui_confirm'
local queue_manager = require 'src.queue_manager'
local render        = require 'src.render'
local stats         = require 'src.stats'
local state         = require 'src.state'
local notify        = require 'src.notify'
local theme         = require 'src.theme'
local ui_goto       = require 'src.ui_goto'
local ui_effects    = require 'src.ui_effects'
local ui_configs    = require 'src.ui_configs'
local updater       = require 'src.updater'
local conf          = require 'src.conf'
local menus         = require 'src.menus'
local lang          = require 'src.lang'

local M = {}

local function on_off(val)
    return lang.t(val and "value_on" or "value_off")
end

local function notify_set(name, value)
    notify.show(lang.t("value_set", { label = lang.t("menu_" .. name), value = value }))
end

local function warn_invalid(name, value)
    notify.show(lang.t("value_invalid", { label = lang.t("menu_" .. name), value = value }), true, "warn")
end

function M.goto_prompt(on_complete)
    ui_goto.show(on_complete, {
        { key = "i", label = lang.t("menu_mark_in"),  get_val = M.get_mark_in_display,  action = function() M.goto_mark(0) end },
        { key = "o", label = lang.t("menu_mark_out"), get_val = M.get_mark_out_display, action = function() M.goto_mark(1) end }
    })
end

function M.mark(place)
    local time = mp.get_property_number("time-pos", 0)
    if place == 0 then
        state.mark_in = time
        notify_set("mark_in", common.format_time(time))
    elseif place == 1 then
        state.mark_out = time
        notify_set("mark_out", common.format_time(time))
    end
end

function M.goto_mark(place)
    local time = place == 0 and M.get_resolved_mark_in() or state.mark_out
    mp.commandv("osd-bar", "seek", time, "absolute")
    notify_set("goto", common.format_time(time))
end

function M.set_mark(place, on_complete)
    ui_goto.show(on_complete, nil, place)
end

function M.set_quality(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local min_val = 0
    local max_val = 51
    local label   = "CRF"

    if enc == "av1" or enc == "nv_av1" then max_val = 63
    elseif enc == "h265" then max_val = 51
    elseif enc == "h264" then max_val = 51
    elseif enc:match("^intel_") then min_val = 1; label = lang.t("quality_global")
    elseif enc:match("^nv_") or enc:match("^amd_") then label = "CQ" end

    ui_input.show({
        title     = lang.t("menu_quality"),
        current   = state.opts.quality,
        hint      = lang.t("hint_quality", { label = label, min = min_val, max = max_val }),
        on_cancel = on_complete,
        on_submit = function(input)
            local num = tonumber(input)
            if num and num >= min_val and num <= max_val then
                state.opts.quality = num
                notify_set("quality", num)
            elseif input ~= "" then
                warn_invalid("quality", input)
            end
            if on_complete then on_complete() end
        end
    })
end

function M.set_preset(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local presets = {}

    if enc == "av1" then presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"}
    elseif enc == "h265" then presets = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo"}
    elseif enc == "h264" then presets = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo"}
    elseif enc:match("^nv_") then presets = {"p1", "p2", "p3", "p4", "p5", "p6", "p7"}
    elseif enc:match("^amd_") then presets = {"speed", "balanced", "quality"}
    elseif enc:match("^intel_") then presets = {"veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"}
    else presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"} end

    ui_list.show(string.format("%s (%s)", lang.t("menu_preset"), enc), presets, tostring(state.opts.preset), function(val)
        if enc == "av1" then
            state.opts.preset = tonumber(val)
        else
            state.opts.preset = val
        end
        notify_set("preset", state.opts.preset)
        if on_complete then on_complete() end
    end, on_complete)
end

local function get_source_fps()
    return mp.get_property_number("container-fps")
end

local function format_fps(val)
    local s = string.format("%.3f", val)
    if s:find(".", 1, true) then s = s:gsub("0+$", ""):gsub("%.$", "") end
    return s
end

function M.get_fps_display()
    if state.fps_override then return format_fps(state.fps_override) end
    local src = get_source_fps()
    if src and src > 0 then return format_fps(src) end
    return lang.t("value_source")
end

function M.set_fps(on_complete)
    ui_input.show({
        title     = lang.t("menu_fps"),
        current   = M.get_fps_display(),
        hint      = lang.t("hint_fps"),
        on_cancel = on_complete,
        on_submit = function(input)
            local num = tonumber(input)
            local src = get_source_fps()

            if input == "" or (num and src and math.abs(num - src) < 0.01) then
                state.fps_override = nil
                notify_set("fps", M.get_fps_display())
            elseif num and num > 0 and num < 1001 then
                state.fps_override = num
                notify_set("fps", M.get_fps_display())
            else
                warn_invalid("fps", input)
            end
            if on_complete then on_complete() end
        end
    })
end

local function valid_keyframe_interval(val)
    local num = tonumber(val:match("^%d+$") or val:match("^([%d%.]+)s$"))
    return num ~= nil and num > 0
end

function M.get_keyframes_display()
    if state.opts.keyframe_interval == "" then return lang.t("value_default") end
    return state.opts.keyframe_interval
end

function M.set_keyframes(on_complete)
    ui_input.show({
        title     = lang.t("menu_keyframes"),
        current   = M.get_keyframes_display(),
        hint      = lang.t("hint_keyframes"),
        on_cancel = on_complete,
        on_submit = function(input)
            input = input:lower()
            if input == "" or valid_keyframe_interval(input) then
                state.opts.keyframe_interval = input
                notify_set("keyframes", M.get_keyframes_display())
            else
                warn_invalid("keyframes", input)
            end
            if on_complete then on_complete() end
        end
    })
end

function M.select_encoder(on_complete)
    local encoders = { "av1", "nv_av1", "amd_av1", "intel_av1", "h265", "nv_h265", "amd_h265", "intel_h265", "h264", "nv_h264", "amd_h264", "intel_h264" }

    ui_list.show(lang.t("menu_encoder"), encoders, state.opts.video_encoder, function(new_enc)
        if new_enc ~= state.opts.video_encoder then
            state.opts.video_encoder = new_enc

            if new_enc == "av1" then state.opts.preset = 4
            elseif new_enc == "h265" then state.opts.preset = "slow"
            elseif new_enc == "h264" then state.opts.preset = "slow"
            elseif new_enc:match("^nv_") then state.opts.preset = "p7"
            elseif new_enc:match("^amd_") then state.opts.preset = "quality"
            elseif new_enc:match("^intel_") then state.opts.preset = "veryslow" end

            if new_enc:match("^intel_") and (tonumber(state.opts.quality) or 0) < 1 then
                state.opts.quality = 1
            end
        end
        notify_set("encoder", state.opts.video_encoder)
        if on_complete then on_complete() end
    end, on_complete)
end

M.stats_visible = false
local stats_ov = mp.create_osd_overlay("ass-events")

function M.refresh_stats()
    if not M.stats_visible then return end

    local msg_title = lang.t("stats_title")
    local msg_body, msg_osd_body, msg_width = stats.get_formatted_stats()
    local pad_len = math.max(0, msg_width - common.text_len(msg_title))
    local pad = string.rep("\\h", pad_len)

    local full_osd = string.format("%s%s%s%s%s%s%s\\N\\N%s",
        theme.c("text_color"), theme.align(3), theme.f(false), theme.b(true),
        theme.escape(msg_title), pad, theme.b(false), msg_osd_body)

    notify.show("\n" .. msg_title .. "\n" .. msg_body .. "\n", false)
    stats_ov.data = full_osd
    stats_ov:update()
end

function M.toggle_stats()
    M.stats_visible = not M.stats_visible

    if not M.stats_visible then
        stats_ov:remove()
        return
    end

    M.refresh_stats()
end

stats.on_update = M.refresh_stats

function M.trash_source(on_complete)
    local current_file = mp.get_property("path")
    if not current_file then
        notify.show(lang.t("no_video"), true, "error")
        if on_complete then on_complete() end
        return
    end
    if not state.trash_path then
        notify.show(lang.t("trash_no_tool"), true, "error")
        if on_complete then on_complete() end
        return
    end

    ui_confirm.show(lang.t("trash_confirm"), current_file, function()
        common.trash_file(current_file, state.trash_path, function(success)
            if success then
                notify.show(lang.t("trash_done"), true)
                mp.commandv("playlist-next", "weak")
            else notify.show(lang.t("trash_failed"), true, "error") end
        end)
        if on_complete then on_complete() end
    end, on_complete)
end

function M.toggle_lossless()
    state.opts.lossless_cut = not state.opts.lossless_cut
    if state.opts.lossless_cut then
        if state.opts.accurate_cut then
            state.opts.accurate_cut = false
            notify_set("accurate_cut", on_off(false))
        end
        if state.effects_enabled then
            state.effects_enabled = false
            notify_set("effects", lang.t("effects_off"))
        end
    end
    notify_set("lossless_cut", on_off(state.opts.lossless_cut))
end

function M.toggle_accurate()
    state.opts.accurate_cut = not state.opts.accurate_cut
    if state.opts.accurate_cut and state.opts.lossless_cut then
        state.opts.lossless_cut = false
        notify_set("lossless_cut", on_off(false))
    end
    notify_set("accurate_cut", on_off(state.opts.accurate_cut))
end

function M.get_effects_display()
    local parts  = {}
    local counts = {}
    for _, inst in ipairs(state.effects) do
        local label = effects.label(inst.name)
        counts[label] = (counts[label] or 0) + 1
    end
    for _, inst in ipairs(state.effects) do
        local label = effects.label(inst.name)
        local p     = effects.preset(inst.name)
        if counts[label] > 1 and p then label = lang.t("effects_duplicate", { label = label, file = p.file }) end
        parts[#parts + 1] = label
    end
    if #parts == 0 then return lang.t(state.effects_enabled and "value_none" or "effects_off") end
    local selected = table.concat(parts, ", ")
    return state.effects_enabled and selected or lang.t("effects_off_list", { list = selected })
end

function M.effects_menu(on_complete)
    ui_effects.show(on_complete)
end

function M.toggle_combine_audio()
    state.opts.combine_audio = not state.opts.combine_audio
    notify_set("combine_audio", on_off(state.opts.combine_audio))
end

function M.toggle_first_audio_only()
    state.opts.first_audio_only = not state.opts.first_audio_only
    notify_set("first_audio_only", on_off(state.opts.first_audio_only))
end

function M.toggle_trash_source()
    state.opts.trash_source = not state.opts.trash_source
    notify_set("trash_source", on_off(state.opts.trash_source))
end

function M.set_space_replacement(on_complete)
    ui_input.show({
        title       = lang.t("menu_space_replacement"),
        current     = M.get_space_replacement_display(),
        hint        = lang.t("hint_space"),
        allow_space = true,
        on_cancel   = on_complete,
        on_submit   = function(input)
            state.opts.space_replacement = input
            notify_set("space_replacement", M.get_space_replacement_display())
            if on_complete then on_complete() end
        end
    })
end

function M.get_space_replacement_display()
    local v = state.opts.space_replacement
    if v == "" then return lang.t("value_none") end
    if v == " " then return lang.t("value_space") end
    return v
end

function M.get_final_path()
    return common.resolve_absolute_path(state.custom_output_name, state.opts)
end

function M.get_final_path_display()
    return common.display_path(M.get_final_path(), mp.get_property("path"))
end

function M.get_resolved_mark_in()
    return common.resolve_mark_in(state.mark_in, state.opts.lossless_cut, mp.get_property("path"))
end

function M.get_mark_in_display()
    return common.format_time(M.get_resolved_mark_in())
end

function M.get_mark_out_display()
    return common.format_time(state.mark_out)
end

function M.set_path(on_complete)
    ui_input.show({
        title       = lang.t("menu_path"),
        current     = state.custom_output_name ~= "" and state.custom_output_name or M.get_final_path_display(),
        hint        = lang.t("hint_path"),
        history     = state.path_history,
        allow_space = true,
        on_cancel   = on_complete,
        preview     = function(input)
            return common.resolve_absolute_path(input, state.opts)
        end,
        on_submit   = function(input)
            state.custom_output_name = input
            if input ~= "" then common.add_to_history(state.path_history, input) end
            notify_set("path", M.get_final_path_display())
            if on_complete then on_complete() end
        end
    })
end

function M.start_render(on_complete)
    render.start({
        final_output_path   = M.get_final_path(),
        mark_in             = state.mark_in,
        mark_out            = state.mark_out,
        input_duration      = mp.get_property_number("duration", 0),
        video_encoder       = state.opts.video_encoder,
        accurate_cut        = state.opts.accurate_cut,
        lossless_cut        = state.opts.lossless_cut,
        quality             = state.opts.quality,
        preset              = state.opts.preset,
        fps_override        = state.fps_override,
        keyframe_interval   = state.opts.keyframe_interval,
        effects             = state.effects_enabled and effects.snapshot() or nil,
        combine_audio       = state.opts.combine_audio,
        combined_audio_name = state.opts.combined_audio_name,
        first_audio_only    = state.opts.first_audio_only,
        trash_source        = state.opts.trash_source,
        trash_path          = state.trash_path,
        space_replacement   = state.opts.space_replacement,
        show_stats_screen   = state.opts.show_stats_screen,
        show_stats_terminal = state.opts.show_stats_terminal,
        stats_osd_time      = state.opts.stats_osd_time,
        rename_callback     = M.set_path,
        on_complete         = on_complete
    })
end

function M.manage_queue(on_complete)
    queue_manager.show(on_complete)
end

function M.toggle_render_pause()
    render.toggle_pause()
end

function M.update(on_complete)
    updater.run(on_complete)
end

function M.select_menu(on_select, on_complete)
    ui_list.show(lang.t("menu_menu_preset"), menus.names(), state.opts.selected_menu, function(name)
        if name ~= state.opts.selected_menu then
            state.opts.selected_menu = name
            conf.write_option("selected_menu", name)
            if on_select then on_select() end
        end
        notify_set("menu_preset", name)
        if on_complete then on_complete() end
    end, on_complete)
end

function M.get_configs_display()
    local names = {}
    for _, c in ipairs(conf.configs) do
        if c.enabled and c.exists then names[#names + 1] = c.name end
    end
    if #names == 0 then return lang.t("value_none") end
    return table.concat(names, ", ")
end

function M.select_configs(on_reload, on_complete)
    ui_configs.show(conf.configs, function(list)
        conf.write_configs(list)
        conf.read_options(state.opts)
        effects.seed()
        lang.load()
        if on_reload then on_reload() end
        notify_set("configs", M.get_configs_display())
        if on_complete then on_complete() end
    end, on_complete)
end

function M.select_language(on_complete)
    local codes = { "auto" }
    for _, code in ipairs(lang.available()) do codes[#codes + 1] = code end

    ui_list.show(lang.t("menu_language"), codes, state.opts.language, function(code)
        if code ~= state.opts.language then
            state.opts.language = code
            conf.write_option("language", code)
            lang.load()
        end
        notify_set("language", code)
        if on_complete then on_complete() end
    end, on_complete)
end

return M
