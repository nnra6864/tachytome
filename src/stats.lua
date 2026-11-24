local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local theme  = require 'src.theme'
local lang   = require 'src.lang'

local M = {}

local fields = { "input_size", "input_duration", "output_size", "output_duration", "render_time" }

local stats_path  = utils.join_path(common.get_state_dir(), "stats.json")
local backup_path = utils.join_path(common.get_state_dir(), "stats.v1.json")
local broken      = false

local function totals(from)
    local out = {}
    for _, key in ipairs(fields) do
        out[key] = (type(from) == "table" and tonumber(from[key])) or 0
    end
    return out
end

local function add(into, from)
    for _, key in ipairs(fields) do into[key] = into[key] + (from[key] or 0) end
end

local function fresh()
    return { version = 2, renders = totals(), trashed = { after_render = totals(), trash_now = totals() }, kept = {} }
end

local function read_raw(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function write(data)
    if broken then return false end
    local tmp = stats_path .. ".tmp"
    if not common.write_json_file(tmp, data) then
        mp.msg.warn("Could not write stats file: " .. tmp)
        return false
    end
    local ok, err = common.replace_file(tmp, stats_path)
    if not ok then mp.msg.warn("Could not replace stats file: " .. tostring(err)) end
    return ok
end

local function from_v1(parsed)
    local old = totals({
        input_size      = parsed.source_space,
        input_duration  = parsed.source_duration,
        output_size     = parsed.output_space,
        output_duration = parsed.output_duration,
        render_time     = parsed.render_time
    })
    local data = fresh()
    add(data.renders, old)
    add(data.trashed.after_render, old)
    return data
end

local function normalize(parsed)
    local data = fresh()
    data.renders              = totals(parsed.renders)
    local trashed             = type(parsed.trashed) == "table" and parsed.trashed or {}
    data.trashed.after_render = totals(trashed.after_render)
    data.trashed.trash_now    = totals(trashed.trash_now)
    if type(parsed.kept) == "table" then
        for path, entry in pairs(parsed.kept) do
            if type(path) == "string" then data.kept[path] = totals(entry) end
        end
    end
    return data
end

local function load()
    broken        = false
    local content = read_raw(stats_path)
    if not content or content:match("^%s*$") then return fresh() end

    local parsed = utils.parse_json(content)
    if type(parsed) ~= "table" then
        broken = true
        mp.msg.error("Could not parse " .. stats_path .. ", stats won't be saved until it's fixed or removed")
        return fresh()
    end
    if parsed.version then return normalize(parsed) end

    if not utils.file_info(backup_path) then
        local f = io.open(backup_path, "w")
        if not f then
            broken = true
            mp.msg.error("Could not back up " .. stats_path .. " to " .. backup_path .. ", stats won't be saved")
            return from_v1(parsed)
        end
        f:write(content)
        f:close()
    end
    local data = from_v1(parsed)
    write(data)
    return data
end

local function find_kept(data, path)
    if data.kept[path] then return path end
    for key in pairs(data.kept) do
        if common.same_path(key, path) then return key end
    end
end

local function changed(data)
    write(data)
    if M.on_update then M.on_update() end
end

M.on_update = nil

function M.record_render(r)
    local data = load()
    add(data.renders, totals(r))

    for key in pairs(data.kept) do
        if not common.same_path(key, r.input_file) and not utils.file_info(key) then data.kept[key] = nil end
    end
    if r.input_file then
        local key   = find_kept(data, r.input_file) or r.input_file
        local entry = data.kept[key] or totals({ input_size = r.input_size, input_duration = r.input_duration })
        add(entry, totals({ output_size = r.output_size, output_duration = r.output_duration, render_time = r.render_time }))
        data.kept[key] = entry
    end
    changed(data)
end

function M.record_trash(path, how)
    local data = load()
    local key  = find_kept(data, path)
    if not key then return end
    add(data.trashed[how] or data.trashed.after_render, data.kept[key])
    data.kept[key] = nil
    changed(data)
end

function M.totals(scope)
    local data = load()
    if scope == "all" then return data.renders end
    local out = totals()
    add(out, data.trashed.after_render)
    add(out, data.trashed.trash_now)
    out.render_time = data.renders.render_time
    return out
end

function M.get_formatted_stats(t)
    t = totals(t)
    local saved_size = t.input_size - t.output_size
    local saved_time = math.max(0, t.input_duration - t.output_duration)

    local lines = {
        { label = lang.t("stats_input_size"),  value = common.format_bytes(t.input_size) },
        { label = lang.t("stats_output_size"), value = common.format_bytes(t.output_size) },
        { label = lang.t("stats_saved_size"),  value = common.format_bytes(saved_size) },
        { separator = true },
        { label = lang.t("stats_input_time"),  value = common.format_duration(t.input_duration) },
        { label = lang.t("stats_output_time"), value = common.format_duration(t.output_duration) },
        { label = lang.t("stats_saved_time"),  value = common.format_duration(saved_time) },
        { separator = true },
        { label = lang.t("stats_render_time"), value = common.format_duration(t.render_time) }
    }

    local max_label_len = 0
    local max_val_len   = 0
    for _, item in ipairs(lines) do
        if not item.separator then
            if common.text_len(item.label) > max_label_len then max_label_len = common.text_len(item.label) end
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
            local pad_len = (max_label_len - common.text_len(item.label)) + (max_val_len - #item.value) + 1

            console_str = console_str .. string.format("%s:%s%s\n", item.label, string.rep(" ", pad_len), item.value)
            osd_str     = osd_str .. string.format("%s:%s%s\\N", l(item.label), string.rep("\\h", pad_len), v(item.value))
        end
    end

    console_str = console_str:gsub("\n$", "")
    osd_str     = osd_str:gsub("\\N$", "")

    return console_str, osd_str, separator_len
end

return M
