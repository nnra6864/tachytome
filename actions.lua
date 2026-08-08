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

function M.set_crf(on_complete)
    osd_input.get_user_input("CRF (0-63): ", function(input)
        local num = tonumber(input)
        if num and num >= 0 and num <= 63 then
            state.opts.crf = num
            common.notify("CRF: " .. state.opts.crf)
        else
            common.notify("Invalid CRF, keeping: " .. state.opts.crf, true, "warn")
        end
        if on_complete then on_complete() end
    end, tostring(state.opts.crf), true)
end

function M.set_path(on_complete)
    local display_path = state.custom_output_name ~= "" and state.custom_output_name or common.resolve_absolute_path("", state.opts)
    osd_input.get_user_input("Output Path: ", function(input)
        if input ~= "" then
            state.custom_output_name = common.resolve_absolute_path(input, state.opts)
            common.notify("Target: " .. state.custom_output_name)
        else
            state.custom_output_name = ""
            common.notify("Output path reset to default")
        end
        if on_complete then on_complete() end
    end, display_path, true)
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
            if success then common.notify("Trashed original video", true)
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

function M.start_render()
    local final_output = state.custom_output_name ~= "" and state.custom_output_name or common.resolve_absolute_path("", state.opts)

    render.start({
        final_output_path   = final_output,
        mark_in             = state.mark_in,
        mark_out            = state.mark_out,
        full_input_duration = mp.get_property_number("duration", 0),
        video_encoder       = state.opts.video_encoder,
        accurate_cut        = state.opts.accurate_cut,
        lossless_cut        = state.opts.lossless_cut,
        crf                 = state.opts.crf,
        preset              = state.opts.preset,
        combine_audio       = state.opts.combine_audio,
        combined_audio_name = state.opts.combined_audio_name,
        trash_original      = state.opts.trash_original,
        trash_path          = state.trash_path,
        space_replacement   = state.opts.space_replacement,
        conflict_suffix     = state.opts.conflict_suffix,
        show_stats_screen   = state.opts.show_stats_screen,
        show_stats_terminal = state.opts.show_stats_terminal,
        stats_osd_time      = state.opts.stats_osd_time
    })
    state.custom_output_name = ""
end

function M.manage_queue(on_complete)
    render.show_queue_manager(on_complete)
end

return M
