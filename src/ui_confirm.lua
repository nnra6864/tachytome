local mp    = require 'mp'
local theme = require 'src.theme'

local M = {}

function M.show(warning, sub_text, on_yes, on_no)
    mp.set_osd_ass(0, 0, "")
    mp.osd_message("", 0)
    
    local ov     = mp.create_osd_overlay("ass-events")
    local active = true

    local function cleanup()
        if not active then return end
        active = false
        ov:remove()
        mp.remove_key_binding("conf-y")
        mp.remove_key_binding("conf-n")
        mp.remove_key_binding("conf-enter")
        mp.remove_key_binding("conf-esc")
    end

    ov.data = string.format("%s%s%s%s%s\\N%s%s\\N\\N[ y / Enter ] Yes\\N[ n / Esc ]   No",
        theme.align(7), theme.f(), theme.c("warning_color"), warning, theme.reset(), theme.f(true), sub_text)
    ov:update()

    local function yes() cleanup(); if on_yes then on_yes() end end
    local function no()  cleanup(); if on_no then on_no() end end

    mp.add_forced_key_binding("y",     "conf-y",     yes)
    mp.add_forced_key_binding("ENTER", "conf-enter", yes)
    mp.add_forced_key_binding("n",     "conf-n",     no)
    mp.add_forced_key_binding("ESC",   "conf-esc",   no)
end

return M
