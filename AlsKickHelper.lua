--------------------------------------------------------------------------------
-- KickSync - simple group interrupt rotation helper for Classic WoW
--------------------------------------------------------------------------------
local ADDON, KS       = ...

--------------------------------------------------------------------------------
-- basic constants -------------------------------------------------------------
--------------------------------------------------------------------------------
local PREFIX          = "KickSync" -- Addon‑message prefix (≤16 chars)
local MAX_LINES       = 10         -- How many names to show
local UPDATE_INTERVAL = 0.5        -- How often to poll cooldown
local playerName      = UnitName("player")


--------------------------------------------------------------------------------
-- utility helpers -------------------------------------------------------------
--------------------------------------------------------------------------------
local function UnitTargetGUID()
    return UnitExists("target") and UnitGUID("target") or nil
end

local function Send(msg)
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
end

--------------------------------------------------------------------------------
-- state data ------------------------------------------------------------------
--------------------------------------------------------------------------------

local readyQueue        = {} -- ordered list: { {name=string, guid=string} , ... }
local hasEntry          = {} -- quick lookup: name => true/false
local timerPool         = {} -- recycled C_Timer handles so we do not leak them

_G["AlsKickReadyQueue"] = readyQueue
_G["AlsKickHasEntry"]   = hasEntry

--------------------------------------------------------------------------------
-- simple UI -------------------------------------------------------------------
--------------------------------------------------------------------------------
local f                 = CreateFrame("Frame", "KickSyncFrame", UIParent, "BackdropTemplate")
KS.frame                = f
f:SetSize(160, 20 + MAX_LINES * 14)
f:SetPoint("LEFT", 20, 0)
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOP", 0, -6)
title:SetText("KickSync")

-- create line objects once
f.lines = {}
for i = 1, MAX_LINES do
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontWhiteSmall")
    txt:SetPoint("TOPLEFT", 8, -6 - i * 14)
    txt:SetWidth(144)
    txt:SetJustifyH("LEFT")
    txt:Hide()
    f.lines[i] = txt
end

local function UpdateDisplay()
    local tgt = UnitTargetGUID()
    local shown = 0
    for _, entry in ipairs(readyQueue) do
        if entry.guid and entry.guid == tgt then
            shown = shown + 1
            if shown <= MAX_LINES then
                f.lines[shown]:SetText(entry.name)
                f.lines[shown]:Show()
            end
        end
    end
    -- hide unused rows
    for i = shown + 1, MAX_LINES do
        f.lines[i]:Hide()
    end
    f:SetShown(shown > 0)
end

--------------------------------------------------------------------------------
-- queue helpers ---------------------------------------------------------------
--------------------------------------------------------------------------------
local function RemoveFromQueue(name)
    if not hasEntry[name] then return end
    for i = #readyQueue, 1, -1 do
        if readyQueue[i].name == name then
            table.remove(readyQueue, i)
        end
    end
    hasEntry[name] = nil
end

local function AddToQueue(name, guid)
    print("ADD TO QUEUE: " .. name)
    RemoveFromQueue(name)
    readyQueue[#readyQueue + 1] = { name = name, guid = guid }
    hasEntry[name] = true
end

--------------------------------------------------------------------------------
-- cooldown polling (local player only) ----------------------------------------
--------------------------------------------------------------------------------
local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    if not AlsTiMAbilities.interruptName then return end
    local start, dur = GetSpellCooldown(AlsTiMAbilities.interruptName)
    local ready = (start == 0) or (dur == 0)
    if ready and not hasEntry[playerName] and UnitTargetGUID() then
        -- broadcast & show we are ready
        local guid = UnitTargetGUID()
        Send("READY:" .. guid)
        AddToQueue(playerName, guid)
        UpdateDisplay()
    end
end)

--------------------------------------------------------------------------------
-- event engine ----------------------------------------------------------------
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
KS.eventFrame = ev

ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon ~= ADDON then return end
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        -- announce existing status once UI is ready
        C_Timer.After(3, function()
            if AlsTiMAbilities.interruptName and UnitTargetGUID() then
                Send("READY:" .. UnitTargetGUID())
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX or sender == playerName then return end

        local cmd, arg = msg:match("^(%u+):(.+)$")
        print("MSG: " .. msg)
        print("CMD: " .. cmd)
        print("ARG: " .. arg)

        if not cmd then return end
        if cmd == "READY" then
            local guid = arg
            AddToQueue(sender, guid)
            UpdateDisplay()
        elseif cmd == "USED" then
            RemoveFromQueue(sender)
            UpdateDisplay()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- prune list whenever you change targets
        UpdateDisplay()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- remove people who left
        for i = #readyQueue, 1, -1 do
            if not UnitInParty(readyQueue[i].name) and not UnitInRaid(readyQueue[i].name) then
                table.remove(readyQueue, i)
            end
        end
        UpdateDisplay()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" or not AlsTiMAbilities.interruptName then return end
        if spellID == select(7, GetSpellInfo(AlsTiMAbilities.interruptName)) then
            -- we just kicked – broadcast usage & drop from list
            local guid = UnitTargetGUID() or "0"
            Send("USED:" .. guid)
            RemoveFromQueue(playerName)
            UpdateDisplay()

            -- schedule re‑add when CD is about to finish, +0.1s buffer
            local s, d = GetSpellCooldown(AlsTiMAbilities.interruptName)
            if d and d > 0 then
                C_Timer.After(d + 0.1, function()
                    local g = UnitTargetGUID()
                    if g then
                        Send("READY:" .. g)
                        AddToQueue(playerName, g)
                        UpdateDisplay()
                    end
                end)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- slash commands --------------------------------------------------------------
--------------------------------------------------------------------------------
SLASH_KICKSYNC1, SLASH_KICKSYNC2 = "/ks", "/kicksync"
SlashCmdList["KICKSYNC"] = function(msg)
    if msg == "reset" then
        f:ClearAllPoints()
        f:SetPoint("LEFT", 20, 0)
    else
        if f:IsShown() then f:Hide() else f:Show() end
    end
end
