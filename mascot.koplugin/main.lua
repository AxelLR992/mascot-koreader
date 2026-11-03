local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Mascot = WidgetContainer:extend{
    name = "mascot",
    is_doc_only = false,
}

function Mascot:init()
    self.ui.menu:registerToMainMenu(self)
end

function Mascot:addToMainMenu(menu_items)
    menu_items.mascot = {
        text = _("Mascot"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Mascot is alive."),
            })
        end,
    }
end

return Mascot
