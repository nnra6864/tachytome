local mp      = require 'mp'
local utils   = require 'mp.utils'
local common  = require 'src.common'
local conf    = require 'src.conf'
local version = require 'src.version'

local M = {
    pending = {},
    ran     = {}
}

local steps = {
    require 'src.migrations.2_0_0',
    require 'src.migrations.2_1_0'
}

local version_path = utils.join_path(common.get_state_dir(), "version")

local function read_version()
    local f = io.open(version_path, "r")
    if not f then return nil end
    local val = (f:read("*l") or ""):match("^%s*(.-)%s*$")
    f:close()
    if val == "" then return nil end
    return val
end

function M.finish()
    conf.hold = false
    local f = io.open(version_path, "w")
    if not f then
        mp.msg.warn("Failed to write " .. version_path)
        return
    end
    f:write(version.current .. "\n")
    f:close()
end

local stored = read_version()
local due    = false
for _, step in ipairs(steps) do
    if stored then
        due = version.compare(step.version, stored) > 0 and version.compare(step.version, version.current) <= 0
    elseif not due then
        due = step.detect()
    end
    if due then
        step.prepare()
        M.ran[#M.ran + 1] = step
        local plan = step.plan()
        if plan then M.pending[#M.pending + 1] = { step = step, plan = plan } end
    end
end

if #M.pending > 0 then
    conf.hold = true
else
    M.finish()
end

return M
