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

local bindings = { "up", "down", "j", "k", "move-up", "move-down", "J", "K", "tab", "enter", "a", "v", "e", "r", "o", "d", "esc" }
local picks    = { "up", "down", "j", "k", "tab", "enter", "m", "r", "o", "esc" }
local moves    = { "up", "down", "j", "k", "move-up", "move-down", "J", "K", "o", "enter", "esc" }
for i = 1, 10 do
    bindings[#bindings + 1] = tostring(i)
    picks[#picks + 1]       = tostring(i)
end

local function track_label(entry, track)
    if entry.kind == "mix" then return entry.name end
    return entry.title or track and track.title or lang.t("tracks_track", { n = entry.n })
end

local function mix_inputs(entry)
    local audio  = tracks.list("audio")
    local inputs = {}
    for _, e in ipairs(entry.inputs) do inputs[#inputs + 1] = track_label(e, e.kind == "source" and audio[e.n] or nil) end
    return table.concat(inputs, "+")
end

local function added(step, prev)
    local seen = {}
    for _, e in ipairs(prev or {}) do seen[e] = true end
    for _, e in ipairs(step) do
        if e.kind == "mix" and not seen[e] then return e end
    end
    return nil
end

local function track_details(entry, track)
    if entry.kind == "mix" then return lang.t("tracks_mix_of", { list = mix_inputs(entry) }) end
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
    local audio = tracks.list("audio")
    for _, e in ipairs(present) do out[#out + 1] = track_label(e, e.kind == "source" and audio[e.n] or nil) end
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
    local output = nil
    local chain  = nil
    local err    = nil
    local focus  = nil
    local open_ui
    local open_picker
    local open_move

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
        output     = nil

        local function section(key)
            if #rows > 0 then rows[#rows + 1] = { kind = "gap" } end
            rows[#rows + 1] = { kind = "header", key = key }
        end

        if kind == "video" then
            for k, row in ipairs(tracks.rows("video") or {}) do rows[k] = { kind = "track", row = row, k = k } end
        elseif not chain then
            rows[1] = { kind = "chain" }
        else
            local audio                = tracks.list("audio")
            local list, rerr           = tracks.rows("audio")
            local present, perr, steps = tracks.run(chain.layers, #audio)
            err                        = rerr or perr
            if list and #list > 0 then
                section("tracks_picks")
                for k, row in ipairs(list) do rows[#rows + 1] = { kind = "track", row = row, k = k } end
            end
            if #chain.layers > 0 then
                section("tracks_layers")
                for i in ipairs(chain.layers) do
                    local step      = steps and steps[i]
                    rows[#rows + 1] = { kind = "layer", index = i, step = step, prev = steps and steps[i - 1], failed = not present and not step and i == #(steps or {}) + 1 }
                end
            end
            if #rows > 0 then rows[#rows + 1] = { kind = "gap" } end
            rows[#rows + 1] = { kind = "chain" }
            output          = audio
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

    local function preview()
        local row = rows[cursor]
        return state.opts.layer_preview and row and row.kind == "layer" and row or nil
    end

    local function preview_rows(row)
        local out = { { kind = "note", text = lang.t("tracks_after", { layer = tracks.layer_text(chain.layers[row.index]) }), color = "dim_text_color" } }
        if not row.step then
            out[2] = { kind = "note", text = err, color = "error_color" }
        elseif #row.step == 0 then
            out[2] = { kind = "note", text = lang.t("tracks_no_output"), color = "dim_text_color" }
        end
        for k, e in ipairs(row.step or {}) do out[#out + 1] = { kind = "out", entry = e, track = e.kind == "source" and output[e.n] or nil, k = k } end
        return out
    end

    local function displayed()
        local row = preview()
        if not row then return rows, cursor end
        local list = preview_rows(row)
        if rows[1].key ~= "tracks_picks" then list[#list + 1] = { kind = "gap" } end
        for _, r in ipairs(rows) do
            if r.kind ~= "track" and r.key ~= "tracks_picks" then list[#list + 1] = r end
        end
        for i, r in ipairs(list) do
            if r == rows[cursor] then return list, i end
        end
        return list, 1
    end

    local function draw()
        local list, at = displayed()
        local widths   = { track = 0, layer = 0, out = 0 }
        for _, row in ipairs(list) do
            if row.kind == "track" then
                widths.track = math.max(widths.track, common.text_len(track_label(row.row.entry, row.row.track)))
            elseif row.kind == "layer" then
                widths.layer = math.max(widths.layer, common.text_len(tracks.layer_text(chain.layers[row.index])))
            elseif row.kind == "out" then
                widths.out = math.max(widths.out, common.text_len(track_label(row.entry, row.track)))
            end
        end

        local function line(row)
            if row.kind == "gap" then
                return ""
            elseif row.kind == "header" then
                return string.format("%s%s", theme.c("dim_text_color"), theme.escape(lang.t(row.key)))
            elseif row.kind == "note" then
                return string.format("%s%s", theme.c(row.color), theme.escape(row.text or ""))
            elseif row.kind == "chain" then
                local text = chain and tracks.format(chain) or state.tracks
                if text == "" then text = lang.t("value_none") end
                return string.format("%s > %s%s", theme.escape(lang.t("tracks_chain")), theme.c("value_color"), theme.escape(text))
            elseif row.kind == "track" then
                local entry   = row.row.entry
                local details = track_details(entry, row.row.track)
                local line    = string.format("%s%s\\h> %s", ui.number_prefix(row.k), pad(track_label(entry, row.row.track), widths.track), toggle(row.row.on))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            elseif row.kind == "layer" then
                local text = pad(tracks.layer_text(chain.layers[row.index]), widths.layer)
                if row.failed then return string.format("\\h%s\\h\\h%s!", text, theme.c("error_color")) end
                if not row.step or state.opts.layer_preview then return "\\h" .. text end
                local mix = chain.layers[row.index].op == "mix" and added(row.step, row.prev)
                local to  = mix and string.format("%s = %s", mix.name, mix_inputs(mix)) or labels(row.step)
                return string.format("\\h%s\\h\\h%s-> %s", text, theme.c("dim_text_color"), theme.escape(to))
            end
            local label = pad(track_label(row.entry, row.track), widths.out)
            if row.entry.kind == "mix" then label = theme.c("value_color") .. label .. theme.c("text_color") end
            local details = row.entry.kind == "mix" and "" or track_details(row.entry, row.track)
            local tail    = details ~= "" and details .. ", " .. origin(row.entry) or origin(row.entry)
            return string.format("\\h%d %s\\h\\h%s%s", row.k, label, theme.c("dim_text_color"), theme.escape(tail))
        end

        local body = ui.list(#list, at, function(i) return line(list[i]) end)

        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_" .. kind))
        local head  = ui.title(title)
        local hints
        if kind == "video" then
            if #rows == 0 then body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_video")), theme.reset()) end
            hints = { { "Tab/0-9", "toggle" }, { "Up/Down", "navigate" }, { "a", "audio" }, { "Enter/Esc", "close" } }
        else
            local sum = chain and summary(state.tracks) or err
            if sum and sum ~= "" then head = head .. ui.dim(sum) end
            local row = rows[cursor]
            hints     = { { "Up/Down", "navigate" }, { "a", "add" }, { "v", "video" }, { "Enter", "edit" }, { "Esc", "close" } }
            if row and row.kind == "track" then
                hints = { { "Up/Down", "navigate" }, { "Shift+Up/Down", "move" }, { "a", "add" }, { "r", "rename" }, { "o", "position" }, { "v", "video" }, { "Tab/0-9", "toggle" }, { "Enter/Esc", "close" } }
            elseif row and row.kind == "layer" then
                local layer = chain.layers[row.index]
                hints       = { { "Up/Down", "navigate" }, { "Shift+Up/Down", "move" }, { "a", "add" }, { "e", "type" } }
                if layer.op == "mix" then
                    hints[#hints + 1] = { "r", "rename" }
                    hints[#hints + 1] = { "o", "position" }
                end
                hints[#hints + 1] = { "v", "video" }
                hints[#hints + 1] = { "d", "delete" }
                hints[#hints + 1] = { "Enter", "edit" }
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

    local function prompt(title, current, hint, history, compose, submit, back)
        back = back or open_ui
        teardown()
        ui_input.show({
            title       = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, title),
            current     = current,
            hint        = hint,
            history     = history,
            allow_space = true,
            on_cancel   = back,
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
                back()
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

    local function edit_mix(i, field, back)
        local layer = chain.layers[i]
        if layer.op ~= "mix" then return end
        local is_name = field == "name"
        local current = is_name and (layer.name or "") or (layer.at and tostring(layer.at) or "")
        prompt(lang.t(is_name and "tracks_name" or "tracks_position"), current, lang.t(is_name and "hint_tracks_name" or "hint_tracks_at"), is_name and tracks.names or nil, function(input)
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
        end, is_name and tracks.remember_name or nil, back)
    end

    local function rename(entry, back)
        local current = entry.kind == "mix" and entry.name or entry.title or ""
        local hint    = lang.t(entry.kind == "mix" and "hint_tracks_name" or "hint_tracks_title")
        prompt(lang.t("tracks_rename", { name = track_label(entry, entry.n and tracks.list("audio")[entry.n]) }), current, hint, tracks.names, function(input)
            return tracks.rename_text(entry, input)
        end, tracks.remember_name, back)
    end

    local function rename_row()
        local row = rows[cursor]
        if kind ~= "audio" or not row then return end
        if row.kind == "track" then return rename(row.row.entry) end
        if row.kind ~= "layer" or chain.layers[row.index].op ~= "mix" then return end
        local mix = row.step and added(row.step, row.prev)
        if mix then return rename(mix) end
        edit_mix(row.index, "name")
    end

    local function toggle_row(target)
        local on, terr = tracks.toggle(kind, target.row.entry)
        if on == nil then return notify.show(terr, true, "error") end
        notify.show(lang.t("value_set", { label = lang.t("tracks_" .. kind) .. " " .. track_label(target.row.entry, target.row.track), value = lang.t(on and "value_on" or "value_off") }))
        refresh({ kind = "track", k = target.k })
    end

    local function toggle_track(n)
        for _, row in ipairs(rows) do
            if row.kind == "track" and row.k == n then return toggle_row(row) end
        end
    end

    local function tab_row()
        local row = rows[cursor]
        if row and row.kind == "track" then toggle_row(row) end
    end

    local function edit_row()
        local row = rows[cursor]
        if not row then return end
        if row.kind == "track" then return cleanup() end
        if not chain then return edit_chain() end
        if row.kind == "chain" then return edit_chain() end
        if row.kind ~= "layer" then return end
        local op = chain.layers[row.index].op
        if op == "rename" then return edit_layer(row.index) end
        if op == "move" then return open_move(row.index, nil, true) end
        open_picker(row.index)
    end

    local function add_layer()
        if kind ~= "audio" then return end
        if not chain then return edit_chain() end
        local row   = rows[cursor]
        local at    = (row and row.kind == "layer") and row.index + 1 or #chain.layers + 1
        local items = { "mix", "keep", "drop", "move", lang.t("tracks_type") }
        local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, lang.t("tracks_add"))
        local before = state.tracks
        teardown()
        ui_list.show(title, items, nil, function(op)
            if op == lang.t("tracks_type") then
                return prompt(lang.t("tracks_add"), "", lang.t("hint_tracks"), tracks.history, function(input)
                    return layers_text(input, at, 0)
                end, function(input)
                    tracks.remember(input)
                    focus = { kind = "layer", index = at }
                end)
            end
            if op == "move" then return open_move(at, before, false) end
            local layer = { op = op }
            if op == "keep" then layer.list = { { kind = "all" } } end
            if op == "drop" then layer.list = { { kind = "none" } } end
            commit(splice(chain.layers, at, 0, { layer }))
            open_picker(at, before)
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
        local row = rows[cursor]
        if kind == "audio" and row and row.kind == "track" then
            local n = row.k + delta
            if not rows[cursor + delta] or rows[cursor + delta].kind ~= "track" then return end
            local text, merr = tracks.move_text(row.row.entry, tostring(n))
            if not text then return notify.show(merr, true, "error") end
            state.tracks = text
            return refresh({ kind = "track", k = n })
        end
        local i = layer_row()
        if not i then return end
        local j = i + delta
        if not chain.layers[j] then return end
        chain.layers[i], chain.layers[j] = chain.layers[j], chain.layers[i]
        save()
        refresh({ kind = "layer", index = j })
    end

    local function type_layer()
        local i = layer_row()
        if i then edit_layer(i) end
    end

    local function switch(to)
        if to == kind then return end
        kind   = to
        cursor = 1
        refresh()
    end

    open_picker = function(index, before)
        local restore = before or state.tracks
        teardown()
        rebuild()
        local audio          = tracks.list("audio")
        local present, names = tracks.run(chain.layers, #audio, index)
        local pov            = mp.create_osd_overlay("ass-events")
        local pcursor        = 1
        local layer          = chain.layers[index]
        local is_mix         = layer.op == "mix"
        local exclude        = is_mix and tracks.excludes(layer.list)
        local set            = {}
        local flags          = {}
        present              = present or {}
        if not layer.list then
            for _, e in ipairs(present) do set[e] = true end
        elseif exclude or tracks.excludes(layer.list) or not names then
            set = names and tracks.resolve(layer.list, present, names) or {}
        else
            local rest = {}
            for _, item in ipairs(layer.list) do
                if item.kind == "mixes" or item.kind == "sources" then
                    flags[item.kind] = true
                else
                    rest[#rest + 1] = item
                end
            end
            set = #rest > 0 and tracks.resolve(rest, present, names) or {}
        end
        state.ui_owner = "tracks"

        local function groups()
            local out  = {}
            local seen = {}
            if exclude then return out end
            for _, e in ipairs(present) do seen[tracks.group_of(e)] = true end
            for _, g in ipairs({ "mixes", "sources" }) do
                if seen[g] then out[#out + 1] = g end
            end
            return out
        end

        local function shown(on)
            return on ~= (layer.op == "drop")
        end

        local function group_on(g)
            if flags[g] then return true end
            for _, e in ipairs(present) do
                if tracks.group_of(e) == g and not set[e] then return false end
            end
            return true
        end

        local function hide()
            pov:remove()
            for _, name in ipairs(picks) do mp.remove_key_binding("trp-" .. name) end
            state.ui_owner = nil
        end

        local function close(keep)
            hide()
            if not keep then state.tracks = restore end
            if keep and before then focus = { kind = "layer", index = index } end
            open_ui()
        end

        local function write()
            layer.list = tracks.list_for(set, present, exclude, layer.op, flags)
            save()
        end

        local function draw_picker()
            local extra = groups()
            local width = 0
            for _, e in ipairs(present) do width = math.max(width, common.text_len(track_label(e, audio[e.n]))) end
            for _, g in ipairs(extra) do width = math.max(width, common.text_len(lang.t("tracks_" .. g))) end
            local body = ui.list(#present + #extra, pcursor, function(k)
                local e = present[k]
                if not e then
                    local g = extra[k - #present]
                    return string.format("%s%s\\h> %s %s@%s", ui.number_prefix(11), pad(lang.t("tracks_" .. g), width), toggle(shown(group_on(g))), theme.c("dim_text_color"), g)
                end
                local details = track_details(e, e.kind == "source" and audio[e.n] or nil)
                local on      = set[e] == true or flags[tracks.group_of(e)] == true
                local line    = string.format("%s%s\\h> %s", ui.number_prefix(k), pad(track_label(e, audio[e.n]), width), toggle(shown(on)))
                if details ~= "" then line = string.format("%s %s%s", line, theme.c("dim_text_color"), theme.escape(details)) end
                return line
            end)
            if #present == 0 then body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_audio")), theme.reset()) end
            local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, tracks.layer_text(layer))
            local sum   = summary(state.tracks)
            if is_mix then sum = lang.t(exclude and "tracks_all_except" or "tracks_include") .. ", " .. sum end
            local head  = ui.title(title) .. ui.dim(sum)
            local hints = { { "Up/Down", "navigate" }, { "Tab/0-9", "toggle" }, { "Enter", "apply" }, { "Esc", "cancel" } }
            if is_mix then
                hints[#hints + 1] = { "m", "mode" }
                hints[#hints + 1] = { "r", "rename" }
                hints[#hints + 1] = { "o", "position" }
            end
            pov.data    = head .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
            pov:update()
        end

        local function flip(k)
            local e = present[k]
            local g = e and tracks.group_of(e) or groups()[k - #present]
            if not g then return end
            pcursor = k
            if not e then
                local was = group_on(g)
                flags[g]  = not was or nil
                for _, m in ipairs(present) do
                    if tracks.group_of(m) == g then set[m] = nil end
                end
            elseif flags[g] then
                flags[g] = nil
                for _, m in ipairs(present) do
                    if tracks.group_of(m) == g then set[m] = true end
                end
                set[e] = nil
            else
                set[e] = not set[e] or nil
            end
            write()
            draw_picker()
        end

        local function move(delta)
            local count = #present + #groups()
            if count == 0 then return end
            pcursor = ui.wrap(pcursor, delta, count)
            draw_picker()
        end

        mp.add_forced_key_binding("UP", "trp-up", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "trp-down", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "trp-k", function() move(-1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "trp-j", function() move(1) end, {repeatable = true})
        mp.add_forced_key_binding("TAB", "trp-tab", function() flip(pcursor) end)
        mp.add_forced_key_binding("ENTER", "trp-enter", function() close(true) end)
        mp.add_forced_key_binding("r", "trp-r", function()
            if not is_mix then return end
            local back = function() open_picker(index, restore) end
            local _, _, steps = tracks.run(chain.layers, #audio, index + 1)
            local mix         = steps and steps[index] and added(steps[index], steps[index - 1])
            hide()
            if mix then return rename(mix, back) end
            edit_mix(index, "name", back)
        end)
        mp.add_forced_key_binding("o", "trp-o", function()
            if not is_mix then return end
            hide()
            edit_mix(index, "position", function() open_picker(index, restore) end)
        end)
        mp.add_forced_key_binding("m", "trp-m", function()
            if not is_mix then return end
            for _, e in ipairs(present) do
                if flags[tracks.group_of(e)] then set[e] = true end
            end
            flags   = {}
            exclude = not exclude
            pcursor = math.min(pcursor, math.max(#present, 1))
            write()
            draw_picker()
        end)
        for n = 1, 10 do
            mp.add_forced_key_binding(ui.number_key(n), "trp-" .. n, function()
                if present[n] then flip(n) end
            end)
        end
        mp.add_forced_key_binding("ESC", "trp-esc", function() close(false) end)
        draw_picker()
    end

    open_move = function(index, before, exists, picked)
        local restore = before or state.tracks
        teardown()
        rebuild()
        local audio        = tracks.list("audio")
        local input, names = tracks.run(chain.layers, #audio, index)
        local mov          = mp.create_osd_overlay("ass-events")
        local mcursor      = 1
        input              = input or {}
        state.ui_owner     = "tracks"

        local function output()
            if not exists then return input end
            local _, _, steps = tracks.run(chain.layers, #audio, index + 1)
            return steps and steps[index] or input
        end
        if picked then mcursor = tracks.position(output(), picked) or 1 end

        local function hide()
            mov:remove()
            for _, name in ipairs(moves) do mp.remove_key_binding("trm-" .. name) end
            state.ui_owner = nil
        end

        local function close(keep)
            hide()
            if not keep then state.tracks = restore end
            if keep and exists then focus = { kind = "layer", index = index } end
            open_ui()
        end

        local function draw_move()
            local out   = output()
            local width = 0
            for _, e in ipairs(out) do width = math.max(width, common.text_len(track_label(e, audio[e.n]))) end
            local body = ui.list(#out, mcursor, function(k)
                local e    = out[k]
                local from = tracks.position(input, e)
                local line = string.format("%s%s", ui.number_prefix(k), pad(track_label(e, audio[e.n]), width))
                if from and from ~= k then line = string.format("%s\\h\\h%s%s", line, theme.c("dim_text_color"), theme.escape(lang.t("tracks_from", { n = from }))) end
                return line
            end)
            if #out == 0 then body = string.format("\\N%s\\h\\h%s%s", theme.c("dim_text_color"), theme.escape(lang.t("tracks_no_audio")), theme.reset()) end
            local title = string.format("%s %s %s", lang.t("menu_tracks"), state.opts.menu_path_separator, exists and tracks.layer_text(chain.layers[index]) or "move")
            local hints = { { "Up/Down", "navigate" }, { "Shift+Up/Down", "move" }, { "o", "position" }, { "Enter", "apply" }, { "Esc", "cancel" } }
            mov.data    = ui.title(title) .. ui.dim(summary(state.tracks)) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
            mov:update()
        end

        local function build(entry, text)
            local n, verr = tracks.at_value(text)
            if n == nil then return nil, verr end
            local copy   = tracks.parse(state.tracks)
            local layer  = exists and copy.layers[index] or { op = "move", pairs = {} }
            local layers = splice(copy.layers, index, exists and 1 or 0, { layer })
            tracks.place(layers, index, input, names, entry, n or nil)
            local has = #layer.pairs > 0
            if not has then table.remove(layers, index) end
            tracks.rebase(tracks.parse(state.tracks).layers, layers, has and index or index - 1, (has and 1 or 0) - (exists and 1 or 0))
            return tracks.format({ layers = layers, video = copy.video }), nil, has
        end

        local function position()
            local entry = output()[mcursor]
            if not entry then return end
            local layer   = exists and chain.layers[index]
            local k       = tracks.pair_index(layer, input, names, entry)
            local current = k and tostring(layer.pairs[k].at) or ""
            local after   = exists
            hide()
            prompt(lang.t("tracks_move", { name = track_label(entry, audio[entry.n]) }), current, lang.t("hint_tracks_move"), nil, function(text)
                return build(entry, text)
            end, function(text)
                local _, _, has = build(entry, text)
                after           = has
            end, function() open_move(index, restore, after, entry) end)
        end

        local function step(delta)
            local count = #output()
            if count == 0 then return end
            mcursor = ui.wrap(mcursor, delta, count)
            draw_move()
        end

        local function shift(delta)
            local out   = output()
            local entry = out[mcursor]
            local n     = mcursor + delta
            if not entry or not out[n] then return end
            local text, _, has = build(entry, tostring(n))
            if not text then return end
            state.tracks = text
            hide()
            open_move(index, restore, has, entry)
        end

        mp.add_forced_key_binding("UP", "trm-up", function() step(-1) end, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "trm-down", function() step(1) end, {repeatable = true})
        mp.add_forced_key_binding("k", "trm-k", function() step(-1) end, {repeatable = true})
        mp.add_forced_key_binding("j", "trm-j", function() step(1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+UP", "trm-move-up", function() shift(-1) end, {repeatable = true})
        mp.add_forced_key_binding("shift+DOWN", "trm-move-down", function() shift(1) end, {repeatable = true})
        mp.add_forced_key_binding("K", "trm-K", function() shift(-1) end, {repeatable = true})
        mp.add_forced_key_binding("J", "trm-J", function() shift(1) end, {repeatable = true})
        mp.add_forced_key_binding("o", "trm-o", position)
        mp.add_forced_key_binding("ENTER", "trm-enter", function() close(true) end)
        mp.add_forced_key_binding("ESC", "trm-esc", function() close(false) end)
        draw_move()
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
        mp.add_forced_key_binding("TAB", "tr-tab", tab_row)
        mp.add_forced_key_binding("ENTER", "tr-enter", edit_row)
        mp.add_forced_key_binding("a", "tr-a", function()
            if kind == "video" then return switch("audio") end
            add_layer()
        end)
        mp.add_forced_key_binding("v", "tr-v", function() switch("video") end)
        mp.add_forced_key_binding("e", "tr-e", type_layer)
        mp.add_forced_key_binding("r", "tr-r", rename_row)
        mp.add_forced_key_binding("o", "tr-o", function()
            local row = rows[cursor]
            if kind == "audio" and row and row.kind == "track" then
                local entry = row.row.entry
                return prompt(lang.t("tracks_move", { name = track_label(entry, row.row.track) }), "", lang.t("hint_tracks_move"), nil, function(input)
                    return tracks.move_text(entry, input)
                end, nil, function()
                    for k, r in ipairs(tracks.rows("audio") or {}) do
                        if tracks.same_entry(r.entry, entry) then focus = { kind = "track", k = k } end
                    end
                    open_ui()
                end)
            end
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
        refresh(focus)
        focus = nil
    end

    open_ui()
end

return M
