local addonName, addonTable = ...

local Compat = {}
addonTable.Compat = Compat

function Compat.GetTocVersion()
    local toc = select(4, GetBuildInfo())
    return tonumber(toc) or 0
end

function Compat.IsForeverClient()
    local toc = Compat.GetTocVersion()
    if toc >= 16000 and toc < 20000 then return true end
    local version = GetBuildInfo()
    return type(version) == "string" and version:find("^1%.60") ~= nil
end

function Compat.IsClassicEraClient()
    if Compat.IsForeverClient() then return false end
    if WOW_PROJECT_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
        return true
    end
    local toc = Compat.GetTocVersion()
    return toc >= 10000 and toc < 16000
end

function Compat.IsRetailClient()
    return not Compat.IsForeverClient() and not Compat.IsClassicEraClient()
end

function Compat.HasEditMode()
    return EditModeManagerFrame ~= nil
end

function Compat.SupportsClassicSkills()
    return true
end

function Compat.SupportsPetXpLeveling()
    return not Compat.IsRetailClient()
end

function Compat.After(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
        return
    end

    local waiter = CreateFrame("Frame")
    waiter.elapsed = 0
    waiter:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
end

function Compat.RegisterEvent(frame, event)
    if not frame or not event then return false end
    return pcall(frame.RegisterEvent, frame, event)
end
