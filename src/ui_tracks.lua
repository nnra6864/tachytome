local mp          = require 'mp'
local common      = require 'src.common'
local tracks      = require 'src.tracks'
local list_search = require 'src.list_search'
local state       = require 'src.state'
local notify      = require 'src.notify'
local theme       = require 'src.theme'
local lang        = require 'src.lang'
local ui          = require 'src.ui'

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
    ui.clear_osd()
    state.ui_owner = "tracks"

    local ov     = mp.create_osd_overlay("ass-events")
    local active = true
    local kind   = state.opts.tracks_type == "video" and "video" or "audio"
    local list   = tracks.list(kind)
    local cursor = 1
    local search

    local function cleanup()
        if not active then return end
        active         = false
        state.ui_owner = nil
        search.close()
        ov:remove()
        for _, name in ipairs(bindings) do mp.remove_key_binding(name) end
        if on_close then on_close() end
    end

    local function labels()
        local out = {}
        for i, t in ipairs(list) do
            local details = track_details(t)
            out[i] = string.format("%d %s", i, track_label(t, i)) .. (details ~= "" and " " .. details or "")
        end
        return out
    end

    local function visible()
        local names = labels()
        return ui.visible(#list, function(i) return search.keep(names[i]) end)
    end

    local function draw()
        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_" .. kind))
        local vis   = visible()
        local body  = ""
        if #list == 0 then
            body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_" .. kind)), theme.reset())
        elseif #vis == 0 then
            body = search.empty()
        else
            if ui.position(vis, cursor) == 0 then cursor = vis[1] end
            local selected  = tracks.selected(kind)
            local max_label = 0
            for i, t in ipairs(list) do max_label = math.max(max_label, common.text_len(track_label(t, i))) end
            body = ui.list(#vis, ui.position(vis, cursor), function(k)
                local i       = vis[k]
                local label   = track_label(list[i], i)
                local details = track_details(list[i])
                local key     = ui.number_prefix(i)
                local pad     = string.rep("\\h", max_label - common.text_len(label) + 1)
                local line    = string.format("%s%s%s> %s", key, theme.escape(label), pad, toggle(selected[i]))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            end)
        end
        local hints = search.hints({ { "a", "audio" }, { "v", "video" }, { "0-9/Enter", "toggle" }, { "Up/Down", "navigate" }, { "/", "search" }, { "Esc", "close" } })
        ov.data = search.title(title) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function switch(to)
        if to == kind then return end
        kind   = to
        list   = tracks.list(kind)
        cursor = 1
        search.clear()
    end

    local function toggle_track(i)
        if not list[i] then return end
        cursor = i
        local on = tracks.toggle(kind, i)
        notify.show(lang.t("value_set", { label = lang.t("tracks_" .. kind) .. " " .. i, value = lang.t(on and "value_on" or "value_off") }))
        draw()
    end

    local function move(delta)
        cursor = ui.step(visible(), cursor, delta)
        draw()
    end

    search = list_search.new({
        prefix = "tr",
        labels = labels,
        redraw = draw,
        move   = move,
        pick   = toggle_track
    })

    mp.add_forced_key_binding("UP", "tr-up", function() move(-1) end, {repeatable = true})
    mp.add_forced_key_binding("DOWN", "tr-down", function() move(1) end, {repeatable = true})
    mp.add_forced_key_binding("j", "tr-j", function() move(1) end, {repeatable = true})
    mp.add_forced_key_binding("k", "tr-k", function() move(-1) end, {repeatable = true})
    mp.add_forced_key_binding("ENTER", "tr-enter", function()
        if #visible() > 0 then toggle_track(cursor) end
    end)
    mp.add_forced_key_binding("a", "tr-a", function() switch("audio") end)
    mp.add_forced_key_binding("v", "tr-v", function() switch("video") end)
    for i = 1, 10 do
        mp.add_forced_key_binding(ui.number_key(i), "tr-" .. i, function() toggle_track(i) end)
    end
    mp.add_forced_key_binding("/", "tr-search", search.start)
    mp.add_forced_key_binding("ESC", "tr-esc", function()
        if search.filtering() then return search.clear() end
        cleanup()
    end)
    draw()
end

return M
