function ZebRaid:RosterInit()
	if not self.unitIds then self.unitIds = {} end
	self:RegisterBucketEvent("RAID_ROSTER_UPDATE", 1, "MembersChanged")
	self:RegisterBucketEvent("PARTY_MEMBERS_CHANGED", 1, "MembersChanged")
end

function ZebRaid:RosterFinal()
	self:UnregisterBucketEvent("PARTY_MEMBERS_CHANGED")
	self:UnregisterBucketEvent("RAID_ROSTER_UPDATE")
end

function ZebRaid:IsPlayerInRaid(player)
   if self.unitIds[player] then return true
   else return false
   end
end

function ZebRaid:MembersChanged()
	self:Debug("ZebRaid:MembersChanged()")
	
	-- Get rid of people who left the raid, or changed unit ids
	for name, unit in pairs(self.unitIds) do
		if GetUnitName(unit) ~= name
		then
			self.unitIds[name] = nil
		end
	end
	
	-- Scan either the party, or the raid
	if UnitInRaid("player") then
		local n = GetNumRaidMembers()
		for i=1,n do
			local unit=string.format("raid%d", i)
			local name=GetUnitName(unit)
			if unit and name then
				self.unitIds[name] = unit
			end
		end
	elseif UnitInParty("player") then
		local n = GetNumPartyMembers()
		for i=1,n do
			local unit=string.format("party%d", i)
			local name=GetUnitName(unit)
			if unit and name then
				self.unitIds[name] = unit
			end
		end
	end

	-- FIXME: HACK ALERT. Fire an event here
	if coroutine.status(self.coInvite) == "suspended" then
		coroutine.resume(self.coInvite)
	end

	self:Debug("ZebRaid:MembersChanged():END")
end

--[[
function ZebRaid:RosterLib_RosterUpdated()
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end

    self:Debug("ZebRaid:RosterLib_RosterUpdated()");

    if (DoingFirstInvite and
        GetNumPartyMembers() > 0 and
        not UnitInRaid("player"))
    then
        self:Debug("Converting to raid");
        ConvertToRaid();
        DoingFirstInvite = nil;
    end

    -- Check the unsigned, signed and unsure lists for people in raid.
    -- When you find them, move them to "confirmed".
    local state = ZebRaidState[ZebRaidState.KarmaDB];
    if state then
        local playersToMove = {}
        local listsToScan = {
            "GuildList",
            "SignedUp",
            "Unsure",
            "Reserved"
        };
        
        for _, listName in pairs(listsToScan) do
            for pos, name in pairs(state.Lists[listName].members) do
                if Roster:GetUnitIDFromName(name) then
                    self:Debug("Moving " .. name .. " from " .. listName .. "to Confirmed");
                    table.insert(playersToMove, {list = listName, pos = pos, name = name});
                end
            end
        end

        local confirmedList = state.Lists["Confirmed"];
        for _, data in pairs(playersToMove) do
            local fromList = state.Lists[data.list];
            local fromPos = data.pos;
            self:RemoveFromList(state, fromList, fromPos);
            self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, data.list, fromPos);
            self:AddToList(state, confirmedList, data.name);
            self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, "Confirmed", data.name);
        end
    end
end
]]--