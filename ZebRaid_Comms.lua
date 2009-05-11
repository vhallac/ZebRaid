local L = AceLibrary("AceLocale-2.2"):new("ZebRaid");

-- Sent by the addon to guild when it starts. Used for advertising its presence,
-- and learning the other instances of the addon.
function ZebRaid.OnCommReceive.BROADCAST(self, prefix, sender, distibution)
    self:Debug("Received BROADCAST from " .. sender);
    if not ZebRaid.UiLockedDown then
        local state = ZebRaidState[ZebRaidState.KarmaDB];

        ZebRaid:SendCommMessage("GUILD", "I_IS_MASTER",
                                ZebRaidState.KarmaDB, state.RaidID, 
                                state.RegisteredUsers, state.RaidHistoryEntry,
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
    
    self:SendCommMessage("WHISPER", sender, "REQUESTHISTORY");
    self:SendCommMessage("WHISPER", sender, "ACKNOWLEDGE");
end

-- Sent from the addons receiving a BROADCAST to the sender of the BROADCAST.
-- We use it to learn their history.
function ZebRaid.OnCommReceive.ACKNOWLEDGE(self, prefix, sender, distribution)
    self:Debug("Received ACKNOWLEDGE from " .. sender);
    self:SendCommMessage("WHISPER", sender, "REQUESTHISTORY");
end

-- Sent from a ZebRaid instance to us to discover our known raid history
-- We send back a RAIDHISTORY message containing the details for all the raid IDs
-- in out history, except the one we are working with right now.
-- TODO: A system to send the current raid. Scenario: I handle raid yesterday, and want to 
-- send the data without obtaining today's raid.
function ZebRaid.OnCommReceive.REQUESTHISTORY(self, prefix, sender, distribution)
    self:Debug("Received REQUESTHISTORY from " .. sender);
    local raidIdList = {};
    for id, val in pairs(ZebRaidHistory) do
        if val.RaidClosed then
            table.insert(raidIdList, id);
        end
    end
    self.Debug("Sending a list with " .. ZebRaid:Count(raidIdList) ..  "elements");
    self:SendCommMessage("WHISPER", sender, "RAIDHISTORY", raidIdList);
end

-- Sent as s response to REQUSTHISTORY. Contains a list of raid IDs in the
-- caller's raid history.
function ZebRaid.OnCommReceive.RAIDHISTORY(self, prefix, sender, distribution, raidIdList)
    self:Debug("Received RAIDHISTORY from " .. sender);
    local remoteRaidIdList = {};
    local first = true;
    local raidListStr = "";
    for pos, val in pairs(raidIdList) do
        self:Debug("Checking: " .. val);
        if not ZebRaidHistory[val] or not ZebRaidHistory[val].RaidClosed then
            self:Debug("Adding: " .. val);
            table.insert(remoteRaidIdList, val);
            if first then
                first = nil;
            else
                raidListStr = raidListStr .. ", ";
            end
            raidListStr = raidListStr .. val;
        end
    end
    if table.getn(remoteRaidIdList) > 0 then
        local dialog = StaticPopup_Show("ZEBRAID_SHOW_UNKNOWN_RAIDS", sender, raidListStr);
        if dialog then
            dialog.data = {
                raidIdList = remoteRaidIdList;
                sender = sender
            }
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(sender .. ": " .. L["NONEWRAIDDATA"]);
    end
end

-- Sent to discover what we know about a particular raid's history.
function ZebRaid.OnCommReceive.REQUESTDETAILS(self, prefix, sender, distribution, raidId)
    self:Debug("Received REQUESTDETAILS(" .. raidId .. ") from " .. sender);
    if ZebRaidHistory[raidId] then
        self:SendCommMessage("WHISPER", sender, "RAIDDETAILS", raidId, ZebRaidHistory[raidId]);
    end
end

-- Sent as a response to a REQUESTDETAILS message.
-- It contains the history data for the requested raid.
function ZebRaid.OnCommReceive.RAIDDETAILS(self, prefix, sender, distribution, raidId, history)
    self:Debug("Received RAIDDETAILS from " .. sender);

    if not ZebRaidHistory[raidId] then
        -- Record the raid details
        ZebRaidHistory[raidId] = history;
        -- and update the cached counts.
        ZebRaid:AddPlayerRaidStats(raidId, history);

        DEFAULT_CHAT_FRAME:AddMessage(L["RAIDADDED"] .. raidId);
    end
end

-- Sent by an instance to tell others that it is becoming the master now.
function ZebRaid.OnCommReceive.I_IS_MASTER(self, prefix, sender, distribution, KarmaDB, RaidID, RegisteredUsers, RaidHistory, Lists)
    DEFAULT_CHAT_FRAME:AddMessage(sender .. " is now the master for " .. KarmaDB .. ".");
    if (ZebRaidState.KarmaDB == KarmaDB) then
        ZebRaid:LockUI();
    end
    ZebRaidState[KarmaDB] = {
        RaidID = RaidID,
        RegisteredUsers = RegisteredUsers,
        RaidHistoryEntry = RaidHistory,
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

    local list = state.Lists[listName];
    
    if list then
        ZebRaid:AddToList(state, list, name);
    end
end

function ZebRaid.OnCommReceive.REMOVE_FROM_LIST(self, prefix, sender, distribution, KarmaDB, listName, nameOrPos)
    self:Debug("Received REMOVE_FROM_LIST(" .. listName .. ", " .. nameOrPos .. ")");

    local state = ZebRaidState[KarmaDB];

    local list = state.Lists[listName];

    if list then
        ZebRaid:RemoveFromList(state, list, nameOrPos);
    end
end

function ZebRaid.OnCommReceive.CLOSE_RAID(self, prefix, sender, distribution, KarmaDB)
    self:Debug("Received CLOSE_RAID(" .. KarmaDB .. ")");

    local state = ZebRaidState[KarmaDB];

    if state then
        ZebRaid:DoCloseRaid(state);
    end
end
