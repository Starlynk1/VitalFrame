local addonName, addonTable = ...
local L = addonTable.L
local Compat = addonTable.Compat or {}

local eventFrame = CreateFrame("Frame")
local db
local DB_VERSION = 2

local defaults = {
    profile = {
        frame = {
            point = "CENTER",
            x = 0,
            y = 0,
            width = 200,
            height = 200,
            shown = true,
            frameOpacity = 100,
            contentOpacity = 100
        },
        fonts = {
            name = "frizqt",
            level = "frizqt",
            bars = "frizqt",
            nameSize = 24,
            lastNamePercent = 50,
            barSize = 12
        },
        bars = {
            enabled = {
                xpFill = true,
                xpRemaining = true,
                petXp = false,
                reputation = true,
                crafting = true
            },
            xpFill = {useClassColor = false, hideWhenMaxLevel = false},
            reputation = {autoSwitch = true},
            autoScale = false
        },
        hideBlizzardWatchBar = true,
        streamerMode = false,
        theme = "auto",
        skillsFrame = {
            point = "CENTER",
            x = 180,
            y = 0,
            width = 155,
            height = 170,
            barHeight = 16,
            growDirection = "down",
            shown = true,
            mode = "selected",
            weaponMode = "allKnown",
            selected = {},
            barFont = "frizqt",
            barFontSize = 12,
            frameOpacity = 100,
            contentOpacity = 100
        }
    },
    global = {
        settingsPanel = {
            hasCustomPosition = false,
            point = "CENTER",
            x = 0,
            y = 0
        }
    }
}

local function PrintMessage(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. L["Vital Frame"] .. ":|r " .. msg)
end

addonTable.PrintMessage = PrintMessage
addonTable.GetDB = function() return db end

local function GetUI()
    local ui = addonTable.UI
    if not ui then
        PrintMessage(L["UI module was not loaded. Check VitalFrame.toc order."])
        return nil
    end
    return ui
end

local function GetXPFillUseClassColor()
    return db and db.profile and db.profile.bars and db.profile.bars.xpFill and
               Compat.ReadFlag(db.profile.bars.xpFill.useClassColor, false)
end

local function GetXPFillHideWhenMaxLevel()
    return db and db.profile and db.profile.bars and db.profile.bars.xpFill and
               Compat.ReadFlag(db.profile.bars.xpFill.hideWhenMaxLevel, false)
end

local function SafeNumber(fn, ...)
    if not fn then return nil end
    local args = {...}
    local ok, value = pcall(function()
        return tonumber(fn(unpack(args)))
    end)
    if not ok then return nil end
    return value
end

local function SafeIsTrue(fn, ...)
    if not fn then return false end
    local args = {...}
    local ok, isTrue = pcall(function()
        return fn(unpack(args)) == true
    end)
    return ok and isTrue == true
end

local function GetEffectiveMaxLevelSafe()
    local isTimerunning = SafeIsTrue(PlayerIsTimerunning)
    local isTrial = SafeIsTrue(IsTrialAccount)
    local expansionMax
    if isTimerunning and not isTrial then
        expansionMax = SafeNumber(GetMaxLevelForLatestExpansion)
    end
    if not expansionMax then
        expansionMax = SafeNumber(GetMaxLevelForPlayerExpansion)
    end

    local playerMax = SafeNumber(GetMaxPlayerLevel)
    if expansionMax and playerMax then return math.min(expansionMax, playerMax) end
    return expansionMax or playerMax
end

local function IsPlayerXPInactive()
    local level = SafeNumber(UnitLevel, "player")
    local maxLevel = GetEffectiveMaxLevelSafe()
    if level and maxLevel and level >= maxLevel then return true end

    -- Avoid secret-boolean APIs in if statements (Midnight).
    if SafeIsTrue(IsPlayerAtEffectiveMaxLevel) then return true end
    if SafeIsTrue(IsXPUserDisabled) then return true end

    if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule
        and Enum.GameRule.ExperienceBarDisabled then
        if SafeIsTrue(C_GameRules.IsGameRuleActive,
                      Enum.GameRule.ExperienceBarDisabled) then
            return true
        end
    end

    local maxXP = SafeNumber(UnitXPMax, "player")
    if maxXP and maxXP <= 0 then return true end

    return false
end

local function GetPlayerClassColorOrDefault()
    local defaultR, defaultG, defaultB, defaultA = 0.34, 0.69, 0.17, 1
    local _, classTag = UnitClass("player")

    if classTag and CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classTag] then
        local c = CUSTOM_CLASS_COLORS[classTag]
        return c.r or defaultR, c.g or defaultG, c.b or defaultB,
               c.a or defaultA
    end

    if classTag and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTag] then
        local c = RAID_CLASS_COLORS[classTag]
        return c.r or defaultR, c.g or defaultG, c.b or defaultB,
               c.a or defaultA
    end

    return defaultR, defaultG, defaultB, defaultA
end

local function UpdateXPFillBar()
    local ui = GetUI()
    if not ui or not ui.SetBarPercent or not ui.SetBarLabelText or
        not ui.SetBarBackgroundPercent then return end

    local xpInactive = IsPlayerXPInactive()
    local hideAtMax = GetXPFillHideWhenMaxLevel()
    if ui.SetBarRuntimeHidden then
        ui.SetBarRuntimeHidden("xpFill", hideAtMax and xpInactive)
    end

    if ui.IsBarEnabled and not ui.IsBarEnabled("xpFill") then
        ui.SetBarPercent("xpFill", 0)
        ui.SetBarLabelText("xpFill", "")
        ui.SetBarBackgroundPercent("xpFill", 0)
        return
    end

    if hideAtMax and xpInactive then
        ui.SetBarPercent("xpFill", 0)
        ui.SetBarLabelText("xpFill", "")
        ui.SetBarBackgroundPercent("xpFill", 0)
        return
    end

    if ui.SetBarColor then
        if GetXPFillUseClassColor() then
            local r, g, b, a = GetPlayerClassColorOrDefault()
            ui.SetBarColor("xpFill", r, g, b, a)
        else
            ui.SetBarColor("xpFill", 0.34, 0.69, 0.17, 1)
        end
    end

    if xpInactive then
        ui.SetBarBackgroundPercent("xpFill", 0)
        ui.SetBarPercent("xpFill", 1)
        ui.SetBarLabelText("xpFill", L["Max Level"])
        return
    end

    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0
    local pct = 0
    if maxXP > 0 then
        pct = currentXP / maxXP
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
    end

    local restedXP = GetXPExhaustion() or 0
    local restedPct = 0
    if maxXP > 0 then
        local restedCapXP = currentXP + restedXP
        if restedCapXP < 0 then restedCapXP = 0 end
        if restedCapXP > maxXP then restedCapXP = maxXP end
        restedPct = restedCapXP / maxXP
    end
    ui.SetBarBackgroundPercent("xpFill", restedPct)
    ui.SetBarPercent("xpFill", pct)
    local pctInt = math.floor((pct * 100) + 0.5)
    ui.SetBarLabelText("xpFill", string.format(L["%d / %d (%d%%)"], currentXP,
                                               maxXP, pctInt))
end

local function UpdateXPRemainingBar()
    local ui = GetUI()
    if not ui or not ui.SetBarPercent then return end

    local xpInactive = IsPlayerXPInactive()
    local hideAtMax = GetXPFillHideWhenMaxLevel()
    if ui.SetBarRuntimeHidden then
        ui.SetBarRuntimeHidden("xpRemaining", hideAtMax and xpInactive)
    end

    if ui.IsBarEnabled and not ui.IsBarEnabled("xpRemaining") then
        ui.SetBarPercent("xpRemaining", 0)
        if ui.SetBarLabelText then ui.SetBarLabelText("xpRemaining", "") end
        return
    end

    if hideAtMax and xpInactive then
        ui.SetBarPercent("xpRemaining", 0)
        if ui.SetBarLabelText then ui.SetBarLabelText("xpRemaining", "") end
        return
    end

    if xpInactive then
        ui.SetBarPercent("xpRemaining", 0)
        if ui.SetBarLabelText then
            ui.SetBarLabelText("xpRemaining", L["Max Level"])
        end
        return
    end

    local currentXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0
    local remainingXP = 0
    local pct = 0
    if maxXP > 0 then
        remainingXP = maxXP - currentXP
        if remainingXP < 0 then remainingXP = 0 end
        pct = remainingXP / maxXP
    end

    ui.SetBarPercent("xpRemaining", pct)
    ui.SetBarLabelText("xpRemaining",
                       string.format(L["%d Remaining"], remainingXP))
end

local function UpdateLevelText(level)
    local ui = GetUI()
    if not ui or not ui.SetLevelText then return end
    ui.SetLevelText(level)
end

local function GetReputationSettings()
    if not db or not db.profile then return nil end
    db.profile.bars = db.profile.bars or {}
    db.profile.bars.reputation = db.profile.bars.reputation or {}
    if db.profile.bars.reputation.autoSwitch == nil then
        db.profile.bars.reputation.autoSwitch = 1
    end
    return db.profile.bars.reputation
end

local function GetReputationAutoSwitch()
    local settings = GetReputationSettings()
    return settings and Compat.ReadFlag(settings.autoSwitch, true)
end

local function GetLastGainedFactionID()
    local settings = GetReputationSettings()
    return settings and tonumber(settings.lastGainedFactionID) or nil
end

local function SetLastGainedFactionID(factionID)
    factionID = tonumber(factionID)
    if not factionID or factionID <= 0 then return end
    local settings = GetReputationSettings()
    if not settings then return end
    settings.lastGainedFactionID = factionID
end

local function GetWatchedFactionDataSafe()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        return C_Reputation.GetWatchedFactionData()
    end
    return nil
end

local function GetReputationFactionData()
    if GetReputationAutoSwitch() then
        local lastID = GetLastGainedFactionID()
        if lastID and C_Reputation and C_Reputation.GetFactionDataByID then
            local data = C_Reputation.GetFactionDataByID(lastID)
            if data and data.name and data.name ~= "" then return data end
        end
    end
    return GetWatchedFactionDataSafe()
end

local reputationProgressCache = {}
local reputationCacheReady = false

local function GetFactionProgressSnapshot(factionID, factionData)
    local snapshot = tostring(factionData.currentStanding or 0)
    local isParagonForPlayer = C_Reputation and
                                   C_Reputation.IsFactionParagonForCurrentPlayer
    local isParagonAny = C_Reputation and C_Reputation.IsFactionParagon
    if C_Reputation and C_Reputation.GetFactionParagonInfo and
        ((isParagonForPlayer and isParagonForPlayer(factionID)) or
            (not isParagonForPlayer and isParagonAny and isParagonAny(factionID))) then
        local currentValue = C_Reputation.GetFactionParagonInfo(factionID)
        snapshot = snapshot .. ":p" .. tostring(currentValue or 0)
    elseif C_Reputation and C_Reputation.IsMajorFaction and
        C_Reputation.IsMajorFaction(factionID) and C_MajorFactions and
        C_MajorFactions.GetMajorFactionData then
        local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
        if majorFactionData then
            snapshot = snapshot .. ":r" ..
                           tostring(majorFactionData.renownLevel or 0) .. ":" ..
                           tostring(majorFactionData.renownReputationEarned or 0)
        end
    end
    return snapshot
end

local function NoteKnownFactionID(factionID)
    factionID = tonumber(factionID)
    if factionID and factionID > 0 and reputationProgressCache[factionID] == nil then
        reputationProgressCache[factionID] = false
    end
end

local function ScanReputationGainsClassic()
    if not GetNumFactions or not GetFactionInfo then return end

    NoteKnownFactionID(GetLastGainedFactionID())
    if GetWatchedFactionInfo then
        local _, _, _, _, _, watchedID = GetWatchedFactionInfo()
        NoteKnownFactionID(watchedID)
    end

    local numFactions = GetNumFactions() or 0
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, isHeader, _, hasRep, _, _, factionID =
            GetFactionInfo(i)
        if name and (not isHeader or hasRep) then
            NoteKnownFactionID(factionID)
        end
    end

    local lastChangedID
    for factionID in pairs(reputationProgressCache) do
        local dataName, _, _, _, _, barValue
        if GetFactionInfoByID then
            dataName, _, _, _, _, barValue = GetFactionInfoByID(factionID)
        end
        if dataName and dataName ~= "" then
            local snapshot = tostring(barValue or 0)
            local prev = reputationProgressCache[factionID]
            if reputationCacheReady and prev and prev ~= snapshot then
                lastChangedID = factionID
            end
            reputationProgressCache[factionID] = snapshot
        end
    end
    reputationCacheReady = true
    if lastChangedID then SetLastGainedFactionID(lastChangedID) end
end

local function ScanReputationGains()
    if not C_Reputation or not C_Reputation.GetFactionDataByID then
        ScanReputationGainsClassic()
        return
    end

    NoteKnownFactionID(GetLastGainedFactionID())
    local watched = GetWatchedFactionDataSafe()
    if watched then NoteKnownFactionID(watched.factionID) end

    if C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        local numFactions = C_Reputation.GetNumFactions() or 0
        for i = 1, numFactions do
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data and (not data.isHeader or data.isHeaderWithRep) then
                NoteKnownFactionID(data.factionID)
            end
        end
    end

    local lastChangedID
    for factionID in pairs(reputationProgressCache) do
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data and data.name and data.name ~= "" then
            local snapshot = GetFactionProgressSnapshot(factionID, data)
            local prev = reputationProgressCache[factionID]
            if reputationCacheReady and prev and prev ~= snapshot then
                lastChangedID = factionID
            end
            reputationProgressCache[factionID] = snapshot
        end
    end
    reputationCacheReady = true
    if lastChangedID then SetLastGainedFactionID(lastChangedID) end
end

local function UpdateReputationBar()
    local ui = GetUI()
    if not ui or not ui.SetBarPercent or not ui.SetBarLabelText then return end

    local name, standingID, barMin, barMax, barValue
    local renownLevel
    local friendshipReactionText
    local isParagon = false
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local factionData = GetReputationFactionData()
        local factionID = factionData and tonumber(factionData.factionID) or 0
        local factionName = factionData and factionData.name
        if factionData and factionID > 0 and factionName and factionName ~= "" then
            name = factionName
            standingID = factionData.reaction
            barMin = factionData.currentReactionThreshold
            barMax = factionData.nextReactionThreshold
            barValue = factionData.currentStanding

            local isParagonForPlayer = C_Reputation.IsFactionParagonForCurrentPlayer
            local isParagonAny = C_Reputation.IsFactionParagon
            if C_Reputation.GetFactionParagonInfo and
                ((isParagonForPlayer and isParagonForPlayer(factionID)) or
                    (not isParagonForPlayer and isParagonAny and
                        isParagonAny(factionID))) then
                local currentValue, threshold, _, hasRewardPending =
                    C_Reputation.GetFactionParagonInfo(factionID)
                if currentValue and threshold and threshold > 0 then
                    isParagon = true
                    barMin = 0
                    barMax = threshold
                    barValue = currentValue % threshold
                    if hasRewardPending then
                        barValue = barValue + threshold
                    end
                end
            end

            if C_Reputation.IsMajorFaction and
                C_Reputation.IsMajorFaction(factionID) and C_MajorFactions and
                C_MajorFactions.GetMajorFactionData then
                local majorFactionData =
                    C_MajorFactions.GetMajorFactionData(factionID)
                if majorFactionData then
                    renownLevel = majorFactionData.renownLevel
                    if not isParagon then
                        barMin = 0
                        barMax = majorFactionData.renownLevelThreshold
                        barValue = majorFactionData.renownReputationEarned
                    end
                end
            end

            if not isParagon and not renownLevel and C_GossipInfo and
                C_GossipInfo.GetFriendshipReputation then
                local friendshipInfo = C_GossipInfo.GetFriendshipReputation(
                                           factionID)
                if friendshipInfo and friendshipInfo.friendshipFactionID and
                    friendshipInfo.friendshipFactionID > 0 then
                    if friendshipInfo.name and friendshipInfo.name ~= "" then
                        name = friendshipInfo.name
                    end
                    friendshipReactionText = friendshipInfo.reaction
                    if friendshipInfo.nextThreshold then
                        barMin = friendshipInfo.reactionThreshold
                        barMax = friendshipInfo.nextThreshold
                        barValue = friendshipInfo.standing
                    else
                        barMin = 0
                        barMax = 1
                        barValue = 1
                    end
                end
            end
        end
    elseif GetWatchedFactionInfo then
        if GetReputationAutoSwitch() then
            local lastID = GetLastGainedFactionID()
            if lastID and GetFactionInfoByID then
                name, _, standingID, barMin, barMax, barValue =
                    GetFactionInfoByID(lastID)
            end
        end
        if not name or name == "" then
            name, standingID, barMin, barMax, barValue = GetWatchedFactionInfo()
        end
    end
    local hasWatch = name and name ~= "" and barMin ~= nil and barMax ~= nil and
                         barValue ~= nil
    if ui.SetBarRuntimeHidden then ui.SetBarRuntimeHidden("reputation", not hasWatch) end

    if ui.IsBarEnabled and not ui.IsBarEnabled("reputation") then
        ui.SetBarPercent("reputation", 0)
        ui.SetBarLabelText("reputation", "")
        return
    end

    if not hasWatch then
        ui.SetBarPercent("reputation", 0)
        ui.SetBarLabelText("reputation", "")
        return
    end

    local progress = barValue - barMin
    local range = barMax - barMin
    if range <= 0 then
        progress = 1
        range = 1
    end
    if progress < 0 then progress = 0 end
    if progress > range then progress = range end

    local pct = 0
    if range > 0 then pct = progress / range end
    local pctInt = math.floor((pct * 100) + 0.5)

    if ui.SetBarColor then
        if renownLevel then
            ui.SetBarColor("reputation", 0.35, 0.75, 1.00, 1)
        else
            local standingColor = FACTION_BAR_COLORS and standingID and
                                      FACTION_BAR_COLORS[standingID]
            if standingColor then
                ui.SetBarColor("reputation",
                               standingColor.r or standingColor[1] or 0.10,
                               standingColor.g or standingColor[2] or 0.70,
                               standingColor.b or standingColor[3] or 0.30,
                               standingColor.a or standingColor[4] or 1)
            else
                ui.SetBarColor("reputation", 0.10, 0.70, 0.30, 1)
            end
        end
    end

    local standingText
    if isParagon then
        standingText = L["Paragon"]
    elseif renownLevel then
        standingText = string.format(L["Renown (%d)"], renownLevel)
    elseif friendshipReactionText and friendshipReactionText ~= "" then
        standingText = friendshipReactionText
    else
        standingText =
            _G["FACTION_STANDING_LABEL" .. tostring(standingID or "")] or ""
    end
    if standingText ~= "" then
        ui.SetBarLabelText("reputation",
                           string.format(L["%s\n%s -- %d / %d (%d%%)"], name,
                                         standingText, progress, range, pctInt))
    else
        ui.SetBarLabelText("reputation",
                           string.format(L["%s\n%d / %d (%d%%)"], name, progress,
                                         range, pctInt))
    end

    ui.SetBarPercent("reputation", pct)
end

local function SupportsPetXpLeveling()
    if Compat.SupportsPetXpLeveling then return Compat.SupportsPetXpLeveling() end
    return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
end

local function CanShowPetXpBar()
    if not SupportsPetXpLeveling() then return false end
    local _, classTag = UnitClass("player")
    if classTag ~= "HUNTER" then return false end
    local ok, exists = pcall(function() return UnitExists("pet") == true end)
    return ok and exists == true
end

local function UpdatePetXpBar()
    local ui = GetUI()
    if not ui then return end

    local showPetXp = CanShowPetXpBar()
    if ui.SetBarRuntimeHidden then ui.SetBarRuntimeHidden("petXp", not showPetXp) end

    if not showPetXp then
        if ui.SetBarPercent then ui.SetBarPercent("petXp", 0) end
        if ui.SetBarLabelText then ui.SetBarLabelText("petXp", "") end
        return
    end

    if ui.IsBarEnabled and not ui.IsBarEnabled("petXp") then
        if ui.SetBarPercent then ui.SetBarPercent("petXp", 0) end
        if ui.SetBarLabelText then ui.SetBarLabelText("petXp", "") end
        return
    end

    local currentXP, nextXP = 0, 0
    if GetPetExperience then
        currentXP, nextXP = GetPetExperience()
    end
    currentXP = tonumber(currentXP) or 0
    nextXP = tonumber(nextXP) or 0
    local pct = 0
    if nextXP > 0 then
        pct = currentXP / nextXP
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
    end
    if ui.SetBarPercent then ui.SetBarPercent("petXp", pct) end
    if ui.SetBarLabelText then
        local pctInt = math.floor((pct * 100) + 0.5)
        ui.SetBarLabelText("petXp", string.format(L["%d / %d (%d%%)"], currentXP,
                                                   nextXP, pctInt))
    end
end

local function IsSecondaryProfessionName(name)
    if not name or name == "" then return true end
    if COOKING and name == COOKING then return true end
    if FISHING and name == FISHING then return true end
    if FIRST_AID and name == FIRST_AID then return true end
    return name == "Cooking" or name == "Fishing" or name == "First Aid" or
               name == "Archaeology" or name == "Riding"
end

local function GetClassicProfessionData(slot)
    if not GetNumSkillLines or not GetSkillLineInfo then return nil end
    local found = 0
    local inProfessions = false
    local useHeader = TRADE_SKILLS ~= nil
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank, isAbandonable =
            GetSkillLineInfo(i)
        if useHeader then
            if isHeader then
                inProfessions = name == TRADE_SKILLS
            elseif inProfessions and name and name ~= "" and
                not IsSecondaryProfessionName(name) then
                found = found + 1
                if found == slot then
                    return name, tonumber(rank) or 0, tonumber(maxRank) or 0
                end
            end
        elseif not isHeader and isAbandonable and name and name ~= "" and
            not IsSecondaryProfessionName(name) then
            found = found + 1
            if found == slot then
                return name, tonumber(rank) or 0, tonumber(maxRank) or 0
            end
        end
    end
    return nil
end

local function GetPrimaryProfessionData(slot)
    if GetProfessions and GetProfessionInfo then
        local prof1, prof2 = GetProfessions()
        local index = (slot == 1) and prof1 or prof2
        if index then
            local name, _, rank, maxRank = GetProfessionInfo(index)
            if name and name ~= "" then
                return name, tonumber(rank) or 0, tonumber(maxRank) or 0
            end
        end
    end
    return GetClassicProfessionData(slot)
end

local function UpdateProfessionBars()
end

local function NormalizeSkillName(name)
    if type(name) ~= "string" then
        local ok, text = pcall(tostring, name)
        if not ok or type(text) ~= "string" then return "" end
        name = text
    end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return string.lower(name)
end

local function IsSecondarySkillName(name)
    if IsSecondaryProfessionName(name) then return true end
    if RIDING and name == RIDING then return true end
    return name == "Riding"
end

local function IsStatSkillName(name)
    if not name or name == "" then return false end
    if DEFENSE and name == DEFENSE then return true end
    local lower = NormalizeSkillName(name)
    return lower == "defense" or lower == "defence"
end

local BLOCKED_SKILL_NAMES = {
    retribution = true,
    holy = true,
    protection = true,
    arms = true,
    fury = true,
    discipline = true,
    shadow = true,
    assassination = true,
    subtlety = true,
    combat = true,
    balance = true,
    feral = true,
    restoration = true,
    enhancement = true,
    elemental = true,
    affliction = true,
    demonology = true,
    destruction = true,
    arcane = true,
    fire = true,
    frost = true,
    ["beast mastery"] = true,
    marksmanship = true,
    survival = true
}

local function IsBlockedSkillName(name)
    local lower = NormalizeSkillName(name)
    if lower == "" then return true end
    if BLOCKED_SKILL_NAMES[lower] then return true end
    return lower:find("retribution", 1, true) ~= nil
end

local function StripOneHandedPrefix(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lower = NormalizeSkillName(name)
    if lower == "one-handed" or lower == "one handed" then return nil end
    local stripped = name:gsub("^[Oo]ne%-%s*[Hh]anded%s+", ""):gsub(
                         "^[Oo]ne%s+[Hh]anded%s+", "")
    if stripped == "" then return nil end
    return stripped
end

local function GetSkillHeaderCategory(name)
    if not name or name == "" then return nil end
    if TRADE_SKILLS and name == TRADE_SKILLS then return "profession" end
    if SECONDARY_SKILLS and name == SECONDARY_SKILLS then return "secondary" end
    if WEAPON_SKILLS and name == WEAPON_SKILLS then return "weapon" end

    local lower = NormalizeSkillName(name)
    if lower:find("weapon", 1, true) then return "weapon" end
    if lower == "professions" or lower == "trade skills" then
        return "profession"
    end
    if lower == "secondary skills" or lower:find("secondary", 1, true) then
        return "secondary"
    end
    if lower:find("class", 1, true) or lower:find("armor", 1, true) or
        lower:find("language", 1, true) or lower:find("talent", 1, true) or
        lower:find("specializ", 1, true) then
        return "skip"
    end
    return nil
end

local WEAPON_SKILL_IDS = {
    {id = 43, name = "Swords", spellID = 201},
    {id = 55, name = "Two-Handed Swords", spellID = 202},
    {id = 44, name = "Axes", spellID = 196},
    {id = 172, name = "Two-Handed Axes", spellID = 197},
    {id = 54, name = "Maces", spellID = 198},
    {id = 160, name = "Two-Handed Maces", spellID = 199},
    {id = 173, name = "Daggers", spellID = 1180},
    {id = 229, name = "Polearms", spellID = 200},
    {id = 136, name = "Staves", spellID = 227},
    {id = 45, name = "Bows", spellID = 264},
    {id = 226, name = "Crossbows", spellID = 5011},
    {id = 46, name = "Guns", spellID = 266},
    {id = 176, name = "Thrown", spellID = 2567},
    {id = 228, name = "Wands", spellID = 5009},
    {id = 162, name = "Unarmed", spellID = 203, alwaysKnown = true},
    {id = 95, name = "Defense", alwaysKnown = true, category = "stat"},
    {id = 473, name = "Fist Weapons", spellID = 15590}
}

local WEAPON_SKILL_BY_ID = {}
for _, skill in ipairs(WEAPON_SKILL_IDS) do
    WEAPON_SKILL_BY_ID[skill.id] = skill
end

local WEAPON_SUBCLASS_TO_SKILL = {
    [0] = "Axes",
    [1] = "Two-Handed Axes",
    [2] = "Bows",
    [3] = "Guns",
    [4] = "Maces",
    [5] = "Two-Handed Maces",
    [6] = "Polearms",
    [7] = "Swords",
    [8] = "Two-Handed Swords",
    [10] = "Staves",
    [13] = "Fist Weapons",
    [15] = "Daggers",
    [16] = "Thrown",
    [18] = "Crossbows",
    [19] = "Wands"
}

local function IsSecretValue(value)
    return issecretvalue and pcall(issecretvalue, value) and
               issecretvalue(value)
end

local function ReadableNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    return tonumber(value)
end

local function ReadableString(value)
    if value == nil or IsSecretValue(value) then return nil end
    if type(value) == "string" then
        if value == "" then return nil end
        return value
    end
    return nil
end

local function PlayerKnowsSpell(spellID)
    if not spellID then return false end
    if C_SpellBook then
        if C_SpellBook.IsSpellKnown then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
            if ok and known then return true end
        end
        if C_SpellBook.IsSpellInSpellBook then
            local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID)
            if ok and known then return true end
        end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok and known then return true end
    end
    return false
end

local function GetSpellNameSafe(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok then
            name = ReadableString(name)
            if name then return name end
        end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then
            name = ReadableString(name)
            if name then return name end
        end
    end
    return nil
end

local function ValuesToSkillInfo(...)
    local count = select("#", ...)
    if count == 0 then return nil end
    local first = select(1, ...)
    if first == nil then return nil end

    if type(first) == "table" then
        local info = first
        return {
            name = ReadableString(info.skillName or info.name or info.Name or
                                      info.skillLineName or
                                      info.professionName),
            isHeader = info.isHeader == true or info.header == true or
                info.IsHeader == true or info.isHeader == 1 or
                info.header == 1,
            rank = ReadableNumber(info.skillRank or info.rank or
                                      info.currentRank or info.skillLevel or
                                      info.currentLevel or info.curRank),
            maxRank = ReadableNumber(info.skillMaxRank or info.maxRank or
                                         info.maxSkillLevel or info.maxLevel),
            skillLineID = ReadableNumber(info.skillLineID or info.skillID or
                                             info.id or info.professionID or
                                             info.skillLine)
        }
    end

    local a, b, c, d, e, f, g = ...
    if type(a) == "string" then
        if type(b) == "string" then
            return {
                name = ReadableString(a),
                rank = ReadableNumber(c),
                maxRank = ReadableNumber(d)
            }
        end
        if type(b) == "number" and b > 1 and
            (c == nil or type(c) == "number") and
            (type(c) ~= "number" or c > 1 or d == nil) then
            if b >= 40 and (d ~= nil or e ~= nil) then
                return {
                    name = ReadableString(a),
                    skillLineID = b,
                    rank = ReadableNumber(c),
                    maxRank = ReadableNumber(d)
                }
            end
            return {
                name = ReadableString(a),
                rank = ReadableNumber(b),
                maxRank = ReadableNumber(c),
                isHeader = false
            }
        end
        return {
            name = ReadableString(a),
            isHeader = b == true or b == 1,
            rank = ReadableNumber(d),
            maxRank = ReadableNumber(g) or ReadableNumber(e)
        }
    end

    if type(a) == "number" then
        if type(b) == "string" then
            return {
                skillLineID = a,
                name = ReadableString(b),
                rank = ReadableNumber(c),
                maxRank = ReadableNumber(d),
                isHeader = e == true or e == 1
            }
        end
        return {
            skillLineID = a,
            rank = ReadableNumber(b),
            maxRank = ReadableNumber(c)
        }
    end
    return nil
end

local function CallSkillInfo(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if not ok then return nil end
    return ValuesToSkillInfo(a, b, c, d, e, f, g)
end

local PROFESSION_SKILL_IDS = {
    [164] = "profession",
    [165] = "profession",
    [171] = "profession",
    [182] = "profession",
    [186] = "profession",
    [197] = "profession",
    [202] = "profession",
    [333] = "profession",
    [393] = "profession",
    [755] = "profession",
    [773] = "profession",
    [129] = "secondary",
    [184] = "secondary",
    [185] = "secondary",
    [356] = "secondary",
    [762] = "secondary",
    [794] = "secondary"
}

local function CategoryForSkillLine(skillLineID, name)
    if skillLineID and WEAPON_SKILL_BY_ID[skillLineID] then
        return WEAPON_SKILL_BY_ID[skillLineID].category or "weapon"
    end
    if skillLineID and PROFESSION_SKILL_IDS[skillLineID] then
        return PROFESSION_SKILL_IDS[skillLineID]
    end
    if name and IsStatSkillName(name) then return "stat" end
    if name and IsSecondarySkillName(name) then return "secondary" end
    return nil
end

local function GetProfessionInfoBySkillLineID(skillLineID)
    if not skillLineID or not C_TradeSkillUI or
        not C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        return nil
    end
    return CallSkillInfo(C_TradeSkillUI.GetProfessionInfoBySkillLineID,
                         skillLineID)
end

local function ProbeNamespaceByID(api, skillID)
    if type(api) ~= "table" then return nil end
    for name, fn in pairs(api) do
        if type(fn) == "function" and type(name) == "string" and
            name:find("^Get") then
            local info = CallSkillInfo(fn, skillID)
            if info and (info.rank or info.maxRank) then return info end
        end
    end
    return nil
end

local function GetSkillRankByID(skillID)
    local info = GetProfessionInfoBySkillLineID(skillID)
    if info and (info.rank or info.maxRank) then
        return info.rank, info.maxRank, info.name, info.skillLineID or skillID
    end

    info = ProbeNamespaceByID(C_SkillInfo, skillID)
    if info then
        return info.rank, info.maxRank, info.name, info.skillLineID or skillID
    end

    if C_Spell and C_Spell.GetSpellSkillLineAbilityRank then
        local known = WEAPON_SKILL_BY_ID[skillID]
        if known and known.spellID then
            local ok, rank = pcall(C_Spell.GetSpellSkillLineAbilityRank,
                                   known.spellID)
            rank = ok and ReadableNumber(rank) or nil
            if rank then return rank, nil, known.name, skillID end
        end
    end

    local functions = {}
    if C_SpellBook then
        functions[#functions + 1] = C_SpellBook.GetSkillLineRank
        functions[#functions + 1] = C_SpellBook.GetSkillRank
        functions[#functions + 1] = C_SpellBook.GetSkillLineInfo
    end
    if C_SkillLine then
        functions[#functions + 1] = C_SkillLine.GetSkillLineRank
        functions[#functions + 1] = C_SkillLine.GetSkillInfo
    end
    functions[#functions + 1] = GetSkillLineRank
    functions[#functions + 1] = GetSkillInfo

    for _, fn in ipairs(functions) do
        info = CallSkillInfo(fn, skillID)
        if info and (info.rank or info.maxRank or info.name) then
            return info.rank, info.maxRank, info.name, info.skillLineID or
                       skillID
        end
    end
    return nil
end

local function CollectSkillInfoAPIEntries()
    local entries = {}
    local api = C_SkillInfo
    if not api then return entries end

    local listFn = api.GetAllSkillLines or api.GetPlayerSkillLines or
                       api.GetSkillLines or api.GetSkills or
                       api.GetKnownSkillLines
    if type(listFn) == "function" then
        local ok, list = pcall(listFn)
        if ok and type(list) == "table" then
            for _, item in ipairs(list) do
                local info = type(item) == "table" and
                                 ValuesToSkillInfo(item) or
                                 ValuesToSkillInfo(item)
                if info then entries[#entries + 1] = info end
            end
        end
    end

    local numFn = api.GetNumSkillLines or api.GetNumSkills or
                      api.GetNumPlayerSkillLines
    local infoFn = api.GetSkillLineInfo or api.GetSkillInfo or
                       api.GetPlayerSkillLineInfo
    if type(numFn) == "function" and type(infoFn) == "function" then
        local ok, num = pcall(numFn)
        num = ok and tonumber(num) or 0
        for i = 1, num do
            local info = CallSkillInfo(infoFn, i)
            if info then entries[#entries + 1] = info end
        end
    end
    return entries
end

local function GetDefaultWeaponSkillCap()
    local level = SafeNumber(UnitLevel, "player") or
                      SafeNumber(UnitEffectiveLevel, "player")
    if level and level > 0 then return level * 5 end
    return 300
end

local WEAPON_NAME_ALIASES = {
    ["one-handed swords"] = "swords",
    ["one handed swords"] = "swords",
    ["one-handed axes"] = "axes",
    ["one handed axes"] = "axes",
    ["one-handed maces"] = "maces",
    ["one handed maces"] = "maces",
    ["fist weapon"] = "fist weapons"
}

local function CanonicalWeaponSkillName(name)
    local lower = NormalizeSkillName(name)
    if lower == "one-handed" or lower == "one handed" then return "" end
    lower = lower:gsub("^one%-handed%s+", ""):gsub("^one handed%s+", "")
    return WEAPON_NAME_ALIASES[lower] or lower
end

local function GetEquippedSlotItemID(slot)
    if ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item then
        local location = ItemLocation:CreateFromEquipmentSlot(slot)
        if location then
            local exists = true
            if C_Item.DoesItemExist then
                exists = C_Item.DoesItemExist(location)
            end
            if exists and C_Item.GetItemID then
                local itemID = ReadableNumber(C_Item.GetItemID(location))
                if itemID then return itemID end
            end
        end
    end
    if GetInventoryItemID then
        local itemID = ReadableNumber(GetInventoryItemID("player", slot))
        if itemID then return itemID end
    end
    return nil
end

local function GetItemWeaponInfo(itemInfo)
    if not itemInfo then return nil end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if instant then
        -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
        local ok, _, _, itemSubType, itemEquipLoc, _, classID, subClassID =
            pcall(instant, itemInfo)
        if ok then
            classID = ReadableNumber(classID)
            subClassID = ReadableNumber(subClassID)
            return classID, subClassID, ReadableString(itemSubType),
                   ReadableString(itemEquipLoc)
        end
    end
    if GetItemInfo then
        local ok, _, _, _, _, _, _, itemSubType, _, itemEquipLoc, _, _,
              classID, subClassID = pcall(GetItemInfo, itemInfo)
        if ok then
            return ReadableNumber(classID), ReadableNumber(subClassID),
                   ReadableString(itemSubType), ReadableString(itemEquipLoc)
        end
    end
    return nil
end

local function GetInventoryWeaponSubclass(slot)
    local itemID = GetEquippedSlotItemID(slot)
    if not itemID then return nil end
    local classID, subclassID = GetItemWeaponInfo(itemID)
    local weaponClass = 2
    if Enum and Enum.ItemClass and Enum.ItemClass.Weapon then
        weaponClass = Enum.ItemClass.Weapon
    end
    if classID == weaponClass then return subclassID end
    return nil
end

local WEAPON_SKILL_NAMES = {
    axes = true,
    ["two-handed axes"] = true,
    swords = true,
    ["two-handed swords"] = true,
    maces = true,
    ["two-handed maces"] = true,
    daggers = true,
    polearms = true,
    staves = true,
    bows = true,
    crossbows = true,
    guns = true,
    thrown = true,
    wands = true,
    unarmed = true,
    ["fist weapons"] = true
}

local function IsWeaponSkillName(name)
    if not name or name == "" or IsStatSkillName(name) then return false end
    if UNARMED and name == UNARMED then return true end
    local lower = NormalizeSkillName(name)
    if WEAPON_SKILL_NAMES[lower] then return true end
    return lower:find("sword", 1, true) ~= nil or
               lower:find("axe", 1, true) ~= nil or
               lower:find("mace", 1, true) ~= nil or
               lower:find("dagger", 1, true) ~= nil or
               lower:find("staff", 1, true) ~= nil or
               lower:find("staves", 1, true) ~= nil or
               lower:find("bow", 1, true) ~= nil or
               lower:find("gun", 1, true) ~= nil or
               lower:find("wand", 1, true) ~= nil or
               lower:find("polearm", 1, true) ~= nil or
               lower:find("thrown", 1, true) ~= nil or
               lower:find("unarmed", 1, true) ~= nil or
               lower:find("fist", 1, true) ~= nil or
               lower:find("crossbow", 1, true) ~= nil
end

local function AddEquippedSkillName(set, name)
    if not name or name == "" then return end
    set[CanonicalWeaponSkillName(name)] = true
end

local function GetEquippedWeaponSkillNames()
    local equipped = {}
    local slots = {
        INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18
    }
    local hasMeleeWeapon = false
    local mainHandSlot = INVSLOT_MAINHAND or 16
    local mainHandItemID = GetEquippedSlotItemID(mainHandSlot)
    local weaponClass = 2
    if Enum and Enum.ItemClass and Enum.ItemClass.Weapon then
        weaponClass = Enum.ItemClass.Weapon
    end

    for _, slot in ipairs(slots) do
        local itemID = GetEquippedSlotItemID(slot)
        if itemID then
            local classID, subclassID, itemSubType, itemEquipLoc =
                GetItemWeaponInfo(itemID)
            if classID == weaponClass and subclassID ~= 20 then
                local loc = itemEquipLoc or ""
                local isRanged = loc == "INVTYPE_RANGED" or
                                     loc == "INVTYPE_RANGEDRIGHT" or
                                     loc == "INVTYPE_THROWN" or
                                     subclassID == 2 or subclassID == 3 or
                                     subclassID == 16 or subclassID == 18 or
                                     subclassID == 19
                if not isRanged then hasMeleeWeapon = true end
                local mapped = WEAPON_SUBCLASS_TO_SKILL[subclassID]
                if mapped then AddEquippedSkillName(equipped, mapped) end
                AddEquippedSkillName(equipped, itemSubType)
                if GetItemSubClassInfo then
                    AddEquippedSkillName(equipped,
                                         GetItemSubClassInfo(weaponClass,
                                                             subclassID))
                end
            end
        end
    end

    if not hasMeleeWeapon and not mainHandItemID then
        AddEquippedSkillName(equipped, UNARMED)
        AddEquippedSkillName(equipped, "Unarmed")
    end
    return equipped
end

local function ScanClassicSkills()
    local catalog = {}
    local visible = {}
    local settings = db and db.profile and db.profile.skillsFrame
    local weaponMode = settings and settings.weaponMode or "allKnown"
    if settings and type(settings.selected) ~= "table" then
        settings.selected = {}
    end
    local selected = settings and settings.selected or {}
    local includeAll = settings and
                           (settings.includeAllSkills or settings.mode ~= "selected")
    local hasChoices = false
    if not includeAll then
        for _ in pairs(selected) do
            hasChoices = true
            break
        end
    end
    local seededSelectable = false
    local equipped = nil
    if weaponMode == "equipped" then equipped = GetEquippedWeaponSkillNames() end

    local function AddSkill(name, rank, maxRank, skillCategory)
        if name == nil or name == "" then return end
        name = StripOneHandedPrefix(name)
        if not name or name == "" then return end
        if IsBlockedSkillName(name) then return end
        if skillCategory ~= "stat" and IsWeaponSkillName(name) then
            skillCategory = "weapon"
        end
        if skillCategory == "weapon" and not IsWeaponSkillName(name) then
            return
        end
        local key = skillCategory == "weapon" and CanonicalWeaponSkillName(name) or
                        NormalizeSkillName(name)
        for _, existing in ipairs(catalog) do
            if existing.name == name then return end
            if skillCategory == "weapon" and existing.category == "weapon" and
                CanonicalWeaponSkillName(existing.name) == key then
                return
            end
        end
        local entry = {
            name = name,
            rank = tonumber(rank) or 0,
            maxRank = tonumber(maxRank) or 0,
            category = skillCategory
        }
        catalog[#catalog + 1] = entry
        local include = true
        local nameKey = type(name) == "string" and name or nil
        local selectable = skillCategory == "profession" or
                               skillCategory == "secondary"
        if selectable and nameKey then
            if includeAll or not hasChoices then
                selected[nameKey] = 1
                seededSelectable = true
            elseif not Compat.ReadFlag(selected[nameKey], false) then
                include = false
            end
        end
        if include and skillCategory == "weapon" and equipped and nameKey then
            include = Compat.ReadFlag(equipped[CanonicalWeaponSkillName(nameKey)],
                                      false)
        end
        if include then visible[#visible + 1] = entry end
    end

    local CATEGORY_SORT = {
        weapon = 1,
        stat = 2,
        profession = 3,
        secondary = 4
    }
    local NAME_SORT = {
        axes = 10,
        ["two-handed axes"] = 11,
        bows = 12,
        guns = 13,
        maces = 14,
        ["two-handed maces"] = 15,
        polearms = 16,
        swords = 17,
        ["two-handed swords"] = 18,
        staves = 19,
        ["fist weapons"] = 20,
        daggers = 21,
        thrown = 22,
        crossbows = 23,
        wands = 24,
        unarmed = 25,
        defense = 40,
        defence = 40
    }
    local function SortSkillList(list)
        table.sort(list, function(a, b)
            local ac = CATEGORY_SORT[a.category] or 50
            local bc = CATEGORY_SORT[b.category] or 50
            if ac ~= bc then return ac < bc end
            local al = NormalizeSkillName(a.name)
            local bl = NormalizeSkillName(b.name)
            local an = NAME_SORT[al] or 100
            local bn = NAME_SORT[bl] or 100
            if an ~= bn then return an < bn end
            return al < bl
        end)
    end

    local function AddInfo(info, fallbackCategory)
        if not info then return end
        local name = info.name
        local skillLineID = info.skillLineID
        if skillLineID and WEAPON_SKILL_BY_ID[skillLineID] then
            name = WEAPON_SKILL_BY_ID[skillLineID].name
        end
        local rank = tonumber(info.rank) or 0
        local maxRank = tonumber(info.maxRank) or 0
        if rank <= 0 and maxRank <= 1 then return end
        local category = CategoryForSkillLine(skillLineID, name) or
                             fallbackCategory
        if name and category then AddSkill(name, rank, maxRank, category) end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines then
        local ok, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
        if ok and type(lines) == "table" then
            for _, skillLineID in ipairs(lines) do
                AddInfo(GetProfessionInfoBySkillLineID(skillLineID))
            end
        end
    end

    for _, entry in ipairs(CollectSkillInfoAPIEntries()) do
        AddInfo(entry)
    end

    for _, skill in ipairs(WEAPON_SKILL_IDS) do
        local rank, maxRank, _, skillLineID = GetSkillRankByID(skill.id)
        local name = skill.name
        local skillCategory = skill.category or "weapon"
        if rank and (rank > 0 or (maxRank and maxRank > 1)) then
            AddSkill(name, rank, maxRank or GetDefaultWeaponSkillCap(),
                     skillCategory)
        elseif skill.alwaysKnown or PlayerKnowsSpell(skill.spellID) then
            if rank or maxRank then
                AddSkill(name, rank or 0,
                         maxRank or GetDefaultWeaponSkillCap(), skillCategory)
            end
        end
        if skillLineID then
            AddInfo({
                name = name,
                rank = rank,
                maxRank = maxRank,
                skillLineID = skillLineID
            }, skillCategory)
        end
    end

    local hasSkillLines = false
    pcall(function()
        hasSkillLines = GetNumSkillLines ~= nil and GetSkillLineInfo ~= nil
    end)

    if hasSkillLines then
        if ExpandSkillHeader then pcall(ExpandSkillHeader, 0) end
        local numLines = GetNumSkillLines() or 0
        for i = 1, numLines do
            local ok, header = pcall(function()
                local name, isHeader, isExpanded = GetSkillLineInfo(i)
                if isHeader and not isExpanded and ExpandSkillHeader then
                    ExpandSkillHeader(i)
                end
                return isHeader
            end)
            if ok and header then numLines = GetNumSkillLines() or numLines end
        end

        local category = nil
        numLines = GetNumSkillLines() or 0
        for i = 1, numLines do
            local ok, name, isHeader, _, rank, _, _, maxRank, isAbandonable =
                pcall(GetSkillLineInfo, i)
            if ok then
                if isHeader then
                    local headerCategory = nil
                    pcall(function()
                        headerCategory = GetSkillHeaderCategory(name)
                    end)
                    category = headerCategory
                elseif name ~= nil and name ~= "" then
                    local skillCategory = category
                    local secondaryName = false
                    pcall(function()
                        secondaryName = IsSecondarySkillName(name)
                    end)
                    local weaponName = false
                    pcall(function()
                        weaponName = IsWeaponSkillName(name)
                    end)
                    if skillCategory == "skip" or IsBlockedSkillName(name) then
                        skillCategory = nil
                    elseif skillCategory == "profession" and secondaryName then
                        skillCategory = "secondary"
                    elseif IsStatSkillName(name) then
                        skillCategory = "stat"
                    elseif weaponName then
                        skillCategory = "weapon"
                    elseif skillCategory == "profession" or
                        skillCategory == "secondary" then
                        -- keep
                    elseif isAbandonable then
                        skillCategory = "profession"
                    else
                        skillCategory = nil
                    end
                    if skillCategory then
                        AddSkill(name, rank, maxRank, skillCategory)
                    end
                end
            end
        end
    end

    if GetProfessions and GetProfessionInfo then
        local indices = {GetProfessions()}
        for i, index in ipairs(indices) do
            if index then
                local name, _, rank, maxRank, _, _, skillLine =
                    GetProfessionInfo(index)
                local category = CategoryForSkillLine(skillLine, name)
                if not category then
                    if i <= 2 then
                        category = "profession"
                    else
                        category = "secondary"
                    end
                end
                AddSkill(name, rank, maxRank, category)
            end
        end
    end

    SortSkillList(catalog)
    SortSkillList(visible)
    if settings and (seededSelectable or hasChoices) then
        settings.mode = "selected"
        settings.includeAllSkills = nil
    end
    return visible, catalog
end

local function UpdateSkillsFrame()
    local ui = GetUI()
    if not ui or not ui.SetSkillsData then return end
    if ui.CreateSkillsFrame then ui.CreateSkillsFrame() end
    local visible, catalog = ScanClassicSkills()
    ui.SetSkillsData(visible, catalog)
end

addonTable.RefreshSkillsData = UpdateSkillsFrame

addonTable.RefreshAllData = function()
    local ui = GetUI()
    if not ui then return end
    UpdateXPFillBar()
    UpdateXPRemainingBar()
    UpdatePetXpBar()
    UpdateProfessionBars()
    UpdateSkillsFrame()
    UpdateReputationBar()
    UpdateLevelText(UnitLevel("player"))
    if ui.UpdateNameText then ui.UpdateNameText() end
end

local function CopyDefaults(src)
    local copy = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            copy[key] = CopyDefaults(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function MergeDefaults(dest, src)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dest[key]) ~= "table" then dest[key] = {} end
            MergeDefaults(dest[key], value)
        elseif dest[key] == nil then
            dest[key] = value
        end
    end
end

local function CanUseSavedStringKey(value)
    if type(value) ~= "string" then return false end
    local ok, usable = pcall(function()
        local probe = {}
        probe[value] = true
        return probe[value] == true and tostring(value) == value
    end)
    return ok and usable == true
end

local function ProfileUsesNumericFlags(profile)
    if type(profile) ~= "table" then return false end
    local streamer = profile.streamerMode
    if streamer == 1 or streamer == 0 then return true end
    local enabled = profile.bars and profile.bars.enabled
    if type(enabled) == "table" then
        for _, value in pairs(enabled) do
            if value == 1 or value == 0 then return true end
        end
    end
    return false
end

local function InitializeDB()
    -- SavedVariables are only available at ADDON_LOADED, not during file load.
    local existing = _G.VitalFrameDB
    local existingVersion = existing and tonumber(existing.dbVersion)
    local alreadyMigrated = type(existing) == "table" and
                                ProfileUsesNumericFlags(
                                    existing.profiles and
                                        existing.profiles.Default)
    local needsWipe = type(existing) ~= "table" or
                          (existingVersion ~= DB_VERSION and not alreadyMigrated)
    if needsWipe and Compat.IsForeverClient and Compat.IsForeverClient() then
        existing = {}
    elseif type(existing) ~= "table" then
        existing = {}
    end

    VitalFrameDB = existing
    _G.VitalFrameDB = VitalFrameDB
    VitalFrameDB.dbVersion = DB_VERSION
    VitalFrameDB.profiles = VitalFrameDB.profiles or {}
    VitalFrameDB.global = VitalFrameDB.global or {}
    VitalFrameDB.profileKeys = VitalFrameDB.profileKeys or {}
    VitalFrameDB.profiles.Default = VitalFrameDB.profiles.Default or
                                        CopyDefaults(defaults.profile)
    MergeDefaults(VitalFrameDB.profiles.Default, defaults.profile)
    MergeDefaults(VitalFrameDB.global, defaults.global)

    local playerName = UnitName("player")
    local realmName = GetRealmName and GetRealmName()
    if CanUseSavedStringKey(playerName) and
        CanUseSavedStringKey(realmName or "") then
        VitalFrameDB.profileKeys[playerName .. " - " .. realmName] = "Default"
    end

    db = {
        profile = VitalFrameDB.profiles.Default,
        global = VitalFrameDB.global
    }
end

local function ApplySavedSettingsNow()
    local ui = GetUI()
    if not ui then return end
    if ui.CreateVitalFrame then ui.CreateVitalFrame() end
    if ui.CreateSkillsFrame then ui.CreateSkillsFrame() end
    if ui.ApplySavedSettings then
        ui.ApplySavedSettings()
    elseif ui.ApplySavedFrameLayout then
        ui.ApplySavedFrameLayout()
    end
end

SLASH_VITALFRAME1 = "/vitalframe"
SLASH_VITALFRAME2 = "/vf"
SlashCmdList["VITALFRAME"] = function(msg)
    local command, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    arg = (arg or ""):lower()

    local ui = GetUI()
    if not ui then return end

    if command == "show" then
        if not ui.HasFrame() then
            ui.CreateVitalFrame()
        else
            ui.SetVitalFrameShown(true)
        end
        PrintMessage(L["Frame shown."])
        return
    end

    if command == "hide" and ui.HasFrame() then
        ui.SetVitalFrameShown(false)
        PrintMessage(L["Frame hidden."])
        return
    end

    if command == "reset" then
        if not ui.HasFrame() then ui.CreateVitalFrame() end
        ui.ResetToDefaults()
        ui.SetVitalFrameShown(true)
        PrintMessage(L["Position reset to center."])
        return
    end

    if command == "config" or command == "unlock" or command == "lock" or
        command == "options" then
        if ui.HasEditMode and ui.HasEditMode() then
            PrintMessage(L["Use Edit Mode to configure Vital Frame."])
            return
        end
        if not ui.HasFrame() then ui.CreateVitalFrame() end
        local shouldUnlock = command ~= "lock"
        if command == "config" or command == "options" or command == "unlock" then
            if command == "unlock" then
                shouldUnlock = true
            else
                shouldUnlock = not (ui.IsLayoutUnlocked and ui.IsLayoutUnlocked())
            end
        end
        if ui.SetLayoutUnlocked then ui.SetLayoutUnlocked(shouldUnlock) end
        if shouldUnlock then
            PrintMessage(L["Layout unlocked. Drag the frame or use the options panel."])
        else
            PrintMessage(L["Layout locked."])
        end
        return
    end

    ui.ToggleVitalFrame()
end

local registerEvent = Compat.RegisterEvent or function(frame, event)
    frame:RegisterEvent(event)
end
registerEvent(eventFrame, "ADDON_LOADED")
registerEvent(eventFrame, "EDIT_MODE_LAYOUTS_UPDATED")
registerEvent(eventFrame, "PLAYER_LOGIN")
registerEvent(eventFrame, "PLAYER_ENTERING_WORLD")
registerEvent(eventFrame, "PLAYER_LOGOUT")
registerEvent(eventFrame, "PLAYER_XP_UPDATE")
registerEvent(eventFrame, "PLAYER_LEVEL_UP")
registerEvent(eventFrame, "PLAYER_MAX_LEVEL_UPDATE")
registerEvent(eventFrame, "UPDATE_EXPANSION_LEVEL")
registerEvent(eventFrame, "UNIT_LEVEL")
registerEvent(eventFrame, "ENABLE_XP_GAIN")
registerEvent(eventFrame, "DISABLE_XP_GAIN")
registerEvent(eventFrame, "UPDATE_EXHAUSTION")
registerEvent(eventFrame, "UPDATE_FACTION")
registerEvent(eventFrame, "FACTION_STANDING_CHANGED")
registerEvent(eventFrame, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
registerEvent(eventFrame, "SKILL_LINES_CHANGED")
registerEvent(eventFrame, "UNIT_NAME_UPDATE")
registerEvent(eventFrame, "UNIT_PET")
registerEvent(eventFrame, "UNIT_PET_EXPERIENCE")
registerEvent(eventFrame, "CHARACTER_POINTS_CHANGED")
registerEvent(eventFrame, "CHAT_MSG_SKILL")
registerEvent(eventFrame, "PLAYER_EQUIPMENT_CHANGED")
registerEvent(eventFrame, "UNIT_INVENTORY_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local ui = GetUI()
    if not ui then return end

    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then InitializeDB() end
    elseif event == "PLAYER_LOGOUT" then
        if ui.SaveAllFramePositions then ui.SaveAllFramePositions() end
    elseif event == "PLAYER_LOGIN" then
        if not db then InitializeDB() end
        ApplySavedSettingsNow()
        ui.UpdateEditModeDragState()
        UpdateLevelText(UnitLevel("player"))
        UpdateXPFillBar()
        UpdateXPRemainingBar()
        UpdatePetXpBar()
        UpdateProfessionBars()
        UpdateSkillsFrame()
        UpdateReputationBar()
        if ui.UpdateNameText then ui.UpdateNameText() end
        if ui.HasEditMode and ui.HasEditMode() then
            PrintMessage(L["Loaded. Commands: /vitalframe (or /vf)."])
        else
            PrintMessage(L["Loaded. Commands: /vitalframe (or /vf). Use /vf config to move and edit."])
        end
    elseif event == "PLAYER_ENTERING_WORLD" or
        event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if not db then InitializeDB() end
        UpdateLevelText(UnitLevel("player"))
        UpdateXPFillBar()
        UpdateXPRemainingBar()
        UpdatePetXpBar()
        UpdateProfessionBars()
        UpdateSkillsFrame()
        UpdateReputationBar()
        if ui.UpdateNameText then ui.UpdateNameText() end
    elseif event == "UPDATE_EXHAUSTION" then
        UpdateXPFillBar()
        UpdateXPRemainingBar()
    elseif event == "PLAYER_XP_UPDATE" then
        UpdateXPFillBar()
        UpdateXPRemainingBar()
        UpdateLevelText(UnitLevel("player"))
    elseif event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        UpdateXPFillBar()
        UpdateXPRemainingBar()
        UpdateLevelText(newLevel or UnitLevel("player"))
    elseif event == "PLAYER_MAX_LEVEL_UPDATE" or event == "ENABLE_XP_GAIN" or
        event == "DISABLE_XP_GAIN" or event == "UPDATE_EXPANSION_LEVEL" then
        UpdateXPFillBar()
        UpdateXPRemainingBar()
        UpdateLevelText(UnitLevel("player"))
    elseif event == "UNIT_LEVEL" then
        local unit = ...
        if unit == "player" then
            UpdateXPFillBar()
            UpdateXPRemainingBar()
            UpdateLevelText(UnitLevel("player"))
        end
    elseif event == "FACTION_STANDING_CHANGED" then
        local factionID = ...
        SetLastGainedFactionID(factionID)
        ScanReputationGains()
        UpdateReputationBar()
    elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        local majorFactionID = ...
        SetLastGainedFactionID(majorFactionID)
        ScanReputationGains()
        UpdateReputationBar()
    elseif event == "UPDATE_FACTION" then
        ScanReputationGains()
        UpdateReputationBar()
    elseif event == "SKILL_LINES_CHANGED" or event == "CHARACTER_POINTS_CHANGED"
        or event == "CHAT_MSG_SKILL" then
        UpdateProfessionBars()
        UpdateSkillsFrame()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateSkillsFrame()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit == "player" then UpdateSkillsFrame() end
    elseif event == "UNIT_PET" or event == "UNIT_PET_EXPERIENCE" then
        UpdatePetXpBar()
    elseif event == "UNIT_NAME_UPDATE" then
        local unit = ...
        if unit == "player" and ui.UpdateNameText then ui.UpdateNameText() end
    end
end)

if EventRegistry then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
        local ui = GetUI()
        if ui then ui.UpdateEditModeDragState() end
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        local ui = GetUI()
        if ui then ui.UpdateEditModeDragState() end
    end)
end
