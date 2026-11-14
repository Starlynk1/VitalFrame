local addonName, addonTable = ...

-- Thin wrapper around LibSharedMedia-3.0. Everything here degrades to the
-- built-in Blizzard media when the library is not installed.
local Media = {}
addonTable.Media = Media

local LSM_MAJOR = "LibSharedMedia-3.0"

Media.DEFAULT_STATUSBAR = "Blizzard"
Media.DEFAULT_STATUSBAR_FILE = "Interface\\TargetingFrame\\UI-StatusBar"

-- Used when LibSharedMedia is missing so the texture picker still works.
local BUILTIN_STATUSBARS = {
    {name = "Blizzard", file = "Interface\\TargetingFrame\\UI-StatusBar"},
    {name = "Solid", file = "Interface\\Buttons\\WHITE8X8"},
    {
        name = "Blizzard Character Skills Bar",
        file = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
    }
}

local lsm
local triedLoad = false

local function LoadLibrary()
    if lsm then return lsm end
    if LibStub then lsm = LibStub(LSM_MAJOR, true) end
    if lsm or triedLoad then return lsm end
    triedLoad = true

    -- The standalone library is LoadOnDemand. OptionalDeps normally pulls it
    -- in, but load it explicitly in case the client skipped it.
    local loadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if loadAddOn then pcall(loadAddOn, LSM_MAJOR) end
    if LibStub then lsm = LibStub(LSM_MAJOR, true) end
    return lsm
end

function Media.GetLibrary() return LoadLibrary() end
function Media.HasLibrary() return LoadLibrary() ~= nil end

local function SortedNames(kind)
    local lib = LoadLibrary()
    if not lib then return {} end
    local ok, list = pcall(lib.List, lib, kind)
    if not ok or type(list) ~= "table" then return {} end
    local names = {}
    for _, name in ipairs(list) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local function Fetch(kind, name)
    local lib = LoadLibrary()
    if not lib or type(name) ~= "string" then return nil end
    -- noDefault = true so an unknown name returns nil instead of LSM's default.
    local ok, file = pcall(lib.Fetch, lib, kind, name, true)
    if ok and type(file) == "string" and file ~= "" then return file end
    return nil
end

-- Fonts ---------------------------------------------------------------------

function Media.ListFonts() return SortedNames("font") end
function Media.FetchFont(name) return Fetch("font", name) end

-- Status bar textures --------------------------------------------------------

-- Returns a sorted array of {name = ..., file = ...}.
function Media.ListStatusbars()
    local options = {}
    local seen = {}
    local names = SortedNames("statusbar")
    for _, name in ipairs(names) do
        local file = Fetch("statusbar", name)
        if file then
            options[#options + 1] = {name = name, file = file}
            seen[name] = true
        end
    end
    for _, builtin in ipairs(BUILTIN_STATUSBARS) do
        if not seen[builtin.name] then
            options[#options + 1] = builtin
            seen[builtin.name] = true
        end
    end
    table.sort(options, function(a, b) return a.name:lower() < b.name:lower() end)
    return options
end

function Media.IsStatusbar(name)
    if type(name) ~= "string" then return false end
    if Fetch("statusbar", name) then return true end
    for _, builtin in ipairs(BUILTIN_STATUSBARS) do
        if builtin.name == name then return true end
    end
    return false
end

function Media.FetchStatusbar(name)
    local file = Fetch("statusbar", name)
    if file then return file end
    for _, builtin in ipairs(BUILTIN_STATUSBARS) do
        if builtin.name == name then return builtin.file end
    end
    return Media.DEFAULT_STATUSBAR_FILE
end

-- Change notifications --------------------------------------------------------

-- Other addons can register media after VitalFrame loads. Listeners are told
-- so they can rebuild lists and re-apply saved choices that were not yet known.
local listeners = {}
local callbackRegistered = false
local notifyPending = false

local function Notify(_, mediaType)
    if mediaType ~= nil and mediaType ~= "font" and mediaType ~= "statusbar" then
        return
    end
    -- Many addons register media in a burst; collapse it into one refresh.
    if notifyPending then return end
    notifyPending = true
    local function run()
        notifyPending = false
        for _, listener in ipairs(listeners) do pcall(listener) end
    end
    local compat = addonTable.Compat
    if compat and compat.After then
        compat.After(0, run)
    else
        run()
    end
end

function Media.OnChanged(listener)
    if type(listener) ~= "function" then return end
    listeners[#listeners + 1] = listener
    if callbackRegistered then return end
    local lib = LoadLibrary()
    if lib and lib.RegisterCallback then
        callbackRegistered = true
        lib.RegisterCallback(Media, "LibSharedMedia_Registered", Notify)
    end
end
