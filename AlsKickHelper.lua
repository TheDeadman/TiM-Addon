-- TimKick 1.0.0

local addonName, addon = ...
local f                = CreateFrame("Frame")

-- internal state
local playerName       = UnitName("player")
local myKickTargetGUID = nil -- your target’s GUID
local myUpdateTime     = nil
local assignments      = {}  -- [playerName] = guid
local invalid          = {}  -- [playerName] = true  ⇒  user is no longer a valid timkick
local assignTime       = {}  -- [playerName] = timestamp (when SET or VALID was sent)
local isReady          = nil
local isValid          = false

AlsTiMKickHelper       = {}

-- helpers
local function trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
local function inGroup(name)
    return UnitInRaid(name) or UnitInParty(name) or name == playerName
end

local stringtoboolean = { ["true"] = true, ["false"] = false }

-- ui
local function CreateUI()
    local ui = CreateFrame("Frame", "TimKickFrame", UIParent, "BackdropTemplate")
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
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
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

    local good, bad = {}, {}
    for p, g in pairs(assignments) do
        if g == guid then
            if invalid[p] then
                tinsert(bad, p)
            else
                tinsert(good, p)
            end
        end
    end

    table.sort(good, function(a, b) -- sort valid by timestamp
        return (assignTime[a] or 0) < (assignTime[b] or 0)
    end)
    table.sort(bad) -- invalid alphabetical

    local list = good
    for _, p in ipairs(bad) do tinsert(list, p) end

    for i = 1, #ui.lines do
        local name = list[i]
        if name then
            if invalid[name] then
                ui.lines[i]:SetText("|cffff2020" .. name .. "|r")
            elseif name == playerName then
                ui.lines[i]:SetText("|cff20FF3e" .. name .. "|r")
            else
                ui.lines[i]:SetText(name)
            end
        else
            ui.lines[i]:SetText("")
        end
    end
    ui:SetHeight(28 + #list * 14)
    ui:Show()
end
-- for handling group change stuff
for p in pairs(assignments) do
    if not inGroup(p) then
        assignments[p] = nil
        invalid[p]     = nil
    end
end

-- comms
local PREFIX = "KICKER"

local function getChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

-- send wrapper ------------------------------------------------
-- type = "SET" | "CLEAR" | "QUERY"
local function SendAddon(type, payload)
    local channel = getChannel()
    if not channel then return end
    local msg = (type == "SET" and ("SET:" .. payload))
        or type == "CLEAR" and "CLEAR"
        or type == "QUERY" and "QUERY"
        or type == "INVALID" and "INVALID"
        or (type == "VALID" and ("VALID:" .. payload))
    if msg then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
end

function AlsTiMKickHelper.SendInvalid() -- <‑‑ you call this
    if isReady == true or isReady == nil then
        local now = GetTime()
        myUpdateTime = now
        SendAddon("INVALID", tostring(now)) -- broadcast to the group
        invalid[playerName] = true          -- mark yourself locally
        assignTime[playerName] = now
        isReady = false
        isValid = false
        UpdateUI()
    end
end

-- Call this when the player’s interrupt is available again.
-- call when you are BACK and ready to kick
function AlsTiMKickHelper.SendValid()
    if not isReady then
        local now = GetTime()
        SendAddon("VALID", tostring(now))
        myUpdateTime = now
        invalid[playerName] = nil
        assignTime[playerName] = now
        isReady = true
        isValid = true
        UpdateUI()
    end
end

function AlsTiMKickHelper.SendUpdate()
    local targetGUID = UnitGUID('target')
    -- print("cd: " .. tostring(AlsTiMRange.isOnCD))
    -- print("enemy: " .. tostring(AlsTiMRange.isTargettingEnemy))

    if AlsTiMRange.isInRange and not AlsTiMRange.isOnCD and AlsTiMRange.isTargettingEnemy and targetGUID == myKickTargetGUID then
        -- print("in")
        AlsTiMKickHelper.SendValid()
    else
        -- print("else")
        AlsTiMKickHelper.SendInvalid()
    end
end

-- message handler
local function HandleAddonMessage(msg, sender)
    if sender == playerName then return end

    if msg == "CLEAR" then
        assignments[sender] = nil
        invalid[sender]     = nil
        UpdateUI()
    elseif msg:sub(1, 4) == "SET:" then -- "SET:<guid>:<time>"
        local rest                 = msg:sub(5)
        local guid, tstr, validStr = rest:match("^([^:]+):([^:]+):(.+)$")
        assignments[sender]        = guid
        invalid[sender]            = not stringtoboolean[validStr]
        assignTime[sender]         = tonumber(tstr)
        UpdateUI()
    elseif msg == "QUERY" then
        if myKickTargetGUID then
            SendAddon("SET", myKickTargetGUID .. ":" .. myUpdateTime .. ":" .. tostring(isValid))
        end
    elseif msg == "INVALID" then -- unchanged
        local t            = tonumber(msg:sub(7))
        assignTime[sender] = t
        invalid[sender]    = true
        UpdateUI()
    elseif msg:sub(1, 6) == "VALID:" then -- "VALID:<time>"
        local t            = tonumber(msg:sub(7))
        invalid[sender]    = nil
        assignTime[sender] = t
        UpdateUI()
    end
end

-- slash commands
SLASH_KICKER1 = "/timkick"
SlashCmdList.KICKER = function(msg)
    msg = trim(string.lower(msg or ""))
    if msg == "add" then
        if UnitExists("target") and UnitCanAttack("player", "target") then
            local guid = UnitGUID("target")
            if guid then
                myKickTargetGUID        = guid
                assignments[playerName] = guid
                print("|cff00ff00[TimKick]|r kick target set to |cffffff00" .. UnitName("target") .. "|r.")
                local now = GetTime()
                SendAddon("SET", guid .. ":" .. now .. ":" .. tostring(isValid)) -- new format with time
                assignTime[playerName] = now
                SendAddon("QUERY")                                               -- ask others for their state
                UpdateUI()
            else
                print("|cff00ff00[TimKick]|r Could not read target GUID.")
            end
        else
            print("|cff00ff00[TimKick]|r You must target an enemy first.")
        end
    elseif msg == "clear" then
        if myKickTargetGUID then
            isReady                 = nil
            myKickTargetGUID        = nil
            assignments[playerName] = nil
            print("|cff00ff00[TimKick]|r kick target cleared.")
            SendAddon("CLEAR")
            UpdateUI()
        end
    elseif msg == "invalid" then
        AlsTiMKickHelper.SendInvalid()
    elseif msg == "valid" then
        AlsTiMKickHelper.SendValid()
    else
        print("|cff00ff00[TimKick]|r usage:")
        print("  /timkick add   – mark your target as kick target")
        print("  /timkick clear – remove your kick target")
    end
end

-- event handlers
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        CreateUI()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- clean up names that left the group
        for p in pairs(assignments) do
            if not inGroup(p) then assignments[p] = nil end
        end
        UpdateUI()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _channel, sender = ...
        if prefix == PREFIX then
            HandleAddonMessage(msg, Ambiguate(sender, "none"))
        end
    end
end)
