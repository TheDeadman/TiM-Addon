local InRange = CreateFrame("Frame", "InRangeFrame")

AlsTiMRange = {}

AlsTiMRange.isInRange = nil
AlsTiMRange.isTargettingEnemy = false
AlsTiMRange.currentEnemyTarget = nil


function AlsTiMRange.CheckKickRange()
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
    print("IS IN RANGE: " .. tostring(AlsTiMRange.isInRange))
end

InRange:RegisterEvent("SPELL_UPDATE_USABLE")
InRange:SetScript("OnEvent", function(_, event, arg1)
    AlsTiMRange.CheckKickRange()
end)
