local utils  = require 'mp.utils'
local common = require 'src.common'
local theme  = require 'src.theme'

local M = {}

local function get_stats_path()
    return utils.join_path(common.get_data_dir(), "stats.json")
end

function M.read_stats()
    local stats = { source_space = 0, output_space = 0, source_duration = 0, output_duration = 0, render_time = 0 }
    local f = io.open(get_stats_path(), "r")
    if f then
        local parsed = utils.parse_json(f:read("*all"))
        if parsed then
            for k, v in pairs(parsed) do stats[k] = v end
        end
        f:close()
    end
    return stats
end

function M.write_stats(stats)
    local f = io.open(get_stats_path(), "w")
    if f then
        f:write(utils.format_json(stats))
        f:close()
    end
end

function M.update_stats(input_bytes, output_bytes, full_input_duration, output_clip_duration, render_wall_time)
    local stats = M.read_stats()
    stats.source_space    = (stats.source_space or 0) + (input_bytes or 0)
    stats.output_space    = (stats.output_space or 0) + (output_bytes or 0)
    stats.source_duration = (stats.source_duration or 0) + (full_input_duration or 0)
    stats.output_duration = (stats.output_duration or 0) + (output_clip_duration or 0)
    stats.render_time     = (stats.render_time or 0) + (render_wall_time or 0)
    M.write_stats(stats)
    return stats
end

function M.get_formatted_stats(stats_data)
    stats_data = stats_data or M.read_stats()

    local s_processed = stats_data.source_space or 0
    local s_output    = stats_data.output_space or 0
    local s_in_dur    = stats_data.source_duration or 0
    local s_out_dur   = stats_data.output_duration or 0
    local s_render    = stats_data.render_time or 0

    local delta_bytes  = s_processed - s_output
    local cut_duration = s_in_dur - s_out_dur
    if cut_duration < 0 then cut_duration = 0 end

    local lines = {
        { label = "Source Space", value = common.format_bytes(s_processed) },
        { label = "Output Space", value = common.format_bytes(s_output) },
        { label = "Saved Space",  value = common.format_bytes(delta_bytes) },
        { separator = true },
        { label = "Source Time",  value = common.format_duration(s_in_dur) },
        { label = "Output Time",  value = common.format_duration(s_out_dur) },
        { label = "Saved Time",   value = common.format_duration(cut_duration) },
        { separator = true },
        { label = "Render Time",  value = common.format_duration(s_render) }
    }

    local max_label_len = 0
    local max_val_len = 0
    for _, item in ipairs(lines) do
        if not item.separator then
            if #item.label > max_label_len then max_label_len = #item.label end
            if #item.value > max_val_len then max_val_len = #item.value end
        end
    end

    local separator_len = max_label_len + 2 + max_val_len
    local dynamic_separator = string.rep("-", separator_len)

    local console_str = ""
    local osd_str     = ""
    local function l(lab) return string.format("%s%s%s", theme.c("text_color"), lab, theme.reset()) end
    local function v(val) return string.format("%s%s%s", theme.c("value_color"), tostring(val), theme.reset()) end

    for _, item in ipairs(lines) do
        if item.separator then
            console_str = console_str .. dynamic_separator .. "\n"
            osd_str     = osd_str     .. dynamic_separator .. "\\N"
        else
            local pad_len     = max_label_len - #item.label
            local console_pad = string.rep(" ", pad_len + 1)

            local osd_pad_len = max_val_len - #item.value
            local osd_pad     = string.rep("\\h", osd_pad_len)

            console_str = console_str .. string.format("%s:%s%s\n", item.label, console_pad, item.value)
            osd_str     = osd_str .. string.format("%s: %s%s\\N", l(item.label), v(item.value), osd_pad)
        end
    end

    console_str = console_str:gsub("\n$", "")
    osd_str     = osd_str:gsub("\\N$", "")

    return console_str, osd_str, separator_len
end

return M
