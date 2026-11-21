local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local state  = require 'src.state'
local lang   = require 'src.lang'

local M = {}

local history_path = utils.join_path(common.get_state_dir(), "tracks_history.json")
local codec_exts   = { opus = "opus", aac = "m4a", alac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg" }
local encoder_exts = { opus = "opus", aac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg", pcm = "wav" }
local ops          = { keep = true, drop = true, mix = true, rename = true, video = true }
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

local function bare_name(name)
    local word = name:lower()
    return valid_name(name) and not name:find("%s") and not name:find("^[-@]") and not name:match("^%d+$") and not reserved[word] and not ops[word]
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

function M.parse(text)
    local tokens, bad = tokenize(text or "")
    if not tokens then return nil, lang.t("tracks_unknown", { token = bad }) end
    local layers = {}
    local video  = nil
    local i      = 1

    local function fail(token)
        return nil, lang.t("tracks_unknown", { token = token })
    end

    local function lists()
        local items = {}
        while tokens[i] and not ops[tokens[i]:lower()] and tokens[i]:lower() ~= "at" do
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
            else
                layers[#layers + 1] = { op = word, list = items }
            end
        elseif word == "mix" then
            local layer = { op = "mix" }
            while tokens[i] and not ops[tokens[i]:lower()] do
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
            while tokens[i] and not ops[tokens[i]:lower()] do
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
        else
            return fail(token)
        end
    end
    return { layers = layers, video = video }
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
    if layer.op == "rename" then
        local parts = { "rename" }
        for _, pair in ipairs(layer.pairs) do parts[#parts + 1] = item_text(pair.item) .. " \"" .. pair.name .. "\"" end
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
            for _, e in ipairs(present) do
                if e.kind == "source" and e.n == item.n then found = { e } end
            end
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
    for i, layer in ipairs(layers) do
        if upto and i >= upto then break end
        if layer.op == "keep" or layer.op == "drop" then
            local set, err = resolve(layer.list, present, names)
            if not set then return nil, err, steps end
            local keep = layer.op == "keep"
            present    = filter(present, function(e) return (set[e] == true) == keep end)
        elseif layer.op == "mix" then
            local inputs = present
            if layer.list then
                local set, err = resolve(layer.list, present, names)
                if not set then return nil, err, steps end
                inputs = filter(present, function(e) return set[e] == true end)
            end
            local name = layer.name
            if not name then
                repeat
                    unnamed = unnamed + 1
                    name    = unnamed == 1 and lang.t("tracks_mix") or lang.t("tracks_mix_n", { n = unnamed })
                until names[name:lower()] == nil
            elseif names[name:lower()] ~= nil then
                return nil, lang.t("tracks_name_taken", { name = name }), steps
            end
            if #inputs >= 1 then
                local entry = { kind = "mix", name = name, layer = i, inputs = filter(inputs, function() return true end) }
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
                if not set then return nil, err, steps end
                for k, e in ipairs(present) do
                    if set[e] then
                        local taken = names[pair.name:lower()]
                        if taken ~= nil and taken ~= e then return nil, lang.t("tracks_name_taken", { name = pair.name }), steps end
                        local renamed            = alias(e, pair.name)
                        present[k]               = renamed
                        names[pair.name:lower()] = renamed
                    end
                end
            end
        end
        steps[i] = present
    end
    return present, names, steps
end

M.resolve = resolve

function M.evaluate(chain, audio_count, video_count)
    local present, names = M.run(chain.layers, audio_count)
    if not present then return nil, names end

    local video = nil
    if chain.video then
        local list     = sources(video_count)
        local set, err = resolve(chain.video, list, {})
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

local function same_item(a, b)
    if a.kind ~= b.kind then return false end
    if a.kind == "n" then return a.n == b.n end
    return a.name:lower() == b.name:lower()
end

local function entry_item(entry)
    if entry.kind == "mix" then return { kind = "name", name = entry.name } end
    return { kind = "n", n = entry.n }
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

function M.list_for(set, present, exclude, op)
    local items  = {}
    local picked = 0
    for _, e in ipairs(present) do
        if set[e] == true then picked = picked + 1 end
        if (set[e] == true) ~= exclude then
            local item        = entry_item(e)
            item.neg          = exclude or nil
            items[#items + 1] = item
        end
    end
    local every = #present > 0 and picked == #present
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

function M.rows(kind)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local list = M.list(kind)
    local rows = {}
    if kind == "video" then
        local result, verr = M.evaluate({ layers = {}, video = chain.video }, 0, #list)
        if not result then return nil, verr end
        for n, t in ipairs(list) do rows[n] = { entry = { kind = "source", n = n }, track = t, on = M.kept(result.video, n) } end
        return rows
    end

    local drop, mix, only = tail(chain.layers)
    local stop            = drop or mix or only or #chain.layers + 1
    local before          = {}
    for i = 1, stop - 1 do before[i] = chain.layers[i] end
    local result, rerr = M.evaluate({ layers = before }, #list, 0)
    if not result then return nil, rerr end
    for k, e in ipairs(result.audio) do
        local on = true
        if drop then
            for _, item in ipairs(chain.layers[drop].list) do
                if same_item(item, entry_item(e)) then on = false end
            end
        end
        rows[k] = { entry = e, track = e.kind == "source" and list[e.n] or nil, on = on }
    end
    return rows
end

function M.toggle(kind, entry)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    if kind == "video" then
        local count  = #M.list("video")
        local result = M.evaluate({ layers = {}, video = chain.video }, 0, count)
        local on     = {}
        for n = 1, count do on[n] = result and M.kept(result.video, n) end
        on[entry.n]  = not on[entry.n]
        local items  = {}
        for n = 1, count do
            if on[n] then items[#items + 1] = { kind = "n", n = n } end
        end
        if #items == count then
            chain.video = nil
        elseif #items == 0 then
            chain.video = { { kind = "none" } }
        else
            chain.video = items
        end
        save(chain)
        return on[entry.n]
    end

    local drop, mix, only = tail(chain.layers)
    local item            = entry_item(entry)
    if not drop then
        drop = mix or only or #chain.layers + 1
        table.insert(chain.layers, drop, { op = "drop", list = {} })
    end
    local list = chain.layers[drop].list
    for i, other in ipairs(list) do
        if same_item(other, item) then
            table.remove(list, i)
            if #list == 0 then table.remove(chain.layers, drop) end
            save(chain)
            return true
        end
    end
    list[#list + 1] = item
    save(chain)
    return false
end

local function rename_pair(layer, match)
    if not layer or layer.op ~= "rename" then return nil end
    for k, pair in ipairs(layer.pairs) do
        if match(pair) then return k end
    end
    return nil
end

local function retarget(layers, from, old, item)
    local function swap(it)
        if it.kind ~= "name" or it.name:lower() ~= old then return end
        it.kind = item.kind
        it.name = item.name
        it.n    = item.n
    end
    for i = from + 1, #layers do
        for _, it in ipairs(layers[i].list or {}) do swap(it) end
        for _, pair in ipairs(layers[i].pairs or {}) do swap(pair.item) end
    end
end

function M.rename_text(entry, name)
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" and not valid_name(name) then return nil, lang.t("tracks_unknown", { token = name }) end

    local drop, mix, only = tail(chain.layers)
    local stop            = drop or mix or only or #chain.layers + 1
    local layer           = chain.layers[stop - 1]
    local label           = M.entry_label(entry):lower()
    local k               = rename_pair(layer, function(pair) return pair.name:lower() == label end)
    if not k and entry.kind == "source" then k = rename_pair(layer, function(pair) return same_item(pair.item, entry_item(entry)) end) end

    local from = stop - 1
    local item = name ~= "" and { kind = "name", name = name } or nil
    if k then
        if name == "" then
            item = entry_item(entry.of or entry)
            table.remove(layer.pairs, k)
            if #layer.pairs == 0 then table.remove(chain.layers, from) end
        else
            layer.pairs[k].name = name
        end
    elseif entry.kind == "mix" then
        local root              = entry.of or entry
        from                    = root.layer
        chain.layers[from].name = name ~= "" and name or nil
        if not item then
            local _, _, steps = M.run(chain.layers, #M.list("audio"), from + 1)
            for _, e in ipairs(steps[from] or {}) do
                if e.layer == from and not e.of then item = { kind = "name", name = e.name } end
            end
        end
    elseif name ~= "" then
        if not layer or layer.op ~= "rename" then
            layer = { op = "rename", pairs = {} }
            table.insert(chain.layers, stop, layer)
            from = stop
        end
        layer.pairs[#layer.pairs + 1] = { item = entry_item(entry), name = name }
    end
    if item and label ~= (item.name or ""):lower() then retarget(chain.layers, from, label, item) end

    local present, rerr = M.run(chain.layers, #M.list("audio"))
    if not present then return nil, rerr end
    return M.format(chain)
end

function M.combine_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    local _, mix = tail(chain.layers)
    return mix ~= nil
end

function M.only_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    return only_layer(chain.layers[#chain.layers])
end

function M.toggle_combine()
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    local _, mix, only = tail(chain.layers)
    if mix then
        table.remove(chain.layers, mix)
        if only and not has_mix(chain.layers) then table.remove(chain.layers, #chain.layers) end
    else
        table.insert(chain.layers, only or #chain.layers + 1, { op = "mix" })
    end
    save(chain)
    return not mix
end

function M.toggle_only()
    local chain, err = M.parse(state.tracks)
    if not chain then return nil, err end
    if only_layer(chain.layers[#chain.layers]) then
        table.remove(chain.layers, #chain.layers)
        save(chain)
        return false
    end
    if not has_mix(chain.layers) then chain.layers[#chain.layers + 1] = { op = "mix" } end
    chain.layers[#chain.layers + 1] = { op = "keep", list = { { kind = "mixes" } } }
    save(chain)
    return true
end

return M
