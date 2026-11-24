local common     = require 'src.common'
local conf       = require 'src.conf'
local easing     = require 'src.easing'
local resolution = require 'src.resolution'
local text_edit  = require 'src.text_edit'
local menus      = require 'src.menus'
local lang       = require 'src.lang'

local M = {}

local svt   = {}
local x26x  = { "placebo", "veryslow", "slower", "slow", "medium", "fast", "faster", "veryfast", "superfast", "ultrafast" }
local nv    = { "p7", "p6", "p5", "p4", "p3", "p2", "p1" }
local amd   = { "quality", "balanced", "speed" }
local intel = { "veryslow", "slower", "slow", "medium", "fast", "faster", "veryfast" }
for i = 0, 13 do svt[#svt + 1] = tostring(i) end

M.encoders = {
    { name = "av1",        family = "av1",  quality = 35, min = 0, max = 63, preset = "4",        presets = svt },
    { name = "nv_av1",     family = "av1",  quality = 25, min = 0, max = 63, preset = "p7",       presets = nv },
    { name = "amd_av1",    family = "av1",  quality = 25, min = 0, max = 51, preset = "quality",  presets = amd },
    { name = "intel_av1",  family = "av1",  quality = 25, min = 1, max = 51, preset = "veryslow", presets = intel },
    { name = "h265",       family = "h265", quality = 20, min = 0, max = 51, preset = "slower",   presets = x26x },
    { name = "nv_h265",    family = "h265", quality = 20, min = 0, max = 51, preset = "p7",       presets = nv },
    { name = "amd_h265",   family = "h265", quality = 20, min = 0, max = 51, preset = "quality",  presets = amd },
    { name = "intel_h265", family = "h265", quality = 20, min = 1, max = 51, preset = "veryslow", presets = intel },
    { name = "h264",       family = "h264", quality = 20, min = 0, max = 51, preset = "slower",   presets = x26x },
    { name = "nv_h264",    family = "h264", quality = 20, min = 0, max = 51, preset = "p7",       presets = nv },
    { name = "amd_h264",   family = "h264", quality = 20, min = 0, max = 51, preset = "quality",  presets = amd },
    { name = "intel_h264", family = "h264", quality = 20, min = 1, max = 51, preset = "veryslow", presets = intel }
}

local by_name = {}
for _, e in ipairs(M.encoders) do by_name[e.name] = e end

function M.encoder(name)
    return by_name[tostring(name):lower()] or by_name.av1
end

function M.encoder_names()
    local names = {}
    for i, e in ipairs(M.encoders) do names[i] = e.name end
    return names
end

function M.quality_label(e)
    if e.name:match("^intel_") then return lang.t("quality_global") end
    if e.name:match("^nv_") or e.name:match("^amd_") then return "CQ" end
    return "CRF"
end

function M.encoder_detail(e)
    if e.name == e.family then return lang.t("encoder_" .. e.family) end
    return lang.t("encoder_gpu", { family = e.family })
end

local inherit = {
    start_in_easing  = true,
    start_out_easing = true
}

local choices = {
    container        = common.containers,
    cursor_style     = text_edit.cursor_styles,
    tracks_type      = { "audio", "video" },
    stats_scope      = { "trashed", "all" },
    resolution_mode  = resolution.modes,
    scaler_down      = resolution.scalers,
    scaler_up        = resolution.scalers,
    flash_in_easing  = easing.names,
    flash_out_easing = easing.names,
    start_in_easing  = easing.names,
    start_out_easing = easing.names,
    selected_menu    = function() return menus.names() end,
    language         = function()
        local codes = { "auto" }
        for _, code in ipairs(lang.available()) do codes[#codes + 1] = code end
        return codes
    end
}

function M.choices(key)
    local list = choices[key]
    if type(list) == "function" then return list() end
    return list
end

local function is_easing(key)
    return choices[key] == easing.names
end

function M.typed(key)
    return key == "container" or is_easing(key)
end

M.ranges = {
    font_size          = { min = 1 },
    small_font_size    = { min = 1 },
    glow_size          = { min = 0 },
    glow_blur          = { min = 0, max = 1 },
    cursor_glow_size   = { min = 0 },
    cursor_glow_blur   = { min = 0, max = 1 },
    stats_osd_time     = { min = 0 },
    flash_in_duration  = { min = 0 },
    flash_out_duration = { min = 0 },
    start_stagger      = { min = 0 },
    start_in_duration  = { min = -1 },
    start_out_duration = { min = -1 }
}

M.ffmpeg_colors = { pad_color = true }

local families = { "av1", "h265", "h264" }

function M.describe(key, encoder)
    local out = {}
    for _, line in ipairs(lang.lines("opt_" .. key)) do out[#out + 1] = line end
    local e = M.encoder(encoder)
    if key == "video_encoder" then
        for _, family in ipairs(families) do out[#out + 1] = string.format("  %-5s %s", family, lang.t("encoder_" .. family)) end
    elseif key == "quality" then
        out[#out + 1] = lang.t("value_set", { label = e.name, value = lang.t("hint_quality", { label = M.quality_label(e), min = e.min, max = e.max, range = M.range_hint(e), recommended = e.quality }) })
    elseif key == "preset" then
        out[#out + 1] = lang.t("preset_list", { encoder = e.name, list = table.concat(e.presets, ", "), recommended = e.preset })
    end
    return out
end

function M.section(key)
    local id = conf.section(key)
    return id and lang.t("section_" .. id)
end

function M.range_hint(range)
    if range.max then return lang.t("hint_range", { min = range.min, max = range.max }) end
    return lang.t("hint_min", { min = range.min })
end

function M.hint(key)
    if M.ranges[key] then return M.range_hint(M.ranges[key]) end
    if is_easing(key) then return lang.t("hint_easing") end
    return nil
end

function M.valid(key, val)
    local range = M.ranges[key]
    if range then
        local n = tonumber(val)
        return n ~= nil and n >= range.min and (not range.max or n <= range.max)
    end
    if is_easing(key) then return (inherit[key] and val == "") or easing.parse(val) ~= nil end
    return true
end

return M
