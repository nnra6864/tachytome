local mp         = require 'mp'
local utils      = require 'mp.utils'
local queue      = require 'src.queue'
local notify     = require 'src.notify'
local ui_confirm = require 'src.ui_confirm'

local M = {}

local branch      = "master"
local archive_url = "https://github.com/nnra6864/tachytome/archive/refs/heads/" .. branch .. ".tar.gz"
local busy        = false

local function run(args, callback)
    mp.command_native_async({
        name           = "subprocess",
        args           = args,
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        local ok  = success and result and result.status == 0
        local out = result and result.stdout and result.stdout:gsub("%s+$", "") or ""
        local err = result and result.stderr or error
        callback(ok, out, err, result)
    end)
end

local function git(dir, args, callback)
    local full = {"git", "-C", dir}
    for _, arg in ipairs(args) do full[#full + 1] = arg end
    run(full, callback)
end

local function done(on_complete)
    busy = false
    if on_complete then on_complete() end
end

local function fail(msg, err, on_complete)
    notify.show(msg, true, "error")
    if err and err ~= "" then mp.msg.error(err) end
    done(on_complete)
end

local function cancelled(on_complete)
    notify.show("Update cancelled.", true)
    done(on_complete)
end

local function apply_git(dir, old, new, on_complete)
    notify.show("Updating...", true)
    git(dir, {"reset", "--hard", "origin/" .. branch}, function(ok, _, err)
        if not ok then return fail("Update failed: git reset error.", err, on_complete) end
        notify.show("Updated " .. old .. " -> " .. new .. ", restart mpv to apply.", true)
        done(on_complete)
    end)
end

local function update_git(dir, on_complete)
    notify.show("Checking for updates...", true)
    git(dir, {"fetch", "origin", branch}, function(ok, _, err)
        if not ok then return fail("Update failed: git fetch error.", err, on_complete) end
        git(dir, {"rev-list", "--count", "HEAD..origin/" .. branch}, function(ok_count, count, err_count)
            if not ok_count then return fail("Update failed: git rev-list error.", err_count, on_complete) end
            if tonumber(count) == 0 then
                notify.show("Tachytome is already up to date.", true)
                return done(on_complete)
            end
            git(dir, {"show", "-s", "--format=%h", "HEAD", "origin/" .. branch}, function(ok_rev, revs, err_rev)
                if not ok_rev then return fail("Update failed: git show error.", err_rev, on_complete) end
                local old, new = revs:match("^(%S+)%s+(%S+)$")
                old = old or "?"
                new = new or "?"
                ui_confirm.show("Update Tachytome?", string.format("Method: git, %s new commit(s), %s -> %s", count, old, new), function()
                    apply_git(dir, old, new, on_complete)
                end, function()
                    cancelled(on_complete)
                end)
            end)
        end)
    end)
end

local function apply_archive(dir, on_complete)
    notify.show("Downloading update...", true)
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local archive  = utils.join_path(temp_dir, "tachytome_update_" .. tostring(math.floor(mp.get_time() * 1000)) .. ".tar.gz")
    run({"curl", "-fsSL", "-o", archive, archive_url}, function(ok, _, err)
        if not ok then
            os.remove(archive)
            return fail("Update failed: download error.", err, on_complete)
        end
        run({"tar", "-xzf", archive, "--strip-components=1", "-C", dir}, function(ok_tar, _, err_tar)
            os.remove(archive)
            if not ok_tar then return fail("Update failed: extract error.", err_tar, on_complete) end
            notify.show("Updated from GitHub, restart mpv to apply.", true)
            done(on_complete)
        end)
    end)
end

local function update_archive(dir, reason, on_complete)
    ui_confirm.show("Update Tachytome?", "Method: download from GitHub (" .. reason .. ")", function()
        apply_archive(dir, on_complete)
    end, function()
        cancelled(on_complete)
    end)
end

function M.run(on_complete)
    if busy then
        notify.show("Update already in progress.", true, "warn")
        return
    end
    if queue.is_rendering or #queue.jobs > 0 then
        notify.show("Cannot update while renders are active or queued.", true, "warn")
        if on_complete then on_complete() end
        return
    end

    local dir = mp.get_script_directory()
    if not dir then
        notify.show("Update failed: script directory not found.", true, "error")
        if on_complete then on_complete() end
        return
    end

    busy = true
    git(dir, {"rev-parse", "--show-prefix"}, function(ok, prefix, _, result)
        if ok and prefix == "" then return update_git(dir, on_complete) end
        local reason = "not a git repo"
        if result and result.error_string == "init" then reason = "git not found" end
        update_archive(dir, reason, on_complete)
    end)
end

return M
