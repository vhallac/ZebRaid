local Guild = LibStub("LibGuild-1.0")
local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- Define a shorter name for the following code
local obj = ZebRaid:NewClass("PlayerData", {})

function obj:Construct()
    -- Nothing to see here. Move on.
end

-- This is supposed to be called on the class.
-- TODO: Any way we can separate class methods from instance methods?
function obj:SetDataStore(data)
    self.data = data
end

function obj:Get(name)
    if not self.data[name] then
        self.data[name] = {}
    end
    return self:NewPlayer(self, name, self.data[name])
end

function obj:NewPlayer(playerdata, name, record)
    return ZebRaid:Construct("Player", playerdata, name, record)
end

-- Class that represents a player. It has a PlayerData backend for persistent
-- state management.
PlayerClass = ZebRaid:NewClass("Player", {})

function PlayerClass:Construct(playerdata, name, record)
    self.playerData = playerdata
    self.name = name
    self.record = record
end

function PlayerClass:GetName()
    return self.name
end

-- Overrides for new version. This is a backward compatibility problem
-- introduced by the wrm4 script.
local RoleOverrides={
	["healing"] = "healer"
}

function PlayerClass:SetRole(role)
    role = string.lower(role)
    -- Update the player role with the new one unless the role is
    -- unknown. If the player role is not recorded yet, just stick
    -- anything we have (including unknown) to it.
    if ( not self.record.role or
         role ~= "unknown" )
    then
        self.record.role = RoleOverrides[role] or role
    end
end

function PlayerClass:GetRole()
    local role = self.record.role or "unknown"
    return string.lower(RoleOverrides[role] or role)
end

function PlayerClass:GetSitoutCount()
    return #self:GetSitoutDates()
end

function PlayerClass:GetSitoutDates()
    if not self.record.sitoutDates then self.record.sitoutDates = {} end
	return self.record.sitoutDates
end

function PlayerClass:GetLastSitoutDate()
	local dates = self:GetSitoutDates()
	return dates[#dates] or "01/01/09"
end

function PlayerClass:AddSitout()
	local curDate = ZebRaid:GetRaidDate()
	local lastSitout = self:GetLastSitoutDate()
	if curDate ~= lastSitout then
		table.insert(self:GetSitoutDates(), curDate)
	end
end

function PlayerClass:RemoveSitout()
	local curDate = ZebRaid:GetRaidDate()
	local lastSitout = self:GetLastSitoutDate()
	if  lastSitout == curDate then
        local dates = self:GetSitoutDates()
        table.remove(dates, #dates)
	end
end

function PlayerClass:GetPenaltyCount()
    return #self:GetPenaltyDates()
end

function PlayerClass:GetPenaltyDates()
    if not self.record.penaltyDates then self.record.penaltyDates = {} end
    return self.record.penaltyDates
end

function PlayerClass:GetLastPenaltyDate()
	local dates = self:GetPenaltyDates()
	return dates[#dates] or "01/01/09"
end

function PlayerClass:AddPenalty()
	local curDate = ZebRaid:GetRaidDate()
	local lastPenalty = self:GetLastPenaltyDate()
	if curDate ~= lastPenalty then
		table.insert(self:GetPenaltyDates(), curDate)
	end
end

function PlayerClass:RemovePenalty()
	local curDate = ZebRaid:GetRaidDate()
	local lastPenalty = self:GetLastPenaltyDate()
	if  lastPenalty == curDate then
        local dates = self:GetPenaltyDates()
        table.remove(dates, #dates)
	end
end

function PlayerClass:GetSignedCount()
    return #self:GetSignedDates()
end

function PlayerClass:GetSignedDates()
    if not self.record.sitoutDates then self.record.sitoutDates = {} end
	return self.record.sitoutDates
end

function PlayerClass:GetLastSignedDate()
	local dates = self:GetSignedDates()
	return dates[#dates] or "01/01/09"
end

function PlayerClass:AddSigned()
	local curDate = ZebRaid:GetRaidDate()
	local lastSigned = self:GetLastSignedDate()
	if curDate ~= lastSigned then
		table.insert(self:GetSignedDates(), curDate)
	end
end

function PlayerClass:RemoveSigned()
	local curDate = ZebRaid:GetRaidDate()
	local lastSigned = self:GetLastSignedDate()
	if  lastSigned == curDate then
        local dates = self:GetSignedDates()
        table.remove(dates, #dates)
	end
end

function PlayerClass:GetAlts()
    return self.record.AltList
end

function PlayerClass:AddAlt(alt)
    if not self.record.AltList then self.record.AltList = {} end
    self.record.AltList[alt] = true
end

function PlayerClass:GetGuildRank()
    return Guild:GetRank(self.name)
end

function PlayerClass:GetGuildNote()
    return Guild:GetNote(self.name)
end

function PlayerClass:IsOnline()
    return Guild:IsMemberOnline(self.name)
end
