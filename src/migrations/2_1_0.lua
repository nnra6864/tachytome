local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'

local M = {
    version = "2.1.0",
    done    = "migrate_tracks_done",
    skipped = "migrate_tracks_skipped"
}

local old_keys = { combine_audio = true, combined_audio_only = true, combined_audio_name = true, audio_tracks = true, video_tracks = true }

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
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    return true
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
        if name and name ~= "" and name ~= "Combined" and not name:find("[\",#]") then
            parts[#parts + 1] = "mix \"" .. name .. "\""
        else
            parts[#parts + 1] = "mix"
        end
        if yes(o.combined_audio_only) then parts[#parts + 1] = "only" end
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

function M.detect()
    return #scan() > 0
end

function M.prepare()
    local dir = common.get_state_dir()
    for _, name in ipairs(utils.readdir(dir, "files") or {}) do
        if name:match("^queue%-%d+%.json$") then fix_queue(utils.join_path(dir, name)) end
    end
end

function M.plan()
    local found = scan()
    if #found == 0 then return nil end
    local list = {}
    for _, f in ipairs(found) do list[#list + 1] = string.format("%s: tracks=%s", f.name, f.chain) end
    return {
        files = found,
        lines = {
            { key = "migrate_tracks_intro" },
            { key = "migrate_tracks", list = list }
        }
    }
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
end

function M.skip()
end

return M
