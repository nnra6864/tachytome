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

function M.tooltip(hints)
    local parts = {}
    for _, hint in ipairs(hints) do
        parts[#parts + 1] = lang.t("key_hint", { keys = hint[1], action = lang.t("key_" .. hint[2]) })
    end
    return M.dim("(" .. table.concat(parts, ", ") .. ")")
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
