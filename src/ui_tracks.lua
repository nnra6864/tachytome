local mp      = require 'mp'
local common  = require 'src.common'
local tracks  = require 'src.tracks'
local ui_list = require 'src.ui_list'
local state   = require 'src.state'
local notify  = require 'src.notify'
local theme   = require 'src.theme'
local lang    = require 'src.lang'
local ui      = require 'src.ui'

local M = {}

local bindings = { "tr-up", "tr-down", "tr-j", "tr-k", "tr-enter", "tr-a", "tr-v", "tr-search", "tr-esc" }
for i = 1, 10 do bindings[#bindings + 1] = "tr-" .. i end

local function track_label(t, n)
    return t.title or lang.t("tracks_track", { n = n })
end

local function track_details(t)
    local parts = {}
    if t.codec then parts[#parts + 1] = t.codec end
    if t["demux-channel-count"] then parts[#parts + 1] = t["demux-channel-count"] .. "ch" end
    if t["demux-w"] and t["demux-h"] then parts[#parts + 1] = t["demux-w"] .. "x" .. t["demux-h"] end
    if t.lang then parts[#parts + 1] = t.lang end
    return table.concat(parts, " ")
end

local function toggle(val)
    if val then return string.format("%s%s", theme.c("on_color"), state.opts.on_text) end
    return string.format("%s%s", theme.c("off_color"), state.opts.off_text)
end

function M.show(on_close)
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local kind   = state.opts.tracks_type == "video" and "video" or "audio"
    local list   = tracks.list(kind)
    local cursor = 1
    local open_ui

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function draw()
        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_" .. kind))
        local body  = ""
        if #list == 0 then
            body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_" .. kind)), theme.reset())
        else
            local selected  = tracks.selected(kind)
            local max_label = 0
            for i, t in ipairs(list) do max_label = math.max(max_label, common.text_len(track_label(t, i))) end
            body = ui.list(#list, cursor, function(i)
                local label   = track_label(list[i], i)
                local details = track_details(list[i])
                local key     = ui.number_prefix(i)
                local pad     = string.rep("\\h", max_label - common.text_len(label) + 1)
                local line    = string.format("%s%s%s> %s", key, theme.escape(label), pad, toggle(selected[i]))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            end)
        end
        local hints = { { "a", "audio" }, { "v", "video" }, { "0-9/Enter", "toggle" }, { "Up/Down", "navigate" }, { "/", "search" }, { "Esc", "close" } }
        ov.data = ui.title(title) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function switch(to)
        if to == kind then return end
        kind   = to
        list   = tracks.list(kind)
        cursor = 1
        draw()
    end

    local function toggle_track(i)
        if not list[i] then return end
        cursor = i
        local on = tracks.toggle(kind, i)
        notify.show(lang.t("value_set", { label = lang.t("tracks_" .. kind) .. " " .. i, value = lang.t(on and "value_on" or "value_off") }))
        draw()
    end

    local function move_up()
        cursor = ui.wrap(cursor, -1, #list)
        draw()
    end

    local function move_down()
        cursor = ui.wrap(cursor, 1, #list)
        draw()
    end

    local function search()
        local labels = {}
        for i, t in ipairs(list) do
            local details = track_details(t)
            labels[i] = string.format("%d %s", i, track_label(t, i)) .. (details ~= "" and " " .. details or "")
        end
        teardown()
        ui_list.search(string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_" .. kind)), labels, function(i)
            open_ui()
            toggle_track(i)
        end, open_ui)
    end

    local function bind()
        mp.add_forced_key_binding("UP", "tr-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "tr-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("j", "tr-j", move_down, {repeatable = true})
        mp.add_forced_key_binding("k", "tr-k", move_up, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "tr-enter", function() toggle_track(cursor) end)
        mp.add_forced_key_binding("a", "tr-a", function() switch("audio") end)
        mp.add_forced_key_binding("v", "tr-v", function() switch("video") end)
        for i = 1, 10 do
            mp.add_forced_key_binding(ui.number_key(i), "tr-" .. i, function() toggle_track(i) end)
        end
        mp.add_forced_key_binding("/", "tr-search", search)
        mp.add_forced_key_binding("ESC", "tr-esc", cleanup)
    end

    open_ui = function()
        ui.clear_osd()
        active         = true
        state.ui_owner = "tracks"
        bind()
        draw()
    end

    open_ui()
end

return M
