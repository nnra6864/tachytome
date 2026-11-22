local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local conf   = require 'src.conf'

local M = {
    version = "2.2.0",
    done    = "migrate_user_done"
}

local old_main = utils.join_path(common.get_conf_dir(), "tachytome.conf")

local function read_lines(path)
    local lines = {}
    local f = io.open(path, "r")
    if not f then return lines end
    for line in f:lines() do lines[#lines + 1] = line:gsub("\r$", "") end
    f:close()
    return lines
end

local function write_lines(path, lines)
    local f = io.open(path, "w")
    if not f then
        mp.msg.warn("Failed to write " .. path)
        return false
    end
    f:write(#lines > 0 and table.concat(lines, "\n") .. "\n" or "")
    f:close()
    return true
end

local function backup(path)
    if not common.file_exists(path) then return nil end
    local bak = path .. ".bak"
    os.remove(bak)
    local ok, err = os.rename(path, bak)
    if not ok then
        mp.msg.warn("Failed to back up " .. path .. ": " .. tostring(err))
        return nil
    end
    return bak
end

local function split_configs(val)
    local kept    = {}
    local enabled = 0
    local seen    = false
    local place   = nil
    for entry in val:gmatch("[^,]+") do
        local name = entry:match("^%s*(.-)%s*$")
        local on   = name:sub(1, 1) ~= "!"
        local bare = (on and name or name:sub(2):match("^%s*(.-)$")):gsub("%.conf$", "")
        if bare == "default" then
            if not seen and on then place = enabled == 0 and "before" or "after" end
            seen = true
        elseif bare ~= "" then
            kept[#kept + 1] = name
            if on then enabled = enabled + 1 end
        end
    end
    return kept, place
end

local function own_lines(path)
    local out = {}
    local gap = false
    for _, line in ipairs(read_lines(path)) do
        if line:find("%S") and not line:find("^%s*#") then
            if gap and #out > 0 then out[#out + 1] = "" end
            out[#out + 1] = line
            gap           = false
        else
            gap = true
        end
    end
    return out
end

local function build()
    local main   = read_lines(old_main)
    local own    = own_lines(conf.default_path())
    local before = {}
    local after  = {}
    local kept   = {}
    local place  = nil
    local idx    = nil
    for i, line in ipairs(main) do
        if line:sub(1, 8) == "configs=" then
            idx = i
            break
        end
    end
    for i, line in ipairs(main) do
        if not idx or i < idx then
            before[#before + 1] = line
        elseif i > idx then
            after[#after + 1] = line
        end
    end
    if idx then kept, place = split_configs(main[idx]:sub(9)) end

    local commented = #own > 0 and not place
    if commented then
        for i, line in ipairs(own) do
            if line ~= "" then own[i] = "#" .. line end
        end
    end

    local configs  = #kept > 0 and { "configs=" .. table.concat(kept, ",") } or {}
    local sections = { before, own, configs, after }
    if place == "after" then sections = { before, configs, own, after } end
    sections[#sections + 1] = read_lines(conf.main_path())

    local lines = {}
    for _, section in ipairs(sections) do
        local first = 1
        local last  = #section
        while first <= last and not section[first]:find("%S") do first = first + 1 end
        while last >= first and not section[last]:find("%S") do last = last - 1 end
        if first <= last and #lines > 0 then lines[#lines + 1] = "" end
        for i = first, last do lines[#lines + 1] = section[i] end
    end
    return lines, kept, commented
end

function M.detect()
    return common.file_exists(old_main)
end

function M.prepare()
end

function M.plan()
    if not common.file_exists(old_main) then return nil end

    local lines, kept, commented = build()
    local moved = {}
    for _, line in ipairs(lines) do
        local key  = line:match("^([%w_]+)=")
        local menu = line:match("^menu%s+(%S+)")
        if key and key ~= "configs" then
            moved[#moved + 1] = key
        elseif menu then
            moved[#moved + 1] = "menu " .. menu
        end
    end

    local plan = { lines = { { key = "migrate_user_intro" } } }
    if #moved > 0 then
        plan.lines[#plan.lines + 1] = { key = "migrate_user_moved", list = moved }
    elseif not commented then
        plan.lines[#plan.lines + 1] = { key = "migrate_user_nothing" }
    end
    if commented then plan.lines[#plan.lines + 1] = { key = "migrate_user_commented" } end
    if #kept > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_user_configs", list = kept } end
    plan.lines[#plan.lines + 1] = { key = "migrate_user_removed" }
    return plan
end

function M.apply()
    common.ensure_dir(common.get_conf_dir())
    if write_lines(conf.main_path(), (build())) then os.remove(old_main) end
end

function M.skip()
    backup(old_main)
    backup(conf.default_path())
end

return M
