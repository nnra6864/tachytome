local mp      = require 'mp'
local common  = require 'common'
local state   = require 'state'
local actions = require 'actions'

local M            = {}
local menu_active  = false
local menu_overlay = mp.create_osd_overlay("ass-events")

local function r(val) return string.format("{\\c&H0000FF&}%s{\\c&HFFFFFF&}", tostring(val)) end
local function g(val) return string.format("{\\c&H00FF00&}%s{\\c&HFFFFFF&}", tostring(val)) end

local menu_items = {
    { key = "i", label = "Mark In",  get_val = function() return g(common.format_time(state.mark_in)) end,  action = function() actions.mark(0) end, keep_open = true },
    { key = "o", label = "Mark Out", get_val = function() return g(common.format_time(state.mark_out)) end, action = function() actions.mark(1) end, keep_open = true },

    { separator = true },
    { key = "l", label = "Lossless Cut", get_val = function() return state.opts.lossless_cut and g("ON") or r("OFF") end, action = function() state.opts.lossless_cut = not state.opts.lossless_cut end, keep_open = true },
    { key = "e", label = "Encoder",      get_val = function() return g(state.opts.video_encoder) end,                     action = function() actions.select_encoder(M.open) end,                        keep_open = false },
    { key = "q", label = "Quality",      get_val = function() return g(state.opts.quality) end,                           action = function() actions.set_quality(M.open) end,                           keep_open = false },
    { key = "P", label = "Preset",       get_val = function() return g(state.opts.preset) end,                            action = function() actions.set_preset(M.open) end,                            keep_open = false },

    { separator = true },
    { key = "a", label = "Accurate Cut",  get_val = function() return state.opts.accurate_cut and g("ON") or r("OFF") end,  action = function() state.opts.accurate_cut = not state.opts.accurate_cut end,     keep_open = true },
    { key = "c", label = "Combine Audio", get_val = function() return state.opts.combine_audio and g("ON") or r("OFF") end, action = function() state.opts.combine_audio = not state.opts.combine_audio end,   keep_open = true },
    { key = "t", label = "Trash Source",  get_val = function() return state.opts.trash_source and g("ON") or r("OFF") end,  action = function() state.opts.trash_original = not state.opts.trash_original end, keep_open = true },
    { key = "p", label = "Path",          get_val = function()
        local display_name = state.custom_output_name ~= "" and state.custom_output_name or common.resolve_absolute_path("", state.opts)
        return g(display_name)
    end, action = function() actions.set_path(M.open) end, keep_open = false },

    { separator = true },
    { key = "r",     label = "Render Queue",     action = function() actions.manage_queue(M.open) end, keep_open = false },
    { key = "DEL",   label = "Trash Source Now", action = actions.trash_source,                        keep_open = false },
    { key = "ENTER", label = "Render",           action = actions.start_render,                        keep_open = false },
    { key = "s",     label = "Stats",            action = actions.show_stats,                          keep_open = false },

    { separator = true },
    { key = "ESC", label = "Close ", action = function() end, keep_open = false }
}

function M.close()
    if not menu_active then return end
    menu_active = false
    menu_overlay:remove()
    for _, item in ipairs(menu_items) do
        if not item.separator then mp.remove_key_binding("menu-" .. item.key) end
    end
end

local function draw()
    local text = "{\\an7}{\\fnmonospace}{\\fs18}{\\b1}Tachytome{\\b0}\\N\\N"
    local max_key_len = 0
    local max_label_len = 0

    for _, item in ipairs(menu_items) do
        if not item.separator then
            if #item.key > max_key_len then max_key_len = #item.key end
            if item.get_val and #item.label > max_label_len then max_label_len = #item.label end
        end
    end

    for _, item in ipairs(menu_items) do
        if item.separator then
            text = text .. "\\N"
        else
            local key_pad = string.rep("\\h", max_key_len - #item.key)
            local line = string.format("%s[ %s ] %s", key_pad, item.key, item.label)

            if item.get_val then
                local val_pad = string.rep("\\h", max_label_len - #item.label + 1)
                line = line .. val_pad .. item.get_val()
            end

            text = text .. line .. "\\N"
        end
    end

    menu_overlay.data = text
    menu_overlay:update()
end

function M.open()
    if menu_active then M.close() return end
    menu_active = true

    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)

    draw()

    for _, item in ipairs(menu_items) do
        if not item.separator then
            mp.add_forced_key_binding(item.key, "menu-" .. item.key, function()
                if not item.keep_open then M.close() end
                item.action()
                if item.keep_open and menu_active then draw() end
            end)
        end
    end
end

return M
