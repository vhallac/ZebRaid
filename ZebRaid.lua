ZebRaid = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceDebug-2.0",
"AceDB-2.0", "AceEvent-2.0", "AceComm-2.0");
local L = AceLibrary("AceLocale-2.2"):new("ZebRaid");
local BC = AceLibrary("Babble-Class-2.2");
local RollCall = AceLibrary("RollCall-1.0");
local Roster = AceLibrary("Roster-2.1");

local options = {
    type = 'group',
    args = {
        start = {
            type = 'execute',
            name = 'Start planning the raid',
            desc = L["START_DIALOG"],
            func = function() ZebRaid:Start() end,
        },
    }
}

ZebRaid:RegisterChatCommand({"/zebraid", "/zebr"}, options);

local ON_TIME_KARMA_VAL = 5;
local MAX_NUM_BUTTONS = 100; -- See the ZebRaid.xml for this

-- Manifest constants will go here...
ZebRaid.Const = {
    -- Enumareated constants for player status changes in the raid history.
    NoChange = 0,
    SitoutAdded = 1,
    SitoutRemoved = 2,
    PenaltyAdded = 3,
    PenaltyRemoved = 4,
    SitoutRemovedForPenalty = 5,
}

local FreePlayerButton = 1; -- The button index that is available.
local ListNames = {
    "GuildList",
    "SignedUp",
    "Unsure",
    "Confirmed",
    "Reserved",
    "Penalty",
    "Sitout"
};

local StartWasCalled = nil;
local NeedRecalculateAfterUpdate = nil;
local PlayerName = nil;
local DraggingPlayer = nil;

ZebRaid.Lists = {};
ZebRaid.RegisteredUsers = {};

local RemotePlayer = nil;
local RemoteRaidIdList = nil;

ZebRaid.UiLockedDown = true;

-- Temprary set up for add-on comms handler
ZebRaid.OnCommReceive = {};

-- List of karma databases.
ZebRaid.KarmaList = {};

ZebRaid.PlayerStats = {};
ZebRaid.UIMasters = {};
ZebRaidState = {};

-------------------------------
-- UI and Ace Event Handlers --
-------------------------------

-- Called when the addon is loaded
function ZebRaid:OnInitialize()
    self:RegisterDB("ZebRaidDB"); -- We don't use it - just want the standby to work
	self:UnregisterAllEvents();
	self:UnregisterAllComms();
    self:SetDebugging(false);

    -- The commands we expect to see. Memoization shrinks message sizes.
    local memoizations = {
        "BROADCAST",
        "ACKNOWLEDGE",
        "REQUESTHISTORY",
        "RAIDHISTORY",
        "REQUESTDETAILS",
        "RAIDDETAILS",
        "I_IS_MASTER",
        "ADD_TO_LIST",
        "REMOVE_FROM_LIST",
        "CLOSE_RAID"
    };
    -- The version in channel name is the protocol revision. It is increased
    -- when incompatible changes are made.
    self:SetCommPrefix("ZebRaid2");
    self:RegisterMemoizations(memoizations);

    -- First, make sure we have an initialized raid history
    if not ZebRaidHistory then
        ZebRaidHistory = {};
    end

    -- Construct a player sitout/penalty state out of the ZebRaidHistory
    self:BuildPlayerRaidStats();

    -- Now, add the current history to raid history (if it is not already there)
    if not ZebRaidHistory[ZebRaid.RaidID] then
        ZebRaidHistory[ZebRaid.RaidID] = {
            players = {}
        };
    end

    --
    -- Set up the Dialog Labels {{{
    --
    for i=1, 30 do
        getglobal("ZebRaidDialogPanelSignedUpSlot"..i.."Label"):SetText("---");
        getglobal("ZebRaidDialogPanelUnsureSlot"..i.."Label"):SetText("---");
        getglobal("ZebRaidDialogPanelConfirmedSlot"..i.."Label"):SetText("---");
        getglobal("ZebRaidDialogPanelReservedSlot"..i.."Label"):SetText("---");
        getglobal("ZebRaidDialogPanelGuildListSlot"..i.."Label"):SetText("---");
        if (i < 15) then
            getglobal("ZebRaidDialogPanelPenaltySlot"..i.."Label"):SetText("---");
            getglobal("ZebRaidDialogPanelSitoutSlot"..i.."Label"):SetText("---");
        end
    end

    --
    -- Set up the button texts according to locale
    --
    ZebRaidDialogCommandsAutoConfirm:SetText(L["AUTOCONFIRM"]);
    ZebRaidDialogCommandsReset:SetText(L["RESET"]);
    ZebRaidDialogCommandsGiveKarma:SetText(L["KARMA"]);
    ZebRaidDialogCommandsAnnounce:SetText(L["ANNOUNCE"]);
    ZebRaidDialogCommandsCloseRaid:SetText(L["CLOSERAID"]);
    ZebRaidDialogCommandsSync:SetText(L["SYNCH"]);
    ZebRaidDialogCommandsUnlock:SetText(L["UNLOCK"]);

    ZebRaidDialogConfirmedStatsTitle:SetText(L["CONFIRMED_STATS"]);
    ZebRaidDialogConfirmedStatsWarriors:SetTextColor(BC:GetColor("WARRIOR"));
    ZebRaidDialogConfirmedStatsDruids:SetTextColor(BC:GetColor("DRUID"));
    ZebRaidDialogConfirmedStatsPaladins:SetTextColor(BC:GetColor("PALADIN"));
    ZebRaidDialogConfirmedStatsRogues:SetTextColor(BC:GetColor("ROGUE"));
    ZebRaidDialogConfirmedStatsPriests:SetTextColor(BC:GetColor("PRIEST"));
    ZebRaidDialogConfirmedStatsMages:SetTextColor(BC:GetColor("MAGE"));
    ZebRaidDialogConfirmedStatsShamans:SetTextColor(BC:GetColor("SHAMAN"));
    ZebRaidDialogConfirmedStatsWarlocks:SetTextColor(BC:GetColor("WARLOCK"));
    ZebRaidDialogConfirmedStatsHunters:SetTextColor(BC:GetColor("HUNTER"));
    ZebRaidDialogConfirmedStatsTotal:SetTextColor(1, .6, 0);

    ZebRaidDialogTotalStatsTitle:SetText(L["TOTAL_STATS"]);
    ZebRaidDialogTotalStatsWarriors:SetTextColor(BC:GetColor("WARRIOR"));
    ZebRaidDialogTotalStatsDruids:SetTextColor(BC:GetColor("DRUID"));
    ZebRaidDialogTotalStatsPaladins:SetTextColor(BC:GetColor("PALADIN"));
    ZebRaidDialogTotalStatsRogues:SetTextColor(BC:GetColor("ROGUE"));
    ZebRaidDialogTotalStatsPriests:SetTextColor(BC:GetColor("PRIEST"));
    ZebRaidDialogTotalStatsMages:SetTextColor(BC:GetColor("MAGE"));
    ZebRaidDialogTotalStatsShamans:SetTextColor(BC:GetColor("SHAMAN"));
    ZebRaidDialogTotalStatsWarlocks:SetTextColor(BC:GetColor("WARLOCK"));
    ZebRaidDialogTotalStatsHunters:SetTextColor(BC:GetColor("HUNTER"));
    ZebRaidDialogTotalStatsTotal:SetTextColor(1, .6, 0);

    --
    -- Hide all player buttons
    --
    for i=1, MAX_NUM_BUTTONS do
        local button = getglobal("ZebRaidDialogButton" .. i);
        button:ClearAllPoints();
        button:Hide();
    end

    --
    -- Prepare the popup dialog
    --
    StaticPopupDialogs["ZEBRAID_SHOW_UNKNOWN_RAIDS"] = {
        text = L["SYNCHCONFIRMATION"],
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(data)
            for pos, val in pairs(data.raidIdList) do
                if not ZebRaidHistory[val] then
                    ZebRaid:SendCommMessage("WHISPER", data.sender, "REQUESTDETAILS", val);
                end
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1
    };

    StaticPopupDialogs["ZEBRAID_CONFIRM_REMOTE_CLOSE"] = {
        text = L["CLOSECONFIRMATION"],
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(data)
            ZebRaid:DoCloseRaid(data);
            self:SendCommMessage("GUILD", "CLOSE_RAID", ZebRaidState.KarmaDB);
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1
    };

end

function ZebRaid:OnEnable()
    PlayerName, _ = UnitName("player");

    self:RegisterEvent("RollCall10_MemberDisconnected");
    self:RegisterEvent("RollCall10_MemberConnected");
    self:RegisterEvent("RollCall10_MemberAdded");
    self:RegisterEvent("RollCall10_MemberRemoved");
    self:RegisterEvent("RollCall10_Updated");
    self:RegisterEvent("RosterLib_RosterUpdated");

    if not UnitInRaid("player") then
        ZebRaidDialogCommandsInviteRaid:SetText(L["START_RAID"]);
    else
        ZebRaidDialogCommandsInviteRaid:SetText(L["INVITE_REST"]);
    end

    -- Get ready to receive add-on comms
    self:RegisterComm("ZebRaid2", "GUILD");
    self:RegisterComm("ZebRaid2", "WHISPER");

    -- Start off with interface locked.
    self:LockUI();

    -- select the indicated karma DB when appropriate:
    -- i.e. when we have a DB selected, and the raid is not closed.
    if ZebRaidState.KarmaDB and ZebRaidState[ZebRaidState.KarmaDB] then
        local raidId = ZebRaidState[ZebRaidState.KarmaDB].RaidID;
        if Karma_command and
           ( not ZebRaidHistory[raidId] or
             not ZebRaidHistory[raidId].RaidClosed )
        then
            Karma_command("use " .. ZebRaidState.KarmaDB);
        end
    end

    -- Tell the rest of the guild that we are here.
    self:SendCommMessage("GUILD", "BROADCAST");
end

function ZebRaid:OnDisable()
    -- Hide the main dialog
    ZebRaidDialog:Hide();

    -- Stop responding to stuff
	self:UnregisterAllEvents();
	self:UnregisterAllComms();
end

function ZebRaid:ParseLocalRaidData()
    for _,val in pairs(ZebRaid.Signups) do
        self:Debug("Value: " .. val);
        local name, status, roll, note =
            select(3, val:find("^([^:]+):([^:]+):([^:]+):?(.*)"));

        local list = nil;

        if status == "signed" then
            list = "SignedUp";
        elseif status == "unsure" then
            list = "Unsure";
        end

        if note == "" then
            note = nil;
        end

        if RollCall:HasMember(name) then
            -- If we didn't gkick the user since sign-up, add him to the RegisteredUsers table
            self.RegisteredUsers[name] = {
                status = status,
                list = list,
                roll = roll,
                note = note
            };
        end
    end
end

function ZebRaid:Start()
    self:Debug("ZebRaid:Start");

    if not self:IsActive() then return; end
    
    if StartWasCalled then
        StartWasCalled = nil;
        ZebRaidDialog:Hide();
        return;
    end

    if ZebRaidState.KarmaDB then
        local raidId = nil;
        if ZebRaidState[ZebRaidState.KarmaDB] then 
            raidId = ZebRaidState[ZebRaidState.KarmaDB].RaidID;
        end
        
        if raidId and ZebRaidHistory[raidId] and ZebRaidHistory[raidId].RaidClosed then
            ZebRaidDialogReportMaster:SetText(L["REPORT_RAID_CLOSED"]);
        elseif not self.UIMasters[ZebRaidState.KarmaDB] then
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"]);
        elseif self.UIMasters[ZebRaidState.KarmaDB] == PlayerName then
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"]);
        else
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. self.UIMasters[ZebRaidState.KarmaDB]);
        end
        
        if not self.PlayerStats[ZebRaidState.KarmaDB] then
            self.PlayerStats[ZebRaidState.KarmaDB] = {};
        end
    end

    --
    -- If we are not the master or we do not know the master of a list,
    -- and if the DB's raid ID does not match our current raid ID, then
    -- remove the state for that DB.
    --
    for db, val in pairs(ZebRaidState) do
        if (not self.UIMasters[db]) and
           (val.RaidID ~= self.RaidID)
        then
            self:Debug("Erasing db state " .. db);
            ZebRaidState[db] = nil;
        end
    end
    
    if ZebRaid:Count(self.KarmaList)==0 and KarmaList then
        -- Copy the Karma database names
        for db, val in pairs(KarmaList) do
            table.insert(self.KarmaList, db);
        end        
    end
    
    --
    -- Parse the signup list
    --
    if ( not self.RegisteredUsers ) or
       ( ZebRaid:Count(self.RegisteredUsers) == 0 ) then
        self:ParseLocalRaidData();
    end

    if ZebRaidState.KarmaDB and
       ZebRaidState[ZebRaidState.KarmaDB]
    then
        local state = ZebRaidState[ZebRaidState.KarmaDB];
        --
        -- Fill the lists out according to online and registered users
        --
        self:InitializeListContents(state);
    end
    
    -- Display the current setup
    local raidID = ZebRaid.RaidID;
    if ZebRaidState.KarmaDB and
       ZebRaidState[ZebRaidState.KarmaDB] and
       ZebRaidState[ZebRaidState.KarmaDB].RaidID
    then
        raidID = ZebRaidState[ZebRaidState.KarmaDB].RaidID;
    end
    
    ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidID);
    self:ShowListMembers();
    
    StartWasCalled = true;

    ZebRaidDialog:Show();
end

function ZebRaid:AddButtonToList(list, button)
    -- Place the button in its list
    button:ClearAllPoints();
    local slot = getglobal("ZebRaidDialogPanel" .. list.name ..
                           "Slot" .. list.freeSlot);
    if slot == nil then
        button:ClearAllPoints();
        button:Hide();
        return;
   end
    button:SetPoint("TOP", slot);
    button:SetHitRectInsets(0, 0, 0, 0);
    button:SetFrameLevel(slot:GetFrameLevel() + 20);
    button:RegisterForDrag("LeftButton");
    button.inList = list;
    list.freeSlot = list.freeSlot + 1;
    button:Show();
end

local movingButtonLevel;

function ZebRaid:PlayerOnDragStart()
    self:Debug("PlayerOnDragStart");

    movingButtonLevel = this:GetFrameLevel();
    if self.UiLockedDown then return; end

    local cursorX, cursorY = GetCursorPosition();
    DraggingPlayer = true;
    this:StartMoving();
    this:SetFrameLevel(movingButtonLevel + 30);
end

function ZebRaid:PlayerOnDragStop()
    self:Debug("PlayerOnDragStop");

    this:SetFrameLevel(movingButtonLevel);
    this:StopMovingOrSizing();

    if self.UiLockedDown then self:ShowListMembers(); return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];
    
    local selectedList = nil;
    for list, _ in pairs(state.Lists) do
        if MouseIsOver(getglobal("ZebRaidDialogPanel" .. list )) then
            selectedList = list;
            break;
        else
            for slot=1,30 do
                local slotFrame = getglobal("ZebRaidDialogPanel" .. list ..  "Slot" .. slot);
                if slotFrame and MouseIsOver(slotFrame) then
                    selectedList = list
                    break;
                end
            end
        end
        if selectedList then break; end
    end
    self:Debug("MouseIsOver: " .. (selectedList or "nothing"));

    local list;
    if selectedList then
        list = state.Lists[selectedList];
    else
        list = this.inList;
    end

    -- FIXME: Implement more logic to prevent weird moves:
    -- Rules I can think of are below.

    -- Not signed up or unsigned => Cannot go to SignedUp, Unsure, Penalty, or
    --                              Sitout
    if not state.RegisteredUsers[this.player] or
       not state.RegisteredUsers[this.player].list
    then
        if ( selectedList == "Penalty" or
             selectedList == "Sitout" or
             selectedList == "SignedUp" or
             selectedList == "Unsure")
        then
            list = this.inList;
        end
    else
        -- Unsure => Cannot go to Penalty
        if ( selectedList == "Penalty" and
             state.RegisteredUsers[this.player].list == "Unsure")
        then
            list = this.inList;
        end

        -- SignedUp or Unsure cannot go back to guild
        if ( state.RegisteredUsers[this.player] and
             state.RegisteredUsers[this.player].list and
             selectedList == "GuildList" )
        then
            list = this.inList;
        end

        -- SignedUp and Unsure cannot go each other
        if ( ( selectedList == "SignedUp" or
               selectedList == "Unsure" ) and
               state.RegisteredUsers[this.player].list ~= selectedList)
        then
            list = this.inList;
        end
    end

    if list ~= this.inList then
        -- Remove from the old one
        self:RemoveFromList(state, this.inList, this.player);
        self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, this.inList.name, this.player);

        -- Insert to new list
        -- If player is offline, and the target list is online list, then
        -- do not add to the target list.
        if list.name ~= "GuildList" or
           RollCall:IsMemberOnline(this.player)
        then
            self:AddToList(state, list, this.player);
            self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, list.name, this.player);
        end

    end

    DraggingPlayer = nil;

    self:ShowListMembers();
end

function ZebRaid:PlayerOnDoubleClick()
    self:Debug("ZebRaid:OnDoubleClick");

    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];
    local list = ZebRaid:FindTargetList(this.inList, this.player);

    if list then
        -- Remove from the old one
        self:RemoveFromList(state, this.inList, this.player);
        self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, this.inList.name, this.player);

        -- Insert to new list
        -- If player is offline, and the target list is online list, then
        -- do not add to the target list.
        if list.name ~= "GuildList" or
           RollCall:IsMemberOnline(this.player)
        then
            self:AddToList(state, list, this.player);
            self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, list.name, this.player);
        end

        self:ShowListMembers();
    end
end

function ZebRaid:RollCall10_MemberConnected(name)
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end

    if RollCall:GetLevel(name) ~= 70 then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];
    
    if not state or not state.Lists then return; end
    
    local found = nil;

    for listName, list in pairs(state.Lists) do
        for i, val in pairs(list.members) do
            if val == name then
                found = true;
            end
        end
    end

    if not found then
        self:AddToList(state, state.Lists["GuildList"], name);
        -- FIXME: Should be unneeded. Double check.
        -- self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, "GuildList", name);
    end

    NeedRecalculateAfterUpdate = true;
end

function ZebRaid:RollCall10_MemberDisconnected(name)
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end

    self:RemoveFromList(state, state.Lists["GuildList"], name);
    -- FIXME: Should not be necessary. Double check
    -- self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, "GuildList", name);

    -- We either removed a user, or need to update the background color
    -- of a user. Update it.
    NeedRecalculateAfterUpdate = true;
end

function ZebRaid:RollCall10_MemberAdded(name)
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end


    -- Do we need to do anything here? He'll come online, and we'll process
    -- him.
end

function ZebRaid:RollCall10_MemberRemoved(name)
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end

    local changed = nil;

    for listName, list in pairs(state.Lists) do
        for i, val in pairs(list.members) do
            if val == name then
                self:RemoveFromList(state, list, i);
                self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, list.name, i);
                
                changed = true;
                break;
            end
        end
    end

    if changed then
        NeedRecalculateAfterUpdate = true;
    end
end

function ZebRaid:RollCall10_Updated()
    if not StartWasCalled then return; end

    if self.UiLockedDown then return; end

    if NeedRecalculateAfterUpdate then
        self:ShowListMembers();
        NeedRecalculateAfterUpdate = nil;
    end
end

local DoingFirstInvite = nil;

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

    --[[
    if DoingFirstInvite then
        -- Invite the rest from here only on the first invite.
        -- This function will be called again for each player accepting 
        -- the invite.
        self:Debug("Inviting the rest")
        DoingFirstInvite = false;
        self:InviteRemaining();
    end
    ]]
end

function ZebRaid:InviteConfirmed()

    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end

    if (ZebRaid:Count(state.Lists["Confirmed"].members) == 0) then return; end

    if (GetNumPartyMembers() < 2 and not UnitInRaid("player")) then
        DoingFirstInvite = true;

        -- Find first eligible member to invite.
        invitePos = 0;
        local list = state.Lists["Confirmed"];

        for pos = 1,ZebRaid:Count(list.members) do
            local name = list.members[pos];
            if  name ~= PlayerName and RollCall:IsMemberOnline(name) then
                invitePos = pos;
                break;
            end
        end

        if (invitePos == 0) then return; end

        self:Debug("Inviting first player: " .. list.members[invitePos]);
        InviteUnit(list.members[invitePos]);

        ZebRaidDialogCommandsInviteRaid:SetText(L["INVITE_REST"]);
    elseif not UnitInRaid("player") then
        -- We're in a party, but not in a raid. Convert to raid,
        -- and change the button to allow inviting the rest of the poeple
        ConvertToRaid();
        ZebRaidDialogCommandsInviteRaid:SetText(L["INVITE_REST"]);
    else
        self:Debug("Inviting Others");
        self:InviteRemaining();
    end
end

function ZebRaid:InviteRemaining()
    local state = ZebRaidState[ZebRaidState.KarmaDB];

    for _, name in pairs(state.Lists["Confirmed"].members) do
        if name ~= PlayerName and
           not ( UnitInParty("player") or UnitInRaid("player") ) or
           not Roster:GetUnitIDFromName(name)
        then
            self:Debug("Inviting: " .. name);
            InviteUnit(name);
        end
    end
end

local LastUpdateTime = GetTime();

function ZebRaid:OnUpdate()
    -- If we call ShowListMembers() too often, the UI becomes unresponsive.
    -- e.g. resisting drag-drop attempts.
    -- TODO: Optimize the loop.
    if not DraggingPlayer and (GetTime() - LastUpdateTime > 1) then
        self:ShowListMembers();
        LastUpdateTime = GetTime();
    end
end

function ZebRaid:AutoConfirm()

    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end

    local listFrom = state.Lists["SignedUp"];

    local movePos = {};

    pos = 1;
    self:Debug("pos: " .. pos .. "listCount: " .. ZebRaid:Count(listFrom.members));
    while pos <= ZebRaid:Count(listFrom.members) do
        self:Debug("pos: " .. pos .. "listCount: " .. ZebRaid:Count(listFrom.members));
        local name = listFrom.members[pos];

        if (RollCall:IsMemberOnline(name)) then
            local listTo = self:FindTargetList(listFrom, name);

            if listTo then
                self:RemoveFromList(state, listFrom, pos);
                self:SendCommMessage("GUILD", "REMOVE_FROM_LIST", ZebRaidState.KarmaDB, listFrom.name, pos);
                self:AddToList(state, listTo, name);
                self:SendCommMessage("GUILD", "ADD_TO_LIST", ZebRaidState.KarmaDB, listTo.name, name);
            end
        else
            pos = pos + 1;
        end
    end

    self:ShowListMembers();
end

function ZebRaid:Announce()
    if self.UiLockedDown then return; end    
    
    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end

    local list = state.Lists["Sitout"];
    
    local message = "";
    
    if ZebRaid:Count(list.members) > 0 then
        for pos, name in pairs(list.members) do
            message = message .. name;
            if pos ~= ZebRaid:Count(list.members) then
                message = message .. ", ";
            else
                message = message .. ".";
            end
        end
        
    -- FIXME: Add note for raid karma db name (perhaps): T5SE may not mean for guildies.
        SendChatMessage("--------------------\r\n" ..
                        L["SITOUT_ANNOUNCE_MSG"] .. "\r\n" ..
                        message .. "\r\n" ..
                        "--------------------", "GUILD");
--[[
        SendChatMessage(L["SITOUT_ANNOUNCE_MSG"], "GUILD");
        SendChatMessage(message, "GUILD");
        SendChatMessage("--------------------", "GUILD");
        ]]
    end
end

function ZebRaid:GiveKarma()
    if self.UiLockedDown then return; end

    local state = ZebRaidState[ZebRaidState.KarmaDB];
    
    if not state.RaidHistoryEntry.KarmaGiven then
        -- If we can give karma ...
        if not Karma_Add_Player then
            DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_ADDON"]);
            return;
        end

        if not KarmaConfig["CURRENT RAID"] then
            DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DB"]);
            return;
        end

        local state = ZebRaidState[ZebRaidState.KarmaDB];

        if not state or not state.Lists then return; end
        
        -- Give on time karma to all Confirmed and Sitout users.
        for pos, name in pairs(state.Lists["Confirmed"].members) do
            -- Only confirmed people who are in raid deserve online karma. :-)
            if Roster:GetUnitIDFromName(name) then
                Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P");
            end
        end

        for pos, name in pairs(state.Lists["Sitout"].members) do
            Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P");
        end

        state.RaidHistoryEntry.KarmaGiven = true;    
    else
        DEFAULT_CHAT_FRAME:AddMessage(L["KARMA_GIVEN"]);
        return;
    end
end

function ZebRaid:CloseRaid()
    if self.UiLockedDown then return; end
    
    if not ZebRaidState.KarmaDB then return; end
   
    local state = ZebRaidState[ZebRaidState.KarmaDB];

    if not state or not state.Lists then return; end
    
    -- Make sure users really wants to close someone else's raid.
    if state.RaidID ~= self.RaidID then
        -- DoCloseRaid() will be called by the dialog "yes" handler.
        local dialog = StaticPopup_Show("ZEBRAID_CONFIRM_REMOTE_CLOSE", sender, raidListStr);
        if dialog then
            dialog.data = state;
        end
    else
        self:DoCloseRaid(state);
        self:SendCommMessage("GUILD", "CLOSE_RAID", ZebRaidState.KarmaDB);
    end
end

function ZebRaid:DoCloseRaid(state)
    state.RaidHistoryEntry.RaidClosed = true;
    state.RaidHistoryEntry.RaidCloseTime = date("%x");    
    
    local karmaDB = state.RaidHistoryEntry.KarmaDB;

    if (karmaDB == ZebRaidState.KarmaDB) then
        ZebRaidDialogReportMaster:SetText(L["REPORT_RAID_CLOSED"]);
        self.LockUI();
    end
    
    local playerStats = self.PlayerStats[karmaDB];
    
    ZebRaidHistory[state.RaidID] = state.RaidHistoryEntry;
    
    -- Create history changes for the sitout table
    for _, name in pairs(state.Lists["Sitout"].members) do
        if not state.RaidHistoryEntry.players[name] then
            state.RaidHistoryEntry.players[name] = {};
        end

        local histEntry = state.RaidHistoryEntry.   players[name];
        local stats = playerStats[name];

        -- Sitout table. If the player has outstanding penalties, remove one.
        -- Otherwise, give a sitout.
        if stats and stats.penalties > 0 then
            histEntry.change = ZebRaid.Const.PenaltyRemoved;
        else
            histEntry.change = ZebRaid.Const.SitoutAdded;
        end
    end
    
    -- Create history changes for the sitout table
    for _, name in pairs(state.Lists["Penalty"].members) do
        if not state.RaidHistoryEntry.players[name] then
            state.RaidHistoryEntry.players[name] = {};
        end

        local histEntry = state.RaidHistoryEntry.players[name];
        local state = ZebRaidState[karmaDB];
        local stats = playerStats[name];

        -- Penalty table. If the player has oustanding sitouts, remove one.
        -- Otherwise, give a penalty
        if stats and stats.sitouts > 0 then
            histEntry.change = ZebRaid.Const.SitoutRemovedForPenalty;
        else
            histEntry.change = ZebRaid.Const.PenaltyAdded;
        end
    end
    
    for _, name in pairs(state.Lists["Confirmed"].members) do
        if not state.RaidHistoryEntry.players[name] then
            state.RaidHistoryEntry.players[name] = {};
        end

        local histEntry = state.RaidHistoryEntry.players[name];
        local state = ZebRaidState[karmaDB];
        local stats = playerStats[name];

        -- If the user is registerd, and added to raid, then remove a sitout
        if  state.RegisteredUsers[name] and
            stats and stats.sitouts > 0
        then
            histEntry.change = ZebRaid.Const.SitoutRemoved;
        end
    end
end

function ZebRaid:InitializeListContents(state)
    state.Lists = {};
        
    -- Create the lists (throw old ones away)
    for _, list in pairs(ListNames) do
        state.Lists[list] = self:NewList(list);
    end
    

    for name, val in pairs(state.RegisteredUsers) do
        local histEntry = state.RaidHistoryEntry.players[name];

        -- If the user is saved in a list, use that list
        if histEntry and histEntry.listName then
            list = histEntry.listName;
        else
            list = val.list;
        end

        if list then
            self:AddToList(state, state.Lists[list], name);
        end
    end

    -- Populate the guild list with online users
    -- They need to be lvl 70, and not signed up yet.
    for name in RollCall:GetIterator("NAME", false) do
        if (RollCall:GetLevel(name) == 70 and
            not (state.RegisteredUsers[name] and
                 state.RegisteredUsers[name].list))
        then
            local histEntry = state.RaidHistoryEntry.players[name];
            local list = "GuildList";

            if histEntry and histEntry.listName then
                list = histEntry.listName;
            end

            self:AddToList(state, state.Lists[list], name);
        end
    end
end

function ZebRaid:Reset()
    self:Debug("ZebRaid:Reset");
    
    if self.UiLockedDown then return; end
    if not self:IsActive() then return; end
    
    local state = ZebRaidState[ZebRaidState.KarmaDB];

    -- Clean up the raid history entry for current raid
    state.RaidHistoryEntry = {
        players = {},
        KarmaDB = ZebRaidState.KarmaDB
    };

    self:InitializeListContents(state);
    self:SendCommMessage("GUILD", "I_IS_MASTER",
                         ZebRaidState.KarmaDB, state.RaidID,
                         state.RegisteredUsers, state.RaidHistoryEntry,
                         state.Lists);
    self:ShowListMembers();
end

function ZebRaid:RaidSelection_OnShow()
	if not self.initSortDropDown then
		UIDropDownMenu_Initialize(this, function() self:RaidSelection_Populate() end)
		self.initSortDropDown = true
	end
end

function ZebRaid:RaidSelection_Populate()
	local info;
    local dbList = {};
        
    if self.KarmaList then
        for db, val in pairs(self.KarmaList) do
            table.insert(dbList, val);
        end
    end
    
	for pos, name in pairs(dbList) do
		info = UIDropDownMenu_CreateInfo()
        info.value = pos;
        info.owner = this:GetParent();
		info.text = name;
		info.func = function() ZebRaid:RaidSelection_OnClick(); end
		UIDropDownMenu_AddButton(info);
        if name == ZebRaidState.KarmaDB then
        	UIDropDownMenu_SetSelectedValue(ZebRaidDialogRaidSelection, pos);
        end
	end
end

function ZebRaid:RaidSelection_OnClick()
    self:Debug("ZebRaid:RaidSelection_OnClick: " .. this:GetText() .. ", " .. this.value);
    
    UIDropDownMenu_SetSelectedValue(this.owner, this.value);
    local karmaDB=this:GetText();
    ZebRaidState.KarmaDB = karmaDB;
    if Karma_command then
        Karma_command("use " .. karmaDB);
    end
    
    if not ZebRaidState[karmaDB] then
        -- Usually constructed from the Raid History, but if no history for this raid exists,
        -- we create it here.
        ZebRaidState[karmaDB] = {};
    end
    
    local state = ZebRaidState[karmaDB];
    
    if not self.PlayerStats then
        self.PlayerStats = {}
    end

    if not self.PlayerStats[karmaDB] then
        self.PlayerStats[karmaDB] = {}
    end

    -- Recalculate RaidHistoryEntry here.
    if not state.RaidHistoryEntry then
        state.RaidHistoryEntry = {
            players = {},
            KarmaDB = karmaDB
        };
    end
    
    if ( not state.RegisteredUsers ) or
       ( ZebRaid:Count(state.RegisteredUsers) == 0 )
    then
        self:Debug("Updating registered users for " .. karmaDB)
        state.RaidID = self.RaidID;
        state.RegisteredUsers = self.RegisteredUsers;
        self:InitializeListContents(state);
    end    

    -- Recalculate the Guild list: all online members that are not in other lists go to guild list.
    
    
    -- Display the current setup
    self:ShowListMembers();

    local raidId = state.RaidID;
    
    if raidId and ZebRaidHistory[raidId] and ZebRaidHistory[raidId].RaidClosed then
        ZebRaidDialogReportMaster:SetText(L["REPORT_RAID_CLOSED"]);
        self:LockUI();
    elseif not self.UIMasters[karmaDB] then
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"]);
        self:LockUI();
    elseif (self.UIMasters[karmaDB] == PlayerName) then
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"]);
        self:UnlockUI();
    else
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. self.UIMasters[karmaDB]);
        self:LockUI();
    end
    
    ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. state.RaidID);
end

----------------------
-- Helper Functions --
----------------------

-- Add/modify the player statistics according to a raid history entry.
function ZebRaid:AddPlayerRaidStats(id, tbl)
    if not tbl.players then return; end
    
    if not ZebRaidState[tbl.KarmaDB] then
        ZebRaidState[tbl.KarmaDB] = {};
    end

    local state = ZebRaidState[tbl.KarmaDB];
    
    if not self.PlayerStats then
        self.PlayerStats = {};
    end

    if not self.PlayerStats[tbl.KarmaDB] then
        self.PlayerStats[tbl.KarmaDB] = {};
    end
    
    local playerStats = self.PlayerStats[tbl.KarmaDB];
    
    for player, val in pairs(tbl.players) do
        if val.change and val.change ~= ZebRaid.Const.NoChange then            
            
            if not playerStats[player] then
                playerStats[player] = {
                    penalties = 0,
                    sitouts = 0,
                    totalPenalties = 0,
                    totalSitouts = 0
                };
            end

            local stats = playerStats[player];

            if val.change == ZebRaid.Const.SitoutAdded then
                stats.sitouts = stats.sitouts + 1;
                stats.totalSitouts = stats.totalSitouts + 1;
            elseif val.change == ZebRaid.Const.SitoutRemoved then
                stats.sitouts = stats.sitouts - 1;
            elseif val.change == ZebRaid.Const.SitoutRemovedForPenalty then
                stats.sitouts = stats.sitouts - 1;
                stats.totalPenalties = stats.totalPenalties + 1;
            elseif val.change == ZebRaid.Const.PenaltyAdded then
                stats.penalties = stats.penalties + 1;
                stats.totalPenalties = stats.totalPenalties + 1;
            elseif val.change == ZebRaid.Const.PenaltyRemoved then
                stats.penalties = stats.penalties - 1;
                stats.totalSitouts = stats.totalSitouts + 1;
            end
        end
    end
end

-- Create a table of players with their penalty/sitout statistics
function ZebRaid:BuildPlayerRaidStats()
    for id, tbl in pairs(ZebRaidHistory) do
        -- Do not add the saved state of current raid to member statistics yet.
        -- The statistics is for *past* raids.
        if tbl.RaidClosed then
            self:AddPlayerRaidStats(id, tbl);
        end
    end
end

-- Find a list position in the list members where a new player should be
-- inserted according to its class. The list must already be sorted by class.
function ZebRaid:FindClassInsertPos(list, name)
    local playerClass = RollCall:GetClass(name);
    local foundClassStart = nil;
    local insertPos = nil;
    for pos, val in pairs(list.members) do
        if RollCall:GetClass(val) == playerClass then
            foundClassStart = true;
        end
        if foundClassStart and RollCall:GetClass(val) ~= playerClass then
            insertPos = pos;
            break;
        end
    end

    return insertPos;
end

function ZebRaid:ShowListMembers()
    local buttonNo = 1;
    local confirmedCounts = {
        ["Warrior"] = 0,
        ["Druid"] = 0,
        ["Paladin"] = 0,
        ["Rogue"] = 0,
        ["Priest"] = 0,
        ["Mage"] = 0,
        ["Shaman"] = 0,
        ["Warlock"] = 0,
        ["Hunter"] = 0
    };
    local totalCounts = {
        ["Warrior"] = 0,
        ["Druid"] = 0,
        ["Paladin"] = 0,
        ["Rogue"] = 0,
        ["Priest"] = 0,
        ["Mage"] = 0,
        ["Shaman"] = 0,
        ["Warlock"] = 0,
        ["Hunter"] = 0
    };

    -- If we haven't selected a list, or (for some reason) the
    -- selection has no state, then do not attempt to draw anything.
    if not ZebRaidState.KarmaDB or
       not ZebRaidState[ZebRaidState.KarmaDB]
    then
        self:UpdateCounts("ZebRaidDialogConfirmedStats", confirmedCounts);
        self:UpdateCounts("ZebRaidDialogTotalStats", totalCounts);
        ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] .. " (0)");
        ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] .. " (0)");
        ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] .. " (0)");
        ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] .. " (0)");
        ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] .. " (0)");
        ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] .. " (0)");
        ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] .. " (0)");
        return;
    end
    
    local state = ZebRaidState[ZebRaidState.KarmaDB]
    
    -- FIXME: I've been burnt by table.getn before. If the counts are ever incorrect, 
    -- use ZebRaid:Count() instead.
    ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] ..
        " (" .. table.getn(state.Lists["SignedUp"].members) .. ")");
    ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] ..
        " (" .. table.getn(state.Lists["Unsure"].members) .. ")");
    ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] ..
        " (" .. table.getn(state.Lists["Confirmed"].members) .. ")");
    ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] ..
        " (" .. table.getn(state.Lists["Reserved"].members) .. ")");
    ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] ..
        " (" .. table.getn(state.Lists["GuildList"].members) .. ")");
    ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] ..
        " (" .. table.getn(state.Lists["Penalty"].members) .. ")");
    ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] ..
        " (" .. table.getn(state.Lists["Sitout"].members) .. ")");

    for listName, list in pairs(state.Lists) do
        if (buttonNo > MAX_NUM_BUTTONS) then
            -- Too many players. We cannot show them all.
            -- Silently ignore the problem.
            break;
        end

        list.freeSlot = 1;

        for _, name in pairs(list.members) do
            local button = getglobal("ZebRaidDialogButton" .. buttonNo);

            self:SetButtonRoll(button, list, name);
            self:SetButtonLabel(button, list, name);
            self:SetButtonColor(button, list, name);
            self:SetButtonTooltip(button, list, name);

            button.player = name;
            self:AddButtonToList(list, button);

            buttonNo = buttonNo + 1;

            if list.name == "Confirmed" then
                local engClass = BC:GetReverseTranslation(RollCall:GetClass(name));
                confirmedCounts[engClass] = confirmedCounts[engClass] + 1;
            elseif list.name == "Reserved" then
                local engClass = BC:GetReverseTranslation(RollCall:GetClass(name));
                totalCounts[engClass] = totalCounts[engClass] + 1;
            end
        end
    end

    --
    -- Hide remaining player buttons
    --
    for i=buttonNo, MAX_NUM_BUTTONS do
        local button = getglobal("ZebRaidDialogButton" .. i);
        button:ClearAllPoints();
        button:Hide();
    end

    for idx, val in pairs(totalCounts) do
        totalCounts[idx] = totalCounts[idx] + confirmedCounts[idx];
    end

    self:UpdateCounts("ZebRaidDialogConfirmedStats", confirmedCounts);
    self:UpdateCounts("ZebRaidDialogTotalStats", totalCounts);
end

function ZebRaid:SetButtonRoll(button, list, name)
    local buttonRoll = getglobal(button:GetName() .. "Roll");
    local stats = nil;
    local prefix = "";
    local state = ZebRaidState[ZebRaidState.KarmaDB]
    local stats = nil;
    
    if self.PlayerStats[ZebRaidState.KarmaDB] then
        stats = self.PlayerStats[ZebRaidState.KarmaDB][name];
    end

    if state.RegisteredUsers[name] then
        local data = state.RegisteredUsers[name];
        -- Display the roll of user on button only if the user is not
        -- unsigned. Currently we display the roll on tooltip for all
        -- users who has done something on the raid planner.
    
        if data.note then
            prefix = prefix .. "*";
        end

        if data.roll then
            buttonRoll:SetText(prefix .. data.roll);
        else
            buttonRoll:SetText("");
        end
    else
        buttonRoll:SetText("");
    end

    buttonRoll:SetTextColor(0.8, 0.8, 0);
    
    if stats then        
        if stats.sitouts > 0 then
            buttonRoll:SetTextColor(0, 0.8, 0);
        end

        if stats.penalties > 0 then
            buttonRoll:SetTextColor(0.8, 0, 0);
        end
    end    
end

function ZebRaid:SetButtonLabel(button, list, name)
    local buttonLabel = getglobal(button:GetName() .. "Label");
    local state = ZebRaidState[ZebRaidState.KarmaDB]
    local stats = nil;
    
    if self.PlayerStats[ZebRaidState.KarmaDB] then
        stats = self.PlayerStats[ZebRaidState.KarmaDB][name];
    end
    
    -- Put a * before the name if there is a note.
    -- Put a - before the name if the user has unsigned from the raid
    -- Put a + before the name if the player has outstanding sitouts
    -- Put a ! before the name if the player has outstanding penalties
    local prefix = "";
    if state.RegisteredUsers[name] then
        if state.RegisteredUsers[name].status == "unsigned" then
            prefix = prefix .. "x";
        end
    end
    if stats then
        if stats.sitouts > 0 then
            prefix = prefix .. "|cff00aa00+|r";
        end

        if stats.penalties > 0 then
            prefix = prefix .. "|cffff0000-|r";
        end
    end

    buttonLabel:SetText(prefix .. name);
    buttonLabel:SetTextColor(RollCall:GetClassColor(name));
end

function ZebRaid:SetButtonColor(button, list, name)
    local buttonColor = getglobal(button:GetName() .. "Color");
    if RollCall:IsMemberOnline(name) then
        if list.name == "Confirmed" and
           Roster:GetUnitIDFromName(name)
        then
            -- Confirmed and in raid player background color
            buttonColor:SetTexture(0.1, 0.3, 0.1);
        else
            -- Online player background color
            buttonColor:SetTexture(0.05, 0.05, 0.05);
        end
    else
        if list.name == "Confirmed" and
           Roster:GetUnitIDFromName(name)
        then
            -- Offline: Confirmed and in raid player background color
            buttonColor:SetTexture(0.2, 0.2, 0.1);
        else
            -- Offline player background color
            buttonColor:SetTexture(0.2, 0.1, 0.1);
        end

    end
end

function ZebRaid:SetButtonTooltip(button, list, name)
    local state = ZebRaidState[ZebRaidState.KarmaDB]

    -- Add the guild info to tooltip
    button.tooltipDblLine = {
        left = name,
        right = RollCall:GetClass(name)
    };

    button.tooltipText = "Rank: " .. RollCall:GetRank(name) .. "\n";
    if RollCall:GetNote(name) then
        button.tooltipText = button.tooltipText ..
                             RollCall:GetNote(name) .. "\n\n";
    else
        button.tooltipText = button.tooltipText .. "\n";
    end

    if not RollCall:IsMemberOnline(name) then
        button.tooltipText = button.tooltipText ..
                             "|cffff0000" .. L["PLAYER_OFFLINE"] .. "|r\n\n";
    end

    if state.RegisteredUsers[name] then
        local data = state.RegisteredUsers[name];

        -- Put a note on unsigned users
        if data.status == "unsigned" then
            button.tooltipText = button.tooltipText ..
                                 "|cffff0000" .. L["PLAYER_UNSIGNED"] .. "|r\n\n";
        end

        if data.note then
            button.tooltipText = button.tooltipText .. "\n";
            button.tooltipText = button.tooltipText ..
                                 "|cffffff00Note: " .. data.note .. "|r\n";
        end
    end

    -- Add sitout/penalty information to tooltip
    local stats = nil;
    
    if self.PlayerStats[ZebRaidState.KarmaDB] then
        stats = self.PlayerStats[ZebRaidState.KarmaDB][name];
    end

    if stats then        
        if stats.sitouts > 0 then
            button.tooltipText = button.tooltipText .. L["SITOUTS"] .. "|r: " .. stats.sitouts;
        elseif stats.penalties > 0 then
            button.tooltipText = button.tooltipText .. L["PENALTIES"] .. "|r: " .. stats.penalties;
        elseif stats.penalties == 0 and stats.sitouts == 0 then
            button.tooltipText = button.tooltipText .. L["NOOUTSTANDING"]
        end
        button.tooltipText = button.tooltipText .. " (|cff00ff00" ..
                             stats.totalSitouts .. "|r/|cffff0000" ..
                             stats.totalPenalties .. "|r)\n";
    end
end

function ZebRaid:UpdateCounts(panelName, counts)
    getglobal(panelName .. "Warriors"):SetText(L["WARRIORS"] .. ": " ..
                                               counts["Warrior"]);
    getglobal(panelName .. "Druids"):SetText(L["DRUIDS"] .. ": " ..
                                             counts["Druid"]);
    getglobal(panelName .. "Paladins"):SetText(L["PALADINS"] .. ": " ..
                                               counts["Paladin"]);
    getglobal(panelName .. "Rogues"):SetText(L["ROGUES"] .. ": " ..
                                             counts["Rogue"]);
    getglobal(panelName .. "Priests"):SetText(L["PRIESTS"] .. ": " ..
                                              counts["Priest"]);
    getglobal(panelName .. "Mages"):SetText(L["MAGES"] .. ": " ..
                                            counts["Mage"]);
    getglobal(panelName .. "Shamans"):SetText(L["SHAMANS"] .. ": " ..
                                              counts["Shaman"]);
    getglobal(panelName .. "Warlocks"):SetText(L["WARLOCKS"] .. ": " ..
                                               counts["Warlock"]);
    getglobal(panelName .. "Hunters"):SetText(L["HUNTERS"] .. ": " ..
                                              counts["Hunter"]);
    getglobal(panelName .. "Total"):SetText(L["TOTAL"]..": " ..
                                            counts["Warrior"] +
                                            counts["Druid"] +
                                            counts["Paladin"] +
                                            counts["Rogue"] +
                                            counts["Priest"] +
                                            counts["Mage"] +
                                            counts["Shaman"] +
                                            counts["Warlock"] +
                                            counts["Hunter"]);
end

function ZebRaid:LockUI()
    ZebRaid.UiLockedDown = true;
    ZebRaidDialogCommandsAutoConfirm:Disable();
    ZebRaidDialogCommandsReset:Disable();
    ZebRaidDialogCommandsGiveKarma:Disable();
    ZebRaidDialogCommandsAnnounce:Disable();
    ZebRaidDialogCommandsCloseRaid:Disable();
    ZebRaidDialogCommandsInviteRaid:Disable();
    ZebRaidDialogCommandsSync:Disable();
--    UIDropDownMenu_DisableDropDown(ZebRaidDialogRaidSelection);
    ZebRaidDialogCommandsUnlock:Enable();
end

function ZebRaid:UnlockUI()
    local state = ZebRaidState[ZebRaidState.KarmaDB];
    
    if not ZebRaidHistory[state.RaidID] or not ZebRaidHistory[state.RaidID].RaidClosed then
        ZebRaid.UiLockedDown = nil;
        ZebRaidDialogCommandsAutoConfirm:Enable();
        ZebRaidDialogCommandsReset:Enable();
        ZebRaidDialogCommandsGiveKarma:Enable();
        ZebRaidDialogCommandsAnnounce:Enable();
        ZebRaidDialogCommandsCloseRaid:Enable();
        ZebRaidDialogCommandsInviteRaid:Enable();
        ZebRaidDialogCommandsSync:Enable();
--        UIDropDownMenu_EnableDropDown(ZebRaidDialogRaidSelection);
        ZebRaidDialogCommandsUnlock:Disable();
    end
end

function ZebRaid:OnUnlock()
    local state = ZebRaidState[ZebRaidState.KarmaDB];
    
    if not state then 
        -- FIXME: Print an error message somewhere
        return;
    end

    if ZebRaidHistory[state.RaidID] and ZebRaidHistory[state.RaidID].RaidClosed then
        -- FIXME: An error message?
        return;
    end

    self.UIMasters[ZebRaidState.KarmaDB] = PlayerName;

    self:SendCommMessage("GUILD", "I_IS_MASTER",
                            ZebRaidState.KarmaDB, state.RaidID,
                            state.RegisteredUsers, state.RaidHistoryEntry,
                            state.Lists);
    self:UnlockUI();
    ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"]);
end

function ZebRaid:OnHide()
    StartWasCalled = nil;
end