local addonName, addonTable = ...

local L = {}
setmetatable(L, {
    __index = function(t, key)
        rawset(t, key, key)
        return key
    end
})
addonTable.L = L
