ZebRaid = LibStub("AceAddon-3.0"):NewAddon("ZebRaid", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)
local Guild = LibStub("LibGuild-1.0")

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

-- The letters we use in the lists to indicate raid role
local RoleLetters = {
	melee = "M",
	tank = "T",
	healer = "H",
	ranged = "R",
	hybrid = "Y",
	unknown = "?"
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

ZebRaid.PlayerStats = {}
ZebRaid.UIMasters = {}
ZebRaidState = {}

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
	ZebRaidDialogCommandsCloseRaid:SetText(L["CLOSERAID"])
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
	-- Hide all player buttons
	--
	for i=1, MAX_NUM_BUTTONS do
		local button = getglobal("ZebRaidDialogButton" .. i)
		button:ClearAllPoints()
		button:Hide()
	end

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
	StaticPopupDialogs["ZEBRAID_CONFIRM_REMOTE_CLOSE"] = {
		text = L["CLOSECONFIRMATION"],
		button1 = "Yes",
		button2 = "No",
		OnAccept = function(data)
			ZebRaid:DoCloseRaid(data)
			self:BroadcastComm("CLOSE_RAID", ZebRaidState.KarmaDB)
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1
	}

end

function ZebRaid:OnEnable()
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
	-- i.e. when we have a DB selected, and the raid is not closed.
	if ZebRaidState.KarmaDB and ZebRaidState[ZebRaidState.KarmaDB] then
		if Karma_command then
			Karma_command("use " .. ZebRaidState.KarmaDB)
		end
	end

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

function ZebRaid:ParseLocalRaidData()
	for _,val in pairs(ZebRaid.Signups) do
		self:Debug("Value: " .. val)
		local name, status, role, note =
			select(3, val:find("^([^:]+):([^:]+):([^:]+):?(.*)"))

		local list = nil

		if status == "signed" then
			list = "SignedUp"
		elseif status == "unsure" then
			list = "Unsure"
		end

		if note == "" then
			note = nil
		end

		if Guild:HasMember(name) then
			-- If we didn't gkick the user since sign-up, add him to the RegisteredUsers table
			self.RegisteredUsers[name] = {
				status = status,
				list = list,
				role = role,
				note = note
			}

			if not ZebRaidPlayerData[name] then
				-- New players enter at the bottom of sitout lists
				-- list pos 0 is reserved for people who are chosen for this raid
				ZebRaidPlayerData[name] = {
					role = role,
					sitoutPos = 1
				}
			else
				-- Overwrite all roles with current ones
				ZebRaidPlayerData[name].role = role
			end
		end
	end
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

	if ZebRaidState.KarmaDB then
		if ZebRaidState[ZebRaidState.KarmaDB] and ZebRaidState[ZebRaidState.KarmaDB].RaidClosed then
			ZebRaidDialogReportMaster:SetText(L["REPORT_RAID_CLOSED"])
		elseif not self.UIMasters[ZebRaidState.KarmaDB] then
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
		elseif self.UIMasters[ZebRaidState.KarmaDB] == PlayerName then
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
		else
			ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. self.UIMasters[ZebRaidState.KarmaDB])
		end

		if not self.PlayerStats[ZebRaidState.KarmaDB] then
			self.PlayerStats[ZebRaidState.KarmaDB] = {}
		end
	else
		ZebRaidDialogReportMaster:SetText(L["REPORT_NO_DB"])
	end

	--
	-- If we are not the master or we do not know the master of a list,
	-- and if the DB's raid ID does not match our current raid ID, then
	-- remove the state for that DB.
	--
	for db, val in pairs(ZebRaidState) do
		if (type(ZebRaidState[db]) == "table") and
		   (not self.UIMasters[db]) and
		   (val.RaidID ~= self.RaidID)
		then
			self:Debug("Erasing db state " .. db)
			ZebRaidState[db] = nil
		end
	end

	if self:Count(self.KarmaList)==0 and KarmaList then
		-- Copy the Karma database names
		for db, val in pairs(KarmaList) do
			table.insert(self.KarmaList, db)
		end
	end

	--
	-- Parse the signup list
	--
	if ( not self.RegisteredUsers ) or
	   ( self:Count(self.RegisteredUsers) == 0 ) then
		self:ParseLocalRaidData()
	end

	if ZebRaidState.KarmaDB and
	   ZebRaidState[ZebRaidState.KarmaDB]
	then
		local state = ZebRaidState[ZebRaidState.KarmaDB]
		--
		-- Fill the lists out according to online and registered users
		--
		self:InitializeListContents(state)
	end

	-- Display the current setup
	local raidID = ZebRaid.RaidID
	if ZebRaidState.KarmaDB and
	   ZebRaidState[ZebRaidState.KarmaDB] and
	   ZebRaidState[ZebRaidState.KarmaDB].RaidID
	then
		raidID = ZebRaidState[ZebRaidState.KarmaDB].RaidID
	end

	ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidID)
	self:ShowListMembers()

	-- If there is an offline player in the Sitout list, ask their alts' tracker to respond
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

	StartWasCalled = true

	ZebRaidDialog:Show()
end

function ZebRaid:AddButtonToList(list, button)
	-- Place the button in its list
	button:ClearAllPoints()
	local slot = getglobal("ZebRaidDialogPanel" .. list.name ..
						   "Slot" .. list.freeSlot)
	if slot == nil then
		button:ClearAllPoints()
		button:Hide()
		return
   end
	button:SetPoint("TOP", slot)
	button:SetHitRectInsets(0, 0, 0, 0)
	button:SetFrameLevel(slot:GetFrameLevel() + 20)
	button:RegisterForDrag("LeftButton")
	button.inList = list
	list.freeSlot = list.freeSlot + 1
	button:Show()
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

function ZebRaid:PlayerOnDragStop(frame)
	self:Debug("PlayerOnDragStop")

	frame:SetFrameLevel(movingButtonLevel)
	frame:StopMovingOrSizing()

	if self.UiLockedDown then self:ShowListMembers(); return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	local selectedList = nil
	for list, _ in pairs(state.Lists) do
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

	local list
	if selectedList then
		list = state.Lists[selectedList]
	else
		list = frame.inList
	end

	-- Not signed up or unsigned => Cannot go to SignedUp, Unsure, Penalty, or
	--							  Sitout
	if not state.RegisteredUsers[frame.player] or
	   not state.RegisteredUsers[frame.player].list
	then
		if ( selectedList == "Penalty" or
			 selectedList == "Sitout" or
			 selectedList == "SignedUp" or
			 selectedList == "Unsure")
		then
			list = frame.inList
		end
	else
		-- Unsure => Cannot go to Penalty
		if ( selectedList == "Penalty" and
			 state.RegisteredUsers[frame.player].list == "Unsure")
		then
			list = frame.inList
		end

		-- SignedUp or Unsure cannot go back to guild
		if ( state.RegisteredUsers[frame.player] and
			 state.RegisteredUsers[frame.player].list and
			 selectedList == "GuildList" )
		then
			list = frame.inList
		end

		-- SignedUp and Unsure cannot go each other
		if ( ( selectedList == "SignedUp" or
			   selectedList == "Unsure" ) and
			   state.RegisteredUsers[frame.player].list ~= selectedList)
		then
			list = frame.inList
		end
	end

	if list ~= frame.inList then
		-- Remove from the old one
		self:RemoveFromList(state, frame.inList, frame.player)
		self:BroadcastComm("REMOVE_FROM_LIST", ZebRaidState.KarmaDB, frame.inList.name, frame.player)

		-- Insert to new list
		-- If player is offline, and the target list is online list, then
		-- do not add to the target list.
		if list.name ~= "GuildList" or
		   Guild:IsMemberOnline(frame.player)
		then
			self:AddToList(state, list, frame.player)
			self:BroadcastComm("ADD_TO_LIST", ZebRaidState.KarmaDB, list.name, frame.player)
		end

	end

	DraggingPlayer = nil

	self:ShowListMembers()
end

function ZebRaid:PlayerOnDoubleClick(frame, button)
	self:Debug("ZebRaid:OnDoubleClick")

	if self.UiLockedDown then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]
	local list = ZebRaid:FindTargetList(frame.inList, frame.player)

	if list then
		-- Remove from the old one
		self:RemoveFromList(state, frame.inList, frame.player)
		self:BroadcastComm("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, frame.inList.name, frame.player)

		-- Insert to new list
		-- If player is offline, and the target list is online list, then
		-- do not add to the target list.
		if list.name ~= "GuildList" or
		   Guild:IsMemberOnline(frame.player)
		then
			self:AddToList(state, list, frame.player)
			self:BroadcastComm("ADD_TO_LIST", ZebRaidState.KarmaDB, list.name, frame.player)
		end

		self:ShowListMembers()
	end
end

function ZebRaid:MemberConnected(name)
	self:Debug("Got member: " .. name)

	-- If the player has ever signed up with this name, set it to be the main character
	self:Tracker_SetPlayerMain(name)

	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	if Guild:GetLevel(name) ~= 80 then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	local found = nil

	for listName, list in pairs(state.Lists) do
		for i, val in pairs(list.members) do
			if val == name then
				found = true
			end
		end
	end

	if not found then
		self:AddToList(state, state.Lists["GuildList"], name)
		-- FIXME: Should be unneeded. Double check.
		-- self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, "GuildList", name)
	end

	NeedRecalculateAfterUpdate = true

	-- Since this instance is the current master, let the alt know where to report status
	self:Tracker_SetTracker(name)
end

function ZebRaid:MemberDisconnected(name)
	if not StartWasCalled then return end

	if self.UiLockedDown then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	self:RemoveFromList(state, state.Lists["GuildList"], name)
	-- FIXME: Should not be necessary. Double check
	-- self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, "GuildList", name)

	-- We either removed a user, or need to update the background color
	-- of a user. Update it.
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

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	local changed = nil

	for listName, list in pairs(state.Lists) do
		for i, val in pairs(list.members) do
			if val == name then
				self:RemoveFromList(state, list, i)
				--FIXME: Should be unnecessary. Double check
				--self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, list.name, i)

				changed = true
				break
			end
		end
	end

	if changed then
		NeedRecalculateAfterUpdate = true
	end
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
	if not DraggingPlayer and (GetTime() - LastUpdateTime > 1) then
		self:ShowListMembers()
		LastUpdateTime = GetTime()
	end
end

function ZebRaid:AutoConfirm()

	if self.UiLockedDown then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	local listFrom = state.Lists["SignedUp"]

	local movePos = {}

	local pos = 1
	local count = self:Count(listFrom.members)
	self:Debug("pos: " .. pos .. "listCount: " .. count)
	while pos <= count do
		self:Debug("pos: " .. pos .. "listCount: " .. self:Count(listFrom.members))
		local name = listFrom.members[pos]

		if (Guild:IsMemberOnline(name)) then
			local listTo = self:FindTargetList(listFrom, name)

			if listTo then
				self:RemoveFromList(state, listFrom, pos)
				self:BroadcastComm("REMOVE_FROM_LIST", ZebRaidState.KarmaDB, listFrom.name, pos)
				self:AddToList(state, listTo, name)
				self:BroadcastComm("ADD_TO_LIST", ZebRaidState.KarmaDB, listTo.name, name)
			end
			count = count - 1
		else
			pos = pos + 1
		end
	end
	self:ShowListMembers()
end

function ZebRaid:Announce()
	if self.UiLockedDown then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	local list = state.Lists["Sitout"]

	local message = ""

	if self:Count(list.members) > 0 then
		for pos, name in pairs(list.members) do
			message = message .. name
			if pos ~= self:Count(list.members) then
				message = message .. ", "
			else
				message = message .. "."
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
end

function ZebRaid:GiveKarma()
	if self.UiLockedDown then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

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

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	-- Give on time karma to all Confirmed and Sitout users.
	for pos, name in pairs(state.Lists["Confirmed"].members) do
		-- Only confirmed people who are in raid deserve online karma. :-)
		if self:IsPlayerInRaid(name) then
			self:Debug("Giving on time karma to " .. name)
			-- Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P")
		end
	end

	for pos, name in pairs(state.Lists["Sitout"].members) do
		Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P")
	end
end

function ZebRaid:CloseRaid()
	if self.UiLockedDown then return end

	if not ZebRaidState.KarmaDB then return end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

	if state.RaidClosed then return end

	-- Make sure users really wants to close someone else's raid.
	if state.RaidID ~= self.RaidID then
		-- DoCloseRaid() will be called by the dialog "yes" handler.
		local dialog = StaticPopup_Show("ZEBRAID_CONFIRM_REMOTE_CLOSE", sender, raidListStr)
		if dialog then
			dialog.data = state
		end
	else
		self:DoCloseRaid(state)
		self:BroadcastComm("CLOSE_RAID", ZebRaidState.KarmaDB)
	end
end

function ZebRaid:DoCloseRaid(state)
	-- TODO: Remove the function ... again
	state.RaidClosed = true
	state.RaidCloseTime = self:GetRaidDate()

	local playerStats = self.PlayerStats[karmaDB]

	local minSitoutPos = 1
	local maxSitoutPos = 1
	local sitoutPosAdjust = 0
	for _, stats in pairs(ZebRaidPlayerData) do
		if stats.sitoutPos < minSitoutPos then
			minSitoutPos = stats.sitoutPos
		end
		if stats.sitoutPos > maxSitoutPos then
			maxSitoutPos = stats.sitoutPos
		end
	end

	-- Move sitout to beginning of list
	for _, name in pairs(state.Lists["Sitout"].members) do
		local stat = ZebRaidPlayerData[name]
		if stat then -- Unnecessary, but no harm in checking
			stat.sitoutPos = minSitoutPos - 1
			stat.sitoutCount = (stat.sitoutCount or 0) + 1
			if not stat.sitoutDates then
				stat.sitoutDates = {}
			end
			table.insert(stat.sitoutDates, state.RaidCloseTime)
			-- The lines below ensure unique sitoutPos values
			-- Comment it out if sitoutPos for the same raid sitouts are equal
			-- also add sitoutPosAdjust = 1
			-- minSitoutPos = stat.sitoutPos
			-- sitoutPosAdjust = sitoutPosAdjust + 1
			sitoutPosAdjust = 1
		end
	end

	-- Move penalties to the top of the list
	for _, name in pairs(state.Lists["Penalty"].members) do
		local stat = ZebRaidPlayerData[name]
		if stat then -- Unnecessary, but no harm in checking
			stat.sitoutPos = maxSitoutPos + 1
			stat.penaltyCount = (stat.penaltyCount or 0) + 1
			if not stat.penaltyDates then
				stat.penaltyDates = {}
			end
			table.insert(stat.penaltyDates, state.RaidCloseTime)
			-- The line below ensures unique sitoutPos values
			-- Comment it out if sitoutPos for the same raid sitouts are equal
			-- maxSitoutPos = stat.sitoutPos
		end
	end

	-- Adjust sitoutPos so that the minimum is 1 again
	for _, stats in pairs(ZebRaidPlayerData) do
		stats.sitoutPos = stats.sitoutPos + sitoutPosAdjust
	end

	-- And finally record the people who has signed up
	for name, val in pairs(state.RegisteredUsers) do
		local stat = ZebRaidPlayerData[name]
		if stat then -- Unnecessary, but no harm in checking
			if val.status ~= "unsigned" then
				stat.signedCount = (stat.signedCount or 0) + 1
			end
		end
	end
end

function ZebRaid:InitializeListContents(state)
	if not state.Lists then
		state.Lists = {}

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

			list = val.list

			if list then
				self:AddToList(state, state.Lists[list], name)
			end
		end
	end

	-- First, empty the guild list
	table.wipe(state.Lists["GuildList"].members)

	-- Populate the guild list with online users
	-- They need to be lvl 80, and not signed up yet.
	for name in Guild:GetIterator("NAME", false) do
		if (Guild:GetLevel(name) == 80 and
			not (state.RegisteredUsers[name] and
				 state.RegisteredUsers[name].list) and
			not (self:FindInTable(state.Lists["Confirmed"].members, name) or
				 self:FindInTable(state.Lists["Reserved"].members, name)) )
		then
			-- If online player has ever signed up, tell them that they are main chars
			if ZebRaidPlayerData[name] then
				self:Tracker_SetPlayerMain(name)
			end
			self:AddToList(state, state.Lists["GuildList"], name)
		end
	end
end

function ZebRaid:Reset()
	self:Debug("ZebRaid:Reset")

	if self.UiLockedDown then return end
	if not self:IsEnabled() then return end

	local state = ZebRaidState.KarmaDB and ZebRaidState[ZebRaidState.KarmaDB]

	if state then
		self:Debug("resetting")
		state.Lists = nil

		for name, stat in pairs(state.RegisteredUsers) do
			if stat.status == "signed" then
				stat.list = "SignedUp"
			elseif stat.status == "unsure" then
				stat.list = "Unsure"
			end
		end

		self:InitializeListContents(state)
		--[[
		self:BroadcastComm("ANNOUNCE_MASTER",
							 ZebRaidState.KarmaDB, state.RaidID,
							 state.RegisteredUsers,
							 state.Lists)
		]]--
		self:ShowListMembers()
	else
		self:Debug("No state")
	end
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
		if name == ZebRaidState.KarmaDB then
			UIDropDownMenu_SetSelectedValue(ZebRaidDialogRaidSelection, pos)
		end
	end
end

function ZebRaid:RaidSelection_OnClick()
	self:Debug("ZebRaid:RaidSelection_OnClick: " .. this:GetText() .. ", " .. this.value)

	UIDropDownMenu_SetSelectedValue(this.owner, this.value)
	local karmaDB=this:GetText()
	ZebRaidState.KarmaDB = karmaDB
	if Karma_command then
		Karma_command("use " .. karmaDB)
	end

	if not ZebRaidState[karmaDB] then
		ZebRaidState[karmaDB] = {}
	end

	local state = ZebRaidState[karmaDB]

	if not self.PlayerStats then
		self.PlayerStats = {}
	end

	if not self.PlayerStats[karmaDB] then
		self.PlayerStats[karmaDB] = {}
	end

	if ( not state.RegisteredUsers ) or
	   ( self:Count(state.RegisteredUsers) == 0 )
	then
		self:Debug("Updating registered users for " .. karmaDB)
		state.RaidID = self.RaidID
		state.RegisteredUsers = self.RegisteredUsers
		self:InitializeListContents(state)
	end

	-- Recalculate the Guild list: all online members that are not in other lists go to guild list.


	-- Display the current setup
	self:ShowListMembers()

	local raidId = state.RaidID

	if not self.UIMasters[karmaDB] then
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
		self:LockUI()
	elseif (self.UIMasters[karmaDB] == PlayerName) then
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
		self:UnlockUI()
	else
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. self.UIMasters[karmaDB])
		self:LockUI()
	end

	ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. state.RaidID)
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

-- Find a list position in the list members where a new player should be inserted
-- according to its sitoutPos value. The list must already be sorted by the sitoutInsertPos
function ZebRaid:FindSitoutInsertPos(list, name)
	--local playerSitoutPos = self:GetPlayerSitoutPos(name)
	local playerSitoutCount = ZebRaidPlayerData[name] and ZebRaidPlayerData[name].sitoutCount or 0
	local playerLastSitoutDate = self:GetLastSitoutDate(name)
	local playerLastPenaltyDate = self:GetLastPenaltyDate(name)
	local playerHasPenalty = playerLastPenaltyDate > playerLastSitoutDate
	local playerRole = RoleLetters[self:GetPlayerRole(name)] or "X"
	local insertPos = nil
	local curLastSitoutDate, curRole
	local curLastPenaltyDate, curHasPenalty
	for pos, val in ipairs(list.members) do
		curSitoutCount = ZebRaidPlayerData[val] and ZebRaidPlayerData[val].sitoutCount or 0
		curLastSitoutDate = self:GetLastSitoutDate(val)
		curLastPenaltyDate = self:GetLastPenaltyDate(val)
		curHasPenalty = curLastPenaltyDate > curLastSitoutDate
		curRole = RoleLetters[self:GetPlayerRole(val)] or "X"
		if playerRole < curRole or
		   (playerRole == curRole and playerHasPenalty) or
		   (playerRole == curRole and playerLastSitoutDate < curLastSitoutDate and not curHasPenalty) or
		   (playerRole == curRole and playerLastSitoutDate == curLastSitoutDate and playerSitoutCount < curSitoutCount and not curHasPenalty)
		then
			insertPos = pos
			break
		end
	end

	return insertPos
end

local EmptyTable = {}
function ZebRaid:GetSitoutDates(name)
	return ZebRaidPlayerData[name] and ZebRaidPlayerData[name].sitoutDates or EmptyTable;
end

function ZebRaid:GetLastSitoutDate(name)
	local dates = self:GetSitoutDates(name)
	return dates[#dates] or "01/01/09"
end

function ZebRaid:GetPenaltyDates(name)
	return ZebRaidPlayerData[name] and ZebRaidPlayerData[name].penaltyDates or EmptyTable;
end

function ZebRaid:GetLastPenaltyDate(name)
	local dates = self:GetPenaltyDates(name)
	return dates[#dates] or "01/01/09"
end

function ZebRaid:GetRaidDate()
	local raidId = ZebRaidState[ZebRaidState.KarmaDB].RaidID
	_,_,d,m,y=string.find(raidId, ".*_(%d+).(%d+).20(%d+)")
	return string.format("%02d/%02d/%02d",d,m,y)
end

function ZebRaid:AddSitout(name)
	-- TODO: Extract date from RaidID and reformat
	local curDate = self:GetRaidDate()
	local stat = ZebRaidPlayerData[name]
	local lastSitout = self:GetLastSitoutDate(name)
	if stat and curDate ~= lastSitout then -- This should always be true
		if not stat.sitoutDates then
			stat.sitoutDates = {}
		end
		table.insert(stat.sitoutDates, curDate)
		stat.sitoutCount = (stat.sitoutCount or 0)+ 1
	end
end

function ZebRaid:RemoveSitout(name)
	local curDate = self:GetRaidDate()
	local stat = ZebRaidPlayerData[name]
	local lastSitout = self:GetLastSitoutDate(name)
	if stat and lastSitout == curDate then -- This should always be true
		if stat.sitoutDates then -- Ditto
			table.remove(stat.sitoutDates, #stat.sitoutDates)
			if #stat.sitoutDates == 0 then
				stat.sitoutDates = nil
			end
		end
		stat.sitoutCount = stat.sitoutCount - 1
	end
end

function ZebRaid:AddPenalty(name)
	local curDate = self:GetRaidDate()
	local stat = ZebRaidPlayerData[name]
	local lastPenalty = self:GetLastPenaltyDate(name)
	if stat and lastPenalty ~= curDate then -- This should always be true
		if not stat.penaltyDates then
			stat.penaltyDates = {}
		end
		table.insert(stat.penaltyDates, curDate)
		stat.penaltyCount = (stat.penaltyCount or 0) + 1
	end
end

function ZebRaid:RemovePenalty(name)
	local curDate = self:GetRaidDate()
	local stat = ZebRaidPlayerData[name]
	local lastPenalty = self:GetLastPenaltyDate(name)
	if stat and lastPenalty == curDate then -- This should always be true
		if stat.penaltyDates then -- Ditto
			table.remove(stat.penaltyDates, #stat.penaltyDates)
			if #stat.penaltyDates == 0 then
				stat.penaltyDates = nil
			end
		end
		stat.penaltyCount = stat.penaltyCount - 1
	end
end

function ZebRaid:ShowListMembers()
	local buttonNo = 1
	local confirmedCounts = {
		["melee"] = 0,
		["ranged"] = 0,
		["healer"] = 0,
		["tank"] = 0,
		["hybrid"] = 0,
		["unknown"] = 0
	}
	local totalCounts = {
		["melee"] = 0,
		["ranged"] = 0,
		["healer"] = 0,
		["tank"] = 0,
		["hybrid"] = 0,
		["unknown"] = 0
	}

	-- If we haven't selected a list, or (for some reason) the
	-- selection has no state, then do not attempt to draw anything.
	if not ZebRaidState.KarmaDB or
	   not ZebRaidState[ZebRaidState.KarmaDB]
	then
		self:UpdateCounts("ZebRaidDialogConfirmedStats", confirmedCounts)
		self:UpdateCounts("ZebRaidDialogTotalStats", totalCounts)
		ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] .. " (0)")
		ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] .. " (0)")
		ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] .. " (0)")
		ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] .. " (0)")
		ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] .. " (0)")
		ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] .. " (0)")
		ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] .. " (0)")
		return
	end

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] ..
		" (" .. table.getn(state.Lists["SignedUp"].members) .. ")")
	ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] ..
		" (" .. table.getn(state.Lists["Unsure"].members) .. ")")
	ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] ..
		" (" .. table.getn(state.Lists["Confirmed"].members) .. ")")
	ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] ..
		" (" .. table.getn(state.Lists["Reserved"].members) .. ")")
	ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] ..
		" (" .. table.getn(state.Lists["GuildList"].members) .. ")")
	ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] ..
		" (" .. table.getn(state.Lists["Penalty"].members) .. ")")
	ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] ..
		" (" .. table.getn(state.Lists["Sitout"].members) .. ")")


	for listName, list in pairs(state.Lists) do
		if (buttonNo > MAX_NUM_BUTTONS) then
			-- Too many players. We cannot show them all.
			-- Silently ignore the problem.
			break
		end

		list.freeSlot = 1

		for _, name in pairs(list.members) do
			local button = getglobal("ZebRaidDialogButton" .. buttonNo)

			self:SetButtonRole(button, list, name)
			self:SetButtonLabel(button, list, name)
			self:SetButtonColor(button, list, name)
			self:SetButtonTooltip(button, list, name)

			button.player = name
			self:AddButtonToList(list, button)

			buttonNo = buttonNo + 1

			if list.name == "Confirmed" then
				local role = self:GetPlayerRole(name)
				confirmedCounts[role] = confirmedCounts[role] + 1
			elseif list.name == "Reserved" then
				local role = self:GetPlayerRole(name)
				totalCounts[role] = totalCounts[role] + 1
			end
		end
	end

	--
	-- Hide remaining player buttons
	--
	for i=buttonNo, MAX_NUM_BUTTONS do
		local button = getglobal("ZebRaidDialogButton" .. i)
		button:ClearAllPoints()
		button:Hide()
	end

	for idx, val in pairs(totalCounts) do
		totalCounts[idx] = totalCounts[idx] + confirmedCounts[idx]
	end

	self:UpdateCounts("ZebRaidDialogConfirmedStats", confirmedCounts)
	self:UpdateCounts("ZebRaidDialogTotalStats", totalCounts)
end

function ZebRaid:GetPlayerRole(name)
	local role = "unknown"
	local state = ZebRaidState.KarmaDB and ZebRaidState[ZebRaidState.KarmaDB]

	if state then
		local data = ZebRaidPlayerData[name]
		if not data then
			data = state.RegisteredUsers[name]
		end

		if data then
			role = data.role
		end
	end

	return role
end

function ZebRaid:SetButtonRole(button, list, name)
	local buttonRole = getglobal(button:GetName() .. "Role")
	local stats = nil
	local prefix = ""
	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if self.PlayerStats[ZebRaidState.KarmaDB] then
		stats = self.PlayerStats[ZebRaidState.KarmaDB][name]
	end

	if state.RegisteredUsers[name] then
		local data = state.RegisteredUsers[name]
		-- Display the role of user on button only if we know about the user
		-- FIXME: Need a registry of users/roles

		if data.note then
			prefix = prefix .. "*"
		end
	end

	buttonRole:SetText(prefix .. (RoleLetters[self:GetPlayerRole(name)] or "X") )

	buttonRole:SetTextColor(0.8, 0.8, 0)
end

function ZebRaid:SetButtonLabel(button, list, name)
	local buttonLabel = getglobal(button:GetName() .. "Label")
	local state = ZebRaidState[ZebRaidState.KarmaDB]
	local stats = nil

	if self.PlayerStats[ZebRaidState.KarmaDB] then
		stats = self.PlayerStats[ZebRaidState.KarmaDB][name]
	end

	-- Put a * before the name if there is a note.
	-- Put a x before the name if the user has unsigned from the raid
	local prefix = ""
	if state.RegisteredUsers[name] then
		if state.RegisteredUsers[name].status == "unsigned" then
			prefix = prefix .. "x"
		end
	end

	buttonLabel:SetText(prefix .. name)
	buttonLabel:SetTextColor(Guild:GetClassColor(name))
end

function ZebRaid:SetButtonColor(button, list, name)
	local buttonColor = getglobal(button:GetName() .. "Color")
	if Guild:IsMemberOnline(name) then
		if list.name == "Confirmed" and
		   self:IsPlayerInRaid(name)
		then
			-- Confirmed and in raid player background color
			buttonColor:SetTexture(0.1, 0.3, 0.1)
		else
			-- Online player background color
			buttonColor:SetTexture(0.05, 0.05, 0.05)
		end
	else
		if list.name == "Confirmed" and
		   self:IsPlayerInRaid(name)
		then
			-- Offline: Confirmed and in raid player background color
			buttonColor:SetTexture(0.2, 0.2, 0.1)
		elseif self:Tracker_IsAltOnline(name) then
			buttonColor:SetTexture(0.1, 0.1, 0.2)
		else
			-- Offline player background color
			buttonColor:SetTexture(0.2, 0.1, 0.1)
		end
	end
end

function ZebRaid:SetButtonTooltip(button, list, name)
	local state = ZebRaidState[ZebRaidState.KarmaDB]

	-- Add the guild info to tooltip
	button.tooltipDblLine = {
		left = name,
		right = Guild:GetClass(name)
	}

	button.tooltipText = "Rank: " .. (Guild:GetRank(name) or "not in guild") .. "\n"
	if Guild:GetNote(name) then
		button.tooltipText = button.tooltipText ..
							 Guild:GetNote(name) .. "\n\n"
	else
		button.tooltipText = button.tooltipText .. "\n"
	end

	if not Guild:IsMemberOnline(name) then
		if self:Tracker_IsAltOnline(name) then
			button.tooltipText = button.tooltipText ..
			                     "|cffff0000" .. L["ALT_ONLINE"] ..
			                     ": " .. self:Tracker_GetCurrentAlt(name) ..
			                     "|r\n\n"
		else
			button.tooltipText = button.tooltipText ..
								 "|cffff0000" .. L["PLAYER_OFFLINE"] .. "|r\n\n"
		end
	end

	if state.RegisteredUsers[name] then
		local data = state.RegisteredUsers[name]

		-- Put a note on unsigned users
		if data.status == "unsigned" then
			button.tooltipText = button.tooltipText ..
								 "|cffff0000" .. L["PLAYER_UNSIGNED"] .. "|r\n\n"
		end

		if data.note then
			button.tooltipText = button.tooltipText .. "\n"
			button.tooltipText = button.tooltipText ..
								 "|cffffff00Note: " .. data.note .. "|r\n"
		end
	end

	-- Add sitout/penalty information to tooltip
	local stats = ZebRaidPlayerData[name]

	if stats then
		button.tooltipText = button.tooltipText ..
							"|c9f3fff00" .. L["SIGNSTATS"] .. "|r: " ..
							(stats.signedCount or 0) .. "/" ..
							(stats.sitoutCount or 0) .. "/" ..
							(stats.penaltyCount or 0) .. "\n"
	end

	local sitoutDates = self:GetSitoutDates(name)
	for _,v in ipairs(sitoutDates) do
		button.tooltipText = button.tooltipText ..
							"|c7f1fcf00" .. v .. "|r\n"
	end
	local penaltyDates = self:GetPenaltyDates(name)
	for _,v in ipairs(penaltyDates) do
		button.tooltipText = button.tooltipText ..
							"|cdf1f1f00" .. v .. "|r\n"
	end
end

function ZebRaid:UpdateCounts(panelName, counts)
	getglobal(panelName .. "Tank"):SetText(L["TANK"] .. ": " ..
											   counts["tank"])
	getglobal(panelName .. "Melee"):SetText(L["MELEE"] .. ": " ..
											 counts["melee"])
	getglobal(panelName .. "Healer"):SetText(L["HEALER"] .. ": " ..
											   counts["healer"])
	getglobal(panelName .. "Ranged"):SetText(L["RANGED"] .. ": " ..
											 counts["ranged"])
	getglobal(panelName .. "Total"):SetText(L["TOTAL"]..": " ..
											counts["tank"] +
											counts["melee"] +
											counts["healer"] +
											counts["ranged"])
end

function ZebRaid:LockUI()
	ZebRaid.UiLockedDown = true
	ZebRaidDialogCommandsAutoConfirm:Disable()
	ZebRaidDialogCommandsReset:Disable()
	ZebRaidDialogCommandsGiveKarma:Disable()
	ZebRaidDialogCommandsAnnounce:Disable()
	ZebRaidDialogCommandsCloseRaid:Disable()
	ZebRaidDialogCommandsInviteRaid:Disable()
	ZebRaidDialogCommandsSync:Disable()
--	UIDropDownMenu_DisableDropDown(ZebRaidDialogRaidSelection)
	ZebRaidDialogCommandsUnlock:Enable()
end

function ZebRaid:UnlockUI()
	local state = ZebRaidState.KarmaDB and ZebRaidState[ZebRaidState.KarmaDB]
	if state and not state.RaidClosed then
		ZebRaid.UiLockedDown = nil
		ZebRaidDialogCommandsAutoConfirm:Enable()
		ZebRaidDialogCommandsReset:Enable()
		ZebRaidDialogCommandsGiveKarma:Enable()
		ZebRaidDialogCommandsAnnounce:Enable()
		ZebRaidDialogCommandsCloseRaid:Enable()
		ZebRaidDialogCommandsInviteRaid:Enable()
		ZebRaidDialogCommandsSync:Enable()
--		UIDropDownMenu_EnableDropDown(ZebRaidDialogRaidSelection)
		ZebRaidDialogCommandsUnlock:Disable()
	end
end

function ZebRaid:OnUnlock()
	DEFAULT_CHAT_FRAME:AddMessage("DEBUG: OnUnlock")
	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state then
		DEFAULT_CHAT_FRAME:AddMessage("ERROR: state is nil")
		-- FIXME: Print an error message somewhere
		return
	end

	self.UIMasters[ZebRaidState.KarmaDB] = PlayerName

	--[[
	self:BroadcastComm("ANNOUNCE_MASTER",
							ZebRaidState.KarmaDB, state.RaidID,
							state.RegisteredUsers,
							state.Lists)
	]]--
	DEFAULT_CHAT_FRAME:AddMessage("DEBUG: sent comm msg")
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
	local state = ZebRaidState[ZebRaidState.KarmaDB]
	local inviteList={}
	local inviteCount = 0
	for _, name in pairs(state.Lists["Confirmed"].members) do
		if name ~= UnitName("player") and not self:IsPlayerInRaid(name) then
			table.insert(inviteList, {name=name})
			inviteCount = inviteCount + 1
		end
	end

	for _, name in pairs(state.Lists["Sitout"].members) do
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

	-- Check the unsigned, signed and unsure lists for people in raid.
	-- When you find them, move them to "confirmed".
	local state = ZebRaidState[ZebRaidState.KarmaDB]
	if state then
		local playersToMove = {}

		for _, listName in pairs(listsToScan) do
			for pos, name in pairs(state.Lists[listName].members) do
				if self:IsPlayerInRaid(name) then
					self:Debug("Moving " .. name .. " from " .. listName .. "to Confirmed")
					table.insert(playersToMove, {list = listName, pos = pos, name = name})
				end
			end
		end

		local confirmedList = state.Lists["Confirmed"]
		for _, data in pairs(playersToMove) do
			local fromList = state.Lists[data.list]
			local fromPos = data.pos
			self:RemoveFromList(state, fromList, fromPos)
			self:BroadcastComm("REMOVE_FROM_LIST", ZebRaidState.KarmaDB, data.list, fromPos)
			self:AddToList(state, confirmedList, data.name)
			self:BroadcastComm("ADD_TO_LIST", ZebRaidState.KarmaDB, "Confirmed", data.name)
		end
	end

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

	local state = ZebRaidState[ZebRaidState.KarmaDB]

	if not state or not state.Lists then return end

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

	for pos, name in pairs(state.Lists["Sitout"].members) do
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
		if ZebRaidState.KarmaDB and GetCurrentDungeonDifficulty() == 2 and BossKarmaLookup[mod.id] and not wipe then
			ZebRaid:SetBossAndKarma(mod.id, BossKarmaLookup[mod.id])
		end

		DBMold(self, mod,wipe)
	end
end
