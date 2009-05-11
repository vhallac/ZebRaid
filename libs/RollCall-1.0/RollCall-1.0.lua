--[[
Name: RollCall-1.0
Revision: $Rev: 71175 $
Author: Cameron Kenneth Knight (ckknight@gmail.com)
Website: http://wiki.wowace.com/index.php/RollCall-1.0
Documentation: http://wiki.wowace.com/index.php/RollCall-1.0
SVN: svn://svn.wowace.com/wowace/trunk/RollCall-1.0/RollCall-1.0
Description: A library to provide an easy way to get information about guild members.
Dependencies: AceLibrary, AceOO-2.0, AceEvent-2.0, Babble-Zone-2.2 (optional),
				Babble-Class-2.2 (optional)
License: LGPL v2.1
]]

local MAJOR_VERSION = "RollCall-1.0"
local MINOR_VERSION = "$Revision: 71175 $"

-- This ensures the code is only executed if the libary doesn't already exist, or is a newer version
if not AceLibrary then error(MAJOR_VERSION .. " requires AceLibrary.") end
if not AceLibrary:IsNewVersion(MAJOR_VERSION, MINOR_VERSION) then return end

if not AceLibrary:HasInstance("AceOO-2.0") then error(MAJOR_VERSION .. " requires AceOO-2.0.") end
if not AceLibrary:HasInstance("AceEvent-2.0") then error(MAJOR_VERSION .. " requires AceEvent-2.0.") end

local AceEvent = AceLibrary:GetInstance("AceEvent-2.0")
local BZ, BC

local RollCall = {}

local IsInGuild = IsInGuild
local GuildRoster = GuildRoster
local select = select
local next = next

local new, del
do
	local cache = {}
	function new(...)
		local t = next(cache)
		if t then
			cache[t] = nil
			for i = 1, select('#', ...) do
				t[i] = select(i, ...)
			end
			return t
		else
			return { ... }
		end
	end
	
	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		cache[t] = true
		return nil
	end
end

local playersOnline = {}
local playerOfflineTimes = {}
local playerRanks = {}
local playerRankIndexes = {}
local playerLevels = {}
local playerClasses = {}
local playerZones = {}
local playerStatuses = {}
local playerNotes = {}
local playerOfficerNotes = {}
local numPlayersOnline = 0
local numPlayersTotal = 0
local guildLeader = nil

function RollCall:PLAYER_GUILD_UPDATE(arg1)
	if arg1 and arg1 ~= "player" then return end
	
	if IsInGuild() then
		if not self:IsBucketEventRegistered("GUILD_ROSTER_UPDATE") then
			self:ScheduleEvent("RollCall10-GuildRoster", GuildRoster, 15)
			self:RegisterBucketEvent("GUILD_ROSTER_UPDATE", 1)
		end
		GuildRoster()
		self:TriggerEvent("RollCall10_Joined")
	else
		if self:IsBucketEventRegistered("GUILD_ROSTER_UPDATE") then
			self:CancelScheduledEvent("RollCall10-GuildRoster")
			self:UnregisterBucketEvent("GUILD_ROSTER_UPDATE")
		end
		self:TriggerEvent("RollCall10_Left")
		
		RollCall:GUILD_ROSTER_UPDATE()
	end
end

local tmp, tmp2 = {}, {}
function RollCall:GUILD_ROSTER_UPDATE()
	if IsInGuild() then
		playersOnline, tmp = tmp, playersOnline
		playerLevels, tmp2 = tmp2, playerLevels
		numPlayersOnline = 0
		numPlayersTotal = GetNumGuildMembers(true)
		
		local name, rank, rankIndex, level, class, zone, note, officernote, online, status
		local yearsOffline, monthsOffline, daysOffline, hoursOffline, secondsOffline
		for i = 1, numPlayersTotal do
			name, rank, rankIndex, level, class, zone, note, officernote, online, status = GetGuildRosterInfo(i)
			yearsOffline, monthsOffline, daysOffline, hoursOffline = GetGuildRosterLastOnline(i)
			if yearsOffline then
				secondsOffline = hoursOffline * 60 * 60
				secondsOffline = secondsOffline + daysOffline * 24 * 60 * 60
				secondsOffline = secondsOffline + monthsOffline * 30 * 24 * 60 * 60
				secondsOffline = secondsOffline + yearsOffline * 365 * 24 * 60 * 60
			else
				secondsOffline = nil
			end
			if status == "" then
				status = nil
			end
			if note == "" then
				note = nil
			end
			if officernote == "" then
				officernote = nil
			end
			local add, connect
			if name then
				playerRanks[name] = rank or UNKNOWN
				playerRankIndexes[name] = rankIndex or -1
				playerLevels[name] = level or -1
				playerClasses[name] = class or UNKNOWN
				playerZones[name] = zone or UNKNOWN
				playerStatuses[name] = status
				playerNotes[name] = note
				playerOfficerNotes[name] = officernote
				playerOfflineTimes[name] = secondsOffline
				if tmp2[name] then
					tmp2[name] = nil
				else
					add = true
				end
				if rankIndex == 0 then
					guildLeader = name
				end
			end
			if online then
				numPlayersOnline = numPlayersOnline + 1
				if name then
					playersOnline[name] = true
					if tmp[name] then
						tmp[name] = nil
					else
						connect = true
					end
				end
			end
			if add then
				self:TriggerEvent("RollCall10_MemberAdded", name)
			end
			if connect then
				self:TriggerEvent("RollCall10_MemberConnected", name)
			end
		end
		for k in pairs(tmp2) do
			tmp2[k] = nil
			self:TriggerEvent("RollCall10_MemberRemoved", k)
		end
		for k in pairs(tmp) do
			tmp[k] = nil
			self:TriggerEvent("RollCall10_MemberDisconnected", k)
		end
		
		if self:IsBucketEventRegistered("GUILD_ROSTER_UPDATE") then
			self:ScheduleEvent("RollCall10-GuildRoster", GuildRoster, 15)
		end
	else
		for name in pairs(playerLevels) do
			playersOnline[name] = nil
			playerRanks[name] = nil
			playerRankIndexes[name] = nil
			playerLevels[name] = nil
			playerClasses[name] = nil
			playerZones[name] = nil
			playerStatuses[name] = nil
			playerNotes[name] = nil
			playerOfficerNotes[name] = nil
		end
		numPlayersOnline = 0
		numPlayersTotal = 0
		guildLeader = nil
	end
	self:TriggerEvent("RollCall10_Updated")
end

function RollCall:GetNumOnline()
	return numPlayersOnline
end

function RollCall:GetNumTotal()
	return numPlayersTotal
end

local playerName = UnitName("player")

function RollCall:HasMember(name)
	return playerLevels[name or playerName] and true or false
end

function RollCall:IsMemberOnline(name)
	return playersOnline[name or playerName] or false
end

function RollCall:GetRank(name)
	return playerRanks[name or playerName]
end

function RollCall:GetRankIndex(name)
	return playerRankIndexes[name or playerName]
end

function RollCall:GetLevel(name)
	return playerLevels[name or playerName]
end

function RollCall:GetClass(name)
	return playerClasses[name or playerName]
end

function RollCall:GetEnglishClass(name)
	if not BC then
		self:error("Cannot call `GetEnglishClass' without Babble-Class-2.2 loaded.")
	end
	local class = playerClasses[name or playerName]
	if class then
		BC:GetReverseTranslation(name)
	else
		return nil
	end
end

function RollCall:GetClassColor(name)
	if not BC then
		self:error("Cannot call `GetClassColor' without Babble-Class-2.2 loaded.")
	end
	local class = playerClasses[name or playerName]
	if class then
		return BC:GetColor(class)
	else
		return 0.8, 0.8, 0.8
	end
end

function RollCall:GetClassHexColor(name)
	if not BC then
		self:error("Cannot call `GetClassHexColor' without Babble-Class-2.2 loaded.")
	end
	local class = playerClasses[name or playerName]
	if class then
		return BC:GetHexColor(class)
	else
		return "cccccc"
	end
end

function RollCall:GetZone(name)
	return playerZones[name or playerName]
end

function RollCall:GetEnglishZone(name)
	if not BZ then
		self:error("Cannot call `GetEnglishZone' without Babble-Zone-2.2 loaded.")
	end
	local zone = playerZones[name or playerName]
	if zone ~= UNKNOWN then
		return BZ:GetReverseTranslation(zone)
	else
		return "Unknown"
	end
end

function RollCall:GetStatus(name)
	return playerStatuses[name or playerName]
end

function RollCall:GetNote(name)
	return playerNotes[name or playerName]
end

function RollCall:GetOfficerNote(name)
	return playerOfficerNotes[name or playerName]
end

function RollCall:GetSecondsOffline(name)
	return playerOfflineTimes[name or playerName]
end

function RollCall:GetGuildName()
	return (GetGuildInfo('player'))
end

function RollCall:GetGuildLeader()
	return guildLeader
end

local sorts; sorts = {
	NAME = function(a, b)
		return a < b
	end,
	CLASS =	function(a, b)
		local playerClasses_a = playerClasses[a]
		local playerClasses_b = playerClasses[b]
		if playerClasses_a < playerClasses_b then
			return true
		elseif playerClasses_a > playerClasses_b then
			return false
		else
			local playerLevels_a = playerLevels[a]
			local playerLevels_b = playerLevels[b]
			if playerLevels_a < playerLevels_b then
				return true
			elseif playerLevels_a > playerLevels_b then
				return false
			else
				return a < b
			end
		end
	end,
	LEVEL =	function(a,b)
		local playerLevels_a = playerLevels[a]
		local playerLevels_b = playerLevels[b]
		if playerLevels_a < playerLevels_b then
			return true
		elseif playerLevels_a > playerLevels_b then
			return false
		else
			local playerClasses_a = playerClasses[a]
			local playerClasses_b = playerClasses[b]
			if playerClasses_a < playerClasses_b then
				return true
			elseif playerClasses_a > playerClasses_b then
				return false
			else
				return a < b
			end
		end
	end,
	ZONE = function(a, b)
		local playerZones_a = playerZones[a]
		local playerZones_b = playerZones[b]
		if playerZones_a < playerZones_b then
			return true
		elseif playerZones_a > playerZones_b then
			return false
		else
			return sorts.CLASS(a, b)
		end
	end,
	RANK = function(a, b)
		local playerRanks_a = playerZones[a]
		local playerRanks_b = playerZones[b]
		if playerRanks_a < playerRanks_b then
			return true
		elseif playerRanks_a > playerRanks_b then
			return false
		else
			return sorts.CLASS(a, b)
		end
	end,
}

local iter = function(t)
	local n = t.n
	n = n + 1
	t.n = n
	return t[n] or del(t)
end
function RollCall:GetIterator(sort, includeOffline)
	self:argCheck(sort, 2, "string", "nil")
	local sortFunc = sorts[sort or "NAME"]
	if not sortFunc then
		self:error('Argument #2 must be "NAME", "LEVEL", "CLASS", "ZONE", "RANK", or nil, got %q.', sort)
	end
	
	local tmp = new()
	for k in pairs(tmp) do
		tmp[k] = nil
	end
	
	for k in pairs(includeOffline and playerLevels or playersOnline) do
		tmp[#tmp+1] = k
	end
	
	table.sort(tmp, sortFunc)
	tmp.n = 0
	
	return iter, tmp, nil
end

local function external(self, major, instance)
	if major == "Babble-Class-2.2" then
		BC = instance
	elseif major == "Babble-Zone-2.2" then
		BZ = instance
	elseif major == "AceConsole-2.0" then
		instance:RegisterChatCommand({ "/seen" }, {
			type = 'text',
			usage = '<Player>',
			name = "Seen",
			desc = "Seen",
			get = false,
			set = function(name)
				name = name:sub(1, 1):upper() .. name:sub(2):lower()
				if not self:HasMember(name) then
					instance:Print("Member %q is not in the guild", name)
					return
				end
				local seconds = self:GetSecondsOffline(name)
				if not seconds then
					instance:Print("Member %q is online now", name)
					return
				end
				
				if seconds < 60*60 then
					instance:Print("Seen %q less than an hour ago", name)
					return
				end
				local hours = math.floor(seconds / (60*60)) % 24
				local days = math.floor(seconds / (60*60*24)) % 30
				local months = math.floor(seconds / (60*60*24*30)) % (365/30)
				local years  = math.floor(seconds / (60*60*24*365))
				local t = {"Seen %q "}
				if years == 1 then
					t[#t+1] = "1 year, "
				elseif years >= 2 then
					t[#t+1] = ("%d years, "):format(years)
				end
				if months == 1 then
					t[#t+1] = "1 month, "
				elseif months >= 2 or years >= 1 then
					t[#t+1] = ("%d months, "):format(months)
				end
				if days == 1 then
					t[#t+1] = "1 day, "
				elseif days >= 2 or years >= 1 then
					t[#t+1] = ("%d days, "):format(days)
				end
				if #t >= 3 then
					t[#t+1] = "and "
				end
				if hours == 1 then
					t[#t+1] = "1 hour"
				else
					t[#t+1] = ("%d hours"):format(hours)
				end
				t[#t+1] = " ago"
				instance:Print(table.concat(t), name)
			end,
		}, "SEEN")
	end
end

local function activate(self, oldLib, oldDeactivate)
	RollCall = self
	
	AceEvent:embed(self)
	
	self:UnregisterAllEvents()
	
	self:RegisterEvent("PLAYER_GUILD_UPDATE")
	
	if IsInGuild() then
		self:ScheduleEvent("RollCall10-GuildRoster", GuildRoster, 15)
		self:RegisterBucketEvent("GUILD_ROSTER_UPDATE", 1)
		GuildRoster()
	end
	
	if oldDeactivate then
		oldDeactivate(oldLib)
	end
end

AceLibrary:Register(RollCall, MAJOR_VERSION, MINOR_VERSION, activate, nil, external)
