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

local M = {}

function M.show(on_close)
    local function rebuild_jobs()
        local new_jobs = {}
        if queue.is_rendering and queue.active then
            local active_title = queue.active.final_name
            if queue.render_paused then active_title = active_title .. " (Paused)" end
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
        mp.remove_key_binding("qm-cj")
        mp.remove_key_binding("qm-ck")
        mp.remove_key_binding("qm-enter")
        mp.remove_key_binding("qm-d")
        mp.remove_key_binding("qm-rename")
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
        local text = string.format("%s%s%sRender Queue Manager%s\\N%s(Up/Down to navigate, Enter to pause/resume, d to delete, r to rename, Esc to close)\\N\\N",
            theme.align(7), theme.f(), theme.b(true), theme.b(false), theme.f(true))

        local start_idx = math.max(1, cursor - 7)
        local end_idx   = math.min(#jobs, start_idx + 14)
        if end_idx - start_idx < 14 then start_idx = math.max(1, end_idx - 14) end

        if start_idx > 1 then text = text .. "\\h\\h...\\N" end

        for i = start_idx, end_idx do
            local job    = jobs[i]
            local prefix = (i == cursor) and string.format("%s\\h> ", theme.c("value_color")) or "\\h\\h"
            local status = job.is_active and string.format("%s" .. state.opts.on_text, theme.c("on_color")) or ""

            text = text .. string.format("%s%s%s %s%s\\N", theme.c("text_color"), prefix, job.title, status, theme.reset())
        end

        if end_idx < #jobs then text = text .. "\\h\\h...\\N" end

        ov.data = text
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

    local function rename_selected()
        local sel = jobs[cursor]
        if not sel then return end

        local q_job = sel.is_active and queue.active or queue.jobs[sel.original_index]
        if not q_job or not q_job.output_file then return end

        local current_output = q_job.output_file

        teardown()

        local function apply_rename(input, new_output)
            local target_dir, fname = utils.split_path(new_output)
            common.ensure_dir(target_dir)

            q_job.output_file = new_output
            q_job.final_name  = fname

            if queue.active == q_job then
                notify.show("Active render target: " .. fname, true)
            else
                q_job.args[q_job.output_arg_index] = new_output
                q_job.temp_file                    = queue.temp_path_for(new_output, q_job.temp_id)
                notify.show("Renamed to: " .. fname, true)
            end

            common.add_to_history(state.path_history, input)
            common.save_history(state.path_history)
            queue.save()
        end

        local function prompt_rename()
            ui_input.get_user_input("New Output Path > ", function(input)
                if input == "" then
                    notify.show("Rename cancelled.", true)
                    open_ui()
                    return
                end

                local new_output = common.resolve_absolute_path_for(input, state.opts, q_job.input_file)
                if new_output == "" or new_output == current_output then
                    notify.show("Path unchanged, keeping: " .. q_job.final_name, true)
                    open_ui()
                    return
                end

                if not queue.is_path_in_use(new_output) then
                    apply_rename(input, new_output)
                    open_ui()
                    return
                end

                local _, new_name = utils.split_path(new_output)
                ui_choice.show_exists(new_name, function()
                    prompt_rename()
                end, function()
                    apply_rename(input, new_output)
                    open_ui()
                end, function()
                    notify.show("Rename cancelled.", true)
                    open_ui()
                end)
            end, current_output, "(Up/Down for history, Enter to confirm, Esc to cancel)", state.path_history, function()
                open_ui()
            end)
        end

        prompt_rename()
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
        mp.add_forced_key_binding("ctrl+j", "qm-cj", move_down, {repeatable = true})
        mp.add_forced_key_binding("ctrl+k", "qm-ck", move_up, {repeatable = true})

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
                notify.show("Removed from queue: " .. job.title, true)
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

        mp.add_forced_key_binding("r", "qm-rename", rename_selected)

        mp.add_forced_key_binding("ESC", "qm-esc", cleanup)
    end

    open_ui = function()
        jobs = rebuild_jobs()
        if #jobs == 0 then
            if on_close then on_close() end
            return notify.show("Render queue is empty.", true, "info")
        end
        if cursor > #jobs then cursor = #jobs end

        mp.set_osd_ass(0, 0, "")
        mp.osd_message("", 0)

        active          = true
        state.ui_owner  = "queue"
        refresh_timer   = mp.add_periodic_timer(0.2, refresh)
        bind()
        draw()
    end

    open_ui()
end

return M
