local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local state  = require 'src.state'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local history_path = utils.join_path(common.get_state_dir(), "tracks_history.json")
local names_path   = utils.join_path(common.get_state_dir(), "tracks_names_history.json")
local codec_exts   = { opus = "opus", aac = "m4a", alac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg" }
local encoder_exts = { opus = "opus", aac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg", pcm = "wav" }
local ops          = { keep = true, drop = true, mix = true, rename = true, move = true, video = true }
local reserved     = { all = true, none = true, at = true }
local groups       = { ["@mixes"] = "mixes", ["@sources"] = "sources" }

local function tokenize(text)
    local tokens = {}
    local i      = 1
    while true do
        local s = text:find("%S", i)
        if not s then break end
        local j     = s
        local quote = false
        while j <= #text do
            local c = text:sub(j, j)
            if c == "\"" then
                quote = not quote
            elseif not quote and c:match("%s") then
                break
            end
            j = j + 1
        end
        if quote then return nil, text:sub(s) end
        tokens[#tokens + 1] = text:sub(s, j - 1)
        i                   = j
    end
    return tokens
end

local function valid_name(name)
    return name ~= "" and name == name:match("^%s*(.-)%s*$") and not name:find("[\",#]")
end

local function plain_word(name)
    local word = name:lower()
    return valid_name(name) and not name:find("%s") and not name:find("^[-@]") and not name:match("^%d+$") and not reserved[word] and not ops[word]
end

local presets = {}

local function find_preset(word, disabled)
    for _, p in ipairs(presets) do
        if p.id:lower() == word and not p.disabled == not disabled then return p end
    end
    for _, p in ipairs(presets) do
        if p.name == word and not p.disabled == not disabled then return p end
    end
    return nil
end

local function bare_name(name)
    return plain_word(name) and not find_preset(name:lower())
end

local function starts_layer(token)
    local word = token:lower()
    return ops[word] or find_preset(word) ~= nil
end

local function list_items(token)
    local neg   = token:sub(1, 1) == "-"
    local body  = neg and token:sub(2) or token
    local parts = {}
    local cur   = ""
    local quote = false
    for c in body:gmatch(".") do
        if c == "\"" then quote = not quote end
        if c == "," and not quote then
            parts[#parts + 1] = cur
            cur               = ""
        else
            cur = cur .. c
        end
    end
    parts[#parts + 1] = cur

    local items = {}
    for _, part in ipairs(parts) do
        local item_neg = neg
        if part:sub(1, 1) == "-" then
            item_neg = true
            part     = part:sub(2)
        end
        local word   = part:lower()
        local quoted = part:match("^\"([^\"]+)\"$")
        local item
        if part:match("^%d+$") and tonumber(part) >= 1 then
            item = { kind = "n", n = tonumber(part) }
        elseif word == "all" or word == "none" then
            item = { kind = word }
        elseif groups[word] then
            item = { kind = groups[word] }
        elseif quoted and valid_name(quoted) then
            item = { kind = "name", name = quoted }
        elseif bare_name(part) then
            item = { kind = "name", name = part }
        else
            return nil
        end
        item.neg          = item_neg or nil
        items[#items + 1] = item
    end
    return items
end

local function parse(text, depth)
    local tokens, bad = tokenize(text or "")
    if not tokens then return nil, lang.t("tracks_unknown", { token = bad }) end
    local layers = {}
    local video  = nil
    local own    = false
    local i      = 1

    local function fail(token)
        local key = find_preset(token:lower(), true) and "tracks_disabled" or "tracks_unknown"
        return nil, lang.t(key, { token = token })
    end

    local function lists()
        local items = {}
        while tokens[i] and not starts_layer(tokens[i]) and tokens[i]:lower() ~= "at" do
            local list = list_items(tokens[i])
            if not list then return nil, tokens[i] end
            for _, item in ipairs(list) do items[#items + 1] = item end
            i = i + 1
        end
        return items
    end

    while i <= #tokens do
        local token = tokens[i]
        local word  = token:lower()
        i           = i + 1
        if word == "keep" or word == "drop" or word == "video" then
            local items, bad_token = lists()
            if not items then return fail(bad_token) end
            if #items == 0 then return nil, lang.t("tracks_needs_list", { token = token }) end
            if word == "video" then
                video = items
                own   = true
            else
                layers[#layers + 1] = { op = word, list = items }
            end
        elseif word == "mix" then
            local layer = { op = "mix" }
            while tokens[i] and not starts_layer(tokens[i]) do
                local t    = tokens[i]
                local name = t:match("^\"([^\"]*)\"$")
                if t:lower() == "at" then
                    local n = tonumber((tokens[i + 1] or ""):match("^%d+$") or "")
                    if not n or n < 1 then return fail(tokens[i + 1] or t) end
                    layer.at = n
                    i        = i + 2
                elseif name then
                    if layer.name or not valid_name(name) then return fail(t) end
                    layer.name = name
                    i          = i + 1
                else
                    local items = list_items(t)
                    if not items then return fail(t) end
                    layer.list = layer.list or {}
                    for _, item in ipairs(items) do layer.list[#layer.list + 1] = item end
                    i = i + 1
                end
            end
            layers[#layers + 1] = layer
        elseif word == "rename" then
            local layer = { op = "rename", pairs = {} }
            while tokens[i] and not starts_layer(tokens[i]) do
                local items = list_items(tokens[i])
                local item  = items and #items == 1 and items[1]
                if not item or item.neg or (item.kind ~= "n" and item.kind ~= "name") then return fail(tokens[i]) end
                local t      = tokens[i + 1]
                local quoted = t and t:match("^\"([^\"]*)\"$")
                if not t or not (quoted and valid_name(quoted) or not quoted and bare_name(t)) then return fail(t or tokens[i]) end
                layer.pairs[#layer.pairs + 1] = { item = item, name = quoted or t }
                i = i + 2
            end
            if #layer.pairs == 0 then return nil, lang.t("tracks_needs_list", { token = token }) end
            layers[#layers + 1] = layer
        elseif word == "move" then
            local layer = { op = "move", pairs = {} }
            while tokens[i] and not starts_layer(tokens[i]) do
                local items = list_items(tokens[i])
                local item  = items and #items == 1 and items[1]
                if not item or item.neg or (item.kind ~= "n" and item.kind ~= "name") then return fail(tokens[i]) end
                if (tokens[i + 1] or ""):lower() ~= "at" then return fail(tokens[i + 1] or tokens[i]) end
                local n = tonumber((tokens[i + 2] or ""):match("^%d+$") or "")
                if not n or n < 1 then return fail(tokens[i + 2] or tokens[i + 1]) end
                layer.pairs[#layer.pairs + 1] = { item = item, at = n }
                i = i + 3
            end
            if #layer.pairs == 0 then return nil, lang.t("tracks_needs_list", { token = token }) end
            layers[#layers + 1] = layer
        else
            local preset = find_preset(word)
            if not preset or depth >= 8 then return fail(token) end
            local inner, perr = parse(preset.chain, depth + 1)
            if not inner then return nil, perr end
            layers[#layers + 1] = { op = "preset", name = token, chain = preset.chain, layers = inner.layers }
            if inner.video or inner.preset_video then
                video = inner.video or inner.preset_video
                own   = false
            end
        end
    end
    return { layers = layers, video = own and video or nil, preset_video = not own and video or nil }
end

function M.parse(text)
    return parse(text, 0)
end

local function preset_files(dir)
    local files = {}
    for _, file in ipairs(utils.readdir(dir, "files") or {}) do
        if file:match("%.trk$") then files[#files + 1] = file end
    end
    table.sort(files)
    return files
end

local function upsert(preset)
    preset.id = preset.file .. "/" .. preset.name
    for i, p in ipairs(presets) do
        if p.id == preset.id then
            notify.show(lang.t("warn_redefined", { name = preset.name, where = preset.where }), false, "warn")
            presets[i] = preset
            return
        end
    end
    presets[#presets + 1] = preset
end

local function parse_presets_file(path, file)
    local f = io.open(path, "r")
    if not f then return end
    local n = 0
    for line in f:lines() do
        n = n + 1
        local where   = string.format("%s.trk:%d", file, n)
        local content = line:gsub("\r$", "")
        local hash    = content:find("#", 1, true)
        if hash then content = content:sub(1, hash - 1) end
        content = content:match("^%s*(.-)%s*$")
        if content ~= "" then
            local rest        = content:match("^disabled%s+([^=%s].*)$")
            local name, chain = (rest or content):match("^([^%s=/]+)%s*=%s*(.+)$")
            local word        = name and name:lower()
            if not word or not plain_word(word) then
                notify.show(lang.t("warn_invalid_line", { where = where, line = content }), false, "warn")
            else
                upsert({ name = word, file = file, chain = chain, where = where, line = n, disabled = rest ~= nil })
            end
        end
    end
    f:close()
end

function M.reload(keep_missing)
    presets     = {}
    local dir   = common.get_conf_dir()
    local files = preset_files(dir)
    if #files == 0 and not keep_missing then
        common.ensure_default_conf("tachytome-tracks.conf", "default.trk")
        files = preset_files(dir)
    end
    for _, file in ipairs(files) do parse_presets_file(utils.join_path(dir, file), (file:gsub("%.trk$", ""))) end
end

function M.all()
    return presets
end

function M.presets()
    local list  = {}
    local count = {}
    for _, p in ipairs(presets) do
        if not p.disabled then
            list[#list + 1] = p
            count[p.name]   = (count[p.name] or 0) + 1
        end
    end
    for _, p in ipairs(list) do p.label = count[p.name] > 1 and find_preset(p.name) ~= p and p.id or p.name end
    return list
end

local function item_text(item)
    if item.kind == "n" then return tostring(item.n) end
    if item.kind == "name" then
        if bare_name(item.name) then return item.name end
        return "\"" .. item.name .. "\""
    end
    if item.kind == "mixes" or item.kind == "sources" then return "@" .. item.kind end
    return item.kind
end

local function list_text(list)
    local pos = {}
    local neg = {}
    for _, item in ipairs(list) do
        if item.neg then
            neg[#neg + 1] = "-" .. item_text(item)
        else
            pos[#pos + 1] = item_text(item)
        end
    end
    local parts = {}
    if #pos > 0 then parts[#parts + 1] = table.concat(pos, ",") end
    if #neg > 0 then parts[#parts + 1] = table.concat(neg, ",") end
    return table.concat(parts, " ")
end

function M.layer_text(layer)
    if layer.op == "preset" then return layer.name end
    if layer.op == "rename" then
        local parts = { "rename" }
        for _, pair in ipairs(layer.pairs) do parts[#parts + 1] = item_text(pair.item) .. " \"" .. pair.name .. "\"" end
        return table.concat(parts, " ")
    end
    if layer.op == "move" then
        local parts = { "move" }
        for _, pair in ipairs(layer.pairs) do parts[#parts + 1] = item_text(pair.item) .. " at " .. pair.at end
        return table.concat(parts, " ")
    end
    if layer.op ~= "mix" then return layer.op .. " " .. list_text(layer.list) end
    local parts = { "mix" }
    if layer.list then parts[#parts + 1] = list_text(layer.list) end
    if layer.name then parts[#parts + 1] = "\"" .. layer.name .. "\"" end
    if layer.at then parts[#parts + 1] = "at " .. layer.at end
    return table.concat(parts, " ")
end

function M.format(chain)
    local parts = {}
    for _, layer in ipairs(chain.layers) do parts[#parts + 1] = M.layer_text(layer) end
    if chain.video then parts[#parts + 1] = "video " .. list_text(chain.video) end
    return table.concat(parts, " ")
end

local function filter(list, keep)
    local out = {}
    for _, e in ipairs(list) do
        if keep(e) then out[#out + 1] = e end
    end
    return out
end

local function contains(list, entry)
    for _, e in ipairs(list) do
        if e == entry then return true end
    end
    return false
end

local function resolve(list, present, names)
    local pos     = {}
    local neg     = {}
    local any_pos = false
    for _, item in ipairs(list) do
        local target = item.neg and neg or pos
        local found  = {}
        if not item.neg then any_pos = true end
        if item.kind == "all" then
            found = present
        elseif item.kind == "mixes" or item.kind == "sources" then
            local want = item.kind == "mixes" and "mix" or "source"
            found      = filter(present, function(e) return e.kind == want end)
        elseif item.kind == "n" then
            if present[item.n] then found = { present[item.n] } end
        elseif item.kind == "name" then
            local entry = names[item.name:lower()]
            if entry == nil then return nil, lang.t("tracks_unknown", { token = item.name }) end
            if entry and contains(present, entry) then found = { entry } end
        end
        for _, e in ipairs(found) do target[e] = true end
    end
    if not any_pos then
        for _, e in ipairs(present) do pos[e] = true end
    end
    for e in pairs(neg) do pos[e] = nil end
    return pos
end

local function sources(count)
    local out = {}
    for n = 1, count do out[n] = { kind = "source", n = n } end
    return out
end

local function alias(e, name)
    local out = {}
    for k, v in pairs(e) do out[k] = v end
    out.of = e.of or e
    if e.kind == "mix" then
        out.name = name
    else
        out.title = name
    end
    return out
end

function M.run(layers, audio_count, upto)
    local present = sources(audio_count)
    local names   = {}
    local steps   = {}
    local unnamed = 0

    local function apply(layer, id)
        if layer.op == "preset" then
            for j, inner in ipairs(layer.layers) do
                local err = apply(inner, id .. "/" .. j)
                if err then return err end
            end
        elseif layer.op == "keep" or layer.op == "drop" then
            local set, err = resolve(layer.list, present, names)
            if not set then return err end
            local keep = layer.op == "keep"
            present    = filter(present, function(e) return (set[e] == true) == keep end)
        elseif layer.op == "mix" then
            local inputs = present
            if layer.list then
                local set, err = resolve(layer.list, present, names)
                if not set then return err end
                inputs = filter(present, function(e) return set[e] == true end)
            end
            local name = layer.name
            if not name then
                repeat
                    unnamed = unnamed + 1
                    name    = unnamed == 1 and lang.t("tracks_mix") or lang.t("tracks_mix_n", { n = unnamed })
                until names[name:lower()] == nil
            elseif names[name:lower()] ~= nil then
                return lang.t("tracks_name_taken", { name = name })
            end
            if #inputs >= 1 then
                local entry = { kind = "mix", name = name, layer = id, inputs = filter(inputs, function() return true end) }
                local at    = math.min(layer.at or (#present + 1), #present + 1)
                present     = filter(present, function() return true end)
                table.insert(present, at, entry)
                names[name:lower()] = entry
            else
                names[name:lower()] = false
            end
        elseif layer.op == "rename" then
            present = filter(present, function() return true end)
            for _, pair in ipairs(layer.pairs) do
                local set, err = resolve({ pair.item }, present, names)
                if not set then return err end
                for k, e in ipairs(present) do
                    if set[e] then
                        local taken = names[pair.name:lower()]
                        if taken ~= nil and taken ~= e then return lang.t("tracks_name_taken", { name = pair.name }) end
                        local renamed            = alias(e, pair.name)
                        present[k]               = renamed
                        names[pair.name:lower()] = renamed
                    end
                end
            end
        elseif layer.op == "move" then
            local moves = {}
            for _, pair in ipairs(layer.pairs) do
                local set, err = resolve({ pair.item }, present, names)
                if not set then return err end
                for _, e in ipairs(present) do
                    if set[e] then moves[#moves + 1] = { entry = e, at = pair.at } end
                end
            end
            present = filter(present, function() return true end)
            for _, m in ipairs(moves) do
                for k, e in ipairs(present) do
                    if e == m.entry then
                        table.remove(present, k)
                        table.insert(present, math.min(m.at, #present + 1), e)
                        break
                    end
                end
            end
        end
        return nil
    end

    for i, layer in ipairs(layers) do
        if upto and i >= upto then break end
        local err = apply(layer, i)
        if err then return nil, err, steps end
        steps[i] = present
    end
    return present, names, steps
end

M.resolve = resolve

function M.evaluate(chain, audio_count, video_count)
    local present, names = M.run(chain.layers, audio_count)
    if not present then return nil, names end

    local video = nil
    local pick  = chain.video or chain.preset_video
    if pick then
        local list     = sources(video_count)
        local set, err = resolve(pick, list, {})
        if not set then return nil, err end
        video = {}
        for _, e in ipairs(list) do
            if set[e] then video[#video + 1] = e.n end
        end
    end
    return { audio = present, video = video }
end

function M.build(text, audio_count, video_count)
    local chain, err = M.parse(text)
    if not chain then return nil, err end
    return M.evaluate(chain, audio_count, video_count)
end

function M.leaf(entry)
    while entry.kind == "mix" do entry = entry.inputs[1] end
    return entry.n
end

function M.kept(video, n)
    if not video then return true end
    for _, v in ipairs(video) do
        if v == n then return true end
    end
    return false
end

function M.list(kind)
    local out = {}
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == kind and not t.external then out[#out + 1] = t end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function M.reset()
    state.tracks = state.opts.tracks
end

function M.current()
    return M.build(state.tracks, #M.list("audio"), #M.list("video"))
end

local function kept_video(result)
    for i, t in ipairs(M.list("video")) do
        if M.kept(result.video, i) and not t.albumart and not t.image then return true end
    end
    return false
end

function M.container()
    local result = M.current()
    if not result or kept_video(result) then return nil end
    local out = result.audio
    if #out == 0 then return nil end
    if #out > 1 then return "mka" end

    local encoder = state.opts.audio_encoder
    if encoder_exts[encoder] then return encoder_exts[encoder] end
    local t     = M.list("audio")[M.leaf(out[1])]
    local codec = t and t.codec or ""
    if codec:match("^pcm_") then return "wav" end
    return codec_exts[codec] or "mka"
end

function M.entry_label(entry)
    if entry.kind == "mix" then return entry.name end
    return entry.title or tostring(entry.n)
end

function M.flatten(entry)
    local title = nil
    while true do
        if entry.of then
            title = title or (entry.kind == "mix" and entry.name or entry.title)
            entry = entry.of
        elseif entry.kind == "mix" and #entry.inputs == 1 then
            title = title or entry.name
            entry = entry.inputs[1]
        else
            return entry, title
        end
    end
end

function M.display(kind)
    local result = M.current()
    if not result then return state.tracks end
    local count = #M.list(kind)
    if kind == "video" then
        if not result.video or #result.video == count then return lang.t(count > 0 and "value_all" or "value_none") end
        if #result.video == 0 then return lang.t("value_none") end
        return table.concat(result.video, ", ")
    end

    local out = result.audio
    if #out == 0 then return lang.t("value_none") end
    local all = #out == count
    for k, e in ipairs(out) do
        if e.kind ~= "source" or e.n ~= k or e.title then all = false end
    end
    if all then return lang.t("value_all") end
    local labels = {}
    for _, e in ipairs(out) do labels[#labels + 1] = M.entry_label(e) end
    return table.concat(labels, ", ")
end

local function only_layer(layer)
    return layer ~= nil and layer.op == "keep" and #layer.list == 1 and layer.list[1].kind == "mixes" and not layer.list[1].neg
end

local function tail(layers)
    local i    = #layers
    local only = only_layer(layers[i]) and i or nil
    if only then i = i - 1 end
    local mix = layers[i] and layers[i].op == "mix" and not layers[i].list and i or nil
    if mix then i = i - 1 end
    local drop = layers[i] and layers[i].op == "drop" and i or nil
    if drop then
        for _, item in ipairs(layers[drop].list) do
            if item.neg or (item.kind ~= "n" and item.kind ~= "name") then drop = nil break end
        end
    end
    return drop, mix, only
end

local function has_mix(layers)
    for _, layer in ipairs(layers) do
        if layer.op == "mix" then return true end
    end
    return false
end

local function save(chain)
    state.tracks = M.format(chain)
end

function M.same_entry(a, b)
    a = a.of or a
    b = b.of or b
    if a.kind ~= b.kind then return false end
    if a.kind == "source" then return a.n == b.n end
    return a.layer == b.layer
end

function M.position(list, entry)
    for k, e in ipairs(list) do
        if M.same_entry(e, entry) then return k end
    end
    return nil
end

local function covers(item, input, names, entry)
    local set = resolve({ item }, input, names)
    for e in pairs(set or {}) do
        if M.same_entry(e, entry) then return true end
    end
    return false
end

function M.pair_index(layer, input, names, entry)
    for k, pair in ipairs(layer and layer.pairs or {}) do
        if covers(pair.item, input, names, entry) then return k end
    end
    return nil
end

local function insert_n(list, n)
    local at = #list + 1
    for k, item in ipairs(list) do
        if item.kind == "n" and item.n > n then
            at = k
            break
        end
    end
    table.insert(list, at, { kind = "n", n = n })
end

M.tail = tail

function M.excludes(list)
    if not list then return false end
    local neg = false
    for _, item in ipairs(list) do
        if item.neg then
            neg = true
        elseif item.kind ~= "all" then
            return false
        end
    end
    return neg
end

function M.group_of(entry)
    return entry.kind == "mix" and "mixes" or "sources"
end

function M.list_for(set, present, exclude, op, flags)
    flags         = exclude and {} or flags or {}
    local items   = {}
    local picked  = 0
    local grouped = false
    for _, g in ipairs({ "mixes", "sources" }) do
        if flags[g] then
            items[#items + 1] = { kind = g }
            grouped           = true
        end
    end
    for k, e in ipairs(present) do
        local covered = flags[M.group_of(e)] == true
        local on      = set[e] == true or covered
        if on then picked = picked + 1 end
        if not covered and on ~= exclude then items[#items + 1] = { kind = "n", n = k, neg = exclude or nil } end
    end
    local every = not grouped and #present > 0 and picked == #present
    if op == "mix" and (every or exclude and #items == 0) then return nil end
    if every then return { { kind = "all" } } end
    if #items == 0 then return { { kind = "none" } } end
    return items
end

M.history = common.read_json_file(history_path)
if type(M.history) ~= "table" then M.history = {} end

function M.remember(text)
    if text == "" then return end
    common.add_to_history(M.history, text)
    common.write_json_file(history_path, M.history)
end

M.names = common.read_json_file(names_path)
if type(M.names) ~= "table" then M.names = {} end

function M.remember_name(text)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return end
    common.add_to_history(M.names, text)
    common.write_json_file(names_path, M.names)
end

function M.rows(kind)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local list = M.list(kind)
    local rows = {}
    if kind == "video" then
        local result, verr = M.evaluate({ layers = {}, video = chain.video or chain.preset_video }, 0, #list)
        if not result then return nil, verr end
        for n, t in ipairs(list) do rows[n] = { entry = { kind = "source", n = n }, track = t, on = M.kept(result.video, n) } end
        return rows
    end

    local drop, mix, only = tail(chain.layers)
    local present, names  = M.run(chain.layers, #list, drop or mix or only or #chain.layers + 1)
    if not present then return nil, names end
    local set = {}
    if drop then
        local dropped, derr = resolve(chain.layers[drop].list, present, names)
        if not dropped then return nil, derr end
        set = dropped
    end
    for k, e in ipairs(present) do rows[k] = { entry = e, track = e.kind == "source" and list[e.n] or nil, on = not set[e] } end
    return rows
end

function M.toggle(kind, entry)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    if kind == "video" then
        local count  = #M.list("video")
        local result = M.evaluate({ layers = {}, video = chain.video or chain.preset_video }, 0, count)
        local on     = {}
        for n = 1, count do on[n] = result and M.kept(result.video, n) end
        on[entry.n]  = not on[entry.n]
        local items  = {}
        for n = 1, count do
            if on[n] then items[#items + 1] = { kind = "n", n = n } end
        end
        if #items == count then
            chain.video = chain.preset_video and { { kind = "all" } } or nil
        elseif #items == 0 then
            chain.video = { { kind = "none" } }
        else
            chain.video = items
        end
        save(chain)
        return on[entry.n]
    end

    local drop, mix, only = tail(chain.layers)
    local stop            = drop or mix or only or #chain.layers + 1
    local present, names  = M.run(chain.layers, #M.list("audio"), stop)
    if not present then return nil, names end
    local n = M.position(present, entry)
    if not n then return nil, lang.t("tracks_unknown", { token = M.entry_label(entry) }) end
    if not drop then
        drop = stop
        table.insert(chain.layers, drop, { op = "drop", list = {} })
    end
    local list = chain.layers[drop].list
    for i, other in ipairs(list) do
        if covers(other, present, names, entry) then
            table.remove(list, i)
            if #list == 0 then table.remove(chain.layers, drop) end
            save(chain)
            return true
        end
    end
    insert_n(list, n)
    save(chain)
    return false
end

local function tail_start(layers)
    local drop, mix, only = tail(layers)
    return drop or mix or only or #layers + 1
end

local function near_tail(layers, stop, op)
    local i = stop - 1
    while layers[i] and (layers[i].op == "rename" or layers[i].op == "move") do
        if layers[i].op == op then return layers[i], i end
        i = i - 1
    end
    return nil
end

local function retarget(layers, count, from, old, name, entry)
    if name ~= "" and name:lower() == old then return end
    local i = from + 1
    while layers[i] do
        local layer = layers[i]
        local input = name == "" and M.run(layers, count, i) or nil
        local n     = input and M.position(input, entry)
        local function swap(it)
            if it.kind ~= "name" or it.name:lower() ~= old then return it end
            if name ~= "" then return { kind = "name", name = name, neg = it.neg } end
            if n then return { kind = "n", n = n, neg = it.neg } end
            return nil
        end
        if layer.list then
            local list = {}
            for _, it in ipairs(layer.list) do list[#list + 1] = swap(it) end
            layer.list = #list > 0 and list or { { kind = "none" } }
        end
        local kept = {}
        for _, pair in ipairs(layer.pairs or {}) do
            pair.item = swap(pair.item)
            if pair.item then kept[#kept + 1] = pair end
        end
        if layer.pairs and #kept == 0 then
            table.remove(layers, i)
        else
            if layer.pairs then layer.pairs = kept end
            i = i + 1
        end
    end
end

function M.rename_text(entry, name)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" and not valid_name(name) then return nil, lang.t("tracks_unknown", { token = name }) end

    local count        = #M.list("audio")
    local stop         = tail_start(chain.layers)
    local layer, at    = near_tail(chain.layers, stop, "rename")
    local input, names = M.run(chain.layers, count, at or stop)
    if not input then return nil, names end
    local label = M.entry_label(entry):lower()
    local k     = M.pair_index(layer, input, names, entry)
    for i = stop - 1, 1, -1 do
        if k then break end
        if chain.layers[i].op == "rename" then
            local before, bnames = M.run(chain.layers, count, i)
            k = before and M.pair_index(chain.layers[i], before, bnames, entry)
            if k then layer, at = chain.layers[i], i end
        end
    end
    local from = at or stop - 1
    if k then
        if name == "" then
            table.remove(layer.pairs, k)
            if #layer.pairs == 0 then
                table.remove(chain.layers, at)
                from = at - 1
            end
        else
            layer.pairs[k].name = name
        end
    elseif entry.kind == "mix" and type((entry.of or entry).layer) == "number" then
        from                    = (entry.of or entry).layer
        chain.layers[from].name = name ~= "" and name or nil
    elseif name ~= "" then
        local n = M.position(input, entry)
        if not n then return nil, lang.t("tracks_unknown", { token = M.entry_label(entry) }) end
        if not layer then
            layer = { op = "rename", pairs = {} }
            from  = stop
            table.insert(chain.layers, stop, layer)
        end
        layer.pairs[#layer.pairs + 1] = { item = { kind = "n", n = n }, name = name }
    end
    retarget(chain.layers, count, from, label, name, entry)

    local present, rerr = M.run(chain.layers, count)
    if not present then return nil, rerr end
    return M.format(chain)
end

function M.rebase(old, layers, from, shift)
    local count = #M.list("audio")
    for j = from + 1, #layers do
        local before = M.run(old, count, j - shift)
        local after  = M.run(layers, count, j)
        local function swap(it)
            if it.kind ~= "n" or not before or not after then return end
            local e = before[it.n]
            local n = e and M.position(after, e)
            if n then it.n = n end
        end
        for _, it in ipairs(layers[j].list or {}) do swap(it) end
        for _, pair in ipairs(layers[j].pairs or {}) do swap(pair.item) end
    end
end

function M.at_value(value)
    value   = value:match("^%s*(.-)%s*$")
    local n = tonumber(value:match("^%d+$") or "")
    if value ~= "" and (not n or n < 1) then return nil, lang.t("tracks_unknown", { token = value }) end
    return n or false
end

function M.set_move(layer, input, names, entry, n)
    local k = M.pair_index(layer, input, names, entry)
    if k and n then
        layer.pairs[k].at = n
    elseif k then
        table.remove(layer.pairs, k)
    elseif n then
        local pos = M.position(input, entry)
        if pos then layer.pairs[#layer.pairs + 1] = { item = { kind = "n", n = pos }, at = n } end
    end
end

local function apply_pairs(input, out)
    local current = filter(input, function() return true end)
    for _, pair in ipairs(out) do
        local e = table.remove(current, M.position(current, input[pair.item.n]))
        table.insert(current, math.min(pair.at, #current + 1), e)
    end
    return current
end

local function same_order(a, b)
    if #a ~= #b then return false end
    for k, e in ipairs(a) do
        if not M.same_entry(e, b[k]) then return false end
    end
    return true
end

local function order_pairs(input, wanted)
    local idx = {}
    for p, e in ipairs(wanted) do idx[p] = M.position(input, e) end
    local best  = nil
    local score = math.huge
    if #wanted <= 12 then
        for mask = 0, 2 ^ #wanted - 1 do
            local out  = {}
            local cost = 0
            local bit  = mask
            for p = 1, #wanted do
                if bit % 2 == 1 then
                    out[#out + 1] = { item = { kind = "n", n = idx[p] }, at = p }
                    cost          = cost + 100 + (idx[p] == p and 1 or 0)
                end
                bit = math.floor(bit / 2)
            end
            if cost < score and same_order(apply_pairs(input, out), wanted) then
                best  = out
                score = cost
            end
        end
    end
    if best then return best end

    local out = {}
    for p, e in ipairs(wanted) do
        if not M.same_entry(apply_pairs(input, out)[p], e) then out[#out + 1] = { item = { kind = "n", n = idx[p] }, at = p } end
    end
    return out
end

function M.place(layers, index, input, names, entry, n)
    local layer = layers[index]
    if not n then return M.set_move(layer, input, names, entry, nil) end
    local output = M.run(layers, #M.list("audio"), index + 1) or input
    local wanted = {}
    local picked = nil
    for _, e in ipairs(output) do
        if M.same_entry(e, entry) then
            picked = e
        else
            wanted[#wanted + 1] = e
        end
    end
    if not picked then return end
    table.insert(wanted, math.min(n, #wanted + 1), picked)
    layer.pairs = order_pairs(input, wanted)
end

function M.move_text(entry, value)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local n, verr = M.at_value(value)
    if n == nil then return nil, verr end

    local count        = #M.list("audio")
    local stop         = tail_start(chain.layers)
    local layer, at    = near_tail(chain.layers, stop, "move")
    local input, names = M.run(chain.layers, count, at or stop)
    if not input then return nil, names end
    local old   = M.parse(state.tracks).layers
    local shift = 0
    if not layer then
        layer = { op = "move", pairs = {} }
        at    = stop
        shift = 1
        table.insert(chain.layers, at, layer)
    end
    M.place(chain.layers, at, input, names, entry, n or nil)
    if #layer.pairs == 0 then
        table.remove(chain.layers, at)
        shift = shift - 1
        at    = at - 1
    end
    M.rebase(old, chain.layers, at, shift)

    local present, rerr = M.run(chain.layers, count)
    if not present then return nil, rerr end
    return M.format(chain)
end

local function flat(layers)
    local out = {}
    for _, layer in ipairs(layers) do
        if layer.op == "preset" then
            for _, inner in ipairs(flat(layer.layers)) do out[#out + 1] = inner end
        else
            out[#out + 1] = layer
        end
    end
    return out
end

local function dissolve(chain, layers)
    chain.layers = layers
    chain.video  = chain.video or chain.preset_video
end

function M.combine_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    local _, mix = tail(flat(chain.layers))
    return mix ~= nil
end

function M.only_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    local layers = flat(chain.layers)
    return only_layer(layers[#layers])
end

function M.toggle_combine()
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local layers       = flat(chain.layers)
    local _, mix, only = tail(layers)
    if mix or only then dissolve(chain, layers) end
    if mix then
        table.remove(chain.layers, mix)
        if only and not has_mix(chain.layers) then table.remove(chain.layers, #chain.layers) end
    else
        table.insert(chain.layers, only or #chain.layers + 1, { op = "mix", at = 1 })
    end
    save(chain)
    return not mix
end

function M.toggle_only()
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local layers = flat(chain.layers)
    if only_layer(layers[#layers]) then
        dissolve(chain, layers)
        table.remove(chain.layers, #chain.layers)
        save(chain)
        return false
    end
    if not has_mix(layers) then chain.layers[#chain.layers + 1] = { op = "mix", at = 1 } end
    chain.layers[#chain.layers + 1] = { op = "keep", list = { { kind = "mixes" } } }
    save(chain)
    return true
end

M.reload()

return M
