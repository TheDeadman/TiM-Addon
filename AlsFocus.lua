-- Multi Focus

local ADDON_NAME = ...
local MF         = {}
_G[ADDON_NAME]   = MF
print(ADDON_NAME)
-- config
local MAX_FOCUS              = 5  -- raise for more frames
local FRAME_W                = 130
local FRAME_H                = 50 -- bigger to fit debuff icons
local HEALTHBAR_H            = 18
local ICON_SIZE              = 20
local ICONS_PER_ROW          = 8

-- Warning Vars
local NOTIFICATION_ICON_SIZE = 16                                           -- 16 × 16 px
local ICON_PATH              = "Interface\\GossipFrame\\AvailableQuestIcon" -- yellow “!”
local TOOLTIP_TEXT           = "Cannot find matching target.\nLeft click to requery by name.\nRight click to remove."

-- Dispellable debuff state
local letters                = { "C", "D", "P", "M" }
local fullWords              = { "Curse", "Disease", "Poison", "Magic" }
local enabledTable           = { Curse = false, Disease = false, Poison = false, Magic = false }

-- Anchors
local anchor                 = CreateFrame("Frame", "MF_Anchor", UIParent, "BackdropTemplate")
anchor:SetSize(FRAME_W, HEALTHBAR_H)
anchor:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
anchor:SetMovable(true)
anchor:EnableMouse(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", anchor.StopMovingOrSizing)
anchor:SetClampedToScreen(true)
anchor:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
anchor:SetBackdropColor(0, 0, 0, .35)
anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchor.text:SetPoint("CENTER")
anchor.text:SetText("TiMFocus (drag)")

-- Utils
local function getTruncatedText(text, maxLength)
    if #text > maxLength then
        return strsub(text, 1, maxLength) .. "..."
    end
    return text
end

local function ColorGradient(p)
    if p <= .5 then return 1, p * 2, 0 end
    return 2 - p * 2, 1, 0
end

local function FindGroupUnit(guid)
    if UnitGUID("player") == guid then
        return "player"
    end
    if IsInRaid() then
        for i = 1, 40 do
            if UnitGUID("raid" .. i) == guid then
                return "raid" .. i
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            if UnitGUID("party" .. i) == guid then
                return "party" .. i
            end
        end
    end
end

local function tableLength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- Internal tracking data
MF.list        = {}
MF.frames      = {}

_G['TIMFOCUS'] = MF

-- Debuff Updater
local function UpdateDebuffs(f, unitName)
    local shown = 0
    for i = 1, 140 do
        local name, spellId, _, debuffType, duration, expirationTime, unitCaster, _, _, someId = UnitDebuff(unitName, i)
        if not name then break end
        if unitCaster == "player" then
            shown = shown + 1
            if shown <= ICONS_PER_ROW then
                local icon = f.debuffIcons[shown].icon
                local iconTexture = f.debuffIcons[shown].texture
                local progress = f.debuffIcons[shown].progress
                iconTexture:SetTexture(spellId)
                progress:SetCooldown(expirationTime - duration, duration)
                icon:Show()
            end
        end
    end

    -- Hide unused icons
    for i = shown + 1, ICONS_PER_ROW do
        f.debuffIcons[i].icon:Hide()
    end
end

-- Update debuffs on friendly units
local function UpdateDispellableDebuffs(f, unitName)
    local shown = 0
    for i = 1, 140 do
        local name, spellId, _, debuffType, duration, expirationTime, unitCaster, _, _, someId = UnitDebuff(unitName, i)
        if not name then break end
        if enabledTable[debuffType] then
            shown = shown + 1
            if shown <= ICONS_PER_ROW then
                local icon = f.debuffIcons[shown].icon
                local iconTexture = f.debuffIcons[shown].texture
                local progress = f.debuffIcons[shown].progress
                iconTexture:SetTexture(spellId)
                progress:SetCooldown(expirationTime - duration, duration)
                icon:Show()
            end
        end
    end

    -- Hide unused icons
    for i = shown + 1, ICONS_PER_ROW do
        f.debuffIcons[i].icon:Hide()
    end
end


-- Missing Focus Icon
local function AddFrameIcon(f)
    local exclaim = CreateFrame("Button", "Missing_Focus", f, "BackdropTemplate")
    exclaim:SetSize(NOTIFICATION_ICON_SIZE, NOTIFICATION_ICON_SIZE)
    exclaim:SetPoint("TOPRIGHT", 16, 0)
    exclaim:SetFrameStrata("HIGH")
    exclaim:RegisterForClicks("AnyUp")
    exclaim:Hide()

    -- Background
    -- A 1-pixel white texture lets us tint to any colour
    exclaim:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    -- RGBA:  r, g, b, alpha   (here: dark grey, 80 % opaque)
    exclaim:SetBackdropColor(0.8, 0.15, 0.15, 0.8)

    -- Icon
    local tex = exclaim:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(ICON_PATH)

    -- Highlight
    local hl = exclaim:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    -- ToolTip Handlers
    exclaim:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(TOOLTIP_TEXT, 1, 0.82, 0) -- gold text
        GameTooltip:Show()
    end)
    exclaim:SetScript("OnLeave", GameTooltip_Hide)

    f.data.missingIcon = exclaim

    -- Allow the addon to attempt to find the unit again by name or remove the entry
    exclaim:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unit = plate.namePlateUnitToken -- e.g. "nameplate7"
                local unitGuid = UnitGUID(unit)
                local unitName = UnitName(unit)
                if unitName == f.data.name and unitGuid then
                    local data = {
                        guid        = unitGuid,
                        name        = unitName,
                        unitID      = FindGroupUnit(unitGuid),
                        found       = true,
                        missingIcon = f.data.missingIcon
                        -- index  = #self.frames + 1,
                    }
                    MF.frames[f.data.guid] = nil
                    MF.list[f.data.guid] = nil
                    MF.list[unitGuid] = data
                    MF:UpdateExistingFrame(f, data, unit)

                    break
                end
            end
        elseif button == "RightButton" then
            MF:Remove(f.data.guid)
        end
    end)
end


-- Frame Creation
local function NewFocusFrame(data)
    local f = CreateFrame("Button", "MF_Frame" .. data.guid, UIParent,
        "SecureActionButtonTemplate,BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("TOP", anchor, "BOTTOM", 0, -(tableLength(MF.frames)) * FRAME_H)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    -- f:SetBackdropBorderColor(1, 0.5, 0.5, 1)
    f.data = data

    -- Secure click stuff
    if data.unitID then
        f:SetAttribute("unit", data.unitID)
        f:SetAttribute("type1", "target")
        f:SetAttribute("*type2", "menu")
        RegisterUnitWatch(f)
        f:SetBackdropColor(0, 6, 0, .25)
    else
        f:SetBackdropColor(6, 0, 0, .25)
        f:SetAttribute("type", "macro")
        f:SetAttribute("macrotext", "/targetexact " .. data.name)
    end

    -- Health bar and text
    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetPoint("TOPLEFT", 2, -2)
    hp:SetPoint("TOPRIGHT", -2, -2)
    hp:SetHeight(HEALTHBAR_H - 4)
    hp:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hp:SetMinMaxValues(0, 1)
    f.hp = hp

    f.nameText = hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("LEFT", 4, 0)
    f.nameText:SetText(getTruncatedText(data.name, 12))

    f.hpValue = hp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hpValue:SetPoint("RIGHT", -4, 0)

    -- Debuff icons
    f.debuffIcons = {}
    for i = 1, ICONS_PER_ROW do
        local icon = CreateFrame("Frame", "CD_ICON", f)
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", f, 2 + (i - 1) * (ICON_SIZE + 2), -HEALTHBAR_H - 2)
        icon:Show()

        local texture = icon:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(20920)
        texture:SetAllPoints(true)

        local iconProgress = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        iconProgress:SetAllPoints(icon)

        f.debuffIcons[i] = { icon = icon, texture = texture, progress = iconProgress }
    end

    -- simple tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.data.name)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    MF.frames[data.guid] = f

    AddFrameIcon(f)
    if data.unitID then
        UpdateFocusFrame(f, data.unitID)
    else
        UpdateFocusFrame(f, "target")
    end
    f:Show()
end

-- Frame Creation
function MF:UpdateExistingFrame(existingFrame, data, plateName)
    local f = existingFrame
    UnregisterUnitWatch(f)
    f.data = data

    -- Secure click stuff
    if data.unitID then
        f:SetAttribute("unit", data.unitID)
        f:SetAttribute("type1", "target")
        f:SetAttribute("*type2", "menu")
        RegisterUnitWatch(f)
        f:SetBackdropColor(0, 6, 0, .25)
    else
        f:SetBackdropColor(6, 0, 0, .25)
        f:SetAttribute("type", "macro")
        f:SetAttribute("macrotext", "/targetexact " .. data.name)
    end

    MF.frames[data.guid] = f

    UpdateFocusFrame(f, plateName)
end

function UpdateFocusFrame(f, unitName)
    local guid = f.data.guid

    -- Hide the
    f.data.missingIcon:Hide()

    if unitName == "MISSING" then
        f.hpValue:SetFormattedText("????")
        f.data.missingIcon:Show()
        -- f.nameText:SetTextColor(1, 1, 1)
    elseif guid and UnitExists(unitName) and UnitGUID(unitName) == f.data.guid then
        local cur, max = UnitHealth(unitName), UnitHealthMax(unitName)
        f.hp:SetMinMaxValues(0, max); f.hp:SetValue(cur)
        f.hp:SetStatusBarColor(ColorGradient(max > 0 and cur / max or 0))
        f.hpValue:SetFormattedText("(%.0f%%)", (max > 0 and cur / max * 100 or 0))
        f.nameText:SetTextColor(1, 1, 1)
    else
        f.hp:SetMinMaxValues(0, 1)
        f.hp:SetValue(0)
        f.hp:SetStatusBarColor(.4, .4, .4)
        f.hpValue:SetText("")
        f.nameText:SetTextColor(.6, .6, .6)
    end

    -- If it has a unitID then assume it is friendly
    if f.data.unitID then
        UpdateDispellableDebuffs(f, unitName)
    else
        UpdateDebuffs(f, unitName)
    end
end

local function ReorderFrames()
    local count = 0
    for _, f in pairs(MF.frames) do
        f:SetPoint("TOP", anchor, "BOTTOM", 0, -(count) * FRAME_H)
        count = count + 1
    end
end

-- core
function MF:Add()
    if not UnitExists("target") then
        print("|cff33ff99MF|r: No target selected."); return
    end
    local guid = UnitGUID("target")
    if self.list[guid] then
        print("|cff33ff99MF|r: " .. UnitName("target") .. " already focused.");
        return
    end
    if #self.frames >= MAX_FOCUS then
        print("|cff33ff99MF|r: Maximum of " .. MAX_FOCUS .. " focus frames reached.");
        return
    end


    print(
        "|cff33ff99TiMFocus|r: Added focus frame. NOTE: If a unit despawns / respawns, E.G. Scarlet Enclave Council fight, you must clear / refocus the targets.")
    local data = {
        guid   = guid,
        name   = UnitName("target"),
        unitID = FindGroupUnit(guid),
        found  = true
        -- index  = #self.frames + 1,
    }
    self.list[guid] = data
    NewFocusFrame(data)
end

function MF:Remove(unitGuid)
    local targetGuid = UnitGUID('target')

    if unitGuid then
        targetGuid = unitGuid
    end

    if targetGuid == nil then
        print("|cff33ff99MF|r: Select a target to remove from the list"); return
    end

    local guid

    for listEntryGuid, listEntry in pairs(self.list) do
        if listEntryGuid:lower() == targetGuid:lower() then
            guid = listEntryGuid
        end
    end


    if not guid then
        print("|cff33ff99MF|r: Focus target not found."); return
    end
    if MF.frames[guid] then
        UnregisterUnitWatch(MF.frames[guid])
        MF.frames[guid]:Hide()
    end

    MF.frames[guid] = nil
    MF.list[guid] = nil

    ReorderFrames()
end

function MF:ClearAll()
    if InCombatLockdown() then
        print("CANNOT CLEAR DURING COMBAT")
        return
    end
    for _, frame in pairs(self.frames) do
        UnregisterUnitWatch(frame)
        frame:Hide()
    end
    wipe(self.frames); wipe(self.list)
end

-- Dispell toggle buttons
-- MyToggleButtons.lua
-- Classic WoW  ►  four 16 × 16 toggle buttons: “C”, “D”, “P”, “M” in one row.


local spacing = 4  -- gap between buttons (pixels)
local anchorX = 10 -- screen‑position tweak
local anchorY = 12

local buttons = {}

for i, ch in ipairs(letters) do
    local b = CreateFrame("CheckButton", "ToggleDispels-" .. ch, UIParent)
    b:SetSize(16, 16)

    -- position them left‑to‑right
    if i == 1 then
        b:SetPoint("TOPLEFT", anchor, "TOPLEFT", anchorX, anchorY)
    else
        local index = i - 1;
        b:SetPoint("LEFT", buttons[index], "RIGHT", spacing, 0)
    end

    -- basic textures
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD") -- mouse‑over glow
    b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")     -- lit when toggled ON

    -- single‑letter label
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("CENTER")
    txt:SetText(ch)

    -- (optional) react to clicks
    b:SetScript("OnClick", function(self)
        local on = self:GetChecked() -- true when highlighted
        local category = fullWords[i]
        enabledTable[category] = on
        -- add your custom logic here
    end)

    buttons[i] = b
end


-- Events
local e = CreateFrame("Frame")
e:RegisterEvent("PLAYER_LOGIN")
e:RegisterEvent("UNIT_HEALTH_FREQUENT")
e:RegisterEvent("UNIT_AURA")
e:RegisterEvent("GROUP_ROSTER_UPDATE")
e:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
e:RegisterEvent("NAME_PLATE_UNIT_ADDED")
e:SetScript("OnEvent", function(_, _, unit)
    local guid = UnitGUID(unit)
    local frame = guid and watching[guid]
    if frame then
        frame:Hide()
        watching[guid] = nil
        print(("Unit vanished: |cffff7070%s|r (%s)"):format(UnitName(unit) or "???", guid))
    end
end)
-- e:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

e:SetScript("OnEvent", function(_, ev, arg1)
    if ev == "NAME_PLATE_UNIT_REMOVED" then
        for _, f in pairs(MF.frames) do
            f.data.found = false
        end

        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.namePlateUnitToken -- e.g. "nameplate7"
            local unitGuid = UnitGUID(unit)
            local focusFrame = MF.frames[unitGuid]
            if focusFrame then
                focusFrame.data.found = true
            end
        end

        for _, f in pairs(MF.frames) do
            if f.data.found == false then
                UpdateFocusFrame(f, "MISSING")
            end
        end
    elseif ev == "NAME_PLATE_UNIT_ADDED" then
        local unitGuid = UnitGUID(arg1)
        local unitFrame = MF.frames[unitGuid]
        if unitFrame then
            UpdateFocusFrame(unitFrame, arg1)
        end
    elseif ev == "PLAYER_LOGIN" then
        print("|cff33ff99TiMFocus|r v1.1 loaded – /timfocus add to focus target.")
    elseif ev == "UNIT_HEALTH_FREQUENT" or ev == "UNIT_AURA" then
        local guid = UnitGUID(arg1)

        local data = guid and MF.list[guid]
        if data then UpdateFocusFrame(MF.frames[data.guid], arg1) end
    elseif ev == "GROUP_ROSTER_UPDATE" then
        for guid, data in pairs(MF.list) do
            data.unitID = FindGroupUnit(guid)
            local f = MF.frames[data.guid]
            if f and data.unitID then
                f:SetAttribute("unit", data.unitID)
                f:SetAttribute("type1", "target")
                f:SetAttribute("*type2", "menu")
            end
        end
    end
end)

-- Slash Commands
SLASH_MULTIFOCUS1, SLASH_MULTIFOCUS2 = "/timfocus", "/timf"
SlashCmdList.MULTIFOCUS = function(msg)
    msg = (msg or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    if msg == "" then
        print("|cff33ff99TiMFocus|r:\n",
            "/timfocus add – add current target\n",
            "/timfocus remove – remove current target\n",
            "/timfocus clear - remove all focus targets\n",
            "/timfocus lock – lock frames\n",
            "/timfocus unlock – unlock frames\n")
    elseif msg == "add" then
        MF:Add()
    elseif msg == "remove" then
        MF:Remove()
    elseif msg == "clearall" or msg == "clear" then
        MF:ClearAll()
    elseif msg == "lock" then
        anchor:SetMovable(false); anchor:EnableMouse(false)
        anchor.text:SetShown(false)
        print("|cff33ff99MF|r anchor locked")
    elseif msg == "unlock" then
        anchor:SetMovable(true); anchor:EnableMouse(true)
        anchor.text:SetShown(true)
        print("|cff33ff99MF|r anchor unlocked (drag to move).")
    else
        print("|cff33ff99MF|r: Unknown command – /timfocus for help.")
    end
end
