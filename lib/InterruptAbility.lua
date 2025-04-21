local SkillCheckFrame         = CreateFrame("Frame", "SkillCheckFrame");

AlsTiMAbilities               = {}
-- class‑to‑interrupt mapping (spell names, not IDs, to survive rank differences)
local CLASS_INTERRUPT         = {
    ROGUE   = GetSpellInfo(1766),   -- Kick
    WARRIOR = GetSpellInfo(6552),   -- Pummel
    SHAMAN  = GetSpellInfo(8042),   -- Earth Shock
    MAGE    = GetSpellInfo(2139),   -- Counterspell
    PALADIN = GetSpellInfo(425609), -- Rebuke
    -- WARLOCK = GetSpellInfo(403501), -- Haunt: For local debugging purposes
}
local CLASS_INTERRUPT_ID      = {
    ROGUE   = 1766,   -- Kick
    WARRIOR = 6552,   -- Pummel
    SHAMAN  = 8042,   -- Earth Shock
    MAGE    = 2139,   -- Counterspell
    PALADIN = 425609, -- Rebuke
    -- WARLOCK = 403501, -- Haunt
}

local playerClass             = select(2, UnitClass("player"))
AlsTiMAbilities.interruptName = CLASS_INTERRUPT[playerClass]
AlsTiMAbilities.interruptId   = CLASS_INTERRUPT_ID[playerClass]

-- Special spell id that can change depending on what skills the player knows
AlsTiMAbilities.bookSpellId   = 0

local function SetSpellId()
    -- Short Circuit if we know there is no spell
    if AlsTiMAbilities.interruptId == nil then
        return
    end

    local i = 1
    while true do
        local spellName, spellRank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
        if not spellName then
            do break end
        end

        if spellName == AlsTiMAbilities.interruptName then
            AlsTiMAbilities.bookSpellId = i
            break
        end
        i = i + 1
    end
end

SkillCheckFrame:RegisterEvent("SPELLS_CHANGED")
SkillCheckFrame:SetScript("OnEvent", function(_, event, arg1)
    SetSpellId();
end)
