local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local conf   = require 'src.conf'

local M = {
    version = "2.1.0"
}

local old_keys  = { combine_audio = true, combined_audio_only = true, combined_audio_name = true, audio_tracks = true, video_tracks = true }
local stock_eff = utils.join_path(mp.get_script_directory() or "", "src/migrations/2.0.0/tachytome-effects.conf")
local old_main  = utils.join_path(common.get_conf_dir(), "tachytome.conf")

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

local function yes(val)
    return val == true or val == "yes"
end

local function list_of(val)
    if val == nil then return nil end
    if type(val) == "table" then
        local out = {}
        for _, n in ipairs(val) do out[#out + 1] = tostring(n) end
        if #out == 0 then return "none" end
        return table.concat(out, ",")
    end
    local spec = tostring(val):lower():match("^%s*(.-)%s*$")
    if spec == "all" then return nil end
    local out = {}
    for entry in spec:gmatch("[^,]+") do
        local n = entry:match("^%s*(%d+)%s*$")
        if n and tonumber(n) >= 1 then out[#out + 1] = n end
    end
    if #out == 0 then return "none" end
    return table.concat(out, ",")
end

function M.chain(o)
    local parts = {}
    local audio = list_of(o.audio_tracks)
    local video = list_of(o.video_tracks)
    if audio then parts[#parts + 1] = "keep " .. audio end
    if yes(o.combine_audio) then
        local name = o.combined_audio_name
        if not name or name == "" or name:find("[\",#]") then name = "Combined" end
        parts[#parts + 1] = "mix \"" .. name .. "\" at 1"
        if yes(o.combined_audio_only) then parts[#parts + 1] = "keep @mixes" end
    end
    if video then parts[#parts + 1] = "video " .. video end
    return table.concat(parts, " ")
end

local function conf_files()
    local dir   = common.get_conf_dir()
    local files = {}
    for _, name in ipairs(utils.readdir(dir, "files") or {}) do
        if name:match("%.conf$") then files[#files + 1] = name end
    end
    table.sort(files)
    return dir, files
end

local function scan()
    local dir, files = conf_files()
    local found      = {}
    for _, name in ipairs(files) do
        local path  = utils.join_path(dir, name)
        local lines = read_lines(path)
        local opts  = {}
        local rows  = {}
        for i, line in ipairs(lines) do
            local eq  = line:find("=", 1, true)
            local key = eq and line:sub(1, 1) ~= "#" and line:sub(1, eq - 1)
            if key and old_keys[key] then
                opts[key]       = line:sub(eq + 1)
                rows[#rows + 1] = i
            end
        end
        if #rows > 0 then found[#found + 1] = { name = name, path = path, rows = rows, chain = M.chain(opts) } end
    end
    return found
end

local function fix_queue(path)
    local data = common.read_json_file(path)
    if type(data) ~= "table" then return end
    for _, item in ipairs(data.items or data) do
        if type(item) == "table" and item.tracks == nil then
            item.tracks              = M.chain(item)
            item.combine_audio       = nil
            item.combined_audio_only = nil
            item.combined_audio_name = nil
            item.audio_tracks        = nil
            item.video_tracks        = nil
        end
    end
    common.write_json_file(path, data)
end

local function renew_default_eff()
    local path  = utils.join_path(common.get_conf_dir(), "default.eff")
    local stock = read_lines(stock_eff)
    if #stock == 0 or table.concat(read_lines(path), "\n") ~= table.concat(stock, "\n") then return end
    os.remove(path)
    common.ensure_default_conf("tachytome-effects.conf", "default.eff")
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

local function build_user()
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

local function user_lines(plan)
    local lines, kept, commented = build_user()
    local moved = {}
    for _, line in ipairs(lines) do
        local key  = line:match("^([%w_]+)=")
        local menu = line:match("^menu%s+(%S+)")
        if key and key ~= "configs" and not old_keys[key] then
            moved[#moved + 1] = key
        elseif menu then
            moved[#moved + 1] = "menu " .. menu
        end
    end

    plan.lines[#plan.lines + 1] = { key = "migrate_user_intro" }
    if #moved > 0 then
        plan.lines[#plan.lines + 1] = { key = "migrate_user_moved", list = moved }
    elseif not commented then
        plan.lines[#plan.lines + 1] = { key = "migrate_user_nothing" }
    end
    if commented then plan.lines[#plan.lines + 1] = { key = "migrate_user_commented" } end
    if #kept > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_user_configs", list = kept } end
    plan.lines[#plan.lines + 1] = { key = "migrate_user_removed" }
end

function M.detect()
    return #scan() > 0 or common.file_exists(old_main)
end

function M.prepare()
    local dir = common.get_state_dir()
    for _, name in ipairs(utils.readdir(dir, "files") or {}) do
        if name:match("^queue%-%d+%.json$") then fix_queue(utils.join_path(dir, name)) end
    end
    renew_default_eff()
end

function M.plan()
    local found = scan()
    local user  = common.file_exists(old_main)
    if #found == 0 and not user then return nil end

    local plan = { files = found, user = user, lines = {} }
    if #found > 0 then
        local list = {}
        for _, f in ipairs(found) do list[#list + 1] = string.format("%s: tracks=%s", f.name, f.chain) end
        plan.lines[#plan.lines + 1] = { key = "migrate_tracks_intro" }
        plan.lines[#plan.lines + 1] = { key = "migrate_tracks", list = list }
    end
    if user then user_lines(plan) end
    plan.done    = user and "migrate_user_done" or "migrate_tracks_done"
    plan.skipped = user and "migrate_skipped" or "migrate_tracks_skipped"
    return plan
end

function M.apply(plan)
    for _, f in ipairs(plan.files) do
        local lines = read_lines(f.path)
        for k = #f.rows, 1, -1 do
            if k == 1 and f.chain ~= "" then
                lines[f.rows[k]] = "tracks=" .. f.chain
            else
                table.remove(lines, f.rows[k])
            end
        end
        write_lines(f.path, lines)
    end

    if not plan.user or not common.file_exists(old_main) then return end
    common.ensure_dir(common.get_conf_dir())
    if write_lines(conf.main_path(), (build_user())) then os.remove(old_main) end
end

function M.skip(plan)
    if not plan.user then return end
    backup(old_main)
    backup(conf.default_path())
end

return M
