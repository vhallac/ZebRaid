local Guild = LibStub("LibGuild-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)
local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

-- The function prototypes will go in here
local State_Template = {
    UIMasters = {},          -- Broken feature: List of UI master per DB

    signup_const = {
        signed = "signed",      -- ready and willing
        unsigned = "unsigned",  -- won't make it
        unsure = "unsure",      -- May make it to invite time
        unknown = "unknown"     -- didn't use the planner
    },

    assignment_const = {
        unassigned = "unassigned", -- No raid status yet
        confirmed = "confirmed",   -- Will raid
        reserved = "reserved",     -- Spot reserved for member
        penalty = "penalty",       -- Received a penalty (for not showing up)
        sitout = "sitout",         -- Will be sitting out
    }
}

-- Meta table to allow all object to access the "static" variables.
local meta = {__index = State_Template,
              __newindex = function(tbl, key, val)
                  if State_Template[key] then State_Template[key] = val
                  else rawset(tbl, key, val) end
              end}

-- Define a shorter name for the following code

local obj = State_Template

function ZebRaid:NewState()
    -- Get an accessor to player database shared by all instances
    if not State_Template.players then
        State_Template.players = ZebRaid:NewPlayerData()
    end

    state = setmetatable({}, meta)
    state:Construct()
    return state
end

function ZebRaid:SetStateBackend(state)
    State_Template.data = state
end

function obj:Construct()
    -- If we have a karma DB selected, choose the active state
    if self.data.KarmaDB then
        -- Need to set in in the shared state
        State_Template.active = self.data[db]
    end

    if self.active and not self.active.RegisteredUsers then
        self:ParseLocalRaidData()
    end

--[[ This shouldn't be needed
    -- Now, create a list assignment entry for all registered and online users
    if not self.active.Assignments then
        self.active.Assignments = {}

        for name in pairs(self.RegisteredUsers) do
            self:SetAssignment(name, self.assignment_const.unassigned)
        end
    end
--]]
    -- Now, go through each online member, and add assignments for them if they
    -- don't have one.
	for name in Guild:GetIterator("NAME", false) do
		if Guild:GetLevel(name) == 80 and
            not self:GetAssignment(name)
        then
            self:SetAssignment(name, self.assignment_const.unassigned)
        end
    end
end

function obj:Cleanup()
	--
	-- If we are not the master or we do not know the master of a list,
	-- and if the DB's raid ID does not match our current raid ID, then
	-- remove the state for that DB.
	--
	for db, val in pairs(ZebRaidState) do
		if (type(ZebRaidState[db]) == "table") and
            (not self.UIMasters[db]) and
            (val.RaidID ~= ZebRaid.RaidID)
		then
			ZebRaid:Debug("Erasing db state " .. db)
			ZebRaidState[db] = nil
		end
	end
end

function obj:SetKarmaDb(db)
    -- Take away penalty and sitouts from people
    if self.active and self.active.Assignments then
        for name, assignment in pairs(self.active.Assignments) do
            self:AdjustSitoutPenalty(name, assignment, nil)
        end
    end

    self.data.KarmaDB = db
    if not self.data[db] then
        self.data[db] = {}
    end

    -- Need to set in in the shared state
    State_Template.active = self.data[db]

    if not self.active.RegisteredUsers then
        self:ParseLocalRaidData()
    end

    -- Now, give new penalty and sitouts to people
    if self.active and self.active.Assignments then
        for name, assignment in pairs(self.active.Assignments) do
            self:AdjustSitoutPenalty(name, nil, assignment)
        end
    end

    -- Just assign the online people. The database is probably not up-to-date
    self:AssignOnline()
end

function obj:GetKarmaDb()
    return self.data.KarmaDB
end

function obj:GetRaidId()
    if not self.active then return nil end
    return self.active.RaidID
end

function obj:SetRaidId(id)
    if not self.active then return end
    self.active.RaidID = id
end

function obj:AddRegisteredUser(name, status, role, note)
    if note == "" then note = nil end

    if Guild:HasMember(name) then
        -- If we didn't gkick the user since sign-up, add him to the
        -- RegisteredUsers table
        self.active.RegisteredUsers[name] = {
            status = status,
            role = role, -- Fixme: probably won't want this. Use the player data
            note = note
        }

        -- Update player database with the new role
        self.players:SetRole(name, role)
    end
end

function obj:GetSignupStatus(name)
    if not self.active then return end

    return ( self.active.RegisteredUsers[name] and
             self.active.RegisteredUsers[name].status or
             self.signup_const.unknown )
end

function obj:GetSignupNote(name)
    return ( self.active.RegisteredUsers[name] and
             self.active.RegisteredUsers[name].note or
             nil )
end

function obj:GetAssignment(name)
    if not ( self.active ) then  return end

    -- If the active state has no assignments, create the table
    if not self.active.Assignments then
        self.active.Assignments = {}
    end

    -- If we have an empty assignment table, fill it in.
    if next(self.active.Assignments) == nil then
        self:ResetAssignments()
    end

    return self.active.Assignments[name]
end

function obj:SetAssignment(name, assignment)
    if not self.active then return end

    local oldval = self.active.Assignments[name]
    self.active.Assignments[name] = assignment

    self:AdjustSitoutPenalty(name, oldval, assignment)
end

function obj:AdjustSitoutPenalty(name, oldAssignment, newAssignment)
    if oldAssignment == self.assignment_const.sitout then
        self.players:RemoveSitout(name)
    elseif oldAssignment == self.assignment_const.penalty then
        self.players:RemovePenalty(name)
    end

    if newAssignment == self.assignment_const.sitout then
        self.players:AddSitout(name)
    elseif newAssignment == self.assignment_const.penalty then
        self.players:AddPenalty(name)
    end
end

function obj:RemoveAssignment(name)
    if not self.active then return end
    self.active.Assignments[name] = nil
end

function obj:GetUiMaster(db)
    return self.UIMasters[db]
end

function obj:SetUiMaster(db, name)
    self.UIMasters[db] = name
	--[[
	self:BroadcastComm("ANNOUNCE_MASTER",
							ZebRaidState.KarmaDB, state.RaidID,
							state.RegisteredUsers,
							state.Lists)
	]]--
end

function obj:RemoveUiMaster(name)
	for db, val in pairs(self.UIMasters) do
		ZebRaid.UIMasters[db] = nil
		if self:GetKarmaDb() == db then
            -- FIXME: Why am I locking my UI again?
			ZebRaid:LockUI()
		end
	end
end

function obj:ResetAssignments()
    -- Erase the table elements instead fo creating a new table for less garbage
    -- TODO: Need a generis table allocator to reduce table garbagge
    for i in pairs(self.active.Assignments) do
        self.active.Assignments[i] = nil
    end

    for name in pairs(self.active.RegisteredUsers) do
        self:SetAssignment(name, self.assignment_const.unassigned)
    end

    self:AssignOnline()
end

function obj:AssignOnline()
    for name in Guild:GetIterator("NAME", false) do
		if Guild:GetLevel(name) == 80 and
            not self:GetAssignment(name) -- This will not cause recursion
        then
            self:SetAssignment(name, self.assignment_const.unassigned)
        end
    end
end

-- TODO: Need a GetPlayerRole here?

function obj:GetTooltipText(name)
	local text = "Rank: " .. (Guild:GetRank(name) or "not in guild") .. "\n"
	if Guild:GetNote(name) then
		text = text ..
            Guild:GetNote(name) .. "\n\n"
	else
		text = text .. "\n"
	end

	if not Guild:IsMemberOnline(name) then
		if ZebRaid:Tracker_IsAltOnline(name) then
			text = text ..
                "|cffff0000" .. L["ALT_ONLINE"] ..
                ": " .. ZebRaid:Tracker_GetCurrentAlt(name) ..
                "|r\n\n"
		else
			text = text ..
                "|cffff0000" .. L["PLAYER_OFFLINE"] .. "|r\n\n"
		end
	end

    local status = self:GetSignupStatus(name)
    if status == self.signup_const.unsigned then
        text = text ..
            "|cffff0000" .. L["PLAYER_UNSIGNED"] .. "|r\n\n"
    end

    local note = self:GetSignupNote(name)
    if note then
        text = text .. "\n" ..
            "|cffffff00Note: " .. note .. "|r\n"
    end

    text = text ..
        "|c9f3fff00" .. L["SIGNSTATS"] .. "|r: " ..
        self.players:GetSignedCount(name) .. "/" ..
        self.players:GetSitoutCount(name) .. "/" ..
        self.players:GetPenaltyCount(name) .. "\n"

	local sitoutDates = self.players:GetSitoutDates(name)
	for _,v in ipairs(sitoutDates) do
		text = text ..
            "|c7f1fcf00" .. v .. "|r\n"
	end
	local penaltyDates = self.players:GetPenaltyDates(name)
	for _,v in ipairs(penaltyDates) do
		text = text ..
            "|cff1f1f00" .. v .. "|r\n"
	end
    return text
end

function obj:ParseLocalRaidData()
    -- Get rid of old data
    self.active.RegisteredUsers = {}
	for _,val in pairs(ZebRaid.Signups) do
		ZebRaid:Debug("Value: " .. val)
		local name, status, role, note =
			select(3, val:find("^([^:]+):([^:]+):([^:]+):?(.*)"))

		local list = nil

        self:AddRegisteredUser(name, status, role, note)
	end
end

-- Get an iterator for known players in assigned list.
-- filterfunc is called with name
-- sortfunc is called with the names of the players tro be compared
local iter = function(t)
	local n = t.n + 1
	t.n = n
    if t[n] then
        return n, t[n]
    end
end
function obj:GetPlayerIterator(filterfunc, sortfunc)
    local tmp = {}
    if self.active then
        for name, assignment in pairs(self.active.Assignments) do
            if not filterfunc or
                filterfunc(name)
            then
                table.insert(tmp, name)
            end
        end
    end
	table.sort(tmp, sortfunc)
	tmp.n = 0

	return iter, tmp, nil
end
