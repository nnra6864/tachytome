local mp       = require 'mp'
local common   = require 'src.common'
local tracks   = require 'src.tracks'
local ui_input = require 'src.ui_input'
local ui_list  = require 'src.ui_list'
local state    = require 'src.state'
local notify   = require 'src.notify'
local theme    = require 'src.theme'
local lang     = require 'src.lang'
local ui       = require 'src.ui'

local M = {}

local bindings = { "up", "down", "j", "k", "move-up", "move-down", "J", "K", "enter", "a", "v", "s", "n", "o", "d", "esc" }
local picks    = { "up", "down", "j", "k", "enter", "A", "esc" }
for i = 1, 10 do
    bindings[#bindings + 1] = tostring(i)
    picks[#picks + 1]       = tostring(i)
end

local function track_label(entry, track)
    if entry.kind == "mix" then return entry.name end
    return track and track.title or lang.t("tracks_track", { n = entry.n })
end

local function track_details(entry, track)
    if entry.kind == "mix" then
        local inputs = {}
        for _, e in ipairs(entry.inputs) do inputs[#inputs + 1] = tracks.entry_label(e) end
        return lang.t("tracks_mix_of", { list = table.concat(inputs, "+") })
    end
    if not track then return "" end
    local parts = {}
    if track.codec then parts[#parts + 1] = track.codec end
    if track["demux-channel-count"] then parts[#parts + 1] = track["demux-channel-count"] .. "ch" end
    if track["demux-w"] and track["demux-h"] then parts[#parts + 1] = track["demux-w"] .. "x" .. track["demux-h"] end
    if track.lang then parts[#parts + 1] = track.lang end
    return table.concat(parts, " ")
end

local function origin(entry)
    if entry.kind == "mix" then return track_details(entry) end
    return lang.t("tracks_source", { n = entry.n })
end

local function toggle(val)
    if val then return string.format("%s%s", theme.c("on_color"), state.opts.on_text) end
    return string.format("%s%s", theme.c("off_color"), state.opts.off_text)
end

local function pad(text, width)
    return theme.escape(text) .. string.rep("\\h", width - common.text_len(text))
end

local function labels(present)
    local out = {}
    for _, e in ipairs(present) do out[#out + 1] = tracks.entry_label(e) end
    if #out == 0 then return lang.t("value_none") end
    return table.concat(out, ", ")
end

local function splice(list, at, remove, insert)
    local out = {}
    for i = 1, at - 1 do out[#out + 1] = list[i] end
    for _, item in ipairs(insert) do out[#out + 1] = item end
    for i = at + remove, #list do out[#out + 1] = list[i] end
    return out
end

local function summary(text)
    local result, err = tracks.build(text, #tracks.list("audio"), #tracks.list("video"))
    if not result then return err end
    return lang.t("tracks_in_out", { input = #tracks.list("audio"), output = #result.audio })
end

function M.show(on_close)
    local ov     = mp.create_osd_overlay("ass-events")
    local active = false
    local kind   = state.opts.tracks_type == "video" and "video" or "audio"
    local cursor = 1
    local rows   = {}
    local chain  = nil
    local err    = nil
    local open_ui
    local open_picker

    local function remove_bindings()
        for _, name in ipairs(bindings) do mp.remove_key_binding("tr-" .. name) end
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        ov:remove()
        remove_bindings()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function save()
        state.tracks = tracks.format(chain)
    end

    local function rebuild()
        chain, err = tracks.parse(state.tracks)
        rows       = {}
        if kind == "video" then
            for k, row in ipairs(tracks.rows("video") or {}) do rows[k] = { kind = "track", row = row, k = k } end
        else
            rows[1] = { kind = "chain" }
            if chain then
                local audio                = tracks.list("audio")
                local list, rerr           = tracks.rows("audio")
                local present, perr, steps = tracks.run(chain.layers, #audio)
                err                        = rerr or perr
                if list and #list > 0 then
                    rows[#rows + 1] = { kind = "gap" }
                    rows[#rows + 1] = { kind = "header", key = "tracks_picks" }
                    for k, row in ipairs(list) do rows[#rows + 1] = { kind = "track", row = row, k = k } end
                end
                if #chain.layers > 0 then
                    rows[#rows + 1] = { kind = "gap" }
                    rows[#rows + 1] = { kind = "header", key = "tracks_layers" }
                    for i in ipairs(chain.layers) do
                        local step      = steps and steps[i]
                        rows[#rows + 1] = { kind = "layer", index = i, step = step, failed = not present and not step and i == #(steps or {}) + 1 }
                    end
                end
                rows[#rows + 1] = { kind = "gap" }
                rows[#rows + 1] = { kind = "header", key = "tracks_output" }
                if not present then
                    rows[#rows + 1] = { kind = "note", text = err, color = "error_color" }
                elseif #present == 0 then
                    rows[#rows + 1] = { kind = "note", text = lang.t("tracks_no_output"), color = "dim_text_color" }
                end
                for k, e in ipairs(present or {}) do rows[#rows + 1] = { kind = "out", entry = e, track = e.kind == "source" and audio[e.n] or nil, k = k } end
            end
        end
        if cursor > #rows then cursor = #rows end
        if cursor < 1 then cursor = 1 end
    end

    local function navigable()
        return ui.visible(#rows, function(i)
            local k = rows[i].kind
            return k == "chain" or k == "track" or k == "layer"
        end)
    end

    local function fix_cursor()
        local nav = navigable()
        if #nav > 0 and ui.position(nav, cursor) == 0 then cursor = nav[1] end
    end

    local function draw()
        local widths = { track = 0, layer = 0, out = 0 }
        for _, row in ipairs(rows) do
            if row.kind == "track" then
                widths.track = math.max(widths.track, common.text_len(track_label(row.row.entry, row.row.track)))
            elseif row.kind == "layer" then
                widths.layer = math.max(widths.layer, common.text_len(tracks.layer_text(chain.layers[row.index])))
            elseif row.kind == "out" then
                widths.out = math.max(widths.out, common.text_len(track_label(row.entry, row.track)))
            end
        end

        local body = ui.list(#rows, cursor, function(i)
            local row = rows[i]
            if row.kind == "gap" then
                return ""
            elseif row.kind == "header" then
                return string.format("%s%s", theme.c("dim_text_color"), theme.escape(lang.t(row.key)))
            elseif row.kind == "note" then
                return string.format("%s%s", theme.c(row.color), theme.escape(row.text or ""))
            elseif row.kind == "chain" then
                local text = state.tracks ~= "" and state.tracks or lang.t("value_none")
                return string.format("%s > %s%s", theme.escape(lang.t("tracks_chain")), theme.c("value_color"), theme.escape(text))
            elseif row.kind == "track" then
                local entry   = row.row.entry
                local details = track_details(entry, row.row.track)
                local line    = string.format("%s%s\\h> %s", ui.number_prefix(row.k), pad(track_label(entry, row.row.track), widths.track), toggle(row.row.on))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            elseif row.kind == "layer" then
                local text = pad(tracks.layer_text(chain.layers[row.index]), widths.layer)
                if row.step then return string.format("\\h%s\\h\\h%s-> %s", text, theme.c("dim_text_color"), theme.escape(labels(row.step))) end
                if row.failed then return string.format("\\h%s\\h\\h%s!", text, theme.c("error_color")) end
                return "\\h" .. text
            end
            local label = pad(track_label(row.entry, row.track), widths.out)
            if row.entry.kind == "mix" then label = theme.c("value_color") .. label .. theme.c("text_color") end
            local details = row.entry.kind == "mix" and "" or track_details(row.entry, row.track)
            local tail    = details ~= "" and details .. ", " .. origin(row.entry) or origin(row.entry)
            return string.format("\\h%d %s\\h\\h%s%s", row.k, label, theme.c("dim_text_color"), theme.escape(tail))
        end)

        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_" .. kind))
        local head  = ui.title(title)
        local hints
        if kind == "video" then
            if #rows == 0 then body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_video")), theme.reset()) end
            hints = { { "0-9/Enter", "toggle" }, { "Up/Down", "navigate" }, { "a", "audio" }, { "Esc", "close" } }
        else
            local sum = chain and summary(state.tracks) or err
            if sum and sum ~= "" then head = head .. ui.dim(sum) end
            local row = rows[cursor]
            hints     = { { "Up/Down", "navigate" }, { "Enter", "edit" }, { "a", "add" }, { "v", "video" }, { "Esc", "close" } }
            if row and row.kind == "track" then
                hints = { { "0-9/Enter", "toggle" }, { "Up/Down", "navigate" }, { "a", "add" }, { "v", "video" }, { "Esc", "close" } }
            elseif row and row.kind == "layer" then
                local layer = chain.layers[row.index]
                hints       = { { "Up/Down", "navigate" }, { "Enter", "edit" }, { "a", "add" } }
                if layer.op ~= "only" then hints[#hints + 1] = { "s", "tracks" } end
                if layer.op == "mix" then
                    hints[#hints + 1] = { "n", "name" }
                    hints[#hints + 1] = { "o", "position" }
                end
                hints[#hints + 1] = { "d", "delete" }
                hints[#hints + 1] = { "Shift+Up/Down", "move" }
                hints[#hints + 1] = { "Esc", "close" }
            end
        end
        ov.data = head .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function same_row(a, b)
        return a.kind == b.kind and a.index == b.index and a.k == b.k
    end

    local function refresh(focus)
        focus = focus or rows[cursor]
        rebuild()
        for i, row in ipairs(rows) do
            if focus and same_row(row, focus) then cursor = i end
        end
        fix_cursor()
        draw()
    end

    local function commit(layers, video)
        chain.layers = layers
        if video then chain.video = video end
        save()
    end

    local function prompt(title, current, hint, history, compose, submit)
        teardown()
        ui_input.show({
            title       = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, title),
            current     = current,
            hint        = hint,
            history     = history,
            allow_space = true,
            on_cancel   = open_ui,
            preview     = function(input)
                local text, cerr = compose(input)
                if not text then return cerr or "" end
                return summary(text)
            end,
            on_submit   = function(input)
                local text, bad = compose(input)
                if not text then
                    notify.show(bad or lang.t("tracks_unknown", { token = input }), true, "warn")
                else
                    if submit then submit(input) end
                    state.tracks = text
                end
                open_ui()
            end
        })
    end

    local function layers_text(input, at, remove)
        local parsed, perr = tracks.parse(input)
        if not parsed then return nil, perr end
        local copy = { layers = splice(chain.layers, at, remove, parsed.layers), video = parsed.video or chain.video }
        return tracks.format(copy)
    end

    local function edit_chain()
        prompt(lang.t("tracks_chain"), state.tracks, lang.t("hint_tracks"), tracks.history, function(input)
            local parsed, perr = tracks.parse(input)
            if not parsed then return nil, perr end
            return tracks.format(parsed)
        end, tracks.remember)
    end

    local function edit_layer(i)
        prompt(lang.t("tracks_layer"), tracks.layer_text(chain.layers[i]), lang.t("hint_tracks"), tracks.history, function(input)
            return layers_text(input, i, 1)
        end, tracks.remember)
    end

    local function edit_mix(i, field)
        local layer = chain.layers[i]
        if layer.op ~= "mix" then return end
        local is_name = field == "name"
        local current = is_name and (layer.name or "") or (layer.at and tostring(layer.at) or "")
        prompt(lang.t(is_name and "tracks_name" or "tracks_position"), current, lang.t(is_name and "hint_tracks_name" or "hint_tracks_at"), nil, function(input)
            local copy  = tracks.parse(state.tracks)
            local mix   = copy.layers[i]
            local value = input:match("^%s*(.-)%s*$")
            if is_name then
                mix.name = value ~= "" and value or nil
            else
                local n = tonumber(value:match("^%d+$") or "")
                if value ~= "" and (not n or n < 1) then return nil end
                mix.at = n
            end
            local text = tracks.format(copy)
            return tracks.parse(text) and text or nil
        end)
    end

    local function toggle_track(k)
        local target
        for _, row in ipairs(rows) do
            if row.kind == "track" and row.k == k then target = row end
        end
        if not target then return end
        local on, terr = tracks.toggle(kind, target.row.entry)
        if on == nil then return notify.show(terr, true, "error") end
        notify.show(lang.t("value_set", { label = lang.t("tracks_" .. kind) .. " " .. track_label(target.row.entry, target.row.track), value = lang.t(on and "value_on" or "value_off") }))
        refresh({ kind = "track", k = k })
    end

    local function edit_row()
        local row = rows[cursor]
        if not row then return end
        if row.kind == "track" then return toggle_track(row.k) end
        if not chain then return edit_chain() end
        if row.kind == "chain" then return edit_chain() end
        if row.kind == "layer" then
            if chain.layers[row.index].op == "only" then return end
            return edit_layer(row.index)
        end
    end

    local function add_layer()
        if kind ~= "audio" then return end
        if not chain then return edit_chain() end
        local row   = rows[cursor]
        local at    = (row and row.kind == "layer") and row.index + 1 or #chain.layers + 1
        local items = { "mix", "keep", "drop", "only", lang.t("tracks_type") }
        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_add"))
        teardown()
        ui_list.show(title, items, nil, function(op)
            if op == lang.t("tracks_type") then
                return prompt(lang.t("tracks_add"), "", lang.t("hint_tracks"), tracks.history, function(input)
                    return layers_text(input, at, 0)
                end, tracks.remember)
            end
            local layer = { op = op }
            if op == "keep" then layer.list = { { kind = "all" } } end
            if op == "drop" then layer.list = { { kind = "none" } } end
            commit(splice(chain.layers, at, 0, { layer }))
            if op == "only" then return open_ui() end
            open_picker(at)
        end, open_ui)
    end

    local function layer_row()
        local row = rows[cursor]
        if kind ~= "audio" or not row or row.kind ~= "layer" then return nil end
        return row.index
    end

    local function delete_layer()
        local i = layer_row()
        if not i then return end
        table.remove(chain.layers, i)
        save()
        refresh()
    end

    local function move_layer(delta)
        local i = layer_row()
        if not i then return end
        local j = i + delta
        if not chain.layers[j] then return end
        chain.layers[i], chain.layers[j] = chain.layers[j], chain.layers[i]
        save()
        refresh({ kind = "layer", index = j })
    end

    local function pick_tracks()
        local i = layer_row()
        if i and chain.layers[i].op ~= "only" then open_picker(i) end
    end

    local function switch(to)
        if to == kind then return end
        kind   = to
        cursor = 1
        refresh()
    end

    open_picker = function(index)
        teardown()
        local audio          = tracks.list("audio")
        local present, names = tracks.run(chain.layers, #audio, index)
        local pov            = mp.create_osd_overlay("ass-events")
        local pcursor        = 1
        local layer          = chain.layers[index]
        local exclude        = tracks.excludes(layer.list)
        local set            = {}
        present              = present or {}
        if layer.list then
            set = names and tracks.resolve(layer.list, present, names) or {}
        else
            for _, e in ipairs(present) do set[e] = true end
        end
        state.ui_owner = "tracks"

        local function close()
            pov:remove()
            for _, name in ipairs(picks) do mp.remove_key_binding("trp-" .. name) end
            state.ui_owner = nil
            open_ui()
        end

        local function write()
            layer.list = tracks.list_for(set, present, exclude, layer.op)
            save()
        end

        local function draw_picker()
            local width = 0
            for _, e in ipairs(present) do width = math.max(width, common.text_len(track_label(e, audio[e.n]))) end
            local body = ui.list(#present, pcursor, function(k)
                local e       = present[k]
                local details = track_details(e, e.kind == "source" and audio[e.n] or nil)
                local line    = string.format("%s%s\\h> %s", ui.number_prefix(k), pad(track_label(e, audio[e.n]), width), toggle(set[e] == true))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            end)
            if #present == 0 then body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_audio")), theme.reset()) end
            local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, tracks.layer_text(layer))
            local head  = ui.title(title) .. ui.dim(lang.t(exclude and "tracks_all_except" or "tracks_include") .. ", " .. summary(state.tracks))
            local hints = { { "0-9/Enter", "toggle" }, { "Up/Down", "navigate" }, { "A", "mode" }, { "Esc", "back" } }
            pov.data    = head .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
            pov:update()
        end

        local function flip(k)
            local e = present[k]
            if not e then return end
            pcursor = k
            set[e]  = not set[e] or nil
            write()
            draw_picker()
        end

        local function move(delta)
            if #present == 0 then return end
            pcursor = ui.wrap(pcursor, delta, #present)
            draw_picker()
        end

        mp.add_forced_key_binding("UP", "trp-up", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "trp-down", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "trp-k", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "trp-j", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "trp-enter", function() flip(pcursor) end)
        mp.add_forced_key_binding("A", "trp-A", function()
            exclude = not exclude
            write()
            draw_picker()
        end)
        for n = 1, 10 do
            mp.add_forced_key_binding(ui.number_key(n), "trp-" .. n, function() flip(n) end)
        end
        mp.add_forced_key_binding("ESC", "trp-esc", close)
        draw_picker()
    end

    local function bind()
        local function move(delta)
            cursor = ui.step(navigable(), cursor, delta)
            draw()
        end

        mp.add_forced_key_binding("UP", "tr-up", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "tr-down", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "tr-k", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "tr-j", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+UP", "tr-move-up", function() move_layer(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+DOWN", "tr-move-down", function() move_layer(1) end, {repeatable = true})
        mp.add_forced_key_binding("K", "tr-K", function() move_layer(-1) end, {repeatable = true})
        mp.add_forced_key_binding("J", "tr-J", function() move_layer(1) end, {repeatable = true})
        mp.add_forced_key_binding("ENTER", "tr-enter", edit_row)
        mp.add_forced_key_binding("a", "tr-a", function()
            if kind == "video" then return switch("audio") end
            add_layer()
        end)
        mp.add_forced_key_binding("v", "tr-v", function() switch("video") end)
        mp.add_forced_key_binding("s", "tr-s", pick_tracks)
        mp.add_forced_key_binding("n", "tr-n", function()
            local i = layer_row()
            if i then edit_mix(i, "name") end
        end)
        mp.add_forced_key_binding("o", "tr-o", function()
            local i = layer_row()
            if i then edit_mix(i, "position") end
        end)
        mp.add_forced_key_binding("d", "tr-d", delete_layer)
        for n = 1, 10 do
            mp.add_forced_key_binding(ui.number_key(n), "tr-" .. n, function() toggle_track(n) end)
        end
        mp.add_forced_key_binding("ESC", "tr-esc", cleanup)
    end

    open_ui = function()
        ui.clear_osd()
        active         = true
        state.ui_owner = "tracks"
        bind()
        refresh()
    end

    open_ui()
end

return M
