local addonName, addonTable = ...
local L = addonTable.L
local Compat = addonTable.Compat or {}

addonTable.UI = addonTable.UI or {}
local UI = addonTable.UI
local vitalFrameFrame
local vitalFrameSelection
local selectionFocused = false
local selectionHovered = false
local layoutFocus = nil
local SetLayoutFocus
local vitalFrameSettingsPanel
local suppressNextFocusClear = false
local BAR_ORDER = {
    "xpFill", "petXp", "xpRemaining", "reputation", "profession1", "profession2"
}

local layoutUnlocked = false

local function IsRetailClient()
    if Compat.IsRetailClient then return Compat.IsRetailClient() end
    if WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        return true
    end
    return WOW_PROJECT_ID == 1
end

local function SupportsPetXpLeveling()
    if Compat.SupportsPetXpLeveling then return Compat.SupportsPetXpLeveling() end
    return not IsRetailClient()
end

local function GetSettingsBarOrder()
    local keys = {}
    for _, key in ipairs(BAR_ORDER) do
        if key == "profession1" or key == "profession2" then
            -- Crafting uses one shared settings checkbox.
        elseif key == "xpRemaining" then
            -- XP Remaining is created as a subset of the XP checkbox.
        elseif key ~= "petXp" or SupportsPetXpLeveling() then
            keys[#keys + 1] = key
        end
    end
    return keys
end
local runtimeHiddenBars = {}

local BAR_DEFS = {
    xpFill = {label = L["XP"], color = {0.34, 0.69, 0.17}},
    petXp = {label = L["Pet XP"], color = {0.46, 0, 0.68}},
    xpRemaining = {label = L["XP Remaining"], color = {1, 0.82, 0}},
    profession1 = {label = L["Crafting Skills"], color = {0.85, 0.55, 0.20}},
    profession2 = {label = L["Crafting Skills"], color = {0.75, 0.42, 0.14}},
    reputation = {label = L["Reputation"], color = {0.10, 0.70, 0.30}}
}

local FIXED_BAR_HEIGHT = 30
local PET_BAR_HEIGHT = math.floor(FIXED_BAR_HEIGHT * 2 / 3)
local XP_BAR_HEIGHT = math.floor((FIXED_BAR_HEIGHT + PET_BAR_HEIGHT) / 2)
local CRAFTING_BAR_HEIGHT = math.floor(FIXED_BAR_HEIGHT * 0.4)
local XP_BAR_KEYS = {
    xpFill = true,
    xpRemaining = true,
    reputation = true
}
local CRAFTING_BAR_KEYS = {
    profession1 = true,
    profession2 = true
}

local DEFAULT_FRAME_HEIGHT = 200

local function GetBaseBarHeight(barKey)
    if CRAFTING_BAR_KEYS[barKey] then return CRAFTING_BAR_HEIGHT end
    if XP_BAR_KEYS[barKey] then return XP_BAR_HEIGHT end
    if barKey == "petXp" then return PET_BAR_HEIGHT end
    return FIXED_BAR_HEIGHT
end

local LEVEL_BASE_FONT_SIZE = 60
local LEVEL_TEXT_VERTICAL_PADDING = 5
local NAME_FIRST_FONT_SIZE = 24
local NAME_LAST_FONT_SIZE = 12
local NAME_ICON_GAP = 8
local NAME_FRAME_INSET = 8
local BAR_REGION_COLOR = {0, 0, 0, 0.68}
local BAR_TRACK_COLOR = {0.18, 0.18, 0.18, 0.35}
local BAR_DIVIDER_COLOR = {1, 1, 1, 0.32}
local BAR_DIVIDER_HEIGHT = 1
local THEME_COLORS = {
    classic = {1, 1, 1, 1},
    forever = {0.83, 0.66, 0.27, 1}
}

local UpdateProgressBarLayout
local UpdateEditModeDragState
local levelLayoutRetryPending = false

local function GetDB()
    if addonTable and addonTable.GetDB then return addonTable.GetDB() end
    return nil
end

local function NormalizeTheme(theme)
    if theme == "classic" or theme == "forever" then return theme end
    return "auto"
end

local function GetTheme()
    local db = GetDB()
    if not db or not db.profile then return "auto" end
    return NormalizeTheme(db.profile.theme)
end

local function GetResolvedTheme()
    local theme = GetTheme()
    if theme == "classic" or theme == "forever" then return theme end
    if Compat.IsForeverClient and Compat.IsForeverClient() then
        return "forever"
    end
    return "classic"
end

local function GetResolvedThemeColor()
    local color = THEME_COLORS[GetResolvedTheme()] or THEME_COLORS.classic
    return color[1], color[2], color[3], color[4]
end

local function RefreshThemeChecks()
    if not vitalFrameSettingsPanel then return end
    local theme = GetTheme()
    if vitalFrameSettingsPanel.themeAutoCheck then
        vitalFrameSettingsPanel.themeAutoCheck:SetChecked(theme == "auto")
    end
    if vitalFrameSettingsPanel.themeClassicCheck then
        vitalFrameSettingsPanel.themeClassicCheck:SetChecked(theme == "classic")
    end
    if vitalFrameSettingsPanel.themeForeverCheck then
        vitalFrameSettingsPanel.themeForeverCheck:SetChecked(theme == "forever")
    end
end

local function ApplyFrameTheme()
    local r, g, b, a = GetResolvedThemeColor()
    if vitalFrameFrame and vitalFrameFrame.SetBackdropBorderColor then
        vitalFrameFrame:SetBackdropBorderColor(r, g, b, a)
    end
    if UI.ApplySkillsFrameTheme then UI.ApplySkillsFrameTheme() end
    RefreshThemeChecks()
end

local function SetTheme(theme)
    local db = GetDB()
    if db and db.profile then db.profile.theme = NormalizeTheme(theme) end
    ApplyFrameTheme()
end

local function GetAutoScaleBars()
    local db = GetDB()
    if not db or not db.profile or not db.profile.bars then return false end
    return db.profile.bars.autoScale == true
end

local function SetAutoScaleBars(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.autoScale = enabled and true or false
    UpdateProgressBarLayout()
end

local function GetBarHeight(barKey)
    local base = GetBaseBarHeight(barKey)
    if not GetAutoScaleBars() then return base end

    local height = vitalFrameFrame and vitalFrameFrame:GetHeight() or
                       DEFAULT_FRAME_HEIGHT
    if height < DEFAULT_FRAME_HEIGHT then height = DEFAULT_FRAME_HEIGHT end
    local scaled = math.floor(base * (height / DEFAULT_FRAME_HEIGHT) + 0.5)
    if scaled < 1 then scaled = 1 end
    return scaled
end

local function IsBarEnabled(barKey)
    local db = GetDB()
    if not db or not db.profile or not db.profile.bars or
        not db.profile.bars.enabled then return true end
    local settingKey = barKey
    if barKey == "profession1" or barKey == "profession2" then
        settingKey = "crafting"
    end
    local v = db.profile.bars.enabled[settingKey]
    if v == nil then return true end
    return v == true
end

local function IsBarRuntimeHidden(barKey)
    return runtimeHiddenBars[barKey] == true
end

local function ShouldShowBar(barKey)
    return IsBarEnabled(barKey) and not IsBarRuntimeHidden(barKey)
end

local function SetBarRuntimeHidden(barKey, hidden)
    hidden = hidden and true or false
    if runtimeHiddenBars[barKey] == hidden then return end
    runtimeHiddenBars[barKey] = hidden
    UpdateProgressBarLayout()
end

local function GetEnabledBarKeys()
    local keys = {}
    for _, key in ipairs(BAR_ORDER) do
        if ShouldShowBar(key) then keys[#keys + 1] = key end
    end
    return keys
end

local function SetBarEnabled(barKey, enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.enabled = db.profile.bars.enabled or {}
    db.profile.bars.enabled[barKey] = enabled and true or false
    UpdateProgressBarLayout()
    if addonTable and addonTable.RefreshAllData then
        addonTable.RefreshAllData()
    end
end

local function GetXPFillOption(optionKey)
    local db = GetDB()
    if not db or not db.profile then return false end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.xpFill = db.profile.bars.xpFill or {}

    if db.profile.bars.xpFill.useClassColor == nil then
        db.profile.bars.xpFill.useClassColor = false
    end

    if db.profile.bars.xpFill.hideWhenMaxLevel == nil then
        db.profile.bars.xpFill.hideWhenMaxLevel = false
    end

    return db.profile.bars.xpFill[optionKey] == true
end

local function GetHideBlizzardWatchBar()
    local db = GetDB()
    if not db or not db.profile then return true end
    if db.profile.hideBlizzardWatchBar == nil then return true end
    return db.profile.hideBlizzardWatchBar == true
end

local function SetHideBlizzardWatchBar(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.hideBlizzardWatchBar = enabled and true or false
end

local function GetStreamerMode()
    local db = GetDB()
    if not db or not db.profile then return false end
    return db.profile.streamerMode == true
end

local streamerModeActive = false
local targetShowsPlayer = false
local focusShowsPlayer = false
local applyingUnitName = false
local cachedDisplayName

local function RefreshCachedDisplayName()
    if GetStreamerMode() then
        cachedDisplayName = UnitClass("player") or L["Character"]
    else
        cachedDisplayName = UnitName("player") or L["Character"]
    end
end

local function GetDisplayName()
    if cachedDisplayName then return cachedDisplayName end
    RefreshCachedDisplayName()
    return cachedDisplayName or L["Character"]
end

local function SetStreamerMode(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.streamerMode = enabled and true or false
    streamerModeActive = db.profile.streamerMode == true
    RefreshCachedDisplayName()
end

local function GetNameMaxWidth()
    local frameWidth = vitalFrameFrame and vitalFrameFrame:GetWidth() or
                           DEFAULT_FRAME_HEIGHT
    local iconWidth = vitalFrameFrame and vitalFrameFrame.ClassIcon and
                          vitalFrameFrame.ClassIcon:GetWidth() or 22
    local maxWidth = math.floor(frameWidth - (NAME_FRAME_INSET * 2) - iconWidth -
                                    NAME_ICON_GAP)
    if maxWidth < 40 then maxWidth = 40 end
    return maxWidth
end

local function SplitDisplayName(name)
    name = name or ""
    local space = string.find(name, " ", 1, true)
    if not space then return name, nil end
    local firstName = string.sub(name, 1, space - 1)
    local lastName = string.sub(name, space + 1)
    if lastName == "" then return firstName, nil end
    return firstName, lastName
end

local function ApplyNameFont(fontString, size)
    if not fontString then return end
    local fontPath, _, flags = fontString:GetFont()
    fontString:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", size, flags)
end

local function GetHeaderNameBottom()
    local lastNameText = vitalFrameFrame and vitalFrameFrame.LastNameText
    if lastNameText and lastNameText:IsShown() then
        return lastNameText:GetBottom()
    end
    if vitalFrameFrame and vitalFrameFrame.NameText then
        return vitalFrameFrame.NameText:GetBottom()
    end
    return nil
end

local function UpdateHeaderLayout()
    if not vitalFrameFrame or not vitalFrameFrame.NameText or
        not vitalFrameFrame.ClassIcon then return end

    local nameText = vitalFrameFrame.NameText
    local lastNameText = vitalFrameFrame.LastNameText
    local classIcon = vitalFrameFrame.ClassIcon
    local maxWidth = GetNameMaxWidth()
    local firstName, lastName = SplitDisplayName(GetDisplayName())

    ApplyNameFont(nameText, NAME_FIRST_FONT_SIZE)
    nameText:SetWidth(maxWidth)
    nameText:SetWordWrap(true)
    nameText:SetNonSpaceWrap(true)
    nameText:SetJustifyH("LEFT")
    nameText:SetJustifyV("TOP")
    nameText:SetText(firstName)

    local nameWidth = math.ceil(nameText:GetStringWidth() or 0)
    if nameWidth > maxWidth then nameWidth = maxWidth end
    local nameHeight = math.ceil(nameText:GetStringHeight() or
                                     classIcon:GetHeight())

    if lastNameText then
        if lastName then
            ApplyNameFont(lastNameText, NAME_LAST_FONT_SIZE)
            lastNameText:SetWidth(maxWidth)
            lastNameText:SetWordWrap(true)
            lastNameText:SetNonSpaceWrap(true)
            lastNameText:SetJustifyH("LEFT")
            lastNameText:SetJustifyV("TOP")
            lastNameText:SetText(lastName)
            lastNameText:Show()
            local lastWidth = math.ceil(lastNameText:GetStringWidth() or 0)
            if lastWidth > maxWidth then lastWidth = maxWidth end
            if lastWidth > nameWidth then nameWidth = lastWidth end
            nameHeight = nameHeight +
                             math.ceil(lastNameText:GetStringHeight() or
                                           NAME_LAST_FONT_SIZE)
        else
            lastNameText:SetText("")
            lastNameText:Hide()
        end
    end

    local headerHeight = math.max(classIcon:GetHeight(), nameHeight)
    if vitalFrameFrame.HeaderGroup then
        vitalFrameFrame.HeaderGroup:SetSize(classIcon:GetWidth() + NAME_ICON_GAP +
                                                nameWidth, headerHeight)
    end
end

local blizzardNameHooked = false
local compactNameHooked = false
local hookedNameFontStrings = {}

local function NameEqualsPlayer(unit)
    local ok, isPlayer = pcall(function()
        local unitName = UnitName(unit)
        local playerName = UnitName("player")
        return unitName ~= nil and unitName == playerName
    end)
    return ok and isPlayer == true
end

local function RefreshStreamerNameFlags()
    streamerModeActive = GetStreamerMode()
    RefreshCachedDisplayName()
    targetShowsPlayer = NameEqualsPlayer("target")
    focusShowsPlayer = NameEqualsPlayer("focus")
end

local function SafeSetUnitName(fontString, text)
    if not fontString then return end
    applyingUnitName = true
    fontString:SetText(text)
    applyingUnitName = false
end

local function HookNameFontString(fontString, shouldReplace)
    if not fontString or hookedNameFontStrings[fontString] then return end
    hookedNameFontStrings[fontString] = true
    hooksecurefunc(fontString, "SetText", function(self, text)
        if applyingUnitName then return end
        if not streamerModeActive then return end
        if shouldReplace and not shouldReplace() then return end
        SafeSetUnitName(self, GetDisplayName())
    end)
end

local function HookCompactUnitFrameName()
    if compactNameHooked or not CompactUnitFrame_UpdateName then return end
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if not streamerModeActive then return end
        if not frame or not frame.name then return end
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
        local plate = C_NamePlate.GetNamePlateForUnit("player")
        if plate and plate.UnitFrame == frame then
            SafeSetUnitName(frame.name, GetDisplayName())
        end
    end)
    compactNameHooked = true
end

local function ApplyPlayerFrameName()
    if not PlayerFrame or not PlayerFrame.name then return end
    SafeSetUnitName(PlayerFrame.name, GetDisplayName())
end

local function ApplyPlayerNamePlateName()
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local plate = C_NamePlate.GetNamePlateForUnit("player")
    local unitFrame = plate and plate.UnitFrame
    if not unitFrame or not unitFrame.name then return end
    SafeSetUnitName(unitFrame.name, GetDisplayName())
end

local function ApplySelfTargetFrameName()
    RefreshStreamerNameFlags()
    if TargetFrame and TargetFrame.name and targetShowsPlayer then
        SafeSetUnitName(TargetFrame.name, GetDisplayName())
    end
    if FocusFrame and FocusFrame.name and focusShowsPlayer then
        SafeSetUnitName(FocusFrame.name, GetDisplayName())
    end
end

local function ApplyStreamerUnitNames()
    RefreshStreamerNameFlags()
    ApplyPlayerFrameName()
    ApplyPlayerNamePlateName()
    ApplySelfTargetFrameName()
end

local function HookStreamerUnitNames()
    if blizzardNameHooked then return end
    RefreshStreamerNameFlags()

    if PlayerFrame and PlayerFrame.name then
        HookNameFontString(PlayerFrame.name)
    end
    if TargetFrame and TargetFrame.name then
        HookNameFontString(TargetFrame.name, function()
            return targetShowsPlayer
        end)
    end
    if FocusFrame and FocusFrame.name then
        HookNameFontString(FocusFrame.name, function()
            return focusShowsPlayer
        end)
    end

    HookCompactUnitFrameName()

    local nameEventFrame = CreateFrame("Frame")
    local registerNameEvent = Compat.RegisterEvent or function(frame, event)
        frame:RegisterEvent(event)
    end
    registerNameEvent(nameEventFrame, "NAME_PLATE_UNIT_ADDED")
    registerNameEvent(nameEventFrame, "UNIT_NAME_UPDATE")
    registerNameEvent(nameEventFrame, "PLAYER_TARGET_CHANGED")
    registerNameEvent(nameEventFrame, "PLAYER_FOCUS_CHANGED")
    nameEventFrame:SetScript("OnEvent", function(_, event, unit)
        HookCompactUnitFrameName()
        Compat.After(0, function()
            RefreshStreamerNameFlags()
            if not streamerModeActive then return end
            if event == "PLAYER_TARGET_CHANGED" or event ==
                "PLAYER_FOCUS_CHANGED" then
                ApplySelfTargetFrameName()
                return
            end
            if event == "NAME_PLATE_UNIT_ADDED" then
                if unit and NameEqualsPlayer(unit) then
                    ApplyPlayerNamePlateName()
                end
                return
            end
            if unit and NameEqualsPlayer(unit) then ApplyStreamerUnitNames() end
        end)
    end)

    blizzardNameHooked = true
end

local function UpdateNameText()
    if vitalFrameFrame and vitalFrameFrame.NameText then
        UpdateHeaderLayout()
    end
    ApplyStreamerUnitNames()
end

local applyingBlizzardWatchBar = false
local blizzardWatchBarHooked = false

local function GetBlizzardWatchBars()
    local bars = {}
    if StatusTrackingBarManager then
        bars[#bars + 1] = StatusTrackingBarManager
    end
    if ReputationWatchBar then bars[#bars + 1] = ReputationWatchBar end
    return bars
end

local function ApplyBlizzardWatchBarVisibility()
    if applyingBlizzardWatchBar then return end
    local bars = GetBlizzardWatchBars()
    if #bars == 0 then return end

    local hide = GetHideBlizzardWatchBar() and vitalFrameFrame and
                     vitalFrameFrame:IsShown()
    applyingBlizzardWatchBar = true
    for _, bar in ipairs(bars) do
        if hide then
            bar:Hide()
        else
            bar:Show()
            if bar.UpdateBarsShown then bar:UpdateBarsShown() end
        end
    end
    applyingBlizzardWatchBar = false
end

local function HookBlizzardWatchBar()
    if blizzardWatchBarHooked then return end
    local manager = StatusTrackingBarManager
    if manager and manager.UpdateBarsShown then
        hooksecurefunc(manager, "UpdateBarsShown", function()
            if applyingBlizzardWatchBar then return end
            if GetHideBlizzardWatchBar() and vitalFrameFrame and
                vitalFrameFrame:IsShown() then
                applyingBlizzardWatchBar = true
                manager:Hide()
                applyingBlizzardWatchBar = false
            end
        end)
        blizzardWatchBarHooked = true
    end
    if ReputationWatchBar then
        hooksecurefunc(ReputationWatchBar, "Show", function(self)
            if applyingBlizzardWatchBar then return end
            if GetHideBlizzardWatchBar() and vitalFrameFrame and
                vitalFrameFrame:IsShown() then
                applyingBlizzardWatchBar = true
                self:Hide()
                applyingBlizzardWatchBar = false
            end
        end)
        blizzardWatchBarHooked = true
    end
end

local function SetXPFillOption(optionKey, enabled)
    local db = GetDB()
    if not db or not db.profile then return end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.xpFill = db.profile.bars.xpFill or {}
    db.profile.bars.xpFill[optionKey] = enabled and true or false
end

local function GetReputationAutoSwitch()
    local db = GetDB()
    if not db or not db.profile then return true end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.reputation = db.profile.bars.reputation or {}
    if db.profile.bars.reputation.autoSwitch == nil then
        db.profile.bars.reputation.autoSwitch = true
    end
    return db.profile.bars.reputation.autoSwitch == true
end

local function SetReputationAutoSwitch(enabled)
    local db = GetDB()
    if not db or not db.profile then return end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.reputation = db.profile.bars.reputation or {}
    db.profile.bars.reputation.autoSwitch = enabled and true or false
end

local function SetBarPercent(barKey, percent)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end
    local bar = vitalFrameFrame.ProgressBarsByKey[barKey]
    if not bar then return end
    local p = tonumber(percent) or 0
    if barKey == "petXp" and not SupportsPetXpLeveling() then
        p = 1
    else
        p = tonumber(percent) or 0
        if p < 0 then p = 0 end
        if p > 1 then p = 1 end
    end
    bar:SetValue(p)
end

local function SetBarColor(barKey, r, g, b, a)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end
    local bar = vitalFrameFrame.ProgressBarsByKey[barKey]
    if not bar then return end

    local rr = tonumber(r) or 1
    local gg = tonumber(g) or 1
    local bb = tonumber(b) or 1
    local aa = tonumber(a) or 1

    if rr < 0 then rr = 0 end
    if rr > 1 then rr = 1 end
    if gg < 0 then gg = 0 end
    if gg > 1 then gg = 1 end
    if bb < 0 then bb = 0 end
    if bb > 1 then bb = 1 end
    if aa < 0 then aa = 0 end
    if aa > 1 then aa = 1 end

    bar:SetStatusBarColor(rr, gg, bb, aa)
end

local function SetBarLabelText(barKey, text)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end
    local bar = vitalFrameFrame.ProgressBarsByKey[barKey]
    if not bar or not bar.LabelText then return end
    if barKey == "reputation" or barKey == "profession1" or
        barKey == "profession2" then
        bar.LabelText:SetFontObject(GameFontHighlightSmall)
    else
        bar.LabelText:SetFontObject(GameFontHighlight)
    end
    bar.LabelText:SetText(text or "")
end

local function SetLevelText(level)
    if not vitalFrameFrame or not vitalFrameFrame.LevelText then return end
    local n = tonumber(level)
    if not n then n = UnitLevel("player") end
    if not n then return end
    vitalFrameFrame.LevelText:SetText(tostring(n))
end

local function SetBarBackgroundPercent(barKey, percent)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end
    local bar = vitalFrameFrame.ProgressBarsByKey[barKey]
    if not bar or not bar.BgFill then return end
    local p = tonumber(percent) or 0
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    bar.BgFill:SetValue(p)
    bar.BgFill:SetShown(p > 0)
end

local function PrintMessage(msg)
    if addonTable and addonTable.PrintMessage then
        addonTable.PrintMessage(msg)
    end
end

local function LockFrameToAddonPosition(frame)
    frame = frame or vitalFrameFrame
    if not frame then return end
    if frame.SetDontSavePosition then
        pcall(frame.SetDontSavePosition, frame, true)
    end
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

local function SaveFramePositionFromOffsets(x, y)
    local db = GetDB()
    if not db or not db.profile or not db.profile.frame then return end
    db.profile.frame.point = "TOPLEFT"
    db.profile.frame.x = tonumber(x) or 0
    db.profile.frame.y = tonumber(y) or 0
end

local function SaveFramePosition()
    local db = GetDB()
    if not db or not db.profile or not db.profile.frame or not vitalFrameFrame then
        return
    end

    local ok, point, x, y = pcall(function()
        local p, _, _, px, py = vitalFrameFrame:GetPoint(1)
        return p, tonumber(px), tonumber(py)
    end)
    if ok and x and y then
        db.profile.frame.point = point or "TOPLEFT"
        db.profile.frame.x = x
        db.profile.frame.y = y
        return
    end

    ok, x, y = pcall(function()
        local left = tonumber(vitalFrameFrame:GetLeft())
        local top = tonumber(vitalFrameFrame:GetTop())
        local parentHeight = tonumber(UIParent:GetHeight()) or 0
        local scale = tonumber(vitalFrameFrame:GetScale()) or 1
        if not left or not top then return nil end
        return left, -((parentHeight - top * scale) / scale)
    end)
    if ok and x and y then SaveFramePositionFromOffsets(x, y) end
end

local function SaveFrameSize(width, height)
    local db = GetDB()
    if not db or not db.profile or not db.profile.frame then return end

    db.profile.frame.width = math.floor(width or 200)
    db.profile.frame.height = math.floor(height or 200)
end

local EDIT_MODE_SNAP_METHODS = {
    "IsToTheLeftOfFrame", "IsToTheRightOfFrame", "IsAboveFrame",
    "IsBelowFrame", "IsVerticallyAlignedWithFrame",
    "IsHorizontallyAlignedWithFrame", "GetScaledSelectionCenter",
    "GetScaledCenter", "GetScaledSelectionSides", "GetLeftOffset",
    "GetRightOffset", "GetTopOffset", "GetBottomOffset",
    "GetSelectionOffset", "GetCombinedSelectionOffset",
    "GetCombinedCenterOffset", "GetSnapOffsets", "AddSnappedFrame",
    "RemoveSnappedFrame", "BreakSnappedFrames", "SetSnappedToFrame",
    "ClearFrameSnap", "SnapToFrame", "IsFrameAnchoredToMe",
    "GetFrameMagneticEligibility"
}

local function IsEditModeOpen()
    if EditModeManagerFrame then return EditModeManagerFrame:IsShown() end
    return layoutUnlocked == true
end

local function SetLayoutUnlocked(unlocked)
    layoutUnlocked = unlocked and true or false
    if SetLayoutFocus then
        SetLayoutFocus(layoutUnlocked and "main" or nil)
    else
        layoutFocus = layoutUnlocked and "main" or nil
        selectionFocused = layoutUnlocked and true or false
        selectionHovered = layoutUnlocked and true or false
    end
    UpdateEditModeDragState()
end

local function CanUseEditModeSnap()
    return EditModeMagnetismManager ~= nil and EditModeSystemMixin ~= nil
end

local function GetScaledSelectionSidesSafe(self)
    local source = self.Selection
    local left, bottom, width, height
    if source and source.GetRect then
        left, bottom, width, height = source:GetRect()
    end
    if not left and self.GetRect then
        left, bottom, width, height = self:GetRect()
    end
    if not left then return 0, 0, 0, 0 end
    local scale = self.GetScale and self:GetScale() or 1
    return left * scale, (left + width) * scale, bottom * scale,
           (bottom + height) * scale
end

local function AttachEditModeSnapAPI(frame)
    if not frame then return end
    frame.snappedFrames = frame.snappedFrames or {}
    if CanUseEditModeSnap() then
        for _, name in ipairs(EDIT_MODE_SNAP_METHODS) do
            if EditModeSystemMixin[name] then
                frame[name] = EditModeSystemMixin[name]
            end
        end
    end
    frame.GetScaledSelectionSides = GetScaledSelectionSidesSafe
end

local function HasMagneticPreviewAPI(frame)
    return frame and frame.GetFrameMagneticEligibility
               and frame.GetScaledSelectionSides
end

local function BakeFrameToUIParent(deltaX, deltaY)
    if not vitalFrameFrame then return end

    local ok, offsetX, offsetY = pcall(function()
        local top = tonumber(vitalFrameFrame:GetTop())
        local left = tonumber(vitalFrameFrame:GetLeft())
        local scale = tonumber(vitalFrameFrame:GetScale()) or 1
        local parentHeight = tonumber(UIParent:GetHeight()) or 0
        if not top or not left then return nil end
        return left + (deltaX or 0),
               -((parentHeight - top * scale) / scale) + (deltaY or 0)
    end)
    if not ok or not offsetX then return end

    if vitalFrameFrame.ClearFrameSnap then vitalFrameFrame:ClearFrameSnap() end
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offsetX, offsetY)
    LockFrameToAddonPosition(vitalFrameFrame)
    SaveFramePositionFromOffsets(offsetX, offsetY)
end

local function ProcessNudgeKey(key)
    if not IsEditModeOpen() then return end

    local amount = IsShiftKeyDown() and 10 or 1
    local deltaX, deltaY = 0, 0
    if key == "UP" then
        deltaY = amount
    elseif key == "DOWN" then
        deltaY = -amount
    elseif key == "LEFT" then
        deltaX = -amount
    elseif key == "RIGHT" then
        deltaX = amount
    else
        return
    end

    if layoutFocus == "skills" then
        if UI.NudgeSkillsFrame then UI.NudgeSkillsFrame(deltaX, deltaY) end
        return
    end

    if not vitalFrameFrame or layoutFocus ~= "main" then return end

    if vitalFrameFrame.BreakSnappedFrames then
        vitalFrameFrame:BreakSnappedFrames()
    end
    BakeFrameToUIParent(deltaX, deltaY)
    SaveFramePosition()
end

local function OnEditModeNudgeKey(self, key)
    local isArrow = key == "UP" or key == "DOWN" or key == "LEFT" or
                        key == "RIGHT"
    local handle = layoutFocus ~= nil and IsEditModeOpen() and isArrow
    if self.SetPropagateKeyboardInput then
        pcall(self.SetPropagateKeyboardInput, self, not handle)
    end
    if handle then ProcessNudgeKey(key) end
end

local function UpdateNudgeKeyboard()
    local mainActive = layoutFocus == "main" and IsEditModeOpen() or false
    local skillsActive = layoutFocus == "skills" and IsEditModeOpen() or false
    if vitalFrameFrame then
        vitalFrameFrame:EnableKeyboard(mainActive)
    end
    if vitalFrameSettingsPanel then
        vitalFrameSettingsPanel:EnableKeyboard(mainActive)
    end
    if UI.SetSkillsKeyboardEnabled then
        UI.SetSkillsKeyboardEnabled(skillsActive)
    end
end

local function UpdateMagnetismRegistration()
    if not vitalFrameFrame then return end
    AttachEditModeSnapAPI(vitalFrameFrame)
    -- Do not RegisterFrame. Other Edit Mode systems call methods on snap
    -- targets that a custom frame does not have (archaeology bar error).
    if EditModeMagnetismManager then
        EditModeMagnetismManager:UnregisterFrame(vitalFrameFrame)
    end
end

local function BeginEditModeDrag(frame)
    AttachEditModeSnapAPI(frame)
    if vitalFrameFrame and vitalFrameFrame.BreakSnappedFrames then
        vitalFrameFrame:BreakSnappedFrames()
    end
    if vitalFrameFrame and vitalFrameFrame.ClearFrameSnap then
        vitalFrameFrame:ClearFrameSnap()
    end
    frame:StartMoving()
    LockFrameToAddonPosition(frame)
    if HasMagneticPreviewAPI(frame) and EditModeManagerFrame and
        EditModeManagerFrame.SetSnapPreviewFrame then
        EditModeManagerFrame:SetSnapPreviewFrame(frame)
    end
end

local function FinishEditModeDrag(frame)
    if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
        EditModeManagerFrame:ClearSnapPreviewFrame()
    end
    frame:StopMovingOrSizing()
    if HasMagneticPreviewAPI(frame) and EditModeManagerFrame and
        EditModeManagerFrame.IsSnapEnabled and
        EditModeManagerFrame:IsSnapEnabled() then
        EditModeMagnetismManager:ApplyMagnetism(frame)
    end
    BakeFrameToUIParent(0, 0)
    LockFrameToAddonPosition(frame)
    SaveFramePosition()
end

UpdateProgressBarLayout = function()
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end

    local borderInset = 4
    local bottomPadding = (vitalFrameFrame.ProgressBottomPadding or 0) +
                              borderInset
    local usableWidth = vitalFrameFrame:GetWidth() - (borderInset * 2)
    local frameHeight = vitalFrameFrame:GetHeight()

    local enabledKeys = GetEnabledBarKeys()
    local barCount = #enabledKeys

    for _, key in ipairs(BAR_ORDER) do
        local bar = vitalFrameFrame.ProgressBarsByKey[key]
        if bar then
            if ShouldShowBar(key) then
                bar:Show()
            else
                bar:Hide()
            end
        end
    end

    local firstVisibleBar = nil
    if barCount >= 1 then
        local barsHeight = 0
        for _, key in ipairs(BAR_ORDER) do
            if ShouldShowBar(key) then
                barsHeight = barsHeight + GetBarHeight(key)
            end
        end

        local topPadding = frameHeight - bottomPadding - barsHeight
        if topPadding < borderInset then topPadding = borderInset end

        local previousBar = nil
        for _, key in ipairs(BAR_ORDER) do
            local bar = vitalFrameFrame.ProgressBarsByKey[key]
            if bar and ShouldShowBar(key) then
                bar:ClearAllPoints()
                local barHeight = GetBarHeight(key)
                bar:SetSize(usableWidth, barHeight)
                if not previousBar then
                    firstVisibleBar = bar
                    bar:SetPoint("TOP", vitalFrameFrame, "TOP", 0, -topPadding)
                else
                    bar:SetPoint("TOP", previousBar, "BOTTOM", 0, 0)
                end
                previousBar = bar
            end
        end
    end

    if vitalFrameFrame.BarRegion then
        if firstVisibleBar then
            vitalFrameFrame.BarRegion:ClearAllPoints()
            vitalFrameFrame.BarRegion:SetPoint("TOPLEFT", firstVisibleBar,
                                             "TOPLEFT", 0, 0)
            vitalFrameFrame.BarRegion:SetPoint("BOTTOMRIGHT", vitalFrameFrame,
                                             "BOTTOMRIGHT", -borderInset,
                                             borderInset)
            vitalFrameFrame.BarRegion:Show()
        else
            vitalFrameFrame.BarRegion:Hide()
        end
    end

    UpdateHeaderLayout()

    if vitalFrameFrame.LevelText and vitalFrameFrame.NameText then
        local nameBottom = GetHeaderNameBottom()
        local frameBottom = vitalFrameFrame:GetBottom()
        local barTop = firstVisibleBar and firstVisibleBar:GetTop()
        if not barTop and frameBottom then
            barTop = frameBottom + bottomPadding
        end

        if nameBottom and barTop and frameBottom then
            local availableHeight = math.floor(
                                        (nameBottom - barTop) -
                                            (LEVEL_TEXT_VERTICAL_PADDING * 2))
            if availableHeight < NAME_FIRST_FONT_SIZE then
                availableHeight = NAME_FIRST_FONT_SIZE
            end

            local fontPath, _, flags = vitalFrameFrame.LevelText:GetFont()
            local size = math.max(NAME_FIRST_FONT_SIZE, availableHeight)
            vitalFrameFrame.LevelText:SetFont(fontPath or "Fonts\\FRIZQT__.TTF",
                                            size, flags)

            local textHeight = vitalFrameFrame.LevelText:GetStringHeight() or size
            while size > NAME_FIRST_FONT_SIZE and textHeight > availableHeight do
                size = size - 1
                vitalFrameFrame.LevelText:SetFont(fontPath or
                                                    "Fonts\\FRIZQT__.TTF", size,
                                                flags)
                textHeight = vitalFrameFrame.LevelText:GetStringHeight() or size
            end

            local topY = nameBottom - LEVEL_TEXT_VERTICAL_PADDING
            local bottomY = barTop + LEVEL_TEXT_VERTICAL_PADDING
            local midY = (topY + bottomY) / 2

            vitalFrameFrame.LevelText:ClearAllPoints()
            vitalFrameFrame.LevelText:SetPoint("CENTER", vitalFrameFrame, "BOTTOM",
                                             0, midY - frameBottom)
        elseif not levelLayoutRetryPending then
            -- GetBottom/GetTop are nil until the next frame after /reload.
            levelLayoutRetryPending = true
            Compat.After(0, function()
                levelLayoutRetryPending = false
                if vitalFrameFrame then UpdateProgressBarLayout() end
            end)
        end
    end

end

local function ApplyFrameSize(width, height)
    if not vitalFrameFrame then return end

    local wMinSize, wMaxSize = 200, 600
    local hMinSize, hMaxSize = 200, 300
    local w = math.max(wMinSize, math.min(wMaxSize, math.floor(
                                              width or vitalFrameFrame:GetWidth())))
    local h = math.max(hMinSize, math.min(hMaxSize, math.floor(
                                              height or
                                                  vitalFrameFrame:GetHeight())))

    vitalFrameFrame:SetSize(w, h)
    UpdateProgressBarLayout()
    SaveFrameSize(w, h)
end

local function ClampSizeValue(value, minSize, maxSize)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n + 0.5)
    if n < minSize then n = minSize end
    if n > maxSize then n = maxSize end
    return n
end

local function CreateSizeSlider(name, parent)
    local ok, control = pcall(CreateFrame, "Frame", name, parent,
                              "MinimalSliderWithSteppersTemplate")
    if ok and control and control.Slider then
        control:SetSize(220, 32)
        return control, control.Slider
    end

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetSize(200, 17)
    slider:SetOrientation("HORIZONTAL")
    if slider.SetObeyStepOnDrag then pcall(slider.SetObeyStepOnDrag, slider, true) end
    local text = _G[name .. "Text"]
    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    if text then text:SetText("") end
    if low then low:SetText("") end
    if high then high:SetText("") end
    return slider, slider
end

local function SetSelectionVisual(isSelected)
    if not vitalFrameSelection or not vitalFrameSelection.Background then return end

    if isSelected then
        vitalFrameSelection.Background:SetTexture(
            "Interface/AddOns/VitalFrame/Art/EditModeSelected")
        vitalFrameSelection.Background:SetAlpha(1)
    else
        vitalFrameSelection.Background:SetTexture(
            "Interface/AddOns/VitalFrame/Art/EditModeHighlighted")
        vitalFrameSelection.Background:SetAlpha(selectionHovered and 1 or 0.62)
    end
end

local function GetSettingsPanelSavedPosition()
    local db = GetDB()
    if not db or not db.global or not db.global.settingsPanel then return nil end
    local saved = db.global.settingsPanel
    if saved.hasCustomPosition ~= true then return nil end
    return saved
end

local function SaveSettingsPanelPosition()
    local db = GetDB()
    if not db or not vitalFrameSettingsPanel then return end
    db.global = db.global or {}
    db.global.settingsPanel = db.global.settingsPanel or {}

    local point, _, _, x, y = vitalFrameSettingsPanel:GetPoint(1)
    db.global.settingsPanel.point = point or "CENTER"
    db.global.settingsPanel.x = x or 0
    db.global.settingsPanel.y = y or 0
    db.global.settingsPanel.hasCustomPosition = true
end

local function AnchorSettingsPanel()
    if not vitalFrameSettingsPanel then return end
    vitalFrameSettingsPanel:ClearAllPoints()

    local saved = GetSettingsPanelSavedPosition()
    if saved then
        vitalFrameSettingsPanel:SetPoint(saved.point or "CENTER", UIParent,
                                       saved.point or "CENTER", saved.x or 0,
                                       saved.y or 0)
        return
    end

    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        vitalFrameSettingsPanel:SetPoint("TOPRIGHT", EditModeManagerFrame,
                                       "TOPLEFT", -12, -8)
    elseif vitalFrameFrame then
        vitalFrameSettingsPanel:SetPoint("TOPLEFT", vitalFrameFrame, "TOPRIGHT", 12,
                                       0)
    end
end

local function UpdateSettingsPanelVisibility()
    if not vitalFrameSettingsPanel or not vitalFrameFrame then return end

    local editModeShown = IsEditModeOpen()
    local shouldShow = editModeShown and layoutFocus == "main" and
                           vitalFrameFrame:IsShown()
    if shouldShow then AnchorSettingsPanel() end

    vitalFrameSettingsPanel:SetShown(shouldShow)

    if shouldShow then
        local currentWidth =
            ClampSizeValue(vitalFrameFrame:GetWidth(), 200, 600) or 200
        local currentHeight =
            ClampSizeValue(vitalFrameFrame:GetHeight(), 200, 300) or 200
        if vitalFrameSettingsPanel.widthSlider then
            vitalFrameSettingsPanel.widthSlider:SetValue(currentWidth)
        end
        if vitalFrameSettingsPanel.widthValueText then
            vitalFrameSettingsPanel.widthValueText:SetText(tostring(currentWidth))
        end
        if vitalFrameSettingsPanel.heightSlider then
            vitalFrameSettingsPanel.heightSlider:SetValue(currentHeight)
        end
        if vitalFrameSettingsPanel.heightValueText then
            vitalFrameSettingsPanel.heightValueText:SetText(
                tostring(currentHeight))
        end
    end

    if vitalFrameSettingsPanel.barChecks then
        for key, check in pairs(vitalFrameSettingsPanel.barChecks) do
            check:SetChecked(IsBarEnabled(key))
        end
    end

    if vitalFrameSettingsPanel.xpFillUseClassColorCheck then
        vitalFrameSettingsPanel.xpFillUseClassColorCheck:SetChecked(
            GetXPFillOption("useClassColor"))
        vitalFrameSettingsPanel.xpFillUseClassColorCheck:SetEnabled(
            IsBarEnabled("xpFill"))
    end

    if vitalFrameSettingsPanel.hideBlizzardWatchBarCheck then
        vitalFrameSettingsPanel.hideBlizzardWatchBarCheck:SetChecked(
            GetHideBlizzardWatchBar())
    end

    if vitalFrameSettingsPanel.xpFillHideWhenMaxLevelCheck then
        vitalFrameSettingsPanel.xpFillHideWhenMaxLevelCheck:SetChecked(
            GetXPFillOption("hideWhenMaxLevel"))
        vitalFrameSettingsPanel.xpFillHideWhenMaxLevelCheck:SetEnabled(
            IsBarEnabled("xpFill"))
    end

    if vitalFrameSettingsPanel.reputationAutoSwitchCheck then
        vitalFrameSettingsPanel.reputationAutoSwitchCheck:SetChecked(
            GetReputationAutoSwitch())
        vitalFrameSettingsPanel.reputationAutoSwitchCheck:SetEnabled(
            IsBarEnabled("reputation"))
    end

    if vitalFrameSettingsPanel.autoScaleBarsCheck then
        vitalFrameSettingsPanel.autoScaleBarsCheck:SetChecked(GetAutoScaleBars())
    end

    if vitalFrameSettingsPanel.streamerModeCheck then
        vitalFrameSettingsPanel.streamerModeCheck:SetChecked(GetStreamerMode())
    end

    if vitalFrameSettingsPanel.showSkillsFrameCheck then
        local skillsEnabled = true
        if UI.GetSkillsFrameEnabled then
            skillsEnabled = UI.GetSkillsFrameEnabled()
        end
        vitalFrameSettingsPanel.showSkillsFrameCheck:SetChecked(skillsEnabled)
    end

    RefreshThemeChecks()

    if UI.RefreshSkillsSettings then UI.RefreshSkillsSettings() end

    UpdateNudgeKeyboard()
    UpdateMagnetismRegistration()
end

SetLayoutFocus = function(which)
    if which ~= "main" and which ~= "skills" then
        which = nil
    end
    layoutFocus = which
    selectionFocused = which == "main"
    if which == "main" then
        selectionHovered = true
        if vitalFrameSelection and vitalFrameSelection.EditHint then
            vitalFrameSelection.EditHint:Hide()
        end
    else
        selectionHovered = false
        if vitalFrameSelection and vitalFrameSelection.EditHint then
            vitalFrameSelection.EditHint:Hide()
        end
    end
    SetSelectionVisual(selectionFocused)
    if UI.SetSkillsFocusVisual then
        UI.SetSkillsFocusVisual(which == "skills")
    end
    UpdateSettingsPanelVisibility()
    if UI.UpdateSkillsSettingsVisibility then
        UI.UpdateSkillsSettingsVisibility()
    end
    UpdateNudgeKeyboard()
end

UpdateEditModeDragState = function()
    if not vitalFrameFrame then return end
    local editModeShown = IsEditModeOpen()
    if not editModeShown then
        layoutFocus = nil
        selectionFocused = false
        selectionHovered = false
    else
        selectionFocused = layoutFocus == "main"
    end
    vitalFrameFrame:EnableMouse(editModeShown)
    if vitalFrameSelection then
        SetSelectionVisual(selectionFocused)
        vitalFrameSelection:SetShown(editModeShown and vitalFrameFrame:IsShown())
    end
    UpdateSettingsPanelVisibility()
    UpdateNudgeKeyboard()
    UpdateMagnetismRegistration()
    if UI.UpdateSkillsFrameEditMode then UI.UpdateSkillsFrameEditMode() end
    if UI.UpdateSkillsSettingsVisibility then
        UI.UpdateSkillsSettingsVisibility()
    end
    ApplyFrameTheme()
end

local function SetVitalFrameShown(shouldShow)
    if not vitalFrameFrame then return end

    if shouldShow then
        vitalFrameFrame:Show()
    else
        vitalFrameFrame:Hide()
    end

    local db = GetDB()
    if db and db.profile and db.profile.frame then
        db.profile.frame.shown = shouldShow and true or false
    end
    UpdateEditModeDragState()
    ApplyBlizzardWatchBarVisibility()
end

local function ApplySavedFrameLayout()
    if not vitalFrameFrame then return end
    local db = GetDB()
    local frameSettings = db and db.profile and db.profile.frame
    if not frameSettings then return end

    local width = tonumber(frameSettings.width) or 200
    local height = tonumber(frameSettings.height) or 200
    local point = frameSettings.point or "CENTER"
    local x = tonumber(frameSettings.x) or 0
    local y = tonumber(frameSettings.y) or 0

    LockFrameToAddonPosition(vitalFrameFrame)
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint(point, UIParent, point, x, y)
    vitalFrameFrame:SetSize(width, height)
    LockFrameToAddonPosition(vitalFrameFrame)
    UpdateProgressBarLayout()
    if UI.ApplySavedSkillsFrameLayout then UI.ApplySavedSkillsFrameLayout() end
end

local layoutRestoreToken = 0
local function ScheduleApplySavedFrameLayout()
    ApplySavedFrameLayout()
    if not Compat.After then return end
    layoutRestoreToken = layoutRestoreToken + 1
    local token = layoutRestoreToken
    local function retry()
        if token == layoutRestoreToken then ApplySavedFrameLayout() end
    end
    Compat.After(0, retry)
    Compat.After(0.25, retry)
    Compat.After(1, retry)
end

local function ResetToDefaults()
    if not vitalFrameFrame then return end
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint("CENTER")
    ApplyFrameSize(200, 200)
    SaveFramePosition()
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.widthValueText then
        vitalFrameSettingsPanel.widthValueText:SetText("200")
    end
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.heightValueText then
        vitalFrameSettingsPanel.heightValueText:SetText("200")
    end
    local db = GetDB()
    if db and db.profile then db.profile.theme = "auto" end
    ApplyFrameTheme()
end

local function CreateVitalFrame()
    if vitalFrameFrame then return end

    local db = GetDB()
    local frameSettings = db and db.profile and db.profile.frame
    local frameWidth = frameSettings and frameSettings.width or 200
    local frameHeight = frameSettings and frameSettings.height or 200

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(frameWidth, frameHeight)
    LockFrameToAddonPosition(frame)

    if frameSettings then
        frame:SetPoint(frameSettings.point or "CENTER", UIParent,
                       frameSettings.point or "CENTER", frameSettings.x or 0,
                       frameSettings.y or 0)
    else
        frame:SetPoint("CENTER")
    end

    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(1)
    frame:SetAlpha(1)

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.5)
    frame:SetBackdropBorderColor(0.83, 0.66, 0.27, 1)

    local selection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    selection:SetAllPoints(frame)
    selection:SetFrameLevel(frame:GetFrameLevel() + 10)
    selection:EnableMouse(false)

    selection.Background = selection:CreateTexture(nil, "BACKGROUND")
    selection.Background:SetTexture(
        "Interface/AddOns/VitalFrame/Art/EditModeHighlighted")
    if selection.Background.SetTextureSliceMargins then
        pcall(selection.Background.SetTextureSliceMargins,
              selection.Background, 16, 16, 16, 16)
    end
    if selection.Background.SetTextureSliceMode then
        pcall(selection.Background.SetTextureSliceMode, selection.Background, 0)
    end
    selection.Background:SetPoint("TOPLEFT", selection, "TOPLEFT", -8, 8)
    selection.Background:SetPoint("BOTTOMRIGHT", selection, "BOTTOMRIGHT", 8, -8)
    selection:Hide()

    selection.EditHint = selection:CreateFontString(nil, "OVERLAY",
                                                    "GameFontHighlightLarge")
    selection.EditHint:SetPoint("CENTER", selection, "CENTER", 0, 0)
    selection.EditHint:SetWidth(176)
    selection.EditHint:SetJustifyH("CENTER")
    selection.EditHint:SetWordWrap(false)

    local hintFont = select(1, selection.EditHint:GetFont())
    selection.EditHint:SetFont(hintFont or "Fonts\\FRIZQT__.TTF", 26, nil)
    selection.EditHint:SetText(L["Click To Edit"])
    selection.EditHint:SetTextColor(1, 1, 1, 1)
    selection.EditHint:Hide()
    frame.Selection = selection
    AttachEditModeSnapAPI(frame)

    vitalFrameSelection = selection

    local settingsPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    settingsPanel:SetSize(360, 660)
    settingsPanel:SetFrameStrata("DIALOG")
    settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 20)
    settingsPanel:SetToplevel(true)
    settingsPanel:SetMovable(true)
    settingsPanel:EnableMouse(true)
    settingsPanel:RegisterForDrag("LeftButton")
    settingsPanel:SetClampedToScreen(true)
    settingsPanel:SetScale(1)
    settingsPanel:Hide()

    local borderOk, settingsPanelBorder = pcall(CreateFrame, "Frame", nil,
                                                settingsPanel,
                                                "DialogBorderTranslucentTemplate")
    if borderOk and settingsPanelBorder then
        settingsPanelBorder:SetAllPoints(settingsPanel)
    else
        settingsPanel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
        settingsPanel:SetBackdropColor(0, 0, 0, 0.85)
    end
    settingsPanel:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsEditModeOpen() then
            suppressNextFocusClear = true
            SetLayoutFocus("main")
        end
    end)
    settingsPanel:SetScript("OnDragStart", function(self)
        if IsEditModeOpen() then
            suppressNextFocusClear = true
            SetLayoutFocus("main")
            self:StartMoving()
        end
    end)
    settingsPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSettingsPanelPosition()
    end)
    settingsPanel:SetScript("OnKeyDown", OnEditModeNudgeKey)

    local panelTitle = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightLarge")
    panelTitle:SetPoint("TOP", settingsPanel, "TOP", 0, -15)
    panelTitle:SetText(L["Vital Frame Options"])

    local panelCloseButton = CreateFrame("Button", nil, settingsPanel,
                                         "UIPanelCloseButton")
    panelCloseButton:SetPoint("TOPRIGHT")
    panelCloseButton:SetScript("OnClick", function()
        SetLayoutFocus(nil)
    end)

    local widthLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    widthLabel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, -42)
    widthLabel:SetJustifyH("LEFT")
    widthLabel:SetText(L["Width"])

    local widthControl, widthSlider = CreateSizeSlider("VitalFrameWidthSlider",
                                                       settingsPanel)
    widthControl:SetPoint("LEFT", widthLabel, "LEFT", 60, 0)
    widthSlider:SetMinMaxValues(200, 600)
    widthSlider:SetValueStep(10)
    if widthSlider.SetObeyStepOnDrag then
        pcall(widthSlider.SetObeyStepOnDrag, widthSlider, true)
    end

    if widthControl.MinText then
        widthControl.MinText:Hide()
        widthControl.MinText:SetText("200")
    end
    if widthControl.MaxText then
        widthControl.MaxText:Hide()
        widthControl.MaxText:SetText("600")
    end
    if widthControl.TopText then widthControl.TopText:Hide() end
    if widthControl.LeftText then widthControl.LeftText:Hide() end
    if widthControl.RightText then widthControl.RightText:Hide() end

    local widthValueText = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                          "GameFontNormal")
    widthValueText:SetPoint("LEFT", widthControl, "RIGHT", 8, 0)
    widthValueText:SetJustifyH("LEFT")
    widthValueText:SetText(tostring(frameWidth))

    widthSlider:SetScript("OnValueChanged", function(_, value)
        local v = ClampSizeValue(value, 200, 600)
        if not vitalFrameFrame or not v then return end
        ApplyFrameSize(v, vitalFrameFrame:GetHeight())
        if widthValueText then widthValueText:SetText(tostring(v)) end
    end)

    settingsPanel.widthSlider = widthSlider

    vitalFrameSettingsPanel = settingsPanel
    AnchorSettingsPanel()
    settingsPanel.widthSlider:SetValue(frameWidth)
    settingsPanel.widthValueText = widthValueText
    settingsPanel.widthValueText:SetText(tostring(frameWidth))

    local heightLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                       "GameFontHighlightMedium")
    heightLabel:SetPoint("TOPLEFT", widthLabel, "BOTTOMLEFT", 0, -20)
    heightLabel:SetJustifyH("LEFT")
    heightLabel:SetText(L["Height"])

    local heightControl, heightSlider =
        CreateSizeSlider("VitalFrameHeightSlider", settingsPanel)
    heightControl:SetPoint("LEFT", heightLabel, "LEFT", 60, 0)
    heightSlider:SetMinMaxValues(200, 300)
    heightSlider:SetValueStep(10)
    if heightSlider.SetObeyStepOnDrag then
        pcall(heightSlider.SetObeyStepOnDrag, heightSlider, true)
    end

    if heightControl.MinText then
        heightControl.MinText:Hide()
        heightControl.MinText:SetText("200")
    end
    if heightControl.MaxText then
        heightControl.MaxText:Hide()
        heightControl.MaxText:SetText("300")
    end
    if heightControl.TopText then heightControl.TopText:Hide() end
    if heightControl.LeftText then heightControl.LeftText:Hide() end
    if heightControl.RightText then heightControl.RightText:Hide() end

    local heightValueText = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                           "GameFontNormal")
    heightValueText:SetPoint("LEFT", heightControl, "RIGHT", 8, 0)
    heightValueText:SetJustifyH("LEFT")
    heightValueText:SetText(tostring(frameHeight))

    heightSlider:SetScript("OnValueChanged", function(_, value)
        local v = ClampSizeValue(value, 200, 300)
        if not vitalFrameFrame or not v then return end
        if heightValueText then heightValueText:SetText(tostring(v)) end
        ApplyFrameSize(vitalFrameFrame:GetWidth(), v)
    end)

    settingsPanel.heightSlider = heightSlider
    settingsPanel.heightValueText = heightValueText
    settingsPanel.heightValueText:SetText(tostring(frameHeight))

    local autoScaleBarsCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                           "UICheckButtonTemplate")
    autoScaleBarsCheck:SetPoint("TOPLEFT", heightLabel, "BOTTOMLEFT", 10, -8)

    local autoScaleBarsLabel = autoScaleBarsCheck:CreateFontString(nil,
                                                                   "OVERLAY",
                                                                   "GameFontHighlight")
    autoScaleBarsLabel:SetPoint("LEFT", autoScaleBarsCheck, "RIGHT", 10, 1)
    autoScaleBarsLabel:SetText(L["Auto Scale Bars"])

    autoScaleBarsCheck:SetChecked(GetAutoScaleBars())
    settingsPanel.autoScaleBarsCheck = autoScaleBarsCheck
    autoScaleBarsCheck:SetScript("OnClick", function(self)
        SetAutoScaleBars(self:GetChecked() == true)
    end)

    local barsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                     "GameFontHighlightMedium")
    barsLabel:SetPoint("TOPLEFT", autoScaleBarsCheck, "BOTTOMLEFT", -10, -8)
    barsLabel:SetJustifyH("LEFT")
    barsLabel:SetText(L["Bars"])

    settingsPanel.barChecks = settingsPanel.barChecks or {}
    local prevCheck
    local alignAfterXpSubsets = false
    local checkGap = 0
    for _, key in ipairs(GetSettingsBarOrder()) do
        local def = BAR_DEFS[key]
        local check = CreateFrame("CheckButton", nil, settingsPanel,
                                  "UICheckButtonTemplate")
        if not prevCheck then
            check:SetPoint("TOPLEFT", barsLabel, "BOTTOMLEFT", 10, checkGap)
        elseif alignAfterXpSubsets then
            check:SetPoint("TOPLEFT", prevCheck, "BOTTOMLEFT", -16, checkGap)
            alignAfterXpSubsets = false
        else
            check:SetPoint("TOPLEFT", prevCheck, "BOTTOMLEFT", 0, checkGap)
        end

        local label =
            check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 10, 1)
        label:SetText(def.label or key)

        check:SetChecked(IsBarEnabled(key))
        check:SetScript("OnClick", function(self)
            SetBarEnabled(key, self:GetChecked() == true)
        end)

        settingsPanel.barChecks[key] = check
        if key == "xpFill" then
            local useClassColorCheck = CreateFrame("CheckButton", nil,
                                                   settingsPanel,
                                                   "UICheckButtonTemplate")
            useClassColorCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 16,
                                        checkGap)

            local useClassColorLabel = useClassColorCheck:CreateFontString(nil,
                                                                           "OVERLAY",
                                                                           "GameFontHighlight")
            useClassColorLabel:SetPoint("LEFT", useClassColorCheck, "RIGHT", 10,
                                        1)
            useClassColorLabel:SetText(L["Use Class Color"])

            useClassColorCheck:SetChecked(GetXPFillOption("useClassColor"))
            useClassColorCheck:SetEnabled(IsBarEnabled("xpFill"))
            settingsPanel.xpFillUseClassColorCheck = useClassColorCheck
            useClassColorCheck:SetScript("OnClick", function(self)
                SetXPFillOption("useClassColor", self:GetChecked() == true)
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            local hideWhenMaxLevelCheck = CreateFrame("CheckButton", nil,
                                                      settingsPanel,
                                                      "UICheckButtonTemplate")
            hideWhenMaxLevelCheck:SetPoint("TOPLEFT", useClassColorCheck,
                                           "BOTTOMLEFT", 0, checkGap)

            local hideWhenMaxLevelLabel =
                hideWhenMaxLevelCheck:CreateFontString(nil, "OVERLAY",
                                                       "GameFontHighlight")
            hideWhenMaxLevelLabel:SetPoint("LEFT", hideWhenMaxLevelCheck,
                                           "RIGHT", 10, 1)
            hideWhenMaxLevelLabel:SetText(L["Hide When Max Level"])

            hideWhenMaxLevelCheck:SetChecked(GetXPFillOption("hideWhenMaxLevel"))
            hideWhenMaxLevelCheck:SetEnabled(IsBarEnabled("xpFill"))
            settingsPanel.xpFillHideWhenMaxLevelCheck = hideWhenMaxLevelCheck
            hideWhenMaxLevelCheck:SetScript("OnClick", function(self)
                SetXPFillOption("hideWhenMaxLevel", self:GetChecked() == true)
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            local xpRemainingCheck = CreateFrame("CheckButton", nil,
                                                 settingsPanel,
                                                 "UICheckButtonTemplate")
            xpRemainingCheck:SetPoint("TOPLEFT", hideWhenMaxLevelCheck,
                                      "BOTTOMLEFT", 0, checkGap)

            local xpRemainingLabel = xpRemainingCheck:CreateFontString(nil,
                                                                       "OVERLAY",
                                                                       "GameFontHighlight")
            xpRemainingLabel:SetPoint("LEFT", xpRemainingCheck, "RIGHT", 10, 1)
            xpRemainingLabel:SetText(L["XP Remaining"])

            xpRemainingCheck:SetChecked(IsBarEnabled("xpRemaining"))
            settingsPanel.barChecks.xpRemaining = xpRemainingCheck
            xpRemainingCheck:SetScript("OnClick", function(self)
                SetBarEnabled("xpRemaining", self:GetChecked() == true)
            end)

            check:SetScript("OnClick", function(self)
                local enabled = self:GetChecked() == true
                SetBarEnabled("xpFill", enabled)
                useClassColorCheck:SetEnabled(enabled)
                hideWhenMaxLevelCheck:SetEnabled(enabled)
            end)

            prevCheck = xpRemainingCheck
            alignAfterXpSubsets = true
        elseif key == "reputation" then
            local autoSwitchCheck = CreateFrame("CheckButton", nil,
                                                settingsPanel,
                                                "UICheckButtonTemplate")
            autoSwitchCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 16,
                                     checkGap)

            local autoSwitchLabel = autoSwitchCheck:CreateFontString(nil,
                                                                     "OVERLAY",
                                                                     "GameFontHighlight")
            autoSwitchLabel:SetPoint("LEFT", autoSwitchCheck, "RIGHT", 10, 1)
            autoSwitchLabel:SetText(L["Auto Switch to Last Earned"])

            autoSwitchCheck:SetChecked(GetReputationAutoSwitch())
            autoSwitchCheck:SetEnabled(IsBarEnabled("reputation"))
            settingsPanel.reputationAutoSwitchCheck = autoSwitchCheck
            autoSwitchCheck:SetScript("OnClick", function(self)
                SetReputationAutoSwitch(self:GetChecked() == true)
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            check:SetScript("OnClick", function(self)
                local enabled = self:GetChecked() == true
                SetBarEnabled("reputation", enabled)
                autoSwitchCheck:SetEnabled(enabled)
            end)

            prevCheck = autoSwitchCheck
            alignAfterXpSubsets = true
        else
            prevCheck = check
        end
    end

    local craftingCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                      "UICheckButtonTemplate")
    if prevCheck then
        local craftX = alignAfterXpSubsets and -16 or 0
        craftingCheck:SetPoint("TOPLEFT", prevCheck, "BOTTOMLEFT", craftX,
                               checkGap)
        alignAfterXpSubsets = false
    else
        craftingCheck:SetPoint("TOPLEFT", barsLabel, "BOTTOMLEFT", 10, -2)
    end
    local craftingLabel = craftingCheck:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    craftingLabel:SetPoint("LEFT", craftingCheck, "RIGHT", 10, 1)
    craftingLabel:SetText(L["Crafting Skills"])
    craftingCheck:SetChecked(IsBarEnabled("crafting"))
    craftingCheck:SetScript("OnClick", function(self)
        SetBarEnabled("crafting", self:GetChecked() == true)
    end)
    settingsPanel.barChecks.crafting = craftingCheck
    prevCheck = craftingCheck

    local optionsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                        "GameFontHighlightMedium")
    optionsLabel:SetPoint("TOPLEFT", craftingCheck, "BOTTOMLEFT", -10, -8)
    optionsLabel:SetJustifyH("LEFT")
    optionsLabel:SetText(L["Options"])

    local hideBlizzardWatchBarCheck = CreateFrame("CheckButton", nil,
                                                  settingsPanel,
                                                  "UICheckButtonTemplate")
    hideBlizzardWatchBarCheck:SetPoint("TOPLEFT", optionsLabel, "BOTTOMLEFT",
                                       10, checkGap)

    local hideBlizzardWatchBarLabel = hideBlizzardWatchBarCheck:CreateFontString(
                                          nil, "OVERLAY", "GameFontHighlight")
    hideBlizzardWatchBarLabel:SetPoint("LEFT", hideBlizzardWatchBarCheck,
                                       "RIGHT", 10, 1)
    hideBlizzardWatchBarLabel:SetText(L["Hide Default Watch Bar"])

    hideBlizzardWatchBarCheck:SetChecked(GetHideBlizzardWatchBar())
    settingsPanel.hideBlizzardWatchBarCheck = hideBlizzardWatchBarCheck
    hideBlizzardWatchBarCheck:SetScript("OnClick", function(self)
        SetHideBlizzardWatchBar(self:GetChecked() == true)
        ApplyBlizzardWatchBarVisibility()
    end)

    local streamerModeCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                          "UICheckButtonTemplate")
    streamerModeCheck:SetPoint("TOPLEFT", hideBlizzardWatchBarCheck,
                               "BOTTOMLEFT", 0, checkGap)
    local streamerModeLabel = streamerModeCheck:CreateFontString(nil, "OVERLAY",
                                                                 "GameFontHighlight")
    streamerModeLabel:SetPoint("LEFT", streamerModeCheck, "RIGHT", 10, 1)
    streamerModeLabel:SetText(L["Streamer Mode"])
    streamerModeCheck:SetChecked(GetStreamerMode())
    settingsPanel.streamerModeCheck = streamerModeCheck
    streamerModeCheck:SetScript("OnClick", function(self)
        SetStreamerMode(self:GetChecked() == true)
        UpdateNameText()
    end)

    if Compat.SupportsClassicSkills and Compat.SupportsClassicSkills() then
        local showSkillsFrameCheck = CreateFrame("CheckButton", nil,
                                                 settingsPanel,
                                                 "UICheckButtonTemplate")
        showSkillsFrameCheck:SetPoint("TOPLEFT", streamerModeCheck,
                                      "BOTTOMLEFT", 0, checkGap)
        local showSkillsFrameLabel = showSkillsFrameCheck:CreateFontString(nil,
                                                                           "OVERLAY",
                                                                           "GameFontHighlight")
        showSkillsFrameLabel:SetPoint("LEFT", showSkillsFrameCheck, "RIGHT", 10,
                                      1)
        showSkillsFrameLabel:SetText(L["Show Skills Frame"])
        local skillsShown = true
        if UI.GetSkillsFrameEnabled then
            skillsShown = UI.GetSkillsFrameEnabled()
        end
        showSkillsFrameCheck:SetChecked(skillsShown)
        settingsPanel.showSkillsFrameCheck = showSkillsFrameCheck
        showSkillsFrameCheck:SetScript("OnClick", function(self)
            if UI.SetSkillsFrameShown then
                UI.SetSkillsFrameShown(self:GetChecked() == true)
            end
        end)
    end

    local themeAnchor = settingsPanel.showSkillsFrameCheck or streamerModeCheck
    local themeLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    themeLabel:SetPoint("TOPLEFT", themeAnchor, "BOTTOMLEFT", -10, -8)
    themeLabel:SetJustifyH("LEFT")
    themeLabel:SetText(L["Theme"])

    local themeAutoCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                       "UICheckButtonTemplate")
    themeAutoCheck:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", 10, 0)
    local themeAutoLabel = themeAutoCheck:CreateFontString(nil, "OVERLAY",
                                                           "GameFontHighlight")
    themeAutoLabel:SetPoint("LEFT", themeAutoCheck, "RIGHT", 10, 1)
    themeAutoLabel:SetText(L["Auto"])
    settingsPanel.themeAutoCheck = themeAutoCheck
    themeAutoCheck:SetScript("OnClick", function()
        if UI.SetTheme then UI.SetTheme("auto") end
    end)

    local themeClassicCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                          "UICheckButtonTemplate")
    themeClassicCheck:SetPoint("TOPLEFT", themeAutoCheck, "BOTTOMLEFT", 0,
                               checkGap)
    local themeClassicLabel = themeClassicCheck:CreateFontString(nil, "OVERLAY",
                                                                 "GameFontHighlight")
    themeClassicLabel:SetPoint("LEFT", themeClassicCheck, "RIGHT", 10, 1)
    themeClassicLabel:SetText(L["Classic"])
    settingsPanel.themeClassicCheck = themeClassicCheck
    themeClassicCheck:SetScript("OnClick", function()
        if UI.SetTheme then UI.SetTheme("classic") end
    end)

    local themeForeverCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                          "UICheckButtonTemplate")
    themeForeverCheck:SetPoint("TOPLEFT", themeClassicCheck, "BOTTOMLEFT", 0,
                               checkGap)
    local themeForeverLabel = themeForeverCheck:CreateFontString(nil, "OVERLAY",
                                                                 "GameFontHighlight")
    themeForeverLabel:SetPoint("LEFT", themeForeverCheck, "RIGHT", 10, 1)
    themeForeverLabel:SetText(L["Forever"])
    settingsPanel.themeForeverCheck = themeForeverCheck
    themeForeverCheck:SetScript("OnClick", function()
        if UI.SetTheme then UI.SetTheme("forever") end
    end)

    local resetButton = CreateFrame("Button", nil, settingsPanel,
                                    "UIPanelButtonTemplate")
    resetButton:SetSize(200, 22)
    resetButton:SetPoint("BOTTOM", settingsPanel, "BOTTOM", 0, 15)
    resetButton:SetText(L["Reset to Defaults"])
    resetButton:SetScript("OnClick", function()
        ResetToDefaults()
        UpdateSettingsPanelVisibility()
    end)

    frame:SetScript("OnDragStart", function(self)
        if IsEditModeOpen() then
            SetLayoutFocus("main")
            BeginEditModeDrag(self)
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        FinishEditModeDrag(self)
        ApplyFrameSize(vitalFrameFrame:GetWidth(), vitalFrameFrame:GetHeight())
    end)
    frame:SetScript("OnKeyDown", OnEditModeNudgeKey)

    frame:SetScript("OnSizeChanged", function() UpdateProgressBarLayout() end)
    frame:SetScript("OnShow", function() UpdateProgressBarLayout() end)

    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsEditModeOpen() then
            SetLayoutFocus("main")
        end
    end)

    frame:SetScript("OnEnter", function()
        if IsEditModeOpen() and not selectionFocused then
            selectionHovered = true
            SetSelectionVisual(false)
            if vitalFrameSelection and vitalFrameSelection.EditHint then
                vitalFrameSelection.EditHint:Show()
            end
        end
    end)

    frame:SetScript("OnLeave", function()
        if IsEditModeOpen() and not selectionFocused then
            selectionHovered = false
            SetSelectionVisual(false)
            if vitalFrameSelection and vitalFrameSelection.EditHint then
                vitalFrameSelection.EditHint:Hide()
            end
        end
    end)

    if Compat.RegisterEvent then
        Compat.RegisterEvent(frame, "GLOBAL_MOUSE_DOWN")
    else
        frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end
    frame:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" and IsEditModeOpen() then
            if suppressNextFocusClear then
                suppressNextFocusClear = false
                return
            end
            local overPanel = vitalFrameSettingsPanel and
                                  vitalFrameSettingsPanel:IsMouseOver()
            local overSkills = UI.IsSkillsFrameMouseOver and
                                   UI.IsSkillsFrameMouseOver()
            local overSkillsPanel = UI.IsSkillsSettingsMouseOver and
                                        UI.IsSkillsSettingsMouseOver()
            if not self:IsMouseOver() and not overPanel and not overSkills and
                not overSkillsPanel then
                SetLayoutFocus(nil)
            end
        end
    end)

    local headerGroup = CreateFrame("Frame", nil, frame)
    headerGroup:SetPoint("TOP", frame, "TOP", 0, -10)
    headerGroup:SetSize(22, 22)
    frame.HeaderGroup = headerGroup
    local classIcon = frame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(22, 22)
    classIcon:SetPoint("TOPLEFT", headerGroup, "TOPLEFT", 0, 0)
    local _, classTag = UnitClass("player")
    local atlasName = classTag and GetClassAtlas and
                          GetClassAtlas(string.lower(classTag))
    if atlasName then
        classIcon:SetAtlas(atlasName)
    else
        classIcon:SetTexture(
            "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = classTag and CLASS_ICON_TCOORDS and
                           CLASS_ICON_TCOORDS[classTag]
        if coords then
            classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            classIcon:SetTexCoord(0, 1, 0, 1)
        end
    end

    local classsIconMask = frame:CreateMaskTexture(nil, "ARTWORK")
    classsIconMask:SetTexture("Interface\\COMMON\\CommonIconMask",
                              "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    classsIconMask:SetAllPoints(classIcon)
    classIcon:AddMaskTexture(classsIconMask)

    local classIconBorder = frame:CreateTexture(nil, "OVERLAY")
    classIconBorder:SetPoint("TOPLEFT", classIcon, "TOPLEFT", -2, 2)
    classIconBorder:SetPoint("BOTTOMRIGHT", classIcon, "BOTTOMRIGHT", 2, -2)
    classIconBorder:SetTexture("Interface\\COMMON\\WhiteIconFrame")

    frame.ClassIcon = classIcon

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", NAME_ICON_GAP, 0)
    nameText:SetTextColor(1, 1, 1)
    nameText:SetJustifyH("LEFT")
    nameText:SetJustifyV("TOP")
    nameText:SetWordWrap(true)
    nameText:SetNonSpaceWrap(true)

    local font, _, flags = nameText:GetFont()
    nameText:SetFont(font or "Fonts\\FRIZQT__.TTF", NAME_FIRST_FONT_SIZE, flags)
    frame.NameText = nameText

    local lastNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lastNameText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
    lastNameText:SetTextColor(1, 1, 1)
    lastNameText:SetJustifyH("LEFT")
    lastNameText:SetJustifyV("TOP")
    lastNameText:SetWordWrap(true)
    lastNameText:SetNonSpaceWrap(true)
    lastNameText:SetFont(font or "Fonts\\FRIZQT__.TTF", NAME_LAST_FONT_SIZE, flags)
    lastNameText:Hide()
    frame.LastNameText = lastNameText

    UpdateNameText()
    local levelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetPoint("TOP", nameText, "BOTTOM", 0, -5)
    levelText:SetText(tostring(UnitLevel("player") or ""))
    levelText:SetTextColor(1, 1, 1)
    levelText:SetFont(font or "Fonts\\FRIZQT__.TTF", LEVEL_BASE_FONT_SIZE, flags)
    frame.LevelText = levelText

    local barRegion = CreateFrame("Frame", nil, frame)
    barRegion:SetFrameLevel(frame:GetFrameLevel())
    barRegion:Hide()
    local barRegionBg = barRegion:CreateTexture(nil, "BACKGROUND")
    barRegionBg:SetAllPoints(true)
    barRegionBg:SetColorTexture(BAR_REGION_COLOR[1], BAR_REGION_COLOR[2],
                                BAR_REGION_COLOR[3], BAR_REGION_COLOR[4])
    local barDivider = barRegion:CreateTexture(nil, "OVERLAY")
    barDivider:SetHeight(BAR_DIVIDER_HEIGHT)
    barDivider:SetPoint("BOTTOMLEFT", barRegion, "TOPLEFT", 0, 0)
    barDivider:SetPoint("BOTTOMRIGHT", barRegion, "TOPRIGHT", 0, 0)
    barDivider:SetColorTexture(BAR_DIVIDER_COLOR[1], BAR_DIVIDER_COLOR[2],
                               BAR_DIVIDER_COLOR[3], BAR_DIVIDER_COLOR[4])
    frame.BarRegion = barRegion
    frame.BarDivider = barDivider

    local bars = {}
    local barsByKey = {}
    local topPadding = 100
    local bottomPadding = 0
    local usableWidth = frame:GetWidth() - 8
    local usableHeight = frame:GetHeight() - topPadding - bottomPadding
    local enabledCount = #GetEnabledBarKeys()
    if enabledCount < 1 then enabledCount = 1 end
    local barHeight = math.floor(usableHeight / enabledCount)

    for _, key in ipairs(BAR_ORDER) do
        local def = BAR_DEFS[key]
        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetFrameLevel(frame:GetFrameLevel() + 3)
        bar:SetSize(usableWidth, barHeight)
        bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
        bar:SetMinMaxValues(0, 1)
        if key == "petXp" and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
            bar:SetValue(1)
        else
            bar:SetValue(0)
        end

        local color = def.color
        bar:SetStatusBarColor(color[1], color[2], color[3], 1)

        local bgFrame = CreateFrame("Frame", nil, bar)
        bgFrame:SetAllPoints(bar)
        bgFrame:SetFrameLevel(bar:GetFrameLevel() - 2)

        local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(true)
        bg:SetColorTexture(BAR_TRACK_COLOR[1], BAR_TRACK_COLOR[2],
                           BAR_TRACK_COLOR[3], BAR_TRACK_COLOR[4])

        if key == "xpFill" then
            local restedFill = CreateFrame("StatusBar", nil, bar)
            restedFill:SetAllPoints(bar)
            restedFill:SetFrameLevel(bar:GetFrameLevel() - 1)
            restedFill:SetStatusBarTexture(
                "Interface\\TARGETINGFRAME\\UI-StatusBar")
            restedFill:SetMinMaxValues(0, 1)
            restedFill:SetValue(0)
            restedFill:SetStatusBarColor(0.2, 0.35, 0.95, 1)
            restedFill:Hide()
            bar.BgFill = restedFill
        end

        if CRAFTING_BAR_KEYS[key] then
            bar:SetClipsChildren(false)
        end

        local labelText = bar:CreateFontString(nil, "OVERLAY",
                                               "GameFontHighlight")
        labelText:SetPoint("CENTER", bar, "CENTER", 0, 0)
        labelText:SetJustifyH("CENTER")
        labelText:SetText("")
        bar.LabelText = labelText

        bars[#bars + 1] = bar
        barsByKey[key] = bar
    end

    frame.ProgressTopPadding = topPadding
    frame.ProgressBottomPadding = bottomPadding
    frame.ProgressBarList = bars
    frame.ProgressBarsByKey = barsByKey
    frame.ProgressBars = barsByKey
    vitalFrameFrame = frame
    UpdateProgressBarLayout()

    if frameSettings and frameSettings.shown == false then
        SetVitalFrameShown(false)
    else
        SetVitalFrameShown(true)
    end
    Compat.After(0, function()
        if vitalFrameFrame then UpdateProgressBarLayout() end
    end)

    PrintMessage(L["Frame initialized."])
    UpdateEditModeDragState()
    UpdateSettingsPanelVisibility()
    HookBlizzardWatchBar()
    ApplyBlizzardWatchBarVisibility()
    HookStreamerUnitNames()
    ApplyStreamerUnitNames()
    if UI.CreateSkillsFrame then UI.CreateSkillsFrame() end
end

local function ToggleVitalFrame()
    if not vitalFrameFrame then
        CreateVitalFrame()
        PrintMessage(L["Vital Frame Enabled."])
        return
    end

    if vitalFrameFrame:IsShown() then
        SetVitalFrameShown(false)
        PrintMessage(L["Frame hidden."])
    else
        SetVitalFrameShown(true)
        PrintMessage(L["Frame shown."])
    end
end

function UI.SetBarColor(barKey, r, g, b, a) SetBarColor(barKey, r, g, b, a) end
function UI.HasFrame() return vitalFrameFrame ~= nil end
function UI.GetMainFrameSize()
    if not vitalFrameFrame then return 200, 200 end
    return vitalFrameFrame:GetWidth(), vitalFrameFrame:GetHeight()
end
function UI.IsEditModeOpen() return IsEditModeOpen() end
function UI.LockFrameToAddonPosition(frame) LockFrameToAddonPosition(frame) end
function UI.AttachEditModeSnapAPI(frame) AttachEditModeSnapAPI(frame) end
function UI.CreateSizeSlider(name, parent) return CreateSizeSlider(name, parent) end
function UI.GetFrameBorderColor()
    return GetResolvedThemeColor()
end
function UI.SetTheme(theme) SetTheme(theme) end
function UI.FocusForSettings()
    SetLayoutFocus("main")
end
function UI.SetLayoutFocus(which) SetLayoutFocus(which) end
function UI.GetLayoutFocus() return layoutFocus end
function UI.OnEditModeNudgeKey(frame, key) OnEditModeNudgeKey(frame, key) end
function UI.SuppressNextFocusClear() suppressNextFocusClear = true end
function UI.SetVitalFrameShown(shouldShow) SetVitalFrameShown(shouldShow) end
function UI.CreateVitalFrame() CreateVitalFrame() end
function UI.ApplySavedFrameLayout() ApplySavedFrameLayout() end
function UI.ScheduleApplySavedFrameLayout() ScheduleApplySavedFrameLayout() end
function UI.UpdateEditModeDragState() UpdateEditModeDragState() end
function UI.SetLayoutUnlocked(unlocked) SetLayoutUnlocked(unlocked) end
function UI.IsLayoutUnlocked() return layoutUnlocked == true end
function UI.HasEditMode()
    if Compat.HasEditMode then return Compat.HasEditMode() end
    return EditModeManagerFrame ~= nil
end
function UI.ToggleVitalFrame() ToggleVitalFrame() end
function UI.ResetToDefaults() ResetToDefaults() end
function UI.SetBarPercent(barKey, percent) SetBarPercent(barKey, percent) end
function UI.RefreshBarLayout() UpdateProgressBarLayout() end
function UI.IsBarEnabled(barKey) return IsBarEnabled(barKey) end
function UI.SetBarRuntimeHidden(barKey, hidden)
    SetBarRuntimeHidden(barKey, hidden)
end
function UI.SetBarLabelText(barKey, text) SetBarLabelText(barKey, text) end
function UI.SetBarBackgroundPercent(barKey, percent)
    SetBarBackgroundPercent(barKey, percent)
end
function UI.SetLevelText(level) SetLevelText(level) end
function UI.UpdateNameText() UpdateNameText() end
