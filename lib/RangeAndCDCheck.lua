local InRange = CreateFrame("Frame", "InRangeFrame")

AlsTiMRange = {}

AlsTiMRange.isInRange = nil
AlsTiMRange.isOnCD = false
AlsTiMRange.isTargettingEnemy = false
AlsTiMRange.currentEnemyTarget = nil


function AlsTiMRange.CheckKickRange()
    if not AlsTiMAbilities.bookSpellId then
        return
    end
    local inRange = IsSpellInRange(AlsTiMAbilities.bookSpellId, BOOKTYPE_SPELL, "target")

    if inRange == nil then
        AlsTiMRange.isInRange = false
        AlsTiMRange.isTargettingEnemy = false
    else
        AlsTiMRange.isTargettingEnemy = true
        if inRange == 1 then
            AlsTiMRange.isInRange = true
        else
            AlsTiMRange.isInRange = false
        end
    end
    -- print("IS IN RANGE: " .. tostring(AlsTiMRange.isInRange))
end

function AlsTiMRange.CheckCD()
    if not AlsTiMAbilities.interruptName then
        return
    end
    -- print("INTERRUPT ABILITY: " .. AlsTiMAbilities.interruptName)
    local start, dur, enabled = GetSpellCooldown(AlsTiMAbilities.interruptName)
    if enabled == 1 and dur > 2 then
        -- On CD
        -- print("ON CD")
        AlsTiMRange.isOnCD = true
        return
    end

    AlsTiMRange.isOnCD = false
end

InRange:RegisterEvent("SPELL_UPDATE_USABLE")
InRange:SetScript("OnEvent", function(_, event, arg1)
    AlsTiMRange.CheckKickRange()
    AlsTiMRange.CheckCD()
    if AlsTiMKickHelper then
        AlsTiMKickHelper.SendUpdate()
    end
end)


-- Create a timer to flash the text color every second
C_Timer.NewTicker(0.1, function()
    AlsTiMRange.CheckKickRange()
    AlsTiMRange.CheckCD()
    if AlsTiMKickHelper then
        AlsTiMKickHelper.SendUpdate()
    end
end)
