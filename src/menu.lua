local mp      = require 'mp'
local common  = require 'src.common'
local state   = require 'src.state'
local actions = require 'src.actions'
local theme   = require 'src.theme'

local M            = {}
local menu_active  = false
local menu_overlay = mp.create_osd_overlay("ass-events")

local function r(val) return string.format("%s%s%s", theme.c("off_color"),   tostring(val), theme.reset()) end
local function g(val) return string.format("%s%s%s", theme.c("on_color"),    tostring(val), theme.reset()) end
local function v(val) return string.format("%s%s%s", theme.c("value_color"), tostring(val), theme.reset()) end

local menu_items = {
    { key = "i", label = "Mark In",  get_val = function() return v(common.format_time(state.mark_in)) end,  action = function() actions.mark(0) end, keep_open = true },
    { key = "o", label = "Mark Out", get_val = function() return v(common.format_time(state.mark_out)) end, action = function() actions.mark(1) end, keep_open = true },

    { separator = true },
    { key = "e", label = "Encoder", get_val = function() return v(state.opts.video_encoder) end, action = function() actions.select_encoder(M.open) end, keep_open = false },
    { key = "q", label = "Quality", get_val = function() return v(state.opts.quality) end,       action = function() actions.set_quality(M.open) end,    keep_open = false },
    { key = "P", label = "Preset",  get_val = function() return v(state.opts.preset) end,        action = function() actions.set_preset(M.open) end,     keep_open = false },

    { separator = true },
    { key = "l", label = "Lossless Cut",  get_val = function() return state.opts.lossless_cut and g("ON") or r("OFF") end,  action = actions.toggle_lossless,      keep_open = true },
    { key = "a", label = "Accurate Cut",  get_val = function() return state.opts.accurate_cut and g("ON") or r("OFF") end,  action = actions.toggle_accurate,      keep_open = true },
    { key = "c", label = "Combine Audio", get_val = function() return state.opts.combine_audio and g("ON") or r("OFF") end, action = actions.toggle_combine_audio, keep_open = true },
    { key = "t", label = "Trash Source",  get_val = function() return state.opts.trash_source and g("ON") or r("OFF") end,  action = actions.toggle_trash_source,  keep_open = true },

    { separator = true },
    { key = "_", label = "Space Replacement", get_val = function() return v(actions.get_space_replacement_display()) end,       action = function() actions.set_space_replacement(M.open) end, keep_open = false },
    { key = "p", label = "Path",              get_val = function() return v(actions.get_final_path()) end,                      action = function() actions.set_path(M.open) end,              keep_open = false },

    { separator = true },
    { key = "g",     label = "Go to",            action = function() actions.goto_prompt(M.open) end,  keep_open = false },
    { key = "ENTER", label = "Render",           action = function() actions.start_render(M.open) end, keep_open = false },
    { key = "r",     label = "Render Queue",     action = function() actions.manage_queue(M.open) end, keep_open = false },
    { key = "DEL",   label = "Trash Source Now", action = function() actions.trash_source(M.open) end, keep_open = false },
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
    local text = string.format("%s%s%s%sTachytome%s\\N\\N", theme.align(7), theme.f(), theme.b(true), theme.c("text_color"), theme.b(false))
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

function M.refresh()
    if menu_active then draw() end
end

return M
