local mp          = require 'mp'
local utils       = require 'mp.utils'
local common      = require 'src.common'
local queue       = require 'src.queue'
local render      = require 'src.render'
local state       = require 'src.state'
local notify      = require 'src.notify'
local theme       = require 'src.theme'
local ui_input    = require 'src.ui_input'
local ui_confirm  = require 'src.ui_confirm'
local ui_log      = require 'src.ui_log'
local trash       = require 'src.trash'
local list_search = require 'src.list_search'
local lang        = require 'src.lang'
local ui          = require 'src.ui'

local M = {}

function M.show(on_close)
    local function rebuild_jobs()
        local new_jobs = {}
        if queue.is_rendering and queue.active then
            local active_title = queue.active.final_name
            if queue.render_paused then active_title = lang.t("queue_paused_job", { name = active_title }) end
            table.insert(new_jobs, {title = active_title, is_active = true, original_index = 0})
        end
        for i, q_job in ipairs(queue.jobs) do
            table.insert(new_jobs, {title = q_job.final_name, is_active = false, original_index = i})
        end
        for _, rec in ipairs(queue.failed) do
            table.insert(new_jobs, {title = rec.final_name, is_active = false, is_failed = true, rec = rec})
        end
        return new_jobs
    end

    local function job_of(row)
        if row.is_active then return queue.active end
        if row.is_failed then return row.rec end
        return queue.jobs[row.original_index]
    end

    local ov            = mp.create_osd_overlay("ass-events")
    local active        = false
    local cursor        = 1
    local refresh_timer = nil
    local jobs          = {}
    local search

    local function remove_bindings()
        mp.remove_key_binding("qm-up")
        mp.remove_key_binding("qm-down")
        mp.remove_key_binding("qm-j")
        mp.remove_key_binding("qm-k")
        mp.remove_key_binding("qm-space")
        mp.remove_key_binding("qm-d")
        mp.remove_key_binding("qm-path")
        mp.remove_key_binding("qm-retry")
        mp.remove_key_binding("qm-log")
        mp.remove_key_binding("qm-search")
        mp.remove_key_binding("qm-esc")
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        if refresh_timer then refresh_timer:kill(); refresh_timer = nil end
        search.close()
        ov:remove()
        remove_bindings()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function labels()
        local out = {}
        for i, job in ipairs(jobs) do out[i] = job.title end
        return out
    end

    local function visible()
        return ui.visible(#jobs, function(i) return search.keep(jobs[i].title) end)
    end

    local function draw()
        local vis = visible()
        if #vis > 0 and ui.position(vis, cursor) == 0 then cursor = vis[1] end
        local body = ui.list(#vis, ui.position(vis, cursor), function(k)
            local job    = jobs[vis[k]]
            local status = ""
            if job.is_active then status = string.format(" %s%s", theme.c("on_color"), state.opts.on_text) end
            if job.is_failed then status = string.format(" %s%s", theme.c("error_color"), theme.escape(lang.t("queue_failed"))) end
            return theme.escape(job.title) .. status
        end)
        if #vis == 0 then body = search.empty() end
        local row   = #vis > 0 and jobs[cursor] or nil
        local hints = { { "Up/Down", "navigate" }, { "Space", render.is_paused() and "resume" or "pause" }, { "p", "path" } }
        if row and row.is_failed then
            hints[#hints + 1] = { "r", "retry" }
            hints[#hints + 1] = { "l", "log" }
            hints[#hints + 1] = { "d", "dismiss" }
        else
            hints[#hints + 1] = { "d", "delete" }
        end
        hints[#hints + 1] = { "/", "search" }
        hints[#hints + 1] = { "Esc", "close" }
        local tip = row and row.is_failed and ui.note(row.rec.error) or ""
        ov.data = search.title(lang.t("menu_render_queue")) .. "\\N" .. body .. tip .. "\\N" .. ui.tooltip(search.hints(hints))
        ov:update()
    end

    local function move(delta)
        cursor = ui.step(visible(), cursor, delta)
        draw()
    end

    search = list_search.new({
        prefix = "qm",
        labels = labels,
        redraw = draw,
        move   = move,
        pick   = function(i)
            cursor = i
            draw()
        end
    })

    local function refresh()
        if not active then return end
        local new_jobs = rebuild_jobs()
        local changed = false

        if #new_jobs ~= #jobs then
            changed = true
        else
            for i = 1, #jobs do
                if jobs[i].title ~= new_jobs[i].title or jobs[i].is_active ~= new_jobs[i].is_active or jobs[i].rec ~= new_jobs[i].rec then
                    changed = true; break
                end
            end
        end

        if changed then
            jobs = new_jobs
            if #jobs == 0 then
                cleanup()
            else
                if cursor > #jobs then cursor = #jobs end
                draw()
            end
        end
    end

    local open_ui

    local function change_path_selected()
        local sel = jobs[cursor]
        if not sel then return end

        local q_job = job_of(sel)
        if not q_job or not q_job.output_file then return end

        local current_output = q_job.output_file

        teardown()

        local function apply_change_path(input, new_output)
            local target_dir, fname = utils.split_path(new_output)
            common.ensure_dir(target_dir)

            q_job.output_file = new_output
            q_job.final_name  = fname

            if queue.active ~= q_job and q_job.args then
                q_job.args[q_job.output_arg_index] = new_output
                q_job.temp_file                    = queue.temp_path_for(new_output, q_job.temp_id)
            end
            notify.show(lang.t("value_set", { label = lang.t("menu_path"), value = fname }), true)

            common.add_to_history(state.path_history, input)
            common.save_history(state.path_history)
            queue.save()
        end

        local function ext_of(file)
            return (file:match("%.([^%./\\]+)$") or ""):lower()
        end

        local function resolve(input)
            local ext = ext_of(current_output)
            return common.resolve_absolute_path_for(input, state.opts, q_job.input_file, ext ~= "" and ext or nil)
        end

        local function change_to(input, new_output)
            if ext_of(new_output) == ext_of(current_output) then
                apply_change_path(input, new_output)
                return open_ui()
            end
            if q_job == queue.active then
                notify.show(lang.t("queue_active_container"), true, "warn")
                return open_ui()
            end
            local item = sel.is_failed and {} or queue.item_from_job(q_job)
            if sel.is_failed then
                for k, v in pairs(q_job) do item[k] = v end
            end
            local _, fname   = utils.split_path(new_output)
            item.output_file = new_output
            item.final_name  = fname
            local job, err   = queue.job_from_item(item)
            if not job then
                notify.show(err, true, "error")
                return open_ui()
            end
            render.confirm_losses(job, function()
                for i, j in ipairs(queue.jobs) do
                    if j == q_job then
                        queue.jobs[i] = job
                        q_job         = job
                    end
                end
                apply_change_path(input, new_output)
                open_ui()
            end, open_ui)
        end

        local function prompt_change_path()
            ui_input.show({
                title       = lang.t("menu_path"),
                text        = common.display_path(current_output, q_job.input_file),
                history     = state.path_history,
                allow_space = true,
                preview     = resolve,
                on_cancel   = open_ui,
                on_submit   = function(input)
                    local new_output = input ~= "" and resolve(input) or ""
                    if new_output == "" or new_output == current_output then return open_ui() end

                    if not queue.is_path_in_use(new_output) then return change_to(input, new_output) end

                    local _, new_name = utils.split_path(new_output)
                    render.show_exists(q_job.input_file, new_output, prompt_change_path, function()
                        change_to(input, new_output)
                    end, open_ui, q_job)
                end
            })
        end

        prompt_change_path()
    end

    local function bind()
        local function move_up() move(-1) end
        local function move_down() move(1) end

        mp.add_forced_key_binding("UP", "qm-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "qm-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("j", "qm-j", move_down, {repeatable = true})
        mp.add_forced_key_binding("k", "qm-k", move_up, {repeatable = true})

        mp.add_forced_key_binding("SPACE", "qm-space", function()
            render.toggle_pause()

            jobs = rebuild_jobs()
            if #jobs == 0 then
                cleanup()
            else
                draw()
            end
        end)

        local function after_delete()
            jobs = rebuild_jobs()
            if #jobs == 0 then
                if on_close then on_close() end
            else
                if cursor > #jobs then cursor = #jobs end
                open_ui()
            end
        end

        local function delete_selected()
            local job = jobs[cursor]
            if not job then return end
            local q_job = job_of(job)
            if not q_job then return end
            local input = q_job.input_file

            local function remove()
                if job.is_active then
                    render.cancel_render()
                elseif job.is_failed then
                    render.dismiss(q_job)
                else
                    table.remove(queue.jobs, job.original_index)
                    queue.total_jobs = queue.total_jobs > 0 and (queue.total_jobs - 1) or 0
                    notify.show(lang.t("queue_removed", { name = job.title }), true)
                    queue.save()
                    trash.settle(input)
                end
            end

            local lines = {}
            if not job.is_failed and trash.pending(input) and trash.users(input) == 1 then lines[1] = lang.t("queue_trashes", { path = common.display_path(input) }) end
            if not job.is_active and #lines == 0 then
                remove()
                jobs = rebuild_jobs()
                if #jobs == 0 then return cleanup() end
                if cursor > #jobs then cursor = #jobs end
                return draw()
            end

            teardown()
            local title = lang.t("queue_remove_confirm")
            if job.is_active then title = lang.t("queue_cancel_confirm") end
            if job.is_failed then title = lang.t("queue_dismiss_confirm") end
            ui_confirm.show(title, job.title, function()
                remove()
                after_delete()
            end, open_ui, lines)
        end

        mp.add_forced_key_binding("d", "qm-d", delete_selected)

        mp.add_forced_key_binding("p", "qm-path", change_path_selected)

        mp.add_forced_key_binding("r", "qm-retry", function()
            local row = jobs[cursor]
            if not (row and row.is_failed) then return end
            render.retry(row.rec)
            jobs = rebuild_jobs()
            draw()
        end)

        mp.add_forced_key_binding("l", "qm-log", function()
            local row = jobs[cursor]
            if not (row and row.is_failed) then return end
            teardown()
            ui_log.show(row.title, row.rec.log or {}, row.rec.log_file, open_ui)
        end)

        mp.add_forced_key_binding("/", "qm-search", search.start)

        mp.add_forced_key_binding("ESC", "qm-esc", function()
            if search.filtering() then return search.clear() end
            cleanup()
        end)
    end

    open_ui = function()
        jobs = rebuild_jobs()
        if #jobs == 0 then
            if on_close then on_close() end
            return notify.show(lang.t("queue_empty"), true, "info")
        end
        if cursor > #jobs then cursor = #jobs end

        ui.clear_osd()

        active          = true
        state.ui_owner  = "queue"
        refresh_timer   = mp.add_periodic_timer(0.2, refresh)
        bind()
        draw()
    end

    open_ui()
end

return M
