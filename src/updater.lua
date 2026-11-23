local mp         = require 'mp'
local utils      = require 'mp.utils'
local queue      = require 'src.queue'
local state      = require 'src.state'
local notify     = require 'src.notify'
local ui_confirm = require 'src.ui_confirm'
local lang       = require 'src.lang'
local ver        = require 'src.version'

local M = {}

local repo = "nnra6864/tachytome"
local busy = false

local function version()
    if state.opts.version == "" then return "latest" end
    return state.opts.version
end

local function releases(tags)
    local list = {}
    for _, tag in ipairs(tags) do
        local nums = ver.parse(tag)
        if nums then list[#list + 1] = { tag = tag, nums = nums } end
    end
    table.sort(list, function(a, b) return ver.newer(a.nums, b.nums) end)
    return list
end

local function is_release(val)
    return val == "latest" or ver.parse(val) ~= nil
end

local function with_major(body, t)
    local to   = t.tag and ver.parse(t.name)
    local from = ver.parse(ver.current)
    if not to or not from or to[1] == from[1] then return body end
    return body .. "\n" .. lang.t("update_major", { from = ver.current, to = t.name })
end

local function target(val, tags)
    if not is_release(val) then return { name = val, ref = "refs/heads/" .. val } end
    local want = val ~= "latest" and ver.parse(val) or {}
    for _, r in ipairs(releases(tags or {})) do
        local match = true
        for i, n in ipairs(want) do
            if (r.nums[i] or 0) ~= n then
                match = false
                break
            end
        end
        if match then return { name = r.tag, ref = "refs/tags/" .. r.tag, tag = true } end
    end
    return nil
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

local function latest_api(url)
    local scheme, host, path = url:match("^(%a[%w+.-]*)://([^/]+)/(.+)$")
    if not host then
        host, path = url:match("^[^@/]+@([^:/]+):(.+)$")
    end
    if not host then return nil end
    host = host:gsub("^.*@", "")
    path = path:gsub("^/+", ""):gsub("/+$", ""):gsub("%.git$", "")
    if scheme ~= "http" and scheme ~= "https" then
        host   = host:gsub(":%d+$", "")
        scheme = "https"
    end
    if host == "github.com" then return "https://api.github.com/repos/" .. path .. "/releases/latest" end
    return scheme .. "://" .. host .. "/api/v1/repos/" .. path .. "/releases/latest"
end

local github = { api = "https://api.github.com/repos/" .. repo .. "/releases/latest" }

local function git_source(dir, callback)
    local function from(remote)
        if remote == "" or remote == "." then remote = "origin" end
        git(dir, {"remote", "get-url", remote}, function(ok, url)
            callback({ remote = remote, api = ok and latest_api(url) or nil })
        end)
    end
    git(dir, {"rev-parse", "--abbrev-ref", "HEAD"}, function(ok, branch)
        if not ok or branch == "HEAD" then return from("origin") end
        git(dir, {"config", "--get", "branch." .. branch .. ".remote"}, function(ok_remote, remote)
            from(ok_remote and remote or "origin")
        end)
    end)
end

local function git_refs(dir, src, callback)
    git(dir, {"ls-remote", "--heads", "--tags", src.remote}, function(ok, out, err)
        if not ok then return callback(nil, err) end
        local refs = { branches = {}, tags = {} }
        for kind, name in out:gmatch("refs/(%a+)/(%S+)") do
            if kind == "heads" then
                refs.branches[#refs.branches + 1] = name
            elseif kind == "tags" and not name:find("%^{}$") then
                refs.tags[#refs.tags + 1] = name
            end
        end
        callback(refs)
    end)
end

local function github_names(kind, callback)
    run({"curl", "-fsSL", "https://api.github.com/repos/" .. repo .. "/" .. kind .. "?per_page=100"}, function(ok, out, err)
        local data = ok and utils.parse_json(out)
        if type(data) ~= "table" then return callback(nil, err) end
        local names = {}
        for _, item in ipairs(data) do
            if type(item) == "table" and item.name then names[#names + 1] = item.name end
        end
        callback(names)
    end)
end

local function github_refs(callback)
    github_names("branches", function(branches, err)
        if not branches then return callback(nil, err) end
        github_names("tags", function(tags, err_tags)
            if not tags then return callback(nil, err_tags) end
            callback({ branches = branches, tags = tags })
        end)
    end)
end

local function resolve(val, tags, src, callback)
    if val ~= "latest" or not src.api then return callback(target(val, tags)) end
    run({"curl", "-fsSL", src.api}, function(ok, out)
        local data = ok and utils.parse_json(out)
        if type(data) == "table" and type(data.tag_name) == "string" then
            return callback({ name = data.tag_name, ref = "refs/tags/" .. data.tag_name, tag = true })
        end
        callback(target(val, tags))
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

local function no_release(on_complete)
    fail(lang.t("update_no_release", { version = version() }), nil, on_complete)
end

local function current_name(dir, callback)
    git(dir, {"rev-parse", "--abbrev-ref", "HEAD"}, function(ok, name, err)
        if not ok then return callback(nil, err) end
        if name ~= "HEAD" then return callback(name) end
        git(dir, {"describe", "--tags", "--exact-match", "HEAD"}, function(ok_tag, tag)
            callback(ok_tag and tag or name)
        end)
    end)
end

local function apply_git(dir, t, old, new, on_complete)
    notify.show(lang.t("update_updating"), true)
    local args = {"checkout", "-f", "-B", t.name, "FETCH_HEAD"}
    if t.tag then args = {"checkout", "-f", "--detach", "FETCH_HEAD"} end
    git(dir, args, function(ok, _, err)
        if not ok then return fail(failed("git checkout"), err, on_complete) end
        notify.show(lang.t("update_done_git", { old = old, new = new }), true)
        done(on_complete)
    end)
end

local function confirm_git(dir, t, on_complete)
    current_name(dir, function(current, err)
        if not current then return fail(failed("git rev-parse"), err, on_complete) end
        git(dir, {"rev-list", "--count", "HEAD..FETCH_HEAD"}, function(ok_count, count, err_count)
            if not ok_count then return fail(failed("git rev-list"), err_count, on_complete) end
            git(dir, {"show", "-s", "--format=%h", "HEAD", "FETCH_HEAD^{commit}"}, function(ok_rev, revs, err_rev)
                if not ok_rev then return fail(failed("git show"), err_rev, on_complete) end
                local old, new = revs:match("^(%S+)%s+(%S+)$")
                old = old or "?"
                new = new or "?"
                local same = current == t.name
                if same and (old == new or (not t.tag and tonumber(count) == 0)) then
                    notify.show(lang.t("update_up_to_date"), true)
                    return done(on_complete)
                end
                local body = lang.t("update_method_git", { count = count, old = old, new = new })
                if not same then
                    body = lang.t("update_method_git_switch", { from = current, to = t.name, old = old, new = new })
                end
                ui_confirm.show(lang.t("update_title"), with_major(body, t), function()
                    apply_git(dir, t, old, new, on_complete)
                end, function()
                    done(on_complete)
                end)
            end)
        end)
    end)
end

local function update_git(dir, on_complete)
    notify.show(lang.t("update_checking"), true)
    git_source(dir, function(src)
        git_refs(dir, src, function(refs, err)
            if not refs then return fail(failed("git ls-remote"), err, on_complete) end
            resolve(version(), refs.tags, src, function(t)
                if not t then return no_release(on_complete) end
                local spec = t.name
                if t.tag then spec = "+" .. t.ref .. ":" .. t.ref end
                git(dir, {"fetch", src.remote, spec}, function(ok, _, err_fetch)
                    if not ok then return fail(failed("git fetch"), err_fetch, on_complete) end
                    confirm_git(dir, t, on_complete)
                end)
            end)
        end)
    end)
end

local function apply_archive(dir, t, on_complete)
    notify.show(lang.t("update_downloading"), true)
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
    local archive  = utils.join_path(temp_dir, "tachytome_update_" .. tostring(math.floor(mp.get_time() * 1000)) .. ".tar.gz")
    local url      = "https://github.com/" .. repo .. "/archive/" .. t.ref .. ".tar.gz"
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

local function confirm_archive(dir, t, reason, on_complete)
    ui_confirm.show(lang.t("update_title"), with_major(lang.t("update_method_archive", { version = t.name, reason = reason }), t), function()
        apply_archive(dir, t, on_complete)
    end, function()
        done(on_complete)
    end)
end

local function update_archive(dir, reason, on_complete)
    if not is_release(version()) then return confirm_archive(dir, target(version()), reason, on_complete) end
    notify.show(lang.t("update_checking"), true)
    github_names("tags", function(tags, err)
        if not tags then return fail(failed("curl"), err, on_complete) end
        resolve(version(), tags, github, function(t)
            if not t then return no_release(on_complete) end
            confirm_archive(dir, t, reason, on_complete)
        end)
    end)
end

function M.versions(callback)
    local function collect(refs, err)
        if not refs then return callback(nil, err) end
        local list    = {}
        local details = {}
        local seen    = {}
        local rels    = releases(refs.tags)
        local function add(name, detail)
            if seen[name] then return end
            seen[name]      = true
            list[#list + 1] = name
            details[name]   = detail
        end
        add("latest", lang.t("version_latest"))
        for _, b in ipairs(refs.branches) do
            if b == "master" then add(b, lang.t("version_branch")) end
        end
        for _, b in ipairs(refs.branches) do add(b, lang.t("version_branch")) end
        for _, r in ipairs(rels) do
            for i = 1, #r.nums - 1 do
                local pin = table.concat(r.nums, ".", 1, i)
                add(pin, lang.t("version_pin", { pin = pin .. string.rep(".x", #r.nums - i), version = r.tag }))
            end
            add(table.concat(r.nums, "."))
        end
        callback(list, nil, details)
    end

    local dir = mp.get_script_directory()
    if not dir then return github_refs(collect) end
    in_repo(dir, function(is_repo)
        if not is_repo then return github_refs(collect) end
        git_source(dir, function(src) git_refs(dir, src, collect) end)
    end)
end

function M.follow_latest()
    local dir = mp.get_script_directory()
    if not dir or busy then return end
    in_repo(dir, function(is_repo)
        if not is_repo then return end
        git(dir, {"rev-parse", "--abbrev-ref", "HEAD"}, function(ok, current)
            if not ok or current ~= "master" then return end
            git_source(dir, function(src)
                git_refs(dir, src, function(refs)
                    if not refs then return end
                    resolve("latest", refs.tags, src, function(t)
                        if not t then return end
                        git(dir, {"fetch", src.remote, "+" .. t.ref .. ":" .. t.ref}, function(ok_fetch)
                            if not ok_fetch then return end
                            git(dir, {"rev-parse", "HEAD", "FETCH_HEAD^{commit}"}, function(ok_rev, revs)
                                local head, tag = revs:match("^(%S+)%s+(%S+)$")
                                if not ok_rev or not head or head ~= tag then return end
                                git(dir, {"checkout", "-q", "--detach", "FETCH_HEAD"}, function(ok_checkout, _, err)
                                    if ok_checkout then
                                        mp.msg.info("Switched from master to " .. t.name)
                                    else
                                        mp.msg.warn("Failed to switch from master to " .. t.name .. ": " .. tostring(err))
                                    end
                                end)
                            end)
                        end)
                    end)
                end)
            end)
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
