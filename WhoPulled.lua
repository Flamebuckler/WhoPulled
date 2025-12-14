local WhoPulled = {
    name = "WhoPulled",
    version = "0.1.0",
    author = "Flamebuckler",
}

local EM = GetEventManager()
local lgcs = nil -- LibGroupCombatStats Object

-- Event constants (set in Initialize())
local EVENT_GROUP_DPS_UPDATE = nil
local EVENT_PLAYER_DPS_UPDATE = nil

-- Local variables
local currentBoss = nil
local pullDetected = false
local combatStartTime = 0
local PULL_DETECTION_WINDOW = 5000 -- 5 seconds after combat start
local firstHitData = {}            -- Stores who dealt the first damage and when

-- Saved Variables
local savedVars = nil
local defaultSettings = {
    enabled = true,
    showInChat = true,
    debugMode = false,
    detectionWindow = 5000, -- Configurable
}

-- Forward declarations
local OnCombatStart
local CreateSettingsMenu

-- Helper function: Debug output
local function DebugLog(...)
    if savedVars and savedVars.debugMode then
        d(string.format("[WhoPulled Debug] %s", string.format(...)))
    end
end

-- Helper function: Print message to chat
local function PrintMessage(message)
    if savedVars and savedVars.showInChat then
        d(string.format("|c00FF00[WhoPulled]|r %s", message))
    end
end

-- Callback for group DPS updates from LibGroupCombatStats
local function OnGroupDPSUpdate(unitTag, dpsData)
    DebugLog("[OnGroupDPSUpdate] Called - unitTag: %s", tostring(unitTag))

    if not savedVars or not savedVars.enabled then
        DebugLog("  -> Abort: savedVars not ready or disabled")
        return
    end
    if pullDetected then
        DebugLog("  -> Abort: pull already detected")
        return
    end

    -- Check if we're within the detection window
    local currentTime = GetGameTimeMilliseconds()

    -- If combat hasn't started yet, start it now (first DPS hit)
    if combatStartTime == 0 then
        DebugLog("  -> Combat started via DPS update!")
        OnCombatStart()
    end

    local timeSinceCombatStart = currentTime - combatStartTime
    DebugLog("  combatStartTime: %d, currentTime: %d, timeSince: %d, window: %d",
        combatStartTime, currentTime, timeSinceCombatStart, PULL_DETECTION_WINDOW)

    if timeSinceCombatStart > PULL_DETECTION_WINDOW then
        DebugLog("  -> Abort: detection window expired")
        return
    end

    -- Check if there's new damage (not 0)
    DebugLog("  DPS Data: dps=%s, dmg=%s, dmgType=%s", tostring(dpsData.dps), tostring(dpsData.dmg),
        tostring(dpsData.dmgType))

    if dpsData.dps <= 0 and dpsData.dmg <= 0 then
        DebugLog("  -> Abort: No damage from %s (dps: %d, dmg: %d)", tostring(GetUnitName(unitTag)), dpsData.dps,
            dpsData.dmg)
        return
    end

    local characterName = GetUnitName(unitTag)
    local displayName = GetUnitDisplayName(unitTag)

    DebugLog("=== Boss DPS detected ===")
    DebugLog("Unit: %s (%s)", tostring(characterName), tostring(displayName))
    DebugLog("DPS: %d, Total DMG: %d, time since combat: %dms", dpsData.dps, dpsData.dmg, timeSinceCombatStart)

    -- Store data for the first hit
    if not firstHitData[characterName] then
        firstHitData[characterName] = {
            timestamp = currentTime,
            dps = dpsData.dps,
            dmg = dpsData.dmg,
            unitTag = unitTag,
            displayName = displayName
        }
        DebugLog("First hit stored for %s", characterName)
    end
end

-- Determine who pulled first based on collected data
local function DeterminePuller()
    DebugLog("[DeterminePuller] Called")

    if pullDetected then
        DebugLog("  -> Abort: pull already detected")
        return
    end

    local earliestTime = nil
    local pullerName = nil
    local pullerDisplayName = nil
    local pullerTag = nil

    local count = 0
    for _ in pairs(firstHitData) do count = count + 1 end

    DebugLog("=== Analyzing first hits (count: %d) ===", count)

    if count == 0 then
        DebugLog("  -> WARNING: No first hit data available!")
    end

    for name, data in pairs(firstHitData) do
        DebugLog("  %s: Time=%dms, DPS=%d, DMG=%d", name, data.timestamp - combatStartTime, data.dps, data.dmg)

        if not earliestTime or data.timestamp < earliestTime then
            earliestTime = data.timestamp
            pullerName = name
            pullerDisplayName = data.displayName
            pullerTag = data.unitTag
        end
    end

    if not pullerName then
        DebugLog("No puller determined")
        return
    end

    pullDetected = true

    -- Determine boss name
    for i = 1, 6 do
        local bossTag = "boss" .. i
        if DoesUnitExist(bossTag) then
            currentBoss = GetUnitName(bossTag)
            if currentBoss and currentBoss ~= "" then
                break
            end
        end
    end

    if not currentBoss or currentBoss == "" then
        currentBoss = "Trash"
        return
    end

    -- Output
    local message
    local displayNameToShow = pullerDisplayName ~= "" and pullerDisplayName or pullerName

    if pullerTag and AreUnitsEqual(pullerTag, "player") then
        message = string.format("|cFFFF00You|r pulled |cFF0000%s|r!", currentBoss)
    else
        message = string.format("|cFF6600%s|r pulled |cFF0000%s|r!", displayNameToShow, currentBoss)
    end

    PrintMessage(message)

    DebugLog("=== PULL DETECTED ===")
    DebugLog("Puller: %s (%s)", pullerName, pullerDisplayName)
    DebugLog("Boss: %s", currentBoss)
    DebugLog("Time: %dms after combat start", earliestTime - combatStartTime)
end

-- Handler for Combat Start
OnCombatStart = function()
    local timestamp = GetGameTimeMilliseconds()
    DebugLog("")
    DebugLog("============================================")
    DebugLog("=== Combat Start detected (time: %d) ===", timestamp)
    DebugLog("============================================")
    DebugLog("Grouped: %s, group size: %d",
        tostring(IsUnitGrouped("player")),
        IsUnitGrouped("player") and GetGroupSize() or 0)
    DebugLog("Debug mode: %s", tostring(savedVars.debugMode))
    DebugLog("Enabled: %s", tostring(savedVars.enabled))

    combatStartTime = timestamp
    pullDetected = false
    currentBoss = nil
    firstHitData = {}

    DebugLog("First hit data reset, detection window: %dms", PULL_DETECTION_WINDOW)
    DebugLog("Timer started for DeterminePuller in %dms", PULL_DETECTION_WINDOW + 100)

    zo_callLater(function()
        DeterminePuller()
    end, PULL_DETECTION_WINDOW + 100)
end

-- Handler for Combat End
local function OnCombatEnd()
    DebugLog("=== Combat End detected ===")
    DebugLog("Pull detected: %s, Boss: %s", tostring(pullDetected), tostring(currentBoss))

    zo_callLater(function()
        DebugLog("Reset performed")
        pullDetected = false
        currentBoss = nil
        combatStartTime = 0
        firstHitData = {}
    end, 5000)
end

-- Initialization
local function Initialize()
    savedVars = ZO_SavedVars:NewAccountWide("WhoPulledSavedVars", 1, nil, defaultSettings)
    PULL_DETECTION_WINDOW = savedVars.detectionWindow or 5000

    DebugLog("WhoPulled initialized (Version %s)", WhoPulled.version)

    lgcs = LibGroupCombatStats.RegisterAddon(WhoPulled.name, { "DPS" })
    if not lgcs then
        d("|cFF0000[WhoPulled]|r Error: LibGroupCombatStats not found!")
        return
    end

    DebugLog("LibGroupCombatStats registration successful")

    -- Set event constants after LibGroupCombatStats becomes available
    EVENT_GROUP_DPS_UPDATE = LibGroupCombatStats.EVENT_GROUP_DPS_UPDATE
    EVENT_PLAYER_DPS_UPDATE = LibGroupCombatStats.EVENT_PLAYER_DPS_UPDATE
    DebugLog("Event constants set: GROUP=%s, PLAYER=%s", tostring(EVENT_GROUP_DPS_UPDATE),
        tostring(EVENT_PLAYER_DPS_UPDATE))

    lgcs:RegisterForEvent(EVENT_GROUP_DPS_UPDATE, OnGroupDPSUpdate)
    DebugLog("EVENT_GROUP_DPS_UPDATE callback registered")

    lgcs:RegisterForEvent(EVENT_PLAYER_DPS_UPDATE, OnGroupDPSUpdate)
    DebugLog("EVENT_PLAYER_DPS_UPDATE callback registered")

    EM:RegisterForEvent(WhoPulled.name .. "_PlayerCombat", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
        if not savedVars.enabled then return end
        if inCombat then OnCombatStart() else OnCombatEnd() end
    end)

    DebugLog("Combat event handler activated")

    SLASH_COMMANDS["/whopulled"] = function(cmd)
        if cmd == "toggle" then
            savedVars.enabled = not savedVars.enabled
            PrintMessage(string.format("WhoPulled is now %s",
                savedVars.enabled and "|c00FF00enabled|r" or "|cFF0000disabled|r"))
        elseif cmd == "debug" then
            savedVars.debugMode = not savedVars.debugMode
            PrintMessage(string.format("Debug mode is now %s",
                savedVars.debugMode and "|c00FF00enabled|r" or "|cFF0000disabled|r"))
        else
            PrintMessage("Commands: /whopulled toggle, /whopulled debug")
        end
    end

    PrintMessage(string.format("Version %s loaded. Use /whopulled for commands", WhoPulled.version))
    -- Create settings menu after a short delay (LAM may load later)
    zo_callLater(function()
        if CreateSettingsMenu then CreateSettingsMenu() end
    end, 1000)
end

EM:RegisterForEvent(WhoPulled.name, EVENT_ADD_ON_LOADED, function(event, addonName)
    if addonName == WhoPulled.name then
        EM:UnregisterForEvent(WhoPulled.name, EVENT_ADD_ON_LOADED)
        Initialize()
    end
end)
