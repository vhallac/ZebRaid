﻿local addonName, addonTable = ...
ZebRaid = LibStub("AceAddon-3.0"):NewAddon("ZebRaid", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)
local Guild = LibStub("LibGuild-1.0")
-- Allow objects access to addon functions
addonTable.ZebRaid = ZebRaid

local options = {
	name = "ZebRaid",
	handler = ZebRaid,
	type = 'group',
	args = {
		start = {
			type = 'execute',
			name = 'Start planning the raid',
			desc = L["START_DIALOG"],
			func = function() ZebRaid:Start() end,
		},
	}
}

local ON_TIME_KARMA_VAL = 5
local MAX_NUM_BUTTONS = 100 -- See the ZebRaid.xml for this

local FreePlayerButton = 1 -- The button index that is available.
local ListNames = {
	"GuildList",
	"SignedUp",
	"Unsure",
	"Confirmed",
	"Reserved",
	"Penalty",
	"Sitout"
}

local StartWasCalled = nil
local NeedRecalculateAfterUpdate = nil
local PlayerName = nil
local DraggingPlayer = nil

ZebRaid.Lists = {}
ZebRaid.RegisteredUsers = {}

local RemotePlayer = nil
local RemoteRaidIdList = nil

ZebRaid.UiLockedDown = true

-- Player information
ZebRaidPlayerData = {}

-- Alt Tracker information
ZebRaidTrackerData = {}

-- Temprary set up for add-on comms handler
ZebRaid.OnCommReceive = {}

-- List of karma databases.
ZebRaid.KarmaList = {}

-- Saved variables
ZebRaidState = {}
ZebRaidPlayerData = {}



-------------------------------
-- UI and Ace Event Handlers --
-------------------------------

-- Called when the addon is loaded
function ZebRaid:OnInitialize()
	local libCfg = LibStub("AceConfig-3.0")
	if libCfg then
		libCfg:RegisterOptionsTable("ZebRaid", options, {"zebr", "zebraid"})
	end

	self:SetDebugging(false)

	--
	-- Set up the Dialog Labels {{{
	--
	for i=1, 30 do
		getglobal("ZebRaidDialogPanelSignedUpSlot"..i.."Label"):SetText("---")
		getglobal("ZebRaidDialogPanelUnsureSlot"..i.."Label"):SetText("---")
		getglobal("ZebRaidDialogPanelConfirmedSlot"..i.."Label"):SetText("---")
		getglobal("ZebRaidDialogPanelReservedSlot"..i.."Label"):SetText("---")
		getglobal("ZebRaidDialogPanelGuildListSlot"..i.."Label"):SetText("---")
		if (i < 15) then
			getglobal("ZebRaidDialogPanelPenaltySlot"..i.."Label"):SetText("---")
			getglobal("ZebRaidDialogPanelSitoutSlot"..i.."Label"):SetText("---")
		end
	end

	--
	-- Set up the button texts according to locale
	--
	ZebRaidDialogCommandsAutoConfirm:SetText(L["AUTOCONFIRM"])
	ZebRaidDialogCommandsReset:SetText(L["RESET"])
	ZebRaidDialogCommandsGiveKarma:SetText(L["KARMA"])
	ZebRaidDialogCommandsAnnounce:SetText(L["ANNOUNCE"])
	ZebRaidDialogCommandsSync:SetText(L["SYNCH"])
	ZebRaidDialogCommandsUnlock:SetText(L["UNLOCK"])

	ZebRaidDialogGiveKarma:SetText(L["KARMA"])

	ZebRaidDialogConfirmedStatsTitle:SetText(L["CONFIRMED_STATS"])
	ZebRaidDialogConfirmedStatsTank:SetTextColor(self:GetClassColor("WARRIOR"))
	ZebRaidDialogConfirmedStatsMelee:SetTextColor(self:GetClassColor("ROGUE"))
	ZebRaidDialogConfirmedStatsHealer:SetTextColor(self:GetClassColor("PRIEST"))
	ZebRaidDialogConfirmedStatsRanged:SetTextColor(self:GetClassColor("MAGE"))
	ZebRaidDialogConfirmedStatsTotal:SetTextColor(1, .6, 0)

	ZebRaidDialogTotalStatsTitle:SetText(L["TOTAL_STATS"])
	ZebRaidDialogTotalStatsTank:SetTextColor(self:GetClassColor("WARRIOR"))
	ZebRaidDialogTotalStatsMelee:SetTextColor(self:GetClassColor("ROGUE"))
	ZebRaidDialogTotalStatsHealer:SetTextColor(self:GetClassColor("PRIEST"))
	ZebRaidDialogTotalStatsRanged:SetTextColor(self:GetClassColor("MAGE"))
	ZebRaidDialogTotalStatsTotal:SetTextColor(1, .6, 0)

	--
	-- Prepare the popup dialog
	--
	StaticPopupDialogs["ZEBRAID_SHOW_UNKNOWN_RAIDS"] = {
		text = L["SYNCHCONFIRMATION"],
		button1 = "Yes",
		button2 = "No",
		OnAccept = function(data)
			--[[
			for pos, val in pairs(data.raidIdList) do
				if not ZebRaidHistory[val] then
					ZebRaid:SendCommMessage("WHISPER", data.sender, "REQUESTDETAILS", val)
				end
			end
			]]--
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1
	}
end

function ZebRaid:OnEnable()
	-- Set the saved variable backend for modules
	self:SetStateBackend(ZebRaidState)
	self:SetPlayerDataBackend(ZebRaidPlayerData)

	if not self.state then
		---
		--- Create the state object
		---
		self.state = self:NewState()
	end

	PlayerName, _ = UnitName("player")

	Guild.RegisterCallback(self, "Update", "GuildStatusUpdated")
	Guild.RegisterCallback(self, "Added", "MemberAdded")
	Guild.RegisterCallback(self, "Removed", "MemberRemoved")
	Guild.RegisterCallback(self, "Connected", "MemberConnected")
	Guild.RegisterCallback(self, "Disconnected", "MemberDisconnected")
	self:RegisterMessage("ZebRaid_RosterUpdated", "RosterUpdated")

	ZebRaidDialogCommandsInviteRaid:SetText(L["START_RAID"])

	-- Get ready to receive add-on comms
	self:CommInit()

	-- Start off with interface locked.
	self:LockUI()

	self:Tracker_Init()

	-- select the indicated karma DB when appropriate:
	if self.state:GetKarmaDb() then
		if Karma_command then
			Karma_command("use " .. self.state:GetKarmaDb())
		end
	end

	--
	-- Fill the lists out according to online and registered users
	--
	self:InitializeLists()

	-- Tell the rest of the guild that we are here.
	self:BroadcastComm("BROADCAST")
end

function ZebRaid:OnDisable()
	-- Hide the main dialog
	ZebRaidDialog:Hide()

	-- Stop responding to stuff
	self:UnregisterAllEvents()
	self:UnregisterAllMessages()
	self:Tracker_Final()
	self:CommFinal()
end

function ZebRaid:Start()
	self:Debug("ZebRaid:Start")

	if not self:IsEnabled() then return end

	if StartWasCalled then
		StartWasCalled = nil
		ZebRaidDialog:Hide()
		ZebRaid:RosterFinal()
		return
	end

	self:RosterInit()

	local karmaDb = self.state:GetKarmaDb()
	local uiMaster = self.state:GetUiMaster(karmaDb)
	if karmaDb then
		if not uiMaster then
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
		elseif uiMaster == PlayerName then
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
		else
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. uiMaster)
		end
	else
		ZebRaidDialogReportMaster:SetText(L["REPORT_NO_DB"])
	end

	-- Get rid of left-over state information
	self.state:Cleanup()

	-- If our karma db name list is empty, and if Ni_Karma is loaded, copy the
	-- database names in.
	if #self.KarmaList == 0 and KarmaList then
		-- Copy the Karma database names
		for db, val in pairs(KarmaList) do
			table.insert(self.KarmaList, db)
		end
	end

	-- Display the current setup
	local raidID = self.state:GetRaidId() or ZebRaid.RaidID

	ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidID)
	self:ShowListMembers()

	-- TODO: Tracker not supported yet...
	-- If there is an offline player in the Sitout list, ask their alts' tracker to respond
--[[
	if ZebRaidState.KarmaDB and
	   ZebRaidState[ZebRaidState.KarmaDB]
	then
		local state = ZebRaidState[ZebRaidState.KarmaDB]
		if state.Lists["Sitout"] then
			for _, player in ipairs(state.Lists["Sitout"].members) do
				if not Guild:IsMemberOnline(player) and
					ZebRaidPlayerData[player] and
					ZebRaidPlayerData[player].AltList
				then
					for name in pairs(ZebRaidPlayerData[player].AltList) do
						self:Tracker_QueryPresence(name)
					end
				end
			end
		end
	end
--]]
	StartWasCalled = true

	ZebRaidDialog:Show()
end

local movingButtonLevel

function ZebRaid:PlayerOnDragStart(frame)
	self:Debug("PlayerOnDragStart")

	movingButtonLevel = frame:GetFrameLevel()
	if self.UiLockedDown then return end

	local cursorX, cursorY = GetCursorPosition()
	DraggingPlayer = true
	frame:StartMoving()
	frame:SetFrameLevel(movingButtonLevel + 30)
end

local destListNames = {
	"GuildList",
	"SignedUp",
	"Unsure",
	"Confirmed",
	"Reserved",
	"Penalty",
	"Sitout"
}

function ZebRaid:PlayerOnDragStop(frame)
	self:Debug("PlayerOnDragStop")

	frame:SetFrameLevel(movingButtonLevel)
	frame:StopMovingOrSizing()

	if self.UiLockedDown then self:ShowListMembers(); return end

	local selectedList = nil
	for _, list in ipairs(destListNames) do
		if MouseIsOver(getglobal("ZebRaidDialogPanel" .. list )) then
			selectedList = list
			break
		else
			for slot=1,30 do
				local slotFrame = getglobal("ZebRaidDialogPanel" .. list ..  "Slot" .. slot)
				if slotFrame and MouseIsOver(slotFrame) then
					selectedList = list
					break
				end
			end
		end
		if selectedList then break end
	end
	self:Debug("MouseIsOver: " .. (selectedList or "nothing"))

	-- Go back from visual to logical list object: If we've dropped on a new
	-- list, shoose that list. If not, then choose the list the button
	-- originated from.
	local list
	if selectedList then
		list = selectedList.listObj
	else
		list = frame.inList
	end

	-- Not signed up or unsigned => Cannot go to SignedUp, Unsure, or Penalty
	-- Allow Sitout for people who forgot to sign.
	local signStat = self.state:GetSignupStatus(frame.player)
	if signStat == "unsigned" or signStat == "unknown" then
		if ( selectedList == "Penalty" or
			 selectedList == "SignedUp" or
			 selectedList == "Unsure")
		then
			list = frame.inList
		end
	else
		-- Unsure => Cannot go to Penalty
		if selectedList == "Penalty" and signStat == "unsure" then
			list = frame.inList
		end

		-- SignedUp or Unsure cannot go back to guild
		if signStat ~= "unknown" and selectedList == "GuildList" then
			list = frame.inList
		end

		-- SignedUp and Unsure cannot go each other

		if  ( signStat == "signed" and selectedList == "Unsure" ) or
			( signStat == "unsure" and selectedList == "SignedUp" )
		then
			list = frame.inList
		end
	end

	-- FIXME: List handling will be modified
	if list ~= frame.inList then
		self.state:SetAssignment(button.player, list:GetAssignment())
	end

	DraggingPlayer = nil

	self:ShowListMembers()
end

function ZebRaid:PlayerOnDoubleClick(frame, button)
	self:Debug("ZebRaid:OnDoubleClick")

	if self.UiLockedDown then return end

	local newassignment = self:ToggleAssignment(frame.player)
	if self.state:GetAssignment(frame.player) ~= newassignment then
		self.state:SetAssignment(frame.player, newassignment)
		self:ShowListMembers()
	end
end

-- Find a suitable assignment for the specified player
-- RETURNS: the selected list, or null.
function ZebRaid:ToggleAssignment(name)
	local assignment = self.state:GetAssignment(name)
	local signup = self.state:GetSignupStatus(name)
	local newassignment = "unassigned"

	if assignment == "unassigned" then
		if signup == "signed" then
			newassignment = "confirmed"
		elseif signup == "unsure" then
			if Guild:IsMemberOnline(name) then
				newassignment = "confirmed"
			else
				newassignment = "reserved"
			end
		else -- Guild list: only shows online people, so I must want to confirm them
			newassignment = "confirmed"
		end
	elseif assignment == "reserved" or
		assignment == "confirmed" or
		assignment == "penalty" or
		assignment == "sitout"
	then
		newassignment = "unassigned"
	end

	-- TODO: Want to implement this?
	-- If the guy has a penalty, he moves to sitout
	-- regardless of the current selection

	return newassignment;
end

function ZebRaid:MemberConnected(name)
	self:Debug("Got member: " .. name)

	-- If the player has ever signed up with this name, set it to be the main character
	self:Tracker_SetPlayerMain(name)

	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	if Guild:GetLevel(name) ~= 80 then return end

	if not self.state:GetKarmaDb() then return end

	if self.state:GetAssignment(name) == "unknown" then
		self.state:SetAssignment(name, "unassigned")
	end

	-- FIXME: This is really overkill. We should have a button object, and a way
	-- to get the button of the player. That way we don't redraw the world when
	-- all we need is a single color change.
	NeedRecalculateAfterUpdate = true

	-- Since this instance is the current master, let the alt know where to
	-- report status
	self:Tracker_SetTracker(name)
end

function ZebRaid:MemberDisconnected(name)
	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	if not self.state:GetKarmaDb() then return end

	if self.state:GetAssignment(name) == "unassigned" and
		self.state:GetSignupStatus(name) == "unknown"
	then
		self.state:RemoveAssignment(name)
	end

	-- FIXME: See above note about overkill.
	NeedRecalculateAfterUpdate = true
end

function ZebRaid:MemberAdded(name)
	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	-- Do we need to do anything here? He'll come online, and we'll process
	-- him.
end

function ZebRaid:MemberRemoved(name)
	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	if not self.state:GetKarmaDb() then return end

	-- We just gkicked the bugger. No assignment for him!
	self.state:RemoveAssignment(name)
	NeedRecalculateAfterUpdate = true
end

function ZebRaid:GuildStatusUpdated()
	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	if NeedRecalculateAfterUpdate then
		self:ShowListMembers()
		NeedRecalculateAfterUpdate = nil
	end
end

local LastUpdateTime = GetTime()

function ZebRaid:OnUpdate()
	-- If we call ShowListMembers() too often, the UI becomes unresponsive.
	-- e.g. resisting drag-drop attempts.
	-- TODO: Optimize the loop.
	-- FIXME: Remove OnUpdate() updates altogether. Update when something changes.
	if not DraggingPlayer and (GetTime() - LastUpdateTime > 1) then
-- FIXME: See if we still need this. We shouldn't
--		self:ShowListMembers()
		LastUpdateTime = GetTime()
	end
end

function ZebRaid:AutoConfirm()
	if self.UiLockedDown then return end

	if not self.state:GetKarmaDb() then return end

	-- Move all unassigned people who are signed up to confirmed.
	for i, name in self.SignedUp:GetIterator() do
		if Guild:IsMemberOnline(name) then
			self.state:SetAssignment(name, "confirmed")
		end
	end

	self:ShowListMembers()
end

function ZebRaid:Announce()
	if self.UiLockedDown then return end

	if not self.state:GetKarmaDb() then return end

	local message = ""
	local totalCount = self.Sitout:GetTotalCount()
	if totalCount > 0 then
		for i, name in self.Sitout:GetIterator() do
			message = message .. name
			if i ~= totalCount then
				message = message .. ", "
			else
				message = message .. "."
			end
		end
	end

	-- FIXME: Add note for raid karma db name (perhaps): T5SE may not mean for guildies.
	SendChatMessage("--------------------\r\n" ..
					L["SITOUT_ANNOUNCE_MSG"] .. "\r\n" ..
					message .. "\r\n" ..
					"--------------------", "GUILD")
--[[
		SendChatMessage(L["SITOUT_ANNOUNCE_MSG"], "GUILD")
		SendChatMessage(message, "GUILD")
		SendChatMessage("--------------------", "GUILD")
		]]
end

function ZebRaid:GiveKarma()
	if self.UiLockedDown then return end

	if not self.state:GetKarmaDb() then return end

	-- TODO: Make sure on time karma cannot be given twice for the same raid
	-- If we can give karma ...
	if not Karma_Add_Player then
		DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_ADDON"])
		return
	end

	if not KarmaConfig["CURRENT RAID"] then
		DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DB"])
		return
	end

	-- Give on time karma to all Confirmed and Sitout users.
	for pos, name in self.Confirmed:GetIterator() do
		-- Only confirmed people who are in raid deserve online karma. :-)
		if self:IsPlayerInRaid(name) then
			self:Debug("Giving on time karma to " .. name)
			-- Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P")
		end
	end

	for pos, name in self.Sitout:GetIterator() do
		Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P")
	end
end

function ZebRaid:InitializeLists()
	local and_ = function (...)
		local funcs={...}

		return function(name)
			local res
			for i, f in ipairs(funcs) do
				res = res and f(name)
				if not res then break end
			end
			return res
			   end
	end

	local filter_by_signup = function(status)
		return function(name)
			return self:GetSignupStatus(name) == status
			   end
	end

	local filter_by_assignment = function(assignment)
		return function(name)
			return self.state:GetAssignment(name) == status
			   end
	end

	local is_online = function(name)
		return Guild:IsPlayerOnline(name)
	end

	if not self.GuildList then
		self.GuildList = self:NewList("GuildList",
									  getglobal("ZebRaidDialogPanelGuildList"),
									  "unassigned")
		self.GuildList:SetFilterFunc(and_(filter_by_signup("unknown"),
										  filter_by_assignment("unassigned"),
										  is_online))
		self.GuildList:Update()
	end

	if not self.SignedUp then
		self.SignedUp = self:NewList("SignedUp",
									 getglobal("ZebRaidDialogPanelSignedUp"),
									 "unassigned")
		self.SignedUp:SetFilterFunc(and_(filter_by_signup("signed"),
										 filter_by_assignment("unassigned")))
		self.SignedUp:Update()
	end

	if not self.Unsure then
		self.Unsure = self:NewList("Unsure",
								   getglobal("ZebRaidDialogPanelUnsure"),
								   "unassigned")
		self.Unsure:SetFilterFunc(and_(filter_by_signup("unsure"),
									   filter_by_assignment("unassigned")))
		self.Unsure:Update()
	end

	if not self.Confirmed then
		self.Confirmed = self:NewList("Confirmed",
									  getglobal("ZebRaidDialogPanelConfirmed"),
									  "confirmed")
		self.Confirmed:SetFilterFunc(filter_by_assignment("confirmed"))
		self.Confirmed:Update()
	end

	if not self.Reserved then
		self.Reserved = self:NewList("Reserved",
									 getglobal("ZebRaidDialogPanelReserved"),
									 "reserved")
		self.Confirmed:SetFilterFunc(filter_by_assignment("reserved"))
		self.Reserved:Update()
	end

	if not self.Penalty then
		self.Penalty = self:NewList("Penalty",
									getglobal("ZebRaidDialogPanelPenalty"),
								    "penalty")
		self.Penalty:SetFilterFunc(filter_by_assignment("penalty"))
		self.Penalty:Update()
	end

	if not self.Sitout then
		self.Sitout = self:NewList("Sitout",
								   getglobal("ZebRaidDialogPanelSitout"),
								   "sitout")
		self.Sitout:SetFilterFunc(filter_by_assignment("sitout"))
		self.Sitout:Update()
	end


--[[ TODO: Tracker - How did it work again?
	-- Create the lists
	for _, list in pairs(ListNames) do
		state.Lists[list] = self:NewList(list)
	end

	for name, val in pairs(state.RegisteredUsers) do
		-- Tell all registered users that they are main chars
		-- if they are online
		if Guild:IsMemberOnline(name) then
			self:Tracker_SetPlayerMain(name)
		end
	end
--]]
end

function ZebRaid:Reset()
	self:Debug("ZebRaid:Reset")

	if self.UiLockedDown then return end
	if not self:IsEnabled() then return end

	self.state:ResetAssignments()

	--[[
	self:BroadcastComm("ANNOUNCE_MASTER",
	ZebRaidState.KarmaDB, state.RaidID,
	state.RegisteredUsers,
	state.Lists)
	--]]
	self:ShowListMembers()
end

function ZebRaid:RaidSelection_OnShow()
	if not self.initSortDropDown then
		UIDropDownMenu_Initialize(this, function() self:RaidSelection_Populate() end)
		self.initSortDropDown = true
	end
end

function ZebRaid:RaidSelection_Populate()
	local info
	local dbList = {}

	if self.KarmaList then
		for db, val in pairs(self.KarmaList) do
			table.insert(dbList, val)
		end
	end

	for pos, name in pairs(dbList) do
		info = UIDropDownMenu_CreateInfo()
		info.value = pos
		info.owner = this:GetParent()
		info.text = name
		info.func = function() ZebRaid:RaidSelection_OnClick() end
		UIDropDownMenu_AddButton(info)
		if name == self.state:GetKarmaDb() then
			UIDropDownMenu_SetSelectedValue(ZebRaidDialogRaidSelection, pos)
		end
	end
end

function ZebRaid:RaidSelection_OnClick()
	self:Debug("ZebRaid:RaidSelection_OnClick: " .. this:GetText() .. ", " .. this.value)

	UIDropDownMenu_SetSelectedValue(this.owner, this.value)
	local karmaDB=this:GetText()
	self.state:SetKarmaDb(karmaDB)

	if Karma_command then
		Karma_command("use " .. karmaDB)
	end

	if not self.state:GetRaidId() then
		self.state:SetRaidId(self.RaidID)
	end

	-- Display the current setup
	self:ShowListMembers()

	local raidId = self.state:GetRaidId()

	local uiMaster = self.state:GetUiMaster(karmaDB)
	if not uiMaster then
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
		self:LockUI()
	elseif uiMaster == PlayerName then
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
		self:UnlockUI()
	else
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. uiMaster)
		self:LockUI()
	end

	ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidId)
end

----------------------
-- Helper Functions --
----------------------

-- Find a list position in the list members where a new player should be
-- inserted according to its class. The list must already be sorted by class.
function ZebRaid:FindClassInsertPos(list, name)
	local playerClass = Guild:GetClass(name)
	local foundClassStart = nil
	local insertPos = nil
	for pos, val in pairs(list.members) do
		if Guild:GetClass(val) == playerClass then
			foundClassStart = true
		end
		if foundClassStart and Guild:GetClass(val) ~= playerClass then
			insertPos = pos
			break
		end
	end

	return insertPos
end

-- Obtain the sitout position of a player from the saved state
function ZebRaid:GetPlayerSitoutPos(name)
	local stat = ZebRaidPlayerData[name]
	local sitoutPos = 0
	if stat then
		sitoutPos = stat.sitoutPos
	end
	return sitoutPos
end

-- return true if a>b, false otherwise
-- Compares dates of format MM/DD/YY
local function isDateGreater(a, b)
	-- Convert from MM/DD/YY to YY/MM/DD for all dates
	a = a:gsub("^(.*)/(.*)$", "%2/%1")
	b = b:gsub("^(.*)/(.*)$", "%2/%1")
	return a > b
end

-- return true if a<b, false otherwise
-- Compares dates of format MM/DD/YY
local function isDateLesser(a, b)
	-- Convert from MM/DD/YY to YY/MM/DD for all dates
	a = a:gsub("^(.*)/(.*)$", "%2/%1")
	b = b:gsub("^(.*)/(.*)$", "%2/%1")
	return a < b
end

-- Find a list position in the list members where a new player should be inserted
-- according to its sitoutPos value. The list must already be sorted by the sitoutInsertPos
function ZebRaid:FindSitoutInsertPos(list, name)
	--local playerSitoutPos = self:GetPlayerSitoutPos(name)
	local playerSitoutCount = self.state.players:GetSitoutCount(name)
	local playerLastSitoutDate = self.state.players:GetLastSitoutDate(name)
	local playerLastPenaltyDate = self.state.players:GetLastPenaltyDate(name)
	local playerHasPenalty = isDateGreater(playerLastPenaltyDate,
										   playerLastSitoutDate)
	local playerRole = RoleLetters[self.state.players:GetRole(name)] or "X"
	local insertPos = nil
	local curLastSitoutDate, curRole
	local curLastPenaltyDate, curHasPenalty
	for pos, val in ipairs(list.members) do
		curSitoutCount = self.state.players:GetSitoutCount(val)
		curLastSitoutDate = self.state.players:GetLastSitoutDate(val)
		curLastPenaltyDate = self.state.players:GetLastPenaltyDate(val)
		curHasPenalty = isDateGreater(curLastPenaltyDate, curLastSitoutDate)
		curRole = RoleLetters[self.state.players:GetRole(val)] or "X"
		if playerRole < curRole or
			(playerRole == curRole and playerHasPenalty) or
			(playerRole == curRole and isDateLesser(playerLastSitoutDate, curLastSitoutDate) and not curHasPenalty) or
			(playerRole == curRole and playerLastSitoutDate == curLastSitoutDate and playerSitoutCount < curSitoutCount and not curHasPenalty)
		then
			insertPos = pos
			break
		end
	end

	return insertPos
end

function ZebRaid:GetRaidDate()
	local raidId = self.state:GetRaidId()
	_,_,d,m,y=string.find(raidId, ".*_(%d+).(%d+).20(%d+)")
	return string.format("%02d/%02d/%02d",d,m,y)
end

function ZebRaid:ShowListMembers()
	local add_counts = function(o1, o2)
		return {
			GetCount = function (dummyobj, role)
				return o1:GetCount(role) + o2:GetCount(role)
			end }
	end
	-- If we haven't selected a list, or (for some reason) the
	-- selection has no state, then do not attempt to draw anything.
	if not self.state:GetKarmaDb() then
		-- FIXME: This extra check should not be needed
		self:UpdateCounts("ZebRaidDialogConfirmedStats", self.Confirmed)
		self:UpdateCounts("ZebRaidDialogTotalStats", add_counts(self.Confirmed,
																self.Reserved))
		ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] .. " (0)")
		ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] .. " (0)")
		ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] .. " (0)")
		ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] .. " (0)")
		ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] .. " (0)")
		ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] .. " (0)")
		ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] .. " (0)")
	else
		self.GuildList:Update()
		self.SignedUp:Update()
		self.Unsure:Update()
		self.Confirmed:Update()
		self.Reserved:Update()
		self.Penalty:Update()
		self.Sitout:Update()

		ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] ..
												" (" .. self.SignedUp:GetTotalCount() .. ")")
		ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] ..
												" (" .. self.Unsure:GetTotalCount() .. ")")
		ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] ..
												" (" .. self.Confirmed:GetTotalCount() .. ")")
		ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] ..
												" (" .. self.Reserved:GetTotalCount() .. ")")
		ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] ..
												" (" .. self.GuildList:GetTotalCount() .. ")")
		ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] ..
												" (" .. self.Penalty:GetTotalCount() .. ")")
		ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] ..
												" (" .. self.Sitout:GetTotalCount() .. ")")

		self:UpdateCounts("ZebRaidDialogConfirmedStats", self.Confirmed)
		self:UpdateCounts("ZebRaidDialogTotalStats", add_counts(self.Confirmed,
																self.Reserved))
	end
end

function ZebRaid:UpdateCounts(panelName, list)
	getglobal(panelName .. "Tank"):SetText(L["TANK"] .. ": " ..
										   list:GetCount("tank"))
	getglobal(panelName .. "Melee"):SetText(L["MELEE"] .. ": " ..
											list:GetCount("melee"))
	getglobal(panelName .. "Healer"):SetText(L["HEALER"] .. ": " ..
											 list:GetCount("healer"))
	getglobal(panelName .. "Ranged"):SetText(L["RANGED"] .. ": " ..
											 list:GetCount("ranged"))
	getglobal(panelName .. "Total"):SetText(L["TOTAL"]..": " ..
											list:GetCount("tank") +
											list:GetCount("melee") +
											list:GetCount("healer") +
											list:GetCount("ranged"))
end

function ZebRaid:LockUI()
	ZebRaid.UiLockedDown = true
	ZebRaidDialogCommandsAutoConfirm:Disable()
	ZebRaidDialogCommandsReset:Disable()
	ZebRaidDialogCommandsGiveKarma:Disable()
	ZebRaidDialogCommandsAnnounce:Disable()
	ZebRaidDialogCommandsInviteRaid:Disable()
	ZebRaidDialogCommandsSync:Disable()
--	UIDropDownMenu_DisableDropDown(ZebRaidDialogRaidSelection)
	ZebRaidDialogCommandsUnlock:Enable()
end

function ZebRaid:UnlockUI()
	if self.state:GetRaidId() then
		ZebRaid.UiLockedDown = nil
		ZebRaidDialogCommandsAutoConfirm:Enable()
		ZebRaidDialogCommandsReset:Enable()
		ZebRaidDialogCommandsGiveKarma:Enable()
		ZebRaidDialogCommandsAnnounce:Enable()
		ZebRaidDialogCommandsInviteRaid:Enable()
		ZebRaidDialogCommandsSync:Enable()
--		UIDropDownMenu_EnableDropDown(ZebRaidDialogRaidSelection)
		ZebRaidDialogCommandsUnlock:Disable()
	end
end

function ZebRaid:OnUnlock()
	DEFAULT_CHAT_FRAME:AddMessage("DEBUG: OnUnlock")

	if not self.state:GetKarmaDb() then
		DEFAULT_CHAT_FRAME:AddMessage("ERROR: state is nil")
		-- FIXME: Print an error message somewhere
		return
	end

	self.state:SetUiMaster(self.state:GetKarmaDb(), PlayerName)

	self:UnlockUI()
	ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
end

function ZebRaid:OnHide()
	StartWasCalled = nil
	ZebRaid:RosterFinal()
end

function ZebRaid:StartInvite()
	if self.coInvite and coroutine.status(self.coInvite) ~= "dead" then
		DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Invite already in progress")
		return
	end
	self.coInvite = coroutine.create(self.DoInvites)
	if self.coInvite then
		local status, err = coroutine.resume(self.coInvite, self)
		if not status then
			DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Cannot start invites - " .. (err or "nil"))
		end
	else
		DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Cannot start invites")
	end
end

function ZebRaid:DoInvites()
	-- Periodic event to unlock the coroutine if it gets stuck
	local hTimer = self:ScheduleRepeatingTimer("PeriodicTimer", 1)
	-- Construct a list of members to invite
	local inviteList={}
	local inviteCount = 0
	for _, name in self.Confirmed:GetIterator() do
		if name ~= UnitName("player") and not self:IsPlayerInRaid(name) then
			table.insert(inviteList, {name=name})
			inviteCount = inviteCount + 1
		end
	end

	for _, name in self.Sitout:GetIterator() do
		if name ~= UnitName("player") and not self:IsPlayerInRaid(name) then
			table.insert(inviteList, {name=name})
			inviteCount = inviteCount + 1
		end
	end

	if inviteCount == 0 then return end

	local finished = nil
	while not finished do
		if UnitInParty("player") and
		   GetNumPartyMembers() > 0
		then
			ConvertToRaid()
			self:WaitForRaid()
		end

		if not UnitInRaid("player") then
			-- First, try to find someone who'll accept the invite, so that we can convert to raid
			local waitingAccept = 0

			for i, v in ipairs(inviteList) do
				-- Invite the next person
				if Guild:IsMemberOnline(v.name) then
					self:Debug("Inviting " .. v.name)
					InviteUnit(v.name)
					waitingAccept = waitingAccept + 1
				else
					inviteCount = inviteCount - 1
				end

				-- If we've already invited four people, and they haven't accepted yet, wait
				if waitingAccept == 4 or waitingAccept == inviteCount then

					local startTime = GetTime()
					while not ( UnitInParty("player") and
								GetNumPartyMembers() > 0 )
					do
						self:Debug("Unit is not in party. Waiting.")
						coroutine.yield()
						-- Wait up to 15 seconds
						if GetTime() - startTime > 15 then
							self:Debug("Waited too long. Inviting another.")
							waitingAccept = waitingAccept - 1
							break
						end
					end

					if UnitInParty("player") and
					   GetNumPartyMembers() > 0
					then
						self:Debug("Unit is in party. Converting to raid.")
						ConvertToRaid()
						self:WaitForRaid()
						if UnitInRaid("player") then
							self:Debug("Unit is in raid.")
							finished = true
							break
						else
							-- FIXME: This is quite simplistic, and may break.
							-- A better option would be to get an event on invite timeouts.
							-- See if it is possible
							waitingAccept = waitingAccept - 1
						end
					else
						-- FIXME: See above
						waitingAccept = waitingAccept - 1
					end
				end
			end
		else
			finished = true
		end
	end

	-- We should be in raid now. Invite everybody
	for i, v in ipairs(inviteList) do
		if not self:IsPlayerInRaid(v.name) then
			if (not Guild:HasMember(v.name) or
			    Guild:IsMemberOnline(v.name))
			then
				InviteUnit(v.name)
			end
		end
	end

	-- Remove the event handlers. We are done with them.
	self:CancelTimer(hTimer)
end

function ZebRaid:WaitForRaid()
	local start = GetTime()
	while not UnitInRaid("player") do
		coroutine.yield()
		-- Wait up to 20 seconds
		if GetTime() - start > 20 then break end
	end
end

-- A timer to ensure we can break out of otherwise infinite loops in the coroutine
function ZebRaid:PeriodicTimer()
	--self:Debug("ZebRaid:PeriodicTimer()")
	if self.coInvite and coroutine.status(self.coInvite) == "suspended" then
		coroutine.resume(self.coInvite)
	end
end

-- Used in the function below: the lists we check for people in our raid
-- Moved up here to reduce memory usage
local listsToScan = {
	"GuildList",
	"SignedUp",
	"Unsure",
	"Reserved"
}

-- Event handler: called when we detect changes on the party
function ZebRaid:RosterUpdated()
	self:Debug("RosterUpdated")

	-- Move every player in raid to confirmed if they are not in penalty or sitout
	if self.state:GetKarmaDb() then
		-- FIXME: Make a roster object to fit in with the rest of the code
		for name in self:GetRosterIterator() do
			assignment = self.state:GetAssignment(name)
			if assignment == "unassigned" or
				assignment == "unknown" or
				assignment == "reserved"
			then
				self.state:SetAssignment("confirmed")
			end
		end
	end

	self:ShowListMembers()

	if self.coInvite and coroutine.status(self.coInvite) == "suspended" then
		coroutine.resume(self.coInvite)
	end
end

-- Local variable to control debugging
local debugEnabled = false

-- Enable/Disable debugging
function ZebRaid:SetDebugging(enabled)
	debugEnabled = enabled
end

-- Print a debug statement
function ZebRaid:Debug(...)
	return debugEnabled and self:Print(date(), ": ", ...)
end

function ZebRaid:SetBossAndKarma(boss, karma)
	ZebRaidDialogBoss:SetText(boss)
	ZebRaidDialogKarma:SetText(tostring(karma))
	self:Start()
end

function ZebRaid:GiveBossKarma()
	-- If we can give karma ...
	if not Karma_Add_Player then
		DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_ADDON"])
		return
	end

	if not KarmaConfig["CURRENT RAID"] then
		DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DB"])
		return
	end

	-- Get the boss name and karma amount
	local boss = ZebRaidDialogBoss:GetText()
	local karma = ZebRaidDialogKarma:GetText()

	if not boss or boss == "" or
		not karma or karma == ""
	then
		DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DATA"])
		return
	end

	-- Give on time karma to all raid members.
	Karma_Add(karma .. " all " .. boss, "P")

	for pos, name in self.Sitout:GetIterator() do
		-- Only confirmed people who are in raid deserve online karma. :-)
--[[		if not self:IsPlayerInRaid(name) and
		   ( Guild:IsMemberOnline(name) or
		     self:IsAltOnline(name) )
		Just give everyone in sitout list the karma if they are not already in raid
]]--
		if not self:IsPlayerInRaid(name) then
			Karma_Add(karma .. " " .. name .. " " .. boss, "P")
		end
	end
end

if DBM then
	local DBMold = DBM.EndCombat
	local BossKarmaLookup = {
		["Anub'Rekhan"] = 5,
		["Faerlina"] = 5,
		["Maexxna"] = 5,
		["Gluth"] = 5,
		["Grobbulus"] = 5,
		["Patchwerk"] = 5,
		["Thaddius"] = 5,
		["Gothik"] = 5,
		["Horsemen"] = 5,
		["Razuvious"] = 5,
		["Heigan"] = 5,
		["Loatheb"] = 5,
		["Noth"] = 5,
		["Sapphiron"] = 5,
		["Kel'Thuzad"] = 10,
		["Archavon"] = 10,
		["Sartharion"] = 10,
		["Malygos"] = 10,
	}


	DBM.EndCombat = function (self, mod, wipe)
		if self.state:GetKarmaDb() then
			local difficulty = GetInstanceDifficulty()
			if (difficulty == 2 or difficulty == 4) and
				BossKarmaLookup[mod.id] and not wipe
			then
				ZebRaid:SetBossAndKarma(mod.id, BossKarmaLookup[mod.id])
			end
		end

		DBMold(self, mod, wipe)
	end
end
