local mp    = require 'mp'
local state = require 'src.state'
local lang  = require 'src.lang'

local M = {}

local codec_exts   = { opus = "opus", aac = "m4a", alac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg" }
local encoder_exts = { opus = "opus", aac = "m4a", mp3 = "mp3", flac = "flac", vorbis = "ogg", pcm = "wav" }
local ops          = { keep = true, drop = true, mix = true, only = true, video = true }
local reserved     = { all = true, none = true, at = true }

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
    local word = name:lower()
    return name ~= "" and name == name:match("^%s*(.-)%s*$") and not name:find("[\",#]") and name:sub(1, 1) ~= "-"
        and not name:match("^%d+$") and not reserved[word] and not ops[word]
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
        elseif quoted and valid_name(quoted) then
            item = { kind = "name", name = quoted }
        elseif valid_name(part) and not part:find("%s") then
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
        elseif word == "only" then
            layers[#layers + 1] = { op = "only" }
        else
            return fail(token)
        end
    end
    return { layers = layers, video = video }
end

local function item_text(item)
    if item.kind == "n" then return tostring(item.n) end
    if item.kind == "name" then
        if item.name:find("%s") then return "\"" .. item.name .. "\"" end
        return item.name
    end
    return item.kind
end

local function list_text(list)
    local pos = {}
    local neg = {}
    for _, item in ipairs(list) do
        local target        = item.neg and neg or pos
        target[#target + 1] = item_text(item)
    end
    local parts = {}
    if #pos > 0 then parts[#parts + 1] = table.concat(pos, ",") end
    if #neg > 0 then parts[#parts + 1] = "-" .. table.concat(neg, ",") end
    return table.concat(parts, " ")
end

function M.layer_text(layer)
    if layer.op == "only" then return "only" end
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

local function filter(list, keep)
    local out = {}
    for _, e in ipairs(list) do
        if keep(e) then out[#out + 1] = e end
    end
    return out
end

local function sources(count)
    local out = {}
    for n = 1, count do out[n] = { kind = "source", n = n } end
    return out
end

function M.evaluate(chain, audio_count, video_count)
    local present = sources(audio_count)
    local names   = {}
    local unnamed = 0
    for _, layer in ipairs(chain.layers) do
        if layer.op == "keep" or layer.op == "drop" then
            local set, err = resolve(layer.list, present, names)
            if not set then return nil, err end
            local keep = layer.op == "keep"
            present    = filter(present, function(e) return (set[e] == true) == keep end)
        elseif layer.op == "mix" then
            local inputs = present
            if layer.list then
                local set, err = resolve(layer.list, present, names)
                if not set then return nil, err end
                inputs = filter(present, function(e) return set[e] == true end)
            end
            local name = layer.name
            if not name then
                repeat
                    unnamed = unnamed + 1
                    name    = unnamed == 1 and lang.t("tracks_mix") or lang.t("tracks_mix_n", { n = unnamed })
                until names[name:lower()] == nil
            elseif names[name:lower()] ~= nil then
                return nil, lang.t("tracks_name_taken", { name = name })
            end
            if #inputs >= 2 then
                local entry = { kind = "mix", name = name, inputs = filter(inputs, function() return true end) }
                local at    = math.min(layer.at or (#present + 1), #present + 1)
                present     = filter(present, function() return true end)
                table.insert(present, at, entry)
                names[name:lower()] = entry
            else
                names[name:lower()] = false
            end
        elseif layer.op == "only" then
            local mixes = filter(present, function(e) return e.kind == "mix" end)
            if #mixes > 0 then present = mixes end
        end
    end

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
    return tostring(entry.n)
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
        if e.kind ~= "source" or e.n ~= k then all = false end
    end
    if all then return lang.t("value_all") end
    local labels = {}
    for _, e in ipairs(out) do labels[#labels + 1] = M.entry_label(e) end
    return table.concat(labels, ", ")
end

local function tail(layers)
    local i    = #layers
    local only = layers[i] and layers[i].op == "only" and i or nil
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

function M.combine_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    local _, mix = tail(chain.layers)
    return mix ~= nil
end

function M.only_on()
    local chain = M.parse(state.tracks)
    if not chain then return false end
    local last = chain.layers[#chain.layers]
    return last ~= nil and last.op == "only"
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
    local last = chain.layers[#chain.layers]
    if last and last.op == "only" then
        table.remove(chain.layers, #chain.layers)
        save(chain)
        return false
    end
    if not has_mix(chain.layers) then chain.layers[#chain.layers + 1] = { op = "mix" } end
    chain.layers[#chain.layers + 1] = { op = "only" }
    save(chain)
    return true
end

return M
