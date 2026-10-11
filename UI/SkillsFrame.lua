local addonName, addonTable = ...
local L = addonTable.L
local Compat = addonTable.Compat or {}

addonTable.UI = addonTable.UI or {}
local UI = addonTable.UI

local DEFAULT_SKILLS_WIDTH = 155
local DEFAULT_SKILLS_BAR_HEIGHT = 16
local SKILLS_MIN_WIDTH, SKILLS_MAX_WIDTH = 120, 400
local SKILLS_MIN_BAR_HEIGHT, SKILLS_MAX_BAR_HEIGHT = 8, 32
local SKILLS_BAR_PADDING = 4
local SKILLS_BAR_GAP = 0
local SKILLS_SCREEN_INSET = 0
local SKILLS_EDGE_FLUSH = 1
local applyingSkillsSize = false
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
local ReanchorSkillsFrameForGrow
local LayoutSkillBars
local AllowClientFramePosition
local PersistSkillsPoint
local SKILLS_FRAME_NAME = "VitalFrameSkills"

local function GetDB()
    if addonTable and addonTable.GetDB then return addonTable.GetDB() end
    return nil
end

local function ReadFlag(value, default)
    if Compat.ReadFlag then return Compat.ReadFlag(value, default) end
    if value == nil then return default == true end
    return value == true or value == 1
end

local function WriteFlag(enabled)
    if Compat.WriteFlag then return Compat.WriteFlag(enabled) end
    return enabled and 1 or 0
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
    if settings.barHeight == nil then
        settings.barHeight = DEFAULT_SKILLS_BAR_HEIGHT
    end
    if settings.growDirection ~= "up" then settings.growDirection = "down" end
    if settings.shown == nil then settings.shown = 1 end
    if settings.mode ~= "selected" then
        settings.includeAllSkills = true
        settings.mode = "selected"
    end
    if settings.weaponMode ~= "equipped" then settings.weaponMode = "allKnown" end
    if type(settings.selected) ~= "table" then settings.selected = {} end
    return settings
end

local function ClampSkillsWidth(width)
    width = math.floor(tonumber(width) or DEFAULT_SKILLS_WIDTH)
    if width < SKILLS_MIN_WIDTH then width = SKILLS_MIN_WIDTH end
    if width > SKILLS_MAX_WIDTH then width = SKILLS_MAX_WIDTH end
    return width
end

local function ClampSkillsBarHeight(barHeight)
    barHeight = math.floor(tonumber(barHeight) or DEFAULT_SKILLS_BAR_HEIGHT)
    if barHeight < SKILLS_MIN_BAR_HEIGHT then
        barHeight = SKILLS_MIN_BAR_HEIGHT
    end
    if barHeight > SKILLS_MAX_BAR_HEIGHT then
        barHeight = SKILLS_MAX_BAR_HEIGHT
    end
    return barHeight
end

local function GetSavedSkillsWidth()
    local settings = GetSkillsSettings()
    return ClampSkillsWidth(settings and settings.width)
end

local function GetSavedSkillsBarHeight()
    local settings = GetSkillsSettings()
    return ClampSkillsBarHeight(settings and settings.barHeight)
end

local function SkillsEdgeRoom(bottom, top, parentHeight)
    if not bottom or not top or not parentHeight or parentHeight <= 0 then
        return true, true
    end
    local roomDown = bottom > SKILLS_EDGE_FLUSH
    local roomUp = (parentHeight - top) > SKILLS_EDGE_FLUSH
    return roomDown, roomUp
end

local function SavedGrowDirection()
    local settings = GetSkillsSettings()
    if settings and settings.growDirection == "up" then return "up" end
    return "down"
end

local function ResolveGrowDirection(roomDown, roomUp)
    if not roomUp and roomDown then return "down" end
    if not roomDown and roomUp then return "up" end
    return SavedGrowDirection()
end

local function GetSkillsEdgeRoom()
    if not skillsFrame then return true, true end
    local ok, bottom, top = pcall(function()
        return tonumber(skillsFrame:GetBottom()), tonumber(skillsFrame:GetTop())
    end)
    if not ok then return true, true end
    return SkillsEdgeRoom(bottom, top, tonumber(UIParent:GetHeight()) or 0)
end

local function GetSkillsGrowDirection()
    local roomDown, roomUp = GetSkillsEdgeRoom()
    return ResolveGrowDirection(roomDown, roomUp)
end

local function GetSkillsFrameHeightForCount(count, barHeight)
    if count < 1 then count = 1 end
    barHeight = barHeight or GetSavedSkillsBarHeight()
    local gaps = SKILLS_BAR_GAP * math.max(count - 1, 0)
    return (SKILLS_BAR_PADDING * 2) + (barHeight * count) + gaps
end

local function GetSkillsParentSize()
    local width = tonumber(UIParent:GetWidth()) or 0
    local height = tonumber(UIParent:GetHeight()) or 0
    return width, height
end

local function GetSkillsMaxHeightOnScreen()
    local _, parentHeight = GetSkillsParentSize()
    local maxHeight = parentHeight - (SKILLS_SCREEN_INSET * 2)
    local minHeight = (SKILLS_BAR_PADDING * 2) + SKILLS_MIN_BAR_HEIGHT
    if maxHeight < minHeight then maxHeight = minHeight end
    if not skillsFrame then return maxHeight end

    local ok, bottom, top = pcall(function()
        return tonumber(skillsFrame:GetBottom()),
               tonumber(skillsFrame:GetTop())
    end)
    if not ok or not bottom or not top or parentHeight <= 0 then
        return maxHeight
    end

    local available
    if GetSkillsGrowDirection() == "up" then
        available = (parentHeight - SKILLS_SCREEN_INSET) - bottom
    else
        available = top - SKILLS_SCREEN_INSET
    end
    if available and available > 0 and available < maxHeight then
        maxHeight = available
    end
    if maxHeight < minHeight then maxHeight = minHeight end
    return maxHeight
end

local function FitSkillsBarHeightToScreen(count, barHeight)
    local maxHeight = GetSkillsMaxHeightOnScreen()
    local height = GetSkillsFrameHeightForCount(count, barHeight)
    if height <= maxHeight then return barHeight, height end

    local bars = math.max(count, 1)
    local gaps = SKILLS_BAR_GAP * math.max(bars - 1, 0)
    local fitted = math.floor((maxHeight - (SKILLS_BAR_PADDING * 2) - gaps) /
                                  bars)
    fitted = ClampSkillsBarHeight(fitted)
    return fitted, GetSkillsFrameHeightForCount(count, fitted)
end

local function ClampSkillsFrameToScreen()
    if not skillsFrame then return end
    local parentWidth, parentHeight = GetSkillsParentSize()
    if parentWidth <= 0 or parentHeight <= 0 then return end

    local width = tonumber(skillsFrame:GetWidth()) or 0
    local height = tonumber(skillsFrame:GetHeight()) or 0
    local maxWidth = parentWidth - (SKILLS_SCREEN_INSET * 2)
    local maxHeight = parentHeight - (SKILLS_SCREEN_INSET * 2)
    if maxWidth > 0 and width > maxWidth then width = maxWidth end
    if maxHeight > 0 and height > maxHeight then height = maxHeight end

    local ok, left, bottom = pcall(function()
        return tonumber(skillsFrame:GetLeft()),
               tonumber(skillsFrame:GetBottom())
    end)
    if not ok or not left or not bottom then return end

    if left < SKILLS_SCREEN_INSET then left = SKILLS_SCREEN_INSET end
    if left + width > parentWidth - SKILLS_SCREEN_INSET then
        left = parentWidth - SKILLS_SCREEN_INSET - width
    end
    if bottom < 0 then bottom = 0 end
    if bottom + height > parentHeight then
        bottom = parentHeight - height
    end

    local topEdge = bottom + height
    local roomDown, roomUp = SkillsEdgeRoom(bottom, topEdge, parentHeight)
    local direction = ResolveGrowDirection(roomDown, roomUp)
    local settings = GetSkillsSettings()
    if settings then settings.growDirection = direction end
    local growUp = direction == "up"
    local scale = tonumber(skillsFrame:GetScale()) or 1
    if skillsFrame.ClearFrameSnap then skillsFrame:ClearFrameSnap() end
    skillsFrame:ClearAllPoints()
    applyingSkillsSize = true
    skillsFrame:SetSize(width, height)
    if growUp then
        skillsFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        PersistSkillsPoint("BOTTOMLEFT", left, bottom)
    else
        local top = bottom + height
        local y = -((parentHeight - top * scale) / scale)
        skillsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, y)
        PersistSkillsPoint("TOPLEFT", left, y)
    end
    applyingSkillsSize = false
    AllowClientFramePosition()
end

local function SaveSkillsWidth(width)
    local settings = GetSkillsSettings()
    if not settings then return end
    settings.width = ClampSkillsWidth(width)
end

local function SaveSkillsBarHeight(barHeight)
    local settings = GetSkillsSettings()
    if not settings then return end
    settings.barHeight = ClampSkillsBarHeight(barHeight)
end

local function SaveSkillsPosition()
    if not skillsFrame then return end

    local ok, point, x, y = pcall(function()
        local p, _, _, px, py = skillsFrame:GetPoint(1)
        return p, tonumber(px), tonumber(py)
    end)
    if ok and x and y then
        PersistSkillsPoint(point or "CENTER", x, y)
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
    if ok and x and y then PersistSkillsPoint("TOPLEFT", x, y) end
end

AllowClientFramePosition = function(frame)
    frame = frame or skillsFrame
    if not frame or not frame.GetObjectType then return end
    if UI.AllowClientFramePosition then
        UI.AllowClientFramePosition(frame)
        return
    end
    if frame.SetDontSavePosition then
        pcall(frame.SetDontSavePosition, frame, true)
    end
end

PersistSkillsPoint = function(point, x, y, force)
    if addonTable.SaveLayoutPoint then
        addonTable.SaveLayoutPoint("skillsFrame", point, x, y, force)
    end
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
    AllowClientFramePosition()
    PersistSkillsPoint("TOPLEFT", offsetX, offsetY)
    ReanchorSkillsFrameForGrow()
end

function ReanchorSkillsFrameForGrow()
    if not skillsFrame then return end
    local ok, left, bottom, top = pcall(function()
        return tonumber(skillsFrame:GetLeft()),
               tonumber(skillsFrame:GetBottom()),
               tonumber(skillsFrame:GetTop())
    end)
    if not ok or not left then return end

    local growUp = GetSkillsGrowDirection() == "up"
    local parentHeight = tonumber(UIParent:GetHeight()) or 0
    local scale = tonumber(skillsFrame:GetScale()) or 1
    if skillsFrame.ClearFrameSnap then skillsFrame:ClearFrameSnap() end
    skillsFrame:ClearAllPoints()
    if growUp and bottom then
        skillsFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        PersistSkillsPoint("BOTTOMLEFT", left, bottom)
    elseif top then
        local y = -((parentHeight - top * scale) / scale)
        skillsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, y)
        PersistSkillsPoint("TOPLEFT", left, y)
    end
    AllowClientFramePosition()
    ClampSkillsFrameToScreen()
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

local function DisplaySkillName(name)
    if type(name) ~= "string" or name == "" then return name end
    name = name:gsub("[Tt]wo%-%s*[Hh]anded", "2H")
    name = name:gsub("[Tt]wo%s+[Hh]anded", "2H")
    name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function FormatSkillBarLabel(name, rank, maxRank)
    local ok, text = pcall(string.format, L["%s (%d/%d)"],
                           DisplaySkillName(name) or "", rank or 0, maxRank or 0)
    if ok then return text end
    return tostring(rank or 0) .. "/" .. tostring(maxRank or 0)
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

    local label = bar:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER", bar, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
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

local function ClampSkillsPercent(value)
    local n = tonumber(value)
    if not n then return 100 end
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    return math.floor(n + 0.5)
end

local function GetSkillsPercent(key)
    local settings = GetSkillsSettings()
    return ClampSkillsPercent(settings and settings[key])
end

local function GetSkillsBarFont()
    local settings = GetSkillsSettings()
    local id = settings and settings.barFont
    if UI.IsFontChoice and UI.IsFontChoice(id) then return id end
    return "frizqt"
end

local function GetSkillsBarFontSize()
    local settings = GetSkillsSettings()
    local size = math.floor((tonumber(settings and settings.barFontSize) or 12) +
                                0.5)
    if size < 8 then size = 8 end
    if size > 16 then size = 16 end
    return size
end

local function SetSkillsBarFontSize(size)
    local settings = GetSkillsSettings()
    size = math.floor((tonumber(size) or 12) + 0.5)
    if size < 8 then size = 8 end
    if size > 16 then size = 16 end
    if settings then settings.barFontSize = size end
    LayoutSkillBars()
end

local function ApplySkillsChrome()
    if not skillsFrame or not skillsFrame.SetBackdropBorderColor then return end
    local opacity = GetSkillsPercent("frameOpacity") / 100
    skillsFrame:SetBackdropColor(0, 0, 0, 0.5 * opacity)
    local r, g, b, a = GetSharedFrameBorderColor()
    skillsFrame:SetBackdropBorderColor(r, g, b, (a or 1) * opacity)
end

function LayoutSkillBars()
    if not skillsFrame then return end

    local count = #visibleSkills
    local barHeight, height = FitSkillsBarHeightToScreen(count,
                                                        GetSavedSkillsBarHeight())
    local parentWidth = GetSkillsParentSize()
    local width = ClampSkillsWidth(skillsFrame:GetWidth())
    local maxWidth = parentWidth - (SKILLS_SCREEN_INSET * 2)
    if maxWidth > 0 and width > maxWidth then width = maxWidth end
    local usableWidth = width - (SKILLS_BAR_PADDING * 2)
    if usableWidth < 20 then usableWidth = 20 end

    if math.abs((skillsFrame:GetHeight() or 0) - height) > 0.5 or
        math.abs((skillsFrame:GetWidth() or 0) - width) > 0.5 then
        applyingSkillsSize = true
        skillsFrame:SetSize(width, height)
        ReanchorSkillsFrameForGrow()
        applyingSkillsSize = false
    end

    local previousBar
    for index, skill in ipairs(visibleSkills) do
        local bar = AcquireSkillBar(index)
        local color = CATEGORY_COLORS[skill.category] or CATEGORY_COLORS.weapon
        bar:ClearAllPoints()
        bar:SetHeight(barHeight)
        if previousBar then
            bar:SetPoint("TOPLEFT", previousBar, "BOTTOMLEFT", 0, -SKILLS_BAR_GAP)
            bar:SetPoint("TOPRIGHT", previousBar, "BOTTOMRIGHT", 0,
                         -SKILLS_BAR_GAP)
        else
            bar:SetPoint("TOPLEFT", skillsFrame, "TOPLEFT", SKILLS_BAR_PADDING,
                         -SKILLS_BAR_PADDING)
            bar:SetPoint("TOPRIGHT", skillsFrame, "TOPRIGHT",
                         -SKILLS_BAR_PADDING, -SKILLS_BAR_PADDING)
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
            local fontSize = GetSkillsBarFontSize()
            if UI.FitBarLabelSize then
                fontSize = UI.FitBarLabelSize(fontSize, barHeight, 1)
            end
            local fontFile = "Fonts\\FRIZQT__.TTF"
            if UI.GetFontFileById then
                fontFile = UI.GetFontFileById(GetSkillsBarFont())
            end
            bar.LabelText:SetFont(fontFile, fontSize, "")
            if bar.LabelText.SetShadowOffset then
                bar.LabelText:SetShadowOffset(0, 0)
            end
            if bar.LabelText.SetShadowColor then
                bar.LabelText:SetShadowColor(0, 0, 0, 0)
            end
            bar.LabelText:SetText(FormatSkillBarLabel(skill.name, skill.rank,
                                                      skill.maxRank))
        end
        bar:SetAlpha(GetSkillsPercent("contentOpacity") / 100)
        bar:Show()
        previousBar = bar
    end

    for index = count + 1, #skillsBars do
        skillsBars[index]:Hide()
        if skillsBars[index].Divider then skillsBars[index].Divider:Hide() end
        if skillsBars[index].TrainLine then skillsBars[index].TrainLine:Hide() end
    end
end

local function ApplySkillsFrameWidth(width)
    if not skillsFrame then return end
    width = ClampSkillsWidth(width)
    SaveSkillsWidth(width)
    applyingSkillsSize = true
    skillsFrame:SetWidth(width)
    applyingSkillsSize = false
    LayoutSkillBars()
end

local function ApplySkillsBarHeight(barHeight)
    SaveSkillsBarHeight(barHeight)
    LayoutSkillBars()
end

local function ApplySkillsGrowDirection(direction)
    local roomDown, roomUp = GetSkillsEdgeRoom()
    if direction == "up" and not roomUp then return end
    if direction ~= "up" and not roomDown then return end
    local settings = GetSkillsSettings()
    if settings then
        settings.growDirection = direction == "up" and "up" or "down"
    end
    ReanchorSkillsFrameForGrow()
    LayoutSkillBars()
end

local function SetSkillsFrameShown(shouldShow)
    local settings = GetSkillsSettings()
    if settings then settings.shown = WriteFlag(shouldShow) end
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
    local headings = child.Headings or {}
    child.Headings = headings

    local settings = GetSkillsSettings()
    local selected = settings and settings.selected or {}
    local sections = {
        {key = "profession", title = L["Primary Skills"]},
        {key = "secondary", title = L["Secondary Skills"]}
    }
    local grouped = {profession = {}, secondary = {}}
    for _, skill in ipairs(knownSkills) do
        if grouped[skill.category] then
            grouped[skill.category][#grouped[skill.category] + 1] = skill
        end
    end
    for _, skills in pairs(grouped) do
        table.sort(skills, function(a, b)
            local an = DisplaySkillName(a.name) or ""
            local bn = DisplaySkillName(b.name) or ""
            if an == bn then return false end
            if type(strcmputf8i) == "function" then
                return strcmputf8i(an, bn) < 0
            end
            return string.lower(an) < string.lower(bn)
        end)
    end

    local y = 0
    local used = {}
    local checkIndex = 0
    for _, heading in pairs(headings) do heading:Hide() end

    for _, section in ipairs(sections) do
        local skills = grouped[section.key]
        if #skills > 0 then
            local heading = headings[section.key]
            if not heading then
                heading = child:CreateFontString(nil, "OVERLAY",
                                                 "GameFontHighlightMedium")
                heading:SetJustifyH("LEFT")
                headings[section.key] = heading
            end
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            heading:SetFontObject("GameFontHighlightMedium")
            heading:SetText(section.title)
            if heading.SetAlpha then heading:SetAlpha(1) end
            heading:Show()
            y = y + 20

            for _, skill in ipairs(skills) do
                checkIndex = checkIndex + 1
                local check = checks[checkIndex]
                if not check then
                    check = CreateFrame("CheckButton", nil, child,
                                        "UICheckButtonTemplate")
                    check:SetSize(24, 24)
                    local label = check:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
                    label:SetPoint("LEFT", check, "RIGHT", 10, 1)
                    label:SetJustifyH("LEFT")
                    check.Label = label
                    checks[checkIndex] = check
                end
                check:ClearAllPoints()
                check:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
                check.Label:SetFontObject("GameFontHighlight")
                check.Label:SetText(DisplaySkillName(skill.name))
                check:SetChecked(ReadFlag(selected[skill.name], false))
                check:SetEnabled(true)
                if check.SetAlpha then check:SetAlpha(1) end
                check:SetScript("OnClick", function(self)
                    local current = GetSkillsSettings()
                    if not current then return end
                    current.selected = current.selected or {}
                    current.selected[skill.name] = WriteFlag(not ReadFlag(
                                                                 current.selected[skill.name],
                                                                 false))
                    self:SetChecked(ReadFlag(current.selected[skill.name],
                                             false))
                    if addonTable.RefreshSkillsData then
                        addonTable.RefreshSkillsData()
                    end
                end)
                check:Show()
                used[checkIndex] = true
                y = y + 22
            end
            y = y + 6
        end
    end

    for index, check in pairs(checks) do
        if not used[index] then check:Hide() end
    end

    child:SetHeight(math.max(y, 1))
    child:SetWidth(170)
    local scroll = skillsSettingsWidgets.SkillSelectScroll
    if scroll then
        scroll:EnableMouseWheel(true)
        if scroll.SetAlpha then scroll:SetAlpha(1) end
    end
end

local function RefreshSkillsSettings()
    if not skillsSettingsBuilt then return end
    local settings = GetSkillsSettings()
    if not settings then return end

    local width = GetSavedSkillsWidth()
    local barHeight = GetSavedSkillsBarHeight()
    if skillsFrame then
        width = ClampSkillsWidth(skillsFrame:GetWidth())
    end

    if skillsSettingsWidgets.ShowCheck then
        skillsSettingsWidgets.ShowCheck:SetChecked(ReadFlag(settings.shown, true))
    end
    if skillsSettingsWidgets.WeaponAllCheck then
        skillsSettingsWidgets.WeaponAllCheck:SetChecked(settings.weaponMode ~= "equipped")
    end
    if skillsSettingsWidgets.WeaponEquippedCheck then
        skillsSettingsWidgets.WeaponEquippedCheck:SetChecked(
            settings.weaponMode == "equipped")
    end
    local roomDown, roomUp = GetSkillsEdgeRoom()
    local growDirection = GetSkillsGrowDirection()
    if settings.growDirection ~= growDirection then
        settings.growDirection = growDirection
    end
    if skillsSettingsWidgets.GrowDownCheck then
        skillsSettingsWidgets.GrowDownCheck:SetChecked(growDirection ~= "up")
        skillsSettingsWidgets.GrowDownCheck:SetEnabled(roomDown)
    end
    if skillsSettingsWidgets.GrowDownLabel then
        if roomDown then
            skillsSettingsWidgets.GrowDownLabel:SetTextColor(1, 1, 1)
        else
            skillsSettingsWidgets.GrowDownLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    if skillsSettingsWidgets.GrowUpCheck then
        skillsSettingsWidgets.GrowUpCheck:SetChecked(growDirection == "up")
        skillsSettingsWidgets.GrowUpCheck:SetEnabled(roomUp)
    end
    if skillsSettingsWidgets.GrowUpLabel then
        if roomUp then
            skillsSettingsWidgets.GrowUpLabel:SetTextColor(1, 1, 1)
        else
            skillsSettingsWidgets.GrowUpLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    if skillsSettingsWidgets.WidthSlider then
        skillsSettingsWidgets.WidthSlider:SetValue(width)
    end
    if skillsSettingsWidgets.WidthValue then
        skillsSettingsWidgets.WidthValue:SetText(tostring(width))
    end
    if skillsSettingsWidgets.BarHeightSlider then
        skillsSettingsWidgets.BarHeightSlider:SetValue(barHeight)
    end
    if skillsSettingsWidgets.BarHeightValue then
        skillsSettingsWidgets.BarHeightValue:SetText(tostring(barHeight))
    end
    if skillsSettingsWidgets.BarFontButton then
        skillsSettingsWidgets.BarFontButton.Refresh()
    end
    if skillsSettingsWidgets.BarFontSizeButton then
        skillsSettingsWidgets.BarFontSizeButton.Refresh()
    end
    if skillsSettingsWidgets.FrameOpacitySlider then
        skillsSettingsWidgets.FrameOpacitySlider.Refresh()
    end
    if skillsSettingsWidgets.ContentOpacitySlider then
        skillsSettingsWidgets.ContentOpacitySlider.Refresh()
    end
    UpdateSkillSelectList()
end

local function BeginSkillsDrag(frame)
    if UI.SetLayoutFocus then UI.SetLayoutFocus("skills") end
    if UI.AttachEditModeSnapAPI then UI.AttachEditModeSnapAPI(frame) end
    if frame.BreakSnappedFrames then frame:BreakSnappedFrames() end
    if frame.ClearFrameSnap then frame:ClearFrameSnap() end
    frame:StartMoving()
    AllowClientFramePosition()
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
    AllowClientFramePosition()
    ClampSkillsFrameToScreen()
    LayoutSkillBars()
    RefreshSkillsSettings()
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
    settingsPanel:SetSize(480, 500)
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

    local leftColumn = CreateFrame("Frame", nil, settingsPanel)
    leftColumn:SetSize(1, 1)
    leftColumn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -42)
    local rightColumn = CreateFrame("Frame", nil, settingsPanel)
    rightColumn:SetSize(1, 1)
    rightColumn:SetPoint("TOPLEFT", leftColumn, "TOPRIGHT", 180, 0)

    local checkGap = -2

    local selectScroll = CreateFrame("ScrollFrame", nil, settingsPanel)
    selectScroll:SetSize(170, 220)
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
                                                       "GameFontHighlightMedium")
    weaponLabel:SetPoint("TOPLEFT", leftColumn, "TOPLEFT", 0, 0)
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

    selectScroll:SetPoint("TOPLEFT", weaponEquippedCheck, "BOTTOMLEFT", 0, -8)

    local widthLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    widthLabel:SetPoint("TOPLEFT", rightColumn, "TOPLEFT", 0, 0)
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
    widthControl:SetPoint("TOPLEFT", widthLabel, "BOTTOMLEFT", 0, -6)
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
            ApplySkillsFrameWidth(width)
        end
    end)

    local barHeightLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                          "GameFontHighlightMedium")
    barHeightLabel:SetPoint("TOPLEFT", widthControl, "BOTTOMLEFT", 0, -12)
    barHeightLabel:SetText(L["Bar Height"])

    local barHeightControl, barHeightSlider
    if UI.CreateSizeSlider then
        barHeightControl, barHeightSlider = UI.CreateSizeSlider(
                                                "VitalFrameSkillsBarHeightSlider",
                                                settingsPanel)
    end
    if not barHeightSlider then
        barHeightSlider = CreateFrame("Slider",
                                      "VitalFrameSkillsBarHeightSlider",
                                      settingsPanel, "OptionsSliderTemplate")
        barHeightSlider:SetSize(200, 17)
        barHeightControl = barHeightSlider
    end
    barHeightControl:SetPoint("TOPLEFT", barHeightLabel, "BOTTOMLEFT", 0, -6)
    barHeightSlider:SetMinMaxValues(SKILLS_MIN_BAR_HEIGHT,
                                    SKILLS_MAX_BAR_HEIGHT)
    barHeightSlider:SetValueStep(1)
    if barHeightSlider.SetObeyStepOnDrag then
        pcall(barHeightSlider.SetObeyStepOnDrag, barHeightSlider, true)
    end
    local barHeightValue = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                          "GameFontHighlight")
    barHeightValue:SetPoint("LEFT", barHeightControl, "RIGHT", 8, 0)
    barHeightSlider:SetScript("OnValueChanged", function(_, value)
        local barHeight = math.floor(value + 0.5)
        barHeightValue:SetText(tostring(barHeight))
        if GetSavedSkillsBarHeight() ~= barHeight then
            ApplySkillsBarHeight(barHeight)
        end
    end)

    local growDownCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                      "UICheckButtonTemplate")
    growDownCheck:SetPoint("TOPLEFT", barHeightControl, "BOTTOMLEFT", 0, -10)
    local growDownLabel = growDownCheck:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    growDownLabel:SetPoint("LEFT", growDownCheck, "RIGHT", 10, 1)
    growDownLabel:SetText(L["Grow Down"])
    skillsSettingsWidgets.GrowDownLabel = growDownLabel
    growDownCheck:SetScript("OnClick", function()
        ApplySkillsGrowDirection("down")
        RefreshSkillsSettings()
    end)

    local growUpCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                    "UICheckButtonTemplate")
    growUpCheck:SetPoint("TOPLEFT", growDownCheck, "BOTTOMLEFT", 0, checkGap)
    local growUpLabel = growUpCheck:CreateFontString(nil, "OVERLAY",
                                                     "GameFontHighlight")
    growUpLabel:SetPoint("LEFT", growUpCheck, "RIGHT", 10, 1)
    growUpLabel:SetText(L["Grow Up"])
    skillsSettingsWidgets.GrowUpLabel = growUpLabel
    growUpCheck:SetScript("OnClick", function()
        ApplySkillsGrowDirection("up")
        RefreshSkillsSettings()
    end)

    local fontsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    fontsLabel:SetPoint("TOPLEFT", growUpCheck, "BOTTOMLEFT", -10, -12)
    fontsLabel:SetJustifyH("LEFT")
    fontsLabel:SetText(L["Fonts"])

    local barsFontLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    barsFontLabel:SetPoint("TOPLEFT", fontsLabel, "BOTTOMLEFT", 10, -10)
    barsFontLabel:SetJustifyH("LEFT")
    barsFontLabel:SetText(L["Bars"])
    skillsSettingsWidgets.BarFontButton = UI.CreateFontDropdown(settingsPanel,
                                                                barsFontLabel,
                                                                GetSkillsBarFont,
                                                                function(id)
        local settings = GetSkillsSettings()
        if settings then settings.barFont = id end
        LayoutSkillBars()
    end, 176, true)
    if UI.CreateFontSizeDropdown then
        skillsSettingsWidgets.BarFontSizeButton = UI.CreateFontSizeDropdown(
                                                      settingsPanel,
                                                      skillsSettingsWidgets.BarFontButton,
                                                      8, 16, GetSkillsBarFontSize,
                                                      SetSkillsBarFontSize)
    end
    if skillsSettingsWidgets.BarFontSizeButton then
        local barsSizeLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                             "GameFontHighlight")
        barsSizeLabel:SetPoint("BOTTOMLEFT",
                               skillsSettingsWidgets.BarFontSizeButton,
                               "TOPLEFT", 0, 2)
        barsSizeLabel:SetJustifyH("LEFT")
        barsSizeLabel:SetText(L["Size"])
    end

    local opacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                        "GameFontHighlightMedium")
    opacityLabel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -420)
    opacityLabel:SetJustifyH("LEFT")
    opacityLabel:SetText(L["Opacity"])

    local frameOpacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                             "GameFontHighlight")
    frameOpacityLabel:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -8)
    frameOpacityLabel:SetJustifyH("LEFT")
    frameOpacityLabel:SetText(L["Frame Opacity"])
    skillsSettingsWidgets.FrameOpacitySlider = UI.CreatePercentSlider(
                                                   "VitalFrameSkillsFrameOpacitySlider",
                                                   settingsPanel,
                                                   frameOpacityLabel,
                                                   function()
        return GetSkillsPercent("frameOpacity")
    end, function(percent)
        local settings = GetSkillsSettings()
        if settings then settings.frameOpacity = percent end
        ApplySkillsChrome()
    end, 140)

    local contentOpacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                               "GameFontHighlight")
    contentOpacityLabel:SetPoint("TOPLEFT", frameOpacityLabel, "TOPLEFT", 210, 0)
    contentOpacityLabel:SetJustifyH("LEFT")
    contentOpacityLabel:SetText(L["Content Opacity"])
    skillsSettingsWidgets.ContentOpacitySlider = UI.CreatePercentSlider(
                                                     "VitalFrameSkillsContentOpacitySlider",
                                                     settingsPanel,
                                                     contentOpacityLabel,
                                                     function()
        return GetSkillsPercent("contentOpacity")
    end, function(percent)
        local settings = GetSkillsSettings()
        if settings then settings.contentOpacity = percent end
        LayoutSkillBars()
    end, 140)

    local function PlaceSkillsOpacity()
        local top = settingsPanel:GetTop()
        local leftBottom = selectScroll and selectScroll:GetBottom()
        local rightBottom = skillsSettingsWidgets.BarFontButton and
                                skillsSettingsWidgets.BarFontButton:GetBottom()
        if not top or not leftBottom or not rightBottom then return end
        local lowest = math.min(leftBottom, rightBottom)
        opacityLabel:ClearAllPoints()
        opacityLabel:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18,
                              -(top - lowest) - 18)
        local needed = (top - lowest) + 18 + 120
        settingsPanel:SetHeight(math.ceil(needed))
    end
    settingsPanel:HookScript("OnShow", function()
        if Compat and Compat.After then
            Compat.After(0, PlaceSkillsOpacity)
        else
            PlaceSkillsOpacity()
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
    skillsSettingsWidgets.WeaponAllCheck = weaponAllCheck
    skillsSettingsWidgets.WeaponEquippedCheck = weaponEquippedCheck
    skillsSettingsWidgets.GrowDownCheck = growDownCheck
    skillsSettingsWidgets.GrowUpCheck = growUpCheck
    skillsSettingsWidgets.WidthSlider = widthSlider
    skillsSettingsWidgets.WidthValue = widthValue
    skillsSettingsWidgets.BarHeightSlider = barHeightSlider
    skillsSettingsWidgets.BarHeightValue = barHeightValue
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
    local width = GetSavedSkillsWidth()
    local height = GetSkillsFrameHeightForCount(1, GetSavedSkillsBarHeight())

    local frame = CreateFrame("Frame", SKILLS_FRAME_NAME, UIParent,
                             "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
    AllowClientFramePosition(frame)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(false)
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
    ApplySkillsChrome()
    skillsSelection = selection

    frame:SetScript("OnDragStart", function(self)
        if IsEditModeOpen() then BeginSkillsDrag(self) end
    end)
    frame:SetScript("OnDragStop", function(self) FinishSkillsDrag(self) end)
    frame:SetScript("OnSizeChanged", function()
        if applyingSkillsSize then return end
        LayoutSkillBars()
    end)
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

    if not ReadFlag(settings.shown, true) then
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

function UI.SaveSkillsPosition() SaveSkillsPosition() end

function UI.ApplySavedSkillsFrameLayout()
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    local settings = GetSkillsSettings()
    if not settings then return end
    local width = GetSavedSkillsWidth()
    local height = GetSkillsFrameHeightForCount(#visibleSkills,
                                               GetSavedSkillsBarHeight())
    local point, x, y = "CENTER", 180, 0
    if addonTable.GetLayoutPoint then
        local savedPoint, savedX, savedY = addonTable.GetLayoutPoint("skillsFrame")
        if savedPoint then
            point = savedPoint
            x = tonumber(savedX) or 0
            y = tonumber(savedY) or 0
        end
    end
    skillsFrame:ClearAllPoints()
    skillsFrame:SetPoint(point, UIParent, point, x, y)
    AllowClientFramePosition()
    applyingSkillsSize = true
    skillsFrame:SetSize(width, height)
    applyingSkillsSize = false
    ReanchorSkillsFrameForGrow()
    LayoutSkillBars()
    RefreshSkillsSettings()
end

function UI.ResetSkillsFrame()
    if not skillsFrame or not skillsFrame.GetObjectType then return end
    local settings = GetSkillsSettings()
    local width = DEFAULT_SKILLS_WIDTH
    if settings then
        settings.width = width
        settings.barHeight = DEFAULT_SKILLS_BAR_HEIGHT
        settings.growDirection = "down"
        settings.mode = "selected"
        settings.includeAllSkills = nil
        settings.weaponMode = "allKnown"
        settings.selected = {}
        settings.shown = 1
        settings.barFont = "frizqt"
        settings.barFontSize = 12
        settings.frameOpacity = 100
        settings.contentOpacity = 100
    end
    skillsFrame:ClearAllPoints()
    skillsFrame:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
    PersistSkillsPoint("CENTER", 180, 0, true)
    AllowClientFramePosition()
    ApplySkillsFrameWidth(width)
    ApplySkillsBarHeight(DEFAULT_SKILLS_BAR_HEIGHT)
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
    local editModeShown = IsEditModeOpen()
    local focused = UI.GetLayoutFocus and UI.GetLayoutFocus() == "skills"
    local shouldShow = editModeShown and focused and skillsFrame and
                           skillsFrame:IsShown()
    if shouldShow then CreateSkillsSettingsPanel() end
    if not skillsSettingsPanel then return end
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
    return not settings or ReadFlag(settings.shown, true)
end

function UI.SetSkillsFrameShown(shouldShow)
    SetSkillsFrameShown(shouldShow)
end

function UI.ApplySkillsFrameTheme()
    ApplySkillsChrome()
    LayoutSkillBars()
end

UI.CreateSkillsFrame()
