--[[-----------------------------------------------------------------
 MultiFocus – v1.1  (2025‑04‑17)
  • Shows current / max health (and %)
  • Displays up‑to‑eight debuffs cast by *you* on the focus unit
 -------------------------------------------------------------------]]

local ADDON_NAME = ...
local MF         = {}
_G[ADDON_NAME]   = MF
print(ADDON_NAME)
---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local MAX_FOCUS     = 5  -- raise for more frames
local FRAME_W       = 130
local FRAME_H       = 38 -- bigger to fit debuff icons
local HEALTHBAR_H   = 18
local ICON_SIZE     = 16
local ICONS_PER_ROW = 8

---------------------------------------------------------------------
-- ANCHOR (drag to move – /mf lock toggles)
---------------------------------------------------------------------
local anchor        = CreateFrame("Frame", "MF_Anchor", UIParent, "BackdropTemplate")
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
anchor.text:SetText("MultiFocus (drag)")

---------------------------------------------------------------------
-- UTIL
---------------------------------------------------------------------
local function ColorGradient(p)
    if p <= .5 then return 1, p * 2, 0 end
    return 2 - p * 2, 1, 0
end

local function FindGroupUnit(guid)
    if UnitGUID("player") == guid then return "player" end
    if IsInRaid() then
        for i = 1, 40 do if UnitGUID("raid" .. i) == guid then return "raid" .. i end end
    elseif IsInGroup() then
        for i = 1, 4 do if UnitGUID("party" .. i) == guid then return "party" .. i end end
    end
end

---------------------------------------------------------------------
-- INTERNAL DATA
---------------------------------------------------------------------
MF.list   = {} -- [guid] = data
MF.frames = {} -- ordered array of frame objects

---------------------------------------------------------------------
-- DEBUFF UPDATE
---------------------------------------------------------------------
local function UpdateDebuffs(f)
    if not f.data.unitID or not UnitExists(f.data.unitID) then
        for i = 1, ICONS_PER_ROW do f.debuffIcons[i]:Hide() end
        return
    end

    local shown = 0
    for i = 1, 40 do
        local name, icon, _, _, debuffType, duration, expires, caster = UnitDebuff(f.data.unitID, i)
        if not name then break end
        if caster == "player" then
            shown = shown + 1
            if shown <= ICONS_PER_ROW then
                local tex = f.debuffIcons[shown]
                print("UPDATE SHOW?")
                tex:SetTexture(icon); tex:Show()
            end
        end
    end
    for i = shown + 1, ICONS_PER_ROW do -- hide unused
        f.debuffIcons[i]:Hide()
    end
end

---------------------------------------------------------------------
-- FRAME CREATION / UPDATE
---------------------------------------------------------------------
local function NewFocusFrame(data)
    local f = CreateFrame("Button", "MF_Frame" .. data.index, UIParent,
        "SecureActionButtonTemplate,BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("TOP", anchor, "BOTTOM", 0, -(data.index - 1) * FRAME_H)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0, 0, 0, .55)
    f.data = data

    -------------------------------------------------------------------
    -- secure click behaviour
    -------------------------------------------------------------------
    if data.unitID then
        f:SetAttribute("unit", data.unitID)
        f:SetAttribute("type1", "target")
        f:SetAttribute("*type2", "menu")
        RegisterUnitWatch(f)
    else
        f:SetAttribute("type", "macro")
        f:SetAttribute("macrotext", "/targetexact " .. data.name)
    end

    -------------------------------------------------------------------
    -- HEALTH BAR + TEXT
    -------------------------------------------------------------------
    local hp = CreateFrame("StatusBar", nil, f)
    hp:SetPoint("TOPLEFT", 2, -2)
    hp:SetPoint("TOPRIGHT", -2, -2)
    hp:SetHeight(HEALTHBAR_H - 4)
    hp:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    hp:SetMinMaxValues(0, 1)
    f.hp = hp

    f.nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("LEFT", 4, 0)
    f.nameText:SetText(data.name)

    f.hpValue = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hpValue:SetPoint("RIGHT", -4, 0)

    -------------------------------------------------------------------
    -- DEBUFF ICONS
    -------------------------------------------------------------------
    f.debuffIcons = {}
    for i = 1, ICONS_PER_ROW do
        local icon = f:CreateTexture(nil, "OVERLAY")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetPoint("TOPLEFT", 2 + (i - 1) * (ICON_SIZE + 2), -HEALTHBAR_H - 2)
        icon:Hide()
        f.debuffIcons[i] = icon
    end

    -- simple tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.data.name)
        print("ON ENTER SHOW")
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    MF.frames[data.index] = f
    UpdateFocusFrame(f, data.unitID)
    f:Show()
end

function UpdateFocusFrame(f, unitName)
    local guid = f.data.guid
    -- print("UNIT ID? " .. unit)
    print("GUID: " .. f.data.guid)
    if guid and UnitExists(unitName) and UnitGUID(unitName) == f.data.guid then
        print("HERE")
        local cur, max = UnitHealth(unitName), UnitHealthMax(unitName)
        f.hp:SetMinMaxValues(0, max); f.hp:SetValue(cur)
        f.hp:SetStatusBarColor(ColorGradient(max > 0 and cur / max or 0))
        f.hpValue:SetFormattedText("%d/%d (%.0f%%)", cur, max, (max > 0 and cur / max * 100 or 0))
        f.nameText:SetTextColor(1, 1, 1)
    else
        print("NOT HERE")
        f.hp:SetMinMaxValues(0, 1); f.hp:SetValue(0)
        f.hp:SetStatusBarColor(.4, .4, .4)
        f.hpValue:SetText("")
        f.nameText:SetTextColor(.6, .6, .6)
    end
    UpdateDebuffs(f)
end

---------------------------------------------------------------------
-- CORE OPERATIONS (unchanged)
---------------------------------------------------------------------
function MF:Add()
    if not UnitExists("target") then
        print("|cff33ff99MF|r: No target selected."); return
    end
    local guid = UnitGUID("target")
    if self.list[guid] then
        print("|cff33ff99MF|r: " .. UnitName("target") .. " already focused."); return
    end
    if #self.frames >= MAX_FOCUS then
        print("|cff33ff99MF|r: Maximum of " .. MAX_FOCUS .. " focus frames reached."); return
    end

    local data = {
        guid   = guid,
        name   = UnitName("target"),
        unitID = FindGroupUnit(guid),
        index  = #self.frames + 1,
    }
    self.list[guid] = data
    NewFocusFrame(data)
end

function MF:Remove(arg)
    if not arg or arg == "" then
        print("|cff33ff99MF|r: /mf clear <name|index>"); return
    end
    local guid
    if tonumber(arg) then
        for g, d in pairs(self.list) do if d.index == tonumber(arg) then guid = g end end
    else
        for g, d in pairs(self.list) do if d.name:lower() == arg:lower() then guid = g end end
    end
    if not guid then
        print("|cff33ff99MF|r: Focus target not found."); return
    end
    local idx = self.list[guid].index
    if MF.frames[idx] then MF.frames[idx]:Hide() end
    table.remove(MF.frames, idx)
    MF.list[guid] = nil
    for i, frame in ipairs(MF.frames) do
        frame.data.index = i
        frame:SetPoint("TOP", anchor, "BOTTOM", 0, -(i - 1) * FRAME_H)
        frame:SetName("MF_Frame" .. i)
    end
end

function MF:ClearAll()
    for _, frame in ipairs(self.frames) do
        frame:Hide()
    end
    wipe(self.frames); wipe(self.list)
end

---------------------------------------------------------------------
-- EVENTS
---------------------------------------------------------------------
local e = CreateFrame("Frame")
e:RegisterEvent("PLAYER_LOGIN")
e:RegisterEvent("UNIT_HEALTH_FREQUENT")
e:RegisterEvent("UNIT_AURA")
e:RegisterEvent("GROUP_ROSTER_UPDATE")
-- e:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

e:SetScript("OnEvent", function(_, ev, arg1)
    if ev == "PLAYER_LOGIN" then
        print("|cff33ff99MultiFocus|r v1.1 loaded – /mf add to focus target.")
    elseif ev == "UNIT_HEALTH_FREQUENT" or ev == "UNIT_AURA" then
        print("UNIT HEALTH FREQUENT? " .. arg1)
        local guid = UnitGUID(arg1)
        print("UNIT HEALTH FREQUENT? " .. guid)

        local data = guid and MF.list[guid]
        if data then UpdateFocusFrame(MF.frames[data.index], arg1) end
    elseif ev == "GROUP_ROSTER_UPDATE" then
        for guid, data in pairs(MF.list) do
            data.unitID = FindGroupUnit(guid)
            local f = MF.frames[data.index]
            if f and data.unitID then
                f:SetAttribute("unit", data.unitID)
                f:SetAttribute("type1", "target")
                f:SetAttribute("*type2", "menu")
            end
        end
    end
end)

---------------------------------------------------------------------
-- SLASH COMMANDS (unchanged)
---------------------------------------------------------------------
SLASH_MULTIFOCUS1, SLASH_MULTIFOCUS2 = "/mf", "/multifocus"
SlashCmdList.MULTIFOCUS = function(msg)
    msg = (msg or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    if msg == "" then
        print("|cff33ff99MultiFocus|r:",
            "/mf add – add current target",
            "/mf clear <name|#> – remove one",
            "/mf clearall – remove all",
            "/mf lock – lock/unlock frames")
    elseif msg == "add" then
        MF:Add()
    elseif msg:match("^clear%s") then
        MF:Remove(msg:match("^clear%s+(.+)$") or "")
    elseif msg == "clearall" then
        MF:ClearAll()
    elseif msg == "lock" then
        local locked = not anchor:IsMovable()
        anchor:SetMovable(locked); anchor:EnableMouse(locked)
        anchor.text:SetShown(locked)
        print("|cff33ff99MF|r anchor " .. (locked and "unlocked (drag to move)." or "locked."))
    else
        print("|cff33ff99MF|r: Unknown command – /mf for help.")
    end
end
