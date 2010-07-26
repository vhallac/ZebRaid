local addonName, addonTable = ...
local ZebRaid = addonTable.ZebRaid

ZebRaid.signup_const = {
    signed = "signed",      -- ready and willing
    unsigned = "unsigned",  -- won't make it
    unsure = "unsure",      -- May make it to invite time
    unknown = "unknown"     -- didn't use the planner
}

ZebRaid.assignment_const = {
    unassigned = "unassigned", -- No raid status yet
    confirmed = "confirmed",   -- Will raid
    reserved = "reserved",     -- Spot reserved for member
    penalty = "penalty",       -- Received a penalty (for not showing up)
    sitout = "sitout",         -- Will be sitting out
}

local obj = ZebRaid:NewClass(
    "State",
    {
        UIMasters = {},          -- Broken feature: List of UI master per DB
    })

function obj:Construct()
    -- Get an accessor to player database shared by all instances
    if not self.class.players then
        -- stop the infinite loop
        self.class.players = true
        self.class.players = ZebRaid:Construct("PlayerData")
    end

    -- If we have a karma DB selected, choose the active state
    if self.data.KarmaDB then
        -- Need to set in in the shared state
        self.class.active = self.data[db]
    end

    if self.active and not self.active.RegisteredUsers then
        self:ParseLocalRaidData()
    end
end

-- Class method
function obj:SetDataStore(state)
    self.data = state
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
    self.class.active = self.data[db]

    if not self.active.RegisteredUsers then
        self:ParseLocalRaidData()
    end

    if not self.active.Assignments then
        self.active.Assignments = {}
    end

    -- Now, give new penalty and sitouts to people
    if self.active and self.active.Assignments then
        for name, assignment in pairs(self.active.Assignments) do
            self:AdjustSitoutPenalty(name, nil, assignment)
        end
    end

    -- Just assign the online people. The database is probably not up-to-date
--    self:AssignOnline()
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
    local p = self.players:Get(name)

    if note == "" then note = nil end

    if p:IsInGuild() then
        -- If we didn't gkick the user since sign-up, add him to the
        -- RegisteredUsers table
        self.active.RegisteredUsers[name] = {
            status = status,
            role = role, -- Fixme: probably won't want this. Use the player data
            note = note
        }

        -- Update player database with the new role
        p:SetRole(role)
    end
end

function obj:GetSignupStatus(name)
    if not self.active then return end

    return ( self.active.RegisteredUsers[name] and
             self.active.RegisteredUsers[name].status or
             ZebRaid.signup_const.unknown )
end

function obj:GetSignupNote(name)
    return ( self.active.RegisteredUsers[name] and
             self.active.RegisteredUsers[name].note or
             nil )
end

function obj:GetAssignment(name)
    if not ( self.active ) then  return end

    return self.active.Assignments[name] or ZebRaid.assignment_const.unassigned
end

function obj:SetAssignment(name, assignment)
    if not self.active then return end

    local oldval = self.active.Assignments[name]
    self.active.Assignments[name] = assignment

    self:AdjustSitoutPenalty(name, oldval, assignment)
end

function obj:AdjustSitoutPenalty(name, oldAssignment, newAssignment)
    local p = self.players:Get(name)

    if oldAssignment == ZebRaid.assignment_const.sitout then
        p:RemoveSitout()
    elseif oldAssignment == ZebRaid.assignment_const.penalty then
        p:RemovePenalty()
    end

    if newAssignment == ZebRaid.assignment_const.sitout then
        p:AddSitout()
    elseif newAssignment == ZebRaid.assignment_const.penalty then
        p:AddPenalty()
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
    -- TODO: Need a generic table allocator to reduce table garbagge
    for i in pairs(self.active.Assignments) do
        self.active.Assignments[i] = nil
    end
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

function obj:RegistrationIterator()
    if self.active then
        return pairs(self.active.RegisteredUsers or {})
    end
    return pairs({})
end

function obj:AssignmentsIterator()
    if self.active then
        return pairs(self.active.Assignments or {})
    end
    return pairs({})
end
