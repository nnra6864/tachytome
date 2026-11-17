local migrate   = require 'src.migrate'
local ui_choice = require 'src.ui_choice'
local notify    = require 'src.notify'
local updater   = require 'src.updater'
local lang      = require 'src.lang'

local M = {}

local list_max = 6

local function join(list)
    if #list <= list_max then return table.concat(list, ", ") end
    local shown = {}
    for i = 1, list_max do shown[i] = list[i] end
    return lang.t("migrate_more", { list = table.concat(shown, ", "), count = #list - list_max })
end

local function describe(plan)
    local lines = {}
    for _, line in ipairs(plan.lines) do
        lines[#lines + 1] = lang.t(line.key, { list = line.list and join(line.list) or "", count = line.count or 0 })
    end
    return table.concat(lines, "\n")
end

local function follow_latest()
    for _, step in ipairs(migrate.ran) do
        if step.follow_latest then return updater.follow_latest() end
    end
end

function M.run(on_reload, on_done)
    local function run_step(i)
        local entry = migrate.pending[i]
        if not entry then
            if #migrate.pending > 0 then
                migrate.finish()
                on_reload()
            end
            follow_latest()
            return on_done()
        end
        ui_choice.show(lang.t("migrate_title", { version = entry.step.version }), describe(entry.plan), {
            { key = "1", alt = "ENTER", label = lang.t("choice_migrate") },
            { key = "2", label = lang.t("choice_skip") },
            { key = "3", label = lang.t("choice_later") }
        }, 3, function(idx)
            if idx == 3 then
                notify.show(lang.t("migrate_later"), true, "warn")
                return on_done()
            end
            if idx == 1 then
                entry.step.apply(entry.plan)
                notify.show(lang.t("migrate_done"), true)
            else
                entry.step.skip(entry.plan)
                notify.show(lang.t("migrate_skipped"), true)
            end
            run_step(i + 1)
        end)
    end
    run_step(1)
end

return M
