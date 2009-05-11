local RBC = LibStub("LibBabble-Class-3.0"):GetReverseLookupTable()

function ZebRaid:GetEnglishClass(name)
	if name then
		return RBC[name]
	else
		return nil
	end
end

function ZebRaid:GetClassColor(name)
	local class = self:GetEnglishClass(name)
    -- If there is no reverse translation, assume it is english
    if not class then class = name end
	if class then
		local c = RAID_CLASS_COLORS[class:upper()]
		return c.r, c.g, c.b
	else
		return 0.8, 0.8, 0.8
	end
end 