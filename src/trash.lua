local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'
local queue  = require 'src.queue'
local notify = require 'src.notify'
local lang   = require 'src.lang'

local M = {}

local pending = {}

function M.users(path)
    local count = 0
    if queue.active and common.same_path(queue.active.input_file, path) then count = count + 1 end
    for _, job in ipairs(queue.jobs) do
        if common.same_path(job.input_file, path) then count = count + 1 end
    end
    for _, rec in ipairs(queue.failed) do
        if common.same_path(rec.input_file, path) then count = count + 1 end
    end
    return count
end

function M.in_use(path)
    return M.users(path) > 0
end

function M.pending(path)
    for p in pairs(pending) do
        if common.same_path(p, path) then return true end
    end
    return false
end

local function unload(path, on_done)
    local pos = mp.get_property_number("playlist-pos", -1)
    for i = mp.get_property_number("playlist-count", 0) - 1, 0, -1 do
        if i ~= pos and common.same_path(mp.get_property("playlist/" .. i .. "/filename"), path) then
            mp.commandv("playlist-remove", tostring(i))
        end
    end
    if not common.same_path(mp.get_property("path"), path) then return on_done() end

    pos = mp.get_property_number("playlist-pos", -1)
    if pos >= mp.get_property_number("playlist-count", 0) - 1 and mp.get_property("loop-playlist") == "no" then
        mp.set_property("idle", "yes")
        if mp.get_property("current-vo") then mp.set_property("force-window", "yes") end
    end

    local function ended()
        mp.unregister_event(ended)
        on_done()
    end
    mp.register_event("end-file", ended)
    mp.commandv("playlist-remove", "current")
end

function M.now(path, trash_path, on_done)
    unload(path, function()
        common.trash_file(path, trash_path, function(success)
            if success then
                notify.show(lang.t("trash_done"), true)
            else
                notify.show(lang.t("trash_failed"), true, "error")
            end
            if on_done then on_done(success) end
        end)
    end)
end

function M.settle(path)
    for p, trash_path in pairs(pending) do
        if common.same_path(p, path) and not M.in_use(p) then
            pending[p] = nil
            if utils.file_info(p) then M.now(p, trash_path) end
        end
    end
end

function M.request(path, trash_path)
    if not path or not trash_path then return end
    pending[path] = trash_path
    if M.in_use(path) then
        local _, name = utils.split_path(path)
        notify.show(lang.t("trash_waiting", { name = name }), true)
        return
    end
    M.settle(path)
end

return M
