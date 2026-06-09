local ADDON_NAME = ...
local WhenBuff = CreateFrame("Frame", "WhenBuffInGameFrame", UIParent, "BackdropTemplate")

local DATA = WhenBuffInGame_Data or { servers = {}, serverOrder = {} }
local DB
local currentServer
local currentEvents = {}
local playerFaction
local rows = {}
local miniFrame
local optionsFrame
local optionControls = {}
local lastViewRefresh = 0

local MAIN_DEFAULT_WIDTH = 430
local MAIN_DEFAULT_HEIGHT = 360
local MAIN_MIN_WIDTH = 360
local MAIN_MIN_HEIGHT = 280
local MAIN_MAX_WIDTH = 760
local MAIN_MAX_HEIGHT = 680

local MINI_DEFAULT_WIDTH = 220
local MINI_DEFAULT_HEIGHT = 72
local MINI_MIN_WIDTH = 150
local MINI_MIN_HEIGHT = 48
local MINI_MAX_WIDTH = 460
local MINI_MAX_HEIGHT = 170
local RESIZE_GRIP_SIZE = 34
local MINI_RESIZE_GRIP_SIZE = 42
local MAIN_BG_INSET = 7
local MINI_BG_INSET = 4
local OPTIONS_BG_INSET = 5
local AUTO_VIEW_REFRESH_SECONDS = 60

local LayoutMainWindow
local LayoutMiniWindow
local UpdateCountdown
local UpdateMiniWindow
local RefreshWindow
local HandleSlashCommand
local ToggleMiniWindow
local ToggleOptionsWindow

local reminderThresholds = { 3600, 1800, 900, 300 }
local reminderLabels = {
    [3600] = "1 hour",
    [1800] = "30 minutes",
    [900] = "15 minutes",
    [300] = "5 minutes",
}

local COLORS = {
    text = { 0.94, 0.91, 0.82, 1 },
    muted = { 0.62, 0.58, 0.50, 1 },
    mainTop = { 0.035, 0.035, 0.045, 0.96 },
    mainBottom = { 0.125, 0.115, 0.105, 0.94 },
    green = "|cff33ff99",
    reset = "|r",
}

local BUFF_STYLES = {
    default = {
        short = "BUFF",
        spellId = 23769,
        fallbackIcon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        color = { 0.18, 0.18, 0.18, 0.94 },
        textColor = { 0.92, 0.90, 0.82, 1 },
    },
    rend = {
        short = "REND",
        spellId = 16609,
        fallbackIcon = "Interface\\Icons\\Spell_Arcane_TeleportOrgrimmar",
        color = { 0.95, 0.42, 0.08, 0.94 },
        textColor = { 1.00, 0.60, 0.20, 1 },
    },
    onyHorde = {
        short = "ONY H",
        spellId = 22888,
        fallbackIcon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        color = { 0.72, 0.04, 0.04, 0.94 },
        textColor = { 1.00, 0.30, 0.25, 1 },
    },
    onyAlliance = {
        short = "ONY A",
        spellId = 22888,
        fallbackIcon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        color = { 0.05, 0.25, 0.80, 0.94 },
        textColor = { 0.35, 0.62, 1.00, 1 },
    },
    zg = {
        short = "ZG",
        spellId = 24425,
        fallbackIcon = "Interface\\Icons\\Ability_Creature_Poison_05",
        color = { 0.05, 0.52, 0.22, 0.94 },
        textColor = { 0.28, 0.95, 0.44, 1 },
    },
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(COLORS.green .. "WhenBuff:" .. COLORS.reset .. " " .. message)
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function Round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function Darken(color, amount)
    return {
        math.max(0, color[1] * amount),
        math.max(0, color[2] * amount),
        math.max(0, color[3] * amount),
        color[4] or 1,
    }
end

local function SetTextureColor(texture, color)
    if texture.SetColorTexture then
        texture:SetColorTexture(unpack(color))
    else
        texture:SetTexture(unpack(color))
    end
end

local function SetVerticalGradient(texture, topColor, bottomColor)
    if texture.SetGradientAlpha then
        texture:SetGradientAlpha("VERTICAL",
            bottomColor[1], bottomColor[2], bottomColor[3], bottomColor[4] or 1,
            topColor[1], topColor[2], topColor[3], topColor[4] or 1)
    else
        SetTextureColor(texture, bottomColor)
    end
end

local function InsetTexture(texture, parent, inset)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    texture:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
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

local function FormatCountdown(seconds)
    seconds = math.max(0, math.floor(seconds or 0))

    local days = math.floor(seconds / 86400)
    seconds = seconds % 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60

    if days > 0 then
        return string.format("%dd %02d:%02d:%02d", days, hours, minutes, secs)
    end

    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function TitleCase(value)
    value = value or ""
    return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
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

local function GetStyleIcon(style)
    if style and style.spellId and GetSpellTexture then
        local icon = GetSpellTexture(style.spellId)
        if icon then
            return icon
        end
    end

    return (style and style.fallbackIcon) or BUFF_STYLES.default.fallbackIcon
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
    DB.width = Clamp(DB.width or MAIN_DEFAULT_WIDTH, MAIN_MIN_WIDTH, MAIN_MAX_WIDTH)
    DB.height = Clamp(DB.height or MAIN_DEFAULT_HEIGHT, MAIN_MIN_HEIGHT, MAIN_MAX_HEIGHT)
    DB.sentReminders = DB.sentReminders or {}

    DB.mini = DB.mini or {}
    if DB.mini.hidden == nil then
        DB.mini.hidden = true
    end
    DB.mini.point = DB.mini.point or "CENTER"
    DB.mini.x = DB.mini.x or 0
    DB.mini.y = DB.mini.y or -120
    DB.mini.width = Clamp(DB.mini.width or MINI_DEFAULT_WIDTH, MINI_MIN_WIDTH, MINI_MAX_WIDTH)
    DB.mini.height = Clamp(DB.mini.height or MINI_DEFAULT_HEIGHT, MINI_MIN_HEIGHT, MINI_MAX_HEIGHT)
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

local function GetNextEvent(events)
    local now = time()

    for _, event in ipairs(events) do
        if event.timestamp > now then
            return event
        end
    end

    return nil
end

local function CreateFont(parent, size, template)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    font:SetFont(STANDARD_TEXT_FONT, size, "")
    font:SetTextColor(unpack(COLORS.text))
    font:SetJustifyH("LEFT")
    return font
end

local function SaveMainGeometry()
    if not DB then
        return
    end

    local point, _, _, x, y = WhenBuff:GetPoint(1)
    local width, height = WhenBuff:GetSize()
    DB.point = point or "CENTER"
    DB.x = x or 0
    DB.y = y or 0
    DB.width = Clamp(Round(width), MAIN_MIN_WIDTH, MAIN_MAX_WIDTH)
    DB.height = Clamp(Round(height), MAIN_MIN_HEIGHT, MAIN_MAX_HEIGHT)
end

local function SaveMiniGeometry()
    if not miniFrame or not DB or not DB.mini then
        return
    end

    local point, _, _, x, y = miniFrame:GetPoint(1)
    local width, height = miniFrame:GetSize()
    DB.mini.point = point or "CENTER"
    DB.mini.x = x or 0
    DB.mini.y = y or 0
    DB.mini.width = Clamp(Round(width), MINI_MIN_WIDTH, MINI_MAX_WIDTH)
    DB.mini.height = Clamp(Round(height), MINI_MIN_HEIGHT, MINI_MAX_HEIGHT)
end

local function SetResizeBounds(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    elseif frame.SetMinResize and frame.SetMaxResize then
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
end

local function CreateResizeGrip(parent, size, onStart, onStop)
    local grip = CreateFrame("Button", nil, parent)
    grip:SetSize(size, size)
    grip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)

    grip:SetScript("OnMouseDown", onStart)
    grip:SetScript("OnMouseUp", onStop)
    return grip
end

local function SetRowText(row, event, rowWidth)
    local style = GetBuffStyle(event)
    local color = style.textColor or COLORS.text
    local iconSize = 22
    local timeWidth = 50
    local typeWidth = 78
    local factionWidth = 78
    local gap = 8
    local guildWidth = math.max(70, rowWidth - iconSize - timeWidth - typeWidth - factionWidth - (gap * 5))

    row:SetSize(rowWidth, 36)
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetTexture(GetStyleIcon(style))
    row.time:SetWidth(timeWidth)
    row.type:SetWidth(typeWidth)
    row.guild:SetWidth(guildWidth)
    row.faction:SetWidth(factionWidth)

    row.time:SetText(FormatClock(event.timestamp))
    row.type:SetText(style.short or event.type or "Buff")
    row.guild:SetText(event.guild or "")
    row.faction:SetText(TitleCase(event.faction == "both" and "both" or event.faction or ""))

    row.type:SetTextColor(unpack(color))
    row.time:SetTextColor(color[1], color[2], color[3], 0.92)
    row.guild:SetTextColor(unpack(COLORS.text))
    row.faction:SetTextColor(unpack(COLORS.muted))

    if event.notes and event.notes ~= "" then
        row.notes:SetText(event.notes)
        row.notes:SetWidth(rowWidth - iconSize - gap)
        row.notes:Show()
    else
        row.notes:SetText("")
        row.notes:Hide()
    end
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, WhenBuff.scrollChild or WhenBuff)
    row:SetSize(360, 36)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 6)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.time = CreateFont(row, 12)
    row.time:SetPoint("LEFT", row.icon, "RIGHT", 8, 6)

    row.type = CreateFont(row, 12, "GameFontHighlight")
    row.type:SetPoint("LEFT", row.time, "RIGHT", 8, 0)

    row.guild = CreateFont(row, 12)
    row.guild:SetPoint("LEFT", row.type, "RIGHT", 8, 0)

    row.faction = CreateFont(row, 11)
    row.faction:SetPoint("RIGHT", row, "RIGHT", 0, 6)
    row.faction:SetJustifyH("RIGHT")

    row.notes = CreateFont(row, 10)
    row.notes:SetPoint("TOPLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.notes:SetTextColor(unpack(COLORS.muted))

    rows[index] = row
    return row
end

local function RefreshRows(todayEvents)
    if not WhenBuff.scrollChild then
        return
    end

    local rowWidth = math.max(260, WhenBuff.scrollChild:GetWidth() or 260)
    for _, row in ipairs(rows) do
        row:Hide()
    end

    WhenBuff.scrollChild:SetHeight(math.max(120, (#todayEvents * 40) + 28))

    if #todayEvents == 0 then
        WhenBuff.emptyText:SetWidth(rowWidth)
        WhenBuff.emptyText:Show()
        return
    end

    WhenBuff.emptyText:Hide()

    for index, event in ipairs(todayEvents) do
        local row = rows[index] or CreateRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", WhenBuff.listAnchor, "BOTTOMLEFT", 0, -((index - 1) * 40))
        SetRowText(row, event, rowWidth)
        row:Show()
    end
end

local function RefreshOptionControls()
    if not optionsFrame then
        return
    end

    for _, control in ipairs(optionControls) do
        local value
        if control.target == "main" then
            value = control.key == "width" and DB.width or DB.height
        else
            value = control.key == "width" and DB.mini.width or DB.mini.height
        end

        control.locked = true
        control.slider:SetValue(value)
        control.edit:SetText(tostring(value))
        control.locked = false
    end
end

local function ApplySizeValue(target, key, value)
    if target == "main" then
        if key == "width" then
            DB.width = Clamp(Round(value), MAIN_MIN_WIDTH, MAIN_MAX_WIDTH)
        else
            DB.height = Clamp(Round(value), MAIN_MIN_HEIGHT, MAIN_MAX_HEIGHT)
        end
        WhenBuff:SetSize(DB.width, DB.height)
        LayoutMainWindow()
    elseif miniFrame then
        if key == "width" then
            DB.mini.width = Clamp(Round(value), MINI_MIN_WIDTH, MINI_MAX_WIDTH)
        else
            DB.mini.height = Clamp(Round(value), MINI_MIN_HEIGHT, MINI_MAX_HEIGHT)
        end
        miniFrame:SetSize(DB.mini.width, DB.mini.height)
        LayoutMiniWindow()
        UpdateMiniWindow()
    end
end

local function CreateSizeControl(parent, labelText, target, key, minValue, maxValue, yOffset)
    local label = CreateFont(parent, 11)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 22, yOffset)
    label:SetText(labelText)

    local sliderName = "WhenBuffInGameOptions" .. target .. key .. "Slider"
    local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    slider:SetWidth(220)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    _G[sliderName .. "Low"]:SetText(tostring(minValue))
    _G[sliderName .. "High"]:SetText(tostring(maxValue))
    _G[sliderName .. "Text"]:SetText("")

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(58, 24)
    edit:SetPoint("LEFT", slider, "RIGHT", 18, 0)
    edit:SetAutoFocus(false)
    if edit.SetNumeric then
        edit:SetNumeric(true)
    end
    edit:SetMaxLetters(4)

    local control = {
        target = target,
        key = key,
        slider = slider,
        edit = edit,
        locked = false,
    }
    table.insert(optionControls, control)

    slider:SetScript("OnValueChanged", function(_, value)
        if control.locked then
            return
        end
        value = Clamp(Round(value), minValue, maxValue)
        control.locked = true
        edit:SetText(tostring(value))
        control.locked = false
        ApplySizeValue(target, key, value)
    end)

    local function ApplyEditValue()
        local value = Clamp(Round(edit:GetNumber()), minValue, maxValue)
        control.locked = true
        slider:SetValue(value)
        edit:SetText(tostring(value))
        control.locked = false
        ApplySizeValue(target, key, value)
        edit:ClearFocus()
    end

    edit:SetScript("OnEnterPressed", ApplyEditValue)
    edit:SetScript("OnEditFocusLost", ApplyEditValue)
end

local function BuildOptionsWindow()
    optionsFrame = CreateFrame("Frame", "WhenBuffInGameOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(360, 330)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    optionsFrame.background = optionsFrame:CreateTexture(nil, "BACKGROUND")
    InsetTexture(optionsFrame.background, optionsFrame, OPTIONS_BG_INSET)
    SetVerticalGradient(optionsFrame.background, { 0.025, 0.025, 0.030, 0.98 }, { 0.12, 0.105, 0.09, 0.96 })

    optionsFrame.title = CreateFont(optionsFrame, 16, "GameFontHighlightLarge")
    optionsFrame.title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 18, -18)
    optionsFrame.title:SetText("WhenBuff Options")

    optionsFrame.close = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    optionsFrame.close:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -6, -6)
    optionsFrame.close:SetScript("OnClick", function()
        optionsFrame:Hide()
    end)

    CreateSizeControl(optionsFrame, "Main width", "main", "width", MAIN_MIN_WIDTH, MAIN_MAX_WIDTH, -58)
    CreateSizeControl(optionsFrame, "Main height", "main", "height", MAIN_MIN_HEIGHT, MAIN_MAX_HEIGHT, -118)
    CreateSizeControl(optionsFrame, "Mini width", "mini", "width", MINI_MIN_WIDTH, MINI_MAX_WIDTH, -188)
    CreateSizeControl(optionsFrame, "Mini height", "mini", "height", MINI_MIN_HEIGHT, MINI_MAX_HEIGHT, -248)

    optionsFrame:Hide()
end

function ToggleOptionsWindow()
    if not optionsFrame then
        return
    end

    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        RefreshOptionControls()
        optionsFrame:Show()
    end
end

function LayoutMiniWindow()
    if not miniFrame then
        return
    end

    local width, height = miniFrame:GetSize()
    local padding = math.max(5, math.min(11, height * 0.12))
    local iconSize = math.max(26, math.min(height - (padding * 2), width * 0.24))
    local textWidth = math.max(56, width - iconSize - (padding * 3))
    local textLength = string.len(miniFrame.timerText:GetText() or "REND - 00:00:00")
    local fontSize = Clamp(math.min(height * 0.52, textWidth / (math.max(12, textLength) * 0.43)), 10, 52)

    InsetTexture(miniFrame.background, miniFrame, MINI_BG_INSET)

    miniFrame.icon:SetSize(iconSize, iconSize)
    miniFrame.icon:ClearAllPoints()
    miniFrame.icon:SetPoint("LEFT", miniFrame, "LEFT", padding, 0)

    miniFrame.timerText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
    miniFrame.timerText:ClearAllPoints()
    miniFrame.timerText:SetPoint("LEFT", miniFrame.icon, "RIGHT", padding, 0)
    miniFrame.timerText:SetPoint("RIGHT", miniFrame, "RIGHT", -padding, 0)
    miniFrame.timerText:SetJustifyH("CENTER")

    miniFrame.resizeGrip:SetSize(MINI_RESIZE_GRIP_SIZE, MINI_RESIZE_GRIP_SIZE)
end

function UpdateMiniWindow()
    if not miniFrame then
        return
    end

    local nextEvent = GetNextEvent(currentEvents)
    if not currentServer or not nextEvent then
        local style = BUFF_STYLES.default
        SetVerticalGradient(miniFrame.background, Darken(style.color, 0.34), style.color)
        miniFrame.icon:SetTexture(GetStyleIcon(style))
        miniFrame.timerText:SetText("NONE - --:--:--")
        LayoutMiniWindow()
        return
    end

    local style = GetBuffStyle(nextEvent)

    SetVerticalGradient(miniFrame.background, Darken(style.color, 0.34), style.color)
    miniFrame.icon:SetTexture(GetStyleIcon(style))
    miniFrame.timerText:SetText(string.format("%s - %s", style.short, FormatCountdown(nextEvent.timestamp - time())))
    LayoutMiniWindow()
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
    SetResizeBounds(miniFrame, MINI_MIN_WIDTH, MINI_MIN_HEIGHT, MINI_MAX_WIDTH, MINI_MAX_HEIGHT)

    miniFrame.background = miniFrame:CreateTexture(nil, "BACKGROUND")
    InsetTexture(miniFrame.background, miniFrame, MINI_BG_INSET)

    miniFrame.icon = miniFrame:CreateTexture(nil, "ARTWORK")
    miniFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    miniFrame.timerText = miniFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    miniFrame.timerText:SetTextColor(1, 1, 1)

    miniFrame.resizeGrip = CreateResizeGrip(miniFrame, MINI_RESIZE_GRIP_SIZE, function()
        miniFrame:StartSizing("BOTTOMRIGHT")
    end, function()
        miniFrame:StopMovingOrSizing()
        SaveMiniGeometry()
        LayoutMiniWindow()
        RefreshOptionControls()
    end)

    miniFrame:SetScript("OnDragStart", function()
        miniFrame:StartMoving()
    end)
    miniFrame:SetScript("OnDragStop", function()
        miniFrame:StopMovingOrSizing()
        SaveMiniGeometry()
        RefreshOptionControls()
    end)
    miniFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ToggleOptionsWindow()
        end
    end)
    miniFrame:SetScript("OnSizeChanged", function()
        SaveMiniGeometry()
        LayoutMiniWindow()
        UpdateMiniWindow()
        RefreshOptionControls()
    end)

    LayoutMiniWindow()
    UpdateMiniWindow()
    miniFrame:Hide()
end

function LayoutMainWindow()
    if not WhenBuff.scrollFrame then
        return
    end

    local width, height = WhenBuff:GetSize()
    local padding = 18
    local buttonY = 12
    local scrollTop = 126
    local bottomReserve = 56
    local closeReserve = 48
    local scrollWidth = math.max(260, width - (padding * 2) - 22)
    local scrollHeight = math.max(96, height - scrollTop - bottomReserve)
    local childWidth = math.max(240, scrollWidth - 24)

    InsetTexture(WhenBuff.background, WhenBuff, MAIN_BG_INSET)
    SetVerticalGradient(WhenBuff.background, COLORS.mainTop, COLORS.mainBottom)

    WhenBuff.title:SetWidth(math.max(160, width - (padding * 2) - closeReserve))
    WhenBuff.realmText:SetWidth(math.max(160, width - (padding * 2)))

    WhenBuff.nextIcon:SetSize(24, 24)
    WhenBuff.nextIcon:ClearAllPoints()
    WhenBuff.nextIcon:SetPoint("TOPLEFT", WhenBuff.realmText, "BOTTOMLEFT", 0, -16)
    WhenBuff.nextText:SetWidth(math.max(170, width - (padding * 2) - 34))
    WhenBuff.nextText:ClearAllPoints()
    WhenBuff.nextText:SetPoint("LEFT", WhenBuff.nextIcon, "RIGHT", 8, 0)
    WhenBuff.nextText:SetPoint("RIGHT", WhenBuff, "RIGHT", -padding, 0)

    WhenBuff.todayHeader:ClearAllPoints()
    WhenBuff.todayHeader:SetPoint("TOPLEFT", WhenBuff.nextIcon, "BOTTOMLEFT", 0, -16)

    WhenBuff.scrollFrame:ClearAllPoints()
    WhenBuff.scrollFrame:SetPoint("TOPLEFT", WhenBuff.todayHeader, "BOTTOMLEFT", 0, -10)
    WhenBuff.scrollFrame:SetSize(scrollWidth, scrollHeight)
    WhenBuff.scrollChild:SetSize(childWidth, math.max(scrollHeight, WhenBuff.scrollChild:GetHeight() or scrollHeight))
    WhenBuff.listAnchor:SetSize(childWidth, 1)

    WhenBuff.generatedText:SetWidth(math.max(120, width - 230))

    WhenBuff.refreshButton:SetPoint("BOTTOMRIGHT", WhenBuff, "BOTTOMRIGHT", -(padding + RESIZE_GRIP_SIZE + 10), buttonY)
    WhenBuff.optionsButton:SetPoint("RIGHT", WhenBuff.refreshButton, "LEFT", -8, 0)
    WhenBuff.miniButton:SetPoint("RIGHT", WhenBuff.optionsButton, "LEFT", -8, 0)
    WhenBuff.resizeGrip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)

    RefreshRows(GetTodayEvents(currentEvents))
end

local function BuildWindow()
    WhenBuff:SetSize(DB.width, DB.height)
    WhenBuff:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
    WhenBuff:SetMovable(true)
    WhenBuff:SetResizable(true)
    WhenBuff:EnableMouse(true)
    WhenBuff:RegisterForDrag("LeftButton")
    WhenBuff:SetClampedToScreen(true)
    WhenBuff:SetScript("OnDragStart", WhenBuff.StartMoving)
    WhenBuff:SetScript("OnDragStop", function()
        WhenBuff:StopMovingOrSizing()
        SaveMainGeometry()
        RefreshOptionControls()
    end)
    WhenBuff:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    SetResizeBounds(WhenBuff, MAIN_MIN_WIDTH, MAIN_MIN_HEIGHT, MAIN_MAX_WIDTH, MAIN_MAX_HEIGHT)

    WhenBuff.background = WhenBuff:CreateTexture(nil, "BACKGROUND")
    InsetTexture(WhenBuff.background, WhenBuff, MAIN_BG_INSET)

    WhenBuff.title = CreateFont(WhenBuff, 18, "GameFontHighlightLarge")
    WhenBuff.title:SetPoint("TOPLEFT", WhenBuff, "TOPLEFT", 20, -18)

    WhenBuff.close = CreateFrame("Button", nil, WhenBuff, "UIPanelCloseButton")
    WhenBuff.close:SetPoint("TOPRIGHT", WhenBuff, "TOPRIGHT", -8, -8)
    WhenBuff.close:SetScript("OnClick", function()
        DB.hidden = true
        WhenBuff:Hide()
    end)

    WhenBuff.realmText = CreateFont(WhenBuff, 12)
    WhenBuff.realmText:SetPoint("TOPLEFT", WhenBuff.title, "BOTTOMLEFT", 0, -6)
    WhenBuff.realmText:SetTextColor(unpack(COLORS.muted))

    WhenBuff.nextIcon = WhenBuff:CreateTexture(nil, "ARTWORK")
    WhenBuff.nextIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    WhenBuff.nextText = CreateFont(WhenBuff, 14, "GameFontHighlight")

    WhenBuff.todayHeader = CreateFont(WhenBuff, 13, "GameFontHighlight")
    WhenBuff.todayHeader:SetText("Upcoming Today")

    WhenBuff.scrollFrame = CreateFrame("ScrollFrame", nil, WhenBuff, "UIPanelScrollFrameTemplate")
    WhenBuff.scrollChild = CreateFrame("Frame", nil, WhenBuff.scrollFrame)
    WhenBuff.scrollFrame:SetScrollChild(WhenBuff.scrollChild)

    WhenBuff.listAnchor = CreateFrame("Frame", nil, WhenBuff.scrollChild)
    WhenBuff.listAnchor:SetPoint("TOPLEFT", WhenBuff.scrollChild, "TOPLEFT", 0, 0)

    WhenBuff.emptyText = CreateFont(WhenBuff.scrollChild, 13)
    WhenBuff.emptyText:SetPoint("TOPLEFT", WhenBuff.listAnchor, "BOTTOMLEFT", 0, -8)
    WhenBuff.emptyText:SetTextColor(unpack(COLORS.muted))
    WhenBuff.emptyText:SetText("No buffs remaining today.")

    WhenBuff.generatedText = CreateFont(WhenBuff, 10)
    WhenBuff.generatedText:SetPoint("BOTTOMLEFT", WhenBuff, "BOTTOMLEFT", 20, 16)
    WhenBuff.generatedText:SetTextColor(unpack(COLORS.muted))

    local refreshButton = CreateFrame("Button", nil, WhenBuff, "UIPanelButtonTemplate")
    refreshButton:SetSize(74, 22)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        RefreshWindow()
        Print("View refreshed from loaded Data.lua. New WhenBuff website data requires updating Data.lua and /reload.")
    end)
    WhenBuff.refreshButton = refreshButton

    local optionsButton = CreateFrame("Button", nil, WhenBuff, "UIPanelButtonTemplate")
    optionsButton:SetSize(76, 22)
    optionsButton:SetText("Options")
    optionsButton:SetScript("OnClick", function()
        ToggleOptionsWindow()
    end)
    WhenBuff.optionsButton = optionsButton

    local miniButton = CreateFrame("Button", nil, WhenBuff, "UIPanelButtonTemplate")
    miniButton:SetSize(56, 22)
    miniButton:SetText("Mini")
    miniButton:SetScript("OnClick", function()
        HandleSlashCommand("mini")
    end)
    WhenBuff.miniButton = miniButton

    WhenBuff.resizeGrip = CreateResizeGrip(WhenBuff, RESIZE_GRIP_SIZE, function()
        WhenBuff:StartSizing("BOTTOMRIGHT")
    end, function()
        WhenBuff:StopMovingOrSizing()
        SaveMainGeometry()
        LayoutMainWindow()
        RefreshOptionControls()
    end)

    WhenBuff:SetScript("OnSizeChanged", function()
        SaveMainGeometry()
        LayoutMainWindow()
        RefreshOptionControls()
    end)

    LayoutMainWindow()
end

function RefreshWindow()
    playerFaction = GetPlayerFaction()
    currentServer = FindCurrentServer()
    currentEvents = GetServerEvents(currentServer)
    lastViewRefresh = time()

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

    LayoutMainWindow()
    UpdateCountdown()
    UpdateMiniWindow()
end

function UpdateCountdown()
    local nextEvent = GetNextEvent(currentEvents)

    if not currentServer then
        WhenBuff.nextIcon:SetTexture(GetStyleIcon(BUFF_STYLES.default))
        WhenBuff.nextText:SetText("Next buff: no realm data")
        WhenBuff.nextText:SetTextColor(unpack(COLORS.text))
        return
    end

    if not nextEvent then
        WhenBuff.nextIcon:SetTexture(GetStyleIcon(BUFF_STYLES.default))
        WhenBuff.nextText:SetText("Next buff: none scheduled")
        WhenBuff.nextText:SetTextColor(unpack(COLORS.text))
        return
    end

    local style = GetBuffStyle(nextEvent)
    WhenBuff.nextIcon:SetTexture(GetStyleIcon(style))
    WhenBuff.nextText:SetText(string.format("Next: %s - %s", GetEventLabel(nextEvent), FormatCountdown(nextEvent.timestamp - time())))
    WhenBuff.nextText:SetTextColor(unpack(style.textColor or COLORS.text))
end

local function SendReminder(event, threshold)
    local label = reminderLabels[threshold] or FormatCountdown(threshold)
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
    if time() - lastViewRefresh >= AUTO_VIEW_REFRESH_SECONDS then
        RefreshWindow()
    else
        UpdateCountdown()
        UpdateMiniWindow()
    end
    CheckReminders()
end

local function ShowWindow()
    DB.hidden = false
    RefreshWindow()
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
        Print("View refreshed from loaded Data.lua. New WhenBuff website data requires updating Data.lua and /reload.")
    elseif input == "mini" then
        ToggleMiniWindow()
    elseif input == "options" or input == "config" then
        ToggleOptionsWindow()
    elseif input == "test" then
        Print("Test reminder: Onyxia drops in 5 minutes at 20:00.")
    else
        ToggleWindow()
    end
end

local function OnLogin()
    EnsureDatabase()
    BuildOptionsWindow()
    BuildWindow()
    BuildMiniWindow()
    ClearOldReminderKeys()
    RefreshWindow()

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
