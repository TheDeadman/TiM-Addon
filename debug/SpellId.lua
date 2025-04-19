-- Debug tool to log when someone in your party uses a skill
local addonName = ...

print("ADDON NAME: " .. addonName)

local PSL     = CreateFrame("Frame", "SpellIdFrame")
local party   = {} -- [GUID] = true for everyone currently in party (incl. player)
local enabled = true

-- Party Table
local function UpdatePartyTable()
    wipe(party)

    -- Player
    local playerGUID = UnitGUID("player")
    if playerGUID then party[playerGUID] = true end

    -- Up to 4 other party slots
    for i = 1, 4 do
        local unit = "party" .. i
        local guid = UnitGUID(unit)
        if guid then party[guid] = true end
    end
end

-- slash commands
SLASH_PARTYSKILLLOGGER1 = "/psl"
SlashCmdList.PARTYSKILLLOGGER = function(msg)
    msg = msg:lower()
    if msg == "off" or msg == "disable" then
        enabled = false
        print("|cff9999ff[PSL]|r Disabled.")
    elseif msg == "on" or msg == "enable" then
        enabled = true
        print("|cff9999ff[PSL]|r Enabled.")
    else
        print("|cff9999ff[PSL]|r usage: /psl on | off")
    end
end


PSL:SetScript("OnEvent", function(_, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        UpdatePartyTable()
        return
    end

    -- COMBAT_LOG_EVENT_UNFILTERED
    if not enabled then return end

    -- print('enabled')

    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool =
        CombatLogGetCurrentEventInfo()

    if eventType == "SPELL_CAST_SUCCESS" then
        -- print("time: " .. timestamp)
        -- print("eventType: " .. eventType)
        -- print("hide caster: " .. tostring(hideCaster))
        -- print("sourceGUID: " .. sourceGUID)
        -- print("sourceName: " .. sourceName)
        -- print("source flags?: " .. sourceFlags)
        -- print("source Raid Flags?: " .. sourceRaidFlags)
        -- print("destGUID: " .. destGUID)
        -- if destName then
        --     print("destName: " .. destName)
        -- end
        -- if destFlags then
        --     print("destRaidFlags?: " .. destFlags)
        -- end
        -- if destRaidFlags then
        --     print("destRaidFlags?: " .. destRaidFlags)
        -- end
        -- if spellID then
        --     print("spellID: " .. spellID)
        -- end
        -- if spellName then
        --     print("spellName: " .. spellName)
        -- end
        -- if spellSchool then
        --     print("spellSchool: " .. spellSchool)
        -- end

        -- Only SPELL_* events include spellId/name; ignore SWING_, RANGED_, etc.
        if not spellID or not spellName then return end

        -- Is the source one of our party members?
        if party[sourceGUID] then
            -- Show as: [PSL] Fireball (ID: 133)
            local msg = string.format("|cff9999ff[PSL]|r %s (ID: %d)", spellName, spellID)
            print(msg)
        end
    end
end)

------------------------------------------------------------
-- Init
------------------------------------------------------------
PSL:RegisterEvent("GROUP_ROSTER_UPDATE")
PSL:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
UpdatePartyTable() -- populate on load
print("|cff9999ff[PSL]|r Loaded – /psl on|off to toggle.")
