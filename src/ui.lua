local mp     = require 'mp'
local common = require 'src.common'
local theme  = require 'src.theme'
local lang   = require 'src.lang'

local M = {}

local visible_rows = 15

function M.clear_osd()
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
end

function M.title(text)
    return string.format("%s%s%s%s%s%s", theme.align(7), theme.f(), theme.b(true), theme.c("text_color"), theme.escape(text), theme.b(false))
end

function M.dim(text)
    return string.format("\\N%s%s%s%s", theme.f(true), theme.c("dim_text_color"), theme.escape(text), theme.reset())
end

local key_rank    = { Tab = 1, ["0-9"] = 2, Enter = 3, Esc = 4 }
local nav_rank    = { navigate = 1, history = 2, move = 3, search = 4 }
local action_rank = { add = 1, presets = 2, use = 3, tracks = 4, type = 5, name = 6, position = 7, mode = 8, scaler = 9, path = 10, edit = 11, audio = 12, video = 13, delete = 14 }

function M.tooltip(hints)
    local groups = { {}, {}, {} }
    for i, hint in ipairs(hints) do
        local key  = hint[1]:match("^[^/]+")
        local row  = key_rank[key] and 3 or nav_rank[hint[2]] and 1 or 2
        local rank = key_rank[key] or nav_rank[hint[2]] or action_rank[hint[2]] or 100
        local list = groups[row]
        list[#list + 1] = { rank = rank, i = i, text = lang.t("key_hint", { keys = hint[1], action = lang.t("key_" .. hint[2]) }) }
    end
    local out = string.format("\\N%s%s%s", theme.f(true), theme.c("text_color"), theme.escape(lang.t("keys_title")))
    for _, list in ipairs(groups) do
        if #list > 0 then
            table.sort(list, function(a, b)
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.i < b.i
            end)
            local parts = {}
            for k, part in ipairs(list) do parts[k] = theme.escape(part.text) end
            out = out .. string.format("\\N%s%s", theme.c("dim_text_color"), table.concat(parts, "\\h\\h"))
        end
    end
    return out .. theme.reset()
end

function M.wrap(index, delta, count)
    if count < 1 then return index end
    return (index - 1 + delta) % count + 1
end

function M.number_key(i)
    if i <= 9 then return tostring(i) end
    if i == 10 then return "0" end
    return nil
end

function M.number_prefix(i)
    local key = M.number_key(i)
    return key and key .. " -> " or string.rep("\\h", 5)
end

function M.visible(count, keep)
    local out = {}
    for i = 1, count do
        if keep(i) then out[#out + 1] = i end
    end
    return out
end

function M.position(vis, index)
    for k, i in ipairs(vis) do
        if i == index then return k end
    end
    return 0
end

function M.step(vis, index, delta)
    if #vis == 0 then return index end
    local at = M.position(vis, index)
    if at == 0 then return vis[1] end
    return vis[M.wrap(at, delta, #vis)]
end

function M.list(count, cursor, line)
    local start_idx = math.max(1, cursor - math.floor(visible_rows / 2))
    local end_idx   = math.min(count, start_idx + visible_rows - 1)
    if end_idx - start_idx < visible_rows - 1 then start_idx = math.max(1, end_idx - visible_rows + 1) end

    local text = start_idx > 1 and "\\N\\h\\h..." or ""
    for i = start_idx, end_idx do
        local prefix = i == cursor and theme.c("value_color") .. "\\h> " or "\\h\\h"
        text = text .. string.format("\\N%s%s%s%s", theme.c("text_color"), prefix, line(i), theme.reset())
    end
    if end_idx < count then text = text .. "\\N\\h\\h..." end
    return text
end

function M.rows(rows)
    local max_key_len   = 0
    local max_label_len = 0
    for _, row in ipairs(rows) do
        max_key_len = math.max(max_key_len, common.text_len(row.keys))
        if row.value then max_label_len = math.max(max_label_len, common.text_len(row.label)) end
    end

    local text = ""
    for _, row in ipairs(rows) do
        local key_pad = string.rep("\\h", max_key_len - common.text_len(row.keys))
        local line    = string.format("%s%s -> %s", key_pad, theme.escape(row.keys), theme.escape(row.label))
        if row.value then
            local val_pad = string.rep("\\h", max_label_len - common.text_len(row.label) + 1)
            line = string.format("%s%s> %s%s%s", line, val_pad, theme.c("value_color"), theme.escape(row.value), theme.reset())
        end
        text = text .. "\\N" .. line
    end
    return text
end

return M
