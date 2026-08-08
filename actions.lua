local mp        = require 'mp'
local common    = require 'common'
local osd_input = require 'osd_input'
local render    = require 'render'
local stats     = require 'stats'
local state     = require 'state'

local M = {}

function M.mark(place)
    local time = mp.get_property_number("time-pos", 0)
    if place == 0 then
        state.mark_in = time
        common.notify("In: " .. common.format_time(time))
    elseif place == 1 then
        state.mark_out = time
        common.notify("Out: " .. common.format_time(time))
    end
end

function M.set_quality(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local min_val = 0
    local max_val = 51
    local label   = "CRF"

    if enc == "av1" then
        max_val = 63
    elseif enc == "h265" then
        max_val = 51
    elseif enc:match("^intel_") then
        min_val = 1
        label   = "Global Quality"
    elseif enc:match("^nv_") or enc:match("^amd_") then
        label   = "CQ"
    end

    local prompt = string.format("%s (%d-%d): ", label, min_val, max_val)

    osd_input.get_user_input(prompt, function(input)
        local num = tonumber(input)
        if num and num >= min_val and num <= max_val then
            state.opts.quality = num
            common.notify(label .. ": " .. state.opts.quality)
        else
            common.notify(string.format("Invalid %s, keeping: %s", label, state.opts.quality), true, "warn")
        end
        if on_complete then on_complete() end
    end, tostring(state.opts.quality), true)
end

function M.set_preset(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local presets = {}

    if enc == "av1" then
        presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"}
    elseif enc == "h265" then
        presets = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo"}
    elseif enc:match("^nv_") then
        presets = {"p1", "p2", "p3", "p4", "p5", "p6", "p7"}
    elseif enc:match("^amd_") then
        presets = {"speed", "balanced", "quality"}
    elseif enc:match("^intel_") then
        presets = {"veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"}
    else
        presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"}
    end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1

    local current_preset = tostring(state.opts.preset)
    for i, p in ipairs(presets) do
        if p == current_preset then
            cursor = i
            break
        end
    end

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("pre-up")
        mp.remove_key_binding("pre-down")
        mp.remove_key_binding("pre-enter")
        mp.remove_key_binding("pre-esc")
        if on_complete then on_complete() end
    end

    local function draw()
        local text = "{\\an7}{\\fnmonospace}{\\fs18}{\\b1}Select Preset for " .. enc .. "{\\b0}\\N(Up/Down to navigate, Enter to select, Esc to cancel)\\N\\N"

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#presets, start_idx + 14)
        if end_idx - start_idx < 14 then
            start_idx = math.max(1, end_idx - 14)
        end

        if start_idx > 1 then text = text .. "  ...\\N" end

        for i = start_idx, end_idx do
            local p        = presets[i]
            local prefix   = (i == cursor) and "{\\c&H00FFFF&}➤ " or "  "
            local selected = (p == current_preset) and "{\\c&H00FF00&}[Active]" or ""
            text = text .. string.format("%s%s %s{\\c&HFFFFFF&}\\N", prefix, p, selected)
        end

        if end_idx < #presets then text = text .. "  ...\\N" end

        ov.data = text
        ov:update()
    end

    mp.add_forced_key_binding("UP", "pre-up", function()
        if cursor > 1 then cursor = cursor - 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("DOWN", "pre-down", function()
        if cursor < #presets then cursor = cursor + 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("ENTER", "pre-enter", function()
        local val = presets[cursor]
        if enc == "av1" then
            state.opts.preset = tonumber(val)
        else
            state.opts.preset = val
        end
        common.notify("Preset set to: " .. tostring(state.opts.preset))
        cleanup()
    end)

    mp.add_forced_key_binding("ESC", "pre-esc", cleanup)

    draw()
end

function M.select_encoder(on_complete)
    local encoders = {
        "av1", "nv_av1", "amd_av1", "intel_av1",
        "h265", "nv_h265", "amd_h265", "intel_h265"
    }

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local cursor = 1

    for i, enc in ipairs(encoders) do
        if enc == state.opts.video_encoder then
            cursor = i
            break
        end
    end

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("enc-up")
        mp.remove_key_binding("enc-down")
        mp.remove_key_binding("enc-enter")
        mp.remove_key_binding("enc-esc")
        if on_complete then on_complete() end
    end

    local function draw()
        local text = "{\\an7}{\\fnmonospace}{\\fs18}{\\b1}Select Video Encoder{\\b0}\\N(Up/Down to navigate, Enter to select, Esc to cancel)\\N\\N"
        for i, enc in ipairs(encoders) do
            local prefix   = (i == cursor) and "{\\c&H00FFFF&}➤ " or "  "
            local selected = (enc == state.opts.video_encoder) and "{\\c&H00FF00&}[Active]" or ""
            text = text .. string.format("%s%s %s{\\c&HFFFFFF&}\\N", prefix, enc, selected)
        end
        ov.data = text
        ov:update()
    end

    mp.add_forced_key_binding("UP", "enc-up", function()
        if cursor > 1 then cursor = cursor - 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("DOWN", "enc-down", function()
        if cursor < #encoders then cursor = cursor + 1; draw() end
    end, {repeatable = true})

    mp.add_forced_key_binding("ENTER", "enc-enter", function()
        local new_enc = encoders[cursor]
        if new_enc ~= state.opts.video_encoder then
            state.opts.video_encoder = new_enc

            -- Auto-adjust preset to an archival safe default for the new encoder
            if new_enc == "av1" then
                state.opts.preset = 4
            elseif new_enc == "h265" then
                state.opts.preset = "slow"
            elseif new_enc:match("^nv_") then
                state.opts.preset = "p7"
            elseif new_enc:match("^amd_") then
                state.opts.preset = "quality"
            elseif new_enc:match("^intel_") then
                state.opts.preset = "veryslow"
            end

            -- Safely fix out-of-bounds quality if switching to Intel
            if new_enc:match("^intel_") and (tonumber(state.opts.quality) or 0) < 1 then
                state.opts.quality = 1
            end
        end
        common.notify("Encoder set to: " .. state.opts.video_encoder)
        cleanup()
    end)

    mp.add_forced_key_binding("ESC", "enc-esc", cleanup)

    draw()
end

function M.show_stats()
    local _, msg_osd_body = stats.get_formatted_stats()
    local full_osd = "{\\an7}{\\fnmonospace}{\\fs12}{\\b1}Tachytome Stats{\\b0}\\N\\N" .. msg_osd_body

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    mp.set_osd_ass(0, 0, full_osd)
    mp.add_timeout(state.opts.stats_osd_time, function() mp.set_osd_ass(0, 0, "") end)
end

function M.trash_source()
    local current_file = mp.get_property("path")
    if not current_file then return common.notify("No video loaded", true, "error") end
    if not state.trash_path then return common.notify("Trash utility not found", true, "error") end

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    local ov = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup_trash()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("del-y")
        mp.remove_key_binding("del-n")
        mp.remove_key_binding("del-enter")
        mp.remove_key_binding("del-esc")
    end

    ov.data = string.format("{\\an7}{\\fnmonospace}{\\c&H0000FF&}Warning: Move current file to trash?{\\c&HFFFFFF&}\\N%s\\N\\N[ y / Enter ] Yes\\N[ n / Esc ]   No", current_file)
    ov:update()

    local function confirm_trash()
        cleanup_trash()
        common.trash_file(current_file, state.trash_path, function(success)
            if success then common.notify("Trashed source video", true)
            else common.notify("Failed to trash video (File may be in use)", true, "error") end
        end)
    end

    local function cancel_trash()
        cleanup_trash()
        common.notify("Trashing cancelled.")
    end

    mp.add_forced_key_binding("y",     "del-y",     confirm_trash)
    mp.add_forced_key_binding("ENTER", "del-enter", confirm_trash)
    mp.add_forced_key_binding("n",     "del-n",     cancel_trash)
    mp.add_forced_key_binding("ESC",   "del-esc",   cancel_trash)
end

function M.toggle_lossless()
    state.opts.lossless_cut = not state.opts.lossless_cut
    if state.opts.lossless_cut then
        state.opts.accurate_cut = false
        state.opts.combine_audio = false
    end
    common.notify("Lossless Cut: '"  .. tostring(state.opts.lossless_cut)  .. "'")
    common.notify("Accurate Cut: '"  .. tostring(state.opts.accurate_cut)  .. "'")
    common.notify("Combine Audio: '" .. tostring(state.opts.combine_audio) .. "'")
end

function M.toggle_accurate()
    state.opts.accurate_cut = not state.opts.accurate_cut
    if state.opts.accurate_cut then state.opts.lossless_cut = false end
    common.notify("Accurate Cut: '" .. tostring(state.opts.accurate_cut) .. "'")
    common.notify("Lossless Cut: '" .. tostring(state.opts.lossless_cut) .. "'")
end

function M.toggle_combine_audio()
    state.opts.combine_audio = not state.opts.combine_audio
    if state.opts.combine_audio then state.opts.lossless_cut = false end
    common.notify("Combine Audio: '" .. tostring(state.opts.combine_audio) .. "'")
    common.notify("Lossless Cut: '"  .. tostring(state.opts.lossless_cut)  .. "'")
end

function M.toggle_trash_source()
    state.opts.trash_source = not state.opts.trash_source
    common.notify("Trash Source: '" .. tostring(state.opts.trash_source) .. "'")
end

function M.set_space_replacement(on_complete)
    osd_input.get_user_input("Replace spaces with: ", function(input)
        state.opts.space_replacement = input
        common.notify("Space replacement set to: '" .. input .. "'")
        common.notify("Target: " .. M.get_final_path())
        if on_complete then on_complete() end
    end, state.opts.space_replacement, true)
end

function M.get_space_replacement_display()
    local v = state.opts.space_replacement
    if v == "" then return "None" end
    if v == " " then return "Space" end
    return v
end

function M.get_final_path()
    return common.resolve_absolute_path(state.custom_output_name, state.opts)
end

function M.set_path(on_complete)
    local display_path = state.custom_output_name ~= "" and state.custom_output_name or M.get_final_path()
    local binds        = "(Up/Down for history, Enter to confirm, Esc to cancel)"

    osd_input.get_user_input("Output Path: ", function(input)
        if input ~= "" then
            state.custom_output_name = input
            common.add_to_history(state.path_history, input)
            common.notify("Target: " .. M.get_final_path())
        else
            state.custom_output_name = ""
            common.notify("Output path reset to default")
        end
        if on_complete then on_complete() end
    end, display_path, binds, state.path_history)
end

function M.start_render()
    render.start({
        final_output_path   = M.get_final_path(),
        mark_in             = state.mark_in,
        mark_out            = state.mark_out,
        full_input_duration = mp.get_property_number("duration", 0),
        video_encoder       = state.opts.video_encoder,
        accurate_cut        = state.opts.accurate_cut,
        lossless_cut        = state.opts.lossless_cut,
        quality             = state.opts.quality,
        preset              = state.opts.preset,
        combine_audio       = state.opts.combine_audio,
        combined_audio_name = state.opts.combined_audio_name,
        trash_source        = state.opts.trash_source,
        trash_path          = state.trash_path,
        space_replacement   = state.opts.space_replacement,
        show_stats_screen   = state.opts.show_stats_screen,
        show_stats_terminal = state.opts.show_stats_terminal,
        stats_osd_time      = state.opts.stats_osd_time,
        rename_callback     = M.set_path
    })
end

function M.manage_queue(on_complete)
    render.show_queue_manager(on_complete)
end

return M
