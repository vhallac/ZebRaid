-- Libraries we want to use in this file
local Guild = LibStub("LibGuild-1.0")

-- Find the position of a value in a table.
function ZebRaid:FindInTable(tbl, name)
    for pos, val in pairs(tbl) do
        if val == name then return pos; end
    end

    return nil;
end

function ZebRaid:Count(tbl)
    local count=0;
    for _,_ in pairs(tbl) do
        count = count + 1;
    end
    return count;
end

-- Create a new instance of a list
function ZebRaid:NewList(listName)
    local list = {
        name = listName;
        members = {}
    };
    return list;
end

-- Add a player to the specified list
function ZebRaid:AddToList(state, list, name)
    local insertPos = nil;
    local destList = list;
    local signupData = self.RegisteredUsers[name];

    if not state.RaidHistoryEntry.players[name] then
        state.RaidHistoryEntry.players[name] = {};
    end

    local histEntry = state.RaidHistoryEntry.players[name];

    if list.name == "Confirmed" then
        insertPos = self:FindClassInsertPos(list, name);
    elseif list.name == "GuildList" then
        if not Guild:IsMemberOnline(name) then
            destList = nil;
        end
    end

    -- If we really want to insert to a list ...
    if destList then
        -- If there is a specific position we'd want ...
        if insertPos then
            -- then insert player there, ...
            table.insert(destList.members, insertPos, name);
        else
            -- otherwise insert player to the end.
            table.insert(destList.members, name);
        end
        
        if list.name ~= "GuildList" then
            histEntry.listName = destList.name;
        else
            -- Do not save any data for people in Guild list.
            state.RaidHistoryEntry.players[name] = nil;
        end
    end
end

-- Remove a player from the specified list
function ZebRaid:RemoveFromList(state, list, nameOrPos)
    local name = nil;
    local pos = nil;

    if type(nameOrPos) == "number" then
        pos = nameOrPos;
        name = list.members[pos];
    else
        -- assume string
        self:Debug("Removing: string");
        self:Debug("list: " .. list.name);
        name = nameOrPos;
        pos = self:FindInTable(list.members, name);
        self:Debug("name: " .. (name or "nil") .. " pos: " .. (pos or "nil"));
    end

    -- If garbage in, no work done ...
    if not pos or not name then return; end

    local histEntry = state.RaidHistoryEntry.players[name];

    -- First, get rid of the member
    table.remove(list.members, pos);

    -- If the player has a history entry, then get rid of the changes
    if histEntry then
        -- Get rid of the recorded list name.
        histEntry.listName = nil;
    end
end

-- Find a suitable target list for the specified player name inside the
-- specified list.
-- list: the current list of the player
-- name: name of the player
-- RETURNS: the selected list, or null.
function ZebRaid:FindTargetList(list, name)
    local destList = nil;
    local state = ZebRaidState[ZebRaidState.KarmaDB];
    local stats = self.PlayerStats[ZebRaidState.KarmaDB][name];

    -- Move people back and forth on double click

    -- In Unsure: online => Confirmed
    --            offline => Reserved
    -- In Reserved: Registered => SignedUp or Unsure
    --              Unregistered => GuildList

    if ( list.name == "SignedUp" ) then
        if Guild:IsMemberOnline(name) then
            destList = state.Lists["Confirmed"];
        else
            destList = state.Lists["Reserved"];
        end
    -- SignedUp or Unsure: online and sitout => Confirmed
    --                     offline => Reserved
    elseif list.name == "Unsure" then
        if Guild:IsMemberOnline(name) then
            destList = state.Lists["Confirmed"];
        else
            destList = state.Lists["Reserved"];
        end
    -- Confirmed or Reserved: Registered => SignedUp or Unsure
    --                        Unregistered => GuildList
    elseif list.name == "Confirmed" or list.name == "Reserved" then
        self:Debug("Confirmed or Reserved");

        if state.RegisteredUsers[name] and
           state.RegisteredUsers[name].list
        then
            destList = state.Lists[self.RegisteredUsers[name].list];
        else
            destList = state.Lists["GuildList"];
        end
    -- GuildList: Confirmed
    elseif list.name == "GuildList" then
        destList = state.Lists["Confirmed"];
    -- Penalty or Sitout: SignedUp (unsure players can receive neither)
    elseif list.name == "Penalty" or list.name == "Sitout" then
        destList = state.Lists["SignedUp"];
    end

    -- If the guy has a penalty, he moves to sitout 
    -- regardless of the current selection
--    if stats and (stats.penalties > 0) then
  --      destList = self.Lists["Sitout"];
    --end
    
    return destList;
end

