-- BetterBags owns the item cell and its theme-specific upgrade icon. This module
-- only registers StatCoach's cap-aware yes/no upgrade verdict with that API.
local _, ns = ...

local integration = {}
ns.BetterBags = integration

function integration:Setup()
  if not ns.IsRetail or self.done then return end
  if type(ns.IsBagUpgrade) ~= "function" then
    self.status = "StatCoach upgrade API unavailable"
    return
  end

  local libStub = rawget(_G, "LibStub")
  if not libStub then
    self.status = "LibStub not registered"
    return
  end
  if type(libStub) ~= "table" then
    self.status = "LibStub malformed (expected table, got " .. type(libStub) .. ")"
    return
  end
  if type(libStub.GetLibrary) ~= "function" then
    self.status = "LibStub API missing GetLibrary (got " .. type(libStub.GetLibrary) .. ")"
    return
  end

  local ok, aceAddon = pcall(libStub.GetLibrary, libStub, "AceAddon-3.0", true)
  if not ok then
    self.status = "AceAddon-3.0 lookup failed: " .. tostring(aceAddon)
    return
  end
  if not aceAddon then
    self.status = "AceAddon-3.0 library not registered"
    return
  end
  if type(aceAddon.GetAddon) ~= "function" then
    self.status = "AceAddon-3.0 API missing GetAddon (got " .. type(aceAddon.GetAddon) .. ")"
    return
  end

  local loaded, betterBags = pcall(aceAddon.GetAddon, aceAddon, "BetterBags", true)
  if not loaded then
    self.status = "BetterBags lookup failed: " .. tostring(betterBags)
    return
  end
  if not betterBags then
    self.status = "BetterBags addon not registered"
    return
  end
  if type(betterBags.GetModule) ~= "function" then
    self.status = "BetterBags API missing GetModule (got " .. type(betterBags.GetModule) .. ")"
    return
  end

  local found, items = pcall(betterBags.GetModule, betterBags, "Items", true)
  if not found then
    self.status = "BetterBags Items lookup failed: " .. tostring(items)
    return
  end
  if not items then
    self.status = "BetterBags Items module not registered"
    return
  end
  if type(items.RegisterUpgradeProvider) ~= "function" then
    self.status = "BetterBags Items API missing RegisterUpgradeProvider (got "
      .. type(items.RegisterUpgradeProvider) .. ")"
    return
  end

  -- BetterBags resolves providers while it is drawing item data. A scoring
  -- failure must only hide this icon, never interrupt the bag refresh.
  local registered, err = pcall(items.RegisterUpgradeProvider, items, "StatCoach", function(data)
    local link = data and not data.isItemEmpty and data.itemInfo and data.itemInfo.itemLink
    if not link then return false end
    local scored, isUpgrade = pcall(ns.IsBagUpgrade, link)
    return scored and isUpgrade or false
  end)
  if not registered then
    self.status = "StatCoach provider registration failed: " .. tostring(err)
    return
  end

  self.done = true
  self.status = "registered OK - choose StatCoach in BetterBags -> Upgrade Icon Provider"
end
