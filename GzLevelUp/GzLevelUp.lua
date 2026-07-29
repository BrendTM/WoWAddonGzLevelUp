local ADDON, ns = ...
local L = ns.L

-- Restored from SavedVariables (or created empty on first launch).
GzLevelUpDB = GzLevelUpDB or {}

local defaults = {
    enabled      = true,
    includeSelf  = false,                    -- also announce my own level-up?
    message      = L.DEFAULT_MESSAGE,        -- message for group members
    selfMessage  = L.DEFAULT_SELF_MESSAGE,   -- message for own level-up
    delayEnabled = false,                    -- delay before sending?
    delaySeconds = 3,                        -- delay in seconds
    quickPanelEnabled = false,               -- show floating gz/ty panel?
    quickPanelScale   = 1.0,                 -- panel scale (0.5 - 2.0)
    gzButtonMessage   = "gz",                -- text of the left button
    tyButtonMessage   = "ty",                -- text of the right button
    -- quickPanelPos is saved when the panel is moved (not in defaults).
}

local MAX_DELAY = 60
local MIN_SCALE, MAX_SCALE = 0.5, 2.0

local function ClampDelay(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > MAX_DELAY then n = MAX_DELAY end
    return n
end

local function ClampScale(n)
    n = tonumber(n) or 1
    if n < MIN_SCALE then n = MIN_SCALE end
    if n > MAX_SCALE then n = MAX_SCALE end
    return n
end

-- GUID -> last known level. Keyed by GUID instead of a unit token so that
-- "party1" isn't later mistakenly attributed to a different player.
local knownLevels = {}

local PREFIX = "|cff33ff99GzLevelUp|r: "

local function ApplyDefaults()
    for k, v in pairs(defaults) do
        if GzLevelUpDB[k] == nil then
            GzLevelUpDB[k] = v
        end
    end
end

-- Replace {name}/{level} in a template.
local function Format(template, name, level)
    return (template or "")
        :gsub("{name}", name or "?")
        :gsub("{level}", tostring(level or 0))
end

-- ---------------------------------------------------------------------------
-- Core logic: detect a level-up and send "gz"
-- ---------------------------------------------------------------------------

-- Only consider real group tokens (no target/mouseover/etc.).
local function IsGroupUnit(unit)
    if unit == "player" then
        return GzLevelUpDB.includeSelf == true
    end
    return (unit:match("^party[1-4]$") or unit:match("^raid%d+$")) ~= nil
end

local function RecordLevel(unit)
    if not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    local lvl  = UnitLevel(unit)
    if guid and lvl and lvl > 0 then
        knownLevels[guid] = lvl
    end
end

-- Silently read every member's current level (no "gz" on join).
local function SyncGroup()
    RecordLevel("player")
    if IsInRaid() then
        for i = 1, 40 do RecordLevel("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do RecordLevel("party" .. i) end
    end
end

-- Sends the (already formatted) message to party/raid chat.
-- Channel and conditions are only checked at the actual moment of sending,
-- since the group may have changed during a delay.
local function SendNow(msg)
    if not GzLevelUpDB.enabled then return end
    if not IsInGroup() then return end
    local channel = IsInRaid() and "RAID" or "PARTY"
    SendChatMessage(msg, channel)
end

local function Announce(unit)
    if not GzLevelUpDB.enabled then return end
    if not IsInGroup() then return end
    -- Own level-up uses the separate message.
    local template = (unit == "player") and GzLevelUpDB.selfMessage or GzLevelUpDB.message
    -- Name/level are substituted NOW (at the moment of the level-up).
    local msg = Format(template, UnitName(unit), UnitLevel(unit))

    local delay = GzLevelUpDB.delayEnabled and ClampDelay(GzLevelUpDB.delaySeconds) or 0
    if delay > 0 then
        C_Timer.After(delay, function() SendNow(msg) end)
    else
        SendNow(msg)
    end
end

local function OnUnitLevel(unit)
    if not IsGroupUnit(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    local newLevel = UnitLevel(unit)
    if not newLevel or newLevel <= 0 then return end

    local old = knownLevels[guid]
    knownLevels[guid] = newLevel
    if old and newLevel > old then
        Announce(unit)
    end
end

-- ---------------------------------------------------------------------------
-- Floating quick-buttons panel (gz / ty)
-- ---------------------------------------------------------------------------
local quickPanel

-- Manual send via button: uses the same channel logic as auto mode.
local function ManualSend(text)
    if not text or text == "" then return end
    if IsInGroup() then
        SendChatMessage(text, IsInRaid() and "RAID" or "PARTY")
    else
        print(PREFIX .. L.NOT_IN_GROUP)
    end
end

local function SaveQuickPanelPos()
    local point, _, relPoint, x, y = quickPanel:GetPoint()
    GzLevelUpDB.quickPanelPos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function RestoreQuickPanelPos()
    local pos = GzLevelUpDB.quickPanelPos
    quickPanel:ClearAllPoints()
    if pos then
        quickPanel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        quickPanel:SetPoint("CENTER")
    end
end

local function RefreshQuickButtons()
    if not quickPanel then return end
    quickPanel.gzBtn:SetText(GzLevelUpDB.gzButtonMessage)
    quickPanel.tyBtn:SetText(GzLevelUpDB.tyButtonMessage)
end

local function CreateQuickPanel()
    if quickPanel then return quickPanel end

    local p = CreateFrame("Frame", "GzLevelUpQuickPanel", UIParent, "BackdropTemplate")
    p:SetSize(148, 54)
    p:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetFrameStrata("MEDIUM")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveQuickPanelPos()
    end)
    p:Hide()

    -- Title bar acts as the drag handle.
    local handle = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    handle:SetPoint("TOP", 0, -8)
    handle:SetText("GzLevelUp")

    local gzBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    gzBtn:SetSize(62, 24)
    gzBtn:SetPoint("BOTTOMLEFT", 8, 8)
    gzBtn:SetScript("OnClick", function() ManualSend(GzLevelUpDB.gzButtonMessage) end)

    local tyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    tyBtn:SetSize(62, 24)
    tyBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    tyBtn:SetScript("OnClick", function() ManualSend(GzLevelUpDB.tyButtonMessage) end)

    p.gzBtn = gzBtn
    p.tyBtn = tyBtn

    quickPanel = p
    p:SetScale(ClampScale(GzLevelUpDB.quickPanelScale))
    RestoreQuickPanelPos()
    RefreshQuickButtons()
    return p
end

local function UpdateQuickPanel()
    local p = CreateQuickPanel()
    RefreshQuickButtons()
    if GzLevelUpDB.quickPanelEnabled then p:Show() else p:Hide() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_LEVEL")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            ApplyDefaults()
        end
    elseif event == "UNIT_LEVEL" then
        OnUnitLevel(arg1)
    else -- PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE
        SyncGroup()
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateQuickPanel()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Configuration window
-- ---------------------------------------------------------------------------
local configFrame

-- Small helper: labeled checkbox.
local function CreateCheck(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    return cb
end

-- Small helper: label + input field + preview line as a block.
local function CreateMessageBlock(parent, labelText, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(350, 28)
    edit:SetPoint("TOPLEFT", x + 4, y - 20)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(240)

    local preview = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", x + 4, y - 46)
    preview:SetWidth(350)
    preview:SetJustifyH("LEFT")

    return label, edit, preview
end

local function BuildConfig()
    if configFrame then return configFrame end

    local frame = CreateFrame("Frame", "GzLevelUpConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 560)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "GzLevelUpConfigFrame") -- closes with ESC

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("GzLevelUp")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOP", 0, -40)
    desc:SetWidth(370)
    desc:SetText(L.CONFIG_DESC)

    -- Block 1: message for group members ----------------------------------
    local groupLabel, groupEdit, groupPreview =
        CreateMessageBlock(frame, L.MESSAGE_LABEL, 30, -70)

    -- Checkbox: announce own level-up -------------------------------------
    local selfCB = CreateCheck(frame, L.OPT_INCLUDE_SELF)
    selfCB:SetPoint("TOPLEFT", 30, -148)

    -- Block 2: message for own level-up -----------------------------------
    local selfLabel, selfEdit, selfPreview =
        CreateMessageBlock(frame, L.SELF_MESSAGE_LABEL, 30, -180)

    -- Enables/disables the field for the own message.
    local function SetSelfEnabled(on)
        selfEdit:EnableMouse(on)
        if on then
            selfEdit:SetTextColor(1, 1, 1)
            selfLabel:SetTextColor(1, 0.82, 0)
            selfPreview:SetTextColor(1, 1, 1)
        else
            selfEdit:ClearFocus()
            selfEdit:SetTextColor(0.5, 0.5, 0.5)
            selfLabel:SetTextColor(0.5, 0.5, 0.5)
            selfPreview:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    selfCB:SetScript("OnClick", function(self)
        GzLevelUpDB.includeSelf = self:GetChecked() and true or false
        SetSelfEnabled(GzLevelUpDB.includeSelf)
    end)

    -- Checkbox: addon enabled ---------------------------------------------
    local enabledCB = CreateCheck(frame, L.OPT_ENABLED)
    enabledCB:SetPoint("TOPLEFT", 30, -258)
    enabledCB:SetScript("OnClick", function(self)
        GzLevelUpDB.enabled = self:GetChecked() and true or false
    end)

    -- Delay (opt-in) + seconds field --------------------------------------
    local delayCB = CreateCheck(frame, L.OPT_DELAY)
    delayCB:SetPoint("TOPLEFT", 30, -288)

    local secLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secLabel:SetPoint("TOPLEFT", 54, -320)
    secLabel:SetText(L.DELAY_SECONDS)

    local delayEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    delayEdit:SetSize(50, 22)
    delayEdit:SetPoint("LEFT", secLabel, "RIGHT", 12, 0)
    delayEdit:SetAutoFocus(false)
    delayEdit:SetMaxLetters(5)

    local function SetDelayEnabled(on)
        delayEdit:EnableMouse(on)
        if on then
            delayEdit:SetTextColor(1, 1, 1)
            secLabel:SetTextColor(1, 0.82, 0)
        else
            delayEdit:ClearFocus()
            delayEdit:SetTextColor(0.5, 0.5, 0.5)
            secLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    delayCB:SetScript("OnClick", function(self)
        GzLevelUpDB.delayEnabled = self:GetChecked() and true or false
        SetDelayEnabled(GzLevelUpDB.delayEnabled)
    end)

    -- Quick-buttons panel (opt-in) + button texts -------------------------
    local quickCB = CreateCheck(frame, L.OPT_QUICKPANEL)
    quickCB:SetPoint("TOPLEFT", 30, -352)
    quickCB:SetScript("OnClick", function(self)
        GzLevelUpDB.quickPanelEnabled = self:GetChecked() and true or false
        UpdateQuickPanel()
    end)

    local gzLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gzLabel:SetPoint("TOPLEFT", 40, -386)
    gzLabel:SetText(L.QUICK_GZ_LABEL)

    local gzEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    gzEdit:SetSize(70, 22)
    gzEdit:SetPoint("LEFT", gzLabel, "RIGHT", 12, 0)
    gzEdit:SetAutoFocus(false)
    gzEdit:SetMaxLetters(40)

    local tyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tyLabel:SetPoint("TOPLEFT", 225, -386)
    tyLabel:SetText(L.QUICK_TY_LABEL)

    local tyEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    tyEdit:SetSize(70, 22)
    tyEdit:SetPoint("LEFT", tyLabel, "RIGHT", 12, 0)
    tyEdit:SetAutoFocus(false)
    tyEdit:SetMaxLetters(40)

    -- Live-update the button labels in the panel.
    gzEdit:SetScript("OnTextChanged", function(self)
        if quickPanel then quickPanel.gzBtn:SetText(self:GetText()) end
    end)
    tyEdit:SetScript("OnTextChanged", function(self)
        if quickPanel then quickPanel.tyBtn:SetText(self:GetText()) end
    end)

    -- Size slider for the panel -------------------------------------------
    local scaleSlider = CreateFrame("Slider", "GzLevelUpScaleSlider", frame, "OptionsSliderTemplate")
    scaleSlider:SetWidth(340)
    scaleSlider:SetPoint("TOP", 0, -448)
    scaleSlider:SetMinMaxValues(MIN_SCALE, MAX_SCALE)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)

    local scaleLow  = _G["GzLevelUpScaleSliderLow"]  or scaleSlider.Low
    local scaleHigh = _G["GzLevelUpScaleSliderHigh"] or scaleSlider.High
    local scaleText = _G["GzLevelUpScaleSliderText"] or scaleSlider.Text
    if scaleLow  then scaleLow:SetText("50%") end
    if scaleHigh then scaleHigh:SetText("200%") end

    scaleSlider:SetScript("OnValueChanged", function(self, value)
        value = ClampScale(value)
        GzLevelUpDB.quickPanelScale = value
        if quickPanel then quickPanel:SetScale(value) end
        if scaleText then
            scaleText:SetText(L.SCALE_LABEL .. ": " .. math.floor(value * 100 + 0.5) .. "%")
        end
    end)

    -- Live preview for both messages --------------------------------------
    local function UpdatePreview()
        local name  = UnitName("player") or L.PLAYER
        local level = (UnitLevel("player") or 1) + 1
        groupPreview:SetText(L.PREVIEW_LABEL .. " \"" .. Format(groupEdit:GetText(), name, level) .. "\"")
        selfPreview:SetText(L.PREVIEW_LABEL .. " \"" .. Format(selfEdit:GetText(), name, level) .. "\"")
    end

    -- Save all settings ---------------------------------------------------
    local function Commit()
        GzLevelUpDB.message         = groupEdit:GetText()
        GzLevelUpDB.selfMessage     = selfEdit:GetText()
        GzLevelUpDB.delaySeconds    = ClampDelay(delayEdit:GetText())
        GzLevelUpDB.gzButtonMessage = gzEdit:GetText()
        GzLevelUpDB.tyButtonMessage = tyEdit:GetText()
        delayEdit:SetText(tostring(GzLevelUpDB.delaySeconds))
        delayEdit:SetCursorPosition(0)
        groupEdit:ClearFocus()
        selfEdit:ClearFocus()
        delayEdit:ClearFocus()
        gzEdit:ClearFocus()
        tyEdit:ClearFocus()
        RefreshQuickButtons()
        print(PREFIX .. L.MSG_SAVED)
    end

    for _, e in ipairs({ groupEdit, selfEdit }) do
        e:SetScript("OnTextChanged", UpdatePreview)
        e:SetScript("OnEnterPressed", Commit)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end

    for _, e in ipairs({ delayEdit, gzEdit, tyEdit }) do
        e:SetScript("OnEnterPressed", Commit)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end

    -- Buttons ----------------------------------------------------------------
    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 24)
    saveBtn:SetPoint("BOTTOMLEFT", 30, 22)
    saveBtn:SetText(L.BTN_SAVE)
    saveBtn:SetScript("OnClick", Commit)

    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetSize(120, 24)
    testBtn:SetPoint("BOTTOM", 0, 22)
    testBtn:SetText(L.BTN_PREVIEW)
    testBtn:SetScript("OnClick", function()
        print(PREFIX .. groupPreview:GetText())
        if GzLevelUpDB.includeSelf then
            print(PREFIX .. selfPreview:GetText())
        end
    end)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(120, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", -30, 22)
    closeBtn:SetText(L.BTN_CLOSE)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Load the current values when opening.
    frame:SetScript("OnShow", function()
        groupEdit:SetText(GzLevelUpDB.message)
        groupEdit:SetCursorPosition(0)
        selfEdit:SetText(GzLevelUpDB.selfMessage)
        selfEdit:SetCursorPosition(0)
        enabledCB:SetChecked(GzLevelUpDB.enabled)
        selfCB:SetChecked(GzLevelUpDB.includeSelf)
        SetSelfEnabled(GzLevelUpDB.includeSelf)
        delayCB:SetChecked(GzLevelUpDB.delayEnabled)
        delayEdit:SetText(tostring(GzLevelUpDB.delaySeconds))
        delayEdit:SetCursorPosition(0)
        SetDelayEnabled(GzLevelUpDB.delayEnabled)
        quickCB:SetChecked(GzLevelUpDB.quickPanelEnabled)
        gzEdit:SetText(GzLevelUpDB.gzButtonMessage)
        gzEdit:SetCursorPosition(0)
        tyEdit:SetText(GzLevelUpDB.tyButtonMessage)
        tyEdit:SetCursorPosition(0)
        scaleSlider:SetValue(ClampScale(GzLevelUpDB.quickPanelScale))
        UpdatePreview()
    end)

    -- Reset the panel labels when closing without saving.
    frame:SetScript("OnHide", RefreshQuickButtons)

    configFrame = frame
    return frame
end

local function ToggleConfig()
    local frame = BuildConfig()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands: /gz
-- ---------------------------------------------------------------------------
local function StateText(v)
    return v and L.STATE_ON or L.STATE_OFF
end

SLASH_GZLEVELUP1 = "/gz"
SlashCmdList.GZLEVELUP = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()

    if cmd == "" or cmd == "config" or cmd == "menu" or cmd == "options" then
        ToggleConfig()
    elseif cmd == "on" then
        GzLevelUpDB.enabled = true
        print(PREFIX .. L.ENABLED_ON)
    elseif cmd == "off" then
        GzLevelUpDB.enabled = false
        print(PREFIX .. L.ENABLED_OFF)
    elseif cmd == "self" then
        GzLevelUpDB.includeSelf = not GzLevelUpDB.includeSelf
        print(PREFIX .. L.INCLUDE_SELF_SET:format(tostring(GzLevelUpDB.includeSelf)))
    elseif cmd == "msg" then
        if rest ~= "" then
            GzLevelUpDB.message = rest
            print(PREFIX .. L.MESSAGE_SET:format(rest))
        else
            print(PREFIX .. L.MESSAGE_CURRENT:format(GzLevelUpDB.message))
        end
    elseif cmd == "selfmsg" then
        if rest ~= "" then
            GzLevelUpDB.selfMessage = rest
            print(PREFIX .. L.SELF_MESSAGE_SET:format(rest))
        else
            print(PREFIX .. L.SELF_MESSAGE_CURRENT:format(GzLevelUpDB.selfMessage))
        end
    elseif cmd == "delay" then
        if rest == "" then
            print(PREFIX .. L.DELAY_CURRENT:format(StateText(GzLevelUpDB.delayEnabled), tostring(GzLevelUpDB.delaySeconds)))
        elseif rest:lower() == "off" then
            GzLevelUpDB.delayEnabled = false
            print(PREFIX .. L.DELAY_OFF)
        else
            local n = ClampDelay(rest)
            GzLevelUpDB.delaySeconds = n
            GzLevelUpDB.delayEnabled = n > 0
            print(PREFIX .. L.DELAY_SET:format(tostring(n)))
        end
    elseif cmd == "panel" then
        GzLevelUpDB.quickPanelEnabled = not GzLevelUpDB.quickPanelEnabled
        UpdateQuickPanel()
        print(PREFIX .. (GzLevelUpDB.quickPanelEnabled and L.PANEL_SHOWN or L.PANEL_HIDDEN))
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n then
            if n > 5 then n = n / 100 end -- allow a percentage like 120
            n = ClampScale(n)
            GzLevelUpDB.quickPanelScale = n
            if quickPanel then quickPanel:SetScale(n) end
            print(PREFIX .. L.SCALE_SET:format(math.floor(n * 100 + 0.5)))
        else
            print(PREFIX .. L.SCALE_SET:format(math.floor(ClampScale(GzLevelUpDB.quickPanelScale) * 100 + 0.5)))
        end
    elseif cmd == "test" then
        local level = (UnitLevel("player") or 1) + 1
        print(PREFIX .. L.PREVIEW_PREFIX .. Format(GzLevelUpDB.message, UnitName("player"), level))
        if GzLevelUpDB.includeSelf then
            print(PREFIX .. L.PREVIEW_PREFIX .. Format(GzLevelUpDB.selfMessage, UnitName("player"), level))
        end
    else
        print(PREFIX .. L.HELP_HEADER)
        print(L.HELP_CONFIG)
        print(L.HELP_ONOFF:format(StateText(GzLevelUpDB.enabled)))
        print(L.HELP_MSG)
        print(L.HELP_SELFMSG)
        print(L.HELP_DELAY)
        print(L.HELP_PANEL)
        print(L.HELP_SCALE)
        print(L.HELP_SELF:format(tostring(GzLevelUpDB.includeSelf)))
        print(L.HELP_TEST)
    end
end
