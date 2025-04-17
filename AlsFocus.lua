-- AlsFocusFrame Addon
local AlsFocusFrame = CreateFrame("Frame", "AlsFocusFrame", UIParent, "BackdropTemplate")
AlsFocusFrame:SetSize(150, 40)
AlsFocusFrame:SetPoint("CENTER")
AlsFocusFrame:Hide()

AlsFocusFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
AlsFocusFrame:SetBackdropColor(0, 0, 0, 1)

-- Make the frame moveable
AlsFocusFrame:SetMovable(true)
AlsFocusFrame:EnableMouse(true)
AlsFocusFrame:RegisterForDrag("LeftButton")
AlsFocusFrame:SetScript("OnDragStart", AlsFocusFrame.StartMoving)
AlsFocusFrame:SetScript("OnDragStop", AlsFocusFrame.StopMovingOrSizing)

-- Health bar
local healthBar = CreateFrame("StatusBar", nil, AlsFocusFrame)
healthBar:SetSize(130, 20)
healthBar:SetPoint("TOP", 0, -10)
healthBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
healthBar:SetStatusBarColor(0, 1, 0)

local healthBarBG = healthBar:CreateTexture(nil, "BACKGROUND")
healthBarBG:SetAllPoints()
healthBarBG:SetColorTexture(0.3, 0.3, 0.3, 0.8)

local healthText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
healthText:SetPoint("CENTER", healthBar)

-- Name text
local nameText = AlsFocusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
nameText:SetPoint("BOTTOM", healthBar, "TOP", 0, 5)

-- Variables for storing focused player data
local focusedUnit

-- Function to update health bar
local function UpdateHealth()
    if focusedUnit and UnitExists(focusedUnit) then
        local health = UnitHealth(focusedUnit)
        local maxHealth = UnitHealthMax(focusedUnit)
        healthBar:SetMinMaxValues(0, maxHealth)
        healthBar:SetValue(health)
        healthText:SetText(health .. " / " .. maxHealth)
    else
        AlsFocusFrame:Hide()
    end
end

-- Slash command to set focus
SLASH_ALFOCUS1 = "/alfocus"
SlashCmdList["ALFOCUS"] = function()
    if UnitExists("target") and UnitIsFriend("player", "target") then
        focusedUnit = UnitName("target")
        nameText:SetText(focusedUnit)
        AlsFocusFrame:Show()
        UpdateHealth()
    else
        print("Please target a friendly player to set as focus.")
    end
end

-- Click handler for casting Cleanse
healthBar:SetScript("OnMouseUp", function()
    if focusedUnit and IsSpellKnown("Cleanse") then
        CastSpellByName("Cleanse", focusedUnit)
    else
        print("Cleanse spell not available.")
    end
end)

-- Event handler for updating frame dynamically
AlsFocusFrame:RegisterEvent("UNIT_HEALTH")
AlsFocusFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
AlsFocusFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_HEALTH" and arg1 == focusedUnit then
        UpdateHealth()
    elseif event == "PLAYER_TARGET_CHANGED" and focusedUnit and not UnitExists(focusedUnit) then
        AlsFocusFrame:Hide()
    end
end)
