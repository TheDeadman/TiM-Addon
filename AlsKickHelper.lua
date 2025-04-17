--[[--------------------------------------------------------------------
 ▄█    ▄   ████▄ ██   █    ▄   ▄█▄    ▄█    ▄   ▄███▄   ▄█      ▄   ▄███▄
 █ █  █    █   █ █ █  █     █  █▀ ▀▄  ██    █    █▀   ▀  ██       █  █▀   ▀
 █ ▄  █    █   █ █▄▄█ █ ██   █ █   ▄▀ ██ █   █ ▄ █▀▀      ██ █     █ █▀▀
 █  █ █    ▀████ █  █ █ █ █  █ █▄  ▀█ █ █ █  █  █        ▐█ █  █   █ █
 █   ██        █   █  █ █  █ █  ▀███▀ █  █  █    █        ▐ █   █▄█      v1.0
             █   █  █  █   █
             █   █  █  █   █             by You
---------------------------------------------------------------------]]

local addonName, addon = ...
local f                = CreateFrame("Frame")

------------------------------------------------------------
--  Internal state
------------------------------------------------------------
local playerName       = UnitName("player")
local myKickTargetGUID = nil -- GUID of YOUR target
local assignments      = {}  -- [playerName] = guid

------------------------------------------------------------
--  Utilities
------------------------------------------------------------
local function trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
local function inGroup(name)
    return UnitInRaid(name) or UnitInParty(name) or name == playerName
end

------------------------------------------------------------
--  UI
------------------------------------------------------------
local function CreateUI()
    local ui = CreateFrame("Frame", "KickerFrame", UIParent, "BackdropTemplate")
    ui:SetSize(160, 60)
    ui:SetPoint("CENTER", 0, 200)
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)

    ui:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    ui:SetBackdropColor(0, 0, 0, 0.7)

    ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.title:SetPoint("TOP", 0, -6)
    ui.title:SetText("|cff00ff00Kick Assist|r")

    ui.lines = {}
    for i = 1, 8 do
        local fs = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 10, -6 - i * 14)
        fs:SetText("")
        ui.lines[i] = fs
    end

    ui:Hide()
    addon.ui = ui
end

local function UpdateUI()
    local ui = addon.ui; if not ui then return end
    local guid = myKickTargetGUID
    if not guid then
        ui:Hide()
        return
    end

    local list = {}
    for p, g in pairs(assignments) do
        if g == guid then tinsert(list, p) end
    end
    table.sort(list)

    for i = 1, #ui.lines do
        ui.lines[i]:SetText(list[i] or "")
    end

    ui:SetHeight(28 + #list * 14)
    ui:Show()
end

------------------------------------------------------------
--  Networking
------------------------------------------------------------
local PREFIX = "KICKER"

local function SendUpdate(guidOrClear)
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if channel then
        C_ChatInfo.SendAddonMessage(PREFIX, guidOrClear, channel)
    end
end

local function HandleAddonMessage(msg, sender)
    if sender == playerName then return end
    if msg == "CLEAR" then
        assignments[sender] = nil
    else
        assignments[sender] = msg
    end
    UpdateUI()
end

------------------------------------------------------------
--  Slash commands
------------------------------------------------------------
SLASH_KICKER1 = "/kicker"
SlashCmdList.KICKER = function(msg)
    msg = trim(string.lower(msg or ""))
    if msg == "add" then
        local u = "target"
        if UnitExists(u) and UnitCanAttack("player", u) then
            local guid = UnitGUID(u)
            if guid then
                myKickTargetGUID        = guid
                assignments[playerName] = guid
                print("|cff00ff00[Kicker]|r Kick target set to |cffffff00" .. UnitName(u) .. "|r.")
                SendUpdate(guid)
                UpdateUI()
            else
                print("|cff00ff00[Kicker]|r Could not read target GUID.")
            end
        else
            print("|cff00ff00[Kicker]|r You must target an enemy first.")
        end
    elseif msg == "clear" then
        if myKickTargetGUID then
            myKickTargetGUID        = nil
            assignments[playerName] = nil
            print("|cff00ff00[Kicker]|r Kick target cleared.")
            SendUpdate("CLEAR")
            UpdateUI()
        end
    else
        print("|cff00ff00[Kicker]|r usage:")
        print("  /kicker add   - mark your current enemy as kick target")
        print("  /kicker clear - remove your kick target")
    end
end

------------------------------------------------------------
--  Event handler
------------------------------------------------------------
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        CreateUI()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- purge people who left group
        for p in pairs(assignments) do
            if not inGroup(p) then assignments[p] = nil end
        end
        UpdateUI()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _channel, sender = ...
        if prefix == PREFIX then HandleAddonMessage(msg, Ambiguate(sender, "none")) end
    end
end)
