local initialized = false

function ZebRaid:RosterInit()
	if not initialized then
		if not self.unitIds then self.unitIds = {} end
		self:RegisterEvent("RAID_ROSTER_UPDATE", "MembersChanged")
		self:RegisterEvent("PARTY_MEMBERS_CHANGED", "MembersChanged")

		-- Assume there was a change, and record the current status
		self:MembersChanged()

		initialized = true
	end
end

function ZebRaid:RosterFinal()
	if initialized then
		initialized = false
		self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
		self:UnregisterEvent("RAID_ROSTER_UPDATE")
	end
end

function ZebRaid:IsPlayerInRaid(player)
   if self.unitIds[player] then return true
   else return false
   end
end

function ZebRaid:GetRosterIterator()
	return pairs(self.unitIds)
end

function ZebRaid:MembersChanged()
	self:Debug("ZebRaid:MembersChanged()")
	
	local updated = false
	
	-- Get rid of people who left the raid, or changed unit ids
	for name, unit in pairs(self.unitIds) do
		if GetUnitName(unit) ~= name
		then
			self.unitIds[name] = nil
			updated = true
		end
	end
	
	-- Scan either the party, or the raid
	local formatString, getCountFunc
	if UnitInRaid("player") then
		formatString = "raid%d"
		getCountFunc = GetNumRaidMembers
	elseif UnitInParty("player") and GetNumPartyMembers() > 0 then
		formatString = "party%d"
		getCountFunc = GetNumPartyMembers
	end
	
	if getCountFunc then
		local n = getCountFunc()
		for i=1,n do
			local unit=string.format(formatString, i)
			local name=GetUnitName(unit)
			if unit and name then
				if self.unitIds[name] ~= unit then
					self.unitIds[name] = unit
					updated = true
				end
			end
		end
	end

	if updated then
		self:Debug("Triggering ZebRaid_RosterUpdated");
		self:SendMessage("ZebRaid_RosterUpdated")
	end

	self:Debug("ZebRaid:MembersChanged():END")
end
