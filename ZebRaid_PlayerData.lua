local Guild = LibStub("LibGuild-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)

local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

local obj = ZebRaid:NewClass("PlayerData",
                             {
                                 player_cache={}
                             })

function obj:Construct()
    if not self.class.state then
        -- stop the infinite loop
        self.class.state = true
        self.class.state = ZebRaid:Construct("State")
    end

    if not self.class.roster then
        self.class.roster = ZebRaid:Construct("Roster")
    end
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
    -- These player objects are generating a lot of garbage. Since they don't
    -- have per-insance state, it is much better to have a single instance per
    -- player.
    if not self.player_cache[name] then
        self.player_cache[name] = self:NewPlayer(self, name, self.data[name])
    end
    return self.player_cache[name]
end

function obj:NewPlayer(playerdata, name, record)
    return ZebRaid:Construct("Player", playerdata, name, record)
end


-- Get an iterator for known players in assigned list.
-- filterfunc is called with name
-- sortfunc is called with the names of the players tro be compared
function obj:GetIterator(filterfunc, sortfunc)
    local tmp = {}
    local res = {}
    -- Pick up players from online people, registered users, and players assigned
    -- to roles.

    for name in Guild:GetIterator("NAME", false) do
        tmp[name] = true
    end

    for name in self.state:RegistrationIterator() do
        tmp[name] = true
    end

    for name in self.state:AssignmentsIterator() do
        tmp[name] = true
    end

    for name in pairs(tmp) do
        tmp[name] = nil
        local player = self:Get(name)
        if not filterfunc or filterfunc(player) then
            table.insert(res, player)
        end
    end

    if sortfunc then
        table.sort(res, sortfunc)
    end

    local i = 0
    local n = #res
    local iterfunc = function ()
        if i < n then
            i = i + 1
            return i, res[i]
        end
    end

    return iterfunc, res, nil
end

-- Class that represents a player. It has a PlayerData backend for persistent
-- state management.
Player = ZebRaid:NewClass("Player", {})

function Player:Construct(playerdata, name, record)
    self.playerData = playerdata
    self.name = name
    self.record = record
end

function Player:GetName()
    return self.name
end

-- Overrides for new version. This is a backward compatibility problem
-- introduced by the wrm4 script.
local RoleOverrides={
    ["healing"] = "healer"
}

function Player:SetRole(role)
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

function Player:GetRole()
    local role = string.lower(self.record.role or "unknown")
    return RoleOverrides[role] or role
end

function Player:GetSitoutCount()
    return #self:GetSitoutDates()
end

function Player:GetSitoutDates()
    if not self.record.sitoutDates then self.record.sitoutDates = {} end
    return self.record.sitoutDates
end

function Player:GetLastSitoutDate()
    local dates = self:GetSitoutDates()
    return dates[#dates] or "01/01/09"
end

function Player:AddSitout()
    local curDate = ZebRaid:GetRaidDate()
    local lastSitout = self:GetLastSitoutDate()
    if curDate ~= lastSitout then
        table.insert(self:GetSitoutDates(), curDate)
    end
end

function Player:RemoveSitout()
    local curDate = ZebRaid:GetRaidDate()
    local lastSitout = self:GetLastSitoutDate()
    if  lastSitout == curDate then
        local dates = self:GetSitoutDates()
        table.remove(dates, #dates)
    end
end

function Player:GetPenaltyCount()
    return #self:GetPenaltyDates()
end

function Player:GetPenaltyDates()
    if not self.record.penaltyDates then self.record.penaltyDates = {} end
    return self.record.penaltyDates
end

function Player:GetLastPenaltyDate()
    local dates = self:GetPenaltyDates()
    return dates[#dates] or "01/01/09"
end

function Player:AddPenalty()
    local curDate = ZebRaid:GetRaidDate()
    local lastPenalty = self:GetLastPenaltyDate()
    if curDate ~= lastPenalty then
        table.insert(self:GetPenaltyDates(), curDate)
    end
end

function Player:RemovePenalty()
    local curDate = ZebRaid:GetRaidDate()
    local lastPenalty = self:GetLastPenaltyDate()
    if  lastPenalty == curDate then
        local dates = self:GetPenaltyDates()
        table.remove(dates, #dates)
    end
end

function Player:GetSignedCount()
    return #self:GetSignedDates()
end

function Player:GetSignedDates()
    if not self.record.sitoutDates then self.record.sitoutDates = {} end
    return self.record.sitoutDates
end

function Player:GetLastSignedDate()
    local dates = self:GetSignedDates()
    return dates[#dates] or "01/01/09"
end

function Player:AddSigned()
    local curDate = ZebRaid:GetRaidDate()
    local lastSigned = self:GetLastSignedDate()
    if curDate ~= lastSigned then
        table.insert(self:GetSignedDates(), curDate)
    end
end

function Player:RemoveSigned()
    local curDate = ZebRaid:GetRaidDate()
    local lastSigned = self:GetLastSignedDate()
    if  lastSigned == curDate then
        local dates = self:GetSignedDates()
        table.remove(dates, #dates)
    end
end

function Player:GetAlts()
    return self.record.AltList
end

function Player:AddAlt(alt)
    if not self.record.AltList then self.record.AltList = {} end
    self.record.AltList[alt] = true
end

function Player:GetGuildRank()
    return Guild:GetRank(self.name)
end

function Player:GetGuildNote()
    return Guild:GetNote(self.name)
end

function Player:IsOnline()
    -- It is not easy to determine non-guildies online status.
    -- For now, report online for everyone not in guild.
    return not self:IsInGuild() or Guild:IsMemberOnline(self.name)
end

function Player:IsAltOnline()
    -- TODO: Move tracker functionality to PlayerData
    ZebRaid:Tracker_IsAltOnline(self.name)
end

function Player:SetMainToon()
    ZebRaid:Tracker_SetPlayerMain(self.name)
end

function Player:GetClass()
    return Guild:GetClass(self.name)
end

function Player:GetTooltipText()
    local text = "Rank: " .. (self:GetGuildRank() or "not in guild") .. "\n"
    if self:GetGuildNote() then
        text = text ..
            self:GetGuildNote() .. "\n\n"
    else
        text = text .. "\n"
    end

    if not self:IsOnline() then
        if self:IsAltOnline() then
            text = text ..
                "|cffff0000" .. L["ALT_ONLINE"] ..
                ": " .. ZebRaid:Tracker_GetCurrentAlt(self.name) ..
                "|r\n\n"
        else
            text = text ..
                "|cffff0000" .. L["PLAYER_OFFLINE"] .. "|r\n\n"
        end
    end

    local status = self:GetSignupStatus(self.name)
    if status == ZebRaid.signup_const.unsigned then
        text = text ..
            "|cffff0000" .. L["PLAYER_UNSIGNED"] .. "|r\n\n"
    end

    local note = self:GetSignupNote(self.name)
    if note then
        text = text .. "\n" ..
            "|cffffff00Note: " .. note .. "|r\n"
    end

    text = text ..
        "|c9f3fff00" .. L["SIGNSTATS"] .. "|r: " ..
        self:GetSignedCount() .. "/" ..
        self:GetSitoutCount() .. "/" ..
        self:GetPenaltyCount() .. "\n"

    local sitoutDates = self:GetSitoutDates()
    for _,v in ipairs(sitoutDates) do
        text = text ..
            "|c7f1fcf00" .. v .. "|r\n"
    end
    local penaltyDates = self:GetPenaltyDates()
    for _,v in ipairs(penaltyDates) do
        text = text ..
            "|cff1f1f00" .. v .. "|r\n"
    end
    return text
end

function Player:GetSignupStatus()
    return self.playerData.state:GetSignupStatus(self.name)
end

function Player:GetSignupNote()
    return self.playerData.state:GetSignupNote(self.name)
end

function Player:GetAssignment()
    return self.playerData.state:GetAssignment(self.name)
end

function Player:SetAssignment(assignment)
    return self.playerData.state:SetAssignment(self.name, assignment)
end

function Player:RemoveAssignment()
    return self.playerData.state:RemoveAssignment(self.name)
end

function Player:GetClassColor()
    return Guild:GetClassColor(self.name)
end

function Player:IsInGuild()
    return Guild:HasMember(self.name)
end

function Player:IsInRaid()
    -- TODO: Move roster functionality to playerdata
    return self.playerData.roster:IsPlayerInRaid(self.name)
end

