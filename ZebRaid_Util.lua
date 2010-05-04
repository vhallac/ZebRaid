local RBC = LibStub("LibBabble-Class-3.0"):GetReverseLookupTable()
local addonName, addonTable = ...

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

--
-- Poor man's objects. Supports object construction and static members, and not
-- much else.
--

addonTable.classes = {}

function ZebRaid:NewClass(name, class)
    addonTable.classes[name] = class

    local meta = {
        __index = class,
        __newindex = function(tbl, key, val)
            if class[key] then class[key] = val
            else rawset(tbl, key, val) end
        end}
    class.New = function (self, ...)
        local instance = setmetatable({}, meta)
        if instance then
            -- Make it an instance variable to prevent self-referencing class objects.
            instance.class = class
            instance:Construct(...)
        end
        return instance
    end

    return class
end

function ZebRaid:GetClass(name)
    return addonTable.classes[name]
end

function ZebRaid:Construct(name, ...)
    local class = self:GetClass(name)
    local instance
    if class then
        instance = class:New(...)
    end
    return instance
end
