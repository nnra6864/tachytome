local lang      = require 'src.lang'
local ui_choice = require 'src.ui_choice'

local M = {}

function M.show(title, body, on_yes, on_no)
    ui_choice.show(title, body, {
        { key = "y", alt = "ENTER", label = lang.t("choice_yes") },
        { key = "n", label = lang.t("choice_no") }
    }, 2, function(idx)
        if idx == 1 then
            if on_yes then on_yes() end
        elseif on_no then
            on_no()
        end
    end)
end

return M
