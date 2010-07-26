local addonName, addonTable = ...
ZebRaid = LibStub("AceAddon-3.0"):NewAddon("ZebRaid", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("ZebRaid", true)
local Guild = LibStub("LibGuild-1.0")
-- Allow objects access to addon functions
addonTable.ZebRaid = ZebRaid

local options = {
    name = "ZebRaid",
    handler = ZebRaid,
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

local ON_TIME_KARMA_VAL = 5
local MAX_NUM_BUTTONS = 100 -- See the ZebRaid.xml for this

local FreePlayerButton = 1 -- The button index that is available.
local ListNames = {
    "GuildList",
    "SignedUp",
    "Unsure",
    "Confirmed",
    "Reserved",
    "Penalty",
    "Sitout"
}

local StartWasCalled = nil
local NeedRecalculateAfterUpdate = nil
local PlayerName = nil
local DraggingPlayer = nil

ZebRaid.Lists = {}
ZebRaid.RegisteredUsers = {}

local RemotePlayer = nil
local RemoteRaidIdList = nil

ZebRaid.UiLockedDown = true

-- Player information
ZebRaidPlayerData = {}

-- Alt Tracker information
ZebRaidTrackerData = {}

-- Temprary set up for add-on comms handler
ZebRaid.OnCommReceive = {}

-- List of karma databases.
ZebRaid.KarmaList = {}

-- Saved variables
ZebRaidState = {}
ZebRaidPlayerData = {}



-------------------------------
-- UI and Ace Event Handlers --
-------------------------------

-- Called when the addon is loaded
function ZebRaid:OnInitialize()
    local libCfg = LibStub("AceConfig-3.0")
    if libCfg then
        libCfg:RegisterOptionsTable("ZebRaid", options, {"zebr", "zebraid"})
    end

    self:SetDebugging(false)

    --
    -- Set up the Dialog Labels
    --
    for i=1, 30 do
        getglobal("ZebRaidDialogPanelSignedUpSlot"..i.."Label"):SetText("---")
        getglobal("ZebRaidDialogPanelUnsureSlot"..i.."Label"):SetText("---")
        getglobal("ZebRaidDialogPanelConfirmedSlot"..i.."Label"):SetText("---")
        getglobal("ZebRaidDialogPanelReservedSlot"..i.."Label"):SetText("---")
        getglobal("ZebRaidDialogPanelGuildListSlot"..i.."Label"):SetText("---")
        if (i < 15) then
            getglobal("ZebRaidDialogPanelPenaltySlot"..i.."Label"):SetText("---")
            getglobal("ZebRaidDialogPanelSitoutSlot"..i.."Label"):SetText("---")
        end
    end

    --
    -- Set up the button texts according to locale
    --
    ZebRaidDialogCommandsAutoConfirm:SetText(L["AUTOCONFIRM"])
    ZebRaidDialogCommandsReset:SetText(L["RESET"])
    ZebRaidDialogCommandsGiveKarma:SetText(L["KARMA"])
    ZebRaidDialogCommandsAnnounce:SetText(L["ANNOUNCE"])
    ZebRaidDialogCommandsSync:SetText(L["SYNCH"])
    ZebRaidDialogCommandsUnlock:SetText(L["UNLOCK"])

    ZebRaidDialogGiveKarma:SetText(L["KARMA"])

    ZebRaidDialogConfirmedStatsTitle:SetText(L["CONFIRMED_STATS"])
    ZebRaidDialogConfirmedStatsTank:SetTextColor(self:GetClassColor("WARRIOR"))
    ZebRaidDialogConfirmedStatsMelee:SetTextColor(self:GetClassColor("ROGUE"))
    ZebRaidDialogConfirmedStatsHealer:SetTextColor(self:GetClassColor("PRIEST"))
    ZebRaidDialogConfirmedStatsRanged:SetTextColor(self:GetClassColor("MAGE"))
    ZebRaidDialogConfirmedStatsTotal:SetTextColor(1, .6, 0)

    ZebRaidDialogTotalStatsTitle:SetText(L["TOTAL_STATS"])
    ZebRaidDialogTotalStatsTank:SetTextColor(self:GetClassColor("WARRIOR"))
    ZebRaidDialogTotalStatsMelee:SetTextColor(self:GetClassColor("ROGUE"))
    ZebRaidDialogTotalStatsHealer:SetTextColor(self:GetClassColor("PRIEST"))
    ZebRaidDialogTotalStatsRanged:SetTextColor(self:GetClassColor("MAGE"))
    ZebRaidDialogTotalStatsTotal:SetTextColor(1, .6, 0)

    --
    -- Prepare the popup dialog
    --
    StaticPopupDialogs["ZEBRAID_SHOW_UNKNOWN_RAIDS"] = {
        text = L["SYNCHCONFIRMATION"],
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(data)
            --[[
            for pos, val in pairs(data.raidIdList) do
                if not ZebRaidHistory[val] then
                    ZebRaid:SendCommMessage("WHISPER", data.sender, "REQUESTDETAILS", val)
                end
            end
            ]]--
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1
    }
end

function ZebRaid:OnEnable()
    -- Set up the data stores of the persistent classes
    self:GetClass("State"):SetDataStore(ZebRaidState)
    self:GetClass("PlayerData"):SetDataStore(ZebRaidPlayerData)

    -- Shold I use a VARIABLES_LOADED event, and set the backends there? I don't
    -- want to do this from constructor, because constructing object at wrong
    -- point can mess things up.
    if not self.state then
        ---
        --- Create the state object
        ---
        self.state = self:Construct("State")
    end

    if not self.players then
        ---
        --- Create the state object
        ---
        self.players = self:Construct("PlayerData")
    end

    if not self.roster then
        self.roster = self:Construct("Roster")
    end

    PlayerName, _ = UnitName("player")

    Guild:RegisterCallback("Update", self.GuildStatusUpdated, self)
    Guild:RegisterCallback("Added", self.MemberAdded, self)
    Guild:RegisterCallback("Removed", self.MemberRemoved, self)
    Guild:RegisterCallback("Connected", self.MemberConnected, self)
    Guild:RegisterCallback("Disconnected", self.MemberDisconnected, self)
    self:RegisterMessage("ZebRaid_RosterUpdated", "RosterUpdated")

    ZebRaidDialogCommandsInviteRaid:SetText(L["START_RAID"])

    -- Get ready to receive add-on comms
    self:CommInit()

    -- Start off with interface locked.
    self:LockUI()

    self:Tracker_Init()

    -- select the indicated karma DB when appropriate:
    if self.state:GetKarmaDb() then
        if Karma_command then
            Karma_command("use " .. self.state:GetKarmaDb())
        end
    end

    --
    -- Fill the lists out according to online and registered users
    --
    self:InitializeLists()

    -- Tell the rest of the guild that we are here.
    self:BroadcastComm("BROADCAST")
end

function ZebRaid:OnDisable()
    -- Hide the main dialog
    ZebRaidDialog:Hide()

    -- Stop responding to stuff
    self:UnregisterAllEvents()
    self:UnregisterAllMessages()
    self:Tracker_Final()
    self:CommFinal()
end

function ZebRaid:Start()
    self:Debug("ZebRaid:Start")

    if not self:IsEnabled() then return end

    if StartWasCalled then
        StartWasCalled = nil
        ZebRaidDialog:Hide()
        -- FIXME: yuk!
        self.roster.class:Finalize()
        return
    end

    -- FIXME: yuk!
    self.roster.class:Initialize()

    local karmaDb = self.state:GetKarmaDb()
    local uiMaster = self.state:GetUiMaster(karmaDb)
    if karmaDb then
        if not uiMaster then
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
        elseif uiMaster == PlayerName then
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
        else
            ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. uiMaster)
        end
    else
        ZebRaidDialogReportMaster:SetText(L["REPORT_NO_DB"])
    end

    -- Get rid of left-over state information
    self.state:Cleanup()

    -- If our karma db name list is empty, and if Ni_Karma is loaded, copy the
    -- database names in.
    if #self.KarmaList == 0 and KarmaList then
        -- Copy the Karma database names
        for db, val in pairs(KarmaList) do
            table.insert(self.KarmaList, db)
        end
    end

    -- Display the current setup
    local raidID = self.state:GetRaidId() or ZebRaid.RaidID

    ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidID)
    self:ShowListMembers()

    -- If there is an offline player in the Sitout list, ask their alts' tracker
    -- to respond
    for _, player in self.Sitout:GetIterator() do
        local alts = player:GetAlts()
        if not player:IsOnline() and alts then
            for alt in pairs(alts) do
                self:Tracker_QueryPresence(alt)
            end
        end
    end

    StartWasCalled = true

    ZebRaidDialog:Show()
end

local movingButtonLevel

function ZebRaid:PlayerOnDragStart(frame)
    self:Debug("PlayerOnDragStart")

    movingButtonLevel = frame:GetFrameLevel()
    if self.UiLockedDown then return end

    local cursorX, cursorY = GetCursorPosition()
    DraggingPlayer = true
    frame:StartMoving()
    frame:SetFrameLevel(movingButtonLevel + 30)
end

local destListNames = {
    "GuildList",
    "SignedUp",
    "Unsure",
    "Confirmed",
    "Reserved",
    "Penalty",
    "Sitout"
}

function ZebRaid:PlayerOnDragStop(frame)
    self:Debug("PlayerOnDragStop")

    frame:SetFrameLevel(movingButtonLevel)
    frame:StopMovingOrSizing()

    if self.UiLockedDown then self:ShowListMembers(); return end

    local selectedList = nil
    for _, list in ipairs(destListNames) do
        if MouseIsOver(getglobal("ZebRaidDialogPanel" .. list )) then
            selectedList = list
            break
        else
            for slot=1,30 do
                local slotFrame = getglobal("ZebRaidDialogPanel" .. list ..  "Slot" .. slot)
                if slotFrame and MouseIsOver(slotFrame) then
                    selectedList = list
                    break
                end
            end
        end
        if selectedList then break end
    end
    self:Debug("MouseIsOver: " .. (selectedList or "nothing"))

    -- Go back from visual to logical list object: If we've dropped on a new
    -- list, shoose that list. If not, then choose the list the button
    -- originated from.
    local list
    if selectedList then
        list = getglobal("ZebRaidDialogPanel" .. selectedList).listObj
    else
        list = frame.inList
    end

    -- Not signed up or unsigned => Cannot go to SignedUp, Unsure, or Penalty
    -- Allow Sitout for people who forgot to sign.
    local signStat = frame.player:GetSignupStatus()

    if signStat == self.signup_const.unsigned or
        signStat == self.signup_const.unknown
    then
        if ( list == self.Penalty or
             list == self.SignedUp or
             list == self.Unsure)
        then
            list = frame.inList
        end
    else
        -- Unsure => Cannot go to Penalty
        if list == self.Penalty and
            signStat == self.signup_const.unsure
        then
            list = frame.inList
        end

        -- SignedUp or Unsure cannot go back to guild
        if signStat ~= self.signup_const.unknown and
            list == self.GuildList
        then
            list = frame.inList
        end

        -- SignedUp and Unsure cannot go each other

        if  ( signStat == self.signup_const.signed and
              list == self.Unsure ) or
            ( signStat == self.signup_const.unsure and
              list == self.SignedUp )
        then
            list = frame.inList
        end
    end

    -- If we've moved the player, set up his/her new assignment
    if list ~= frame.inList then
        frame.player:SetAssignment(list:GetAssignment())
    end

    DraggingPlayer = nil

    -- We need to call this even if no list transition occured. The button needs
    -- to go back to its original place.
    self:ShowListMembers()
end

function ZebRaid:PlayerOnDoubleClick(frame, button)
    self:Debug("ZebRaid:OnDoubleClick")

    if self.UiLockedDown then return end

    local newassignment = self:ToggleAssignment(frame.player)
    if frame.player:GetAssignment() ~= newassignment then
        frame.player:SetAssignment(newassignment)
        self:ShowListMembers()
    end
end

function ZebRaid:PlayerOnEnter(frame)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
    GameTooltip:AddDoubleLine(name,
                              frame.player:GetClass(),
                              NORMAL_FONT_COLOR.r,
                              NORMAL_FONT_COLOR.g,
                              NORMAL_FONT_COLOR.b,
                              HIGHLIGHT_FONT_COLOR.r,
                              HIGHLIGHT_FONT_COLOR.g,
                              HIGHLIGHT_FONT_COLOR.b);
    GameTooltip:AddLine(frame.player:GetTooltipText(), 1, 1, 1, 1);
    GameTooltip:Show();
end

function ZebRaid:PlayerOnLeave(frame)
    GameTooltip:Hide()
end

-- Find a suitable assignment for the specified player
-- RETURNS: the selected list, or null.
function ZebRaid:ToggleAssignment(player)
    local assignment = player:GetAssignment()
    local signup = player:GetSignupStatus()
    local newassignment = self.assignment_const.unassigned

    if assignment == self.assignment_const.unassigned then
        if signup == self.signup_const.signed then
            newassignment = self.assignment_const.confirmed
        elseif signup == self.signup_const.unsure then
            if player:IsOnline(name) then
                newassignment = self.assignment_const.confirmed
            else
                newassignment = self.assignment_const.reserved
            end
        else -- Guild list: only shows online people, so I must want to confirm them
            newassignment = self.assignment_const.confirmed
        end
    elseif assignment == self.assignment_const.reserved or
        assignment == self.assignment_const.confirmed or
        assignment == self.assignment_const.penalty or
        assignment == self.assignment_const.sitout
    then
        newassignment = self.assignment_const.unassigned
    end

    -- TODO: Want to implement this?
    -- If the guy has a penalty, he moves to sitout
    -- regardless of the current selection

    return newassignment;
end

function ZebRaid:MemberConnected(event, name)
    self:Debug("Got member: " .. name)

    -- If the player has ever signed up with this name, set it to be the main character
    self:Tracker_SetPlayerMain(name)

    if not StartWasCalled then return end

    -- Leave this as it is. We don't want to create entries in the database for
    -- members who are not 80 yet. If we call self.players:Get(name) here, it would
    -- create an entry (not that there's anything wrong with that).
    if Guild:GetLevel(name) ~= 80 then return end

    if not self.state:GetKarmaDb() then return end

    local p = self.players:Get(name)

    -- FIXME: This is really overkill. We should have a button object, and a way
    -- to get the button of the player. That way we don't redraw the world when
    -- all we need is a single color change.
    NeedRecalculateAfterUpdate = true

    -- Since this instance is the current master, let the alt know where to
    -- report status
    self:Tracker_SetTrackerName(name)
end

function ZebRaid:MemberDisconnected(event, name)
    self:Debug("MemberDisconnected")
    if not StartWasCalled then return end

    if not self.state:GetKarmaDb() then return end

    local p = self.players:Get(name)
    if p:GetAssignment() == self.assignment_const.unassigned and
        p:GetSignupStatus(name) == self.signup_const.unknown
    then
        p:RemoveAssignment(name)
    end

    -- FIXME: See above note about overkill.
    NeedRecalculateAfterUpdate = true
end

function ZebRaid:MemberAdded(event, name)
    if not StartWasCalled then return end

    -- If I understand LibGuild code right, we won't get a separate
    -- MemberConnected event for this player.
    self:MemberConnected(name)
end

function ZebRaid:MemberRemoved(event, name)
    if not StartWasCalled then return end

    if not self.state:GetKarmaDb() then return end

    -- We just gkicked the bugger. No assignment for him!
    self.players:Get(name):RemoveAssignment()
    NeedRecalculateAfterUpdate = true
end

function ZebRaid:GuildStatusUpdated()
    self:Debug("GuildStatusUpdated")
    if not StartWasCalled then return end

    if NeedRecalculateAfterUpdate then
        self:ShowListMembers()
        NeedRecalculateAfterUpdate = nil
    end
end

local LastUpdateTime = GetTime()

function ZebRaid:OnUpdate()
    -- If we call ShowListMembers() too often, the UI becomes unresponsive.
    -- e.g. resisting drag-drop attempts.
    -- TODO: Optimize the loop.
    -- FIXME: Remove OnUpdate() updates altogether. Update when something changes.
    if not DraggingPlayer and (GetTime() - LastUpdateTime > 1) then
-- FIXME: See if we still need this. We shouldn't
--        self:ShowListMembers()
        LastUpdateTime = GetTime()
    end
end

function ZebRaid:AutoConfirm()
    if self.UiLockedDown then return end

    if not self.state:GetKarmaDb() then return end

    -- Move all unassigned people who are signed up to confirmed.
    for _, player in self.SignedUp:GetIterator() do
        if player:IsOnline() then
            player:SetAssignment(self.assignment_const.confirmed)
        end
    end

    self:ShowListMembers()
end

function ZebRaid:Announce()
    if self.UiLockedDown then return end

    if not self.state:GetKarmaDb() then return end

    local message = ""
    local totalCount = self.Sitout:GetTotalCount()
    if totalCount > 0 then
        for i, player in self.Sitout:GetIterator() do
            message = message .. player:GetName()
            if i ~= totalCount then
                message = message .. ", "
            else
                message = message .. "."
            end
        end
    end

    -- FIXME: Add note for raid karma db name (perhaps): T5SE may not mean for guildies.
    SendChatMessage("--------------------\r\n" ..
                    L["SITOUT_ANNOUNCE_MSG"] .. "\r\n" ..
                    message .. "\r\n" ..
                    "--------------------", "GUILD")
--[[
        SendChatMessage(L["SITOUT_ANNOUNCE_MSG"], "GUILD")
        SendChatMessage(message, "GUILD")
        SendChatMessage("--------------------", "GUILD")
        ]]
end

function ZebRaid:GiveKarma()
    if self.UiLockedDown then return end

    if not self.state:GetKarmaDb() then return end

    -- TODO: Make sure on time karma cannot be given twice for the same raid
    -- If we can give karma ...
    if not Karma_Add_Player then
        DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_ADDON"])
        return
    end

    if not KarmaConfig["CURRENT RAID"] then
        DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DB"])
        return
    end

    -- Give on time karma to all Confirmed and Sitout users.
    for _, player in self.Confirmed:GetIterator() do
        -- Only confirmed people who are in raid deserve online karma. :-)
        if player:IsInRaid() then
            self:Debug("Giving on time karma to " .. player:GetName())
            -- Karma_Add_Player(name, ON_TIME_KARMA_VAL, "on time", "P")
        end
    end

    for _, player in self.Sitout:GetIterator() do
        Karma_Add_Player(player:GetName(), ON_TIME_KARMA_VAL, "on time", "P")
    end
end

-- return true if a>b, false otherwise
-- Compares dates of format MM/DD/YY
local function isDateGreater(a, b)
    -- Convert from MM/DD/YY to YY/MM/DD for all dates
    a = a:gsub("^(.*)/([^/]*)$", "%2/%1")
    b = b:gsub("^(.*)/([^/]*)$", "%2/%1")
    return a > b
end

-- helper function to sort the list according to class, sitout and penalty
function cmp_sort_for_sitout(p1, p2)
    local role1, role2
    role1 = p1:GetRole()
    role2 = p2:GetRole()

    -- If the roles are different, sort according to role
    if role1 ~= role2 then
        return role1 < role2
    end

    -- Otherwise, do the whole shebang:
    -- Person with penalty > person witout penalty
    -- both have penalty => sort by penalty date (earlier > later)
    -- both at same date penalty => apply sitout comparisons
    -- earlier sitout > later sitout
    -- equal sitout date => sitout count
    -- just give up and return 0
    local sitoutCount = { p1:GetSitoutCount(),
                          p2:GetSitoutCount() }
    local lastSitout = { p1:GetLastSitoutDate(),
                         p2:GetLastSitoutDate() }
    local lastPenalty = { p1:GetLastPenaltyDate(),
                          p2:GetLastPenaltyDate() }
    local hasPenalty = { isDateGreater(lastPenalty[1], lastSitout[1]),
                         isDateGreater(lastPenalty[2], lastSitout[2]) }

    -- This looks weird, but complicated logic inside sort tends to break it
    -- when you return true for both a<b and b<a. Or even worse, a<b, b<c, and
    -- c<a. Assigning a score per person and comparing eliminates the first
    -- kind. I doubt that it will eliminate the second kind, because scores
    -- depend on the other item compared, but I am hoping that the rules are
    -- sensible enough that it will not happen.
    -- Each test has a different weight in score, prioritizing that test above
    -- others. The downside of the method is the renumbering required every time
    -- a new test is added to the middle.
    local score = { 0, 0 }

    for i = 1, 2 do
        if hasPenalty[i] then
            score[i] = score[i] + 8
            if hasPenalty[2-i+1] and
                isDateGreater(lastPenalty[2-i+1], lastPenalty[i]) then
                score[i] = score[i] + 4
            end
        end
        if isDateGreater(lastSitout[2-i+1], lastSitout[i]) then
            score[i] = score[i] + 2
        end
        if sitoutCount[i] < sitoutCount[2-i+1] then
            score[i] = score[i] + 1
        end
    end

    return (score[1] == score[2]) and (p1:GetName() < p2:GetName()) or (score[1] > score[2])
end

function ZebRaid:InitializeLists()
    local f_and = function (...)
        local funcs={...}

        return function(player)
            local res = true
            for i, f in ipairs(funcs) do
                res = res and f(player)
                if not res then break end
            end
            return res
               end
    end

    local f_or = function (...)
        local funcs={...}

        return function(player)
            local res = false
            for i, f in ipairs(funcs) do
                res = res or f(player)
                if res then break end
            end
            return res
               end
    end

    local by_signup = function(status)
        return function(player)
            return player:GetSignupStatus() == status
               end
    end

    local by_assignment = function(assignment)
        return function(player)
            return player:GetAssignment() == assignment
               end
    end

    local is_online = function(player)
        return player:IsOnline()
    end

    local make_list = function(name, assignment, filter_func, sort_func)
        local list = self:Construct("List",
                                    name,
                                    getglobal("ZebRaidDialogPanel" .. name),
                                    assignment)
        list:SetFilterFunc(filter_func)
        list:SetSortFunc(sort_func)
        list:Update()
        return list
    end

    list_defs = {
        GuildList = {
            assignment = self.assignment_const.unassigned,
            filter = f_and(by_signup(self.signup_const.unknown),
                           by_assignment(self.assignment_const.unassigned),

                           is_online)
        },
        SignedUp = {
            assignment = self.assignment_const.unassigned,
            filter = f_and(by_signup(self.signup_const.signed),
                           by_assignment(self.assignment_const.unassigned))
        },
        Unsure = {
            assignment = self.assignment_const.unassigned,
            filter = f_and(by_signup(self.signup_const.unsure),
                           by_assignment(self.assignment_const.unassigned))
        },
        Confirmed = {
            assignment = self.assignment_const.confirmed,
            filter = by_assignment(self.assignment_const.confirmed),
            sort = cmp_sort_for_sitout
        },
        Reserved = {
            assignment = self.assignment_const.reserved,
            filter = by_assignment(self.assignment_const.reserved)
        },
        Penalty = {
            assignment = self.assignment_const.penalty,
            filter = by_assignment(self.assignment_const.penalty)
        },
        Sitout = {
            assignment = self.assignment_const.sitout,
            filter = by_assignment(self.assignment_const.sitout)
        }
    }

    for name, def in pairs(list_defs) do
        if not self[name] then
            self[name] = make_list(name, def.assignment, def.filter, def.sort)
        end
    end

    local filter_func = function (player)
        -- Choose all players who has signup data
        return player:GetSignupStatus() ~= self.signup_const.unknown
    end

    -- Iterate thrhough all registered users and tell tracker to set the mains
    -- for these people (if they are online)
    for _, player in self.players:GetIterator(filter_func) do
        if player:IsOnline() then
            player:SetMainToon()
        end
    end
end

function ZebRaid:Reset()
    self:Debug("ZebRaid:Reset")

    if self.UiLockedDown then return end
    if not self:IsEnabled() then return end

    self.state:ResetAssignments()

    --[[
    self:BroadcastComm("ANNOUNCE_MASTER",
    ZebRaidState.KarmaDB, state.RaidID,
    state.RegisteredUsers,
    state.Lists)
    --]]
    self:ShowListMembers()
end

function ZebRaid:RaidSelection_OnShow()
    if not self.initSortDropDown then
        UIDropDownMenu_Initialize(this, function() self:RaidSelection_Populate() end)
        self.initSortDropDown = true
    end
end

function ZebRaid:RaidSelection_Populate()
    local info
    local dbList = {}

    if self.KarmaList then
        for db, val in pairs(self.KarmaList) do
            table.insert(dbList, val)
        end
    end

    for pos, name in pairs(dbList) do
        info = UIDropDownMenu_CreateInfo()
        info.value = pos
        info.owner = this:GetParent()
        info.text = name
        info.func = function() ZebRaid:RaidSelection_OnClick() end
        UIDropDownMenu_AddButton(info)
        if name == self.state:GetKarmaDb() then
            UIDropDownMenu_SetSelectedValue(ZebRaidDialogRaidSelection, pos)
        end
    end
end

function ZebRaid:RaidSelection_OnClick()
    self:Debug("ZebRaid:RaidSelection_OnClick: " .. this:GetText() .. ", " .. this.value)

    UIDropDownMenu_SetSelectedValue(this.owner, this.value)
    local karmaDB=this:GetText()
    self.state:SetKarmaDb(karmaDB)

    if Karma_command then
        Karma_command("use " .. karmaDB)
    end

    if not self.state:GetRaidId() then
        self.state:SetRaidId(self.RaidID)
    end

    -- Display the current setup
    self:ShowListMembers()

    local raidId = self.state:GetRaidId()

    local uiMaster = self.state:GetUiMaster(karmaDB)
    if not uiMaster then
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_NONE"])
        self:LockUI()
    elseif uiMaster == PlayerName then
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
        self:UnlockUI()
    else
        ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_OTHER"] .. uiMaster)
        self:LockUI()
    end

    ZebRaidDialogPanelTitle:SetText(L["RAID_ID"] .. raidId)
end

----------------------
-- Helper Functions --
----------------------

function ZebRaid:GetRaidDate()
    local raidId = self.state:GetRaidId()
    _,_,d,m,y=string.find(raidId, ".*_(%d+).(%d+).20(%d+)")
    return string.format("%02d/%02d/%02d",d,m,y)
end

function ZebRaid:ShowListMembers()
    local add_counts = function(o1, o2)
        return {
            GetCount = function (dummyobj, role)
                return o1:GetCount(role) + o2:GetCount(role)
            end }
    end
    -- If we haven't selected a list, or (for some reason) the
    -- selection has no state, then do not attempt to draw anything.
    if not self.state:GetKarmaDb() then
        -- FIXME: This extra check should not be needed
        self:UpdateCounts("ZebRaidDialogConfirmedStats", self.Confirmed)
        self:UpdateCounts("ZebRaidDialogTotalStats", add_counts(self.Confirmed,
                                                                self.Reserved))
        ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] .. " (0)")
        ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] .. " (0)")
        ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] .. " (0)")
        ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] .. " (0)")
        ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] .. " (0)")
        ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] .. " (0)")
        ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] .. " (0)")
    else
        self.GuildList:Update()
        self.SignedUp:Update()
        self.Unsure:Update()
        self.Confirmed:Update()
        self.Reserved:Update()
        self.Penalty:Update()
        self.Sitout:Update()

        ZebRaidDialogPanelSignedUpLabel:SetText(L["SIGNEDUP"] ..
                                                " (" .. self.SignedUp:GetTotalCount() .. ")")
        ZebRaidDialogPanelUnsureLabel:SetText(L["UNSURE"] ..
                                                " (" .. self.Unsure:GetTotalCount() .. ")")
        ZebRaidDialogPanelConfirmedLabel:SetText(L["CONFIRMED"] ..
                                                " (" .. self.Confirmed:GetTotalCount() .. ")")
        ZebRaidDialogPanelReservedLabel:SetText(L["RESERVED"] ..
                                                " (" .. self.Reserved:GetTotalCount() .. ")")
        ZebRaidDialogPanelGuildListLabel:SetText(L["GUILDLIST"] ..
                                                " (" .. self.GuildList:GetTotalCount() .. ")")
        ZebRaidDialogPanelPenaltyLabel:SetText(L["PENALTY"] ..
                                                " (" .. self.Penalty:GetTotalCount() .. ")")
        ZebRaidDialogPanelSitoutLabel:SetText(L["SITOUT"] ..
                                                " (" .. self.Sitout:GetTotalCount() .. ")")

        self:UpdateCounts("ZebRaidDialogConfirmedStats", self.Confirmed)
        self:UpdateCounts("ZebRaidDialogTotalStats", add_counts(self.Confirmed,
                                                                self.Reserved))
    end
end

function ZebRaid:UpdateCounts(panelName, list)
    getglobal(panelName .. "Tank"):SetText(L["TANK"] .. ": " ..
                                           list:GetCount("tank"))
    getglobal(panelName .. "Melee"):SetText(L["MELEE"] .. ": " ..
                                            list:GetCount("melee"))
    getglobal(panelName .. "Healer"):SetText(L["HEALER"] .. ": " ..
                                             list:GetCount("healer"))
    getglobal(panelName .. "Ranged"):SetText(L["RANGED"] .. ": " ..
                                             list:GetCount("ranged"))
    getglobal(panelName .. "Total"):SetText(L["TOTAL"]..": " ..
                                            list:GetCount("tank") +
                                            list:GetCount("melee") +
                                            list:GetCount("healer") +
                                            list:GetCount("ranged"))
end

function ZebRaid:LockUI()
    ZebRaid.UiLockedDown = true
    ZebRaidDialogCommandsAutoConfirm:Disable()
    ZebRaidDialogCommandsReset:Disable()
    ZebRaidDialogCommandsGiveKarma:Disable()
    ZebRaidDialogCommandsAnnounce:Disable()
    ZebRaidDialogCommandsInviteRaid:Disable()
    ZebRaidDialogCommandsSync:Disable()
--    UIDropDownMenu_DisableDropDown(ZebRaidDialogRaidSelection)
    ZebRaidDialogCommandsUnlock:Enable()
end

function ZebRaid:UnlockUI()
    if self.state:GetRaidId() then
        ZebRaid.UiLockedDown = nil
        ZebRaidDialogCommandsAutoConfirm:Enable()
        ZebRaidDialogCommandsReset:Enable()
        ZebRaidDialogCommandsGiveKarma:Enable()
        ZebRaidDialogCommandsAnnounce:Enable()
        ZebRaidDialogCommandsInviteRaid:Enable()
        ZebRaidDialogCommandsSync:Enable()
--        UIDropDownMenu_EnableDropDown(ZebRaidDialogRaidSelection)
        ZebRaidDialogCommandsUnlock:Disable()
    end
end

function ZebRaid:OnUnlock()
    DEFAULT_CHAT_FRAME:AddMessage("DEBUG: OnUnlock")

    if not self.state:GetKarmaDb() then
        DEFAULT_CHAT_FRAME:AddMessage("ERROR: state is nil")
        -- FIXME: Print an error message somewhere
        return
    end

    self.state:SetUiMaster(self.state:GetKarmaDb(), PlayerName)

    self:UnlockUI()
    ZebRaidDialogReportMaster:SetText(L["REPORT_MASTER_SELF"])
end

function ZebRaid:OnHide()
    StartWasCalled = nil
    -- FIXME: yuk!
    self.roster.class:Finalize()
end

function ZebRaid:StartInvite()
    if self.coInvite and coroutine.status(self.coInvite) ~= "dead" then
        DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Invite already in progress")
        return
    end
    self.coInvite = coroutine.create(self.DoInvites)
    if self.coInvite then
        local status, err = coroutine.resume(self.coInvite, self)
        if not status then
            DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Cannot start invites - " .. (err or "nil"))
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("ZebRaid: Cannot start invites")
    end
end

function ZebRaid:DoInvites()
    -- Periodic event to unlock the coroutine if it gets stuck
    local hTimer = self:ScheduleRepeatingTimer("PeriodicTimer", 1)
    -- Construct a list of members to invite
    local inviteList={}
    local inviteCount = 0
    for _, player in self.Confirmed:GetIterator() do
        if player:GetName() ~= UnitName("player") and not player:IsInRaid() then
            table.insert(inviteList, {name=player:GetName()})
            inviteCount = inviteCount + 1
        end
    end

    for _, player in self.Sitout:GetIterator() do
        if player:GetName() ~= UnitName("player") and not player:IsInRaid() then
            table.insert(inviteList, {name=player:GetName()})
            inviteCount = inviteCount + 1
        end
    end

    if inviteCount == 0 then return end

    local finished = nil
    while not finished do
        if UnitInParty("player") and
           GetNumPartyMembers() > 0
        then
            ConvertToRaid()
            self:WaitForRaid()
        end

        if not UnitInRaid("player") then
            -- First, try to find someone who'll accept the invite, so that we can convert to raid
            local waitingAccept = 0

            for i, v in ipairs(inviteList) do
                -- Invite the next person
                if self.players:Get(v.name):IsOnline() then
                    self:Debug("Inviting " .. v.name)
                    InviteUnit(v.name)
                    waitingAccept = waitingAccept + 1
                else
                    inviteCount = inviteCount - 1
                end

                -- If we've already invited four people, and they haven't accepted yet, wait
                if waitingAccept == 4 or waitingAccept == inviteCount then

                    local startTime = GetTime()
                    while not ( UnitInParty("player") and
                                GetNumPartyMembers() > 0 )
                    do
                        self:Debug("Unit is not in party. Waiting.")
                        coroutine.yield()
                        -- Wait up to 15 seconds
                        if GetTime() - startTime > 15 then
                            self:Debug("Waited too long. Inviting another.")
                            waitingAccept = waitingAccept - 1
                            break
                        end
                    end

                    if UnitInParty("player") and
                       GetNumPartyMembers() > 0
                    then
                        self:Debug("Unit is in party. Converting to raid.")
                        ConvertToRaid()
                        self:WaitForRaid()
                        if UnitInRaid("player") then
                            self:Debug("Unit is in raid.")
                            finished = true
                            break
                        else
                            -- FIXME: This is quite simplistic, and may break.
                            -- A better option would be to get an event on invite timeouts.
                            -- See if it is possible
                            waitingAccept = waitingAccept - 1
                        end
                    else
                        -- FIXME: See above
                        waitingAccept = waitingAccept - 1
                    end
                end
            end
        else
            finished = true
        end
    end

    -- We should be in raid now. Invite everybody
    for i, v in ipairs(inviteList) do
        local p = self.players:Get(v.name)
        if not p:IsInRaid() then
            if p:IsOnline() then
                InviteUnit(v.name)
            end
        end
    end

    -- Remove the event handlers. We are done with them.
    self:CancelTimer(hTimer)
end

function ZebRaid:WaitForRaid()
    local start = GetTime()
    while not UnitInRaid("player") do
        coroutine.yield()
        -- Wait up to 20 seconds
        if GetTime() - start > 20 then break end
    end
end

-- A timer to ensure we can break out of otherwise infinite loops in the coroutine
function ZebRaid:PeriodicTimer()
    --self:Debug("ZebRaid:PeriodicTimer()")
    if self.coInvite and coroutine.status(self.coInvite) == "suspended" then
        coroutine.resume(self.coInvite)
    end
end

-- Used in the function below: the lists we check for people in our raid
-- Moved up here to reduce memory usage
local listsToScan = {
    "GuildList",
    "SignedUp",
    "Unsure",
    "Reserved"
}

-- Event handler: called when we detect changes on the party
function ZebRaid:RosterUpdated()
    self:Debug("RosterUpdated")

    -- Move every player in raid to confirmed if they are not in penalty or sitout
    if self.state:GetKarmaDb() then
        -- FIXME: Yuk! Need a much better way to do this. Roster belongs in
        -- PlayerData class.
        for name in self.roster:GetIterator() do
            assignment = self.state:GetAssignment(name)
            if assignment == self.assignment_const.unassigned or
                assignment == self.assignment_const.unknown or
                assignment == self.assignment_const.reserved
            then
                self.state:SetAssignment(name, self.assignment_const.confirmed)
            end
        end
    end

    self:ShowListMembers()

    if self.coInvite and coroutine.status(self.coInvite) == "suspended" then
        coroutine.resume(self.coInvite)
    end
end

-- Local variable to control debugging
local debugEnabled = false

-- Enable/Disable debugging
function ZebRaid:SetDebugging(enabled)
    debugEnabled = enabled
end

-- Print a debug statement
function ZebRaid:Debug(...)
    return debugEnabled and self:Print(date(), ": ", ...)
end

function ZebRaid:SetBossAndKarma(boss, karma)
    ZebRaidDialogBoss:SetText(boss)
    ZebRaidDialogKarma:SetText(tostring(karma))
    self:Start()
end

function ZebRaid:GiveBossKarma()
    -- If we can give karma ...
    if not Karma_Add_Player then
        DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_ADDON"])
        return
    end

    if not KarmaConfig["CURRENT RAID"] then
        DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DB"])
        return
    end

    -- Get the boss name and karma amount
    local boss = ZebRaidDialogBoss:GetText()
    local karma = ZebRaidDialogKarma:GetText()

    if not boss or boss == "" or
        not karma or karma == ""
    then
        DEFAULT_CHAT_FRAME:AddMessage(L["NO_KARMA_DATA"])
        return
    end

    -- Give on time karma to all raid members.
    Karma_Add(karma .. " all " .. boss, "P")

    for _, player in self.Sitout:GetIterator() do
        -- Only confirmed people who are in raid deserve online karma. :-)
        --[[        if not player:IsInRaid() and
        ( player:IsOnline() or
            player:IsAltOnline() )
        Just give everyone in sitout list the karma if they are not already in raid
           ]]--
        if not player:IsInRaid() then
            Karma_Add(karma .. " " .. player:GetName() .. " " .. boss, "P")
        end
    end
end

if DBM then
    local DBMold = DBM.EndCombat
    local BossKarmaLookup = {
        ["Anub'Rekhan"] = 5,
        ["Faerlina"] = 5,
        ["Maexxna"] = 5,
        ["Gluth"] = 5,
        ["Grobbulus"] = 5,
        ["Patchwerk"] = 5,
        ["Thaddius"] = 5,
        ["Gothik"] = 5,
        ["Horsemen"] = 5,
        ["Razuvious"] = 5,
        ["Heigan"] = 5,
        ["Loatheb"] = 5,
        ["Noth"] = 5,
        ["Sapphiron"] = 5,
        ["Kel'Thuzad"] = 10,
        ["Archavon"] = 10,
        ["Sartharion"] = 10,
        ["Malygos"] = 10,
    }


    DBM.EndCombat = function (self, mod, wipe)
        if self.state:GetKarmaDb() then
            local difficulty = GetInstanceDifficulty()
            if (difficulty == 2 or difficulty == 4) and
                BossKarmaLookup[mod.id] and not wipe
            then
                ZebRaid:SetBossAndKarma(mod.id, BossKarmaLookup[mod.id])
            end
        end

        DBMold(self, mod, wipe)
    end
end
