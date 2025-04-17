--------------------------------------------------------------------------------
-- KickSync 1.2.0 – multi‑target interrupt queue helper
-- (Classic Era / Season of Discovery)
-- v1.2.0 changes: after a player kicks they stay in the list, move to the
-- bottom, and their name turns RED until their cooldown finishes.
--------------------------------------------------------------------------------
local ADDON, KS       = ...

--------------------------------------------------------------------------------
-- constants -------------------------------------------------------------------
--------------------------------------------------------------------------------
local PREFIX          = "KickSync" -- Addon‑message prefix
local MAX_LINES       = 10         -- rows per watch frame
local UPDATE_INTERVAL = 0.5        -- seconds between local cooldown polls

--------------------------------------------------------------------------------
-- saved locals ----------------------------------------------------------------
--------------------------------------------------------------------------------
local playerName      = UnitName("player")

--------------------------------------------------------------------------------
-- WatchData data structure ---------------------------------------------------
--------------------------------------------------------------------------------
-- {
--     onCd = bool,
--     watching = { guid, guid, ... },
--     target = {
--         mobGuid = guid,
--         inRange = bool
--     },
--     readyTime = float
-- }

--------------------------------------------------------------------------------
-- watch‑list data structure ---------------------------------------------------
--------------------------------------------------------------------------------
--  watchList[guid] = {
--      mobName   = string,
--      frame     = Frame,
--      readyQ    = { {name=string} , ... },
--      hasEntry  = { [name]=true },
--      onCD      = { [name]=true }   -- true while spell on cooldown (red text)
--      selfWatchData = WatchData
--  }
local watchList       = {}


--------------------------------------------------------------------------------
-- watchers-list data structure ---------------------------------------------------
--------------------------------------------------------------------------------
-- watchersList[guid] = WatchData
local watcherList  = {}

-- ordered list of GUIDs so that frames are stacked consistently
local orderedGUIDs = {}
local function addGUIDOrdered(guid)
    for _, g in ipairs(orderedGUIDs) do if g == guid then return end end
    orderedGUIDs[#orderedGUIDs + 1] = guid
end
local function removeGUIDOrdered(guid)
    for i = #orderedGUIDs, 1, -1 do
        if orderedGUIDs[i] == guid then
            table.remove(orderedGUIDs, i)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- ui helpers -------------------------------------------------------------------
--------------------------------------------------------------------------------
local function CreateWatchFrame(guid, mobName)
    local f = CreateFrame("Frame", "KickSyncFrame" .. guid, UIParent, "BackdropTemplate")
    f:SetSize(160, 20 + MAX_LINES * 14)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetMovable(true); f:EnableMouse(true);
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving);
    f:SetScript("OnDragStop", f.StopMovingOrSizing);

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6)
    title:SetText(mobName)

    f.lines = {}
    for i = 1, MAX_LINES do
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontWhiteSmall")
        txt:SetPoint("TOPLEFT", 8, -6 - i * 14)
        txt:SetWidth(144)
        txt:SetJustifyH("LEFT")
        txt:Hide()
        f.lines[i] = txt
    end
    return f
end

local function LayoutFrames()
    local anchorY = 0
    for _, guid in ipairs(orderedGUIDs) do
        local w = watchList[guid]
        if w then
            local f = w.frame
            f:ClearAllPoints()
            f:SetPoint("LEFT", 20, anchorY)
            anchorY = anchorY - (f:GetHeight() + 6)
        end
    end
end

--------------------------------------------------------------------------------
-- queue helpers (per‑guid) -----------------------------------------------------
--------------------------------------------------------------------------------
local function RemoveFromQueue(watch, name)
    if not watch.hasEntry[name] then return end
    for i = #watch.readyQ, 1, -1 do
        if watch.readyQ[i].name == name then table.remove(watch.readyQ, i) end
    end
    watch.hasEntry[name] = nil
    watch.onCD[name] = nil
end

local function AddToQueue(watch, name, isOnCooldown)
    RemoveFromQueue(watch, name)
    watch.readyQ[#watch.readyQ + 1] = { name = name }
    watch.hasEntry[name] = true
    if isOnCooldown then watch.onCD[name] = true else watch.onCD[name] = nil end
end

-- when a player kicks: push to bottom & mark as on‑CD (red)
local function MarkUsed(watch, name)
    if not watch.hasEntry[name] then return end
    -- remove then re‑add at bottom with on‑CD flag
    RemoveFromQueue(watch, name)
    AddToQueue(watch, name, true)
end

local function UpdateDisplayFor(guid)
    local watch = watchList[guid]; if not watch then return end
    local f = watch.frame
    local shown = 0
    for _, entry in ipairs(watch.readyQ) do
        shown = shown + 1
        if shown <= MAX_LINES then
            local txtObj = f.lines[shown]
            txtObj:SetText(entry.name)
            -- colour: red while on cooldown, white otherwise
            if watch.onCD[entry.name] then
                txtObj:SetTextColor(1, 0, 0)
            else
                txtObj:SetTextColor(1, 1, 1)
            end
            txtObj:Show()
        end
    end
    for i = shown + 1, MAX_LINES do f.lines[i]:Hide() end
    f:SetShown(shown > 0)
end

--------------------------------------------------------------------------------
-- communications --------------------------------------------------------------
--------------------------------------------------------------------------------
local function Send(msg)
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
end

--------------------------------------------------------------------------------
-- polling (local player cooldown) ---------------------------------------------
--------------------------------------------------------------------------------
local pollFrame = CreateFrame("Frame")
local pollElapsed = 0
pollFrame:SetScript("OnUpdate", function(_, dt)
    pollElapsed = pollElapsed + dt
    if pollElapsed < UPDATE_INTERVAL then return end
    pollElapsed = 0

    if not AlsTiMAbilities.interruptName then return end
    -- local start, dur, enabled = GetSpellCooldown("Divine Storm")
    local start, dur, enabled = GetSpellCooldown(AlsTiMAbilities.interruptName)
    if enabled == 1 and dur > 0 then
        -- On CD
        print("ON CD")
        return
    end
    print("NOT CD")

    -- broadcast ready only if current target is watched
    local guid = UnitExists("target") and UnitGUID("target") or nil
    if guid and watchList[guid] then
        if not watchList[guid].hasEntry[playerName] or watchList[guid].onCD[playerName] then
            Send("READY:" .. guid)
            AddToQueue(watchList[guid], playerName, false)
            UpdateDisplayFor(guid)
        end
    end
end)

--------------------------------------------------------------------------------
-- slash commands --------------------------------------------------------------
--------------------------------------------------------------------------------
SLASH_KICKSYNC1, SLASH_KICKSYNC2 = "/ks", "/kicksync"
SlashCmdList["KICKSYNC"] = function(msg)
    msg = msg:lower():trim()
    if msg == "add" then
        if not UnitExists("target") or not UnitCanAttack("player", "target") then
            print("|cff33ff99KickSync|r: Target an enemy first.")
            return
        end
        local guid = UnitGUID("target")
        if watchList[guid] then
            print("KickSync: Already watching " .. UnitName("target"))
            return
        end
        local mobName = UnitName("target") or "Unknown"
        watchList[guid] = {
            mobName  = mobName,
            frame    = CreateWatchFrame(guid, mobName),
            readyQ   = {},
            hasEntry = {},
            onCD     = {},
        }
        addGUIDOrdered(guid)
        LayoutFrames()
        print("KickSync: Now watching " .. mobName)
    elseif msg == "remove" then
        if not UnitExists("target") then
            print("KickSync: target something to remove.")
            return
        end
        local guid = UnitGUID("target")
        local w = watchList[guid]
        if not w then
            print("KickSync: that target isn't watched.")
            return
        end
        w.frame:Hide(); w.frame:SetParent(nil)
        watchList[guid] = nil
        removeGUIDOrdered(guid)
        LayoutFrames()
        print("KickSync: removed " .. UnitName("target"))
    elseif msg == "clear" then
        for guid, w in pairs(watchList) do
            w.frame:Hide(); w.frame:SetParent(nil)
        end
        wipe(watchList); wipe(orderedGUIDs)
        print("KickSync: cleared all watched targets")
    elseif msg == "reset" then
        for _, guid in ipairs(orderedGUIDs) do
            watchList[guid].frame:ClearAllPoints()
            watchList[guid].frame:SetPoint("LEFT", 20, 0)
        end
    else
        print(
            "|cff33ff99KickSync|r commands:\n  /ks add     – watch current enemy\n  /ks remove  – stop watching target\n  /ks clear   – stop watching everyone\n  /ks reset   – reset frame positions")
    end
end

--------------------------------------------------------------------------------
-- event handling --------------------------------------------------------------
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX or sender == playerName then return end
        local cmd, guid = msg:match("^(%u+):(.+)$")
        local w = watchList[guid]; if not w then return end
        if cmd == "READY" then
            AddToQueue(w, sender, false)
            UpdateDisplayFor(guid)
        elseif cmd == "USED" then
            MarkUsed(w, sender)
            UpdateDisplayFor(guid)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        for guid, w in pairs(watchList) do
            for i = #w.readyQ, 1, -1 do
                local n = w.readyQ[i].name
                if not UnitInRaid(n) and not UnitInParty(n) then RemoveFromQueue(w, n) end
            end
            UpdateDisplayFor(guid)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit ~= "player" then return end
        if spellID == select(7, GetSpellInfo(AlsTiMAbilities.interruptName)) then
            local guid = UnitGUID("target")
            if guid and watchList[guid] then
                Send("USED:" .. guid)
                MarkUsed(watchList[guid], playerName)
                UpdateDisplayFor(guid)

                local s, d = GetSpellCooldown(AlsTiMAbilities.interruptName)
                if d and d > 0 then
                    C_Timer.After(d + 0.1, function()
                        local g = guid -- same guid, not necessarily current target when CD ready
                        if g and watchList[g] then
                            Send("READY:" .. g)
                            AddToQueue(watchList[g], playerName, false)
                            UpdateDisplayFor(g)
                        end
                    end)
                end
            end
        end
    end
end)
