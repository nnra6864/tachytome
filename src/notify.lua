local mp    = require 'mp'
local theme = require 'src.theme'

local M = {}
local notify_ov    = mp.create_osd_overlay("ass-events")
local notify_timer = nil

function M.show(msg, show_osd, type)
    if type == "warn" then
        mp.msg.warn(msg)
    elseif type == "error" then
        mp.msg.error(msg)
    else
        mp.msg.info(msg)
    end

    if show_osd then
        local color_key = "text_color"
        if type == "warn" then
            color_key = "warning_color"
        elseif type == "error" then
            color_key = "error_color"
        end

        notify_ov.data = string.format("%s%s%s%s%s%s", theme.align(9), theme.f(), theme.b(true), theme.c(color_key), msg, theme.b(false))
        notify_ov:update()

        if notify_timer then notify_timer:kill() end
        notify_timer = mp.add_timeout(3, function()
            notify_ov:remove()
        end)
    end
end

return M
