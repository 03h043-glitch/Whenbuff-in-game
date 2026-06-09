local ADDON_NAME = ...
local WhenBuff = CreateFrame("Frame", "WhenBuffInGameFrame", UIParent, "BackdropTemplate")

local DATA = WhenBuffInGame_Data or { servers = {}, serverOrder = {} }
local DB
local currentServer
local currentEvents = {}
local playerFaction
local rows = {}
local ROW_WIDTH = 372
local MINI_DEFAULT_WIDTH = 178
local MINI_DEFAULT_HEIGHT = 64
local MINI_MIN_WIDTH = 118
local MINI_MIN_HEIGHT = 42
local MINI_MAX_WIDTH = 360
local MINI_MAX_HEIGHT = 140
local miniFrame
local GetNextEvent
local HandleSlashCommand
local ToggleMiniWindow
local reminderThresholds = { 3600, 1800, 900, 300 }
local reminderLabels = {
    [3600] = "1 hour",
    [1800] = "30 minutes",
    [900] = "15 minutes",
    [300] = "5 minutes",
}

local COLORS = {
    text = { 0.94, 0.91, 0.82 },
    muted = { 0.62, 0.58, 0.50 },
    green = "|cff33ff99",
    gold = "|cffffcc66",
    red = "|cffff6666",
    reset = "|r",
}

local BUFF_STYLES = {
    default = {
        short = "BUFF",
        icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        color = { 0.18, 0.18, 0.18, 0.94 },
    },
    rend = {
        short = "REND",
        icon = "Interface\\Icons\\Ability_Warrior_Rampage",
        color = { 0.95, 0.42, 0.08, 0.94 },
    },
    onyHorde = {
        short = "ONY H",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        color = { 0.72, 0.04, 0.04, 0.94 },
    },
    onyAlliance = {
        short = "ONY A",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        color = { 0.05, 0.25, 0.80, 0.94 },
    },
    zg = {
        short = "ZG",
        icon = "Interface\\Icons\\Ability_Creature_Poison_05",
        color = { 0.05, 0.52, 0.22, 0.94 },
    },
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(COLORS.green .. "WhenBuff:" .. COLORS.reset .. " " .. message)
end

local function NormalizeRealmName(name)
    if not name then
        return ""
    end

    name = string.lower(name)
    name = string.gsub(name, "[%s%-']", "")
    return name
end

local function GetPlayerRealmName()
    if GetNormalizedRealmName then
        local normalized = GetNormalizedRealmName()
        if normalized and normalized ~= "" then
            return normalized
        end
    end

    if GetRealmName then
        return GetRealmName()
    end

    return ""
end

local function GetPlayerFaction()
    if UnitFactionGroup then
        local faction = UnitFactionGroup("player")
        if faction then
            return string.lower(faction)
        end
    end

    return nil
end

local function FindCurrentServer()
    local playerRealm = NormalizeRealmName(GetPlayerRealmName())

    for serverName in pairs(DATA.servers or {}) do
        if NormalizeRealmName(serverName) == playerRealm then
            return serverName
        end
    end

    return nil
end

local function FormatClock(timestamp)
    return date("%H:%M", timestamp)
end

local function FormatDate(timestamp)
    return date("%d/%m/%Y", timestamp)
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))

    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local minutes = math.floor(seconds / 60)

    if days > 0 then
        return string.format("%dd %02dh %02dm", days, hours, minutes)
    end

    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end

    return string.format("%dm", minutes)
end

local function TitleCase(value)
    value = value or ""
    return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
end

local function SetTextureColor(texture, color)
    if texture.SetColorTexture then
        texture:SetColorTexture(unpack(color))
    else
        texture:SetTexture(unpack(color))
    end
end

local function IsOnyxiaEvent(event)
    local buffType = string.lower(event.type or "")
    return buffType == "onyxia" or buffType == "nefarian"
end

local function ShouldShowEventForPlayer(event)
    if not IsOnyxiaEvent(event) then
        return true
    end

    local faction = string.lower(event.faction or "")
    if faction == "" or faction == "both" or faction == "all" then
        return true
    end

    if not playerFaction then
        return true
    end

    return faction == playerFaction
end

local function GetBuffStyle(event)
    local buffType = string.lower(event and event.type or "")

    if buffType == "rend" then
        return BUFF_STYLES.rend
    end

    if buffType == "zulgurub" or buffType == "zg" or buffType == "zandalar" then
        return BUFF_STYLES.zg
    end

    if buffType == "onyxia" or buffType == "nefarian" then
        local faction = string.lower(event.faction or playerFaction or "")
        if faction == "horde" then
            return BUFF_STYLES.onyHorde
        end

        return BUFF_STYLES.onyAlliance
    end

    return BUFF_STYLES.default
end

local function GetEventLabel(event)
    local faction = event.faction or "both"
    if faction == "both" or faction == "all" then
        faction = "both factions"
    end

    local label = string.format("%s for %s", event.type or "Buff", faction)
    if event.guild and event.guild ~= "" then
        label = label .. " by " .. event.guild
    end

    return label
end

local function EventReminderKey(event, threshold)
    return string.format("%s:%s:%s:%s", currentServer or "unknown", event.timestamp or 0, event.type or "buff", threshold)
end

local function EnsureDatabase()
    WhenBuffInGameDB = WhenBuffInGameDB or {}
    DB = WhenBuffInGameDB
    DB.point = DB.point or "CENTER"
    DB.x = DB.x or 0
    DB.y = DB.y or 0
    DB.scale = DB.scale or 1
    DB.sentReminders = DB.sentReminders or {}
    DB.mini = DB.mini or {}
    if DB.mini.hidden == nil then
        DB.mini.hidden = true
    end
    DB.mini.point = DB.mini.point or "CENTER"
    DB.mini.x = DB.mini.x or 0
    DB.mini.y = DB.mini.y or -120
    DB.mini.width = DB.mini.width or MINI_DEFAULT_WIDTH
    DB.mini.height = DB.mini.height or MINI_DEFAULT_HEIGHT
end

local function ClearOldReminderKeys()
    local now = time()
    for key, expiresAt in pairs(DB.sentReminders) do
        if type(expiresAt) ~= "number" or expiresAt < now then
            DB.sentReminders[key] = nil
        end
    end
end

local function SortEvents(events)
    table.sort(events, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)
end

local function GetServerEvents(serverName)
    local server = serverName and DATA.servers and DATA.servers[serverName]
    if not server or not server.buffs then
        return {}
    end

    local events = {}
    for _, event in ipairs(server.buffs) do
        if type(event.timestamp) == "number" and ShouldShowEventForPlayer(event) then
            table.insert(events, event)
        end
    end

    SortEvents(events)
    return events
end

local function SaveMiniPosition()
    if not miniFrame or not DB or not DB.mini then
        return
    end

    local point, _, _, x, y = miniFrame:GetPoint(1)
    local width, height = miniFrame:GetSize()
    DB.mini.point = point or "CENTER"
    DB.mini.x = x or 0
    DB.mini.y = y or 0
    DB.mini.width = width or MINI_DEFAULT_WIDTH
    DB.mini.height = height or MINI_DEFAULT_HEIGHT
end

local function LayoutMiniWindow()
    if not miniFrame then
        return
    end

    local width, height = miniFrame:GetSize()
    local padding = math.max(4, math.min(10, height * 0.12))
    local iconSize = math.max(26, math.min(height - (padding * 2), width * 0.32))
    local shortSize = math.max(9, math.min(22, height * 0.28))
    local timerSize = math.max(11, math.min(30, height * 0.38))

    miniFrame.icon:SetSize(iconSize, iconSize)
    miniFrame.icon:ClearAllPoints()
    miniFrame.icon:SetPoint("LEFT", miniFrame, "LEFT", padding, 0)

    miniFrame.shortText:SetFont(STANDARD_TEXT_FONT, shortSize, "OUTLINE")
    miniFrame.shortText:ClearAllPoints()
    miniFrame.shortText:SetPoint("TOPLEFT", miniFrame.icon, "TOPRIGHT", padding, -padding)
    miniFrame.shortText:SetPoint("RIGHT", miniFrame, "RIGHT", -padding, 0)

    miniFrame.timerText:SetFont(STANDARD_TEXT_FONT, timerSize, "OUTLINE")
    miniFrame.timerText:ClearAllPoints()
    miniFrame.timerText:SetPoint("BOTTOMLEFT", miniFrame.icon, "BOTTOMRIGHT", padding, padding)
    miniFrame.timerText:SetPoint("RIGHT", miniFrame, "RIGHT", -padding, 0)

    miniFrame.resizeGrip:SetSize(math.max(10, height * 0.18), math.max(10, height * 0.18))
end

local function UpdateMiniWindow()
    if not miniFrame then
        return
    end

    local nextEvent = GetNextEvent(currentEvents)
    if not currentServer or not nextEvent then
        local style = BUFF_STYLES.default
        SetTextureColor(miniFrame.background, style.color)
        miniFrame.icon:SetTexture(style.icon)
        miniFrame.shortText:SetText("NONE")
        miniFrame.timerText:SetText("--")
        return
    end

    local style = GetBuffStyle(nextEvent)
    SetTextureColor(miniFrame.background, style.color)
    miniFrame.icon:SetTexture(style.icon)
    miniFrame.shortText:SetText(style.short)
    miniFrame.timerText:SetText(FormatDuration(nextEvent.timestamp - time()))
end

local function GetTodayEvents(events)
    local today = date("%d/%m/%Y", time())
    local now = time()
    local todayEvents = {}

    for _, event in ipairs(events) do
        if event.timestamp > now and FormatDate(event.timestamp) == today then
            table.insert(todayEvents, event)
        end
    end

    return todayEvents
end

function GetNextEvent(events)
    local now = time()

    for _, event in ipairs(events) do
        if event.timestamp > now then
            return event
        end
    end

    return nil
end

local function CreateFont(parent, name, size, template)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    font:SetFont(STANDARD_TEXT_FONT, size, "")
    font:SetTextColor(unpack(COLORS.text))
    font:SetJustifyH("LEFT")
    return font
end

local function SetRowText(row, event)
    row.time:SetText(FormatClock(event.timestamp))
    row.type:SetText(event.type or "Buff")
    row.guild:SetText(event.guild or "")
    row.faction:SetText(TitleCase(event.faction == "both" and "both" or event.faction or ""))

    if event.notes and event.notes ~= "" then
        row.notes:SetText(event.notes)
        row.notes:Show()
    else
        row.notes:SetText("")
        row.notes:Hide()
    end
end

local function CreateRow(index)
    local parent = WhenBuff.scrollChild or WhenBuff
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_WIDTH, 34)

    row.time = CreateFont(row, nil, 13)
    row.time:SetPoint("LEFT", row, "LEFT", 0, 6)
    row.time:SetWidth(44)

    row.type = CreateFont(row, nil, 13)
    row.type:SetPoint("LEFT", row.time, "RIGHT", 8, 0)
    row.type:SetWidth(80)

    row.guild = CreateFont(row, nil, 13)
    row.guild:SetPoint("LEFT", row.type, "RIGHT", 8, 0)
    row.guild:SetWidth(140)

    row.faction = CreateFont(row, nil, 12)
    row.faction:SetPoint("RIGHT", row, "RIGHT", 0, 6)
    row.faction:SetWidth(80)
    row.faction:SetJustifyH("RIGHT")
    row.faction:SetTextColor(unpack(COLORS.muted))

    row.notes = CreateFont(row, nil, 11)
    row.notes:SetPoint("TOPLEFT", row.time, "BOTTOMLEFT", 0, -1)
    row.notes:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.notes:SetTextColor(unpack(COLORS.muted))

    rows[index] = row
    return row
end

local function RefreshRows(todayEvents)
    for _, row in ipairs(rows) do
        row:Hide()
    end

    if WhenBuff.scrollChild then
        WhenBuff.scrollChild:SetHeight(math.max(190, (#todayEvents * 38) + 24))
    end

    if #todayEvents == 0 then
        WhenBuff.emptyText:Show()
        return
    end

    WhenBuff.emptyText:Hide()

    for index, event in ipairs(todayEvents) do
        local row = rows[index] or CreateRow(index)
        row:SetPoint("TOPLEFT", WhenBuff.listAnchor, "BOTTOMLEFT", 0, -((index - 1) * 38))
        SetRowText(row, event)
        row:Show()
    end
end

local function RefreshWindow()
    playerFaction = GetPlayerFaction()
    currentServer = FindCurrentServer()
    currentEvents = GetServerEvents(currentServer)

    local generatedText = DATA.generatedAt and ("Data: " .. DATA.generatedAt) or "Data: unavailable"
    WhenBuff.generatedText:SetText(generatedText)

    if currentServer then
        local server = DATA.servers[currentServer]
        WhenBuff.title:SetText("WhenBuff - " .. currentServer)
        WhenBuff.realmText:SetText(string.format("%s realm, %s, %s", server.region or "Unknown", server.timezone or "server time", TitleCase(playerFaction or "unknown faction")))
        WhenBuff.emptyText:SetText("No buffs remaining today.")
        RefreshRows(GetTodayEvents(currentEvents))
    else
        WhenBuff.title:SetText("WhenBuff - " .. (GetPlayerRealmName() or "Unknown realm"))
        WhenBuff.realmText:SetText("No WhenBuff data for this realm")
        WhenBuff.emptyText:SetText("This realm is not currently returned by WhenBuff.")
        RefreshRows({})
    end

    UpdateMiniWindow()
end

local function UpdateCountdown()
    local nextEvent = GetNextEvent(currentEvents)

    if not currentServer then
        WhenBuff.nextText:SetText("Next buff: no realm data")
        return
    end

    if not nextEvent then
        WhenBuff.nextText:SetText("Next buff: none scheduled")
        return
    end

    local remaining = nextEvent.timestamp - time()
    WhenBuff.nextText:SetText(string.format("Next: %s in %s", GetEventLabel(nextEvent), FormatDuration(remaining)))
end

local function SendReminder(event, threshold)
    local label = reminderLabels[threshold] or FormatDuration(threshold)
    Print(string.format("%s drops in %s at %s.", GetEventLabel(event), label, FormatClock(event.timestamp)))
end

local function CheckReminders()
    if not currentServer or not DB then
        return
    end

    local now = time()
    for _, event in ipairs(currentEvents) do
        local remaining = (event.timestamp or 0) - now
        if remaining > 0 then
            for _, threshold in ipairs(reminderThresholds) do
                if remaining <= threshold and remaining > threshold - 65 then
                    local key = EventReminderKey(event, threshold)
                    if not DB.sentReminders[key] then
                        DB.sentReminders[key] = (event.timestamp or now) + 3600
                        SendReminder(event, threshold)
                    end
                end
            end
        end
    end
end

local function OnTick()
    UpdateCountdown()
    UpdateMiniWindow()
    CheckReminders()
end

local function SavePosition()
    local point, _, _, x, y = WhenBuff:GetPoint(1)
    DB.point = point or "CENTER"
    DB.x = x or 0
    DB.y = y or 0
    DB.scale = WhenBuff:GetScale() or 1
end

local function BuildMiniWindow()
    miniFrame = CreateFrame("Frame", "WhenBuffInGameMiniFrame", UIParent, "BackdropTemplate")
    miniFrame:SetSize(DB.mini.width, DB.mini.height)
    miniFrame:SetPoint(DB.mini.point, UIParent, DB.mini.point, DB.mini.x, DB.mini.y)
    miniFrame:SetMovable(true)
    miniFrame:SetResizable(true)
    miniFrame:EnableMouse(true)
    miniFrame:RegisterForDrag("LeftButton")
    miniFrame:SetClampedToScreen(true)
    miniFrame:SetFrameStrata("MEDIUM")
    miniFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    if miniFrame.SetResizeBounds then
        miniFrame:SetResizeBounds(MINI_MIN_WIDTH, MINI_MIN_HEIGHT, MINI_MAX_WIDTH, MINI_MAX_HEIGHT)
    elseif miniFrame.SetMinResize and miniFrame.SetMaxResize then
        miniFrame:SetMinResize(MINI_MIN_WIDTH, MINI_MIN_HEIGHT)
        miniFrame:SetMaxResize(MINI_MAX_WIDTH, MINI_MAX_HEIGHT)
    end

    miniFrame.background = miniFrame:CreateTexture(nil, "BACKGROUND")
    miniFrame.background:SetAllPoints(miniFrame)

    miniFrame.icon = miniFrame:CreateTexture(nil, "ARTWORK")
    miniFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    miniFrame.shortText = miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    miniFrame.shortText:SetJustifyH("LEFT")
    miniFrame.shortText:SetTextColor(1, 1, 1)

    miniFrame.timerText = miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    miniFrame.timerText:SetJustifyH("LEFT")
    miniFrame.timerText:SetTextColor(1, 1, 1)

    miniFrame.resizeGrip = CreateFrame("Button", nil, miniFrame)
    miniFrame.resizeGrip:SetPoint("BOTTOMRIGHT", miniFrame, "BOTTOMRIGHT", -2, 2)
    miniFrame.resizeGrip:SetScript("OnMouseDown", function()
        miniFrame:StartSizing("BOTTOMRIGHT")
    end)
    miniFrame.resizeGrip:SetScript("OnMouseUp", function()
        miniFrame:StopMovingOrSizing()
        SaveMiniPosition()
        LayoutMiniWindow()
    end)

    miniFrame:SetScript("OnDragStart", function()
        miniFrame:StartMoving()
    end)
    miniFrame:SetScript("OnDragStop", function()
        miniFrame:StopMovingOrSizing()
        SaveMiniPosition()
    end)
    miniFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            DB.mini.hidden = true
            miniFrame:Hide()
        end
    end)
    miniFrame:SetScript("OnSizeChanged", function()
        LayoutMiniWindow()
        SaveMiniPosition()
    end)

    LayoutMiniWindow()
    UpdateMiniWindow()
    miniFrame:Hide()
end

local function BuildWindow()
    WhenBuff:SetSize(430, 360)
    WhenBuff:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
    WhenBuff:SetScale(DB.scale)
    WhenBuff:SetMovable(true)
    WhenBuff:EnableMouse(true)
    WhenBuff:RegisterForDrag("LeftButton")
    WhenBuff:SetScript("OnDragStart", WhenBuff.StartMoving)
    WhenBuff:SetScript("OnDragStop", function()
        WhenBuff:StopMovingOrSizing()
        SavePosition()
    end)
    WhenBuff:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })

    WhenBuff.title = CreateFont(WhenBuff, nil, 18, "GameFontHighlightLarge")
    WhenBuff.title:SetPoint("TOPLEFT", WhenBuff, "TOPLEFT", 20, -18)
    WhenBuff.title:SetPoint("RIGHT", WhenBuff, "RIGHT", -54, 0)

    WhenBuff.close = CreateFrame("Button", nil, WhenBuff, "UIPanelCloseButton")
    WhenBuff.close:SetPoint("TOPRIGHT", WhenBuff, "TOPRIGHT", -8, -8)
    WhenBuff.close:SetScript("OnClick", function()
        DB.hidden = true
        WhenBuff:Hide()
    end)

    WhenBuff.realmText = CreateFont(WhenBuff, nil, 12)
    WhenBuff.realmText:SetPoint("TOPLEFT", WhenBuff.title, "BOTTOMLEFT", 0, -6)
    WhenBuff.realmText:SetTextColor(unpack(COLORS.muted))

    WhenBuff.nextText = CreateFont(WhenBuff, nil, 14, "GameFontHighlight")
    WhenBuff.nextText:SetPoint("TOPLEFT", WhenBuff.realmText, "BOTTOMLEFT", 0, -18)
    WhenBuff.nextText:SetPoint("RIGHT", WhenBuff, "RIGHT", -20, 0)

    WhenBuff.todayHeader = CreateFont(WhenBuff, nil, 13, "GameFontHighlight")
    WhenBuff.todayHeader:SetPoint("TOPLEFT", WhenBuff.nextText, "BOTTOMLEFT", 0, -22)
    WhenBuff.todayHeader:SetText("Upcoming Today")

    WhenBuff.scrollFrame = CreateFrame("ScrollFrame", nil, WhenBuff, "UIPanelScrollFrameTemplate")
    WhenBuff.scrollFrame:SetPoint("TOPLEFT", WhenBuff.todayHeader, "BOTTOMLEFT", 0, -12)
    WhenBuff.scrollFrame:SetSize(390, 190)

    WhenBuff.scrollChild = CreateFrame("Frame", nil, WhenBuff.scrollFrame)
    WhenBuff.scrollChild:SetSize(ROW_WIDTH, 190)
    WhenBuff.scrollFrame:SetScrollChild(WhenBuff.scrollChild)

    WhenBuff.listAnchor = CreateFrame("Frame", nil, WhenBuff.scrollChild)
    WhenBuff.listAnchor:SetPoint("TOPLEFT", WhenBuff.scrollChild, "TOPLEFT", 0, 0)
    WhenBuff.listAnchor:SetSize(ROW_WIDTH, 1)

    WhenBuff.emptyText = CreateFont(WhenBuff.scrollChild, nil, 13)
    WhenBuff.emptyText:SetPoint("TOPLEFT", WhenBuff.listAnchor, "BOTTOMLEFT", 0, -8)
    WhenBuff.emptyText:SetTextColor(unpack(COLORS.muted))
    WhenBuff.emptyText:SetText("No buffs remaining today.")

    WhenBuff.generatedText = CreateFont(WhenBuff, nil, 10)
    WhenBuff.generatedText:SetPoint("BOTTOMLEFT", WhenBuff, "BOTTOMLEFT", 20, 14)
    WhenBuff.generatedText:SetTextColor(unpack(COLORS.muted))

    local refreshButton = CreateFrame("Button", nil, WhenBuff, "UIPanelButtonTemplate")
    refreshButton:SetSize(74, 22)
    refreshButton:SetPoint("BOTTOMRIGHT", WhenBuff, "BOTTOMRIGHT", -20, 12)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        RefreshWindow()
        UpdateCountdown()
    end)
    WhenBuff.refreshButton = refreshButton

    local miniButton = CreateFrame("Button", nil, WhenBuff, "UIPanelButtonTemplate")
    miniButton:SetSize(56, 22)
    miniButton:SetPoint("RIGHT", refreshButton, "LEFT", -8, 0)
    miniButton:SetText("Mini")
    miniButton:SetScript("OnClick", function()
        HandleSlashCommand("mini")
    end)
    WhenBuff.miniButton = miniButton
end

local function ShowWindow()
    DB.hidden = false
    RefreshWindow()
    UpdateCountdown()
    WhenBuff:Show()
end

local function ToggleWindow()
    if WhenBuff:IsShown() then
        DB.hidden = true
        WhenBuff:Hide()
    else
        ShowWindow()
    end
end

function ToggleMiniWindow()
    if not miniFrame then
        return
    end

    if miniFrame:IsShown() then
        DB.mini.hidden = true
        miniFrame:Hide()
    else
        DB.mini.hidden = false
        UpdateMiniWindow()
        miniFrame:Show()
    end
end

function HandleSlashCommand(input)
    input = string.lower(input or "")

    if input == "show" then
        ShowWindow()
    elseif input == "hide" then
        DB.hidden = true
        WhenBuff:Hide()
    elseif input == "refresh" then
        RefreshWindow()
        UpdateCountdown()
        Print("Display refreshed from loaded data.")
    elseif input == "mini" then
        ToggleMiniWindow()
    elseif input == "test" then
        Print("Test reminder: Onyxia drops in 5 minutes at 20:00.")
    else
        ToggleWindow()
    end
end

local function OnLogin()
    EnsureDatabase()
    BuildWindow()
    BuildMiniWindow()
    ClearOldReminderKeys()
    RefreshWindow()
    UpdateCountdown()

    if not DB.hidden then
        WhenBuff:Show()
    end

    if not DB.mini.hidden then
        miniFrame:Show()
    end

    C_Timer.NewTicker(1, OnTick)

    SLASH_WHENBUFFINGAME1 = "/wb"
    SLASH_WHENBUFFINGAME2 = "/whenbuff"
    SlashCmdList.WHENBUFFINGAME = HandleSlashCommand

    if currentServer then
        Print("Tracking " .. currentServer .. ".")
    else
        Print("No WhenBuff data found for " .. (GetPlayerRealmName() or "this realm") .. ".")
    end
end

WhenBuff:RegisterEvent("PLAYER_LOGIN")
WhenBuff:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        OnLogin()
    end
end)
