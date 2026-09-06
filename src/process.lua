local mp     = require 'mp'
local utils  = require 'mp.utils'
local common = require 'src.common'

local M = {}

local platform = common.get_platform()

function M.signal_pid(pid, sig)
    mp.command_native_async({
        name           = "subprocess",
        args           = {"kill", "-" .. sig, tostring(pid)},
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    })
end

function M.process_comm(pid)
    if not pid then return nil end
    if platform == "linux" then
        local f = io.open(string.format("/proc/%d/comm", pid), "r")
        if not f then return nil end
        local comm = f:read("*l")
        f:close()
        return comm
    elseif platform == "macos" then
        local res = utils.subprocess({args = {"ps", "-p", tostring(pid), "-o", "comm="}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" then
            return res.stdout:gsub("[\r\n]+$", "")
        end
    elseif platform == "windows" then
        local res = utils.subprocess({args = {"tasklist", "/FI", "PID eq " .. tostring(pid), "/FO", "CSV", "/NH"}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" and not res.stdout:find("INFO:") then
            return res.stdout:match("^\"([^\"]+)\"")
        end
    end
    return nil
end

function M.mpv_alive(pid)
    local comm = M.process_comm(pid)
    return comm ~= nil and comm:lower():find("mpv", 1, true) ~= nil
end

function M.process_args(pid)
    if not pid then return nil end
    if platform == "linux" then
        local f = io.open(string.format("/proc/%d/cmdline", pid), "r")
        if not f then return nil end
        local data = f:read("*all")
        f:close()
        if not data or data == "" then return nil end
        return data
    end
    if platform == "macos" then
        local res = utils.subprocess({args = {"ps", "-p", tostring(pid), "-o", "command="}, cancellable = false})
        if res.status == 0 and res.stdout and res.stdout ~= "" then
            return res.stdout:gsub("[\r\n]+$", "")
        end
    end
    return nil
end

return M
