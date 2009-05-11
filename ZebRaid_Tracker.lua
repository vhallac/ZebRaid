ZebRaid.AltOnline = {}
ZebRaid.CurrentAlt = {}
-- People we assume to be trackers
local FixedTrackers = {"Dys", "Beh", "Jiny", "Karadine", "Iceberg"}

local hTimer = nil

function ZebRaid:Tracker_Init()
	self:RegisterEvent("PLAYER_LOGIN", "Tracker_OnPlayerLogin")
	self:RegisterEvent("PLAYER_LOGOUT", "Tracker_OnPlayerLogout")
	hTimer = self:ScheduleRepeatingTimer("Tracker_PingTimer", 20)
end

function ZebRaid:Tracker_Final()
	self:CancelTimer(hTimer)
	hTimer = nil
	self:UnregisterEvent("PLAYER_LOGOUT", "Tracker_OnPlayerLogout")
	self:UnregisterEvent("PLAYER_LOGIN", "Tracker_OnPlayerLogin")
end

-- Tell the player's tracker addon to mark
function ZebRaid:Tracker_SetPlayerMain(name)
	if name == UnitName("PLAYER") then
		self:OnSETMAIN(UnitName("PLAYER"))
	else
		self:WhisperComm(name, "SETMAIN")
	end
end

function ZebRaid:Tracker_SetTrackerName(name, tracker)
	if name == UnitName("PLAYER") then
		-- This is somewhat ridiculous, but who cares. :)
		self:OnSETTRACKER(UnitName("PLAYER"), tracker or UnitName("PLAYER"))
	else
		self:WhisperComm(name, "SETTRACKER", tracker or UnitName("player"))
	end
end

-- Ping an alt to see if it is still online
function ZebRaid:Tracker_PingAlt(name)
	if not self.CurrentAlt[name] then
		self.AltOnline[name] = nil
		return
	end

	local time = GetTime()
	self.AltOnline[name] = function()
		if GetTime() - time < 10 then
			return true
		else
			return nil
		end
	end
	self:WhisperComm(self.CurrentAlt[name], "TRACKER_PING")
end

-- This is tricky. The AltOnline[name] may be either a boolean or a function
-- If we have pinged the player recently, and have not received a response yet,
-- then it is a function that returns true or false depending on when we pinged
-- the alt. As soon as we time out on the comms, we change AltOnline[name] back to
-- a boolean.
function ZebRaid:Tracker_IsAltOnline(name)
	local online = false
	if self.AltOnline[name] then
		if type(self.AltOnline[name]) == "function" then
			online = self.AltOnline[name]()
			if not online then
				self.AltOnline[name] = nil
				self.CurrentAlt[name] = nil
			end
		else
			online = self.AltOnline[name]
		end
	end
	return online
end

function ZebRaid:Tracker_GetCurrentAlt(name)
	return self.CurrentAlt[name]
end

function ZebRaid:Tracker_QueryPresence(name)
	self:WhisperComm(name, "TRACKER_QUERY")
end

function ZebRaid:SendToTrackers(...)
	if ZebRaidTrackerData.TrackerName then
		self:WhisperComm(ZebRaidTrackerData.TrackerName, ...)
	end
	for _,name in ipairs(FixedTrackers) do
		self:WhisperComm(name, ...)
	end
end

---------------------
-- EVENT HANDLERS  --
---------------------

-- Periodic timer handler: Ping all alts to make sure they are still online
function ZebRaid:Tracker_PingTimer()
	for name in pairs (self.AltOnline) do
		self:Tracker_PingAlt(name)
	end
end

function ZebRaid:Tracker_OnPlayerLogin()
	if ZebRaidTrackerData.TrackerName then
		if ZebRaidTrackerData.MainName and
		   ZebRaidTrackerData.MainName ~= UnitName("player")
		then
			self:SendToTrackers("ALTLOGGEDIN", ZebRaidTrackerData.MainName)
		end
	end
end

function ZebRaid:Tracker_OnPlayerLogout()
	if ZebRaidTrackerData.TrackerName then
		if ZebRaidTrackerData.MainName and
		   ZebRaidTrackerData.MainName ~= UnitName("player")
		then
			-- self:SendToTrackers("ALTLOGGEDOUT", ZebRaidTrackerData.MainName)
		end
	end
end

-----------------------------
-- COMMS MESSAGE HANDLERS  --
-----------------------------

function ZebRaid:OnSETMAIN(sender)
	ZebRaidTrackerData.MainName = UnitName("player")
end

function ZebRaid:OnSETTRACKER(sender, name)
	ZebRaidTrackerData.TrackerName = name
	-- If the tracker changes while we are on an alt, ping the new tracker
	if ZebRaidTrackerData.MainName and
	   ZebRaidTrackerData.MainName ~= UnitName("player")
	then
		self:WhisperComm(ZebRaidTrackerData.TrackerName,
		                 "ALTLOGGEDIN",
		                 ZebRaidTrackerData.MainName)
	end
end

function ZebRaid:OnALTLOGGEDIN(sender, mainName)
	self:Debug("Received ALTLOGGEDIN from", sender, "for", mainName)
	-- TODO: If I am no longer the master, tell the alt to talk to the new master
	if ZebRaidPlayerData[mainName] then
		if not ZebRaidPlayerData[mainName].AltList then
			ZebRaidPlayerData[mainName].AltList = {}
		end
		ZebRaidPlayerData[mainName].AltList[sender] = true
		self.AltOnline[mainName] = true
		self.CurrentAlt[mainName] = sender
	end
end

function ZebRaid:OnALTLOGGEDOUT(sender, mainName)
	self.CurrentAlt[mainName] = nil
	self.AltOnline[mainName] = nil
end

function ZebRaid:OnTRACKER_PING(sender)
	self:WhisperComm(sender, "TRACKER_PONG", ZebRaidTrackerData.MainName)
end

function ZebRaid:OnTRACKER_PONG(sender, mainName)
	if mainName then
		self.AltOnline[mainName] = true
	end
end

function ZebRaid:OnTRACKER_QUERY(sender)
	self:SendComm("WHISPER", sender, "ALTLOGGEDIN", ZebRaidTrackerData.MainName)
end
