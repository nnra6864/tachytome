local mp          = require 'mp'
local utils       = require 'mp.utils'
local common      = require 'src.common'
local conf        = require 'src.conf'
local tracks_step = require 'src.migrations.2_1_0'

local M = {
    version       = "2.0.0",
    follow_latest = true
}

local opts_dir  = mp.command_native({"expand-path", "~~/script-opts"})
local old_conf  = utils.join_path(opts_dir, "tachytome.conf")
local old_eff   = utils.join_path(opts_dir, "tachytome-effects.conf")
local stock_dir = utils.join_path(mp.get_script_directory() or "", "src/migrations/1.0.0")
local actions   = { ignore = "none", first_audio_only = "combined_audio_only" }
local options   = { first_audio_only = "combined_audio_only" }
local legacy    = { combine_audio = true, combined_audio_only = true, combined_audio_name = true }
local bases     = { builtin = "simple", default = "simple", example = "simple", nested = "default" }

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

local function strip(line)
    local hash = line:find("#", 1, true)
    if hash then line = line:sub(1, hash - 1) end
    return line:match("^%s*(.-)%s*$")
end

local function words(text)
    local list = {}
    for w in text:gmatch("%S+") do list[#list + 1] = w end
    return list
end

local function parse_conf(path)
    local parsed = { opts = {}, order = {}, blocks = {}, flats = {} }
    local block  = nil
    for _, line in ipairs(read_lines(path)) do
        local content = strip(line)
        local w       = words(content)
        local eq      = line:find("=", 1, true)
        if block then
            if content == "end" then
                parsed.blocks[#parsed.blocks + 1] = block
                block = nil
            elseif content ~= "" then
                block.lines[#block.lines + 1] = content
            end
        elseif w[1] == "keymap" and #w == 2 then
            block = { name = w[2], lines = {} }
        elseif w[1] == "keymap" and #w == 3 then
            parsed.flats[#parsed.flats + 1] = { seq = w[2], action = w[3] }
        elseif eq and line:sub(1, 1) ~= "#" then
            local key = line:sub(1, eq - 1)
            if parsed.opts[key] == nil then parsed.order[#parsed.order + 1] = key end
            parsed.opts[key] = line:sub(eq + 1)
        end
    end
    return parsed
end

local function parse_effects(path)
    local list  = {}
    local block = nil
    for _, line in ipairs(read_lines(path)) do
        local content = strip(line)
        local w       = words(content)
        if block then
            block.raw[#block.raw + 1] = line
            if content == "end" then
                list[#list + 1] = block
                block = nil
            elseif content ~= "" then
                block.lines[#block.lines + 1] = content
            end
        elseif w[1] == "effect" and #w == 2 then
            block = { name = w[2], lines = {}, raw = { line } }
        end
    end
    return list
end

local function same_block(a, b)
    if not b or #a.lines ~= #b.lines then return false end
    for i, line in ipairs(a.lines) do
        if line ~= b.lines[i] then return false end
    end
    return true
end

local function by_name(blocks)
    local map = {}
    for _, b in ipairs(blocks) do map[b.name] = b end
    return map
end

local function builtin_names()
    local opts  = {}
    local menus = {}
    for _, line in ipairs(read_lines(conf.builtin_path)) do
        local key = line:match("^([%w_]+)=")
        if key then opts[key] = true end
        local menu = line:match("^menu%s+(%S+)%s+{")
        if menu then menus[menu] = true end
    end
    return opts, menus
end

local function old_data_dir()
    if common.get_platform() ~= "linux" then return nil end
    local base = os.getenv("XDG_DATA_HOME") or ""
    if base == "" then base = utils.join_path(os.getenv("HOME") or "~", ".local/share") end
    return utils.join_path(base, "tachytome")
end

local function fix_queue(path)
    local data = common.read_json_file(path)
    if type(data) ~= "table" then return end
    for _, item in ipairs(data.items or data) do
        if type(item) == "table" and item.first_audio_only ~= nil then
            item.combined_audio_only = item.first_audio_only
            item.first_audio_only    = nil
        end
    end
    common.write_json_file(path, data)
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

local function asks()
    return (common.file_exists(old_conf) and not common.file_exists(conf.main_path())) or common.file_exists(old_eff)
end

function M.detect()
    local old = old_data_dir()
    return asks() or (old ~= nil and utils.file_info(old) ~= nil)
end

function M.prepare()
    local new = common.get_state_dir()
    local old = old_data_dir()
    if old and old ~= new and utils.file_info(old) then
        for _, name in ipairs(utils.readdir(old, "files") or {}) do
            local dest = utils.join_path(new, name)
            if not utils.file_info(dest) then
                local ok, err = os.rename(utils.join_path(old, name), dest)
                if not ok then mp.msg.warn("Failed to move " .. name .. " to " .. new .. ": " .. tostring(err)) end
            end
        end
        os.remove(old)
    end

    local legacy = utils.join_path(new, "queue.json")
    if utils.file_info(legacy) then os.rename(legacy, utils.join_path(new, "queue-0.json")) end
    for _, name in ipairs(utils.readdir(new, "files") or {}) do
        if name:match("^queue%-%d+%.json$") then fix_queue(utils.join_path(new, name)) end
    end
end

function M.plan()
    if not asks() then return nil end

    local plan = { options = {}, dropped = {}, menus = {}, menu_lines = {}, effects = {}, effect_lines = {}, backups = {} }
    local known, builtin_menus = builtin_names()

    if common.file_exists(old_conf) and not common.file_exists(conf.main_path()) then
        local stock  = parse_conf(utils.join_path(stock_dir, "tachytome.conf"))
        local user   = parse_conf(old_conf)
        local stocks = by_name(stock.blocks)

        local old_tracks = {}
        for _, key in ipairs(user.order) do
            local val = user.opts[key]
            local new = options[key] or key
            if key ~= "selected_keymap" and val ~= stock.opts[key] then
                if legacy[new] then
                    old_tracks[new] = val
                elseif known[new] then
                    plan.options[#plan.options + 1] = { key = new, val = val }
                else
                    plan.dropped[#plan.dropped + 1] = key
                end
            end
        end
        local chain = tracks_step.chain(old_tracks)
        if chain ~= "" then plan.options[#plan.options + 1] = { key = "tracks", val = chain } end

        local renamed = {}
        local kept    = {}
        for _, b in ipairs(user.blocks) do
            if not same_block(b, stocks[b.name]) then
                local name = b.name
                if builtin_menus[name] or name == "builtin" then name = "old_" .. name end
                renamed[b.name] = name
                kept[#kept + 1] = b
            end
        end

        local function base(name)
            return renamed[name] or bases[name] or name
        end

        local function action(name)
            return actions[name] or name
        end

        for _, b in ipairs(kept) do
            plan.menus[#plan.menus + 1] = renamed[b.name]
            plan.menu_lines[#plan.menu_lines + 1] = ""
            plan.menu_lines[#plan.menu_lines + 1] = "menu " .. renamed[b.name] .. " {"
            for _, line in ipairs(b.lines) do
                local w = words(line)
                if w[1] == "base" and #w == 2 then
                    plan.menu_lines[#plan.menu_lines + 1] = "    base " .. base(w[2])
                elseif #w == 2 then
                    plan.menu_lines[#plan.menu_lines + 1] = "    " .. w[1] .. " " .. action(w[2])
                end
            end
            plan.menu_lines[#plan.menu_lines + 1] = "}"
        end

        if #user.flats > 0 then plan.menu_lines[#plan.menu_lines + 1] = "" end
        for _, f in ipairs(user.flats) do
            plan.menu_lines[#plan.menu_lines + 1] = "menu " .. f.seq .. " " .. action(f.action)
        end
        plan.rebinds = #user.flats

        plan.backups[#plan.backups + 1] = "tachytome.conf"
    end

    if common.file_exists(old_eff) then
        local stocks = by_name(parse_effects(utils.join_path(stock_dir, "tachytome-effects.conf")))
        for _, b in ipairs(parse_effects(old_eff)) do
            if not same_block(b, stocks[b.name]) then
                plan.effects[#plan.effects + 1] = b.name
                if #plan.effect_lines > 0 then plan.effect_lines[#plan.effect_lines + 1] = "" end
                for _, line in ipairs(b.raw) do plan.effect_lines[#plan.effect_lines + 1] = line end
            end
        end
        plan.backups[#plan.backups + 1] = "tachytome-effects.conf"
    end

    plan.lines = { { key = "migrate_intro" } }
    if #plan.options > 0 then
        local list = {}
        for _, o in ipairs(plan.options) do list[#list + 1] = o.key .. "=" .. o.val end
        plan.lines[#plan.lines + 1] = { key = "migrate_options", list = list }
    else
        plan.lines[#plan.lines + 1] = { key = "migrate_no_options" }
    end
    if #plan.dropped > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_dropped", list = plan.dropped } end
    if #plan.menus > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_menus", list = plan.menus } end
    if (plan.rebinds or 0) > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_rebinds", count = plan.rebinds } end
    plan.lines[#plan.lines + 1] = { key = "migrate_menu" }
    if #plan.effects > 0 then plan.lines[#plan.lines + 1] = { key = "migrate_effects", list = plan.effects } end
    plan.lines[#plan.lines + 1] = { key = "migrate_backup", list = plan.backups }
    return plan
end

function M.apply(plan)
    backup(old_conf)
    backup(old_eff)

    local dir   = common.get_conf_dir()
    local lines = {}
    common.ensure_dir(dir)
    for _, o in ipairs(plan.options) do lines[#lines + 1] = o.key .. "=" .. o.val end
    for _, line in ipairs(plan.menu_lines) do
        if #lines > 0 or line ~= "" then lines[#lines + 1] = line end
    end
    write_lines(conf.main_path(), lines)

    common.ensure_default_conf("tachytome-effects.conf", "default.eff")
    if #plan.effect_lines > 0 then write_lines(utils.join_path(dir, "custom.eff"), plan.effect_lines) end
end

function M.skip()
    backup(old_conf)
    backup(old_eff)
end

return M
