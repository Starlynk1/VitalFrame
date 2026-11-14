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
local BAR_ORDER = {"xpFill", "petXp", "reputation"}

local layoutUnlocked = false

local function IsRetailClient()
    if Compat.IsRetailClient then return Compat.IsRetailClient() end
    if WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
        return true
    end
    return WOW_PROJECT_ID == 1
end

local function SupportsPetXpLeveling()
    if Compat.SupportsPetXpLeveling then
        return Compat.SupportsPetXpLeveling()
    end
    return not IsRetailClient()
end

local function GetSettingsBarOrder()
    local keys = {}
    for _, key in ipairs(BAR_ORDER) do
        if key ~= "petXp" or SupportsPetXpLeveling() then
            keys[#keys + 1] = key
        end
    end
    return keys
end
local runtimeHiddenBars = {}

local BAR_DEFS = {
    xpFill = {label = L["XP"], color = {0.34, 0.69, 0.17}},
    petXp = {label = L["Pet XP"], color = {0.46, 0, 0.68}},
    reputation = {label = L["Reputation"], color = {0.10, 0.70, 0.30}}
}

local FIXED_BAR_HEIGHT = 30
local PET_BAR_HEIGHT = math.floor(FIXED_BAR_HEIGHT * 2 / 3)
local XP_BAR_HEIGHT = math.floor((FIXED_BAR_HEIGHT + PET_BAR_HEIGHT) / 2)
local XP_BAR_KEYS = {xpFill = true, reputation = true}

local DEFAULT_FRAME_WIDTH = 200
local DEFAULT_FRAME_HEIGHT = 200
local FRAME_MIN_WIDTH, FRAME_MAX_WIDTH = 200, 600
local FRAME_MIN_HEIGHT, FRAME_MAX_HEIGHT = 130, 300
local MIN_FIT_BAR_HEIGHT = 4
local LEVEL_MIN_FONT_SIZE = 10

local function GetBaseBarHeight(barKey)
    if XP_BAR_KEYS[barKey] then return XP_BAR_HEIGHT end
    if barKey == "petXp" then return PET_BAR_HEIGHT end
    return FIXED_BAR_HEIGHT
end

local LEVEL_BASE_FONT_SIZE = 60
local LEVEL_TEXT_VERTICAL_PADDING = 5
local NAME_FIRST_FONT_SIZE = 24
local NAME_LAST_FONT_SIZE = 12
local NAME_ICON_SIZE = 22
local NAME_MIN_FONT_SIZE = 8
local VERTICAL_FONT_MAX = 72
-- Level text stays this many points larger than the name and icon.
-- Change this value and /reload to tune it.
local LEVEL_NAME_POINT_GAP = 4
local NAME_ICON_GAP = 8
local NAME_FRAME_INSET = 8
local BAR_REGION_COLOR = {0, 0, 0, 0.68}
local BAR_TRACK_COLOR = {0.18, 0.18, 0.18, 0.35}
local BAR_DIVIDER_COLOR = {1, 1, 1, 0.32}
local BAR_DIVIDER_HEIGHT = 1
local THEME_COLORS = {classic = {1, 1, 1, 1}, forever = {0.83, 0.66, 0.27, 1}}

local UpdateProgressBarLayout
local UpdateEditModeDragState
local CreateVitalFrameSettings

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

local function ClampPercent(value)
    local n = tonumber(value)
    if not n then return 100 end
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    return math.floor(n + 0.5)
end

local function GetFramePercent(key)
    local db = GetDB()
    local frame = db and db.profile and db.profile.frame
    return ClampPercent(frame and frame[key])
end

local function ApplyMainContentOpacity()
    if not vitalFrameFrame then return end
    local alpha = GetFramePercent("contentOpacity") / 100
    local frame = vitalFrameFrame
    if frame.NameText then frame.NameText:SetAlpha(alpha) end
    if frame.LastNameText then frame.LastNameText:SetAlpha(alpha) end
    if frame.LevelText then frame.LevelText:SetAlpha(alpha) end
    if frame.ClassIcon then frame.ClassIcon:SetAlpha(alpha) end
    if frame.ClassIconBorder then frame.ClassIconBorder:SetAlpha(alpha) end
    if frame.BarRegion then frame.BarRegion:SetAlpha(alpha) end
    if frame.ProgressBarsByKey then
        for _, bar in pairs(frame.ProgressBarsByKey) do
            if bar.SetAlpha then bar:SetAlpha(alpha) end
        end
    end
end

local function ApplyFrameTheme()
    local r, g, b, a = GetResolvedThemeColor()
    if vitalFrameFrame and vitalFrameFrame.SetBackdropBorderColor then
        vitalFrameFrame:SetAlpha(GetFramePercent("frameOpacity") / 100)
        vitalFrameFrame:SetBackdropColor(0, 0, 0,
                                         GetFramePercent("backgroundOpacity") /
                                             100)
        vitalFrameFrame:SetBackdropBorderColor(r, g, b, a or 1)
    end
    if UI.ApplySkillsFrameTheme then UI.ApplySkillsFrameTheme() end
    RefreshThemeChecks()
end

local function SetFramePercent(key, percent)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.frame = db.profile.frame or {}
    db.profile.frame[key] = ClampPercent(percent)
    if key == "contentOpacity" then
        ApplyMainContentOpacity()
    else
        ApplyFrameTheme()
    end
end

local function SetTheme(theme)
    local db = GetDB()
    if db and db.profile then db.profile.theme = NormalizeTheme(theme) end
    ApplyFrameTheme()
end

local function GetAutoScaleBars()
    local db = GetDB()
    if not db or not db.profile or not db.profile.bars then return false end
    return ReadFlag(db.profile.bars.autoScale, false)
end

local function SetAutoScaleBars(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.autoScale = WriteFlag(enabled)
    UpdateProgressBarLayout()
end

local barSides = {}

function barSides.Enabled()
    local db = GetDB()
    local bars = db and db.profile and db.profile.bars
    return ReadFlag(bars and bars.vertical, false)
end

function barSides.Side(barKey)
    local db = GetDB()
    local sides = db and db.profile and db.profile.bars and db.profile.bars.side
    local side = sides and sides[barKey]
    if side == "right" or side == "left" then return side end
    if barKey == "reputation" or barKey == "crafting" then return "right" end
    return "left"
end

function barSides.RefreshChecks()
    local panel = vitalFrameSettingsPanel
    if not panel then return end
    if panel.ShowLayoutTab then panel.ShowLayoutTab(barSides.Enabled()) end
    if panel.barSideRefresh then
        for _, refresh in pairs(panel.barSideRefresh) do refresh() end
    end
end

function barSides.SetEnabled(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.vertical = WriteFlag(enabled)
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
end

function barSides.SetSide(barKey, side)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.side = db.profile.bars.side or {}
    db.profile.bars.side[barKey] = side == "right" and "right" or "left"
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
end

function barSides.LevelPlace()
    local db = GetDB()
    local bars = db and db.profile and db.profile.bars
    local place = bars and bars.levelPlace
    if place == "left" or place == "right" or place == "below" then
        return place
    end
    return "below"
end

function barSides.SetLevelPlace(place)
    if place ~= "left" and place ~= "right" then place = "below" end
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.levelPlace = place
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
end

function barSides.NameLines()
    local db = GetDB()
    local bars = db and db.profile and db.profile.bars
    if bars and tonumber(bars.nameLines) == 1 then return 1 end
    return 2
end

function barSides.SetNameLines(lines)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.nameLines = lines == 1 and 1 or 2
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
end

function barSides.Limits()
    if barSides.Enabled() then
        local parentW = 0
        if UIParent and UIParent.GetWidth then
            parentW = tonumber(UIParent:GetWidth()) or 0
        end
        if parentW < 400 then parentW = 1920 end
        local scale = 1
        if vitalFrameFrame and vitalFrameFrame.GetScale then
            scale = tonumber(vitalFrameFrame:GetScale()) or 1
        end
        if scale < 0.5 then scale = 0.5 end
        local maxW = math.floor((parentW / scale) + 0.5)
        if maxW < FRAME_MIN_WIDTH then maxW = FRAME_MIN_WIDTH end
        return FRAME_MIN_WIDTH, maxW, 40, FRAME_MAX_HEIGHT
    end
    return FRAME_MIN_WIDTH, FRAME_MAX_WIDTH, FRAME_MIN_HEIGHT, FRAME_MAX_HEIGHT
end

function barSides.SavedSize()
    local db = GetDB()
    local frame = db and db.profile and db.profile.frame
    local minW, maxW, minH, maxH = barSides.Limits()
    local function Clamp(value, fallback, minSize, maxSize)
        local n = tonumber(value)
        if not n then n = fallback end
        n = math.floor(n + 0.5)
        if n < minSize then n = minSize end
        if n > maxSize then n = maxSize end
        return n
    end
    if barSides.Enabled() then
        return Clamp(frame and frame.verticalWidth, 800, minW, maxW),
               Clamp(frame and frame.verticalHeight, 80, minH, maxH)
    end
    return Clamp(frame and frame.width, DEFAULT_FRAME_WIDTH, minW, maxW),
           Clamp(frame and frame.height, DEFAULT_FRAME_HEIGHT, minH, maxH)
end

local function GetDesiredBarHeight(barKey)
    local base = GetBaseBarHeight(barKey)
    if not GetAutoScaleBars() then return base end

    local height = vitalFrameFrame and vitalFrameFrame:GetHeight() or
                       DEFAULT_FRAME_HEIGHT
    if height <= DEFAULT_FRAME_HEIGHT then return base end
    local scaled = math.floor(base * (height / DEFAULT_FRAME_HEIGHT) + 0.5)
    if scaled < 1 then scaled = 1 end
    return scaled
end

local function IsBarEnabled(barKey)
    local db = GetDB()
    if not db or not db.profile or not db.profile.bars or
        not db.profile.bars.enabled then return true end
    local v = db.profile.bars.enabled[barKey]
    if v == nil then return true end
    return ReadFlag(v, true)
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
    db.profile.bars.enabled[barKey] = WriteFlag(enabled)
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
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
        db.profile.bars.xpFill.useClassColor = 0
    end

    if db.profile.bars.xpFill.hideWhenMaxLevel == nil then
        db.profile.bars.xpFill.hideWhenMaxLevel = 0
    end

    return ReadFlag(db.profile.bars.xpFill[optionKey], false)
end

local function GetHideBlizzardWatchBar()
    local db = GetDB()
    if not db or not db.profile then return true end
    if db.profile.hideBlizzardWatchBar == nil then return true end
    return ReadFlag(db.profile.hideBlizzardWatchBar, true)
end

local function SetHideBlizzardWatchBar(enabled)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.hideBlizzardWatchBar = WriteFlag(enabled)
end

local function GetStreamerMode()
    local db = GetDB()
    if not db or not db.profile then return false end
    return ReadFlag(db.profile.streamerMode, false)
end

local streamerModeActive = false
local targetShowsPlayer = false
local focusShowsPlayer = false
local applyingUnitName = false
local cachedDisplayName
local cachedFirstName
local cachedLastName

local function NameIsPresent(value)
    local ok, missing = pcall(function() return value == nil end)
    if not ok then return true end
    return not missing
end

local function RefreshCachedDisplayName()
    -- Forever UnitName returns the surname as the second value. It is not
    -- part of the first string, and comparing either value can throw.
    if GetStreamerMode() then
        local ok, className = pcall(UnitClass, "player")
        if not ok or not NameIsPresent(className) then return end
        cachedDisplayName = className
        cachedFirstName = className
        cachedLastName = nil
        return
    end

    local ok, name, surname = pcall(UnitName, "player")
    if not ok or not NameIsPresent(name) then return end
    cachedDisplayName = name
    cachedFirstName = name
    if Compat.IsForeverClient and Compat.IsForeverClient() and
        NameIsPresent(surname) then
        cachedLastName = surname
    else
        cachedLastName = nil
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
    db.profile.streamerMode = WriteFlag(enabled)
    streamerModeActive = ReadFlag(db.profile.streamerMode, false)
    RefreshCachedDisplayName()
end

local function GetNameMaxWidth()
    local frameWidth = vitalFrameFrame and vitalFrameFrame:GetWidth() or
                           DEFAULT_FRAME_HEIGHT
    local iconWidth = vitalFrameFrame and vitalFrameFrame.ClassIcon and
                          vitalFrameFrame.ClassIcon:GetWidth() or 22
    local maxWidth = math.floor(
                         frameWidth - (NAME_FRAME_INSET * 2) - iconWidth -
                             NAME_ICON_GAP)
    if vitalFrameFrame and vitalFrameFrame.LayoutNameMaxWidth then
        return vitalFrameFrame.LayoutNameMaxWidth
    end
    if maxWidth < 40 then maxWidth = 40 end
    return maxWidth
end

local function SplitDisplayName(name)
    name = name or ""
    local ok, space = pcall(string.find, name, " ", 1, true)
    if not ok or type(space) ~= "number" then return name, nil end
    local firstName, lastName
    ok, firstName = pcall(string.sub, name, 1, space - 1)
    if not ok or not firstName or firstName == "" then return name, nil end
    ok, lastName = pcall(string.sub, name, space + 1)
    if not ok or not lastName or lastName == "" then return firstName, nil end
    return firstName, lastName
end

local FONT_CANDIDATES = {
    {id = "frizqt", label = "Friz Quadrata", file = "Fonts\\FRIZQT__.TTF"},
    {id = "arialn", label = "Arial Narrow", file = "Fonts\\ARIALN.TTF"},
    {id = "morpheus", label = "Morpheus", file = "Fonts\\MORPHEUS.TTF"},
    {id = "skurri", label = "Skurri", file = "Fonts\\SKURRI.TTF"},
    {id = "2002", label = "2002", file = "Fonts\\2002.TTF"},
    {id = "arhei", label = "AR Hei", file = "Fonts\\ARHei.ttf"},
    {id = "arkai", label = "AR Kai", file = "Fonts\\ARKai_T.ttf"},
    {id = "bhei", label = "bHEI", file = "Fonts\\bHEI00M.TTF"},
    {id = "bheibold", label = "bHEI Bold", file = "Fonts\\bHEI01B.TTF"},
    {id = "bkai", label = "bKAI", file = "Fonts\\bKAI00M.TTF"},
    {id = "blei", label = "bLEI", file = "Fonts\\blei00d.TTF"},
    {id = "damage", label = "Damage", file = "Fonts\\K_Damage.TTF"},
    {id = "pagetext", label = "Page Text", file = "Fonts\\K_Pagetext.TTF"}
}

local Media = addonTable.Media
-- Grouped in one table to stay under Lua 5.1's 200-local limit.
local mediaUI = {}
mediaUI.LSM_FONT_PREFIX = "lsm:"
mediaUI.LSM_GROUP_LABEL = "SharedMedia"

local fontProbe
local function FontFileAvailable(path)
    if type(path) ~= "string" or path == "" then return false end
    if not fontProbe then fontProbe = CreateFont("VitalFrameFontProbe") end
    local ok, result = pcall(fontProbe.SetFont, fontProbe, path, 12, "")
    return ok and result ~= false
end

function mediaUI.NormalizeMediaPath(path)
    return (tostring(path or ""):gsub("/", "\\"):lower())
end

-- These tables are filled in place so closures that captured them stay valid
-- when LibSharedMedia fonts are added later.
local FONT_OPTIONS = {}
local FONT_BY_ID = {}

function mediaUI.RebuildFontOptions()
    wipe(FONT_OPTIONS)
    wipe(FONT_BY_ID)
    local seenFiles = {}

    for _, fontOption in ipairs(FONT_CANDIDATES) do
        if FontFileAvailable(fontOption.file) then
            FONT_OPTIONS[#FONT_OPTIONS + 1] = fontOption
            FONT_BY_ID[fontOption.id] = fontOption
            seenFiles[mediaUI.NormalizeMediaPath(fontOption.file)] = true
        end
    end
    if not FONT_BY_ID.frizqt then
        local fallback = FONT_CANDIDATES[1]
        table.insert(FONT_OPTIONS, 1, fallback)
        FONT_BY_ID.frizqt = fallback
        seenFiles[mediaUI.NormalizeMediaPath(fallback.file)] = true
    end

    if not Media then return end
    for _, name in ipairs(Media.ListFonts()) do
        local file = Media.FetchFont(name)
        local fileKey = mediaUI.NormalizeMediaPath(file)
        -- LSM also registers the stock Blizzard fonts; skip those duplicates.
        if file and not seenFiles[fileKey] and FontFileAvailable(file) then
            local option = {
                id = mediaUI.LSM_FONT_PREFIX .. name,
                label = name,
                file = file,
                group = mediaUI.LSM_GROUP_LABEL
            }
            FONT_OPTIONS[#FONT_OPTIONS + 1] = option
            FONT_BY_ID[option.id] = option
            seenFiles[fileKey] = true
        end
    end
end

mediaUI.RebuildFontOptions()

local function GetFontFileForRole(role)
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    local choice = FONT_BY_ID[fonts and fonts[role]] or FONT_BY_ID.frizqt
    return choice.file
end

local function GetFontChoice(role)
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    local id = fonts and fonts[role]
    if not FONT_BY_ID[id] then return "frizqt" end
    return id
end

local function SetFontChoice(role, id)
    if not FONT_BY_ID[id] then return end
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.fonts = db.profile.fonts or {}
    db.profile.fonts[role] = id
    if vitalFrameFrame then UpdateProgressBarLayout() end
end

-- Status bar textures (LibSharedMedia "statusbar" media) -------------------

mediaUI.DEFAULT_STATUSBAR = Media and Media.DEFAULT_STATUSBAR or "Blizzard"
mediaUI.DEFAULT_STATUSBAR_FILE = Media and Media.DEFAULT_STATUSBAR_FILE or
                                   "Interface\\TargetingFrame\\UI-StatusBar"

function mediaUI.IsStatusbarChoice(name)
    if Media then return Media.IsStatusbar(name) end
    return name == mediaUI.DEFAULT_STATUSBAR
end

function mediaUI.GetStatusbarFile(name)
    if Media then return Media.FetchStatusbar(name) end
    return mediaUI.DEFAULT_STATUSBAR_FILE
end

function mediaUI.ApplyStatusBarTexture(bar, file)
    if not bar or not bar.SetStatusBarTexture then return end
    file = file or mediaUI.DEFAULT_STATUSBAR_FILE
    if bar.vitalFrameTextureFile == file then return end
    -- Keep the fill colour; older clients store it on the texture object.
    local r, g, b, a
    if bar.GetStatusBarColor then r, g, b, a = bar:GetStatusBarColor() end
    bar:SetStatusBarTexture(file)
    if r and bar.SetStatusBarColor then bar:SetStatusBarColor(r, g, b, a) end
    bar.vitalFrameTextureFile = file
end

function mediaUI.GetBarTextureChoice()
    local db = GetDB()
    local textures = db and db.profile and db.profile.textures
    local name = textures and textures.bars
    if mediaUI.IsStatusbarChoice(name) then return name end
    return mediaUI.DEFAULT_STATUSBAR
end

function mediaUI.ApplyMainBarTextures()
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then return end
    local file = mediaUI.GetStatusbarFile(mediaUI.GetBarTextureChoice())
    for _, bar in pairs(vitalFrameFrame.ProgressBarsByKey) do
        mediaUI.ApplyStatusBarTexture(bar, file)
        if bar.BgFill then mediaUI.ApplyStatusBarTexture(bar.BgFill, file) end
    end
end

function mediaUI.SetBarTextureChoice(name)
    if not mediaUI.IsStatusbarChoice(name) then return end
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.textures = db.profile.textures or {}
    db.profile.textures.bars = name
    mediaUI.ApplyMainBarTextures()
end

local fontMetrics = {}

function fontMetrics.clamp(value, minValue, maxValue, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    n = math.floor(n + 0.5)
    if n < minValue then n = minValue end
    if n > maxValue then n = maxValue end
    return n
end

function fontMetrics.nameSize()
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    return fontMetrics.clamp(fonts and fonts.nameSize, NAME_MIN_FONT_SIZE,
                            NAME_FIRST_FONT_SIZE, NAME_FIRST_FONT_SIZE)
end

function fontMetrics.verticalNameSize()
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    return fontMetrics.clamp(fonts and fonts.verticalNameSize, NAME_MIN_FONT_SIZE,
                            VERTICAL_FONT_MAX, NAME_FIRST_FONT_SIZE)
end

function fontMetrics.verticalLevelSize()
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    return fontMetrics.clamp(fonts and fonts.verticalLevelSize, NAME_MIN_FONT_SIZE,
                            VERTICAL_FONT_MAX, 32)
end

function fontMetrics.lastPercent()
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    return fontMetrics.clamp(fonts and fonts.lastNamePercent, 25, 100, 50)
end

function fontMetrics.barSize()
    local db = GetDB()
    local fonts = db and db.profile and db.profile.fonts
    return fontMetrics.clamp(fonts and fonts.barSize, 8, 16, 12)
end

function fontMetrics.set(key, value)
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.fonts = db.profile.fonts or {}
    db.profile.fonts[key] = value
    if vitalFrameFrame then UpdateProgressBarLayout() end
end

function fontMetrics.lastSize(nameSize)
    local size = math.floor((tonumber(nameSize) or fontMetrics.nameSize()) *
                                fontMetrics.lastPercent() / 100)
    if size < 1 then size = 1 end
    return size
end

function fontMetrics.iconSize(nameSize, nameMax)
    if nameSize < nameMax then return nameSize end
    local full = math.floor(nameMax * NAME_ICON_SIZE / NAME_FIRST_FONT_SIZE +
                                0.5)
    if full < NAME_MIN_FONT_SIZE then full = NAME_MIN_FONT_SIZE end
    return full
end

function fontMetrics.fitBar(maxSize, barHeight, pad)
    maxSize = fontMetrics.clamp(maxSize, 8, 16, 12)
    local size = math.floor((tonumber(barHeight) or maxSize) - (pad or 2))
    if size > maxSize then size = maxSize end
    if size < 8 then size = 8 end
    if size > maxSize then size = maxSize end
    return size
end

local ownedFonts = {}

local function ClearTextShadow(fontString)
    if fontString.SetShadowOffset then fontString:SetShadowOffset(0, 0) end
    if fontString.SetShadowColor then fontString:SetShadowColor(0, 0, 0, 0) end
end

local function ApplyPlainFont(fontString, file, size)
    if not fontString then return end
    size = math.floor(tonumber(size) or 12)
    if size < 1 then size = 1 end
    fontString:SetFont(file or "Fonts\\FRIZQT__.TTF", size, "")
    ClearTextShadow(fontString)
end

local function ApplyOwnedFont(fontString, key, size)
    if not fontString or not key then return end
    size = math.floor(tonumber(size) or 12)
    if size < 1 then size = 1 end
    local role = "name"
    if key == "Level" then role = "level" end
    local font = ownedFonts[key]
    if not font then
        font = CreateFont("VitalFrameFont" .. key)
        ownedFonts[key] = font
    end
    font:SetFont(GetFontFileForRole(role), size, "")
    if font.SetFontHeight then pcall(font.SetFontHeight, font, size) end
    fontString:SetFontObject(font)
    ClearTextShadow(fontString)
end

local currentNamePointSize = NAME_FIRST_FONT_SIZE

local function StringPixels(fontString, methodName, fallback)
    if not fontString or not fontString[methodName] then return fallback end
    local ok, value = pcall(fontString[methodName], fontString)
    value = ok and tonumber(value) or nil
    if not value then return fallback end
    return math.ceil(value)
end

local function UpdateHeaderLayout(nameSize)
    if not vitalFrameFrame or not vitalFrameFrame.NameText or
        not vitalFrameFrame.ClassIcon then return end

    local nameMax = fontMetrics.nameSize()
    if barSides.Enabled() then nameMax = fontMetrics.verticalNameSize() end
    nameSize = tonumber(nameSize) or currentNamePointSize
    if nameSize > nameMax then nameSize = nameMax end
    if nameSize < NAME_MIN_FONT_SIZE then nameSize = NAME_MIN_FONT_SIZE end
    currentNamePointSize = nameSize

    local lastSize = fontMetrics.lastSize(nameSize)
    local iconSize = fontMetrics.iconSize(nameSize, nameMax)

    local nameText = vitalFrameFrame.NameText
    local lastNameText = vitalFrameFrame.LastNameText
    local classIcon = vitalFrameFrame.ClassIcon
    classIcon:SetSize(iconSize, iconSize)
    local maxWidth = GetNameMaxWidth()
    RefreshCachedDisplayName()
    local firstName = cachedFirstName or L["Character"]
    local lastName = cachedLastName
    local oneLine = barSides.Enabled() and barSides.NameLines() == 1
    if oneLine and NameIsPresent(lastName) then
        local combinedOk, combined = pcall(function()
            return firstName .. " " .. lastName
        end)
        if combinedOk and NameIsPresent(combined) then
            firstName = combined
            lastName = nil
        end
    end
    local singleLine = oneLine and not NameIsPresent(lastName)

    ApplyOwnedFont(nameText, "Name", nameSize)
    nameText:SetWidth(maxWidth)
    nameText:SetWordWrap(not singleLine)
    nameText:SetNonSpaceWrap(not singleLine)
    nameText:SetJustifyH("LEFT")
    nameText:SetJustifyV("TOP")
    nameText:SetText(firstName)
    if singleLine then
        local width = StringPixels(nameText, "GetStringWidth", maxWidth)
        while nameSize > NAME_MIN_FONT_SIZE and width > maxWidth do
            nameSize = nameSize - 1
            currentNamePointSize = nameSize
            iconSize = fontMetrics.iconSize(nameSize, nameMax)
            classIcon:SetSize(iconSize, iconSize)
            ApplyOwnedFont(nameText, "Name", nameSize)
            nameText:SetText(firstName)
            width = StringPixels(nameText, "GetStringWidth", maxWidth)
        end
    end

    -- Show the last name before measuring. GetStringWidth throws on Forever
    -- secret values and was aborting this function before the second line.
    if lastNameText then
        if NameIsPresent(lastName) then
            ApplyOwnedFont(lastNameText, "LastName", lastSize)
            lastNameText:SetWidth(maxWidth)
            lastNameText:SetWordWrap(true)
            lastNameText:SetNonSpaceWrap(true)
            lastNameText:SetJustifyH("LEFT")
            lastNameText:SetJustifyV("TOP")
            lastNameText:SetText(lastName)
            lastNameText:Show()
        else
            lastNameText:SetText("")
            lastNameText:Hide()
        end
    end

    local nameWidth = StringPixels(nameText, "GetStringWidth", maxWidth)
    if nameWidth > maxWidth then nameWidth = maxWidth end
    local nameHeight = nameSize
    if lastNameText and lastNameText:IsShown() then
        local lastWidth = StringPixels(lastNameText, "GetStringWidth", maxWidth)
        if lastWidth > maxWidth then lastWidth = maxWidth end
        if lastWidth > nameWidth then nameWidth = lastWidth end
        nameHeight = nameHeight + lastSize
    end

    local headerHeight = math.max(classIcon:GetHeight(), nameHeight)
    if vitalFrameFrame.HeaderGroup then
        vitalFrameFrame.HeaderGroup:SetSize(
            classIcon:GetWidth() + NAME_ICON_GAP + nameWidth, headerHeight)
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
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
            return
        end
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
        HookNameFontString(TargetFrame.name,
                           function() return targetShowsPlayer end)
    end
    if FocusFrame and FocusFrame.name then
        HookNameFontString(FocusFrame.name,
                           function() return focusShowsPlayer end)
    end

    HookCompactUnitFrameName()

    local nameEventFrame = CreateFrame("Frame")
    local registerNameEvent = Compat.RegisterEvent or
                                  function(frame, event)
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
            if unit and NameEqualsPlayer(unit) then
                ApplyStreamerUnitNames()
            end
        end)
    end)

    blizzardNameHooked = true
end

local function UpdateNameText()
    local function apply()
        RefreshCachedDisplayName()
        if vitalFrameFrame and vitalFrameFrame.NameText then
            UpdateHeaderLayout()
        end
        if vitalFrameFrame then UpdateProgressBarLayout() end
    end
    -- Read the name on the next frame so a secret UnitName is not compared.
    if Compat.After then
        Compat.After(0, apply)
    else
        apply()
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
    db.profile.bars.xpFill[optionKey] = WriteFlag(enabled)
end

local function GetReputationAutoSwitch()
    local db = GetDB()
    if not db or not db.profile then return true end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.reputation = db.profile.bars.reputation or {}
    if db.profile.bars.reputation.autoSwitch == nil then
        db.profile.bars.reputation.autoSwitch = 1
    end
    return ReadFlag(db.profile.bars.reputation.autoSwitch, true)
end

local function SetReputationAutoSwitch(enabled)
    local db = GetDB()
    if not db or not db.profile then return end

    db.profile.bars = db.profile.bars or {}
    db.profile.bars.reputation = db.profile.bars.reputation or {}
    db.profile.bars.reputation.autoSwitch = WriteFlag(enabled)
end

local function SetBarPercent(barKey, percent)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then
        return
    end
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
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then
        return
    end
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
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then
        return
    end
    local bar = vitalFrameFrame.ProgressBarsByKey[barKey]
    if not bar or not bar.LabelText then return end
    bar.LabelText:SetText(text or "")
    if barSides.Refit then barSides.Refit(bar) end
end

local function SetLevelText(level)
    if not vitalFrameFrame or not vitalFrameFrame.LevelText then return end
    local n = tonumber(level)
    if not n then n = UnitLevel("player") end
    if not n then return end
    vitalFrameFrame.LevelText:SetText(tostring(n))
end

local function SetBarBackgroundPercent(barKey, percent)
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then
        return
    end
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

local MAIN_FRAME_NAME = "VitalFrameMain"

local function FrameHasReadablePosition(frame)
    if not frame then return false end
    local ok, left = pcall(function() return tonumber(frame:GetLeft()) end)
    return ok and left ~= nil
end

local function AllowClientFramePosition(frame)
    frame = frame or vitalFrameFrame
    if not frame then return end
    -- The client drops a named frame's position when the addon is disabled.
    -- SavedVariables own the position, so the client must not keep a copy.
    if frame.SetDontSavePosition then
        pcall(frame.SetDontSavePosition, frame, true)
    end
end

local ParentTopLeftOffset

local function ActiveFrameLayoutKind()
    if barSides.Enabled() then return "frameVertical" end
    return "frame"
end

local function SaveFramePositionFromOffsets(x, y)
    if addonTable.SaveLayoutPoint then
        addonTable.SaveLayoutPoint(ActiveFrameLayoutKind(), "TOPLEFT", x, y)
    end
end

local function SaveFramePosition()
    if not vitalFrameFrame or not addonTable.SaveLayoutPoint then return end

    local ok, point, x, y = pcall(function()
        local p, _, _, px, py = vitalFrameFrame:GetPoint(1)
        return p, tonumber(px), tonumber(py)
    end)
    if ok and x ~= nil and y ~= nil then
        addonTable.SaveLayoutPoint(ActiveFrameLayoutKind(), point or "TOPLEFT",
                                   x, y)
        return
    end

    ok, x, y = pcall(function()
        return ParentTopLeftOffset(vitalFrameFrame)
    end)
    if ok and x ~= nil and y ~= nil then SaveFramePositionFromOffsets(x, y) end
end

local function SaveFrameSize(width, height)
    local db = GetDB()
    if not db or not db.profile or not db.profile.frame then return end

    if barSides.Enabled() then
        db.profile.frame.verticalWidth = math.floor(width or 800)
        db.profile.frame.verticalHeight = math.floor(height or 80)
    else
        db.profile.frame.width = math.floor(width or 200)
        db.profile.frame.height = math.floor(height or 200)
    end
end

local EDIT_MODE_SNAP_METHODS = {
    "IsToTheLeftOfFrame", "IsToTheRightOfFrame", "IsAboveFrame", "IsBelowFrame",
    "IsVerticallyAlignedWithFrame", "IsHorizontallyAlignedWithFrame",
    "GetScaledSelectionCenter", "GetScaledCenter", "GetScaledSelectionSides",
    "GetLeftOffset", "GetRightOffset", "GetTopOffset", "GetBottomOffset",
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
    return frame and frame.GetFrameMagneticEligibility and
               frame.GetScaledSelectionSides
end

local function BakeFrameToUIParent(deltaX, deltaY)
    if not vitalFrameFrame then return end

    local ok, offsetX, offsetY = pcall(function()
        local x, y = ParentTopLeftOffset(vitalFrameFrame)
        if x == nil or y == nil then return nil end
        return x + (deltaX or 0), y + (deltaY or 0)
    end)
    if not ok or offsetX == nil then return end

    if vitalFrameFrame.ClearFrameSnap then vitalFrameFrame:ClearFrameSnap() end
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", offsetX, offsetY)
    AllowClientFramePosition(vitalFrameFrame)
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
    local isArrow = key == "UP" or key == "DOWN" or key == "LEFT" or key ==
                        "RIGHT"
    local handle = layoutFocus ~= nil and IsEditModeOpen() and isArrow
    if self.SetPropagateKeyboardInput then
        pcall(self.SetPropagateKeyboardInput, self, not handle)
    end
    if handle then ProcessNudgeKey(key) end
end

local function UpdateNudgeKeyboard()
    local mainActive = layoutFocus == "main" and IsEditModeOpen() or false
    local skillsActive = layoutFocus == "skills" and IsEditModeOpen() or false
    if vitalFrameFrame then vitalFrameFrame:EnableKeyboard(mainActive) end
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
    AllowClientFramePosition(frame)
    SaveFramePosition()
end

function barSides.ApplyLabel(bar, _, barWidth, barHeight)
    local label = bar.LabelText
    if not label then return end

    local function FitLabelFont(file, maxSize, crossSize, alongSize)
        local size = fontMetrics.fitBar(maxSize, crossSize, 4)
        ApplyPlainFont(label, file, size)
        local width = StringPixels(label, "GetStringWidth", alongSize)
        while size > 8 and width > alongSize do
            size = size - 1
            ApplyPlainFont(label, file, size)
            width = StringPixels(label, "GetStringWidth", alongSize)
        end
    end

    local along = barWidth - 8
    local cross = barHeight - 2
    if along < 8 then along = 8 end
    if cross < 8 then cross = 8 end
    label:ClearAllPoints()
    label:SetWordWrap(false)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    if label.SetRotation then label:SetRotation(0) end
    FitLabelFont(GetFontFileForRole("bars"), fontMetrics.barSize(), cross, along)
    label:SetSize(along, barHeight)
    label:SetPoint("CENTER", bar, "CENTER", 0, 0)
end

function barSides.Orient(bar, orientation)
    if bar.SetOrientation then bar:SetOrientation(orientation) end
    if bar.BgFill and bar.BgFill.SetOrientation then
        bar.BgFill:SetOrientation(orientation)
    end
end

function barSides.Layout()
    local frame = vitalFrameFrame
    local inset = 4
    local frameW = frame:GetWidth()
    local frameH = frame:GetHeight()
    local innerW = frameW - (inset * 2)
    local innerH = frameH - (inset * 2)
    if innerW < 40 then innerW = 40 end
    if innerH < 16 then innerH = 16 end

    local leftKeys, rightKeys = {}, {}
    for _, key in ipairs(BAR_ORDER) do
        local bar = frame.ProgressBarsByKey[key]
        if bar then
            if ShouldShowBar(key) then
                if barSides.Side(key) == "right" then
                    rightKeys[#rightKeys + 1] = key
                else
                    leftKeys[#leftKeys + 1] = key
                end
            else
                barSides.Orient(bar, "HORIZONTAL")
            end
        end
    end

    local nameSize = fontMetrics.verticalNameSize()
    local place = barSides.LevelPlace()
    local oneLine = barSides.NameLines() == 1
    RefreshCachedDisplayName()
    local firstName = cachedFirstName or L["Character"]
    local lastName = cachedLastName
    local nameW = 80
    if frame.NameText then
        ApplyOwnedFont(frame.NameText, "Name", nameSize)
        frame.NameText:SetWidth(1000)
        if oneLine and NameIsPresent(lastName) then
            local combinedOk, combined = pcall(function()
                return firstName .. " " .. lastName
            end)
            if combinedOk and NameIsPresent(combined) then
                frame.NameText:SetText(combined)
                lastName = nil
            else
                frame.NameText:SetText(firstName)
            end
        else
            frame.NameText:SetText(firstName)
        end
        nameW = StringPixels(frame.NameText, "GetStringWidth", 80)
    end
    local textH = nameSize
    if NameIsPresent(lastName) and frame.LastNameText then
        local lastSize = fontMetrics.lastSize(nameSize)
        ApplyOwnedFont(frame.LastNameText, "LastName", lastSize)
        frame.LastNameText:SetWidth(1000)
        frame.LastNameText:SetText(lastName)
        local lastW = StringPixels(frame.LastNameText, "GetStringWidth", nameW)
        if lastW > nameW then nameW = lastW end
        textH = textH + lastSize
    end

    local icon = fontMetrics.iconSize(nameSize, nameSize)
    local headerW = icon + NAME_ICON_GAP + nameW
    local headerH = icon
    if textH > headerH then headerH = textH end

    local levelSize = fontMetrics.verticalLevelSize()
    local levelW = 24
    if frame.LevelText then
        ApplyOwnedFont(frame.LevelText, "Level", levelSize)
        levelW = StringPixels(frame.LevelText, "GetStringWidth", 24)
        if levelW < 12 then levelW = 12 end
    end

    local centerW = headerW + 12
    if place == "left" or place == "right" then
        centerW = headerW + 8 + levelW + 12
    elseif levelW + 12 > centerW then
        centerW = levelW + 12
    end

    local sideCount = 0
    if #leftKeys > 0 then sideCount = sideCount + 1 end
    if #rightKeys > 0 then sideCount = sideCount + 1 end
    if sideCount == 0 then
        centerW = innerW
    else
        local maxCenter = innerW - (sideCount * 80)
        if maxCenter < 50 then maxCenter = 50 end
        if centerW > maxCenter then centerW = maxCenter end
    end
    if centerW < 40 then centerW = 40 end
    if centerW > innerW then centerW = innerW end

    local leftover = innerW - centerW
    if leftover < 0 then leftover = 0 end
    local leftW, rightW = 0, 0
    if #leftKeys > 0 and #rightKeys > 0 then
        leftW = leftover / 2
        rightW = leftover - leftW
    elseif #leftKeys > 0 then
        leftW = leftover
    elseif #rightKeys > 0 then
        rightW = leftover
    end

    local function Stack(keys, width, fromLeft)
        local count = #keys
        if count == 0 or width < 4 then return end
        local barH = innerH / count
        if barH < 1 then barH = 1 end
        for index, key in ipairs(keys) do
            local bar = frame.ProgressBarsByKey[key]
            bar:ClearAllPoints()
            bar:SetSize(width, barH)
            barSides.Orient(bar, "HORIZONTAL")
            local y = -inset - ((index - 1) * barH)
            if fromLeft then
                bar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, y)
            else
                bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, y)
            end
            barSides.ApplyLabel(bar, false, width, barH)
        end
    end
    Stack(leftKeys, leftW, true)
    Stack(rightKeys, rightW, false)

    local nameMax = centerW - icon - NAME_ICON_GAP - 8
    if place == "left" or place == "right" then
        nameMax = nameMax - levelW - 8
    end
    if nameMax < 40 then nameMax = 40 end
    local centerLeft = inset + leftW
    frame.LayoutCenterWidth = centerW
    frame.LayoutCenterOffset = (centerLeft + (centerW / 2)) - (frameW / 2)
    frame.LayoutNameMaxWidth = nameMax

    if frame.BarRegion then frame.BarRegion:Hide() end
end

function barSides.Refit(bar)
    if not bar or not barSides.Enabled() then return end
    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if not width or not height or width < 8 or height < 8 then return end
    barSides.ApplyLabel(bar, false, width, height)
end

UpdateProgressBarLayout = function()
    if not vitalFrameFrame or not vitalFrameFrame.ProgressBarsByKey then
        return
    end

    local borderInset = 4
    local bottomPadding = (vitalFrameFrame.ProgressBottomPadding or 0) +
                              borderInset
    local usableWidth = vitalFrameFrame:GetWidth() - (borderInset * 2)
    local frameHeight = vitalFrameFrame:GetHeight()
    RefreshCachedDisplayName()
    local hasLastName = NameIsPresent(cachedLastName)
    if barSides.Enabled() and barSides.NameLines() == 1 then
        hasLastName = false
    end

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

    -- Keep the bar budget on the full-size header. A shrunk name must not
    -- hand that freed space back to the bars.
    local nameMax = fontMetrics.nameSize()
    local headerReserve = 10 + nameMax
    if hasLastName then
        headerReserve = headerReserve + fontMetrics.lastSize(nameMax)
    end
    local minLevelSpace = LEVEL_MIN_FONT_SIZE +
                              (LEVEL_TEXT_VERTICAL_PADDING * 2)
    local desiredBarsHeight = 0
    for _, key in ipairs(enabledKeys) do
        desiredBarsHeight = desiredBarsHeight + GetDesiredBarHeight(key)
    end
    local maxBarsHeight = frameHeight - bottomPadding - headerReserve -
                              minLevelSpace
    if barCount > 0 and maxBarsHeight < (MIN_FIT_BAR_HEIGHT * barCount) then
        maxBarsHeight = MIN_FIT_BAR_HEIGHT * barCount
    end
    local fitScale = 1
    if desiredBarsHeight > 0 and maxBarsHeight > 0 and desiredBarsHeight >
        maxBarsHeight then fitScale = maxBarsHeight / desiredBarsHeight end

    local function GetFittedBarHeight(barKey)
        local height = math.floor(GetDesiredBarHeight(barKey) * fitScale + 0.5)
        if height < MIN_FIT_BAR_HEIGHT then height = MIN_FIT_BAR_HEIGHT end
        return height
    end

    local vertical = barSides.Enabled()
    local firstVisibleBar = nil
    local topPadding = frameHeight - bottomPadding
    if vertical then
        barSides.Layout()
        topPadding = frameHeight
    else
        vitalFrameFrame.LayoutCenterWidth = nil
        vitalFrameFrame.LayoutCenterOffset = nil
        vitalFrameFrame.LayoutNameMaxWidth = nil

        if barCount >= 1 then
            local barsHeight = 0
            for _, key in ipairs(enabledKeys) do
                barsHeight = barsHeight + GetFittedBarHeight(key)
            end

            topPadding = frameHeight - bottomPadding - barsHeight
            if topPadding < borderInset then topPadding = borderInset end

            local previousBar = nil
            for _, key in ipairs(BAR_ORDER) do
                local bar = vitalFrameFrame.ProgressBarsByKey[key]
                if bar and ShouldShowBar(key) then
                    bar:ClearAllPoints()
                    local barHeight = GetFittedBarHeight(key)
                    bar:SetSize(usableWidth, barHeight)
                    barSides.Orient(bar, "HORIZONTAL")
                    barSides.ApplyLabel(bar, false, usableWidth, barHeight)
                    if not previousBar then
                        firstVisibleBar = bar
                        bar:SetPoint("TOP", vitalFrameFrame, "TOP", 0,
                                     -topPadding)
                    else
                        bar:SetPoint("TOP", previousBar, "BOTTOM", 0, 0)
                    end
                    previousBar = bar
                elseif bar then
                    barSides.Orient(bar, "HORIZONTAL")
                end
            end
        end

        if vitalFrameFrame.BarRegion then
            if firstVisibleBar then
                vitalFrameFrame.BarRegion:ClearAllPoints()
                vitalFrameFrame.BarRegion:SetPoint("TOPLEFT", firstVisibleBar,
                                                   "TOPLEFT", 0, 0)
                vitalFrameFrame.BarRegion:SetPoint("BOTTOMRIGHT",
                                                   vitalFrameFrame,
                                                   "BOTTOMRIGHT", -borderInset,
                                                   borderInset)
                vitalFrameFrame.BarRegion:Show()
            else
                vitalFrameFrame.BarRegion:Hide()
            end
        end
    end

    if vitalFrameFrame.LevelText and vitalFrameFrame.NameText then
        local function HeaderHeightFor(nameSize)
            local textHeight = nameSize
            if hasLastName then
                textHeight = textHeight + fontMetrics.lastSize(nameSize)
            end
            local iconSize = fontMetrics.iconSize(nameSize, nameMax)
            if iconSize > textHeight then return iconSize end
            return textHeight
        end

        -- Room above the bars, under the header inset, for the name plus level.
        local nameSize
        local levelSize
        if barSides.Enabled() then
            nameSize = fontMetrics.verticalNameSize()
            levelSize = fontMetrics.verticalLevelSize()
        else
            local room = topPadding - 10 - (LEVEL_TEXT_VERTICAL_PADDING * 2)
            if room < LEVEL_MIN_FONT_SIZE then room = LEVEL_MIN_FONT_SIZE end

            nameSize = nameMax
            levelSize = room - HeaderHeightFor(nameSize)
            local gap = LEVEL_NAME_POINT_GAP
            if levelSize < nameSize + gap then
                local lastShare = 0
                if hasLastName then
                    lastShare = fontMetrics.lastPercent() / 100
                end
                levelSize = math.floor((room + ((1 + lastShare) * gap)) /
                                           (2 + lastShare))
                nameSize = levelSize - gap
            end
            if nameSize > nameMax then nameSize = nameMax end
            if nameSize < NAME_MIN_FONT_SIZE then
                nameSize = NAME_MIN_FONT_SIZE
            end
            if levelSize < nameSize + gap then levelSize = nameSize + gap end
            if levelSize < LEVEL_MIN_FONT_SIZE then
                levelSize = LEVEL_MIN_FONT_SIZE
            end
        end

        UpdateHeaderLayout(nameSize)
        ApplyOwnedFont(vitalFrameFrame.LevelText, "Level", levelSize)

        -- Hang the level under the names. A centered anchor draws half the
        -- glyphs upward and was covering the Forever last name.
        local headerHeight = HeaderHeightFor(nameSize)
        if vitalFrameFrame.LastNameText and
            vitalFrameFrame.LastNameText:IsShown() then
            local shownHeight = nameSize + fontMetrics.lastSize(nameSize)
            if shownHeight > headerHeight then headerHeight = shownHeight end
        end
        vitalFrameFrame.LevelText:SetJustifyH("CENTER")
        vitalFrameFrame.LevelText:SetJustifyV("TOP")
        vitalFrameFrame.LevelText:ClearAllPoints()
        local header = vitalFrameFrame.HeaderGroup
        if barSides.Enabled() then
            local place = barSides.LevelPlace()
            local offsetX = vitalFrameFrame.LayoutCenterOffset or 0
            local centerWidth = vitalFrameFrame.LayoutCenterWidth or usableWidth
            local gap = 2
            local pad = 1
            if place == "left" or place == "right" then
                ApplyOwnedFont(vitalFrameFrame.LevelText, "Level", levelSize)
                local blockH = headerHeight
                if levelSize > blockH then blockH = levelSize end
                local top = math.floor((frameHeight - blockH) / 2)
                if top < 0 then top = 0 end
                local levelW = StringPixels(vitalFrameFrame.LevelText,
                                            "GetStringWidth", centerWidth)
                if levelW < 12 then levelW = 12 end
                local shift = (gap + levelW) / 2
                if place == "right" then shift = -shift end
                if header then
                    header:ClearAllPoints()
                    header:SetPoint("TOP", vitalFrameFrame, "TOP",
                                    offsetX + shift, -top)
                end
                vitalFrameFrame.LevelText:SetWidth(levelW)
                vitalFrameFrame.LevelText:SetJustifyV("MIDDLE")
                if place == "right" then
                    vitalFrameFrame.LevelText:SetJustifyH("LEFT")
                    if header then
                        vitalFrameFrame.LevelText:SetPoint("LEFT", header,
                                                          "RIGHT", gap, 0)
                    end
                else
                    vitalFrameFrame.LevelText:SetJustifyH("RIGHT")
                    if header then
                        vitalFrameFrame.LevelText:SetPoint("RIGHT", header,
                                                          "LEFT", -gap, 0)
                    end
                end
            else
                ApplyOwnedFont(vitalFrameFrame.LevelText, "Level", levelSize)
                local block = headerHeight + pad + levelSize
                local top = math.floor((frameHeight - block) / 2)
                if top < 0 then top = 0 end
                if header then
                    header:ClearAllPoints()
                    header:SetPoint("TOP", vitalFrameFrame, "TOP", offsetX, -top)
                end
                vitalFrameFrame.LevelText:SetWidth(math.max(40, centerWidth))
                vitalFrameFrame.LevelText:SetPoint("TOP", vitalFrameFrame, "TOP",
                                                   offsetX,
                                                   -(top + headerHeight + pad))
            end
        else
            if header then
                header:ClearAllPoints()
                header:SetPoint("TOP", vitalFrameFrame, "TOP", 0, -10)
            end
            vitalFrameFrame.LevelText:SetWidth(usableWidth)
            vitalFrameFrame.LevelText:SetPoint("TOP", vitalFrameFrame, "TOP", 0,
                                               -(10 + headerHeight +
                                                   LEVEL_TEXT_VERTICAL_PADDING))
        end
    end

    ApplyMainContentOpacity()
end

local function ApplyFrameSize(width, height)
    if not vitalFrameFrame then return end

    local minW, maxW, minH, maxH = barSides.Limits()
    local w = math.max(minW, math.min(maxW, math.floor(width or
                                                           vitalFrameFrame:GetWidth())))
    local h = math.max(minH, math.min(maxH, math.floor(height or
                                                           vitalFrameFrame:GetHeight())))

    vitalFrameFrame:SetSize(w, h)
    UpdateProgressBarLayout()
    SaveFrameSize(w, h)
end

function barSides.SyncSizeSliders()
    local panel = vitalFrameSettingsPanel
    if not panel or not panel.widthSlider or not panel.heightSlider then return end
    local minW, maxW, minH, maxH = barSides.Limits()
    local w, h = barSides.SavedSize()
    panel.sizing = true
    panel.widthSlider:SetMinMaxValues(minW, maxW)
    panel.heightSlider:SetMinMaxValues(minH, maxH)
    panel.widthSlider:SetValue(w)
    panel.heightSlider:SetValue(h)
    panel.sizing = false
    if panel.widthValueText then
        panel.widthValueText:SetText(tostring(math.floor(w)))
    end
    if panel.heightValueText then
        panel.heightValueText:SetText(tostring(math.floor(h)))
    end
end

function barSides.Select(vertical)
    local enabled = vertical and true or false
    if barSides.Enabled() ~= enabled then
        SaveFramePosition()
    end
    local db = GetDB()
    if not db or not db.profile then return end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.vertical = WriteFlag(enabled)
    local w, h = barSides.SavedSize()
    ApplyFrameSize(w, h)
    if vitalFrameFrame and addonTable.GetLayoutPoint then
        local point, x, y = addonTable.GetLayoutPoint(ActiveFrameLayoutKind())
        if point then
            vitalFrameFrame:ClearAllPoints()
            vitalFrameFrame:SetPoint(point, UIParent, point, tonumber(x) or 0,
                                     tonumber(y) or 0)
            AllowClientFramePosition(vitalFrameFrame)
        else
            SaveFramePosition()
        end
    end
    barSides.RefreshChecks()
end

local function ClampSizeValue(value, minSize, maxSize)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n + 0.5)
    if n < minSize then n = minSize end
    if n > maxSize then n = maxSize end
    return n
end

local FRAME_SCALE_MIN = 0.5
local FRAME_SCALE_MAX = 2
local FRAME_SCALE_STEP = 0.05

local function ClampFrameScale(value)
    local n = tonumber(value) or 1
    if n < FRAME_SCALE_MIN then n = FRAME_SCALE_MIN end
    if n > FRAME_SCALE_MAX then n = FRAME_SCALE_MAX end
    local steps = math.floor((n / FRAME_SCALE_STEP) + 0.5)
    return steps * FRAME_SCALE_STEP
end

local function GetSavedFrameScale()
    local db = GetDB()
    local frameSettings = db and db.profile and db.profile.frame
    return ClampFrameScale(frameSettings and frameSettings.scale)
end

local function ScaleAroundCenter(frame, newScale)
    if not frame then return nil end
    local oldScale = tonumber(frame:GetScale()) or 1
    if math.abs(oldScale - newScale) < 0.001 then return nil end

    local point, relativeTo, relativePoint, x, y, centerX, centerY
    local ok, readPoint, readRelative, readRelativePoint, readX, readY,
        readCenterX, readCenterY = pcall(function()
        local p, rel, relPoint, px, py = frame:GetPoint(1)
        local gx, gy = frame:GetCenter()
        return p, rel, relPoint, tonumber(px), tonumber(py), tonumber(gx),
               tonumber(gy)
    end)
    if ok then
        point, relativeTo, relativePoint = readPoint, readRelative,
                                            readRelativePoint
        x, y, centerX, centerY = readX, readY, readCenterX, readCenterY
    end
    frame:SetScale(newScale)
    if x == nil or y == nil or centerX == nil or centerY == nil then
        return nil
    end
    local newCenterX, newCenterY = frame:GetCenter()
    newCenterX, newCenterY = tonumber(newCenterX), tonumber(newCenterY)
    if newCenterX == nil or newCenterY == nil then return nil end
    local newX = x + (centerX * oldScale) - (newCenterX * newScale)
    local newY = y + (centerY * oldScale) - (newCenterY * newScale)
    point = point or "CENTER"
    relativePoint = relativePoint or point
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo or UIParent, relativePoint, newX, newY)
    return point, newX, newY
end

local function ApplyFrameScale(scale)
    scale = ClampFrameScale(scale)
    local db = GetDB()
    if db and db.profile and db.profile.frame then
        db.profile.frame.scale = scale
    end
    if not vitalFrameFrame then return scale end
    local point, x, y = ScaleAroundCenter(vitalFrameFrame, scale)
    if point and addonTable.SaveLayoutPoint then
        addonTable.SaveLayoutPoint(ActiveFrameLayoutKind(), point, x, y)
    end
    if barSides.Enabled() and vitalFrameFrame then
        local w, h = barSides.SavedSize()
        ApplyFrameSize(w, h)
    end
    barSides.SyncSizeSliders()
    return scale
end

UI.ScaleAroundCenter = ScaleAroundCenter

-- Matches EditModeSystemMixin:BreakFrameSnap. GetLeft is already a
-- SetPoint x. GetTop is converted with the frame scale, then the
-- TOPLEFT y is divided by that scale again.
ParentTopLeftOffset = function(frame)
    local scale = tonumber(frame:GetScale()) or 1
    if scale == 0 then scale = 1 end
    local left = tonumber(frame:GetLeft())
    local top = tonumber(frame:GetTop())
    local parentHeight = tonumber(UIParent:GetHeight()) or 0
    if left == nil or top == nil then return nil end
    return left, -((parentHeight - (top * scale)) / scale)
end

UI.ClampFrameScale = ClampFrameScale

local SETTINGS_SLIDER_WIDTH = 200

local function CreateSizeSlider(name, parent, width)
    width = width or SETTINGS_SLIDER_WIDTH
    local ok, control = pcall(CreateFrame, "Frame", name, parent,
                              "MinimalSliderWithSteppersTemplate")
    if ok and control and control.Slider then
        control:SetSize(width, 32)
        if control.MinText then control.MinText:Hide() end
        if control.MaxText then control.MaxText:Hide() end
        if control.TopText then control.TopText:Hide() end
        if control.LeftText then control.LeftText:Hide() end
        if control.RightText then control.RightText:Hide() end
        return control, control.Slider
    end

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetSize(width, 17)
    slider:SetOrientation("HORIZONTAL")
    if slider.SetObeyStepOnDrag then
        pcall(slider.SetObeyStepOnDrag, slider, true)
    end
    local text = _G[name .. "Text"]
    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    if text then text:SetText("") end
    if low then low:SetText("") end
    if high then high:SetText("") end
    return slider, slider
end

local fontDropdownSerial = 0
mediaUI.mediaDropdownSerial = 0
mediaUI.MEDIA_MENU_MAX_HEIGHT = 360
mediaUI.CLASSIC_MENU_PAGE_SIZE = 25

local function FontChoiceLabel(getId)
    local choice = FONT_BY_ID[getId()] or FONT_OPTIONS[1]
    return choice.label
end

local previewFonts = {}
mediaUI.previewFontSerial = 0

local function PreviewFontObject(option, size)
    if not option then return nil end
    size = size or 14
    local key = tostring(option.file) .. "|" .. tostring(size)
    local font = previewFonts[key]
    if font then return font end
    mediaUI.previewFontSerial = mediaUI.previewFontSerial + 1
    font = CreateFont("VitalFramePreview" .. mediaUI.previewFontSerial)
    local ok, result = pcall(font.SetFont, font, option.file, size, "")
    if not ok or result == false then return nil end
    previewFonts[key] = font
    return font
end

function mediaUI.SetClosedDropdownText(dropdown, text)
    if not dropdown then return end
    text = text or ""
    if dropdown.SetDefaultText then dropdown:SetDefaultText(text) end
    if dropdown.Text then dropdown.Text:SetText(text) end
    if dropdown.GetName and dropdown:GetName() and UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, text)
    end
end

local function ApplyClosedDropdownFont(dropdown, option)
    if not dropdown or not option then return end
    local fontObject = PreviewFontObject(option, 12)
    mediaUI.SetClosedDropdownText(dropdown, option.label)
    if dropdown.Text and fontObject then
        dropdown.Text:SetFontObject(fontObject)
        dropdown.Text:SetText(option.label)
    end
    local frameName = dropdown.GetName and dropdown:GetName()
    local classicText = frameName and _G[frameName .. "Text"]
    if classicText and fontObject and classicText ~= dropdown.Text then
        classicText:SetFontObject(fontObject)
    end
end

-- spec fields:
--   options()            -> array of {id, label, file, group?}
--   selected()           -> the selected option (or nil)
--   select(option)       -> store the choice
--   applyClosed(dd, opt) -> optional, draws the closed dropdown
--   initRow(button, opt) -> optional, decorates a modern menu row
--   classicInfo(info, opt) -> optional, decorates a classic menu row
function mediaUI.RefreshMediaDropdown(dropdown, spec)
    local option = spec.selected()
    if spec.applyClosed then
        spec.applyClosed(dropdown, option)
    else
        mediaUI.SetClosedDropdownText(dropdown, option and option.label)
    end
end

function mediaUI.CreateModernMediaDropdown(parent, label, spec, width, below)
    if not MenuUtil then return nil end
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent,
                               "WowStyle1DropdownTemplate")
    if not ok or not dropdown or not dropdown.SetupMenu then return nil end

    dropdown:SetWidth(width or 170)
    if below then
        dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    else
        dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    end

    hooksecurefunc(dropdown, "OnMenuOpened", function(_, menu)
        if not menu then return end
        if menu.SetFrameStrata then menu:SetFrameStrata("TOOLTIP") end
        if menu.SetToplevel then menu:SetToplevel(true) end
        if menu.SetFrameLevel then pcall(menu.SetFrameLevel, menu, 2000) end
    end)

    dropdown.Refresh = function() mediaUI.RefreshMediaDropdown(dropdown, spec) end

    dropdown:SetupMenu(function(_, rootDescription)
        if not rootDescription.CreateButton then return end
        if rootDescription.SetScrollMode then
            rootDescription:SetScrollMode(mediaUI.MEDIA_MENU_MAX_HEIGHT)
        end
        local lastGroup
        local first = true
        for _, option in ipairs(spec.options()) do
            if option.group and option.group ~= lastGroup then
                if not first and rootDescription.CreateDivider then
                    rootDescription:CreateDivider()
                end
                if rootDescription.CreateTitle then
                    rootDescription:CreateTitle(option.group)
                end
            end
            lastGroup = option.group
            first = false
            local row = rootDescription:CreateButton(option.label, function()
                spec.select(option)
                if Compat.After then
                    Compat.After(0, dropdown.Refresh)
                else
                    dropdown.Refresh()
                end
            end)
            if row and row.AddInitializer then
                row:AddInitializer(function(button)
                    if spec.initRow then spec.initRow(button, option) end
                    if button.HookScript and not button.vitalFrameKeepsFocus then
                        button.vitalFrameKeepsFocus = true
                        button:HookScript("OnMouseDown", function()
                            suppressNextFocusClear = true
                        end)
                    end
                    return 220, 24
                end)
            end
        end
    end)

    dropdown.Refresh()
    return dropdown
end

function mediaUI.CreateClassicMediaDropdown(parent, label, spec, width, below)
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then
        return nil
    end
    mediaUI.mediaDropdownSerial = mediaUI.mediaDropdownSerial + 1
    local dropdown = CreateFrame("Frame", "VitalFrameMediaDropdown" ..
                                     mediaUI.mediaDropdownSerial, parent,
                                 "UIDropDownMenuTemplate")
    if below then
        dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -2)
    else
        dropdown:SetPoint("LEFT", label, "RIGHT", -16, -2)
    end
    UIDropDownMenu_SetWidth(dropdown, (width or 170) - 20)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")

    dropdown.Refresh = function() mediaUI.RefreshMediaDropdown(dropdown, spec) end

    local function AddOption(option, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.label
        info.notCheckable = true
        if spec.classicInfo then spec.classicInfo(info, option) end
        info.func = function()
            spec.select(option)
            dropdown.Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(dropdown, function(_, level, menuList)
        level = level or 1
        local options = spec.options()

        -- Large SharedMedia collections overflow the classic menu, so split
        -- them into alphabetical pages shown as submenus.
        if #options <= mediaUI.CLASSIC_MENU_PAGE_SIZE then
            if level == 1 then
                for _, option in ipairs(options) do AddOption(option, 1) end
            end
            return
        end

        if level == 1 then
            for first = 1, #options, mediaUI.CLASSIC_MENU_PAGE_SIZE do
                local last = math.min(first + mediaUI.CLASSIC_MENU_PAGE_SIZE - 1,
                                      #options)
                local info = UIDropDownMenu_CreateInfo()
                info.text = options[first].label .. " - " .. options[last].label
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = first
                UIDropDownMenu_AddButton(info, 1)
            end
            return
        end

        local first = tonumber(menuList) or 1
        local last = math.min(first + mediaUI.CLASSIC_MENU_PAGE_SIZE - 1, #options)
        for index = first, last do AddOption(options[index], level) end
    end)

    dropdown.Refresh()
    return dropdown
end

function mediaUI.CreateMediaDropdown(parent, label, spec, width, below)
    return mediaUI.CreateModernMediaDropdown(parent, label, spec, width, below) or
               mediaUI.CreateClassicMediaDropdown(parent, label, spec, width, below)
end

local function CreateFontDropdown(parent, label, getId, setId, width, below)
    return mediaUI.CreateMediaDropdown(parent, label, {
        options = function() return FONT_OPTIONS end,
        selected = function() return FONT_BY_ID[getId()] or FONT_OPTIONS[1] end,
        select = function(option) setId(option.id) end,
        applyClosed = ApplyClosedDropdownFont,
        initRow = function(button, option)
            local fontObject = PreviewFontObject(option, 14)
            if button.fontString and fontObject then
                button.fontString:SetFontObject(fontObject)
            end
        end,
        classicInfo = function(info, option)
            info.fontObject = PreviewFontObject(option, 14)
        end
    }, width, below)
end

mediaUI.TEXTURE_PREVIEW_COLOR = {0.34, 0.69, 0.17, 0.75}

function mediaUI.StatusbarOptions()
    local options = {}
    if Media then
        for _, entry in ipairs(Media.ListStatusbars()) do
            options[#options + 1] = {
                id = entry.name,
                label = entry.name,
                file = entry.file
            }
        end
    end
    if #options == 0 then
        options[1] = {
            id = mediaUI.DEFAULT_STATUSBAR,
            label = mediaUI.DEFAULT_STATUSBAR,
            file = mediaUI.DEFAULT_STATUSBAR_FILE
        }
    end
    return options
end

function mediaUI.CreateTextureDropdown(parent, label, getName, setName, width,
                                     below)
    return mediaUI.CreateMediaDropdown(parent, label, {
        options = mediaUI.StatusbarOptions,
        selected = function()
            local name = getName()
            return {id = name, label = name, file = mediaUI.GetStatusbarFile(name)}
        end,
        select = function(option) setName(option.id) end,
        initRow = function(button, option)
            -- AttachTexture regions are released with the row, so pooled
            -- menu buttons never keep a stale preview.
            if not button.AttachTexture then return end
            local ok, texture = pcall(button.AttachTexture, button)
            if not ok or not texture then return end
            texture:SetDrawLayer("BACKGROUND")
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -3)
            texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
            texture:SetTexture(option.file)
            texture:SetVertexColor(mediaUI.TEXTURE_PREVIEW_COLOR[1],
                                   mediaUI.TEXTURE_PREVIEW_COLOR[2],
                                   mediaUI.TEXTURE_PREVIEW_COLOR[3],
                                   mediaUI.TEXTURE_PREVIEW_COLOR[4])
        end
    }, width, below)
end

function fontMetrics.applyClosedSizeText(dropdown, size)
    local text = tostring(size)
    if dropdown.SetDefaultText then dropdown:SetDefaultText(text) end
    if dropdown.Text then dropdown.Text:SetText(text) end
    if dropdown.GetName and dropdown:GetName() and UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropdown, text)
    end
end

function fontMetrics.raiseOpenMenu(menu)
    if not menu then return end
    if menu.SetFrameStrata then menu:SetFrameStrata("TOOLTIP") end
    if menu.SetToplevel then menu:SetToplevel(true) end
    if menu.SetFrameLevel then pcall(menu.SetFrameLevel, menu, 2000) end
end

function fontMetrics.keepMenuRowFocus(button)
    if not button or not button.HookScript or button.vitalFrameKeepsFocus then
        return
    end
    button.vitalFrameKeepsFocus = true
    button:HookScript("OnMouseDown", function()
        suppressNextFocusClear = true
    end)
end

function fontMetrics.modernSizeDropdown(parent, relativeTo, minSize, maxSize,
                                        getSize, setSize)
    if not MenuUtil or not relativeTo then return nil end
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent,
                               "WowStyle1DropdownTemplate")
    if not ok or not dropdown or not dropdown.SetupMenu then return nil end

    dropdown:SetWidth(68)
    dropdown:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", 6, 0)
    hooksecurefunc(dropdown, "OnMenuOpened", function(_, menu)
        local function fit()
            fontMetrics.raiseOpenMenu(menu)
            if menu.SetMinimumWidth then menu:SetMinimumWidth(36) end
            if menu.SetWidth then menu:SetWidth(44) end
        end
        fit()
        if Compat.After then Compat.After(0, fit) end
    end)

    dropdown:SetupMenu(function(_, rootDescription)
        if rootDescription.SetMinimumWidth then
            rootDescription:SetMinimumWidth(36)
        end
        if not rootDescription.CreateButton then return end
        for size = minSize, maxSize do
            local picked = size
            local row = rootDescription:CreateButton(tostring(picked),
                                                     function()
                setSize(picked)
                local function apply()
                    fontMetrics.applyClosedSizeText(dropdown, getSize())
                end
                if Compat.After then
                    Compat.After(0, apply)
                else
                    apply()
                end
            end)
            if row and row.AddInitializer then
                row:AddInitializer(function(button)
                    fontMetrics.keepMenuRowFocus(button)
                    return 28, 20
                end)
            end
        end
    end)

    dropdown.Refresh = function()
        fontMetrics.applyClosedSizeText(dropdown, getSize())
    end
    dropdown.Refresh()
    return dropdown
end

function fontMetrics.classicSizeDropdown(parent, relativeTo, minSize, maxSize,
                                         getSize, setSize)
    if not relativeTo or not UIDropDownMenu_Initialize or
        not UIDropDownMenu_SetText then return nil end
    fontDropdownSerial = fontDropdownSerial + 1
    local dropdown = CreateFrame("Frame", "VitalFrameFontSizeDropdown" ..
                                     fontDropdownSerial, parent,
                                 "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", -12, 0)
    UIDropDownMenu_SetWidth(dropdown, 36)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    UIDropDownMenu_Initialize(dropdown, function()
        for size = minSize, maxSize do
            local picked = size
            local info = UIDropDownMenu_CreateInfo()
            info.text = tostring(picked)
            info.notCheckable = true
            info.func = function()
                setSize(picked)
                fontMetrics.applyClosedSizeText(dropdown, getSize())
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    dropdown.Refresh = function()
        fontMetrics.applyClosedSizeText(dropdown, getSize())
    end
    dropdown.Refresh()
    return dropdown
end

function fontMetrics.sizeDropdown(parent, relativeTo, minSize, maxSize, getSize,
                                  setSize)
    return fontMetrics.modernSizeDropdown(parent, relativeTo, minSize, maxSize,
                                          getSize, setSize) or
               fontMetrics.classicSizeDropdown(parent, relativeTo, minSize,
                                               maxSize, getSize, setSize)
end

local function HideSliderCaptions(control)
    if not control then return end
    if control.MinText then control.MinText:Hide() end
    if control.MaxText then control.MaxText:Hide() end
    if control.TopText then control.TopText:Hide() end
    if control.LeftText then control.LeftText:Hide() end
    if control.RightText then control.RightText:Hide() end
end

local function CreatePercentSlider(name, parent, label, getPercent, setPercent,
                                    width)
    local control, slider = CreateSizeSlider(name, parent,
                                             width or SETTINGS_SLIDER_WIDTH)
    control:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        pcall(slider.SetObeyStepOnDrag, slider, true)
    end
    HideSliderCaptions(control)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("LEFT", control, "RIGHT", 8, 0)
    valueText:SetJustifyH("LEFT")

    local function Refresh()
        local percent = getPercent()
        valueText:SetText(percent .. "%")
        if slider:GetValue() ~= percent then slider:SetValue(percent) end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        local percent = ClampPercent(value)
        valueText:SetText(percent .. "%")
        if getPercent() ~= percent then setPercent(percent) end
    end)

    control.Refresh = Refresh
    Refresh()
    return control
end

local function CreateScaleSlider(name, parent, label, getScale, setScale, width)
    local control, slider = CreateSizeSlider(name, parent,
                                             width or SETTINGS_SLIDER_WIDTH)
    control:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    slider:SetMinMaxValues(FRAME_SCALE_MIN * 100, FRAME_SCALE_MAX * 100)
    slider:SetValueStep(FRAME_SCALE_STEP * 100)
    if slider.SetObeyStepOnDrag then
        pcall(slider.SetObeyStepOnDrag, slider, true)
    end
    HideSliderCaptions(control)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("LEFT", control, "RIGHT", 8, 0)
    valueText:SetJustifyH("LEFT")

    local function Refresh()
        local percent = math.floor(ClampFrameScale(getScale()) * 100 + 0.5)
        valueText:SetText(percent .. "%")
        if slider:GetValue() ~= percent then slider:SetValue(percent) end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        local percent = math.floor((tonumber(value) or 100) + 0.5)
        local scale = ClampFrameScale(percent / 100)
        percent = math.floor(scale * 100 + 0.5)
        valueText:SetText(percent .. "%")
        if math.abs(ClampFrameScale(getScale()) - scale) >= 0.001 then
            setScale(scale)
        end
    end)

    control.Refresh = Refresh
    Refresh()
    return control
end

local function SetSelectionVisual(isSelected)
    if not vitalFrameSelection or not vitalFrameSelection.Background then
        return
    end

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
        vitalFrameSettingsPanel:SetPoint("TOPLEFT", vitalFrameFrame, "TOPRIGHT",
                                         12, 0)
    end
end

local function UpdateSettingsPanelVisibility()
    if not vitalFrameFrame then return end

    local editModeShown = IsEditModeOpen()
    local shouldShow = editModeShown and layoutFocus == "main" and
                           vitalFrameFrame:IsShown()
    if shouldShow and not vitalFrameSettingsPanel then
        CreateVitalFrameSettings(vitalFrameFrame)
    end
    if not vitalFrameSettingsPanel then return end
    if shouldShow then AnchorSettingsPanel() end

    vitalFrameSettingsPanel:SetShown(shouldShow)

    if shouldShow then
        barSides.SyncSizeSliders()
        if vitalFrameSettingsPanel.nameFontButton then
            vitalFrameSettingsPanel.nameFontButton.Refresh()
        end
        if vitalFrameSettingsPanel.levelFontButton then
            vitalFrameSettingsPanel.levelFontButton.Refresh()
        end
        if vitalFrameSettingsPanel.barsFontButton then
            vitalFrameSettingsPanel.barsFontButton.Refresh()
        end
        if vitalFrameSettingsPanel.barTextureButton then
            vitalFrameSettingsPanel.barTextureButton.Refresh()
        end
        if vitalFrameSettingsPanel.nameSizeButton then
            vitalFrameSettingsPanel.nameSizeButton.Refresh()
        end
        if vitalFrameSettingsPanel.barSizeButton then
            vitalFrameSettingsPanel.barSizeButton.Refresh()
        end
        if vitalFrameSettingsPanel.RefreshLastNamePercent then
            vitalFrameSettingsPanel.RefreshLastNamePercent()
        end
        if vitalFrameSettingsPanel.frameOpacitySlider then
            vitalFrameSettingsPanel.frameOpacitySlider.Refresh()
        end
        if vitalFrameSettingsPanel.backgroundOpacitySlider then
            vitalFrameSettingsPanel.backgroundOpacitySlider.Refresh()
        end
        if vitalFrameSettingsPanel.contentOpacitySlider then
            vitalFrameSettingsPanel.contentOpacitySlider.Refresh()
        end
        if vitalFrameSettingsPanel.scaleSlider then
            vitalFrameSettingsPanel.scaleSlider.Refresh()
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
    barSides.RefreshChecks()

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
    if which ~= "main" and which ~= "skills" then which = nil end
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
        db.profile.frame.shown = WriteFlag(shouldShow)
    end
    UpdateEditModeDragState()
    ApplyBlizzardWatchBarVisibility()
end

local function ApplySavedFrameLayout()
    if not vitalFrameFrame then return end
    local db = GetDB()
    local frameSettings = db and db.profile and db.profile.frame
    if not frameSettings then return end

    vitalFrameFrame:SetScale(GetSavedFrameScale())
    local width, height = barSides.SavedSize()
    vitalFrameFrame:SetSize(width, height)
    local point, x, y = "CENTER", 0, 0
    if addonTable.GetLayoutPoint then
        local savedPoint, savedX, savedY =
            addonTable.GetLayoutPoint(ActiveFrameLayoutKind())
        if savedPoint then
            point, x, y = savedPoint, tonumber(savedX) or 0, tonumber(savedY) or 0
        end
    end
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint(point, UIParent, point, x, y)
    AllowClientFramePosition(vitalFrameFrame)
    if addonTable.MarkLayoutReady then addonTable.MarkLayoutReady() end
    UpdateProgressBarLayout()
    if UI.ApplySavedSkillsFrameLayout then UI.ApplySavedSkillsFrameLayout() end
end

local function ApplySavedSettings()
    local db = GetDB()
    if not db or not db.profile then return end

    if UI.ScheduleApplySavedFrameLayout then
        UI.ScheduleApplySavedFrameLayout()
    else
        ApplySavedFrameLayout()
    end
    ApplyFrameTheme()

    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.characterPositionCheck then
        vitalFrameSettingsPanel.characterPositionCheck:SetChecked(
            addonTable.UsesOwnLayout and addonTable.UsesOwnLayout())
    end

    streamerModeActive = ReadFlag(db.profile.streamerMode, false)
    ApplyStreamerUnitNames()
    ApplyBlizzardWatchBarVisibility()

    if db.profile.frame and not ReadFlag(db.profile.frame.shown, true) then
        if vitalFrameFrame then vitalFrameFrame:Hide() end
    elseif vitalFrameFrame then
        vitalFrameFrame:Show()
    end

    if UI.SetSkillsFrameShown then
        local showSkills = true
        if db.profile.skillsFrame then
            showSkills = ReadFlag(db.profile.skillsFrame.shown, true)
        end
        UI.SetSkillsFrameShown(showSkills)
    end

    mediaUI.ApplyMainBarTextures()
    UpdateProgressBarLayout()
    if UI.UpdateSkillsFrameEditMode then UI.UpdateSkillsFrameEditMode() end
    if vitalFrameSettingsPanel then UpdateSettingsPanelVisibility() end
    if UI.RefreshSkillsSettings then UI.RefreshSkillsSettings() end
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
    local db = GetDB()
    if db and db.profile then
        db.profile.bars = db.profile.bars or {}
        db.profile.bars.vertical = false
        db.profile.bars.levelPlace = "below"
        db.profile.bars.nameLines = 2
        db.profile.bars.side = {
            xpFill = "left",
            petXp = "left",
            reputation = "right",
            crafting = "right"
        }
        db.profile.frame = db.profile.frame or {}
        db.profile.frame.verticalWidth = 800
        db.profile.frame.verticalHeight = 80
    end
    vitalFrameFrame:ClearAllPoints()
    vitalFrameFrame:SetPoint("CENTER")
    ApplyFrameSize(200, 200)
    AllowClientFramePosition(vitalFrameFrame)
    if addonTable.SaveLayoutPoint then
        addonTable.SaveLayoutPoint("frame", "CENTER", 0, 0, true)
        addonTable.SaveLayoutPoint("frameVertical", "CENTER", 240, 0, true)
        addonTable.SaveLayoutPoint("skillsFrame", "CENTER", 180, 0, true)
    end
    SaveFramePosition()
    if UI.ApplySavedSkillsFrameLayout then UI.ApplySavedSkillsFrameLayout() end
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.widthValueText then
        vitalFrameSettingsPanel.widthValueText:SetText("200")
    end
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.heightValueText then
        vitalFrameSettingsPanel.heightValueText:SetText("200")
    end
    local db = GetDB()
    if db and db.profile then
        db.profile.theme = "auto"
        db.profile.fonts = {
            name = "frizqt",
            level = "frizqt",
            bars = "frizqt",
            nameSize = NAME_FIRST_FONT_SIZE,
            verticalNameSize = NAME_FIRST_FONT_SIZE,
            verticalLevelSize = 32,
            lastNamePercent = 50,
            barSize = 12
        }
        db.profile.textures = {bars = mediaUI.DEFAULT_STATUSBAR}
        db.profile.frame = db.profile.frame or {}
        db.profile.frame.frameOpacity = 100
        db.profile.frame.backgroundOpacity = 100
        db.profile.frame.contentOpacity = 100
        db.profile.frame.scale = 1
    end
    ApplyFrameScale(1)
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.scaleSlider and
        vitalFrameSettingsPanel.scaleSlider.Refresh then
        vitalFrameSettingsPanel.scaleSlider.Refresh()
    end
    ApplyFrameTheme()
    mediaUI.ApplyMainBarTextures()
    if vitalFrameSettingsPanel and vitalFrameSettingsPanel.barTextureButton then
        vitalFrameSettingsPanel.barTextureButton.Refresh()
    end
    UpdateProgressBarLayout()
    barSides.RefreshChecks()
end

function barSides.BuildVerticalSection(panel, topAnchor)
    local section = CreateFrame("Frame", nil, panel)
    section:SetWidth(250)
    section:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", -16, -8)
    local y = -2

    local function AddLabel(text)
        local label = section:CreateFontString(nil, "OVERLAY",
                                               "GameFontHighlight")
        label:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        y = y - 18
    end

    local function AddChoice(parent, previous, text)
        local check = CreateFrame("CheckButton", nil, parent,
                                  "UICheckButtonTemplate")
        if previous then
            check:SetPoint("LEFT", previous, "RIGHT", 10, 0)
        else
            check:SetPoint("LEFT", parent, "LEFT", 0, 0)
        end
        local caption = check:CreateFontString(nil, "OVERLAY",
                                               "GameFontHighlight")
        caption:SetPoint("LEFT", check, "RIGHT", 2, 1)
        caption:SetText(text)
        return check, caption
    end

    panel.barSideRefresh = panel.barSideRefresh or {}
    AddLabel(L["Bars"])
    for _, key in ipairs(GetSettingsBarOrder()) do
        local def = BAR_DEFS[key]
        local row = CreateFrame("Frame", nil, section)
        row:SetSize(250, 26)
        row:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
        y = y - 28
        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", row, "LEFT", 0, 0)
        name:SetWidth(88)
        name:SetJustifyH("LEFT")
        name:SetText(def.label or key)
        local leftCheck, leftLabel = AddChoice(row, name, L["Left"])
        local rightCheck, rightLabel = AddChoice(row, leftLabel, L["Right"])
        local function refresh()
            local onRight = barSides.Side(key) == "right"
            local usable = IsBarEnabled(key)
            leftCheck:SetChecked(not onRight)
            rightCheck:SetChecked(onRight)
            leftCheck:SetEnabled(usable)
            rightCheck:SetEnabled(usable)
            local color = usable and 1 or 0.5
            name:SetTextColor(color, color, color)
            leftLabel:SetTextColor(color, color, color)
            rightLabel:SetTextColor(color, color, color)
        end
        leftCheck:SetScript("OnClick", function() barSides.SetSide(key, "left") end)
        rightCheck:SetScript("OnClick", function()
            barSides.SetSide(key, "right")
        end)
        panel.barSideRefresh[key] = refresh
        refresh()
    end

    AddLabel(L["Level"])
    local levelRow = CreateFrame("Frame", nil, section)
    levelRow:SetSize(250, 26)
    levelRow:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
    y = y - 28
    local belowCheck, belowLabel = AddChoice(levelRow, nil, L["Below"])
    local leftLevelCheck, leftLevelLabel = AddChoice(levelRow, belowLabel,
                                                     L["Left"])
    local rightLevelCheck, rightLevelLabel = AddChoice(levelRow, leftLevelLabel,
                                                       L["Right"])
    local function refreshLevel()
        local place = barSides.LevelPlace()
        belowCheck:SetChecked(place == "below")
        leftLevelCheck:SetChecked(place == "left")
        rightLevelCheck:SetChecked(place == "right")
    end
    belowCheck:SetScript("OnClick", function() barSides.SetLevelPlace("below") end)
    leftLevelCheck:SetScript("OnClick", function() barSides.SetLevelPlace("left") end)
    rightLevelCheck:SetScript("OnClick", function()
        barSides.SetLevelPlace("right")
    end)
    panel.barSideRefresh.level = refreshLevel
    refreshLevel()

    AddLabel(L["Name Lines"])
    local nameRow = CreateFrame("Frame", nil, section)
    nameRow:SetSize(250, 26)
    nameRow:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
    y = y - 28
    local oneCheck, oneLabel = AddChoice(nameRow, nil, L["One Line"])
    local twoCheck, twoLabel = AddChoice(nameRow, oneLabel, L["Two Lines"])
    local function refreshLines()
        local one = barSides.NameLines() == 1
        oneCheck:SetChecked(one)
        twoCheck:SetChecked(not one)
        local color = 1
        oneLabel:SetTextColor(color, color, color)
        twoLabel:SetTextColor(color, color, color)
    end
    oneCheck:SetScript("OnClick", function() barSides.SetNameLines(1) end)
    twoCheck:SetScript("OnClick", function() barSides.SetNameLines(2) end)
    panel.barSideRefresh.nameLines = refreshLines
    refreshLines()

    local function AddFontSlider(key, labelText, getSize, setSize)
        AddLabel(labelText)
        local control, slider = CreateSizeSlider("VitalFrame" .. key, section,
                                                 150)
        control:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
        y = y - 36
        slider:SetMinMaxValues(NAME_MIN_FONT_SIZE, VERTICAL_FONT_MAX)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then
            pcall(slider.SetObeyStepOnDrag, slider, true)
        end
        local valueText = section:CreateFontString(nil, "OVERLAY",
                                                   "GameFontHighlight")
        valueText:SetPoint("LEFT", control, "RIGHT", 8, 0)
        local function refresh()
            local size = getSize()
            valueText:SetText(tostring(size))
            if slider:GetValue() ~= size then slider:SetValue(size) end
        end
        slider:SetScript("OnValueChanged", function(_, value)
            local size = fontMetrics.clamp(value, NAME_MIN_FONT_SIZE,
                                           VERTICAL_FONT_MAX, getSize())
            valueText:SetText(tostring(size))
            if getSize() ~= size then setSize(size) end
        end)
        panel.barSideRefresh[key] = refresh
        refresh()
    end
    AddFontSlider("verticalNameSize", L["Name Size"], fontMetrics.verticalNameSize,
                  function(size) fontMetrics.set("verticalNameSize", size) end)
    AddFontSlider("verticalLevelSize", L["Level Size"],
                  fontMetrics.verticalLevelSize, function(size)
        fontMetrics.set("verticalLevelSize", size)
    end)

    section:SetHeight(-y + 4)
    return section
end

function barSides.CreateSideTab(parent, previous, tooltip, icon, vertical)
    local tab
    local ok, created = pcall(CreateFrame, "Frame", nil, parent,
                              "LargeSideTabButtonTemplate")
    if ok and created then
        tab = created
    else
        ok, created = pcall(CreateFrame, "CheckButton", nil, parent,
                            "SpellBookSkillLineTabTemplate")
        if ok and created then tab = created end
    end
    if not tab then return nil end
    tab.tooltipText = tooltip
    if tab.Icon and tab.Icon.SetTexture then
        tab.Icon:SetTexture(icon)
        if tab.SetFillToInterior then tab:SetFillToInterior(true, 36) end
    elseif tab.SetNormalTexture then
        tab:SetNormalTexture(icon)
    end
    if previous then
        tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
    else
        -- The dialog border's visible edge sits inside the frame rect.
        tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -10, -36)
    end
    if tab.SetFrameLevel and parent.GetFrameLevel then
        tab:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    end
    local function Activate() barSides.Select(vertical) end
    if tab.SetCustomOnMouseUpHandler then
        tab:HookScript("OnMouseDown", function()
            suppressNextFocusClear = true
        end)
        tab:SetCustomOnMouseUpHandler(function(_, button)
            if button == "LeftButton" then Activate() end
        end)
    else
        tab:SetScript("OnClick", Activate)
        tab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText or "")
            GameTooltip:Show()
        end)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if tab.SetChecked then tab:SetChecked(false) end
    return tab
end

function CreateVitalFrameSettings(frame, frameWidth, frameHeight)
    if vitalFrameSettingsPanel then return end
    frame = frame or vitalFrameFrame
    if not frame then return end
    frameWidth = frameWidth or frame:GetWidth()
    frameHeight = frameHeight or frame:GetHeight()
    local settingsPanel =
        CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    settingsPanel:SetSize(560, 640)
    settingsPanel:SetFrameStrata("DIALOG")
    settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 20)
    settingsPanel:SetToplevel(true)
    settingsPanel:SetMovable(true)
    settingsPanel:EnableMouse(true)
    settingsPanel:RegisterForDrag("LeftButton")
    settingsPanel:SetClampedToScreen(true)
    settingsPanel:SetScale(1)
    settingsPanel:Hide()

    local borderOk, settingsPanelBorder =
        pcall(CreateFrame, "Frame", nil, settingsPanel,
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
    panelCloseButton:SetScript("OnClick", function() SetLayoutFocus(nil) end)

    local horizontalTab = barSides.CreateSideTab(settingsPanel, nil,
                                                 L["Horizontal Layout"],
                                                 "Interface\\Icons\\INV_Misc_Note_01",
                                                 false)
    local verticalTab = barSides.CreateSideTab(settingsPanel, horizontalTab,
                                               L["Vertical Layout"],
                                               "Interface\\Icons\\INV_Scroll_03",
                                               true)
    settingsPanel.horizontalTab = horizontalTab
    settingsPanel.verticalTab = verticalTab

    local leftColumn = CreateFrame("Frame", nil, settingsPanel)
    leftColumn:SetSize(1, 1)
    local rightColumn = CreateFrame("Frame", nil, settingsPanel)
    rightColumn:SetSize(1, 1)
    rightColumn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -42)
    leftColumn:SetPoint("TOPLEFT", rightColumn, "TOPRIGHT", 268, 0)

    local widthLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    widthLabel:SetPoint("TOPLEFT", leftColumn, "TOPLEFT", 0, 0)
    widthLabel:SetJustifyH("LEFT")
    widthLabel:SetText(L["Width"])

    local widthControl, widthSlider = CreateSizeSlider("VitalFrameWidthSlider",
                                                       settingsPanel)
    widthControl:SetPoint("TOPLEFT", widthLabel, "BOTTOMLEFT", 0, -2)
    widthSlider:SetMinMaxValues(barSides.Limits())
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
        if settingsPanel.sizing then
            if widthValueText then
                widthValueText:SetText(tostring(math.floor(value + 0.5)))
            end
            return
        end
        local minW, maxW = barSides.Limits()
        local v = ClampSizeValue(value, minW, maxW)
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
    heightLabel:SetPoint("TOPLEFT", widthControl, "BOTTOMLEFT", 0, -10)
    heightLabel:SetJustifyH("LEFT")
    heightLabel:SetText(L["Height"])

    local heightControl, heightSlider = CreateSizeSlider(
                                            "VitalFrameHeightSlider",
                                            settingsPanel)
    heightControl:SetPoint("TOPLEFT", heightLabel, "BOTTOMLEFT", 0, -2)
    heightSlider:SetMinMaxValues(select(3, barSides.Limits()))
    heightSlider:SetValueStep(10)
    if heightSlider.SetObeyStepOnDrag then
        pcall(heightSlider.SetObeyStepOnDrag, heightSlider, true)
    end

    if heightControl.MinText then
        heightControl.MinText:Hide()
        heightControl.MinText:SetText(tostring(FRAME_MIN_HEIGHT))
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
        if settingsPanel.sizing then
            if heightValueText then
                heightValueText:SetText(tostring(math.floor(value + 0.5)))
            end
            return
        end
        local _, _, minH, maxH = barSides.Limits()
        local v = ClampSizeValue(value, minH, maxH)
        if not vitalFrameFrame or not v then return end
        if heightValueText then heightValueText:SetText(tostring(v)) end
        ApplyFrameSize(vitalFrameFrame:GetWidth(), v)
    end)

    settingsPanel.heightSlider = heightSlider
    settingsPanel.heightValueText = heightValueText
    settingsPanel.heightValueText:SetText(tostring(frameHeight))

    local scaleLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    scaleLabel:SetPoint("TOPLEFT", heightControl, "BOTTOMLEFT", 0, -10)
    scaleLabel:SetJustifyH("LEFT")
    scaleLabel:SetText(L["Scale"])
    settingsPanel.scaleSlider = CreateScaleSlider("VitalFrameScaleSlider",
                                                  settingsPanel, scaleLabel,
                                                  GetSavedFrameScale,
                                                  ApplyFrameScale)

    local barsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                     "GameFontHighlightMedium")
    barsLabel:SetPoint("TOPLEFT", rightColumn, "TOPLEFT", 0, 0)
    barsLabel:SetJustifyH("LEFT")
    barsLabel:SetText(L["Bars"])

    local autoScaleBarsCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                           "UICheckButtonTemplate")
    autoScaleBarsCheck:SetPoint("TOPLEFT", barsLabel, "BOTTOMLEFT", 10, -4)

    local autoScaleBarsLabel = autoScaleBarsCheck:CreateFontString(nil,
                                                                   "OVERLAY",
                                                                   "GameFontHighlight")
    autoScaleBarsLabel:SetPoint("LEFT", autoScaleBarsCheck, "RIGHT", 10, 1)
    autoScaleBarsLabel:SetText(L["Auto Scale Bars"])

    autoScaleBarsCheck:SetChecked(GetAutoScaleBars())
    settingsPanel.autoScaleBarsCheck = autoScaleBarsCheck
    autoScaleBarsCheck:SetScript("OnClick", function(self)
        SetAutoScaleBars(not GetAutoScaleBars())
        self:SetChecked(GetAutoScaleBars())
    end)

    settingsPanel.barChecks = settingsPanel.barChecks or {}
    local prevCheck
    local alignAfterXpSubsets = false
    local checkGap = 0
    for _, key in ipairs(GetSettingsBarOrder()) do
        local def = BAR_DEFS[key]
        local check = CreateFrame("CheckButton", nil, settingsPanel,
                                  "UICheckButtonTemplate")
        if not prevCheck then
            check:SetPoint("TOPLEFT", autoScaleBarsCheck, "BOTTOMLEFT", 0,
                           checkGap)
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
            SetBarEnabled(key, not IsBarEnabled(key))
            self:SetChecked(IsBarEnabled(key))
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
                SetXPFillOption("useClassColor",
                                not GetXPFillOption("useClassColor"))
                self:SetChecked(GetXPFillOption("useClassColor"))
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            local hideWhenMaxLevelCheck =
                CreateFrame("CheckButton", nil, settingsPanel,
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
                SetXPFillOption("hideWhenMaxLevel",
                                not GetXPFillOption("hideWhenMaxLevel"))
                self:SetChecked(GetXPFillOption("hideWhenMaxLevel"))
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            check:SetScript("OnClick", function(self)
                SetBarEnabled("xpFill", not IsBarEnabled("xpFill"))
                local enabled = IsBarEnabled("xpFill")
                self:SetChecked(enabled)
                useClassColorCheck:SetEnabled(enabled)
                hideWhenMaxLevelCheck:SetEnabled(enabled)
            end)

            prevCheck = hideWhenMaxLevelCheck
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
                SetReputationAutoSwitch(not GetReputationAutoSwitch())
                self:SetChecked(GetReputationAutoSwitch())
                if addonTable and addonTable.RefreshAllData then
                    addonTable.RefreshAllData()
                end
            end)

            check:SetScript("OnClick", function(self)
                SetBarEnabled("reputation", not IsBarEnabled("reputation"))
                local enabled = IsBarEnabled("reputation")
                self:SetChecked(enabled)
                autoSwitchCheck:SetEnabled(enabled)
            end)

            prevCheck = autoSwitchCheck
            alignAfterXpSubsets = true
        else
            prevCheck = check
        end
    end

    local optionsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                        "GameFontHighlightMedium")
    optionsLabel:SetPoint("TOP", prevCheck or rightColumn, "BOTTOM", 0, -12)
    optionsLabel:SetPoint("LEFT", rightColumn, "LEFT", 0, 0)
    optionsLabel:SetJustifyH("LEFT")
    optionsLabel:SetText(L["Options"])
    settingsPanel.optionsLabel = optionsLabel
    settingsPanel.barListBottom = prevCheck
    settingsPanel.verticalSection =
        barSides.BuildVerticalSection(settingsPanel, prevCheck)

    function settingsPanel.ShowLayoutTab(vertical)
        local section = settingsPanel.verticalSection
        if section then section:SetShown(vertical and true or false) end
        local anchor = vertical and section or settingsPanel.barListBottom
        if settingsPanel.optionsLabel and anchor then
            settingsPanel.optionsLabel:ClearAllPoints()
            settingsPanel.optionsLabel:SetPoint("TOP", anchor, "BOTTOM", 0, -12)
            settingsPanel.optionsLabel:SetPoint("LEFT", rightColumn, "LEFT", 0, 0)
        end
        if settingsPanel.horizontalTab and settingsPanel.horizontalTab.SetChecked then
            settingsPanel.horizontalTab:SetChecked(not vertical)
        end
        if settingsPanel.verticalTab and settingsPanel.verticalTab.SetChecked then
            settingsPanel.verticalTab:SetChecked(vertical and true or false)
        end
        barSides.SyncSizeSliders()
        if settingsPanel.FitOptionsHeight then
            if Compat.After then
                Compat.After(0, settingsPanel.FitOptionsHeight)
            else
                settingsPanel.FitOptionsHeight()
            end
        end
    end

    local characterPositionCheck = CreateFrame("CheckButton", nil, settingsPanel,
                                               "UICheckButtonTemplate")
    characterPositionCheck:SetPoint("TOPLEFT", optionsLabel, "BOTTOMLEFT", 10,
                                    checkGap)
    local characterPositionLabel = characterPositionCheck:CreateFontString(nil,
                                                                           "OVERLAY",
                                                                           "GameFontHighlight")
    characterPositionLabel:SetPoint("LEFT", characterPositionCheck, "RIGHT", 10,
                                    1)
    characterPositionLabel:SetText(L["Use This Character's Position"])
    characterPositionCheck:SetChecked(addonTable.UsesOwnLayout and
                                          addonTable.UsesOwnLayout())
    settingsPanel.characterPositionCheck = characterPositionCheck
    characterPositionCheck:SetScript("OnClick", function(self)
        if addonTable.SetUsesOwnLayout then
            addonTable.SetUsesOwnLayout(self:GetChecked() == true)
        end
        self:SetChecked(addonTable.UsesOwnLayout and addonTable.UsesOwnLayout())
        ApplySavedFrameLayout()
    end)

    local hideBlizzardWatchBarCheck = CreateFrame("CheckButton", nil,
                                                  settingsPanel,
                                                  "UICheckButtonTemplate")
    hideBlizzardWatchBarCheck:SetPoint("TOPLEFT", characterPositionCheck,
                                       "BOTTOMLEFT", 0, checkGap)

    local hideBlizzardWatchBarLabel =
        hideBlizzardWatchBarCheck:CreateFontString(nil, "OVERLAY",
                                                   "GameFontHighlight")
    hideBlizzardWatchBarLabel:SetPoint("LEFT", hideBlizzardWatchBarCheck,
                                       "RIGHT", 10, 1)
    hideBlizzardWatchBarLabel:SetText(L["Hide Default Watch Bar"])

    hideBlizzardWatchBarCheck:SetChecked(GetHideBlizzardWatchBar())
    settingsPanel.hideBlizzardWatchBarCheck = hideBlizzardWatchBarCheck
    hideBlizzardWatchBarCheck:SetScript("OnClick", function(self)
        SetHideBlizzardWatchBar(not GetHideBlizzardWatchBar())
        self:SetChecked(GetHideBlizzardWatchBar())
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
        SetStreamerMode(not GetStreamerMode())
        self:SetChecked(GetStreamerMode())
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
                local shown = true
                if UI.GetSkillsFrameEnabled then
                    shown = not UI.GetSkillsFrameEnabled()
                end
                UI.SetSkillsFrameShown(shown)
                self:SetChecked(UI.GetSkillsFrameEnabled and
                                    UI.GetSkillsFrameEnabled() or shown)
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

    local fontsLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                      "GameFontHighlightMedium")
    fontsLabel:SetPoint("TOPLEFT", settingsPanel.scaleSlider, "BOTTOMLEFT", 0,
                        -12)
    fontsLabel:SetJustifyH("LEFT")
    fontsLabel:SetText(L["Fonts"])

    local nameFontLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    nameFontLabel:SetPoint("TOPLEFT", fontsLabel, "BOTTOMLEFT", 10, -10)
    nameFontLabel:SetJustifyH("LEFT")
    nameFontLabel:SetText(L["Name"])
    settingsPanel.nameFontButton = CreateFontDropdown(settingsPanel,
                                                      nameFontLabel, function()
        return GetFontChoice("name")
    end, function(id) SetFontChoice("name", id) end, 176, true)
    settingsPanel.nameSizeButton = fontMetrics.sizeDropdown(settingsPanel,
                                                          settingsPanel.nameFontButton,
                                                          NAME_MIN_FONT_SIZE,
                                                          NAME_FIRST_FONT_SIZE,
                                                          fontMetrics.nameSize,
                                                          function(size)
        fontMetrics.set("nameSize", fontMetrics.clamp(size, NAME_MIN_FONT_SIZE,
                                                   NAME_FIRST_FONT_SIZE,
                                                   NAME_FIRST_FONT_SIZE))
    end)
    if settingsPanel.nameSizeButton then
        local nameSizeLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                             "GameFontHighlight")
        nameSizeLabel:SetPoint("BOTTOMLEFT", settingsPanel.nameSizeButton,
                               "TOPLEFT", 0, 2)
        nameSizeLabel:SetJustifyH("LEFT")
        nameSizeLabel:SetText(L["Size"])
    end

    local lastNameLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    lastNameLabel:SetPoint("TOPLEFT", settingsPanel.nameFontButton, "BOTTOMLEFT",
                           0, -12)
    lastNameLabel:SetJustifyH("LEFT")
    lastNameLabel:SetText(L["Last Name"])
    local lastNameControl, lastNameSlider = CreateSizeSlider(
                                                "VitalFrameLastNamePercentSlider",
                                                settingsPanel, 176)
    lastNameControl:SetPoint("TOPLEFT", lastNameLabel, "BOTTOMLEFT", 0, -2)
    lastNameSlider:SetMinMaxValues(25, 100)
    lastNameSlider:SetValueStep(1)
    if lastNameSlider.SetObeyStepOnDrag then
        pcall(lastNameSlider.SetObeyStepOnDrag, lastNameSlider, true)
    end
    local lastNameValue = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    lastNameValue:SetPoint("LEFT", lastNameControl, "RIGHT", 6, 0)
    lastNameSlider:SetScript("OnValueChanged", function(_, value)
        local percent = fontMetrics.clamp(value, 25, 100, 50)
        lastNameValue:SetText(percent .. "%")
        if fontMetrics.lastPercent() ~= percent then
            fontMetrics.set("lastNamePercent", percent)
        end
    end)
    settingsPanel.RefreshLastNamePercent = function()
        local percent = fontMetrics.lastPercent()
        lastNameValue:SetText(percent .. "%")
        if lastNameSlider:GetValue() ~= percent then
            lastNameSlider:SetValue(percent)
        end
    end
    settingsPanel.RefreshLastNamePercent()

    local levelFontLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                          "GameFontHighlight")
    levelFontLabel:SetPoint("TOPLEFT", lastNameControl, "BOTTOMLEFT", 0, -12)
    levelFontLabel:SetJustifyH("LEFT")
    levelFontLabel:SetText(L["Level"])
    settingsPanel.levelFontButton = CreateFontDropdown(settingsPanel,
                                                       levelFontLabel,
                                                       function()
        return GetFontChoice("level")
    end, function(id) SetFontChoice("level", id) end, 222, true)

    local barsFontLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                         "GameFontHighlight")
    barsFontLabel:SetPoint("TOPLEFT", settingsPanel.levelFontButton,
                           "BOTTOMLEFT", 0, -12)
    barsFontLabel:SetJustifyH("LEFT")
    barsFontLabel:SetText(L["Bars"])
    settingsPanel.barsFontButton = CreateFontDropdown(settingsPanel,
                                                      barsFontLabel, function()
        return GetFontChoice("bars")
    end, function(id) SetFontChoice("bars", id) end, 176, true)
    settingsPanel.barSizeButton = fontMetrics.sizeDropdown(settingsPanel,
                                                         settingsPanel.barsFontButton,
                                                         8, 16,
                                                         fontMetrics.barSize,
                                                         function(size)
        fontMetrics.set("barSize", fontMetrics.clamp(size, 8, 16, 12))
    end)
    if settingsPanel.barSizeButton then
        local barsSizeLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                             "GameFontHighlight")
        barsSizeLabel:SetPoint("BOTTOMLEFT", settingsPanel.barSizeButton,
                               "TOPLEFT", 0, 2)
        barsSizeLabel:SetJustifyH("LEFT")
        barsSizeLabel:SetText(L["Size"])
    end

    local barTextureLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                           "GameFontHighlight")
    barTextureLabel:SetPoint("TOPLEFT", settingsPanel.barsFontButton or
                                 barsFontLabel, "BOTTOMLEFT", 0, -12)
    barTextureLabel:SetJustifyH("LEFT")
    barTextureLabel:SetText(L["Bar Texture"])
    settingsPanel.barTextureButton = mediaUI.CreateTextureDropdown(settingsPanel,
                                                           barTextureLabel,
                                                           mediaUI.GetBarTextureChoice,
                                                           mediaUI.SetBarTextureChoice,
                                                           222, true)

    local opacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                        "GameFontHighlightMedium")
    opacityLabel:SetPoint("TOPLEFT", settingsPanel.barTextureButton or
                               settingsPanel.barsFontButton or
                               settingsPanel.scaleSlider, "BOTTOMLEFT", -10, -12)
    opacityLabel:SetJustifyH("LEFT")
    opacityLabel:SetText(L["Opacity"])

    local frameOpacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                             "GameFontHighlight")
    frameOpacityLabel:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -8)
    frameOpacityLabel:SetJustifyH("LEFT")
    frameOpacityLabel:SetText(L["Frame Opacity"])
    settingsPanel.frameOpacitySlider = CreatePercentSlider(
                                           "VitalFrameFrameOpacitySlider",
                                           settingsPanel, frameOpacityLabel,
                                           function()
        return GetFramePercent("frameOpacity")
    end, function(percent) SetFramePercent("frameOpacity", percent) end)

    local backgroundOpacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                                  "GameFontHighlight")
    backgroundOpacityLabel:SetPoint("TOPLEFT", settingsPanel.frameOpacitySlider,
                                    "BOTTOMLEFT", 0, -10)
    backgroundOpacityLabel:SetJustifyH("LEFT")
    backgroundOpacityLabel:SetText(L["Background Opacity"])
    settingsPanel.backgroundOpacitySlider = CreatePercentSlider(
                                                "VitalFrameBackgroundOpacitySlider",
                                                settingsPanel,
                                                backgroundOpacityLabel,
                                                function()
        return GetFramePercent("backgroundOpacity")
    end, function(percent) SetFramePercent("backgroundOpacity", percent) end)

    local contentOpacityLabel = settingsPanel:CreateFontString(nil, "OVERLAY",
                                                               "GameFontHighlight")
    contentOpacityLabel:SetPoint("TOPLEFT",
                                 settingsPanel.backgroundOpacitySlider,
                                 "BOTTOMLEFT", 0, -10)
    contentOpacityLabel:SetJustifyH("LEFT")
    contentOpacityLabel:SetText(L["Content Opacity"])
    settingsPanel.contentOpacitySlider = CreatePercentSlider(
                                             "VitalFrameContentOpacitySlider",
                                             settingsPanel, contentOpacityLabel,
                                             function()
        return GetFramePercent("contentOpacity")
    end, function(percent) SetFramePercent("contentOpacity", percent) end)

    local function FitOptionsHeight()
        local top = settingsPanel:GetTop()
        local checksBottom = settingsPanel.themeForeverCheck and
                                 settingsPanel.themeForeverCheck:GetBottom()
        local opacityBottom = settingsPanel.contentOpacitySlider and
                                  settingsPanel.contentOpacitySlider:GetBottom()
        if not top or not opacityBottom then return end
        local lowest = opacityBottom
        if checksBottom and checksBottom < lowest then lowest = checksBottom end
        local needed = (top - lowest) + 53
        settingsPanel:SetHeight(math.ceil(needed))
    end
    settingsPanel.FitOptionsHeight = FitOptionsHeight
    settingsPanel.ShowLayoutTab(barSides.Enabled())
    settingsPanel:HookScript("OnShow", function()
        if Compat.After then
            Compat.After(0, FitOptionsHeight)
        else
            FitOptionsHeight()
        end
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
end

local function CursorOverOpenMenu()
    if Menu and Menu.GetManager then
        local ok, manager = pcall(Menu.GetManager)
        if ok and manager and manager.GetOpenMenu then
            local menuOk, menu = pcall(manager.GetOpenMenu, manager)
            if menuOk and menu then
                if menu.IsMouseOver and menu:IsMouseOver() then return true end
                local foci
                if GetMouseFoci then
                    foci = GetMouseFoci()
                elseif GetMouseFocus then
                    foci = {GetMouseFocus()}
                end
                if foci then
                    for _, focus in ipairs(foci) do
                        local frame = focus
                        while frame do
                            if frame == menu then return true end
                            frame = frame.GetParent and frame:GetParent()
                        end
                    end
                end
            end
        end
    end
    if DropDownList1 and DropDownList1:IsShown() and DropDownList1:IsMouseOver() then
        return true
    end
    return false
end

local function CreateVitalFrame()
    if vitalFrameFrame then return end

    local db = GetDB()
    local frameSettings = db and db.profile and db.profile.frame
    local frameWidth, frameHeight = barSides.SavedSize()

    local frame = CreateFrame("Frame", MAIN_FRAME_NAME, UIParent,
                              "BackdropTemplate")
    frame:SetSize(frameWidth, frameHeight)
    frame:SetScale(GetSavedFrameScale())
    frame:SetPoint("CENTER")
    AllowClientFramePosition(frame)

    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(1)
    frame:SetAlpha(1)

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0.83, 0.66, 0.27, 1)

    local selection = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    selection:SetAllPoints(frame)
    selection:SetFrameLevel(frame:GetFrameLevel() + 10)
    selection:EnableMouse(false)

    selection.Background = selection:CreateTexture(nil, "BACKGROUND")
    selection.Background:SetTexture(
        "Interface/AddOns/VitalFrame/Art/EditModeHighlighted")
    if selection.Background.SetTextureSliceMargins then
        pcall(selection.Background.SetTextureSliceMargins, selection.Background,
              16, 16, 16, 16)
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
            if CursorOverOpenMenu() then return end
            local overTab = false
            if vitalFrameSettingsPanel then
                local horizontalTab = vitalFrameSettingsPanel.horizontalTab
                local verticalTab = vitalFrameSettingsPanel.verticalTab
                if horizontalTab and horizontalTab:IsShown() and
                    horizontalTab:IsMouseOver() then
                    overTab = true
                end
                if verticalTab and verticalTab:IsShown() and
                    verticalTab:IsMouseOver() then
                    overTab = true
                end
            end
            local overPanel = vitalFrameSettingsPanel and
                                  (vitalFrameSettingsPanel:IsMouseOver() or
                                      overTab)
            local overSkills = UI.IsSkillsFrameMouseOver and
                                   UI.IsSkillsFrameMouseOver()
            local overSkillsPanel = UI.IsSkillsSettingsMouseOver and
                                        UI.IsSkillsSettingsMouseOver()
            if not self:IsMouseOver() and not overPanel and not overSkills and
                not overSkillsPanel then SetLayoutFocus(nil) end
        end
    end)

    local headerGroup = CreateFrame("Frame", nil, frame)
    headerGroup:SetPoint("TOP", frame, "TOP", 0, -10)
    headerGroup:SetSize(22, 22)
    frame.HeaderGroup = headerGroup
    local classIcon = frame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(22, 22)
    classIcon:SetPoint("TOPLEFT", headerGroup, "TOPLEFT", 0, 0)
    local _, classToken = UnitClass("player")
    if classToken then classToken = string.upper(classToken) end
    local eraClient = Compat.IsClassicEraClient and Compat.IsClassicEraClient()

    local function UseAtlas(name)
        if not name or not C_Texture or not C_Texture.GetAtlasExists then
            return false
        end
        local ok, exists = pcall(C_Texture.GetAtlasExists, name)
        if not ok or not exists then return false end
        classIcon:SetAtlas(name)
        return true
    end

    local shown = false
    if classToken and GetClassAtlas then
        if eraClient then
            -- UnitFramePortrait_Update: GetClassAtlas(UnitClass token).
            shown = UseAtlas(GetClassAtlas(classToken))
        else
            shown = UseAtlas(GetClassAtlas(string.lower(classToken))) or
                        UseAtlas(GetClassAtlas(classToken))
        end
    end
    if not shown then
        classIcon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        local coords = classToken and CLASS_ICON_TCOORDS and
                           CLASS_ICON_TCOORDS[classToken]
        if coords then
            classIcon:SetTexCoord(unpack(coords))
        else
            classIcon:SetTexCoord(0, 1, 0, 1)
        end
    end

    if not eraClient and frame.CreateMaskTexture then
        local classIconMask = frame:CreateMaskTexture(nil, "ARTWORK")
        local loaded = classIconMask:SetTexture(
                           "Interface\\COMMON\\CommonIconMask",
                           "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if loaded == true or loaded == 1 then
            classIconMask:SetAllPoints(classIcon)
            classIcon:AddMaskTexture(classIconMask)
        end
    end

    local classIconBorder = frame:CreateTexture(nil, "OVERLAY")
    classIconBorder:SetPoint("TOPLEFT", classIcon, "TOPLEFT", -2, 2)
    classIconBorder:SetPoint("BOTTOMRIGHT", classIcon, "BOTTOMRIGHT", 2, -2)
    classIconBorder:SetTexture("Interface\\COMMON\\WhiteIconFrame")

    frame.ClassIcon = classIcon
    frame.ClassIconBorder = classIconBorder

    local nameText = frame:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", NAME_ICON_GAP, 0)
    nameText:SetTextColor(1, 1, 1)
    nameText:SetJustifyH("LEFT")
    nameText:SetJustifyV("TOP")
    nameText:SetWordWrap(true)
    nameText:SetNonSpaceWrap(true)
    frame.NameText = nameText
    ApplyOwnedFont(nameText, "Name", NAME_FIRST_FONT_SIZE)

    local lastNameText = frame:CreateFontString(nil, "OVERLAY")
    lastNameText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
    lastNameText:SetTextColor(1, 1, 1)
    lastNameText:SetJustifyH("LEFT")
    lastNameText:SetJustifyV("TOP")
    lastNameText:SetWordWrap(true)
    lastNameText:SetNonSpaceWrap(true)
    lastNameText:Hide()
    frame.LastNameText = lastNameText
    ApplyOwnedFont(lastNameText, "LastName", NAME_LAST_FONT_SIZE)

    UpdateNameText()
    local levelText = frame:CreateFontString(nil, "OVERLAY")
    levelText:SetPoint("TOP", nameText, "BOTTOM", 0, -5)
    levelText:SetTextColor(1, 1, 1)
    frame.LevelText = levelText
    ApplyOwnedFont(levelText, "Level", LEVEL_BASE_FONT_SIZE)
    levelText:SetText(tostring(UnitLevel("player") or ""))

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
        mediaUI.ApplyStatusBarTexture(bar, mediaUI.GetStatusbarFile(mediaUI.GetBarTextureChoice()))
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
            mediaUI.ApplyStatusBarTexture(restedFill,
                                  mediaUI.GetStatusbarFile(mediaUI.GetBarTextureChoice()))
            restedFill:SetMinMaxValues(0, 1)
            restedFill:SetValue(0)
            restedFill:SetStatusBarColor(0.2, 0.35, 0.95, 1)
            restedFill:Hide()
            bar.BgFill = restedFill
        end

        local labelText = bar:CreateFontString(nil, "OVERLAY")
        labelText:SetPoint("CENTER", bar, "CENTER", 0, 0)
        labelText:SetJustifyH("CENTER")
        ApplyPlainFont(labelText, GetFontFileForRole("bars"), 12)
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
    ApplyFrameTheme()

    if frameSettings and not ReadFlag(frameSettings.shown, true) then
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
function UI.AllowClientFramePosition(frame) AllowClientFramePosition(frame) end
function UI.LockFrameToAddonPosition(frame) AllowClientFramePosition(frame) end
function UI.SaveAllFramePositions()
    SaveFramePosition()
    if UI.SaveSkillsPosition then UI.SaveSkillsPosition() end
end
function UI.AttachEditModeSnapAPI(frame) AttachEditModeSnapAPI(frame) end
function UI.CreateSizeSlider(name, parent) return CreateSizeSlider(name, parent) end
function UI.GetFontFileById(id)
    local choice = FONT_BY_ID[id] or FONT_BY_ID.frizqt
    return choice.file
end
function UI.IsFontChoice(id) return FONT_BY_ID[id] ~= nil end
function UI.IsStatusbarChoice(name) return mediaUI.IsStatusbarChoice(name) end
function UI.GetStatusbarFile(name) return mediaUI.GetStatusbarFile(name) end
function UI.GetDefaultStatusbar() return mediaUI.DEFAULT_STATUSBAR end
function UI.ApplyStatusBarTexture(bar, file) mediaUI.ApplyStatusBarTexture(bar, file) end
function UI.CreateTextureDropdown(parent, label, getName, setName, width, below)
    return mediaUI.CreateTextureDropdown(parent, label, getName, setName, width, below)
end
function UI.CreateFontDropdown(parent, label, getId, setId, width, below)
    return CreateFontDropdown(parent, label, getId, setId, width, below)
end
function UI.CreateFontSizeDropdown(parent, relativeTo, minSize, maxSize, getSize,
                                   setSize)
    return fontMetrics.sizeDropdown(parent, relativeTo, minSize, maxSize, getSize,
                                  setSize)
end
function UI.FitBarLabelSize(maxSize, barHeight, pad)
    return fontMetrics.fitBar(maxSize, barHeight, pad)
end
function UI.CreatePercentSlider(name, parent, label, getPercent, setPercent,
                                 width)
    return CreatePercentSlider(name, parent, label, getPercent, setPercent,
                               width)
end
function UI.CreateScaleSlider(name, parent, label, getScale, setScale, width)
    return CreateScaleSlider(name, parent, label, getScale, setScale, width)
end
function UI.GetFrameBorderColor() return GetResolvedThemeColor() end
function UI.SetTheme(theme) SetTheme(theme) end
function UI.FocusForSettings() SetLayoutFocus("main") end
function UI.SetLayoutFocus(which) SetLayoutFocus(which) end
function UI.GetLayoutFocus() return layoutFocus end
function UI.OnEditModeNudgeKey(frame, key) OnEditModeNudgeKey(frame, key) end
function UI.SuppressNextFocusClear() suppressNextFocusClear = true end
function UI.SetVitalFrameShown(shouldShow) SetVitalFrameShown(shouldShow) end
function UI.CreateVitalFrame() CreateVitalFrame() end
function UI.ApplySavedFrameLayout() ApplySavedFrameLayout() end
function UI.ApplySavedSettings() ApplySavedSettings() end
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

CreateVitalFrame()

-- Fonts and textures registered by other addons after VitalFrame loaded
-- become selectable, and saved choices that were waiting on them apply.
if Media and Media.OnChanged then
    Media.OnChanged(function()
        mediaUI.RebuildFontOptions()
        if vitalFrameFrame then
            mediaUI.ApplyMainBarTextures()
            UpdateProgressBarLayout()
        end
        local panel = vitalFrameSettingsPanel
        if panel then
            for _, key in ipairs({"nameFontButton", "levelFontButton",
                                  "barsFontButton", "barTextureButton"}) do
                local button = panel[key]
                if button and button.Refresh then button.Refresh() end
            end
        end
        if UI.LayoutSkillBars then UI.LayoutSkillBars() end
        if UI.RefreshSkillsSettings then UI.RefreshSkillsSettings() end
    end)
end
