local mp         = require 'mp'
local common     = require 'src.common'
local ui_input   = require 'src.ui_input'
local ui_list    = require 'src.ui_list'
local ui_confirm = require 'src.ui_confirm'
local render     = require 'src.render'
local stats      = require 'src.stats'
local state      = require 'src.state'
local notify     = require 'src.notify'
local theme      = require 'src.theme'
local ui_goto = require 'src.ui_goto'

local M = {}

function M.goto_prompt(on_complete)
    ui_goto.show(on_complete)
end

function M.mark(place)
    local time = mp.get_property_number("time-pos", 0)
    if place == 0 then
        state.mark_in = time
        notify.show("In: " .. common.format_time(time))
    elseif place == 1 then
        state.mark_out = time
        notify.show("Out: " .. common.format_time(time))
    end
end

function M.set_quality(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local min_val = 0
    local max_val = 51
    local label   = "CRF"

    if enc == "av1" then max_val = 63
    elseif enc == "h265" then max_val = 51
    elseif enc:match("^intel_") then min_val = 1; label = "Global Quality"
    elseif enc:match("^nv_") or enc:match("^amd_") then label = "CQ" end

    local prompt = string.format("%s (%d-%d) > ", label, min_val, max_val)

    ui_input.get_user_input(prompt, function(input)
        local num = tonumber(input)
        if num and num >= min_val and num <= max_val then
            state.opts.quality = num
            notify.show(label .. ": " .. state.opts.quality)
        else
            notify.show(string.format("Invalid %s, keeping: %s", label, state.opts.quality), true, "warn")
        end
        if on_complete then on_complete() end
    end, tostring(state.opts.quality), true, nil, on_complete)
end

function M.set_preset(on_complete)
    local enc     = state.opts.video_encoder:lower()
    local presets = {}

    if enc == "av1" then presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"}
    elseif enc == "h265" then presets = {"ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow", "placebo"}
    elseif enc:match("^nv_") then presets = {"p1", "p2", "p3", "p4", "p5", "p6", "p7"}
    elseif enc:match("^amd_") then presets = {"speed", "balanced", "quality"}
    elseif enc:match("^intel_") then presets = {"veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"}
    else presets = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13"} end

    ui_list.show("Select Preset for " .. enc, presets, tostring(state.opts.preset), function(val)
        if enc == "av1" then
            state.opts.preset = tonumber(val)
        else
            state.opts.preset = val
        end
        notify.show("Preset set to: " .. tostring(state.opts.preset))
        if on_complete then on_complete() end
    end, on_complete)
end

function M.select_encoder(on_complete)
    local encoders = { "av1", "nv_av1", "amd_av1", "intel_av1", "h265", "nv_h265", "amd_h265", "intel_h265" }

    ui_list.show("Select Video Encoder", encoders, state.opts.video_encoder, function(new_enc)
        if new_enc ~= state.opts.video_encoder then
            state.opts.video_encoder = new_enc

            if new_enc == "av1" then state.opts.preset = 4
            elseif new_enc == "h265" then state.opts.preset = "slow"
            elseif new_enc:match("^nv_") then state.opts.preset = "p7"
            elseif new_enc:match("^amd_") then state.opts.preset = "quality"
            elseif new_enc:match("^intel_") then state.opts.preset = "veryslow" end

            if new_enc:match("^intel_") and (tonumber(state.opts.quality) or 0) < 1 then
                state.opts.quality = 1
            end
        end
        notify.show("Encoder set to: " .. state.opts.video_encoder)
        if on_complete then on_complete() end
    end, on_complete)
end

M.stats_visible = false

function M.toggle_stats()
    M.stats_visible = not M.stats_visible

    if not M.stats_visible then
        mp.set_osd_ass(0, 0, "")
        return
    end

    local msg_title = "Tachytome Stats"
    local msg_body, msg_osd_body, msg_width = stats.get_formatted_stats()
    local pad_len = msg_width - #msg_title
    local pad = string.rep("\\h", pad_len)
    local full_osd = string.format("%s%s%s%s%s%s%s\\N\\N%s", theme.c("text_color"), theme.align(3), theme.f(true), theme.b(true), msg_title, pad, theme.b(false), msg_osd_body)

    notify.show("Tachytome Stats\n" .. msg_body, false)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    mp.set_osd_ass(0, 0, full_osd)
end

function M.trash_source(on_complete)
    local current_file = mp.get_property("path")
    if not current_file then
        notify.show("No video loaded", true, "error")
        if on_complete then on_complete() end
        return
    end
    if not state.trash_path then
        notify.show("Trash utility not found", true, "error")
        if on_complete then on_complete() end
        return
    end

    ui_confirm.show("Move current file to trash?", current_file, function()
        common.trash_file(current_file, state.trash_path, function(success)
            if success then notify.show("Trashed source video", true)
            else notify.show("Failed to trash video (File may be in use)", true, "error") end
        end)
        if on_complete then on_complete() end
    end, function()
        notify.show("Trashing cancelled.")
        if on_complete then on_complete() end
    end)
end

function M.toggle_lossless()
    state.opts.lossless_cut = not state.opts.lossless_cut
    if state.opts.lossless_cut then
        state.opts.accurate_cut = false
        state.opts.combine_audio = false
    end
    notify.show("Lossless Cut: '"  .. tostring(state.opts.lossless_cut)  .. "'")
    notify.show("Accurate Cut: '"  .. tostring(state.opts.accurate_cut)  .. "'")
    notify.show("Combine Audio: '" .. tostring(state.opts.combine_audio) .. "'")
end

function M.toggle_accurate()
    state.opts.accurate_cut = not state.opts.accurate_cut
    if state.opts.accurate_cut then state.opts.lossless_cut = false end
    notify.show("Accurate Cut: '" .. tostring(state.opts.accurate_cut) .. "'")
    notify.show("Lossless Cut: '" .. tostring(state.opts.lossless_cut) .. "'")
end

function M.toggle_combine_audio()
    state.opts.combine_audio = not state.opts.combine_audio
    if state.opts.combine_audio then state.opts.lossless_cut = false end
    notify.show("Combine Audio: '" .. tostring(state.opts.combine_audio) .. "'")
    notify.show("Lossless Cut: '"  .. tostring(state.opts.lossless_cut)  .. "'")
end

function M.toggle_trash_source()
    state.opts.trash_source = not state.opts.trash_source
    notify.show("Trash Source: '" .. tostring(state.opts.trash_source) .. "'")
end

function M.set_space_replacement(on_complete)
    ui_input.get_user_input("Replace spaces with: ", function(input)
        state.opts.space_replacement = input
        notify.show("Space replacement set to: '" .. input .. "'")
        notify.show("Target: " .. M.get_final_path())
        if on_complete then on_complete() end
    end, state.opts.space_replacement, true, nil, on_complete)
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

    ui_input.get_user_input("Output Path > ", function(input)
        if input ~= "" then
            state.custom_output_name = input
            common.add_to_history(state.path_history, input)
            notify.show("Target: " .. M.get_final_path())
        else
            state.custom_output_name = ""
            notify.show("Output path reset to default")
        end
        if on_complete then on_complete() end
    end, display_path, binds, state.path_history, on_complete)
end

function M.start_render(on_complete)
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
        rename_callback     = M.set_path,
        on_complete         = on_complete
    })
end

function M.manage_queue(on_complete)
    render.show_queue_manager(on_complete)
end

return M
