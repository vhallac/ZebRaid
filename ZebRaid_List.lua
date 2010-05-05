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
        self.buttonFactory:Free(v)
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
    local button = self.buttonFactory:Allocate()
    button.inList = self
    button.player = player
    self:SetButtonRole(button, player)
    self:SetButtonLabel(button, player)
    self:SetButtonColor(button, player)

    if self:SetButtonPos(button, pos) then
        table.insert(self.buttons, button)
        return true
    else
        -- A bit of a waste to do it like this, but cleaner code. Will leave it
        -- in for now.
        self.buttonFactory:Free(button)
        return false
    end
end

-- The letters we use in the lists to indicate raid role
local RoleLetters = {
    melee = "M",
    tank = "T",
    healer = "H",
    ranged = "R",
    hybrid = "Y",
    unknown = "?"
}

function obj:SetButtonRole(button, player)
    local buttonRole = getglobal(button:GetName() .. "Role")
    local prefix = ""

    -- Put a * before the role if there is a note.
    if player:GetSignupNote() then
        prefix = prefix .. "*"
    end

    buttonRole:SetText(prefix .. (RoleLetters[player:GetRole()] or "X") )

    buttonRole:SetTextColor(0.8, 0.8, 0)
end

function obj:SetButtonLabel(button, player)
    local buttonLabel = getglobal(button:GetName() .. "Label")

    -- Put a x before the name if the user has unsigned from the raid
    local prefix = ""
    -- TODO: Move constants to a sensible location
    if player:GetSignupStatus() == ZebRaid.signup_const.unsigned then
        prefix = prefix .. "x"
    end

    buttonLabel:SetText(prefix .. player:GetName())
    -- TODO: Add GetClassColor() to player class
    buttonLabel:SetTextColor(Guild:GetClassColor(player:GetName()))
end

-- TODO: These are supposed to be only for the confirmed list
-- We may need a special callout for the logic here
function obj:SetButtonColor(button, player)
    local buttonColor = getglobal(button:GetName() .. "Color")
    if player:IsOnline() then
        -- TODO: Move to player class
        if ZebRaid:IsPlayerInRaid(player:GetName()) then
            -- Confirmed and in raid player background color
            buttonColor:SetTexture(0.1, 0.3, 0.1)
        else
            -- Online player background color
            buttonColor:SetTexture(0.05, 0.05, 0.05)
        end
    else
        if ZebRaid:IsPlayerInRaid(player:GetName()) then
            -- Offline: Confirmed and in raid player background color
            buttonColor:SetTexture(0.2, 0.2, 0.1)
            -- TODO: Move to player class
        elseif ZebRaid:Tracker_IsAltOnline(player:GetName()) then
            buttonColor:SetTexture(0.1, 0.1, 0.2)
        else
            -- Offline player background color
            buttonColor:SetTexture(0.2, 0.1, 0.1)
        end
    end
end

function obj:SetButtonPos(button, pos)
    -- Place the button in its list
    button:ClearAllPoints()
    -- TODO: Layou the slots dynamically at constructor
    local slot = getglobal(self.visual:GetName() .. "Slot" .. pos)
    if slot then
        button:SetPoint("TOP", slot)
        button:SetHitRectInsets(0, 0, 0, 0)
        button:SetFrameLevel(slot:GetFrameLevel() + 20)
        button:RegisterForDrag("LeftButton")
        button:Show()
        return true
    else
        return false
   end
end

function obj:GetIterator()
    return self.players:GetIterator(self.filterfunc, self.sortfunc)
end
