local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- Define a shorter name for the following code
local obj = ZebRaid:NewClass(
    "ButtonFactory",
    {
        buttons = {},
        allocCount = 0
    })

function obj:Construct()
end

function obj:Allocate()
    local button
    if #self.buttons > 0 then
        button = table.remove(self.buttons)
    else
        self.allocCount = self.allocCount + 1
        button = CreateFrame("Button", "ZebRaidButton" .. self.allocCount, getglobal("ZebRaidDialogPanel"), "ZebRaidDialogButtonTemplate")
    end
    return button
end

function obj:Free(button)
    if button then
        button:Hide()
        table.insert(self.buttons, button)
    end
end
