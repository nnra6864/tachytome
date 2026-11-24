local mp            = require 'mp'
local common        = require 'src.common'
local effects       = require 'src.effects'
local resolution    = require 'src.resolution'
local ui_input      = require 'src.ui_input'
local ui_list       = require 'src.ui_list'
local ui_confirm    = require 'src.ui_confirm'
local queue_manager = require 'src.queue_manager'
local render        = require 'src.render'
local trash         = require 'src.trash'
local stats         = require 'src.stats'
local state         = require 'src.state'
local notify        = require 'src.notify'
local theme         = require 'src.theme'
local ui_goto       = require 'src.ui_goto'
local ui_effects    = require 'src.ui_effects'
local ui_resolution = require 'src.ui_resolution'
local ui_tracks     = require 'src.ui_tracks'
local tracks        = require 'src.tracks'
local ui_configs    = require 'src.ui_configs'
local ui_settings   = require 'src.ui_settings'
local options       = require 'src.options'
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
    local enc = options.encoder(state.opts.video_encoder)

    ui_input.show({
        title     = lang.t("menu_quality"),
        current   = state.opts.quality,
        hint      = lang.t("hint_quality", { label = options.quality_label(enc), min = enc.min, max = enc.max, range = options.range_hint(enc), recommended = enc.quality }),
        on_cancel = on_complete,
        on_submit = function(input)
            local num = tonumber(input)
            if num and num >= enc.min and num <= enc.max then
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
    local enc = options.encoder(state.opts.video_encoder)

    ui_list.show(string.format("%s (%s)", lang.t("menu_preset"), enc.name), enc.presets, tostring(state.opts.preset), function(val)
        state.opts.preset = val
        notify_set("preset", val)
        if on_complete then on_complete() end
    end, on_complete, {
        detail = function(i) return enc.presets[i] == enc.preset and lang.t("value_recommended") or "" end
    })
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

local function source_keyframes(peek)
    local path = mp.get_property("path")
    local fps  = get_source_fps()
    if not path or not fps or fps <= 0 then return nil end

    local interval, ready = nil, true
    if peek then
        interval, ready = common.peek_keyframe_interval(path)
    else
        interval = common.get_keyframe_interval(path)
    end
    if not ready then return nil, nil, true end
    if not interval then return nil end

    local frames = math.floor(interval * fps + 0.5)
    if frames < 2 or frames < fps then return nil end
    return frames / fps, fps
end

local function keyframe_seconds(val, fps)
    local secs = tonumber(val:match("^([%d%.]+)s$") or "")
    if secs then return secs end
    local frames = tonumber(val:match("^%d+$") or "")
    if frames and fps then return frames / fps end
    return nil
end

function M.get_keyframe_interval()
    if state.opts.keyframe_interval ~= "" then return state.opts.keyframe_interval end
    local secs = source_keyframes()
    if secs then return format_fps(secs) .. "s" end
    return ""
end

function M.get_keyframes_display()
    if state.opts.keyframe_interval ~= "" then return state.opts.keyframe_interval end
    local secs, _, pending = source_keyframes(true)
    if pending then return lang.t("value_detecting") end
    if secs then return format_fps(secs) .. "s" end
    return lang.t("value_default")
end

function M.set_keyframes(on_complete)
    local current = M.get_keyframe_interval()
    if current == "" then current = lang.t("value_default") end
    ui_input.show({
        title     = lang.t("menu_keyframes"),
        current   = current,
        hint      = lang.t("hint_keyframes"),
        on_cancel = on_complete,
        on_submit = function(input)
            input = input:lower()
            if input == "" or valid_keyframe_interval(input) then
                local src, fps = source_keyframes()
                local secs     = src and keyframe_seconds(input, fps)
                if secs and math.abs(secs - src) < 0.5 / fps then input = "" end
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
    ui_list.show(lang.t("menu_encoder"), options.encoder_names(), state.opts.video_encoder, function(new_enc)
        if new_enc ~= state.opts.video_encoder then
            local enc = options.encoder(new_enc)
            state.opts.video_encoder = new_enc
            state.opts.quality       = enc.quality
            state.opts.preset        = enc.preset
            notify.show(lang.t("encoder_recommended", { encoder = new_enc, quality = enc.quality, preset = enc.preset }))
        else
            notify_set("encoder", new_enc)
        end
        if on_complete then on_complete() end
    end, on_complete, {
        detail = function(i) return options.encoder_detail(options.encoders[i]) end
    })
end

function M.select_audio_encoder(on_complete)
    local encoders = { "copy", "opus", "aac", "mp3", "flac", "vorbis", "pcm" }

    ui_list.show(lang.t("menu_audio_encoder"), encoders, state.opts.audio_encoder, function(new_enc)
        state.opts.audio_encoder = new_enc
        notify_set("audio_encoder", new_enc)
        if on_complete then on_complete() end
    end, on_complete)
end

local function source_bitrate()
    local result = tracks.current()
    local first  = result and result.audio[1]
    local t      = first and tracks.list("audio")[tracks.leaf(first)]
    if not t then return nil end
    local enc  = state.opts.audio_encoder
    local same = enc == "copy" or t.codec == enc or (enc == "pcm" and (t.codec or ""):match("^pcm_"))
    if not same then return nil, true end
    local bps = tonumber(t["demux-bitrate"])
    if bps and bps > 0 then return string.format("%dk", math.floor(bps / 1000 + 0.5)) end
    return nil, enc ~= "copy"
end

function M.get_audio_bitrate_display()
    if state.opts.audio_bitrate ~= "" then return state.opts.audio_bitrate end
    local src, best = source_bitrate()
    if best then return lang.t("value_best") end
    return src or lang.t("value_source")
end

function M.set_audio_bitrate(on_complete)
    ui_input.show({
        title     = lang.t("menu_audio_bitrate"),
        current   = M.get_audio_bitrate_display(),
        hint      = lang.t("hint_audio_bitrate"),
        on_cancel = on_complete,
        on_submit = function(input)
            input = input:lower()
            if input == source_bitrate() or (state.opts.audio_bitrate == "" and input == M.get_audio_bitrate_display():lower()) then input = "" end
            if input == "" or input:match("^%d+k?$") then
                state.opts.audio_bitrate = input
                notify_set("audio_bitrate", M.get_audio_bitrate_display())
            else
                warn_invalid("audio_bitrate", input)
            end
            if on_complete then on_complete() end
        end
    })
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

    local queued = trash.users(current_file)
    local title  = queued > 0 and lang.t("trash_confirm_queued", { count = queued }) or lang.t("trash_confirm")
    ui_confirm.show(title, current_file, function()
        if queued > 0 then
            trash.request(current_file, state.trash_path)
        else
            trash.now(current_file, state.trash_path)
        end
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
            notify_set("effects", on_off(false))
        end
        if state.resolution_enabled then
            state.resolution_enabled = false
            notify_set("resolution", on_off(false))
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
    return table.concat(parts, ", ")
end

function M.effects_menu(on_complete)
    ui_effects.show(on_complete)
end

function M.get_resolution_display()
    if state.resolution == "" then return "" end
    local out = resolution.output(state.resolution)
    if not out then return state.resolution end
    return string.format("%s -> %s", state.resolution, out)
end

function M.resolution_menu(on_complete)
    ui_resolution.show(on_complete)
end

function M.get_tracks_display()
    return lang.t("tracks_summary", { audio = tracks.display("audio"), video = tracks.display("video") })
end

function M.tracks_menu(on_complete)
    ui_tracks.show(on_complete)
end

function M.toggle_combine_audio()
    local on, err = tracks.toggle_combine()
    if on == nil then return notify.show(err, true, "error") end
    notify_set("combine_audio", on_off(on))
end

function M.toggle_combined_audio_only()
    local on, err = tracks.toggle_only()
    if on == nil then return notify.show(err, true, "error") end
    notify_set("combined_audio_only", on_off(on))
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
    return common.resolve_absolute_path(state.custom_output_name, state.opts, tracks.container())
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
            return common.resolve_absolute_path(input, state.opts, tracks.container())
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
    local res, err = resolution.snapshot()
    if not err then
        local ok, tracks_err = tracks.current()
        if not ok then err = tracks_err end
    end
    if err then
        notify.show(err, true, "error")
        if on_complete then on_complete() end
        return
    end
    local job = {
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
        keyframe_interval   = M.get_keyframe_interval(),
        effects             = state.effects_enabled and effects.snapshot() or nil,
        resolution          = res,
        audio_encoder       = state.opts.audio_encoder,
        audio_bitrate       = state.opts.audio_bitrate,
        tracks              = state.tracks,
        trash_source        = state.opts.trash_source,
        trash_path          = state.trash_path,
        space_replacement   = state.opts.space_replacement,
        show_stats_screen   = state.opts.show_stats_screen,
        show_stats_terminal = state.opts.show_stats_terminal,
        stats_osd_time      = state.opts.stats_osd_time,
        rename_callback     = M.set_path,
        on_complete         = on_complete
    }
    local path    = mp.get_property("path")
    local waiting = resolution.prepare(res, function(ready)
        if mp.get_property("path") ~= path then
            if on_complete then on_complete() end
            return
        end
        job.resolution = ready
        render.start(job)
    end)
    if waiting then notify.show(lang.t("resolution_detecting")) end
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

function M.select_version(on_complete)
    notify.show(lang.t("update_fetching_versions"), true)
    updater.versions(function(list, err, details)
        if not list then
            notify.show(lang.t("update_versions_failed"), true, "error")
            if err and err ~= "" then mp.msg.error(err) end
            if on_complete then on_complete() end
            return
        end
        ui_list.show(lang.t("menu_version"), list, state.opts.version, function(name)
            if name ~= state.opts.version then
                state.opts.version = name
                conf.write_option("version", name)
            end
            notify_set("version", name)
            if on_complete then on_complete() end
        end, on_complete, {
            detail = function(i) return details[list[i]] or "" end
        })
    end)
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

local function apply_configs(list, on_reload)
    conf.write_configs(list)
    conf.read_options(state.opts)
    effects.seed()
    resolution.seed()
    tracks.reset()
    lang.load()
    if on_reload then on_reload() end
    notify.show(lang.t("configs_applied", { list = M.get_configs_display() }))
end

local function setting_pickers()
    return {
        video_encoder     = M.select_encoder,
        quality           = M.set_quality,
        preset            = M.set_preset,
        keyframe_interval = M.set_keyframes,
        audio_encoder     = M.select_audio_encoder,
        audio_bitrate     = M.set_audio_bitrate,
        space_replacement = M.set_space_replacement,
        resolution        = M.resolution_menu,
        tracks            = M.tracks_menu,
        effects_presets   = M.effects_menu
    }
end

function M.select_configs(on_reload, on_complete)
    ui_configs.show(conf.configs, function(list)
        apply_configs(list, on_reload)
        if on_complete then on_complete() end
    end, on_complete, function(list, row)
        if list then apply_configs(list, on_reload) end
        ui_settings.show(row.name, row.pinned or row.enabled, setting_pickers(), function()
            if on_reload then on_reload() end
            M.select_configs(on_reload, on_complete)
        end)
    end, function(list) apply_configs(list, on_reload) end)
end

function M.select_language(on_complete)
    ui_list.show(lang.t("menu_language"), options.choices("language"), state.opts.language, function(code)
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
