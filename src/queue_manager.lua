local mp        = require 'mp'
local utils     = require 'mp.utils'
local common    = require 'src.common'
local queue     = require 'src.queue'
local render    = require 'src.render'
local state     = require 'src.state'
local notify    = require 'src.notify'
local theme     = require 'src.theme'
local ui_input  = require 'src.ui_input'
local ui_choice = require 'src.ui_choice'
local lang      = require 'src.lang'
local ui        = require 'src.ui'

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
        return new_jobs
    end

    local ov            = mp.create_osd_overlay("ass-events")
    local active        = false
    local cursor        = 1
    local refresh_timer = nil
    local jobs          = {}

    local function remove_bindings()
        mp.remove_key_binding("qm-up")
        mp.remove_key_binding("qm-down")
        mp.remove_key_binding("qm-j")
        mp.remove_key_binding("qm-k")
        mp.remove_key_binding("qm-enter")
        mp.remove_key_binding("qm-d")
        mp.remove_key_binding("qm-path")
        mp.remove_key_binding("qm-esc")
    end

    local function teardown()
        if not active then return end
        active         = false
        state.ui_owner = nil
        if refresh_timer then refresh_timer:kill(); refresh_timer = nil end
        ov:remove()
        remove_bindings()
    end

    local function cleanup()
        if not active then return end
        teardown()
        if on_close then on_close() end
    end

    local function draw()
        local body = ui.list(#jobs, cursor, function(i)
            local job    = jobs[i]
            local status = job.is_active and string.format(" %s%s", theme.c("on_color"), state.opts.on_text) or ""
            return theme.escape(job.title) .. status
        end)
        local hints = { { "Up/Down", "navigate" }, { "Enter", "pause" }, { "p", "path" }, { "d", "delete" }, { "Esc", "close" } }
        ov.data = ui.title(lang.t("menu_render_queue")) .. "\\N" .. body .. "\\N" .. ui.tooltip(hints)
        ov:update()
    end

    local function refresh()
        if not active then return end
        local new_jobs = rebuild_jobs()
        local changed = false

        if #new_jobs ~= #jobs then
            changed = true
        else
            for i = 1, #jobs do
                if jobs[i].title ~= new_jobs[i].title or jobs[i].is_active ~= new_jobs[i].is_active then
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

        local q_job = sel.is_active and queue.active or queue.jobs[sel.original_index]
        if not q_job or not q_job.output_file then return end

        local current_output = q_job.output_file

        teardown()

        local function apply_change_path(input, new_output)
            local target_dir, fname = utils.split_path(new_output)
            common.ensure_dir(target_dir)

            q_job.output_file = new_output
            q_job.final_name  = fname

            if queue.active ~= q_job then
                q_job.args[q_job.output_arg_index] = new_output
                q_job.temp_file                    = queue.temp_path_for(new_output, q_job.temp_id)
            end
            notify.show(lang.t("value_set", { label = lang.t("menu_path"), value = fname }), true)

            common.add_to_history(state.path_history, input)
            common.save_history(state.path_history)
            queue.save()
        end

        local function resolve(input)
            return common.resolve_absolute_path_for(input, state.opts, q_job.input_file)
        end

        local function prompt_change_path()
            ui_input.show({
                title       = lang.t("menu_path"),
                current     = common.display_path(current_output, q_job.input_file),
                history     = state.path_history,
                allow_space = true,
                preview     = resolve,
                on_cancel   = open_ui,
                on_submit   = function(input)
                    local new_output = input ~= "" and resolve(input) or ""
                    if new_output == "" or new_output == current_output then return open_ui() end

                    if not queue.is_path_in_use(new_output) then
                        apply_change_path(input, new_output)
                        return open_ui()
                    end

                    local _, new_name = utils.split_path(new_output)
                    ui_choice.show_exists(new_name, prompt_change_path, function()
                        apply_change_path(input, new_output)
                        open_ui()
                    end, open_ui)
                end
            })
        end

        prompt_change_path()
    end

    local function bind()
        local function move_up()
            if cursor > 1 then cursor = cursor - 1; draw() end
        end

        local function move_down()
            if cursor < #jobs then cursor = cursor + 1; draw() end
        end

        mp.add_forced_key_binding("UP", "qm-up", move_up, {repeatable = true})
        mp.add_forced_key_binding("DOWN", "qm-down", move_down, {repeatable = true})
        mp.add_forced_key_binding("j", "qm-j", move_down, {repeatable = true})
        mp.add_forced_key_binding("k", "qm-k", move_up, {repeatable = true})

        mp.add_forced_key_binding("ENTER", "qm-enter", function()
            render.toggle_pause()

            jobs = rebuild_jobs()
            if #jobs == 0 then
                cleanup()
            else
                draw()
            end
        end)

        local function delete_selected()
            local job = jobs[cursor]
            if not job then return end

            if job.is_active then
                render.cancel_render()
            else
                table.remove(queue.jobs, job.original_index)
                queue.total_jobs = queue.total_jobs > 0 and (queue.total_jobs - 1) or 0
                notify.show(lang.t("queue_removed", { name = job.title }), true)
                queue.save()
            end

            jobs = rebuild_jobs()
            if #jobs == 0 then
                cleanup()
            else
                if cursor > #jobs then cursor = #jobs end
                draw()
            end
        end

        mp.add_forced_key_binding("d", "qm-d", delete_selected)

        mp.add_forced_key_binding("p", "qm-path", change_path_selected)

        mp.add_forced_key_binding("ESC", "qm-esc", cleanup)
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
