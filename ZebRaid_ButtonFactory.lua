local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

local obj = ZebRaid:NewClass(
    "ButtonFactory",
    {
        buttons = {},
        -- This is where we register the button objects of players
        objStore = {},
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

function obj:Get(player)
    if not self.class.objStore[player] then
        local button = self:Allocate()
        button.obj = ZebRaid:Construct("Button", button, player)
        self.class.objStore[player] = {obj=button.obj, refcount=0}
    end
    local data = self.class.objStore[player]
    data.refcount = data.refcount + 1
    local obj = data.obj
    obj:Hide()
    return obj
end

function obj:Put(button)
    -- Nothing to do here. Buttons are always kept in cache. Maybe we'll make
    -- the store into a weak valued table to garbage collection if memory usage
    -- is too high.
    local data = self.class.objStore[button.player]
    -- I don't like the idea of refcounting. Probably I will need a better
    -- method to assign buttons to lists. For now, just make it work.
    data.refcount = data.refcount - 1
    if data.refcount == 0 then
        data.obj:Hide()
    end
end

-- I am not expecting to call this, but putting it here for completeness.
function obj:Destroy(button)
    if self.class.objStore[button.player] then
        self.class.objStore[button.player] = nil
        button.player = nil
        button.obj = nil
        self:Free(button)
    end
end

-- The button objects that help maintain player buttons
local Button = ZebRaid:NewClass("Button", {})

function Button:Construct(button, player)
    -- Note that button and self are not the same objects. button is the frame,
    -- self is the object
    button.player = player
    self.button = button
    self.player = player
    -- The fixed portion of buttons. If any of these become variable, they need
    -- to move to Refresh() method.
    self:SetRole()
    self:SetLabel()
    self:Refresh()
end

function Button:Refresh()
    self:UpdateColor()
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

function Button:SetRole()
    local buttonRole = getglobal(self.button:GetName() .. "Role")
    local prefix = ""

    -- Put a * before the role if there is a note.
    if self.player:GetSignupNote() then
        prefix = prefix .. "*"
    end

    buttonRole:SetText(prefix .. (RoleLetters[self.player:GetRole()] or "X") )

    buttonRole:SetTextColor(0.8, 0.8, 0)
end

function Button:SetLabel()
    local buttonLabel = getglobal(self.button:GetName() .. "Label")

    -- Put a x before the name if the user has unsigned from the raid
    local prefix = ""
    -- TODO: Move constants to a sensible location
    if self.player:GetSignupStatus() == ZebRaid.signup_const.unsigned then
        prefix = prefix .. "x"
    end

    buttonLabel:SetText(prefix .. self.player:GetName())
    buttonLabel:SetTextColor(self.player:GetClassColor())
end

-- TODO: These are supposed to be only for the confirmed list
-- We may need a special callout for the logic here
function Button:UpdateColor()
    local buttonColor = getglobal(self.button:GetName() .. "Color")
    if self.player:IsOnline() then
        if self.player:IsInRaid() then
            -- Confirmed and in raid player background color
            buttonColor:SetTexture(0.1, 0.3, 0.1)
        else
            -- Online player background color
            buttonColor:SetTexture(0.05, 0.05, 0.05)
        end
    else
        if self.player:IsInRaid() then
            -- Offline: Confirmed and in raid player background color
            buttonColor:SetTexture(0.2, 0.2, 0.1)
        elseif self.player:IsAltOnline() then
            buttonColor:SetTexture(0.1, 0.1, 0.2)
        else
            -- Offline player background color
            buttonColor:SetTexture(0.2, 0.1, 0.1)
        end
    end
end

function Button:Overlay(slotName)
    -- Place the button in its list
    self.button:ClearAllPoints()
    -- TODO: Layou the slots dynamically at constructor
    local slot = getglobal(slotName)
    if slot then
        self.button:SetPoint("TOP", slot)
        self.button:SetHitRectInsets(0, 0, 0, 0)
        self.button:SetFrameLevel(slot:GetFrameLevel() + 20)
        self.button:RegisterForDrag("LeftButton")
        self.button:Show()
        return true
    else
        return false
   end
end

function Button:Hide()
    self.button:Hide()
end
