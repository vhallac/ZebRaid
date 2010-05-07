-- TODO: Create a button object
local Guild = LibStub("LibGuild-1.0")
local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

local obj = ZebRaid:NewClass("List", {})

function obj:Construct(name, visual, assignment)
    self.name = name
    self.visual = visual
    self.players = ZebRaid:Construct("PlayerData")
    self.buttonFactory = ZebRaid:Construct("ButtonFactory")
    self.visual.listObj = self
    self.assignment = assignment
    self.counts = {
        ["melee"] = 0,
        ["ranged"] = 0,
        ["healer"] = 0,
        ["tank"] = 0,
        ["hybrid"] = 0,
        ["unknown"] = 0
    }
    self.buttons = {}
end

function obj:SetFilterFunc(filterfunc)
    self.filterfunc = filterfunc
end

function obj:SetSortFunc(sortfunc)
    self.sortfunc = sortfunc
end

function obj:GetAssignment()
    return self.assignment
end

function obj:Update()
    for k, v in ipairs(self.buttons) do
        -- Put the button back on the store
        self.buttonFactory:Put(v)
        self.buttons[k] = nil
    end

    -- Reset the counts
    for n in pairs(self.counts) do
        self.counts[n] = 0
    end

    local makebuttons = true
    for i, player in self:GetIterator() do
        -- TODO: It should be possible to do incremental updates here
        -- WTB more side-effect programming. Fix it!
        if makebuttons and not self:InsertNewButton(player, i) then
            -- List full. No need to add buttons further. But contiune the loop
            -- to have up-to-date counts
            makebuttons = false
        end
        -- Keep statistics. :)
        local role = player:GetRole()
        self.counts[role] = self.counts[role] + 1
    end
end

function obj:GetCount(role)
    return self.counts[role]
end

function obj:GetTotalCount()
    local total = 0
    for i, v in pairs(self.counts) do
        total = total + v
    end
    return total
end

function obj:InsertNewButton(player, pos)
    local button = self.buttonFactory:Get(player)
    button.inList = self

    if self:SetButtonPos(button, pos) then
        button:Refresh()
        table.insert(self.buttons, button) -- Do we need these?
        return true
    else
        -- Hide it away until it is visible
        self.buttonFactory:Put(button)
        return false
    end
end

function obj:SetButtonPos(button, pos)
    local slotName = self.visual:GetName() .. "Slot" .. pos
    return button:Overlay(slotName)
end

function obj:GetIterator()
    return self.players:GetIterator(self.filterfunc, self.sortfunc)
end
