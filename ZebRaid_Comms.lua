local L = AceLibrary("AceLocale-2.2"):new("ZebRaid");

-- Sent by the addon to guild when it starts. Used for advertising its presence,
-- and learning the other instances of the addon.
function ZebRaid.OnCommReceive.BROADCAST(self, prefix, sender, distibution)
    self:Debug("Received BROADCAST from " .. sender);
	-- TODO: Sync the known player roles
	--[[
	
    if not ZebRaid.UiLockedDown then
        local state = ZebRaidState[ZebRaidState.KarmaDB];

        ZebRaid:SendCommMessage("GUILD", "I_IS_MASTER",
                                ZebRaidState.KarmaDB, state.RaidID, 
                                state.RegisteredUsers,
                                state.Lists);
    end
    -- If the broadcasting person is a UI Master, assume he reloaded, and release
    -- FIXME: Can I remove and iterate in the same loop? Would clarify code.
    local removeDBs = {};
    for db, val in pairs(ZebRaid.UIMasters) do
        if val == sender then
            table.insert(removeDBs, db);
        end
    end
    
    for pos, db in pairs(removeDBs) do
        ZebRaid.UIMasters[db] = nil;
        if ZebRaidState.KarmaDB == db then
            ZebRaid:LockUI();
        end
    end
    
    self:SendCommMessage("WHISPER", sender, "ACKNOWLEDGE");
	]]--
end

-- Sent from the addons receiving a BROADCAST to the sender of the BROADCAST.
-- We use it to learn their history.
function ZebRaid.OnCommReceive.ACKNOWLEDGE(self, prefix, sender, distribution)
    self:Debug("Received ACKNOWLEDGE from " .. sender);
end

-- Sent by an instance to tell others that it is becoming the master now.
function ZebRaid.OnCommReceive.I_IS_MASTER(self, prefix, sender, distribution, KarmaDB, RaidID, RegisteredUsers, Lists)
    DEFAULT_CHAT_FRAME:AddMessage(sender .. " is now the master for " .. KarmaDB .. ".");
    if (ZebRaidState.KarmaDB == KarmaDB) then
        ZebRaid:LockUI();
    end
    ZebRaidState[KarmaDB] = {
        RaidID = RaidID,
        RegisteredUsers = RegisteredUsers,
        Lists = Lists,
    };
    
    ZebRaid.UIMasters[KarmaDB] = sender;
    
    if (ZebRaidState.KarmaDB == KarmaDB) then
        local state = ZebRaidState[KarmaDB];
        
        ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. state.RaidID);
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. sender);
        ZebRaid:ShowListMembers();
    end
end

function ZebRaid.OnCommReceive.ADD_TO_LIST(self, prefix, sender, distribution, KarmaDB, listName, name)
    self:Debug("Received ADD_TO_LIST(" .. listName .. ", " .. name .. ")");

    local state = ZebRaidState[KarmaDB];

    if state and state.Lists then
        local list = state.Lists[listName];
        
        if list then
            ZebRaid:AddToList(state, list, name);
        end
    end
end

function ZebRaid.OnCommReceive.REMOVE_FROM_LIST(self, prefix, sender, distribution, KarmaDB, listName, nameOrPos)
    self:Debug("Received REMOVE_FROM_LIST(" .. listName .. ", " .. nameOrPos .. ")");

    local state = ZebRaidState[KarmaDB];

    if state and state.Lists then
        local list = state.Lists[listName];

        if list then
            ZebRaid:RemoveFromList(state, list, nameOrPos);
        end
    end
end

function ZebRaid.OnCommReceive.CLOSE_RAID(self, prefix, sender, distribution, KarmaDB)
    self:Debug("Received CLOSE_RAID(" .. KarmaDB .. ")");

    local state = ZebRaidState[KarmaDB];

    if state then
        ZebRaid:DoCloseRaid(state);
    end
end
