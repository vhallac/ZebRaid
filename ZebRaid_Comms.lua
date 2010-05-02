local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)
local S = LibStub("AceSerializer-3.0")
-- If either serializer or locale is missing, blow up earlier.
if not L or not S then return end

local CommPrefix="ZebRaid5"

function ZebRaid:CommInit()
	ZebRaid:RegisterComm(CommPrefix)
end

function ZebRaid:CommFinal()
	ZebRaid:UnregisterComm(CommPrefix)
end

function ZebRaid:SendComm(distribution, target, ...)
	self:Debug("ZebRaid:SendComm(", distribution, ", ", target, ")")
	msgRaw = S:Serialize(...)
	self:SendCommMessage(CommPrefix, msgRaw, distribution, target)
end

function ZebRaid:BroadcastComm(...)
	self:SendComm("GUILD", nil, ...)
end

function ZebRaid:WhisperComm(target, ...)
	self:SendComm("WHISPER", target, ...)
end

function ZebRaid:OnCommReceived(prefix, msgRaw, distribution, sender)
	if prefix ~= CommPrefix then return end
	
	-- Ignore our own broadcasts
	if sender == GetUnitName("player") then return end

	local msg = {S:Deserialize(msgRaw)}
	if not msg[1] then
		DEFAULT_CHAT_FRAME:AddMessage("ZebRaid ERROR: Cannot unpack comms message")
		return
	end

	local handlerName = "On" .. msg[2]
	if self[handlerName] then
		self[handlerName](self, sender, select(3,unpack(msg)))
	else
		self:Debug("Unhandled command received: ", handlerName)
	end
end

-- Sent by the addon to guild when it starts. Used for advertising its presence,
-- and learning the other instances of the addon.
function ZebRaid:OnBROADCAST(sender)
	self:Debug("Received BROADCAST from " .. sender)

	-- TODO: Sync the known player roles
	if not ZebRaid.UiLockedDown then
		--[[
		self:SendCommMessage("GUILD", "I_IS_MASTER",
								ZebRaidState.KarmaDB, state.RaidID,
								state.RegisteredUsers,
								state.Lists)
		]]--
	end

	-- If the broadcasting person is a UI Master, assume he reloaded, and release
	self.state:RemoveUiMaster(sender)

	--self:SendCommMessage("WHISPER", sender, "REQUESTDATA")
	--self:SendCommMessage("WHISPER", sender, "ACKNOWLEDGE")
end

-- Sent from the addons receiving a BROADCAST to the sender of the BROADCAST.
-- We use it to learn their history.
function ZebRaid:OnACKNOWLEDGE(sender)
	--self:SendCommMessage("WHISPER", sender, "REQUESTDATA")
    self:Debug("Received ACKNOWLEDGE from " .. sender)
end

-- Sent by an instance to request the player data
function ZebRaid:OnREQUESTDATA(sender)
--[[
	local playerData = {}
	-- Filter the ZebRaidPlayerData, and send it
	-- We will avoid non-integer indexes to reduce data size
	-- Format: {name1, sitoutPos1, signedCount1, sitoutCount1, penaltyCount1,...}
	for dbName, dbData in pairs(ZebRaidPlayerData) do
		-- First entry is the KarmaDB name
		table.insert(playerData, dbName)
		local stats = {}
		for player, playerStats in pairs(dbData) do
			table.insert(stats, player)
			table.insert(stats, playerStats.sitoutPos)
		end
		table.insert(playerData, stats)
	end
	--]]
end

-- Sent by an instance to tell others that it is becoming the master now.
function ZebRaid.OnANNOUNCE_MASTER(sender, KarmaDB, RaidID, RegisteredUsers, Lists)
--[[ This requires a lot of rework due to lists. Ignore for now
	DEFAULT_CHAT_FRAME:AddMessage(sender .. " is now the master for " .. KarmaDB .. ".")
	if (ZebRaidState.KarmaDB == KarmaDB) then
		ZebRaid:LockUI()
	end
	ZebRaidState[KarmaDB].RaidID = RaidID
	ZebRaidState[KarmaDB].RegisteredUsers = RegisteredUsers
	ZebRaidState[KarmaDB].Lists = Lists

	self.state:SetUiMaster(KarmaDB, sender)

	if (ZebRaidState.KarmaDB == KarmaDB) then
		local state = ZebRaidState[KarmaDB]

		ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. state.RaidID)
		ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. sender)
		ZebRaid:ShowListMembers()
	end
--]]
end

function ZebRaid:OnADD_TO_LIST(sender, KarmaDB, listName, name)
--[[ Invalid command. Need assignments, not lists...
	self:Debug("Received ADD_TO_LIST(" .. listName .. ", " .. name .. ")")

	local state = ZebRaidState[KarmaDB]

	if state and state.Lists then
		local list = state.Lists[listName]

		if list then
			ZebRaid:AddToList(state, list, name)
		end
	end
	--]]
end

function ZebRaid:OnREMOVE_FROM_LIST(sender, KarmaDB, listName, nameOrPos)
--[[ Invalid command. Need assignments, not lists...
	self:Debug("Received REMOVE_FROM_LIST(" .. listName .. ", " .. nameOrPos .. ")")

	local state = ZebRaidState[KarmaDB]

	if state and state.Lists then
		local list = state.Lists[listName]

		if list then
			ZebRaid:RemoveFromList(state, list, nameOrPos)
		end
	end
	--]]
end

function ZebRaid:OnCLOSE_RAID(sender, KarmaDB)
--[[ Invalid command. We don't close raids anymore
	self:Debug("Received CLOSE_RAID(" .. KarmaDB .. ")")

	local state = ZebRaidState[KarmaDB]

	if state then
		ZebRaid:DoCloseRaid(state)
	end
	--]]
end
