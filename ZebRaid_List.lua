-- TODO: Create a button object
local Guild = LibStub("LibGuild-1.0")
local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- The function prototypes will go in here
local List_Template = {
}

-- Define a shorter name for the following code

local obj = List_Template

function ZebRaid:NewList(name, visual, assignment)
    list = setmetatable({}, {__index = List_Template })
    list:Construct(name, visual, assignment)
    return list
end

function obj:Construct(name, visual, assignment)
    self.name = name
    self.visual = visual
    self.state = ZebRaid:NewState()
    self.buttonFactory = ZebRaid:NewButtonFactory()
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
    for i, name in self.state:GetPlayerIterator(self.filterfunc, self.sortfunc) do
        DEFAULT_CHAT_FRAME:AddMessage("i="..i.."name="..(name or "nil"))
        -- TODO: It should be possible to do incremental updates here
        -- WTB more side-effect programming. Fix it!
        if makebuttons and not self:InsertNewButton(name, i) then
            -- List full. No need to add buttons further. But contiune the loop
            -- to have up-to-date counts
            makebuttons = false
        end
        -- Keep statistics. :)
        local role = self.state.players:GetRole(name)
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

function obj:InsertNewButton(name, pos)
    local button = self.buttonFactory:Allocate()
    button.inList = self
    self:SetButtonRole(button, name)
    self:SetButtonLabel(button, name)
    self:SetButtonColor(button, name)
    self:SetButtonTooltip(button, name)

    button.player = name
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

function obj:SetButtonRole(button, name)
	local buttonRole = getglobal(button:GetName() .. "Role")
	local prefix = ""

	-- Put a * before the role if there is a note.
    if self.state:GetSignupNote(name) then
        prefix = prefix .. "*"
	end

	buttonRole:SetText(prefix .. (RoleLetters[self.state.players:GetRole(name)] or "X") )

	buttonRole:SetTextColor(0.8, 0.8, 0)
end

function obj:SetButtonLabel(button, name)
	local buttonLabel = getglobal(button:GetName() .. "Label")

	-- Put a x before the name if the user has unsigned from the raid
	local prefix = ""
    if self.state:GetSignupStatus() == "unsigned" then
        prefix = prefix .. "x"
    end

	buttonLabel:SetText(prefix .. name)
	buttonLabel:SetTextColor(Guild:GetClassColor(name))
end

-- TODO: These are supposed to be only for the confirmed list
-- We may need a special callout for the logic here
function obj:SetButtonColor(button, name)
	local buttonColor = getglobal(button:GetName() .. "Color")
	if Guild:IsMemberOnline(name) then
		if ZebRaid:IsPlayerInRaid(name) then
			-- Confirmed and in raid player background color
			buttonColor:SetTexture(0.1, 0.3, 0.1)
		else
			-- Online player background color
			buttonColor:SetTexture(0.05, 0.05, 0.05)
		end
	else
		if ZebRaid:IsPlayerInRaid(button, name) then
			-- Offline: Confirmed and in raid player background color
			buttonColor:SetTexture(0.2, 0.2, 0.1)
		elseif ZebRaid:Tracker_IsAltOnline(name) then
			buttonColor:SetTexture(0.1, 0.1, 0.2)
		else
			-- Offline player background color
			buttonColor:SetTexture(0.2, 0.1, 0.1)
		end
	end
end

function obj:SetButtonTooltip(button, name)
	-- Add the guild info to tooltip
	button.tooltipDblLine = {
		left = name,
		right = Guild:GetClass(name)
	}

	button.tooltipText = self.state:GetTooltipText(name)
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
        button.inList = list
        button:Show()
        return true
    else
        return false
   end
end

function obj:GetIterator()
    return self.state:GetPlayerIterator(self.filterfunc, self.sortfunc)
end
