local Guild = LibStub("LibGuild-1.0")
local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- The function prototypes will go in here
local PlayerDataClass = {
}

-- Define a shorter name for the following code
local obj = PlayerDataClass

function ZebRaid:NewPlayerData()
    return ZebRaid:Construct(PlayerDataClass)
end

function ZebRaid:SetPlayerDataBackend(data)
    PlayerDataClass.data = data
end

function obj:Construct()
    -- Nothing to see here. Move on.
end

function obj:Get(name)
    if not self.data[name] then
        self.data[name] = {}
    end
    return self.data[name]
end

-- Overrides for new version. This is a backward compatibility problem
-- introduced by the wrm4 script.
local RoleOverrides={
	["healing"] = "healer"
}

function obj:SetRole(name, role)
    local data = self:Get(name)
    role = string.lower(role)
    -- Update the player role with the new one unless the role is
    -- unknown. If the player role is not recorded yet, just stick
    -- anything we have (including unknown) to it.
    if ( not data.role or
         role ~= "unknown" )
    then
        data.role = RoleOverrides[role] or role
    end
end

function obj:GetRole(name)
    local data = self:Get(name)
    local role = data.role or "unknown"
    return RoleOverrides[role] or role
end

function obj:GetSitoutCount(name)
    return #self:GetSitoutDates(name)
end

function obj:GetSitoutDates(name)
    local data = self:Get(name)
    if not data.sitoutDates then data.sitoutDates = {} end
	return data.sitoutDates
end

function obj:GetLastSitoutDate(name)
	local dates = self:GetSitoutDates(name)
	return dates[#dates] or "01/01/09"
end

function obj:AddSitout(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastSitout = self:GetLastSitoutDate(name)
	if curDate ~= lastSitout then
		table.insert(self:GetSitoutDates(name), curDate)
	end
end

function obj:RemoveSitout(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastSitout = self:GetLastSitoutDate(name)
    -- Edge case: cannot remove the sitout from someone after midnight
	if  lastSitout == curDate then
        local dates = self:GetSitoutDates(name)
        table.remove(dates, #dates)
	end
end

function obj:GetPenaltyCount(name)
    return #self:GetPenaltyDates(name)
end

function obj:GetPenaltyDates(name)
    local data = self:Get(name)
    if not data.penaltyDates then data.penaltyDates = {} end
    return data.penaltyDates
end

function obj:GetLastPenaltyDate(name)
	local dates = self:GetPenaltyDates(name)
	return dates[#dates] or "01/01/09"
end

function obj:AddPenalty(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastPenalty = self:GetLastPenaltyDate(name)
	if curDate ~= lastPenalty then
		table.insert(self:GetPenaltyDates(name), curDate)
	end
end

function obj:RemovePenalty(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastPenalty = self:GetLastPenaltyDate(name)
    -- Edge case: cannot remove the sitout from someone after midnight
	if  lastPenalty == curDate then
        local dates = self:GetPenaltyDates(name)
        table.remove(dates, #dates)
	end
end

function obj:GetSignedCount(name)
    return #self:GetSignedDates(name)
end

function obj:GetSignedDates(name)
    local data = self:Get(name)
    if not data.sitoutDates then data.sitoutDates = {} end
	return data.sitoutDates
end

function obj:GetLastSignedDate(name)
	local dates = self:GetSignedDates(name)
	return dates[#dates] or "01/01/09"
end

function obj:AddSigned(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastSigned = self:GetLastSignedDate(name)
	if curDate ~= lastSigned then
		table.insert(self:GetSignedDates(name), curDate)
	end
end

function obj:RemoveSigned(name)
	local curDate = ZebRaid:GetRaidDate()
	local lastSigned = self:GetLastSignedDate(name)
    -- Edge case: cannot remove the sitout from someone after midnight
	if  lastSigned == curDate then
        local dates = self:GetSignedDates(name)
        table.remove(dates, #dates)
	end
end

function obj:GetAlts(name)
    local data = self:Get(name)
    if data then return data.AltList end
end

function obj:AddAlt(name, alt)
    local data = self:Get(name)
    if data then
        if not data.AltList then
            data.AltList = {}
        end
        data.AltList[alt] = true
    end
end
