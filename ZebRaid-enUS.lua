﻿local AceLocale = AceLibrary("AceLocale-2.2"):new("ZebRaid")

AceLocale:RegisterTranslations("enUS", function()
    return {
        ["START_DIALOG"] = "Start planning the raid",
        ["SHOW_DIALOG"] = "Show/Hide the dialog",
        ["TANK"] = "Tank",
        ["MELEE"] = "Melee DPS",
        ["HEALER"] = "Healer",
        ["RANGED"] = "Ranged DPS",
		["HYBRID"] = "Hybrid w. Heal",
        ["TOTAL"] = "Total",
        ["RAID_ID"] = "Raid ID: ",
        ["SIGNEDUP"] = "Signed up",
        ["UNSURE"] = "Unsure",
        ["CONFIRMED"] = "Confirmed",
        ["RESERVED"] = "Reserved",
        ["GUILDLIST"] = "Online",
        ["START_RAID"] = "Build Raid",
        ["INVITE_REST"] = "Invite Rest",
        ["AUTOCONFIRM"] = "Auto Confirm",
        ["KARMA"] = "Gief Karma",
        ["ANNOUNCE"] = "Announce",
        ["NO_KARMA_ADDON"] = "Ni_Karma addon is not loaded",
        ["NO_KARMA_DB"] = "You haven't selected the karma database. Use /km use <raidname>.",
        ["KARMA_GIVEN"] = "You have already given on time karma for this raid.",
        ["RESET"] = "Reset",
        ["PLAYER_OFFLINE"] = "Player is offline",
        ["PLAYER_UNSIGNED"] = "Unsigned from the raid",
        ["CONFIRMED_STATS"] = "Confirmed Counts",
        ["TOTAL_STATS"] = "Total Counts",
        ["NOOUTSTANDING"] = "No outstanding stats",
        ["NONEWRAIDDATA"] = "No new raid history data discovered during synchronization",
        ["RAIDADDED"] = "Synchronized raid data: ",
        ["SYNCHCONFIRMATION"] = "Player %s has raid history data for raids: %s.\n\nDo you wish to synchronize?",
        ["SYNCH"] = "Synchronize",
        ["UNLOCK"] = "Unlock UI",
        ["SITOUT_ANNOUNCE_MSG"] = "THE FOLLOWING PLAYERS WILL BE SITOUT TODAY: ",
        ["REPORT_MASTER_NONE"] = "ZebRaid master is not set yet.",
        ["REPORT_MASTER_SELF"] = "You are the current ZebRaid master.",
        ["REPORT_MASTER_OTHER"] = "The current ZebRaid master is: ",
    }
end)
