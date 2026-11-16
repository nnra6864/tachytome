local mp         = require 'mp'
local utils      = require 'mp.utils'
local queue      = require 'src.queue'
local state      = require 'src.state'
local notify     = require 'src.notify'
local ui_confirm = require 'src.ui_confirm'
local lang       = require 'src.lang'

local M = {}

local repo = "nnra6864/tachytome"
local busy = false

local function branch()
    if state.opts.update_branch == "" then return "master" end
    return state.opts.update_branch
end

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

local function in_repo(dir, callback)
    git(dir, {"rev-parse", "--show-prefix"}, function(ok, prefix, _, result)
        if ok and prefix == "" then return callback(true) end
        local reason = lang.t("update_no_repo")
        if result and result.error_string == "init" then reason = lang.t("update_no_git") end
        callback(false, reason)
    end)
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

local function failed(step)
    return lang.t("update_failed", { step = step })
end

local function apply_git(dir, target, old, new, on_complete)
    notify.show(lang.t("update_updating"), true)
    git(dir, {"checkout", "-f", "-B", target, "FETCH_HEAD"}, function(ok, _, err)
        if not ok then return fail(failed("git checkout"), err, on_complete) end
        notify.show(lang.t("update_done_git", { old = old, new = new }), true)
        done(on_complete)
    end)
end

local function update_git(dir, on_complete)
    local target = branch()
    notify.show(lang.t("update_checking"), true)
    git(dir, {"fetch", "origin", target}, function(ok, _, err)
        if not ok then return fail(failed("git fetch"), err, on_complete) end
        git(dir, {"rev-parse", "--abbrev-ref", "HEAD"}, function(ok_head, current, err_head)
            if not ok_head then return fail(failed("git rev-parse"), err_head, on_complete) end
            git(dir, {"rev-list", "--count", "HEAD..FETCH_HEAD"}, function(ok_count, count, err_count)
                if not ok_count then return fail(failed("git rev-list"), err_count, on_complete) end
                if tonumber(count) == 0 and current == target then
                    notify.show(lang.t("update_up_to_date"), true)
                    return done(on_complete)
                end
                git(dir, {"show", "-s", "--format=%h", "HEAD", "FETCH_HEAD"}, function(ok_rev, revs, err_rev)
                    if not ok_rev then return fail(failed("git show"), err_rev, on_complete) end
                    local old, new = revs:match("^(%S+)%s+(%S+)$")
                    old = old or "?"
                    new = new or "?"
                    local body = lang.t("update_method_git", { count = count, old = old, new = new })
                    if current ~= target then
                        body = lang.t("update_method_git_switch", { from = current, to = target, old = old, new = new })
                    end
                    ui_confirm.show(lang.t("update_title"), body, function()
                        apply_git(dir, target, old, new, on_complete)
                    end, function()
                        done(on_complete)
                    end)
                end)
            end)
        end)
    end)
end

local function apply_archive(dir, target, on_complete)
    notify.show(lang.t("update_downloading"), true)
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local archive  = utils.join_path(temp_dir, "tachytome_update_" .. tostring(math.floor(mp.get_time() * 1000)) .. ".tar.gz")
    local url      = "https://github.com/" .. repo .. "/archive/refs/heads/" .. target .. ".tar.gz"
    run({"curl", "-fsSL", "-o", archive, url}, function(ok, _, err)
        if not ok then
            os.remove(archive)
            return fail(failed("curl"), err, on_complete)
        end
        run({"tar", "-xzf", archive, "--strip-components=1", "-C", dir}, function(ok_tar, _, err_tar)
            os.remove(archive)
            if not ok_tar then return fail(failed("tar"), err_tar, on_complete) end
            notify.show(lang.t("update_done_archive"), true)
            done(on_complete)
        end)
    end)
end

local function update_archive(dir, reason, on_complete)
    local target = branch()
    ui_confirm.show(lang.t("update_title"), lang.t("update_method_archive", { branch = target, reason = reason }), function()
        apply_archive(dir, target, on_complete)
    end, function()
        done(on_complete)
    end)
end

local function github_branches(callback)
    run({"curl", "-fsSL", "https://api.github.com/repos/" .. repo .. "/branches?per_page=100"}, function(ok, out, err)
        local data = ok and utils.parse_json(out)
        if type(data) ~= "table" then return callback(nil, err) end
        local list = {}
        for _, b in ipairs(data) do
            if type(b) == "table" and b.name then list[#list + 1] = b.name end
        end
        callback(list)
    end)
end

function M.branches(callback)
    local dir = mp.get_script_directory()
    if not dir then return github_branches(callback) end
    in_repo(dir, function(is_repo)
        if not is_repo then return github_branches(callback) end
        git(dir, {"ls-remote", "--heads", "origin"}, function(ok, out, err)
            if not ok then return callback(nil, err) end
            local list = {}
            for name in out:gmatch("refs/heads/(%S+)") do list[#list + 1] = name end
            callback(list)
        end)
    end)
end

function M.run(on_complete)
    if busy then
        notify.show(lang.t("update_busy"), true, "warn")
        return
    end
    if queue.is_rendering or #queue.jobs > 0 then
        notify.show(lang.t("update_blocked"), true, "warn")
        if on_complete then on_complete() end
        return
    end

    local dir = mp.get_script_directory()
    if not dir then
        notify.show(lang.t("update_no_dir"), true, "error")
        if on_complete then on_complete() end
        return
    end

    busy = true
    in_repo(dir, function(is_repo, reason)
        if is_repo then return update_git(dir, on_complete) end
        update_archive(dir, reason, on_complete)
    end)
end

return M
