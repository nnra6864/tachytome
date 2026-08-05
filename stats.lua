local mp = require 'mp'
local utils = require 'mp.utils'
local common = require 'common'

local M = {}

local function get_stats_path()
    return mp.command_native({"expand-path", "~~/tachytome_stats.json"})
end

function M.read_stats()
    local stats = {
        processed = 0,
        output = 0,
        input_duration = 0,
        output_duration = 0,
        render_time = 0
    }
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
    stats.processed = (stats.processed or 0) + (input_bytes or 0)
    stats.output = (stats.output or 0) + (output_bytes or 0)
    stats.input_duration = (stats.input_duration or 0) + (full_input_duration or 0)
    stats.output_duration = (stats.output_duration or 0) + (output_clip_duration or 0)
    stats.render_time = (stats.render_time or 0) + (render_wall_time or 0)
    M.write_stats(stats)
    return stats
end

function M.get_lifetime_stats_string(stats)
    stats = stats or M.read_stats()
    local delta_bytes = stats.processed - stats.output
    local cut_duration = (stats.input_duration or 0) - (stats.output_duration or 0)
    if cut_duration < 0 then cut_duration = 0 end

    return string.format(
        "Total Processed: %s\nTotal Output: %s\nLifetime Space Saved: %s\n--------------------------\nSource Video Time: %s\nOutput Video Time: %s\nTime Cut: %s\nTotal Encoding Time: %s",
        common.format_bytes(stats.processed),
        common.format_bytes(stats.output),
        common.format_bytes(delta_bytes),
        common.format_duration(stats.input_duration),
        common.format_duration(stats.output_duration),
        common.format_duration(cut_duration),
        common.format_duration(stats.render_time)
    )
end

return M
