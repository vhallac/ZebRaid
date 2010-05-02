local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- The function prototypes will go in here
local Factory_Template = {
    buttons = {},
    allocCount = 0
}

-- Meta table to allow all object to access the "static" variables.
local meta = {__index = Factory_Template,
              __newindex = function(tbl, key, val)
                  if Factory_Template[key] then Factory_Template[key] = val
                  else rawset(tbl, key, val) end
              end}

-- Define a shorter name for the following code

local obj = Factory_Template

function ZebRaid:NewButtonFactory()
    factory = setmetatable({}, meta)
    factory:Construct()
    return factory
end

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
