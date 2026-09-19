local addonName, addonTable = ...
local L = addonTable.L
local Compat = addonTable.Compat or {}

addonTable.UI = addonTable.UI or {}
local UI = addonTable.UI

local DEFAULT_SKILLS_WIDTH = 155
local DEFAULT_SKILLS_HEIGHT = 170
local SKILLS_MIN_WIDTH, SKILLS_MAX_WIDTH = 120, 400
local SKILLS_MIN_HEIGHT, SKILLS_MAX_HEIGHT = 80, 400
local SKILLS_BAR_PADDING = 4
local SKILLS_BAR_GAP = 0
local SKILLS_MIN_BAR_HEIGHT = 8
local SKILLS_BORDER_COLOR = {0.83, 0.66, 0.27, 1}
local SKILLS_TRAIN_MARK_COLOR = {0.42, 0.42, 0.42, 0.85}

local CATEGORY_COLORS = {
    profession = {0.85, 0.55, 0.20, 1},
    secondary = {0.55, 0.72, 0.35, 1},
    weapon = {0.55, 0.62, 0.72, 1},
    stat = {0.68, 0.58, 0.72, 1}
}

local skillsFrame
local skillsSelection
local skillsSettingsPanel
local skillsBars = {}
local visibleSkills = {}
local knownSkills = {}
local skillsSettingsBuilt = false
local skillsSettingsWidgets = {}
local skillsFocused = false
local skillsHovered = false

local function GetDB()
    if addonTable and addonTable.GetDB then return addonTable.GetDB() end
    return nil
end

local function SupportsClassicSkills()
    if Compat.SupportsClassicSkills then return Compat.SupportsClassicSkills() end
    return false
end

local function GetSkillsSettings()
    local db = GetDB()
    if not db or not db.profile then return nil end
    db.profile.skillsFrame = db.profile.skillsFrame or {}
    local settings = db.profile.skillsFrame
    if settings.point == nil then settings.point = "CENTER" end
    if settings.x == nil then settings.x = 180 end
    if settings.y == nil then settings.y = 0 end
    if settings.width == nil or settings.width == 133 or settings.width == 150 then
        settings.width = DEFAULT_SKILLS_WIDTH
    end
    if settings.height == nil or settings.height == 133 or
        settings.height == 150 then
        settings.height = DEFAULT_SKILLS_HEIGHT
    end
    if settings.shown == nil then settings.shown = true end
    if settings.mode ~= "selected" then settings.mode = "all" end
    if settings.weaponMode ~= "equipped" then settings.weaponMode = "allKnown" end
    if type(settings.selected) ~= "table" then settings.selected = {} end
    return settings
end

local function GetDefaultSkillsSize()
    return DEFAULT_SKILLS_WIDTH, DEFAULT_SKILLS_HEIGHT
end

local function ClampSkillsSize(width, height)
    local defaultWidth, defaultHeight = GetDefaultSkillsSize()
    width = math.floor(tonumber(width) or defaultWidth)
    height = math.floor(tonumber(height) or defaultHeight)
    if width < SKILLS_MIN_WIDTH then width = SKILLS_MIN_WIDTH end
    if width > SKILLS_MAX_WIDTH then width = SKILLS_MAX_WIDTH end
    if height < SKILLS_MIN_HEIGHT then height = SKILLS_MIN_HEIGHT end
    if height > SKILLS_MAX_HEIGHT then height = SKILLS_MAX_HEIGHT end
    return width, height
end

local function GetSavedSkillsSize()
    local settings = GetSkillsSettings()
    local defaultWidth, defaultHeight = GetDefaultSkillsSize()
    if not settings then return defaultWidth, defaultHeight end
    return ClampSkillsSize(settings.width or defaultWidth,
                           settings.height or defaultHeight)
end

local function SaveSkillsSize(width, height)
    local settings = GetSkillsSettings()
    if not settings then return end
    width, height = ClampSkillsSize(width, height)
    settings.width = width
    settings.height = height
end

local function SaveSkillsPosition()
    local settings = GetSkillsSettings()
    if not settings or not skillsFrame then return end

    local ok, point, x, y = pcall(function()
        local p, _, _, px, py = skillsFrame:GetPoint(1)
        return p, tonumber(px), tonumber(py)
    end)
    if ok and x and y then
        settings.point = point or "CENTER"
        settings.x = x
        settings.y = y
        return
    end

    ok, x, y = pcall(function()
        local left = tonumber(skillsFrame:GetLeft())
        local top = tonumber(skillsFrame:GetTop())
        local parentHeight = tonumber(UIParent:GetHeight()) or 0
        local scale = tonumber(skillsFrame:GetScale()) or 1
        if not left or not top then return nil end
        return left, -((parentHeight - top * scale) / scale)
    end)
    if ok and x and y then
        settings.point = "TOPLEFT"
        settings.x = x
        settings.y = y
    end
end

local function LockSkillsFramePosition(frame)
    frame = frame or skillsFrame
    if not frame or not frame.GetObjectType then return end
    if UI.LockFrameToAddonPosition then
        UI.LockFrameToAddonPosition(frame)
        return
    end
    if frame.SetDontSavePosition then
        pcall(frame.SetDontSavePosition, frame, true)
    end
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

local function BakeSkillsFrameToUIParent(deltaX, deltaY)
    if not skillsFrame then return end

    local ok, offsetX, offsetY = pcall(function()
        local top = tonumber(skillsFrame:GetTop())
        local left = tonumber(skillsFrame:GetLeft())
        local scale = tonumber(skillsFrame:GetScale()) or 1
        local parentHeight = tonumber(UIParent:GetHeight()) or 0
        if not top or not left then return nil end
        return left + (deltaX or 0),
               -((parentHeight - top * scale) / scale) + (deltaY or 0)
    end)
    if not ok or not offsetX then return end

    if skillsFrame.ClearFrameSnap then skillsFrame:ClearFrameSnap() end
    skillsFrame:ClearAllPoints()
    skillsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offsetX, offsetY)
    LockSkillsFramePosition()
    local settings = GetSkillsSettings()
    if settings then
        settings.point = "TOPLEFT"
        settings.x = offsetX
        settings.y = offsetY
    end
end

local function IsEditModeOpen()
    if UI.IsEditModeOpen then return UI.IsEditModeOpen() end
    if EditModeManagerFrame then return EditModeManagerFrame:IsShown() end
    return UI.IsLayoutUnlocked and UI.IsLayoutUnlocked()
end

local function GetOnePixelHeight(region)
    region = region or skillsFrame
    local scale = 1
    if region and region.GetEffectiveScale then
        scale = region:GetEffectiveScale() or 1
    end
    if scale == 0 then scale = 1 end
    if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
        return PixelUtil.GetPixelToUIUnitFactor() / scale
    end
    local physicalHeight = 768
    if GetPhysicalScreenSize then
        physicalHeight = select(2, GetPhysicalScreenSize()) or 768
    end
    return (768 / physicalHeight) / scale
end

local function GetSharedFrameBorderColor()
    if UI.GetFrameBorderColor then return UI.GetFrameBorderColor() end
    return SKILLS_BORDER_COLOR[1], SKILLS_BORDER_COLOR[2], SKILLS_BORDER_COLOR[3],
           SKILLS_BORDER_COLOR[4]
end

local function GetSkillsBorderColor()
    if skillsFrame and skillsFrame.GetBackdropBorderColor then
        local r, g, b, a = skillsFrame:GetBackdropBorderColor()
        if r then return r, g, b, a or 1 end
    end
    return GetSharedFrameBorderColor()
end

local function GetProfessionTrainRank(maxRank)
    maxRank = tonumber(maxRank) or 0
    if maxRank < 75 then return nil end
    local expansionCap = 300
    if Compat.IsRetailClient and Compat.IsRetailClient() then
        expansionCap = 800
    elseif Compat.GetTocVersion then
        local toc = Compat.GetTocVersion() or 0
        if toc >= 40000 then
            expansionCap = 525
        elseif toc >= 30000 then
            expansionCap = 450
        elseif toc >= 20000 then
            expansionCap = 375
        end
    end
    if maxRank >= expansionCap then return nil end
    return maxRank - 25
end

local function AcquireSkillBar(index)
    local bar = skillsBars[index]
    if bar then return bar end

    bar = CreateFrame("StatusBar", nil, skillsFrame)
    bar:SetFrameLevel(skillsFrame:GetFrameLevel() + 3)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetClipsChildren(true)

    local bgFrame = CreateFrame("Frame", nil, bar)
    bgFrame:SetAllPoints(bar)
    bgFrame:SetFrameLevel(bar:GetFrameLevel() - 2)
    local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0.18, 0.18, 0.18, 0.35)
    bar.Background = bg

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER", bar, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:SetText("")
    bar.LabelText = label

    local trainLine = bar:CreateTexture(nil, "OVERLAY")
    trainLine:SetWidth(2)
    trainLine:Hide()
    bar.TrainLine = trainLine

    local divider = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    divider:SetHeight(1)
    divider:Hide()
    bar.Divider = divider

    skillsBars[index] = bar
    return bar
end

local function LayoutSkillBars()
    if not skillsFrame then return end

    local count = #visibleSkills
    local width = skillsFrame:GetWidth()
    local height = skillsFrame:GetHeight()
    local usableWidth = width - (SKILLS_BAR_PADDING * 2)
    local usableHeight = height - (SKILLS_BAR_PADDING * 2)
    if usableWidth < 20 then usableWidth = 20 end
    if usableHeight < SKILLS_MIN_BAR_HEIGHT then
        usableHeight = SKILLS_MIN_BAR_HEIGHT
    end

    local barHeight = SKILLS_MIN_BAR_HEIGHT
    if count > 0 then
        local totalGap = SKILLS_BAR_GAP * (count - 1)
        barHeight = math.floor((usableHeight - totalGap) / count)
        if barHeight < 1 then barHeight = 1 end
    end

    local previousBar
    for index, skill in ipairs(visibleSkills) do
        local bar = AcquireSkillBar(index)
        local color = CATEGORY_COLORS[skill.category] or CATEGORY_COLORS.weapon
        bar:ClearAllPoints()
        if previousBar then
            bar:SetPoint("TOPLEFT", previousBar, "BOTTOMLEFT", 0, 0)
            bar:SetPoint("TOPRIGHT", previousBar, "BOTTOMRIGHT", 0, 0)
        else
            bar:SetPoint("TOPLEFT", skillsFrame, "TOPLEFT", SKILLS_BAR_PADDING,
                         -SKILLS_BAR_PADDING)
            bar:SetPoint("TOPRIGHT", skillsFrame, "TOPRIGHT",
                         -SKILLS_BAR_PADDING, -SKILLS_BAR_PADDING)
        end
        if index == count then
            bar:SetPoint("BOTTOMLEFT", skillsFrame, "BOTTOMLEFT",
                         SKILLS_BAR_PADDING, SKILLS_BAR_PADDING)
            bar:SetPoint("BOTTOMRIGHT", skillsFrame, "BOTTOMRIGHT",
                         -SKILLS_BAR_PADDING, SKILLS_BAR_PADDING)
        else
            bar:SetHeight(barHeight)
        end
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        local pct = 0
        if skill.maxRank and skill.maxRank > 0 then
            pct = skill.rank / skill.maxRank
            if pct < 0 then pct = 0 end
            if pct > 1 then pct = 1 end
        end
        bar:SetValue(pct)

        local borderR, borderG, borderB, borderA = GetSkillsBorderColor()
        if bar.TrainLine then
            local trainAt = nil
            if skill.category == "profession" or skill.category == "secondary" then
                trainAt = GetProfessionTrainRank(skill.maxRank)
            end
            if trainAt and skill.maxRank and skill.maxRank > 0 then
                local barWidth = bar:GetWidth()
                if barWidth <= 0 then barWidth = usableWidth end
                local offset = math.floor((trainAt / skill.maxRank) * barWidth +
                                              0.5)
                if offset < 1 then offset = 1 end
                if offset > barWidth - 2 then offset = barWidth - 2 end
                bar.TrainLine:ClearAllPoints()
                bar.TrainLine:SetWidth(2)
                bar.TrainLine:SetColorTexture(SKILLS_TRAIN_MARK_COLOR[1],
                                              SKILLS_TRAIN_MARK_COLOR[2],
                                              SKILLS_TRAIN_MARK_COLOR[3],
                                              SKILLS_TRAIN_MARK_COLOR[4])
                bar.TrainLine:SetPoint("TOPLEFT", bar, "TOPLEFT", offset, 0)
                bar.TrainLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", offset, 0)
                bar.TrainLine:Show()
            else
                bar.TrainLine:Hide()
            end
        end

        if bar.Divider then
            if index < count then
                local lineHeight = GetOnePixelHeight(bar)
                bar.Divider:ClearAllPoints()
                bar.Divider:SetColorTexture(borderR, borderG, borderB, borderA)
                bar.Divider:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
                bar.Divider:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
                bar.Divider:SetHeight(lineHeight)
                bar.Divider:Show()
            else
                bar.Divider:Hide()
            end
        end
        if bar.LabelText then
            local fontPath, _, flags = bar.LabelText:GetFont()
            local fontSize = math.max(8, math.min(12, barHeight - 1))
            bar.LabelText:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", fontSize,
                                  flags)
            local ok, text = pcall(string.format, L["%s (%d/%d)"], skill.name,
                                   skill.rank or 0, skill.maxRank or 0)
            if ok then
                bar.LabelText:SetText(text)
            else
                bar.LabelText:SetText(tostring(skill.rank or 0) .. "/" ..
                                          tostring(skill.maxRank or 0))
            end
        end
        bar:Show()
        previousBar = bar
    end

    for index = count + 1, #skillsBars do
        skillsBars[index]:Hide()
        if skillsBars[index].Divider then skillsBars[index].Divider:Hide() end
        if skillsBars[index].TrainLine then skillsBars[index].TrainLine:Hide() end
    end
end

local function ApplySkillsFrameSize(width, height)
    if not skillsFrame then return end
    width, height = ClampSkillsSize(width, height)
    skillsFrame:SetSize(width, height)
    SaveSkillsSize(width, height)
    LayoutSkillBars()
end

local function SetSkillsFrameShown(shouldShow)
    local settings = GetSkillsSettings()
    if settings then settings.shown = shouldShow and true or false end
    if not skillsFrame then return end
    if shouldShow then
        skillsFrame:Show()
    else
        skillsFrame:Hide()
        if UI.GetLayoutFocus and UI.GetLayoutFocus() == "skills" then
            UI.SetLayoutFocus(nil)
        end
    end
    if UI.UpdateSkillsFrameEditMode then UI.UpdateSkillsFrameEditMode() end
end

local function UpdateSkillSelectList()
    local child = skillsSettingsWidgets.SkillSelectChild
    if not child then return end
    local checks = child.Checks or {}
    child.Checks = checks

    local settings = GetSkillsSettings()
    local selected = settings and settings.selected or {}
    local modeIsSelected = settings and settings.mode == "selected"
    local y = 0
    local used = {}

    for index, skill in ipairs(knownSkills) do
        local check = checks[index]
        if not check then
            check = CreateFrame("CheckButton", nil, child,
                                "UICheckButtonTemplate")
            check:SetSize(24, 24)
            local label = check:CreateFontString(nil, "OVERLAY",
                                                 "GameFontHighlightSmall")
            label:SetPoint("LEFT", check, "RIGHT", 4, 1)
            label:SetJustifyH("LEFT")
            check.Label = label
            checks[index] = check
        end
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
        check.Label:SetText(skill.name)
        check:SetChecked(selected[skill.name] == true)
        check:SetEnabled(modeIsSelected)
        if check.SetAlpha then check:SetAlpha(modeIsSelected and 1 or 0.55) end
        check:SetScript("OnClick", function(self)
            local current = GetSkillsSettings()
            if not current then return end
            current.selected = current.selected or {}
            current.selected[skill.name] = self:GetChecked() == true
            if addonTable.RefreshSkillsData then
                addonTable.RefreshSkillsData()
            end
        end)
        check:Show()
        used[index] = true
        y = y + 22
    end

    for index, check in pairs(checks) do
        if not used[index] then check:Hide() end
    end

    child:SetHeight(math.max(y, 1))
    child:SetWidth(260)
    local scroll = skillsSettingsWidgets.SkillSelectScroll
    if scroll then
        scroll:EnableMouseWheel(modeIsSelected)
        if scroll.SetAlpha then scroll:SetAlpha(modeIsSelected and 1 or 0.55) end
    end
end

local function RefreshSkillsSettings()
    if not skillsSettingsBuilt then return end
    local settings = GetSkillsSettings()
    if not settings then return end

    local width, height = GetSavedSkillsSize()
    if skillsFrame then
        width = math.floor(skillsFrame:GetWidth() + 0.5)
        height = math.floor(skillsFrame:GetHeight() + 0.5)
    end

    if skillsSettingsWidgets.ShowCheck then
        skillsSettingsWidgets.ShowCheck:SetChecked(settings.shown ~= false)
    end
    if skillsSettingsWidgets.AllSkillsCheck then
        skillsSettingsWidgets.AllSkillsCheck:SetChecked(settings.mode ~= "selected")
    end
    if skillsSettingsWidgets.SelectedSkillsCheck then
        skillsSettingsWidgets.SelectedSkillsCheck:SetChecked(settings.mode == "selected")
    end
    if skillsSettingsWidgets.WeaponAllCheck then
        skillsSettingsWidgets.WeaponAllCheck:SetChecked(settings.weaponMode ~= "equipped")
    end
    if skillsSettingsWidgets.WeaponEquippedCheck then
        skillsSettingsWidgets.WeaponEquippedCheck:SetChecked(
            settings.weaponMode == "equipped")
    end
    if skillsSettingsWidgets.WidthSlider then
        skillsSettingsWidgets.WidthSlider:SetValue(width)
    end
    if skillsSettingsWidgets.WidthValue then
        skillsSettingsWidgets.WidthValue:SetText(tostring(width))
    end
    if skillsSettingsWidgets.HeightSlider then
        skillsSettingsWidgets.HeightSlider:SetValue(height)
    end
    if skillsSettingsWidgets.HeightValue then
        skillsSettingsWidgets.HeightValue:SetText(tostring(height))
    end
    UpdateSkillSelectList()
end

local function SeedSelectedSkills()
    local settings = GetSkillsSettings()
    if not settings then return end
    settings.selected = settings.selected or {}
    local hasAny = false
    for _, enabled in pairs(settings.selected) do
        if enabled then
            hasAny = true
            break
        end
    end
    if hasAny then return end
    for _, skill in ipairs(knownSkills) do
        settings.selected[skill.name] = true
    end
end

local function BeginSkillsDrag(frame)
    if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
    if UI.AttachEditModeSnapAPI then UI.AttachEditModeSnapAPI(frame) end
    if frame.BreakSnappedFrames then frame:BreakSnappedFrames() end
    if frame.ClearFrameSnap then frame:ClearFrameSnap() end
    frame:StartMoving()
    LockSkillsFramePosition()
    if frame.GetFrameMagneticEligibility and EditModeManagerFrame and
        EditModeManagerFrame.SetSnapPreviewFrame then
        EditModeManagerFrame:SetSnapPreviewFrame(frame)
    end
end

local function FinishSkillsDrag(frame)
    if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
        EditModeManagerFrame:ClearSnapPreviewFrame()
    end
    frame:StopMovingOrSizing()
    if EditModeMagnetismManager and frame.GetFrameMagneticEligibility and
        EditModeManagerFrame and EditModeManagerFrame.IsSnapEnabled and
        EditModeManagerFrame:IsSnapEnabled() then
        EditModeMagnetismManager:ApplyMagnetism(frame)
    end
    BakeSkillsFrameToUIParent()
    LockSkillsFramePosition()
    SaveSkillsPosition()
end

local function SetSkillsSelectionVisual(isSelected)
    if not skillsSelection or not skillsSelection.Background then return end
    if isSelected then
        skillsSelection.Background:SetTexture(
            "Interface/AddOns/VitalFrame/Art/EditModeSelected")
        skillsSelection.Background:SetAlpha(1)
        if skillsSelection.EditHint then skillsSelection.EditHint:Hide() end
    else
        skillsSelection.Background:SetTexture(
            "Interface/AddOns/VitalFrame/Art/EditModeHighlighted")
        skillsSelection.Background:SetAlpha(skillsHovered and 1 or 0.62)
    end
end

local function GetSkillsSettingsPanelSavedPosition()
    local db = GetDB()
    if not db or not db.global or not db.global.skillsSettingsPanel then
        return nil
    end
    local saved = db.global.skillsSettingsPanel
    if saved.hasCustomPosition ~= true then return nil end
    return saved
end

local function SaveSkillsSettingsPanelPosition()
    local db = GetDB()
    if not db or not skillsSettingsPanel then return end
    db.global = db.global or {}
    db.global.skillsSettingsPanel = db.global.skillsSettingsPanel or {}

    local point, _, _, x, y = skillsSettingsPanel:GetPoint(1)
    db.global.skillsSettingsPanel.point = point or "CENTER"
    db.global.skillsSettingsPanel.x = x or 0
    db.global.skillsSettingsPanel.y = y or 0
    db.global.skillsSettingsPanel.hasCustomPosition = true
end

local function AnchorSkillsSettingsPanel()
    if not skillsSettingsPanel then return end
    skillsSettingsPanel:ClearAllPoints()

    local saved = GetSkillsSettingsPanelSavedPosition()
    if saved then
        skillsSettingsPanel:SetPoint(saved.point or "CENTER", UIParent,
                                     saved.point or "CENTER", saved.x or 0,
                                     saved.y or 0)
        return
    end

    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        skillsSettingsPanel:SetPoint("TOPRIGHT", EditModeManagerFrame,
                                     "TOPLEFT", -12, -8)
    elseif skillsFrame then
        skillsSettingsPanel:SetPoint("TOPLEFT", skillsFrame, "TOPRIGHT", 12, 0)
    end
end

local function CreateSkillsSettingsPanel()
    if not SupportsClassicSkills() or skillsSettingsBuilt then return end

    local settingsPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    settingsPanel:SetSize(360, 532)
    settingsPanel:SetFrameStrata("DIALOG")
    settingsPanel:SetFrameLevel((skillsFrame and skillsFrame:GetFrameLevel() or
                                    1) + 20)
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
            if UI.SuppressNextFocusClear then UI.SuppressNextFocusClear() end
            if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
        end
    end)
    settingsPanel:SetScript("OnDragStart", function(self)
        if IsEditModeOpen() then
            if UI.SuppressNextFocusClear then UI.SuppressNextFocusClear() end
            if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
            self:StartMoving()
        end
    end)
    settingsPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveSkillsSettingsPanelPosition()
    end)
    settingsPanel:SetScript("OnKeyDown", function(self, key)
        if UI.OnEditModeNudgeKey then UI.OnEditModeNudgeKey(self, key) end
    end)

    local panelTitle = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightLarge")
    panelTitle:SetPoint("TOP", settingsPanel, "TOP", 0, -15)
    panelTitle:SetText(L["Skills Frame Options"])

    local panelCloseButton = CreateFrame("Button", nil, settingsPanel,
                                         "UIPanelCloseButton")
    panelCloseButton:SetPoint("TOPRIGHT")
    panelCloseButton:SetScript("OnClick", function()
        if UI.SetLayoutFocus then UI.SetLayoutFocus(nil) end
    end)

    local checkGap = 0
    local allCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                 "UICheckButtonTemplate")
    allCheck:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 20, -42)
    local allLabel = allCheck:CreateFontString(nil, "OVERLAY",
                                               "GameFontHighlight")
    allLabel:SetPoint("LEFT", allCheck, "RIGHT", 10, 1)
    allLabel:SetText(L["All Skills"])
    allCheck:SetScript("OnClick", function()
        local settings = GetSkillsSettings()
        if settings then settings.mode = "all" end
        if addonTable.RefreshSkillsData then addonTable.RefreshSkillsData() end
        RefreshSkillsSettings()
    end)

    local selectedCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                      "UICheckButtonTemplate")
    selectedCheck:SetPoint("TOPLEFT", allCheck, "BOTTOMLEFT", 0, checkGap)
    local selectedLabel = selectedCheck:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    selectedLabel:SetPoint("LEFT", selectedCheck, "RIGHT", 10, 1)
    selectedLabel:SetText(L["Selected Skills"])
    selectedCheck:SetScript("OnClick", function()
        SeedSelectedSkills()
        local settings = GetSkillsSettings()
        if settings then settings.mode = "selected" end
        if addonTable.RefreshSkillsData then addonTable.RefreshSkillsData() end
        RefreshSkillsSettings()
    end)

    local selectScroll = CreateFrame("ScrollFrame", nil, settingsPanel)
    selectScroll:SetSize(284, 150)
    selectScroll:SetPoint("TOPLEFT", selectedCheck, "BOTTOMLEFT", 16, 0)
    selectScroll:EnableMouseWheel(true)
    local selectChild = CreateFrame("Frame", nil, selectScroll)
    selectChild:SetSize(260, 1)
    selectScroll:SetScrollChild(selectChild)
    selectScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local range = self:GetVerticalScrollRange() or 0
        local nextScroll = current - (delta * 20)
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > range then nextScroll = range end
        self:SetVerticalScroll(nextScroll)
    end)

    local weaponLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                       "GameFontHighlight")
    weaponLabel:SetPoint("TOPLEFT", selectScroll, "BOTTOMLEFT", -16, -4)
    weaponLabel:SetText(L["Weapon Skills"])

    local weaponAllCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                       "UICheckButtonTemplate")
    weaponAllCheck:SetPoint("TOPLEFT", weaponLabel, "BOTTOMLEFT", 0, checkGap)
    local weaponAllLabel = weaponAllCheck:CreateFontString(nil, "OVERLAY",
                                                           "GameFontHighlight")
    weaponAllLabel:SetPoint("LEFT", weaponAllCheck, "RIGHT", 10, 1)
    weaponAllLabel:SetText(L["All Known"])
    weaponAllCheck:SetScript("OnClick", function()
        local settings = GetSkillsSettings()
        if settings then settings.weaponMode = "allKnown" end
        if addonTable.RefreshSkillsData then addonTable.RefreshSkillsData() end
        RefreshSkillsSettings()
    end)

    local weaponEquippedCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                            "UICheckButtonTemplate")
    weaponEquippedCheck:SetPoint("TOPLEFT", weaponAllCheck, "BOTTOMLEFT", 0,
                                 checkGap)
    local weaponEquippedLabel = weaponEquippedCheck:CreateFontString(nil,
                                                                     "OVERLAY",
                                                                     "GameFontHighlight")
    weaponEquippedLabel:SetPoint("LEFT", weaponEquippedCheck, "RIGHT", 10, 1)
    weaponEquippedLabel:SetText(L["Equipped"])
    weaponEquippedCheck:SetScript("OnClick", function()
        local settings = GetSkillsSettings()
        if settings then settings.weaponMode = "equipped" end
        if addonTable.RefreshSkillsData then addonTable.RefreshSkillsData() end
        RefreshSkillsSettings()
    end)

    local widthLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlight")
    widthLabel:SetPoint("TOPLEFT", weaponEquippedCheck, "BOTTOMLEFT", 0, -6)
    widthLabel:SetText(L["Width"])

    local widthControl, widthSlider
    if UI.CreateSizeSlider then
        widthControl, widthSlider = UI.CreateSizeSlider(
                                        "VitalFrameSkillsWidthSlider",
                                        settingsPanel)
    end
    if not widthSlider then
        widthSlider = CreateFrame("Slider", "VitalFrameSkillsWidthSlider",
                                  settingsPanel, "OptionsSliderTemplate")
        widthSlider:SetSize(200, 17)
        widthControl = widthSlider
    end
    widthControl:SetPoint("LEFT", widthLabel, "LEFT", 60, 0)
    widthSlider:SetMinMaxValues(SKILLS_MIN_WIDTH, SKILLS_MAX_WIDTH)
    widthSlider:SetValueStep(1)
    if widthSlider.SetObeyStepOnDrag then
        pcall(widthSlider.SetObeyStepOnDrag, widthSlider, true)
    end
    local widthValue = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlight")
    widthValue:SetPoint("LEFT", widthControl, "RIGHT", 8, 0)
    widthSlider:SetScript("OnValueChanged", function(_, value)
        local width = math.floor(value + 0.5)
        widthValue:SetText(tostring(width))
        if skillsFrame and skillsFrame.GetObjectType and
            math.floor(skillsFrame:GetWidth() + 0.5) ~= width then
            ApplySkillsFrameSize(width, skillsFrame:GetHeight())
        end
    end)

    local heightLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                       "GameFontHighlight")
    heightLabel:SetPoint("TOPLEFT", widthLabel, "BOTTOMLEFT", 0, -20)
    heightLabel:SetText(L["Height"])

    local heightControl, heightSlider
    if UI.CreateSizeSlider then
        heightControl, heightSlider = UI.CreateSizeSlider(
                                          "VitalFrameSkillsHeightSlider",
                                          settingsPanel)
    end
    if not heightSlider then
        heightSlider = CreateFrame("Slider", "VitalFrameSkillsHeightSlider",
                                   settingsPanel, "OptionsSliderTemplate")
        heightSlider:SetSize(200, 17)
        heightControl = heightSlider
    end
    heightControl:SetPoint("LEFT", heightLabel, "LEFT", 60, 0)
    heightSlider:SetMinMaxValues(SKILLS_MIN_HEIGHT, SKILLS_MAX_HEIGHT)
    heightSlider:SetValueStep(1)
    if heightSlider.SetObeyStepOnDrag then
        pcall(heightSlider.SetObeyStepOnDrag, heightSlider, true)
    end
    local heightValue = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                       "GameFontHighlight")
    heightValue:SetPoint("LEFT", heightControl, "RIGHT", 8, 0)
    heightSlider:SetScript("OnValueChanged", function(_, value)
        local height = math.floor(value + 0.5)
        heightValue:SetText(tostring(height))
        if skillsFrame and skillsFrame.GetObjectType and
            math.floor(skillsFrame:GetHeight() + 0.5) ~= height then
            ApplySkillsFrameSize(skillsFrame:GetWidth(), height)
        end
    end)

    local resetButton = CreateFrame("Button", nil, settingsPanel,
                                    "UIPanelButtonTemplate")
    resetButton:SetSize(200, 22)
    resetButton:SetPoint("BOTTOM", settingsPanel, "BOTTOM", 0, 15)
    resetButton:SetText(L["Reset to Defaults"])
    resetButton:SetScript("OnClick", function()
        UI.ResetSkillsFrame()
    end)

    skillsSettingsPanel = settingsPanel
    skillsSettingsWidgets.AllSkillsCheck = allCheck
    skillsSettingsWidgets.SelectedSkillsCheck = selectedCheck
    skillsSettingsWidgets.WeaponAllCheck = weaponAllCheck
    skillsSettingsWidgets.WeaponEquippedCheck = weaponEquippedCheck
    skillsSettingsWidgets.WidthSlider = widthSlider
    skillsSettingsWidgets.WidthValue = widthValue
    skillsSettingsWidgets.HeightSlider = heightSlider
    skillsSettingsWidgets.HeightValue = heightValue
    skillsSettingsWidgets.SkillSelectScroll = selectScroll
    skillsSettingsWidgets.SkillSelectChild = selectChild

    skillsSettingsBuilt = true
    RefreshSkillsSettings()
end

function UI.CreateSkillsFrame()
    if not SupportsClassicSkills() then return end
    if skillsFrame and skillsFrame.GetObjectType then return end

    local settings = GetSkillsSettings() or {
        point = "CENTER",
        x = 180,
        y = 0,
        shown = true
    }
    local width, height = GetSavedSkillsSize()

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    LockSkillsFramePosition(frame)
    frame:SetPoint(settings.point or "CENTER", UIParent,
                   settings.point or "CENTER", settings.x or 180,
                   settings.y or 0)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(2)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.5)
    local borderR, borderG, borderB, borderA = GetSharedFrameBorderColor()
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    if frame.SetClipsChildren then frame:SetClipsChildren(true) end

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
    selection:Hide()
    frame.Selection = selection
    if UI.AttachEditModeSnapAPI then UI.AttachEditModeSnapAPI(frame) end

    skillsFrame = frame
    skillsSelection = selection

    frame:SetScript("OnDragStart", function(self)
        if IsEditModeOpen() then BeginSkillsDrag(self) end
    end)
    frame:SetScript("OnDragStop", function(self) FinishSkillsDrag(self) end)
    frame:SetScript("OnSizeChanged", function() LayoutSkillBars() end)
    frame:SetScript("OnShow", function() LayoutSkillBars() end)
    frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and IsEditModeOpen() then
            if UI.SuppressNextFocusClear then UI.SuppressNextFocusClear() end
            if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
        end
    end)
    frame:SetScript("OnEnter", function()
        if IsEditModeOpen() and not skillsFocused then
            skillsHovered = true
            SetSkillsSelectionVisual(false)
            if skillsSelection and skillsSelection.EditHint then
                skillsSelection.EditHint:Show()
            end
        end
    end)
    frame:SetScript("OnLeave", function()
        if IsEditModeOpen() and not skillsFocused then
            skillsHovered = false
            SetSkillsSelectionVisual(false)
            if skillsSelection and skillsSelection.EditHint then
                skillsSelection.EditHint:Hide()
            end
        end
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        if UI.OnEditModeNudgeKey then UI.OnEditModeNudgeKey(self, key) end
    end)

    CreateSkillsSettingsPanel()

    if settings.shown == false then
        frame:Hide()
    else
        frame:Show()
    end

    UI.UpdateSkillsFrameEditMode()
    LayoutSkillBars()
end

function UI.SetSkillsData(visible, catalog)
    visibleSkills = visible or {}
    knownSkills = catalog or {}
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    LayoutSkillBars()
    UpdateSkillSelectList()
end

function UI.LayoutSkillBars() LayoutSkillBars() end

function UI.RefreshSkillsSettings() RefreshSkillsSettings() end

function UI.IsSkillsFrameShown()
    return skillsFrame and skillsFrame.GetObjectType and skillsFrame:IsShown()
end

function UI.ApplySavedSkillsFrameLayout()
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    local settings = GetSkillsSettings()
    if not settings then return end
    local width, height = GetSavedSkillsSize()
    LockSkillsFramePosition()
    skillsFrame:ClearAllPoints()
    skillsFrame:SetPoint(settings.point or "CENTER", UIParent,
                         settings.point or "CENTER", settings.x or 180,
                         settings.y or 0)
    skillsFrame:SetSize(width, height)
    LockSkillsFramePosition()
    LayoutSkillBars()
end

function UI.ResetSkillsFrame()
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    local settings = GetSkillsSettings()
    local width, height = GetDefaultSkillsSize()
    if settings then
        settings.point = "CENTER"
        settings.x = 180
        settings.y = 0
        settings.width = width
        settings.height = height
        settings.mode = "all"
        settings.weaponMode = "allKnown"
        settings.selected = {}
        settings.shown = true
    end
    skillsFrame:ClearAllPoints()
    skillsFrame:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
    ApplySkillsFrameSize(width, height)
    skillsFrame:Show()
    RefreshSkillsSettings()
    if addonTable.RefreshSkillsData then addonTable.RefreshSkillsData() end
    if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
end

function UI.UpdateSkillsFrameEditMode()
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    local editModeShown = IsEditModeOpen()
    if not editModeShown then
        skillsFocused = false
        skillsHovered = false
    end
    skillsFrame:EnableMouse(editModeShown)
    if skillsSelection then
        skillsSelection:SetShown(editModeShown and skillsFrame:IsShown())
        SetSkillsSelectionVisual(skillsFocused)
    end
    if UI.AttachEditModeSnapAPI then UI.AttachEditModeSnapAPI(skillsFrame) end
end

function UI.SetSkillsFocusVisual(focused)
    skillsFocused = focused and true or false
    if skillsFocused then
        skillsHovered = true
        if skillsSelection and skillsSelection.EditHint then
            skillsSelection.EditHint:Hide()
        end
    end
    SetSkillsSelectionVisual(skillsFocused)
end

function UI.SetSkillsKeyboardEnabled(enabled)
    if skillsFrame then skillsFrame:EnableKeyboard(enabled and true or false) end
    if skillsSettingsPanel then
        skillsSettingsPanel:EnableKeyboard(enabled and true or false)
    end
end

function UI.NudgeSkillsFrame(deltaX, deltaY)
    if not skillsFrame then return end
    if skillsFrame.BreakSnappedFrames then skillsFrame:BreakSnappedFrames() end
    BakeSkillsFrameToUIParent(deltaX, deltaY)
    SaveSkillsPosition()
end

function UI.UpdateSkillsSettingsVisibility()
    if not skillsSettingsPanel then return end
    local editModeShown = IsEditModeOpen()
    local focused = UI.GetLayoutFocus and UI.GetLayoutFocus() == "skills"
    local shouldShow = editModeShown and focused and skillsFrame and
                           skillsFrame:IsShown()
    if shouldShow then AnchorSkillsSettingsPanel() end
    skillsSettingsPanel:SetShown(shouldShow)
    if shouldShow then RefreshSkillsSettings() end
end

function UI.IsSkillsFrameMouseOver()
    return skillsFrame and skillsFrame.GetObjectType and skillsFrame:IsShown()
               and skillsFrame:IsMouseOver()
end

function UI.IsSkillsSettingsMouseOver()
    return skillsSettingsPanel and skillsSettingsPanel:IsShown() and
               skillsSettingsPanel:IsMouseOver()
end

function UI.GetSkillsFrameEnabled()
    local settings = GetSkillsSettings()
    return not settings or settings.shown ~= false
end

function UI.SetSkillsFrameShown(shouldShow)
    SetSkillsFrameShown(shouldShow)
end

function UI.ApplySkillsFrameTheme()
    if not skillsFrame or not skillsFrame.SetBackdropBorderColor then return end
    local r, g, b, a = GetSharedFrameBorderColor()
    skillsFrame:SetBackdropBorderColor(r, g, b, a)
    LayoutSkillBars()
end
