--[[ StatCoach.lua
     Engine + UI. Reads level/class/spec + combat ratings + talent hit LIVE and
     shows stat priority (with your current values) + cap coach in a movable window.
     Slash: /statcoach or /stc   (reset = reset position)
]]--

local ADDON, ns = ...
local D = ns.Data

------------------------------------------------------------------------
-- Combat rating constants (use the client's own globals, with fallback id)
------------------------------------------------------------------------
local CR_HIT_MELEE  = _G.CR_HIT_MELEE  or 6
local CR_HIT_RANGED = _G.CR_HIT_RANGED or 7
local CR_HIT_SPELL  = _G.CR_HIT_SPELL  or 8
local CR_EXPERTISE  = _G.CR_EXPERTISE  or 24
local CR_VERSATILITY = _G.CR_VERSATILITY_DAMAGE_DONE or 29

-- Flavor: retail (Mainline) vs Classic. Retail has NO hit/expertise/defense caps;
-- it uses Crit/Haste/Mastery/Versatility (diminishing returns) + item level. The whole
-- Classic engine below stays untouched; retail routes to RefreshRetail() instead.
local RETAIL = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil
                and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- World of Warcraft: Forever reports itself as Mainline (WOW_PROJECT_ID 1, loads the
-- _Mainline TOC) but it is a Vanilla ruleset on that client: level 60, weapon skill
-- and defense, no Mastery or Versatility. The interface number tells them apart.
local FOREVER = RETAIL and (select(4, GetBuildInfo()) or 0) < 20000

-- Mists of Pandaria Classic (5.5.x) has a project id of its own, so RETAIL is false
-- there - but it is not TBC either: specializations like retail, hit and expertise
-- caps like TBC. The interface number is what tells it apart from the TBC client.
local MISTS = not RETAIL and (select(4, GetBuildInfo()) or 0) >= 50000
                         and (select(4, GetBuildInfo()) or 0) < 60000

-- Classic Era (1.15.x, also Season of Discovery and Hardcore) is neither of those:
-- Vanilla rules on the classic client - level 60, weapon skill, no ratings. A field,
-- not a local: this file sits at Lua's 200-local limit for one chunk.
ns.ERA = not RETAIL and (select(4, GetBuildInfo()) or 0) < 20000

-- The item and spec functions live in namespaces now. The old globals are already
-- gone on the newest Mainline-family client, while C_Item and C_SpecializationInfo
-- exist on every client this file runs on. Namespace first, global as the fallback.
local GetItemInfo              = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant       = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemIcon              = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local GetSpecialization        = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local GetSpecializationInfo    = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo

local function num(v) return v or 0 end
local function fmt(v) return string.format("%.1f", v or 0) end
local ceil = math.ceil

-- Call an API safely: returns nil if the function is missing or errors
local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return r[2], r[3], r[4], r[5] end
  return nil
end

-- Retail spec name -> the English key D.retail.classes is written in.
-- GetSpecializationInfo answers in the client's language, so on a non-English
-- client every spec lookup missed and the panel showed no data. The id does not
-- change with locale. Falls back to the name for an id we do not know yet.
-- Retail and Mists both pick a specialization; each has its own roster file.
-- (a field, not a local: this file sits at Lua's 200-local limit for one chunk)
ns.SpecData = function() return (MISTS and D and D.mists) or (D and D.retail) end

local function RetailSpecKey(id, name)
  local sdat = ns.SpecData()
  local map = sdat and sdat.SPECID
  return (id and map and map[id]) or name
end

------------------------------------------------------------------------
-- Talents that grant hit. Addressed by POSITION, not by name: GetTalentInfo
-- returns the talent's name in the client's language, so the old name table
-- matched nothing outside an English client and the hit bar quietly read zero
-- talent hit. Coordinates verified against TWO independent sources that ship
-- in this client - LibClassicInspector's TBC talent tables (TacoTip) and
-- CharacterStatsTBC - which agree on every talent both of them cover.
--
-- Per class: { tab, index, tier, column, maxRank, <school> = % per rank }.
-- tier/column/maxRank are an identity check, not decoration: if a tree is ever
-- renumbered under us we want to read NOTHING rather than read some other
-- talent's rank and report a confidently wrong hit total.
--
-- Note the name collision the old table could not express: Elemental Precision
-- is 1%/rank for a mage and 2%/rank for a shaman. Keyed by name, shamans were
-- credited the mage value - wrong on English clients too, now fixed.
------------------------------------------------------------------------
local HIT_TALENTS = {
  WARRIOR = { { 2, 17, 7, 1, 3, melee = 1 } },                        -- Precision (Fury)
  PALADIN = { { 2,  3, 2, 1, 3, melee = 1 } },                        -- Precision (Protection)
  ROGUE   = { { 2,  6, 2, 3, 5, melee = 1 } },                        -- Precision (Combat)
  HUNTER  = { { 3, 12, 4, 2, 3, ranged = 1 } },                       -- Surefooted (Survival)
  SHAMAN  = { { 3,  6, 3, 1, 3, melee = 1, ranged = 1, spell = 1 },   -- Nature's Guidance (Restoration)
              { 1, 15, 6, 1, 3, spell = 2 } },                        -- Elemental Precision (Elemental)
  MAGE    = { { 1,  2, 1, 2, 5, spell = 2 },                          -- Arcane Focus (Arcane)
              { 3,  3, 1, 3, 3, spell = 1 } },                        -- Elemental Precision (Frost)
  PRIEST  = { { 3,  5, 2, 3, 5, spell = 2 } },                        -- Shadow Focus (Shadow)
  WARLOCK = { { 1,  1, 1, 2, 5, spell = 2 } },                        -- Suppression (Affliction)
  DRUID   = { { 1, 16, 6, 3, 2, spell = 2 } },                        -- Balance of Power (Balance)
}

local function ReadTalentHit()
  local m, r, sp = 0, 0, 0
  -- GetNumTalentTabs is the classic-only gate the old loop relied on. It is not
  -- needed for the lookup any more, but it still tells us we are on a client
  -- whose GetTalentInfo takes (tab, index) - keep it, or retail would call this
  -- with coordinates that mean nothing there.
  if type(GetNumTalentTabs) ~= "function" or type(GetTalentInfo) ~= "function" then
    return m, r, sp
  end
  local _, class = UnitClass("player")
  for _, t in ipairs(HIT_TALENTS[class or ""] or {}) do
    local _, _, tier, column, rank, maxRank = GetTalentInfo(t[1], t[2])
    if rank and rank > 0 and tier == t[3] and column == t[4] and maxRank == t[5] then
      if t.melee  then m  = m  + t.melee  * rank end
      if t.ranged then r  = r  + t.ranged * rank end
      if t.spell  then sp = sp + t.spell  * rank end
    end
  end
  return m, r, sp
end

------------------------------------------------------------------------
-- Read the player's current stats (hit totals include talent hit)
------------------------------------------------------------------------
-- Draenei party auras grant hit that gear/talent numbers miss. Scan live buffs:
-- Heroic Presence = +1% melee/ranged hit, Inspiring Presence = +1% spell hit.
-- Buff NAMES are localized, so match the spell id (UnitBuff's 10th return).
-- 28878 is verified against CharacterStatsTBC, which reads the same aura.
-- The English names stay as a second chance purely so that an id which turns
-- out to be wrong can never take away what English clients already read.
local HEROIC_PRESENCE, INSPIRING_PRESENCE = 6562, 28878
local function ReadAuraHit()
  local m, sp = 0, 0
  if type(UnitBuff) ~= "function" then return m, sp end
  for i = 1, 40 do
    local name, _, _, _, _, _, _, _, _, spellID = UnitBuff("player", i)
    if not name then break end
    if spellID == HEROIC_PRESENCE or name == "Heroic Presence" then m = m + 1
    elseif spellID == INSPIRING_PRESENCE or name == "Inspiring Presence" then sp = sp + 1 end
  end
  return m, sp
end

-- True when an actual weapon sits in the off-hand (not shield/held item)
local function IsDualWielding()
  local oh = GetInventoryItemLink and GetInventoryItemLink("player", 17)
  if not oh then return false end
  local equipLoc = select(4, GetItemInfoInstant(oh))
  return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
end

-- TBC weapon-skill racials: +5 skill vs a boss lowers the yellow miss 9->6, the DW
-- white miss 28->25, and boss dodge enough that expertise caps at 24 instead of 26.
-- Each hand rolls its own weapon skill, so the discount only applies when EVERY
-- weapon involved benefits - a sword+dagger human keeps the standard caps.
-- Weapon KIND by subclass id, not by the item's subtype text: that text arrives
-- translated ("Schwerter"), so matching it against "Sword" failed on every
-- non-English client and quietly handed those players the wrong caps - a worse
-- outcome than showing nothing, because the bar looked right. Both handed
-- variants must be listed; "Sword" used to catch one- and two-handers for free.
local WSC = Enum and Enum.ItemWeaponSubclass
local RACIAL_WEAPONS = WSC and {
  Human = { [WSC.Sword1H] = true, [WSC.Sword2H] = true, [WSC.Mace1H] = true, [WSC.Mace2H] = true },
  Orc   = { [WSC.Axe1H] = true, [WSC.Axe2H] = true },
  Dwarf = { [WSC.Guns] = true },
  Troll = { [WSC.Bows] = true },
} or {}
local function weaponBenefits(link, kinds)
  if not link then return false end
  local subclassID = select(7, GetItemInfoInstant(link))
  return subclassID ~= nil and kinds[subclassID] == true
end
local function HasWeaponSkillRacial(forRanged)
  local _, race = UnitRace("player")
  local kinds = RACIAL_WEAPONS[race or ""]
  if not kinds then return false end
  if forRanged then
    return weaponBenefits(GetInventoryItemLink("player", 18), kinds)
  end
  local mh = GetInventoryItemLink("player", 16)
  if not weaponBenefits(mh, kinds) then return false end
  local oh = GetInventoryItemLink("player", 17)
  if oh then
    local equipLoc = select(4, GetItemInfoInstant(oh))
    if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
      if not weaponBenefits(oh, kinds) then return false end
    end
  end
  return true
end

local function ReadStats()
  local s = {}
  local rM = num(safe(GetCombatRatingBonus, CR_HIT_MELEE))
  local rR = num(safe(GetCombatRatingBonus, CR_HIT_RANGED))
  local rS = num(safe(GetCombatRatingBonus, CR_HIT_SPELL))
  local tM, tR, tS = ReadTalentHit()
  local aM, aS = ReadAuraHit()
  s.meleeHitTotal  = rM + tM + aM
  s.rangedHitTotal = rR + tR + aM
  s.spellHitTotal  = rS + tS + aS
  s.talentMelee, s.talentRanged, s.talentSpell = tM, tR, tS
  s.dualWield = IsDualWielding()

  -- Expertise skill: use GetExpertise if it exists, otherwise derive from rating
  local expSkill
  local ge = safe(GetExpertise)
  if type(ge) == "number" then expSkill = ge end
  if not expSkill then
    local expRating = num(safe(GetCombatRating, CR_EXPERTISE))
    expSkill = math.floor(expRating / D.RATING.expertise + 0.5)
  end
  s.expertiseSkill = expSkill or 0

  -- Total defense skill
  local base, mod = safe(UnitDefense, "player")
  s.defenseSkill = num(base) + num(mod)

  -- Tank avoidance (uncrushable math) + crit-taken reduction (feral uncrit)
  s.dodge = num(safe(GetDodgeChance))
  s.parry = num(safe(GetParryChance))
  s.block = num(safe(GetBlockChance))
  s.critTakenReduction = num(safe(GetCombatRatingBonus, CR_CRIT_TAKEN_MELEE))

  -- Racial-adjusted caps, computed ONCE here so the cap bars and the scoring
  -- engine's cap-gating can never disagree about where the cap sits.
  s.meleeRacial  = HasWeaponSkillRacial(false)
  s.rangedRacial = HasWeaponSkillRacial(true)
  s.capMeleeHit  = D.CAP.meleeSpecialHitPct - (s.meleeRacial and 3 or 0)
  s.capWhiteDW   = D.CAP.meleeWhiteDWHitPct - (s.meleeRacial and 3 or 0)
  s.capExpertise = D.CAP.expertiseSkill     - (s.meleeRacial and 2 or 0)
  s.capRangedHit = D.CAP.meleeSpecialHitPct - (s.rangedRacial and 3 or 0)
  return s
end

------------------------------------------------------------------------
-- Auto-detect class + spec
------------------------------------------------------------------------
local function DetectClass()
  local _, class = UnitClass("player")
  return class
end

local function DetectSpec(class)
  local cd = D.classes[class]
  if not cd then return nil end
  local tabs = (GetNumTalentTabs and GetNumTalentTabs()) or 3
  local bestIdx, bestPts = 1, -1
  for i = 1, tabs do
    local pts = 0
    if GetTalentTabInfo then
      local a, b, c, d2, e = GetTalentTabInfo(i)
      if type(c) == "number" then pts = c
      elseif type(e) == "number" then pts = e
      elseif type(d2) == "number" then pts = d2 end
    end
    if pts > bestPts then bestPts = pts; bestIdx = i end
  end
  if bestPts <= 0 then return nil end
  return cd.tabSpec[bestIdx] or cd.specOrder[1]
end

------------------------------------------------------------------------
-- Resolve: what we show right now (auto or manual override)
------------------------------------------------------------------------
local function Resolve()
  local db = StatCoachDB
  local detClass = DetectClass()
  local detSpec  = DetectSpec(detClass)

  local class, spec
  if db.manual then
    class = db.manualClass or detClass or "WARRIOR"
    if not D.classes[class] then class = "WARRIOR" end
    local cd = D.classes[class]
    spec = db.manualSpec
    if not (cd.specs and cd.specs[spec]) then spec = cd.specOrder[1] end
  else
    class = detClass or "WARRIOR"
    if not D.classes[class] then class = "WARRIOR" end
    spec = detSpec or D.classes[class].specOrder[1]
  end

  local level = UnitLevel("player") or 1
  local cm = db.contextMode
  local context
  if cm == "leveling" or cm == "preraid" or cm == "endgame" then context = cm
  else context = (level >= 70) and "preraid" or "leveling" end

  return class, spec, context, level, detClass, detSpec
end

------------------------------------------------------------------------
-- Cap bars for a given role (endgame only). Hit uses live totals.
------------------------------------------------------------------------
local R = D.RATING
local function CapBarsFor(role, s)
  local bars = {}
  local function overPct(cur, cap)
    local over = cur - cap
    if over >= 0.5 then return "capped (+" .. fmt(over) .. "% over)" else return "capped" end
  end
  local function overSkill(cur, cap)
    local over = cur - cap
    if over >= 1 then return "capped (+" .. math.floor(over + 0.5) .. " over)" else return "capped" end
  end
  local function hitBar(label, cur, cap, ratingPer)
    local need = cap - cur
    local done = need <= 0
    bars[#bars+1] = {
      kind = "hit",
      label = label, cur = cur, target = cap, frac = math.min(cur/cap, 1), done = done,
      needText = done and overPct(cur, cap) or ("need ~" .. ceil(need * ratingPer) .. " rating"),
      unit = "%",
    }
  end
  local function exp()
    local cap, cur = s.capExpertise, s.expertiseSkill
    local need = cap - cur
    local done = need <= 0
    bars[#bars+1] = {
      kind = "expertise",
      label = "Expertise -> " .. cap .. (s.meleeRacial and " (racial)" or ""),
      cur = cur, target = cap, frac = math.min(cur/cap, 1), done = done,
      needText = done and overSkill(cur, cap) or ("need ~" .. ceil(need * R.expertise) .. " rating"),
      unit = "",
    }
  end
  local function defense()
    local cap, cur = D.CAP.tankDefenseSkill, s.defenseSkill
    local need = cap - cur
    local done = need <= 0
    bars[#bars+1] = {
      kind = "defense",
      label = "Defense -> " .. cap, cur = cur, target = cap, frac = math.min(cur/cap, 1), done = done,
      needText = done and "uncrittable" or ("need ~" .. ceil(need * R.defense) .. " rating"),
      unit = "",
    }
  end
  local function uncrushable()
    -- Passive avoidance only: Shield Block / Holy Shield uptime pushes you over
    -- in practice, but a cap bar must show what your GEAR delivers standing still.
    local cap = D.CAP.uncrushablePct
    local cur = D.CAP.baseMissPct + s.dodge + s.parry + s.block - D.CAP.bossAvoidPenalty
    if cur < 0 then cur = 0 end
    local need = cap - cur
    local done = need <= 0
    -- Label/needText kept SHORT: the row is label(left) + value(right) in one
    -- line, and a long value string buries the label (seen live on Prot).
    bars[#bars+1] = {
      kind = "avoid",
      label = "Uncrushable", cur = cur, target = cap,
      frac = math.min(cur/cap, 1), done = done,
      needText = done and "no crushing blows" or ("need " .. fmt(need) .. "% (passive)"),
      unit = "%",
    }
  end
  local function feralUncrit()
    -- Ferals get uncrittable via resilience + defense-above-350, not Defense 490.
    local cap = D.CAP.feralUncritPct
    local fromDef = math.max(s.defenseSkill - 350, 0) * 0.04
    local cur = fromDef + s.critTakenReduction
    local need = cap - cur
    local done = need <= 0
    bars[#bars+1] = {
      kind = "avoid",
      label = "Uncrit (resil+def)", cur = cur, target = cap,
      frac = math.min(cur/cap, 1), done = done,
      needText = done and "uncrittable" or ("need " .. fmt(need) .. "% more"),
      unit = "%",
    }
  end

  local meleeTag  = s.meleeRacial and " (racial)" or ""
  local rangedTag = s.rangedRacial and " (racial)" or ""
  if role == "melee" or role == "meleeDW" then
    hitBar("Melee Hit -> " .. s.capMeleeHit .. "%" .. meleeTag, s.meleeHitTotal, s.capMeleeHit, R.meleeHit)
    if s.dualWield then
      -- Auto-swings while dual-wielding miss until 28% (25% w/ racial) - a soft
      -- goal (specials cap at 9%)
      hitBar("Auto-attacks (DW)", s.meleeHitTotal, s.capWhiteDW, R.meleeHit)
    end
    exp()
  elseif role == "ranged" then
    hitBar("Ranged Hit -> " .. s.capRangedHit .. "%" .. rangedTag, s.rangedHitTotal, s.capRangedHit, R.meleeHit)
  elseif role == "caster" then
    hitBar("Spell Hit -> " .. D.CAP.spellHitPct .. "%", s.spellHitTotal, D.CAP.spellHitPct, R.spellHit)
  elseif role == "tank" then
    defense()
    uncrushable()
    hitBar("Melee Hit (threat) -> " .. s.capMeleeHit .. "%" .. meleeTag, s.meleeHitTotal, s.capMeleeHit, R.meleeHit)
    exp()
  elseif role == "tankDruid" then
    feralUncrit()
  end
  return bars
end

local function isDmgMelee(role) return role == "melee" or role == "meleeDW" or role == "ranged" end

-- Resolve the priority list for a context (endgame may be phase-split: preraid vs endgame)
local function resolveList(sd, context)
  if context == "leveling" then return sd.leveling or {} end
  local eg = sd.endgame or {}
  if eg[1] then return eg end                          -- flat list (phase-independent)
  return eg[context] or eg.endgame or eg.preraid or {} -- phase table
end

------------------------------------------------------------------------
-- Trade advisor: cap-aware live ordering + a plain-language "NOW" line
------------------------------------------------------------------------
-- Is this priority entry a capped stat, and is that cap already met?
local function capInfo(entry, role, s)
  if entry:find("Hit") then
    local cur, cap
    if role == "caster" then cur, cap = s.spellHitTotal, D.CAP.spellHitPct
    elseif role == "ranged" then cur, cap = s.rangedHitTotal, s.capRangedHit
    else cur, cap = s.meleeHitTotal, s.capMeleeHit end
    return true, cur >= cap
  elseif entry:find("Expertise") then
    return true, s.expertiseSkill >= s.capExpertise
  elseif entry:find("Defense") then
    return true, s.defenseSkill >= D.CAP.tankDefenseSkill
  end
  return false, false
end

-- Build the display list: on leveling keep static (+weapon); at 70 sink met caps
local function buildDisplay(context, role, base, s)
  local display = {}
  if context == "leveling" then
    if isDmgMelee(role) then display[#display+1] = { text = "Weapon DPS" } end
    for _, v in ipairs(base) do display[#display+1] = { text = v } end
    return display
  end
  local active, done = {}, {}
  for _, v in ipairs(base) do
    local isCap, ok = capInfo(v, role, s)
    if isCap and ok then done[#done+1] = { text = v, done = true }
    else active[#active+1] = { text = v } end
  end
  for _, x in ipairs(active) do display[#display+1] = x end
  for _, x in ipairs(done)   do display[#display+1] = x end
  return display
end

-- One-line "what to favor / trade toward right now"
local function nowAdvice(context, role, base, s)
  if context == "leveling" then
    if isDmgMelee(role) then return "Take weapon & primary-stat upgrades. Don't sweat trading small stats yet." end
    if role == "caster" then return "Take Spell Power & Intellect upgrades. Stat ratios barely matter until 70." end
    return nil
  end
  if role == "healer" then return "No hard cap - take throughput (healing/crit), keep mana sustainable." end
  if role == "tankDruid" then return "Stack stamina & armor; agility covers uncrit. No defense cap to chase." end
  if role == "tank" then
    if s.defenseSkill < D.CAP.tankDefenseSkill then return "Below defense cap - prioritise Defense until uncrittable (490)." end
    if s.meleeHitTotal < s.capMeleeHit then return "Uncrittable. Now favor Hit/Expertise for threat, then stamina/avoidance." end
    return "Uncrittable & threat is solid - stack stamina/avoidance now."
  end
  local hitCur, hitCap, hitName
  if role == "caster" then hitCur, hitCap, hitName = s.spellHitTotal, D.CAP.spellHitPct, "Spell Hit"
  elseif role == "ranged" then hitCur, hitCap, hitName = s.rangedHitTotal, s.capRangedHit, "Hit"
  else hitCur, hitCap, hitName = s.meleeHitTotal, s.capMeleeHit, "Hit" end
  local topStat
  for _, v in ipairs(base) do
    if not capInfo(v, role, s) then topStat = v; break end
  end
  local expApplies = (role == "melee" or role == "meleeDW")
  if hitCur < hitCap then
    return "Below " .. hitName .. " cap - favor " .. hitName .. ", even trading " .. (topStat or "other stats") .. " for it."
  elseif expApplies and s.expertiseSkill < s.capExpertise then
    return hitName .. " capped. Now favor Expertise; trading some hit for expertise is fine."
  elseif expApplies and s.dualWield and hitCur < s.capWhiteDW then
    return "Caps met - favor " .. (topStat or "your top stat") ..
      ". DW: surplus hit still feeds your white swings (to " .. s.capWhiteDW .. "%), so don't dump it for nothing."
  else
    return "Caps met - favor " .. (topStat or "your top stat") .. ". Trade surplus hit/expertise for it."
  end
end


------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local UI = {}
local PRIO_MAX, BAR_MAX = 8, 6   -- classic needs 4 (def + uncrush + hit + exp); Forever up to 6 (2 hit + 3 weapons + defense)
local PAD = 12

------------------------------------------------------------------------
-- Gear compare: score a hovered item vs what you have equipped (cap-aware).
-- This is what beats Pawn: a stat you've already capped is scored ~0.
------------------------------------------------------------------------
local Refresh          -- forward declaration (assigned below)
local curCtx = {}      -- current role + weights, set each Refresh
local bagCache = {}    -- itemLink -> upgrade pct (false = not an upgrade); wiped each Refresh

local KEYMAP = {
  ITEM_MOD_STRENGTH_SHORT = "strength", ITEM_MOD_AGILITY_SHORT = "agility",
  ITEM_MOD_STAMINA_SHORT = "stamina", ITEM_MOD_INTELLECT_SHORT = "intellect",
  ITEM_MOD_SPIRIT_SHORT = "spirit", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_HIT_RATING_SHORT = "hit",
  ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
  ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellHit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellCrit",
  ITEM_MOD_HASTE_SPELL_RATING_SHORT = "spellHaste",
  ITEM_MOD_SPELL_POWER_SHORT = "spellPower", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spellPower",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing",
  -- mp5 answers to two different keys: TBC uses POWER_REGEN0, later clients the
  -- MANA_REGENERATION name. Map both - StatCoach ships to both.
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
  ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
  ITEM_MOD_BLOCK_RATING_SHORT = "blockRating", ITEM_MOD_RESILIENCE_RATING_SHORT = "resilience",
  RESISTANCE0_NAME = "armor",
}

local SLOTMAP = {
  INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_CHEST = {5},
  INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7}, INVTYPE_FEET = {8},
  INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
  INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16},
  INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_HOLDABLE = {17},
  INVTYPE_SHIELD = {17}, INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18},
}
local WEAPON_TYPES = {
  INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}
-- Weapon DPS only counts for the slot the class actually ATTACKS with:
-- melee weapon for melee roles, ranged weapon for hunters. A warrior's bow/thrown
-- (or a hunter's melee weapon) is a stat-stick -> its DPS must NOT be weighted.
local MELEE_WEAPONS = {
  INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
}
local RANGED_WEAPONS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- Armor proficiency: don't call a cloth/leather/mail piece an upgrade for a
-- plate class. Ranked by armor SUBCLASS ID - the subtype text is translated,
-- so a German client recognised no armor type at all and the check never fired.
local ASC = Enum and Enum.ItemArmorSubclass
-- The subclass IDs are stable in every flavor; the Enum is only a nicer name for
-- them. So fall back to the numbers, never to an EMPTY table - a client without
-- the Enum would silently turn the whole armor check off.
local ARMOR_RANK = {
  [(ASC and ASC.Cloth) or 1] = 1, [(ASC and ASC.Leather) or 2] = 2,
  [(ASC and ASC.Mail)  or 3] = 3, [(ASC and ASC.Plate)   or 4] = 4,
}
local ARMOR_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
local CLASS_ARMOR = {   -- straight to the rank; no name in the middle
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
  HUNTER = 3, SHAMAN = 3, EVOKER = 3,
  ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
  PRIEST = 1, MAGE = 1, WARLOCK = 1,
}
local ARMOR_SLOTS = {  -- slots where armor type matters (cloak/neck/rings/etc excluded)
  INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
  INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
}

-- Shields are a proficiency, not a preference. Only classes that are CERTAIN to be
-- locked out are named here; anything not on the list is left alone, so a wrong
-- guess can never hide a real upgrade. (Hunters keep shields in TBC - left off on
-- purpose.)
local NO_SHIELD = {
  MAGE = true, PRIEST = true, WARLOCK = true, ROGUE = true, DRUID = true,
  DEATHKNIGHT = true, DEMONHUNTER = true, MONK = true, EVOKER = true,
}

-- Weapons, same idea, one level more detailed. Subclass ids again - stable in every
-- flavor, and the only thing here that is not translated.
local WSC = Enum and Enum.ItemWeaponSubclass
local WEAPON_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local W = {
  AXE1  = (WSC and WSC.Axe1H)   or 0,  AXE2   = (WSC and WSC.Axe2H)    or 1,
  BOW   = (WSC and WSC.Bows)    or 2,  GUN    = (WSC and WSC.Guns)     or 3,
  MACE1 = (WSC and WSC.Mace1H)  or 4,  MACE2  = (WSC and WSC.Mace2H)   or 5,
  POLE  = (WSC and WSC.Polearm) or 6,  SWORD1 = (WSC and WSC.Sword1H)  or 7,
  SWORD2= (WSC and WSC.Sword2H) or 8,  STAFF  = (WSC and WSC.Staff)    or 10,
  FIST  = (WSC and WSC.Unarmed) or 13, DAGGER = (WSC and WSC.Dagger)   or 15,
  THROWN= (WSC and WSC.Thrown)  or 16, XBOW   = (WSC and WSC.Crossbow) or 18,
  WAND  = (WSC and WSC.Wand)    or 19, GLAIVE = (WSC and WSC.Warglaive) or 9,
}
local function wset(...)
  local t = {}
  for _, v in ipairs({ ... }) do t[v] = true end
  return t
end

-- What each class can NEVER swing. Written as a BAN list on purpose: a class that
-- is missing, or a weapon type I forgot, behaves exactly as before rather than
-- vanishing. Baseline is Classic proficiency (incl. what a weapon master can
-- train - "not trained yet" is not the same as "never"), with the retail
-- differences applied below.
-- Warglaives exist on retail only and belong to demon hunters alone, so every
-- other class bans them; on a classic client the id simply never comes up.
-- MONK, DEMONHUNTER and EVOKER were absent until 15 Sep 2026 (a monk got
-- "UPGRADE" on a bow it can never draw). Their lists are the proficiencies
-- each class launched with and has kept since:
--   monk         fist, 1H axe, 1H mace, 1H sword, polearm, staff
--   demon hunter warglaive, fist, 1H axe, 1H sword
--   evoker       dagger, fist, 1H axe, 1H mace, 1H sword, staff
local NO_WEAPON = {
  WARRIOR     = wset(W.WAND, W.GLAIVE),
  PALADIN     = wset(W.DAGGER, W.STAFF, W.FIST, W.BOW, W.GUN, W.XBOW, W.THROWN, W.WAND, W.GLAIVE),
  HUNTER      = wset(W.MACE1, W.MACE2, W.WAND, W.GLAIVE),
  ROGUE       = wset(W.AXE1, W.AXE2, W.MACE2, W.SWORD2, W.POLE, W.STAFF, W.WAND, W.GLAIVE),
  PRIEST      = wset(W.AXE1, W.AXE2, W.MACE2, W.SWORD1, W.SWORD2, W.POLE, W.FIST,
                     W.BOW, W.GUN, W.XBOW, W.THROWN, W.GLAIVE),
  SHAMAN      = wset(W.SWORD1, W.SWORD2, W.POLE, W.BOW, W.GUN, W.XBOW, W.THROWN, W.WAND, W.GLAIVE),
  MAGE        = wset(W.AXE1, W.AXE2, W.MACE1, W.MACE2, W.SWORD2, W.POLE, W.FIST,
                     W.BOW, W.GUN, W.XBOW, W.THROWN, W.GLAIVE),
  WARLOCK     = wset(W.AXE1, W.AXE2, W.MACE1, W.MACE2, W.SWORD2, W.POLE, W.FIST,
                     W.BOW, W.GUN, W.XBOW, W.THROWN, W.GLAIVE),
  DRUID       = wset(W.AXE1, W.AXE2, W.SWORD1, W.SWORD2, W.BOW, W.GUN, W.XBOW,
                     W.THROWN, W.WAND, W.GLAIVE),
  DEATHKNIGHT = wset(W.DAGGER, W.STAFF, W.FIST, W.BOW, W.GUN, W.XBOW, W.THROWN, W.WAND, W.GLAIVE),
  MONK        = wset(W.DAGGER, W.AXE2, W.MACE2, W.SWORD2, W.BOW, W.GUN, W.XBOW, W.THROWN,
                     W.WAND, W.GLAIVE),
  DEMONHUNTER = wset(W.DAGGER, W.MACE1, W.MACE2, W.AXE2, W.SWORD2, W.POLE, W.STAFF,
                     W.BOW, W.GUN, W.XBOW, W.THROWN, W.WAND),
  EVOKER      = wset(W.AXE2, W.MACE2, W.SWORD2, W.POLE, W.BOW, W.GUN, W.XBOW, W.THROWN,
                     W.WAND, W.GLAIVE),
}
if RETAIL then
  NO_WEAPON.ROGUE[W.AXE1] = nil   -- one-handed axes are a rogue weapon since Wrath
end

-- What the class can NEVER put on or pick up - a different question from off-type
-- armor further down. A warrior CAN wear a cloth belt; it is merely a bad idea, so
-- it is scored and (optionally) filtered. A mage will never wear mail or swing an
-- axe at all, so "upgrade" is not a wrong number there, it is a meaningless one.
-- Reported on CurseForge: mail read as BIG UPGRADE for a cloth-wearing mage,
-- because the old check only ever looked DOWNWARDS from the class's armor type.
local function cannotEquip(link)
  local _, playerClass = UnitClass("player")
  playerClass = playerClass or ""
  if type(GetItemInfoInstant) ~= "function" then return false end
  -- classID/subclassID, not itemType/subType: those two are translated.
  local _, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(link)
  if classID == WEAPON_CLASS_ID then
    local banned = NO_WEAPON[playerClass]
    return (banned and banned[subclassID]) == true
  end
  if classID ~= ARMOR_CLASS_ID then return false end
  local pref = CLASS_ARMOR[playerClass]
  if not pref then return false end
  if equipLoc == "INVTYPE_SHIELD" then return NO_SHIELD[playerClass] == true end
  if not ARMOR_SLOTS[equipLoc] then return false end
  local itemRank = ARMOR_RANK[subclassID]
  if not itemRank then return false end
  -- Classic trains plate and mail at 40; until then the ceiling is one tier lower,
  -- which is why a level 30 hunter must not be sent after mail either.
  local ceiling = pref
  if not RETAIL and pref >= 3 and (UnitLevel("player") or 1) < 40 then ceiling = pref - 1 end
  return itemRank > ceiling
end

local scanTip = CreateFrame("GameTooltip", "StatCoachScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Turn one of the game's own format strings into a Lua pattern. The game ships
-- these translated, so a pattern built from one matches in every language.
-- Placeholders become captures: %d and %s as usual, and %.1f-style floats too
-- (DPS_TEMPLATE is "(%.1f damage per second)").
local function fromGlobal(fmt)
  if type(fmt) ~= "string" then return nil end
  -- Park the format specifiers on sentinels FIRST so the escaping pass cannot
  -- mangle them, escape everything else, then put real captures in their place.
  local p = fmt:gsub("%%%d*%.?%d*f", "\1"):gsub("%%d", "\2"):gsub("%%s", "\3")
  p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("\1", "([%%d%%.,]+)"):gsub("\2", "(%%d+)"):gsub("\3", "(.-)")
  return p
end

-- DPS is the one number GetItemStats does not carry, so the weapon line still
-- has to be read off the tooltip. Built from DPS_TEMPLATE where the client has
-- it; the English wording stays as a last resort so nothing is lost if it does not.
local DPS_PATTERNS = {}
do
  local p = fromGlobal(rawget(_G, "DPS_TEMPLATE"))
  if p then DPS_PATTERNS[#DPS_PATTERNS + 1] = p end
  DPS_PATTERNS[#DPS_PATTERNS + 1] = "([%d%.]+) damage per second"
end

local function getWeaponDPS(link)
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetHyperlink, scanTip, link) then return nil end
  for i = 1, scanTip:NumLines() do
    local fs = _G["StatCoachScanTipTextLeft" .. i]
    local text = fs and fs:GetText()
    if text then
      for _, pat in ipairs(DPS_PATTERNS) do
        local dps = text:match(pat)
        -- Some locales group thousands with a comma and use a comma decimal;
        -- normalise to something tonumber understands.
        if dps then
          dps = dps:gsub("(%d),(%d%d%d)", "%1%2"):gsub(",", ".")
          local n = tonumber(dps)
          if n then return n end
        end
      end
    end
  end
  return nil
end

-- FALLBACK ONLY since 1.1.14. These patterns are English, which is exactly the
-- bug: on any other client not one of them matched, so every item scored as if
-- it had no stats at all and the whole gear compare was meaningless. The stats
-- now come from GetItemStats (below), which is keyed on ITEM_MOD_* names that
-- never change with language. This pass is kept for the one case that route
-- cannot serve: an item whose data the client has not cached yet, where
-- GetItemStats returns nothing and the tooltip may still have something.
-- Written with Pawn's "#" convention in mind - if these ever need to work in
-- other languages, they become a per-locale table rather than more code.
local PARSE = {
  { "improves hit rating by (%d+)",                    "hit" },
  { "increases hit rating by (%d+)",                   "hit" },
  { "%+(%d+) hit rating",                              "hit" },
  { "improves spell hit rating by (%d+)",              "spellHit" },
  { "%+(%d+) spell hit rating",                        "spellHit" },
  { "improves critical strike rating by (%d+)",        "crit" },
  { "increases critical strike rating by (%d+)",       "crit" },
  { "%+(%d+) critical strike rating",                  "crit" },
  { "improves spell critical strike rating by (%d+)",  "spellCrit" },
  { "increases attack power by (%d+)",                 "ap" },
  { "%+(%d+) attack power",                            "ap" },
  { "expertise rating by (%d+)",                       "expertise" },
  { "%+(%d+) expertise rating",                        "expertise" },
  { "improves haste rating by (%d+)",                  "haste" },
  { "%+(%d+) haste rating",                            "haste" },
  { "%+(%d+) strength",                                "strength" },
  { "%+(%d+) agility",                                 "agility" },
  { "%+(%d+) stamina",                                 "stamina" },
  { "%+(%d+) intellect",                               "intellect" },
  { "%+(%d+) spirit",                                  "spirit" },
  { "spells and effects by up to (%d+)",               "spellPower" },
  { "increases healing done by up to (%d+)",           "healing" },
  { "%+(%d+) healing",                                 "healing" },
  { "improves spell haste rating by (%d+)",            "spellHaste" },
  { "%+(%d+) spell haste rating",                      "spellHaste" },
  { "%+(%d+) spell critical strike rating",            "spellCrit" },
  { "(%d+) mana per 5 sec",                            "mp5" },
  { "increases defense rating by (%d+)",               "defense" },
  { "%+(%d+) defense rating",                          "defense" },
  { "%+(%d+) dodge rating",                            "dodge" },
  { "block value of your shield by (%d+)",             "blockValue" },
  { "%+(%d+) block value",                             "blockValue" },
}

-- The same lines, built from the CLIENT'S OWN wordings. The tooltip has to stay
-- the stat source here, so this is the only way it can speak another language.
-- The game uses two shapes, both harvested with /stc globals on 2.5.6:
--   "Improves hit rating by %s."  - the Equip: effect lines
--   "%c%d Agility"                - base stats and gems, i.e. "+22 Agility"
-- Gems and enchants also use the bare stat NAME ("+10 Hit Rating"), so the
-- _SHORT globals earn a pattern too - except for the five base stats, whose long
-- form already IS the "+N Name" shape and would otherwise count twice.
local function statPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:lower():gsub("%%c%%d", "\1"):gsub("%%d", "\1"):gsub("%%s", "\1")
  p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return (p:gsub("\1", "([%%d,]+)"))
end

-- Keeping each global's trailing period matters: it is what stops the plain
-- attack-power line from also swallowing "Increases attack power by 40 in Cat,
-- Bear, ... forms only", which the hand-written English patterns did count.
local STAT_GLOBALS = {
  { "hit",        { "ITEM_MOD_HIT_RATING", "ITEM_MOD_HIT_MELEE_RATING" }, { "ITEM_MOD_HIT_RATING_SHORT" } },
  { "spellHit",   { "ITEM_MOD_HIT_SPELL_RATING" },      { "ITEM_MOD_HIT_SPELL_RATING_SHORT" } },
  { "crit",       { "ITEM_MOD_CRIT_RATING", "ITEM_MOD_CRIT_MELEE_RATING" }, { "ITEM_MOD_CRIT_RATING_SHORT" } },
  { "spellCrit",  { "ITEM_MOD_CRIT_SPELL_RATING" },     { "ITEM_MOD_CRIT_SPELL_RATING_SHORT" } },
  { "ap",         { "ITEM_MOD_ATTACK_POWER" },          { "ITEM_MOD_ATTACK_POWER_SHORT" } },
  { "expertise",  { "ITEM_MOD_EXPERTISE_RATING" },      { "ITEM_MOD_EXPERTISE_RATING_SHORT" } },
  { "haste",      { "ITEM_MOD_HASTE_RATING", "ITEM_MOD_HASTE_MELEE_RATING" }, { "ITEM_MOD_HASTE_RATING_SHORT" } },
  { "spellHaste", { "ITEM_MOD_HASTE_SPELL_RATING" },    { "ITEM_MOD_HASTE_SPELL_RATING_SHORT" } },
  { "spellPower", { "ITEM_MOD_SPELL_DAMAGE_DONE", "ITEM_MOD_SPELL_POWER" },
                  { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" } },
  { "healing",    { "ITEM_MOD_SPELL_HEALING_DONE" },    { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" } },
  { "mp5",        { "ITEM_MOD_MANA_REGENERATION" },     { "ITEM_MOD_POWER_REGEN0_SHORT" } },
  { "defense",    { "ITEM_MOD_DEFENSE_SKILL_RATING" },  { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" } },
  { "dodge",      { "ITEM_MOD_DODGE_RATING" },          { "ITEM_MOD_DODGE_RATING_SHORT" } },
  { "blockValue", { "ITEM_MOD_BLOCK_VALUE" },           { "ITEM_MOD_BLOCK_VALUE_SHORT" } },
  { "strength",   { "ITEM_MOD_STRENGTH" } },
  { "agility",    { "ITEM_MOD_AGILITY" } },
  { "stamina",    { "ITEM_MOD_STAMINA" } },
  { "intellect",  { "ITEM_MOD_INTELLECT" } },
  { "spirit",     { "ITEM_MOD_SPIRIT" } },
}

local PARSE_LOCALE, LINES = {}, {}
do
  local covered = {}
  for _, entry in ipairs(STAT_GLOBALS) do
    local stat = entry[1]
    for _, g in ipairs(entry[2] or {}) do
      local p = statPattern(rawget(_G, g))
      if p then PARSE_LOCALE[#PARSE_LOCALE + 1] = { p, stat }; covered[stat] = true end
    end
    for _, g in ipairs(entry[3] or {}) do
      local name = rawget(_G, g)
      if type(name) == "string" and name ~= "" then
        local esc = name:lower():gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        PARSE_LOCALE[#PARSE_LOCALE + 1] = { "%+([%d,]+) " .. esc, stat }
        covered[stat] = true
      end
    end
  end
  -- Any stat the client had no wording for keeps its English pattern rather than
  -- silently dropping out. Per stat, so nothing can be counted from both lists.
  for _, p in ipairs(PARSE) do
    if not covered[p[2]] then PARSE_LOCALE[#PARSE_LOCALE + 1] = p end
  end

  -- Line shapes that are not stat formats: the two conditional lines to skip,
  -- the empty-socket names, and the bare "1048 Armor" line.
  local function prefixOf(fmt, fallback)
    local head = type(fmt) == "string" and (fmt:match("^(.-)%%s") or fmt) or nil
    head = head and head:gsub("%s+$", "")
    if not head or head == "" then return fallback end
    return head:lower():gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  end
  LINES.socketBonus = "^" .. prefixOf(rawget(_G, "ITEM_SOCKET_BONUS"), "socket bonus")
  LINES.setBonus = "^%(%d+%)%s*" .. prefixOf(rawget(_G, "ITEM_SET_BONUS"), "set:")
  -- Keep the socket's COLOUR, not just the fact that there is a hole: the advice
  -- line below has to name a red gem for a red socket.
  LINES.sockets = {}
  for _, g in ipairs({ { "EMPTY_SOCKET_RED", "red" }, { "EMPTY_SOCKET_YELLOW", "yellow" },
                       { "EMPTY_SOCKET_BLUE", "blue" }, { "EMPTY_SOCKET_META", "meta" },
                       { "EMPTY_SOCKET_PRISMATIC", "prismatic" } }) do
    local v = rawget(_G, g[1])
    if type(v) == "string" then LINES.sockets[v:lower()] = g[2] end
  end
  local armor = rawget(_G, "RESISTANCE0_NAME") or rawget(_G, "ARMOR")
  LINES.armor = "^([%d,]+) " .. (type(armor) == "string" and armor:lower() or "armor") .. "$"
end

local function statTableFromTooltip(link, patterns)
  patterns = patterns or PARSE_LOCALE
  local t = {}
  if type(link) ~= "string" then return t end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetHyperlink, scanTip, link) then return t end
  local english = (patterns == PARSE)
  for i = 2, scanTip:NumLines() do   -- skip line 1 (the item name)
    local fs = _G["StatCoachScanTipTextLeft" .. i]
    local text = fs and fs:GetText()
    if text then
      local low = text:lower()
      -- Skip CONDITIONAL lines - stats you don't actually have by equipping this item:
      --   "Socket Bonus: +6 Attack Power"  -> only pays out once the right gems are in
      --                                       (and the empty-socket credit below already
      --                                       accounts for the holes; counting both double-dips)
      --   "(2) Set: Increases attack power by 40." -> needs 2+ pieces of the set; a single
      --                                       tier piece would otherwise score the whole set
      local skip
      if english then
        skip = low:find("socket bonus", 1, true) ~= nil or low:match("^%(%d+%) set")
      else
        skip = low:match(LINES.socketBonus) ~= nil or low:match(LINES.setBonus) ~= nil
      end
      if not skip then
        for _, p in ipairs(patterns) do
          local n = low:match(p[1])
          if n then t[p[2]] = (t[p[2]] or 0) + (tonumber((n:gsub(",", ""))) or 0) end
        end
      end
      -- EMPTY sockets show as "Blue Socket" / "Yellow Socket" / etc. (a filled socket
      -- shows the gem's stat line instead, which the patterns above already count).
      local socketColor
      if english then socketColor = low:match("^(%a+) socket$")
      else socketColor = LINES.sockets[low] end
      if socketColor then
        t.__sockets = (t.__sockets or 0) + 1
        t.__socketColors = t.__socketColors or {}
        t.__socketColors[socketColor] = (t.__socketColors[socketColor] or 0) + 1
      end
      -- Base lines: "1048 Armor" / "39 Block" (commas stripped just in case)
      local armor = low:match(english and "^([%d,]+) armor$" or LINES.armor)
      if armor then t.armor = (t.armor or 0) + tonumber((armor:gsub(",", ""))) end
      -- The block line is the one wording the client ships no global for.
      local block = low:match("^(%d+) block$")
      if block then t.blockValue = (t.blockValue or 0) + tonumber(block) end
    end
  end
  return t
end

-- LAST RESORT ONLY - see the measurement note on statTable below. GetItemStats
-- is keyed on ITEM_MOD_* names that never change with language, which is why it
-- looked like the answer to the whole localisation problem; on 2.5.6 it simply
-- does not carry enough of the item to score one.
-- Deliberately NOT reading EMPTY_SOCKET_* here: on 2.5.6 those keys count every
-- socket the item has, filled or not, so they cannot answer "how many sockets
-- are still empty" - which is the only thing the score wants to know.
-- TBC reports mp5 one short of what the item says (verified against
-- CharacterStatsTBC, which corrects the same stat the same way).
local MP5_KEYS = { ITEM_MOD_POWER_REGEN0_SHORT = true, ITEM_MOD_MANA_REGENERATION_SHORT = true }

local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats

local function statTableFromStats(link)
  local t, any = {}, false
  if type(link) ~= "string" or type(GetStats) ~= "function" then return t, false end
  local ok, stats = pcall(GetStats, link)
  if not ok or type(stats) ~= "table" then return t, false end
  for key, val in pairs(stats) do
    if type(val) == "number" then
      local mapped = KEYMAP[key]
      if mapped then
        if MP5_KEYS[key] then val = val + 1 end
        t[mapped] = (t[mapped] or 0) + val
        any = true
      end
    end
  end
  return t, any
end

-- MEASURED 2026-08-16 on 2.5.6, and it settles the question the code comment
-- above the parser was warning about all along: on this client GetItemStats
-- returns the item's BASE stats only. Across 17 equipped items, strength,
-- agility, stamina and armor matched the tooltip exactly - and:
--   * hit and crit rating came back 0 on every item that carries them as an
--     "Equip: Improves ... rating by N" effect (9 and 6 items respectively),
--   * attack power came back consistently ONE low (37 vs 38, 29 vs 30, ...),
--     the same off-by-one this client has on mp5,
--   * socketed gems contributed nothing,
--   * EMPTY_SOCKET_* counted ALL sockets, gems in them or not, so trusting it
--     would have paid the empty-socket bonus on fully gemmed gear.
-- So the tooltip stays the source of truth here and GetItemStats is only a
-- last resort for an item the tooltip had nothing for. Making it primary would
-- have quietly under-scored most raid gear on every client, English included.
local function statTable(link)
  local t = statTableFromTooltip(link)
  if next(t) ~= nil then return t end
  return (statTableFromStats(link))
end

-- An empty socket is worth roughly one standard gem for your role. Without this,
-- a gemmed equipped item always beats a better item with empty sockets.
local SOCKET_GEM = {
  melee   = { stat = "strength",  amount = 8 },   -- Bold (+8 Str)
  meleeDW = { stat = "agility",   amount = 8 },   -- Delicate (+8 Agi)
  ranged  = { stat = "agility",   amount = 8 },
  caster  = { stat = "spellPower", amount = 12 }, -- Runed (+12 SpDmg)
  healer  = { stat = "healing",   amount = 22 },  -- Teardrop (+22 Heal)
  tank    = { stat = "stamina",   amount = 15 },  -- Solid (+15 Stam)
  tankDruid = { stat = "agility", amount = 8 },
}

local function effWeight(stat, w, role, s)
  if not w or w == 0 then return 0 end
  -- Cap-gating is based on your LIVE hit/expertise vs the +3-boss caps. This is correct
  -- at every level: below cap (leveling) hit counts full; at cap (raid) it's near-zero.
  if stat == "hit" then
    local cur = (role == "ranged") and s.rangedHitTotal or s.meleeHitTotal
    local cap = (role == "ranged") and s.capRangedHit or s.capMeleeHit
    if cur < cap then return w end
    -- Past the special cap: worthless for most, but a dual-wielder's auto-attacks
    -- keep missing until 28% (25% with a weapon-skill racial), so hit retains
    -- ~40% of its value there.
    if s.dualWield and role ~= "ranged" and cur < s.capWhiteDW then
      return 0.4 * w
    end
    return 0.05 * w
  elseif stat == "spellHit" then
    return (s.spellHitTotal >= D.CAP.spellHitPct) and (0.05 * w) or w
  elseif stat == "expertise" then
    return (s.expertiseSkill >= s.capExpertise) and (0.05 * w) or w
  elseif stat == "defense" then
    return (s.defenseSkill >= D.CAP.tankDefenseSkill) and (0.1 * w) or w
  end
  return w
end

-- "Classes: Paladin" is a hard lock the item API never shows: Veteran's Scaled
-- is plain plate to GetItemInfoInstant and paladin-only in reality. The line
-- exists only in the tooltip, and it is localized - so the pattern comes from
-- the client's own ITEM_CLASSES_ALLOWED global, and the player's class name
-- from UnitClass, which answers in the same language. Cached per item id.
local classLockTip = CreateFrame("GameTooltip", "StatCoachClassLockTip", nil, "GameTooltipTemplate")
classLockTip:SetOwner(UIParent, "ANCHOR_NONE")
local classLockCache = {}
local function ClassLocked(link)
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return false end
  local c = classLockCache[id]
  if c ~= nil then return c end
  local pat = fromGlobal(rawget(_G, "ITEM_CLASSES_ALLOWED"))
  if not pat then classLockCache[id] = false; return false end
  -- The class list sits at the END of its line, and fromGlobal's non-greedy
  -- capture would match the empty string there - anchor it or lock everyone out.
  pat = pat .. "$"
  classLockTip:ClearLines()
  classLockTip:SetHyperlink(link)
  -- An item the client has not cached yet renders a near-empty tooltip; caching
  -- "not locked" off that would freeze the wrong answer for the whole session.
  -- Answer false for now and ask again next hover, when the lines are there.
  if classLockTip:NumLines() < 2 then return false end
  local locked = false
  for i = 2, classLockTip:NumLines() do
    local fs = _G["StatCoachClassLockTipTextLeft" .. i]
    local txt = fs and fs:GetText()
    local list = txt and txt:match(pat)
    if list then
      local me = UnitClass("player")   -- localized, same language as the line
      locked = not list:find(me, 1, true)
      break
    end
  end
  classLockCache[id] = locked
  return locked
end

-- Is this piece a LOWER armor class than what the player prefers (mail on plate, etc.)?
-- Below 40 nothing is off-type: plate/mail upgrades don't exist yet, you wear what drops.
local function offTypeArmor(link)
  local _, playerClass = UnitClass("player")
  local prefRank = CLASS_ARMOR[playerClass or ""]
  if not prefRank or (UnitLevel("player") or 1) < 40 then return false end
  -- classID/subclassID, not itemType/subType: those two are translated as well.
  local _, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(link)
  if classID ~= ARMOR_CLASS_ID or not ARMOR_SLOTS[equipLoc] then return false end
  local itemRank = ARMOR_RANK[subclassID]
  return itemRank ~= nil and itemRank < prefRank
end

-- NOTE: the old 10% off-type haircut (armorMult) is GONE. Since 1.1.8 armor has an
-- explicit weight, so the armor loss of going off-type is already priced in - the
-- multiplier double-counted it, and (worse) penalized the EQUIPPED item as baseline,
-- making any same-armor-class candidate look ~10% better than it was. Found via a
-- real case: plate tank shoulders scored +2% over strictly better leather DPS
-- shoulders on a Fury. Users who never want off-type suggested have /stc armor.

-- gemmed = score the item as it WOULD be with a standard gem in every empty
-- socket. Off (the default) scores it as it is right now.
--
-- Empty sockets used to be credited at 70% of a gem in the one and only score,
-- and that was the wrong shape of answer, not the wrong number. Your equipped
-- item is scored with its REAL gems - they are printed in its tooltip - while a
-- candidate was credited for gems you do not own. The two sides were measured
-- differently and 70% just split the difference. It let a tank leg with three
-- empty sockets read as a 37% upgrade for a Fury warrior on the strength of
-- three rubies that were still in the auction house.
--
-- At a loot roll you cannot gem it first, so the honest question is "what
-- happens if I equip this now" and an empty socket is worth nothing yet. The
-- gemmed number is still computed - it is genuinely useful - but it is shown
-- beside the verdict instead of hidden inside it.
local function scoreItem(link, role, weights, s, gemmed)
  local t = statTable(link)
  local score = 0
  if t then
    for stat, val in pairs(t) do
      -- Only real, numeric stats are scored. The __ keys are bookkeeping the
      -- socket scan leaves behind (__sockets is a count, __socketColors is a
      -- TABLE), and multiplying one of those by a weight is how the bag view
      -- of a Baganator user goes blank. Type-check rather than name-check, so
      -- the next piece of bookkeeping cannot repeat it.
      if type(val) == "number" and stat:sub(1, 2) ~= "__" then
        score = score + val * effWeight(stat, weights[stat], role, s)
      end
    end
    -- 0.7, and it is not a fudge any more. The dishonest part was that the
    -- credit was ONE-SIDED - your gear scored with its real gems, a candidate
    -- credited for gems you do not own - and that nothing said the number
    -- assumed gems at all. Both are fixed above and in the verdict line.
    -- What is left for the discount to price is real: you do not own them yet,
    -- and SOCKET_GEM assumes the BEST gem in every hole, which nobody actually
    -- does - people gem for the socket bonus, or buy the cheaper cut. Full
    -- value read 58% on a leg that is worth about 37%, and 37% is the number
    -- that survives a look at the item.
    local g = gemmed and t.__sockets and SOCKET_GEM[role]
    if g then
      score = score + t.__sockets * g.amount * 0.7 * effWeight(g.stat, weights[g.stat], role, s)
    end
  end
  -- weapon DPS, only for the slot this role actually attacks with
  local equipLoc = select(4, GetItemInfoInstant(link))
  local dpsSlot
  if role == "ranged" then dpsSlot = RANGED_WEAPONS[equipLoc]
  else dpsSlot = MELEE_WEAPONS[equipLoc] end
  if dpsSlot and (weights.weaponDPS or 0) > 0 then
    local dps = getWeaponDPS(link)
    if dps then score = score + dps * weights.weaponDPS end
  end
  return score
end

------------------------------------------------------------------------
-- RETAIL gear scoring. Item level dominates (as it should - primary stat and
-- stamina scale with it); secondaries are weighted by the spec's priority order.
-- Uses C_Item.GetItemStats (retail API) instead of tooltip parsing.
------------------------------------------------------------------------
local RETAIL_MOD = {
  ITEM_MOD_CRIT_RATING_SHORT    = "Crit",
  ITEM_MOD_HASTE_RATING_SHORT   = "Haste",
  ITEM_MOD_MASTERY_RATING_SHORT = "Mastery",
  ITEM_MOD_VERSATILITY          = "Versatility",
}

-- Current retail spec data, cached in curCtx (false = detected "no data")
local function retailSpecSD()
  if curCtx.retailSd ~= nil then return curCtx.retailSd or nil end
  local _, class = UnitClass("player")
  local rc = D.retail and D.retail.classes and D.retail.classes[class]
  local specName
  local idx = safe(GetSpecialization)
  if idx and type(GetSpecializationInfo) == "function" then
    local sid, name = safe(GetSpecializationInfo, idx)
    specName = RetailSpecKey(sid, name)
  end
  local sd = rc and specName and rc.specs and rc.specs[specName] or nil
  curCtx.retailSd = sd or false
  return sd
end

local function retailItemScore(link, sd)
  local ilvl = num(safe(GetDetailedItemLevelInfo, link))
  local score = ilvl * 10   -- ilvl dominates by design
  local stats = safe((C_Item and C_Item.GetItemStats) or GetItemStats, link)
  if type(stats) == "table" then
    local prim
    if sd.primary == "Strength" then prim = stats.ITEM_MOD_STRENGTH_SHORT
    elseif sd.primary == "Agility" then prim = stats.ITEM_MOD_AGILITY_SHORT
    else prim = stats.ITEM_MOD_INTELLECT_SHORT end
    score = score + num(prim) * 1.0
    -- Secondary weights by priority rank: #1 = 0.82, #2 = 0.64, #3 = 0.46, #4 = 0.28
    local w = {}
    for i, st in ipairs(sd.stats or {}) do w[st] = 1.0 - i * 0.18 end
    for key, statName in pairs(RETAIL_MOD) do
      local v = stats[key]
      if v and w[statName] then score = score + v * w[statName] end
    end
    score = score + num(stats.ITEM_MOD_STAMINA_SHORT) * 0.05
  end
  return score
end

-- Retail has had no ranged slot since Warlords: bows, guns and crossbows are
-- two-handers that sit in the main hand, wands are one-handers there. Slot 18
-- is always empty on a modern client, so the old map sent a level-4 vendor gun
-- to "BIG UPGRADE (empty slot)" on a rogue wearing two 259 daggers (Shhz,
-- 15 Sep 2026). A two-hander must beat main-hand + off-hand COMBINED - the rule
-- the classic path already has - with one retail twist: a Titan's Grip warrior
-- already holding two of them is comparing for ONE slot, like a one-hander.
-- Returns the slots to look at and whether their scores are summed.
local function retailTwoHander(link)
  local _, _, _, loc, _, classID, subclassID = GetItemInfoInstant(link)
  if loc == "INVTYPE_2HWEAPON" then return true end
  if not RANGED_WEAPONS[loc] then return false end
  return not (classID == WEAPON_CLASS_ID and subclassID == W.WAND)
end
local function retailSlots(link, equipLoc)
  if RANGED_WEAPONS[equipLoc] and not retailTwoHander(link) then
    equipLoc = "INVTYPE_WEAPONMAINHAND"      -- a wand is a main-hand one-hander here
  end
  local mh = GetInventoryItemLink("player", 16)
  local oh = GetInventoryItemLink("player", 17)
  local mhTwoHander = mh and retailTwoHander(mh)
  if equipLoc == "INVTYPE_2HWEAPON" or RANGED_WEAPONS[equipLoc] then
    if oh and mhTwoHander then return { 16, 17 }, false end   -- Titan's Grip: replaces the weaker one
    return { 16, 17 }, true                                    -- takes both hands, must beat both
  end
  if mhTwoHander and not oh then
    -- The off-hand is not free: the two-hander is silently occupying it. An
    -- off-hand item means giving up the 2H entirely - a loadout decision, so
    -- stay silent rather than shout "BIG UPGRADE (empty slot)" at every shield
    -- a hunter or a staff caster hovers. A one-hander competes with the 2H
    -- itself, never with the "empty" slot.
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_WEAPONOFFHAND"
       or equipLoc == "INVTYPE_HOLDABLE" then return nil end
    if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then return { 16 }, false end
  end
  return SLOTMAP[equipLoc], false
end

local function retailEvalItem(link)
  if type(GetItemInfoInstant) ~= "function" then return nil end
  local sd = retailSpecSD()
  if not sd then return nil end
  local equipLoc = select(4, GetItemInfoInstant(link))
  if not equipLoc then return nil end
  if not SLOTMAP[equipLoc] then return nil end
  if cannotEquip(link) or ClassLocked(link) then return nil end
  local slots, combined = retailSlots(link, equipLoc)
  if not slots then return nil end
  local name = GetItemInfo(link) or (link:match("%[(.-)%]")) or "item"
  local itemScore = retailItemScore(link, sd)
  local eqScore
  for _, slot in ipairs(slots) do
    local eqLink = GetInventoryItemLink("player", slot)
    local sc = eqLink and retailItemScore(eqLink, sd) or 0   -- empty slot scores 0
    if combined then
      eqScore = (eqScore or 0) + sc
    elseif not eqScore or sc < eqScore then
      eqScore = sc
    end
  end
  local eq = eqScore or 0
  local delta = itemScore - eq
  local pct = (eq > 0) and (delta / eq * 100) or nil
  return { name = name, delta = delta, pct = pct }
end

-- Evaluate a hovered item; returns { name, delta, noEquip } or nil if not gear
-- Phase 1 of the denominator experiment: what SHOULD an upgrade percent mean?
-- Today's percent is relative to the old item in the slot, which inflates small
-- slots (a ranged stat-stick reads +32% while moving a few points). The honest
-- scale is delta over the WHOLE equipped gear score - but its tier thresholds
-- must be calibrated from real play, not guessed. So: behavior unchanged, and
-- with /stc calib ON every verdict quietly records BOTH percentages to
-- StatCoachDB.pctlog (capped, deduped) for reading off SavedVariables later.
local function CharTotalScore(role, weights, s)
  if curCtx.charTotal then return curCtx.charTotal end
  local total = 0
  for slot = 1, 18 do
    if slot ~= 4 then   -- shirt
      local l = GetInventoryItemLink("player", slot)
      if l then total = total + (scoreItem(l, role, weights, s) or 0) end
    end
  end
  curCtx.charTotal = total
  return total
end

local calibSeen = {}
local function CalibLog(link, equipLoc, r, role, weights, s)
  if not (StatCoachDB and StatCoachDB.calib) or not r then return end
  local log = StatCoachDB.pctlog
  if not log then log = {}; StatCoachDB.pctlog = log end
  if #log >= 500 or calibSeen[link] then return end   -- cap: SavedVariables is not a landfill
  calibSeen[link] = true
  local total = CharTotalScore(role, weights, s)
  local function r1(v) return v and math.floor(v * 10 + 0.5) / 10 or nil end
  log[#log + 1] = { n = r.name, loc = equipLoc, d = math.floor((r.delta or 0) + 0.5),
    ps = r1(r.pct), psg = r1(r.pctGemmed),
    pt = (total > 0) and r1((r.delta or 0) / total * 100) or nil,
    when = date("%m-%d %H:%M") }
end

local function evalItem(link)
  if FOREVER then return nil end   -- no verdicts without data: see the FOREVER path
  if MISTS then return nil end     -- Mists: caps and priority first, item verdicts later
  if ns.ERA then return nil end    -- Era: the same
  if RETAIL then return retailEvalItem(link) end
  if not curCtx.role or type(GetItemInfoInstant) ~= "function" then return nil end
  local equipLoc = select(4, GetItemInfoInstant(link))   -- instant: works even uncached
  if not equipLoc then return nil end
  local slots = SLOTMAP[equipLoc]
  if not slots then return nil end
  -- Armor you cannot equip at all is not an upgrade of any size: stay silent
  -- everywhere (no verdict, no badge, no number), not just in strict mode.
  if cannotEquip(link) or ClassLocked(link) then return nil end
  -- At max level the KIND of weapon is a build decision, and GearCoach's data
  -- names each spec's kinds. Three answers: YOUR kind -> judged on stats as
  -- always; ANOTHER spec's kind -> shown as that spec's business (its icon and
  -- the bare percent, none of our tier icons, no badge); NO spec's kind (a
  -- dagger, for a warrior) -> silence. Below max level nothing is gated, and
  -- without GearCoach nothing changes.
  local offspecIcon
  if type(_G.GearCoach_WeaponSpecInfo) == "function"
     and (UnitLevel("player") or 1) >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 70) then
    local classID, subclassID = select(6, GetItemInfoInstant(link))
    if classID == WEAPON_CLASS_ID then
      local kind, sicon = _G.GearCoach_WeaponSpecInfo(subclassID)
      if kind == nil then return nil end
      if kind == "other" then offspecIcon = sicon or "" end
    end
  end
  -- Strict armor filter (/stc armor): hide off-type armor entirely instead of the
  -- default soft penalty. Requested by users who never want cloth/leather suggested.
  if StatCoachDB and StatCoachDB.armorStrict and offTypeArmor(link) then return nil end
  local name = GetItemInfo(link) or (link and link:match("%[(.-)%]")) or "item"
  local role = curCtx.role
  local s = ReadStats()
  local weights = curCtx.weights or {}
  local itemScore = scoreItem(link, role, weights, s)
  -- Second pass with every empty socket filled, on BOTH sides of every
  -- comparison below, so "gemmed" compares two fully-gemmed items rather than
  -- your real gear against a candidate's wishful thinking.
  local itemGem = scoreItem(link, role, weights, s, true)
  local function pctOf(item, eq) return (eq > 0) and ((item - eq) / eq * 100) or nil end

  -- A two-hander occupies BOTH weapon slots: equipping it means giving up whatever is in
  -- the off-hand (a second weapon for a dual-wielder, a shield for a tank, a held item for
  -- a caster). So it must beat main-hand + off-hand COMBINED, not just the main-hand. This
  -- is why a 2H is (correctly) NOT an upgrade for a dual-wielding Fury warrior/rogue/etc.
  if equipLoc == "INVTYPE_2HWEAPON" then
    local eqScore, eqGem, vsNames = 0, 0, {}
    for _, slot in ipairs({16, 17}) do
      local eqLink = GetInventoryItemLink("player", slot)
      if eqLink then
        eqScore = eqScore + scoreItem(eqLink, role, weights, s)
        eqGem = eqGem + scoreItem(eqLink, role, weights, s, true)
        vsNames[#vsNames + 1] = GetItemInfo(eqLink) or "?"
      end
    end
    local r = { name = name, delta = itemScore - eqScore,
      pct = pctOf(itemScore, eqScore), pctGemmed = pctOf(itemGem, eqGem),
      vsName = (#vsNames > 0) and table.concat(vsNames, " + ") or "empty slot",
      offspec = offspecIcon }
    CalibLog(link, equipLoc, r, role, weights, s)
    return r
  end

  -- An EMPTY slot scores 0, so anything usable is (correctly) an upgrade for it.
  -- For two-slot types (rings/trinkets) we compare against the weakest of the two.
  -- Off-hand items while a TWO-HANDER is equipped: the "empty" off-hand is not
  -- actually free - equipping this means giving up the 2H entirely. That's a
  -- loadout decision, not a 1:1 comparison, so we stay silent instead of
  -- shouting "BIG UPGRADE (empty slot)" at every shield a 2H user hovers.
  if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_WEAPONOFFHAND"
     or equipLoc == "INVTYPE_HOLDABLE" then
    local mh = GetInventoryItemLink("player", 16)
    if mh then
      local mhLoc = select(9, GetItemInfo(mh))
      if mhLoc == "INVTYPE_2HWEAPON" then return nil end
    end
  end

  -- A one-hander while a two-hander is equipped: the off-hand isn't free either
  -- (same reasoning as above), so compare against the 2H itself - never against
  -- the "empty" slot the 2H is silently occupying.
  if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
    local mh = GetInventoryItemLink("player", 16)
    if mh and select(9, GetItemInfo(mh)) == "INVTYPE_2HWEAPON" then
      slots = { 16 }
    end
  end

  local eqScore, eqGem, vsLink
  for _, slot in ipairs(slots) do
    local eqLink = GetInventoryItemLink("player", slot)
    local sc = eqLink and scoreItem(eqLink, role, weights, s) or 0
    if not eqScore or sc < eqScore then
      eqScore, vsLink = sc, eqLink
      eqGem = eqLink and scoreItem(eqLink, role, weights, s, true) or 0
    end
  end
  local eq = eqScore or 0
  local r = { name = name, delta = itemScore - eq,
    pct = pctOf(itemScore, eq), pctGemmed = pctOf(itemGem, eqGem or 0),
    vsName = vsLink and (GetItemInfo(vsLink) or "?") or "empty slot",
    offspec = offspecIcon }
  CalibLog(link, equipLoc, r, role, weights, s)
  return r
end

-- THE number, for every surface. An item with empty sockets is judged on what
-- it becomes once they are filled. This lives in one place on purpose: the
-- badge on the item and the verdict in its tooltip must never name different
-- tiers for the same thing, and they would drift the moment each picked its own.
local function shownPct(r)
  if not r then return nil end
  if r.pctGemmed and r.pct and r.pctGemmed > r.pct + 0.5 then return r.pctGemmed, true end
  return r.pct, false
end

-- How small an upgrade is still worth mentioning. Presentation only: the score
-- is unchanged, this is just how low StatCoach will open its mouth. Someone in
-- raid gear wants 10%+ and nothing else; someone levelling wants every scrap.
-- Same reason as shownPct for living in one place - the badge and the tooltip
-- must agree on what counts, or an item gets a badge and no verdict.
local function badgeFloor()
  return (StatCoachDB and StatCoachDB.minUpgrade) or 1
end

-- Upgrade % for a bag item vs equipped (nil if not an upgrade); cached per link
local function bagUpgradePct(link)
  if not link or not StatCoachDB.bagBadge then return nil end
  if not curCtx.role and not RETAIL then return nil end
  local c = bagCache[link]
  if c == nil then
    local r = evalItem(link)
    local p = shownPct(r)
    -- pct == nil with a positive delta means the slot is EMPTY -> big upgrade
    local floor = badgeFloor()
    -- our badges mark YOUR build's gear; another spec's weapon gets only its
    -- tooltip line, never a glowing icon in your bags
    local up = r and not r.offspec and ((p and p > floor) or (p == nil and (r.delta or 0) > 1))
    c = up and (p or 100) or false
    bagCache[link] = c
  end
  return c or nil
end

-- Verdict label + colours (hex for panel, r,g,b for tooltip)
-- Only surface UPGRADES; downgrades / sidegrades / non-comparable show nothing (nil)
-- Colour scale: green arrow = solid upgrade, gold arrow = strong (10%+),
-- PURPLE SKULL = BIG upgrade (25%+ / empty slot) - it kills your old item.
local function verdictOf(r)
  -- Icon size is configurable (/stc icon N, default 14); the skull stays 2px bigger.
  local sz = (StatCoachDB and StatCoachDB.iconSize) or 14
  -- The badge on bags and quest rewards is a "+", so the tooltip says "+" too.
  -- It used to be a gold arrow texture in BOTH upgrade tiers, which meant the
  -- green tier drew a gold icon next to green text - the one place the two
  -- surfaces disagreed. A plain glyph also takes the line's colour, which an
  -- inline texture cannot: |T has no tint, so a green "+" was never possible
  -- as an image. The glow and the pulse stay behind on the badge; a tooltip
  -- line is static text and nothing can animate inside it.
  local UP_PLUS  = "+ "
  local UP_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:" .. (sz + 2) .. ":" .. (sz + 2) .. ":0:2|t "
  if r.notUsable or r.noEquip then return nil end
  -- Another spec's weapon: the verdict reads exactly as always - same words,
  -- same tiers, same colours - but that spec's ICON opens the line (icon, never
  -- a spec name in text), and OUR tier icon steps to the END of it. Order on an
  -- offspec line: [spec-icon] WORDS (+%) [our icon]. On your own gear the line
  -- is untouched: [our icon] WORDS (+%).
  local specIc = ""
  if r.offspec and r.offspec ~= "" then
    specIc = "|T" .. r.offspec .. ":" .. sz .. ":" .. sz .. ":0:2|t "
  end
  -- Adams kald: our tier icon closes EVERY verdict line - own gear included.
  -- [spec-icon if offspec] WORDS (+%) [our icon].
  local function order(ownIc, body)
    return specIc .. body .. "  " .. ownIc
  end
  -- An item with empty sockets is judged on what it becomes once they are
  -- filled - that is the version you will actually wear, and nobody leaves
  -- sockets empty. So the headline number is the GEMMED comparison, at full
  -- gem value: the 70% discount that used to sit here was an attempt to be
  -- half-honest about an assumption that was never stated out loud.
  --
  -- Stating it costs one word and makes the discount unnecessary. Both sides
  -- of the comparison are scored fully gemmed, so it stays a fair fight rather
  -- than your real gear against a candidate's wishful thinking - which is what
  -- the old one-sided credit actually was.
  local p, assumesGems = shownPct(r)
  local gem = assumesGems and "   |cff8d8279(once gemmed)|r" or ""
  if p == nil then
    if r.delta and r.delta > 1 then
      return order(UP_SKULL, "BIG UPGRADE  (empty slot)"), "bf5aff", 0.75, 0.35, 1
    end
    return nil
  end
  -- The floor comes BEFORE the tiers, not after: a 15% item reaches the gold
  -- branch and returns from there, so a floor checked further down would never
  -- see it and "only tell me about 25%+" would silently do nothing.
  if p <= badgeFloor() then return nil end
  if p >= 25 then
    return order(UP_SKULL, string.format("BIG UPGRADE  (+%d%%)", math.min(math.floor(p + 0.5), 999)) .. gem), "bf5aff", 0.75, 0.35, 1
  end
  -- Amber, not Blizzard's own gold (ffd100): the strong tier must not wear the
  -- same colour as every highlighted line the client itself draws.
  if p >= 10 then
    return order(UP_PLUS, string.format("UPGRADE  (+%d%%)", math.floor(p + 0.5)) .. gem), "ffb020", 1, 0.69, 0.13
  end
  -- No condition left to test: the floor above already sent everything smaller
  -- home, so anything still here is an upgrade worth naming.
  -- Mint, not equip-green (00ff00): the solid tier drowned between the
  -- client's own "Equip:" lines in exactly the colour we used to borrow.
  return order(UP_PLUS, string.format("UPGRADE  (+%d%%)", math.floor(p + 0.5)) .. gem), "40ff9a", 0.25, 1, 0.6
end

-- Add our verdict to any item tooltip so the player notices without opening the panel.
-- IMPORTANT: append the line SYNCHRONOUSLY (no C_Timer / no extra tt:Show). The tooltip
-- sizes itself once, right after this hook returns, so a line added here is part of that
-- first layout -> no resize, no flicker. A deferred AddLine + Show grows the tooltip a
-- frame later, which makes it "jump" (and fights comparison/shopping-tooltip addons).
-- We guard on link so a re-fire for the same item on the same tooltip won't double-add.
-- "(once gemmed)" promises a number without saying what to put in the holes.
-- This says it: the gem this ROLE wants for each empty socket, swapping the
-- yellow pick for the hit gem while you are still under the cap - the same
-- rule the GEMS window follows, applied to the item you are looking at.
local function BelowHitCap(role, s)
  if role == "caster" then return s.spellHitTotal < D.CAP.spellHitPct end
  if role == "ranged" then return s.rangedHitTotal < s.capRangedHit end
  if role == "melee" or role == "meleeDW" then return s.meleeHitTotal < s.capMeleeHit end
  return false
end

-- Which gem belongs in a socket of each colour, for the player's role right now.
local function GemPicks(link)
  if RETAIL or MISTS or ns.ERA then return nil end
  local role = curCtx and curCtx.role
  local list = role and D.GEMS and D.GEMS[role]
  if not list then return nil end
  local t = statTable(link)
  local cols = t and t.__socketColors
  if not cols then return nil end
  local below = BelowHitCap(role, ReadStats())
  -- Quality 4 = epic. Everything below it (and anything the client has not
  -- cached yet, which reports nil) is treated as gear on the way to something
  -- better, so it is pointed at the affordable stone.
  local quality = select(3, GetItemInfo(link))
  local epicItem = (quality or 0) >= 4
  local picks, any = {}, false
  for color in pairs(cols) do
    -- A prismatic socket takes any gem, so it gets the primary-stat pick.
    local want = (color == "prismatic") and "red" or color
    for _, e in ipairs(list) do
      -- e.label marks the alternative rows (the honor gem); the first plain
      -- entry of a colour is the recommendation.
      if e.color == want and not e.label then
        local nm, id = e.name, e.id
        if e.hitName and below then nm, id = e.hitName, e.hitId end
        -- The gem's tier follows the ITEM's tier, not the player's wallet:
        -- an epic piece is worth the epic stone, anything below it gets the
        -- rare cut of the same gem. Recommending a 500g Crimson Spinel for a
        -- blue you replace next week is advice nobody can afford to take.
        if not epicItem then
          local rareNm, rareId
          if e.hitName and below then rareNm, rareId = e.hitRare, e.hitRareId
          else rareNm, rareId = e.rare, e.rareId end
          if rareNm then nm, id = rareNm, (rareId or id) end
        end
        picks[color] = { name = nm, icon = id and GetItemIcon and GetItemIcon(id) or nil }
        any = true
        break
      end
    end
  end
  return any and picks or nil
end

-- Put the recommendation where the question is asked: on the socket's own line,
-- in the tooltip's empty right-hand column. No extra lines, no icons, no words
-- beyond the gem's name - the tooltip already says "Red Socket", we just answer
-- it. Applied on every fresh tooltip because the client rebuilds the lines.
-- Font strings are reused across every item the tooltip shows, so a line we
-- shrank for a gem name would keep the small font on the NEXT item's "Speed
-- 1.50". Remember what we changed and hand it back before touching anything.
local shrunk = {}
local function RestoreHintFonts()
  for fs, f in pairs(shrunk) do
    if f[1] then pcall(fs.SetFont, fs, f[1], f[2], f[3]) end
    shrunk[fs] = nil
  end
end

local function ApplyGemHints(tt, link, worthGemming)
  RestoreHintFonts()
  -- Own switch in the minimap menu, on unless turned off (nil = on, so nobody
  -- who never opens the menu misses the feature).
  if StatCoachDB and StatCoachDB.gemHints == false then return end
  -- Only where there is something to gem FOR. Naming a gem on every socketed
  -- item in the world - vendor junk, auction browsing, gear you will never
  -- wear - is noise, and the hint means "if you take this, fill it with X".
  if not worthGemming then return end
  local picks = GemPicks(link)
  if not picks then return end
  local base = tt.GetName and tt:GetName()
  if not base then return end
  local sz = (StatCoachDB and StatCoachDB.iconSize) or 14
  for i = 2, tt:NumLines() do
    local left = _G[base .. "TextLeft" .. i]
    local text = left and left:GetText()
    if text then
      local low = text:lower()
      local color = low:match("^(%a+) socket$") or LINES.sockets[low]
      local pick = color and picks[color]
      if pick then
        local right = _G[base .. "TextRight" .. i]
        if right then
          -- The gem's own icon leads; its name follows in a smaller font so it
          -- reads as a caption rather than another line of tooltip text. A
          -- tooltip line has a fixed height, so the caption sits beside the
          -- icon - underneath it would overlap the socket line below.
          local font, fsize, flags = right:GetFont()
          if font then
            shrunk[right] = { font, fsize, flags }
            pcall(right.SetFont, right, font, math.max((fsize or 12) - 3, 8), flags)
          end
          local ic = pick.icon and ("|T" .. pick.icon .. ":" .. sz .. ":" .. sz .. ":0:0|t ") or ""
          right:SetText(ic .. pick.name)
          right:SetTextColor(0.4, 1, 0.72)   -- the Coach mint, quietly
          right:Show()
        end
      end
    end
  end
end

local function AddVerdict(tt, link, resize)
  if not link then RestoreHintFonts(); return end
  local r = evalItem(link)
  UI.hover = r
  if Refresh then Refresh() end
  if not r then RestoreHintFonts(); return end
  if tt.scLink == link then return end   -- already added our line for this item on this tooltip
  tt.scLink = link
  -- The socket hint answers a different question than the verdict does, so it
  -- keeps its own switch and still appears with the verdict line turned off -
  -- but only on items the verdict would call an upgrade.
  local label, _, cr, cg, cb = verdictOf(r)
  ApplyGemHints(tt, link, label ~= nil)
  if not (StatCoachDB and StatCoachDB.tooltip) then return end
  if not label then return end
  tt:AddLine(" ")   -- spacer: our block stands on its own at the bottom, Pawn-style
  -- The prefix speaks in the Coach series' mint - the one colour no Blizzard
  -- tooltip line uses, and the same voice TrinketCoach already answers in.
  tt:AddLine("|cff33ff99StatCoach:|r " .. label, cr, cg, cb)
  -- The post-hooks below run AFTER the tooltip has sized itself, so they must
  -- re-Show to fit the new line. The OnTooltipSetItem path must NOT (no flicker).
  if resize then tt:Show() end
end

-- Retail removed the OnTooltipSetItem script (Dragonflight+); it uses the
-- TooltipDataProcessor pipeline instead. Classic keeps the classic hook.
if (RETAIL or MISTS) and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
    if tt ~= GameTooltip then return end
    local link
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
      local _, l = TooltipUtil.GetDisplayedItem(tt)
      link = l
    elseif tt.GetItem then
      local _, l = tt:GetItem()
      link = l
    end
    AddVerdict(tt, link, false)
  end)
else
  GameTooltip:HookScript("OnTooltipSetItem", function(tt)
    local _, link = tt:GetItem()
    AddVerdict(tt, link, false)
  end)
end
-- Reset the guard whenever the tooltip is cleared/rebuilt. This fires on every rebuild
-- (including in-place refreshes), so our line re-appears after a clear but never doubles
-- up on a same-build double-fire of OnTooltipSetItem.
GameTooltip:HookScript("OnTooltipCleared", function(tt) tt.scLink = nil end)

-- Quest log rewards, quest-giver rewards and dungeon loot rolls don't always expose
-- the item link through tt:GetItem(), so fetch it explicitly via post-hooks.
-- The scLink guard prevents a double line when GetItem() DID work.
if type(hooksecurefunc) == "function" then
  if GameTooltip.SetQuestLogItem and type(GetQuestLogItemLink) == "function" then
    hooksecurefunc(GameTooltip, "SetQuestLogItem", function(tt, itemType, index)
      AddVerdict(tt, GetQuestLogItemLink(itemType, index), true)
    end)
  end
  if GameTooltip.SetQuestItem and type(GetQuestItemLink) == "function" then
    hooksecurefunc(GameTooltip, "SetQuestItem", function(tt, itemType, index)
      AddVerdict(tt, GetQuestItemLink(itemType, index), true)
    end)
  end
  if GameTooltip.SetLootRollItem and type(GetLootRollItemLink) == "function" then
    hooksecurefunc(GameTooltip, "SetLootRollItem", function(tt, rollID)
      AddVerdict(tt, GetLootRollItemLink(rollID), true)
    end)
  end
end

local function MakeButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetHeight(20)
  b:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  b:SetBackdropColor(0.18, 0.18, 0.22, 0.9)
  b:SetBackdropBorderColor(0, 0, 0, 1)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  fs:SetWordWrap(false)
  b.text = fs
  b:SetScript("OnEnter", function(self) self:SetBackdropColor(0.28, 0.28, 0.34, 1) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropColor(0.18, 0.18, 0.22, 0.9) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", onClick)
  b.SetLabel = function(self, t)
    self.text:SetWidth(0)   -- reset any clamp from a previous layout pass
    self.text:SetText(t)
    self:SetWidth(self.text:GetStringWidth() + 16)
  end
  return b
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Secondary-stat radar (retail). Four axes, Wowhead's layout: Crit top,
-- Mastery right, Versatility bottom, Haste left.
--
-- Plotted from the same PERCENTAGES the character sheet shows, so the shape can
-- always be checked against the bars above it and against Blizzard's own panel.
-- Ratings would arguably be the fairer currency - versatility costs the most
-- rating per percent, so a rating radar makes it the longest arm while the
-- character sheet calls it the second smallest stat - but a chart that
-- contradicts the game's own numbers reads as broken, whatever its merits.
--
-- Axes run to a FIXED maximum, not to your own biggest stat. Scaling to the
-- peak was wrong: your largest stat then always touches the rim, so stripping
-- every piece of gear left the shape almost unchanged - it could show balance
-- but never size. With a fixed axis the whole diamond shrinks as stats drop,
-- which is what anyone comparing two sets of gear expects to see.
-- The axis still grows if a stat passes the ceiling, so nothing ever clips.
-- A gentle curve keeps a 50% mastery from crushing three 12% stats out of view;
-- it preserves the order and still moves with every point.
------------------------------------------------------------------------
-- The key lives in the top-left corner, which is the one area no axis label
-- reaches, so nothing has to be squeezed around it.
local RADAR_R, RADAR_H, RADAR_CY = 46, 148, 0
local RADAR_FULL = 60   -- % that reaches the outer ring
local RADAR_AXES = {   -- order: top, right, bottom, left
  { "Crit",        0,  1 },
  { "Mastery",     1,  0 },
  { "Versatility", 0, -1 },
  { "Haste",      -1,  0 },
}

local function MakeRadar(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(RADAR_H)
  if not c.CreateLine then return c end   -- no Line support: stays an empty gap

  local function line(thickness, r, g, b, a)
    local l = c:CreateLine()
    l:SetThickness(thickness)
    l:SetColorTexture(r, g, b, a)
    return l
  end

  -- Grid: two concentric diamonds at 50% and 100%, plus the four spokes.
  -- Grid sits well back: it is scaffolding, not data. If it competes with the
  -- two shapes the chart reads as a mess of lines.
  c.grid, c.spokes = {}, {}
  for i = 1, 8 do c.grid[i] = line(1, 0.34, 0.34, 0.40, 0.30) end
  for i = 1, 4 do c.spokes[i] = line(1, 0.34, 0.34, 0.40, 0.22) end
  -- Two shapes: your gear sits behind, dimmed; what the spec wants sits in front
  -- in gold. Created in that order because lines on the same layer draw in
  -- creation order, so the later one wins the overlap.
  c.edges = {}
  for i = 1, 4 do c.edges[i] = line(2, 0.42, 0.60, 0.85, 0.85) end
  c.wants = {}
  for i = 1, 4 do c.wants[i] = line(2, 1, 0.82, 0, 1) end

  -- Axis names are muted so the two shapes carry the eye. White labels at this
  -- size fight the data for attention.
  c.labels = {}
  for i, a in ipairs(RADAR_AXES) do
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetText(a[1])
    fs:SetTextColor(0.62, 0.62, 0.66)
    c.labels[i] = fs
  end

  -- No colour key on purpose. The blue shape plots the same percentages as the
  -- bars directly above it, so whichever stat has the longest bar has the
  -- longest arm - one glance connects them. A legend would only be needed if
  -- the two sections disagreed, which is exactly the bug that made an earlier
  -- rating-based version unreadable.
  return c
end

-- Anchor everything relative to the frame's own centre, so the radar follows
-- whatever width the panel happens to be.
-- Rank -> distance from centre for the "wanted" shape. The guides give an ORDER,
-- never numbers, so these steps encode position only: 1st leans furthest out,
-- 4th sits nearest the middle. Deliberately gentle - a steeper ramp would read
-- as "you need twice as much haste", which is a claim we cannot make.
local RANK_FRAC = { 1.0, 0.70, 0.46, 0.26 }

local function UpdateRadar(c, vals, order)
  if not c or not c.edges then return end
  local cx, cy = 0, RADAR_CY
  local R = RADAR_R

  local function pt(i, frac)
    local a = RADAR_AXES[i]
    return cx + a[2] * R * frac, cy + a[3] * R * frac
  end
  local function setLine(l, x1, y1, x2, y2)
    l:SetStartPoint("CENTER", c, x1, y1)
    l:SetEndPoint("CENTER", c, x2, y2)
  end

  for ring = 1, 2 do
    local frac = ring * 0.5
    for i = 1, 4 do
      local j = (i % 4) + 1
      local x1, y1 = pt(i, frac)
      local x2, y2 = pt(j, frac)
      setLine(c.grid[(ring - 1) * 4 + i], x1, y1, x2, y2)
    end
  end
  for i = 1, 4 do
    local x, y = pt(i, 1)
    setLine(c.spokes[i], cx, cy, x, y)
    local fs = c.labels[i]
    fs:ClearAllPoints()
    local a = RADAR_AXES[i]
    -- Wider clearance sideways than vertically: the side labels are long words
    -- sitting next to the widest part of the diamond.
    fs:SetPoint("CENTER", c, "CENTER", a[2] * (R + 32), cy + a[3] * (R + 17))
  end

  -- Largest rating defines the outer ring. A floor keeps a zeroed stat visible
  -- as a small nub instead of collapsing the polygon onto the centre point.
  local peak = RADAR_FULL
  for i = 1, 4 do
    local v = vals[RADAR_AXES[i][1]]
    if v and v > peak then peak = v end
  end

  local px, py = {}, {}
  for i = 1, 4 do
    local v = vals[RADAR_AXES[i][1]] or 0
    px[i], py[i] = pt(i, math.max((v / peak) ^ 0.6, 0.08))
  end
  for i = 1, 4 do
    local j = (i % 4) + 1
    setLine(c.edges[i], px[i], py[i], px[j], py[j])
  end

  -- The spec's shape. Rank comes from the priority list, so switching spec
  -- swings this diamond towards whatever that spec leans on.
  local rank = {}
  local n = 0
  for _, name in ipairs(order or {}) do
    if not rank[name] then n = n + 1; rank[name] = n end
  end
  local wx, wy = {}, {}
  for i = 1, 4 do
    local r = rank[RADAR_AXES[i][1]] or 4
    wx[i], wy[i] = pt(i, RANK_FRAC[r] or 0.4)
  end
  for i = 1, 4 do
    local j = (i % 4) + 1
    setLine(c.wants[i], wx[i], wy[i], wx[j], wy[j])
  end
end

local function MakeBar(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetHeight(30)
  local val = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  val:SetPoint("TOPRIGHT", 0, 0)
  local label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  -- Clamp the label against the value text so long labels truncate instead of overlapping
  label:SetPoint("TOPLEFT", 0, 0)
  label:SetPoint("TOPRIGHT", val, "TOPLEFT", -6, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  local bar = CreateFrame("StatusBar", nil, c, "BackdropTemplate")
  bar:SetPoint("TOPLEFT", 0, -13)
  bar:SetPoint("TOPRIGHT", 0, -13)
  bar:SetHeight(14)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  bar:SetBackdropColor(0.05, 0.05, 0.06, 1)
  bar:SetBackdropBorderColor(0, 0, 0, 1)
  -- Optional target tick (retail guide rating targets). Positioned as a fraction
  -- of the bar width; the bar is anchored to both edges so its width only exists
  -- after layout - re-place on size change instead of guessing.
  local mark = bar:CreateTexture(nil, "OVERLAY")
  mark:SetColorTexture(1, 0.85, 0.3, 1)
  mark:SetSize(2, 14)
  mark:Hide()
  bar.mark = mark
  bar:SetScript("OnSizeChanged", function(self, w)
    if self.markFrac and w and w > 0 then
      mark:ClearAllPoints()
      mark:SetPoint("LEFT", self, "LEFT", w * self.markFrac, 0)
    end
  end)
  c.label, c.val, c.bar = label, val, bar
  return c
end

-- Soft pulsing golden glow behind a close button so it's easy to spot
local function AddCloseGlow(closeBtn)
  local glow = closeBtn:CreateTexture(nil, "BACKGROUND")
  glow:SetTexture("Interface\\Buttons\\CheckButtonGlow")
  glow:SetBlendMode("ADD")
  glow:SetPoint("CENTER", 0, 0)
  glow:SetSize(40, 40)
  glow:SetVertexColor(1, 0.85, 0.3)
  local ag = glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(0.12); a:SetToAlpha(0.6); a:SetDuration(1.1)
  ag:Play()
end

------------------------------------------------------------------------
-- Gem popup (separate little window, opened via the GEMS button)
------------------------------------------------------------------------
local COLOR_ICON = {
  meta   = "Interface\\Icons\\INV_Misc_Gem_Diamond_07",
  red    = "Interface\\Icons\\INV_Misc_Gem_Ruby_02",
  yellow = "Interface\\Icons\\INV_Misc_Gem_Topaz_02",
  blue   = "Interface\\Icons\\INV_Misc_Gem_Sapphire_02",
}
local COLOR_LABEL = { meta = "Meta", red = "Red", yellow = "Yellow", blue = "Blue" }
local COLOR_HEX   = { meta = "cccccc", red = "ff6060", yellow = "ffe040", blue = "6090ff" }

local function BuildGemPopup()
  if UI.gemPopup then return end
  local p = CreateFrame("Frame", "StatCoachGemFrame", UIParent, "BackdropTemplate")
  p:SetSize(304, 239)
  p:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 8, 0)
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  p:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
  p:SetBackdropBorderColor(0.35, 0.30, 0.10, 1)
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetClampedToScreen(true)
  -- The three popups share an anchor, so two open at once used to interleave
  -- into one unreadable blend. The one you open - or merely touch - now takes
  -- the top: toplevel raises on click, OnShow raises on open.
  p:SetToplevel(true)
  p:SetScript("OnShow", function(self) self:Raise() end)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffffd100Gems|r")
  p.title = title
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() p:Hide() end)
  AddCloseGlow(close)

  p.rows = {}
  for i = 1, 5 do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(280, 34)
    row:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 39)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28); icon:SetPoint("LEFT")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    local nm = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nm:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    nm:SetWidth(244); nm:SetJustifyH("LEFT")
    row.icon, row.lbl, row.nm = icon, lbl, nm
    p.rows[i] = row
  end

  p:Hide()
  UI.gemPopup = p
end

local function RefreshGems(role, belowHitCap, spec, showCheap)
  local p = UI.gemPopup
  if not p then return end
  p.title:SetText("|cffffd100Gems|r  |cff888888" .. (spec or "") .. "|r")
  local list = D.GEMS[role]
  for i = 1, 5 do
    local row, e = p.rows[i], list and list[i]
    if e then
      local name, iconId, cheap
      if e.hitName and belowHitCap then
        name = e.hitName .. " (until hit-capped)"; iconId = e.hitId; cheap = e.hitCheap
      else
        name = e.name; iconId = e.id; cheap = e.cheap
      end
      if showCheap and cheap then name = name .. "  |cff888888/ " .. cheap .. "|r" end
      local tex = (iconId and GetItemIcon and GetItemIcon(iconId)) or COLOR_ICON[e.color]
      row.icon:SetTexture(tex or COLOR_ICON.red)
      -- a row may name its own label (the honor gem says "Honor gem", not "Red")
      row.lbl:SetText("|cff" .. (COLOR_HEX[e.color] or "ffffff") .. (e.label or COLOR_LABEL[e.color] or "") .. "|r")
      row.nm:SetText(name)
      row:Show()
    else row:Hide() end
  end
end

------------------------------------------------------------------------
-- Enchant popup (separate little window, opened via the ENCH button)
------------------------------------------------------------------------
local ENCH_ICON = "Interface\\Icons\\INV_Scroll_03"

-- Our own TomTom pins, max 2 at a time (FIFO). We only ever remove waypoints
-- WE created (by uid) - the player's own TomTom waypoints are never touched.
local scPins = {}
local function AddScPin(map, x, y, title)
  -- persistent=false: our pins die at logout, so they can never pile up across
  -- sessions (the queue only lives for the session; TomTom would otherwise save them)
  local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, x / 100, y / 100,
    { title = title, persistent = false })
  if not ok then return false end
  if uid then
    scPins[#scPins + 1] = uid
    if #scPins > 2 then
      pcall(TomTom.RemoveWaypoint, TomTom, scPins[1])
      table.remove(scPins, 1)
    end
    pcall(TomTom.SetCrazyArrow, TomTom, uid, 8, title)  -- arrow jumps to the new pin
  end
  return true
end

-- Can you actually BUY this one yet? Every vendor enchant in TBC sits behind a
-- reputation, and knowing where the quartermaster stands is useless if you are
-- not welcome there. Scans the pane rather than asking by id, because the pane
-- only lists factions you actually have - which is what settles Aldor vs
-- Scryers without having to ask which one you joined.
local ENCH_STANDING = { [6] = "Honored", [7] = "Revered", [8] = "Exalted" }

local function EnchantRepState(e)
  local rep = e and e.vendor and e.vendor.rep
  if not rep then return nil end
  local need = rep[1]
  for i = 1, (GetNumFactions and GetNumFactions() or 0) do
    local name, _, standing, _, _, _, _, _, _, _, _, _, _, factionID = GetFactionInfo(i)
    for j = 2, #rep do
      if factionID == rep[j] then
        return {
          ok = (standing or 0) >= need,
          need = need, have = standing, faction = name,
          needName = ENCH_STANDING[need] or ("standing " .. need),
          haveName = _G["FACTION_STANDING_LABEL" .. (standing or 4)] or "?",
        }
      end
    end
  end
  -- Faction not in the pane at all: for Aldor/Scryers that means you have not
  -- picked a side yet, which is a different answer from "not high enough".
  return { ok = false, need = need, unknown = true,
           needName = ENCH_STANDING[need] or ("standing " .. need) }
end

local function BuildEnchantPopup()
  if UI.enchPopup then return end
  local p = CreateFrame("Frame", "StatCoachEnchantFrame", UIParent, "BackdropTemplate")
  p:SetSize(262, 322)
  p:SetPoint("TOPRIGHT", UI.frame, "TOPLEFT", -8, 0)
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  p:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
  p:SetBackdropBorderColor(0.35, 0.30, 0.10, 1)
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetClampedToScreen(true)
  -- The three popups share an anchor, so two open at once used to interleave
  -- into one unreadable blend. The one you open - or merely touch - now takes
  -- the top: toplevel raises on click, OnShow raises on open.
  p:SetToplevel(true)
  p:SetScript("OnShow", function(self) self:Raise() end)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffffd100Enchants|r")
  p.title = title
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() p:Hide() end)
  AddCloseGlow(close)

  p.rows = {}
  for i = 1, 12 do
    local row = CreateFrame("Button", nil, p)
    row:SetSize(238, 24)
    row:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 24)
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16); icon:SetPoint("LEFT")
    icon:SetTexture(ENCH_ICON); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot:SetPoint("LEFT", icon, "RIGHT", 6, 0); slot:SetWidth(58); slot:SetJustifyH("LEFT")
    local ench = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ench:SetPoint("LEFT", slot, "RIGHT", 4, 0); ench:SetWidth(150); ench:SetJustifyH("LEFT")
    row.icon, row.slot, row.ench = icon, slot, ench
    -- Click: TomTom pin to the vendor (GearCoach-style); degrades to chat coords
    row:SetScript("OnClick", function(self)
      local e = self.e
      if not e then return end
      if e.vendor then
        local v = e.vendor
        if TomTom and TomTom.AddWaypoint then
          local ok = AddScPin(v.map, v.x, v.y, "StatCoach: " .. e.ench)
          if ok then
            print("|cffffd100StatCoach:|r waypoint set - " .. (v.where or e.ench))
            return
          end
        end
        print("|cffffd100StatCoach:|r " .. e.ench .. " - " .. (v.where or "") ..
          string.format("  (%.1f, %.1f)", v.x, v.y))
      else
        print("|cffffd100StatCoach:|r " .. e.ench ..
          " - cast by an enchanter (ask in trade chat) or crafted.")
      end
    end)
    row:SetScript("OnEnter", function(self)
      if not self.e then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if self.e.vendor then
        GameTooltip:AddLine(self.e.vendor.where or "Vendor", 1, 1, 1, true)
        local r = EnchantRepState(self.e)
        if r then
          if r.ok then
            GameTooltip:AddLine("You can buy this now (" .. r.faction .. " - "
              .. r.haveName .. ")", 0.3, 1, 0.3, true)
          elseif r.unknown then
            GameTooltip:AddLine("Needs " .. r.needName
              .. " - you have not joined either faction yet", 0.85, 0.5, 0.3, true)
          else
            GameTooltip:AddLine("Needs " .. r.needName .. " with " .. r.faction
              .. " - you are " .. r.haveName, 0.85, 0.5, 0.3, true)
          end
        end
        GameTooltip:AddLine("|cff888888Click: map pin " ..
          (TomTom and "(via TomTom)" or "(coords in chat - install TomTom)") .. "|r")
      else
        GameTooltip:AddLine("|cff888888Cast by an enchanter or crafted - click for info|r")
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.rows[i] = row
  end
  p:Hide()
  UI.enchPopup = p
end

local function RefreshEnchants(role, spec)
  local p = UI.enchPopup
  if not p then return end
  p.title:SetText("|cffffd100Enchants|r  |cff888888" .. (spec or "") .. "|r")
  local list = D.ENCHANTS[role]
  for i = 1, 12 do
    local row, e = p.rows[i], list and list[i]
    if e then
      row.e = e
      -- Retail keeps spell textures under C_Spell since 12.0; the bare
      -- global is TBC's. Without the C_Spell branch every enchant row on
      -- retail wore the generic icon (9 Sep 2026 migration scan).
      local tex = (e.id and GetItemIcon and GetItemIcon(e.id))
        or (e.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.spell))
        or (e.spell and GetSpellTexture and GetSpellTexture(e.spell))
        or ENCH_ICON
      row.icon:SetTexture(tex or ENCH_ICON)
      row.slot:SetText("|cffffd100" .. e.slot .. "|r")
      -- The name is left alone. Reputation state belongs in the tooltip: these
      -- names are already long enough to be cut off, and a marker in front of
      -- every row buys a glance at the cost of the thing people came to read.
      row.ench:SetText(e.ench)
      row:Show()
    else row.e = nil; row:Hide() end
  end
end

------------------------------------------------------------------------
-- Notes popup (opened by the info "i" button)
------------------------------------------------------------------------
local function BuildNotesPopup()
  if UI.notesPopup then return end
  local p = CreateFrame("Frame", "StatCoachNotesFrame", UIParent, "BackdropTemplate")
  p:SetSize(284, 150)
  -- Sits ABOVE the window by default. Anchored by its BOTTOM edge on purpose:
  -- the popup is resized to fit its text, and anchoring the top would make it
  -- grow downwards across the panel it belongs to. Still draggable anywhere.
  p:SetPoint("BOTTOMLEFT", UI.frame, "TOPLEFT", 0, 8)
  p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  p:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
  p:SetBackdropBorderColor(0.35, 0.30, 0.10, 1)
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", p.StopMovingOrSizing)
  p:SetClampedToScreen(true)
  -- The three popups share an anchor, so two open at once used to interleave
  -- into one unreadable blend. The one you open - or merely touch - now takes
  -- the top: toplevel raises on click, OnShow raises on open.
  p:SetToplevel(true)
  p:SetScript("OnShow", function(self) self:Raise() end)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("|cffffd100Notes|r")
  p.title = title
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() p:Hide() end)
  AddCloseGlow(close)

  local body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", 12, -34)
  body:SetWidth(284 - 24); body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
  p.body = body
  p:Hide()
  UI.notesPopup = p
end

local function RefreshNotes(spec)
  local p = UI.notesPopup
  if not p then return end
  p.title:SetText("|cffffd100Notes|r  |cff888888" .. (spec or "") .. "|r")
  local parts = UI.infoParts or {}
  local text = (#parts > 0) and table.concat(parts, "\n\n") or "No notes for this context."
  -- Coach-series line (flavor-matched: TBC promotes TBC, retail promotes retail).
  -- Forever, Mists and Era get none: neither addon does anything on those clients.
  local partner
  if not (FOREVER or MISTS or ns.ERA) then
    partner = RETAIL and "TrinketCoach - trinket tiers right on your tooltips."
      or "GearCoach - BiS checklists and where to get them."
  end
  if partner then text = text .. "\n\n|cff888888Goes hand in hand with " .. partner .. "|r" end
  p.body:SetText(text)
  p:SetHeight(p.body:GetStringHeight() + 48)
end

local function BuildUI()
  local f = CreateFrame("Frame", "StatCoachFrame", UIParent, "BackdropTemplate")
  f:SetSize(268, 400)
  f:SetPoint(StatCoachDB.point or "CENTER", UIParent, StatCoachDB.point or "CENTER",
    StatCoachDB.x or 0, StatCoachDB.y or 0)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
  })
  f:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
  f:SetBackdropBorderColor(0.35, 0.30, 0.10, 1)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScale(StatCoachDB.scale or 1)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    StatCoachDB.point, StatCoachDB.x, StatCoachDB.y = p, x, y
  end)
  -- ESC closes the window (and its popups) like a normal frame
  tinsert(UISpecialFrames, "StatCoachFrame")
  f:SetScript("OnHide", function()
    if UI.gemPopup then UI.gemPopup:Hide() end
    if UI.enchPopup then UI.enchPopup:Hide() end
    if UI.notesPopup then UI.notesPopup:Hide() end
    StatCoachDB.shown = false
  end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -10)
  title:SetText("|cffffd100StatCoach|r")
  UI.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() UI.hideAll() end)
  AddCloseGlow(close)

  -- Info button: all the notes live here so the panel stays clean
  local info = CreateFrame("Button", nil, f)
  info:SetSize(18, 18)
  info:SetPoint("RIGHT", close, "LEFT", 0, 0)
  local itx = info:CreateTexture(nil, "ARTWORK")
  itx:SetAllPoints(); itx:SetTexture("Interface\\FriendsFrame\\InformationIcon")
  info:RegisterForClicks("LeftButtonUp")
  info:SetScript("OnClick", function()
    if UI.notesPopup and UI.notesPopup:IsShown() then UI.notesPopup:Hide()
    elseif UI.notesPopup then RefreshNotes(); UI.notesPopup:Show() end
  end)
  UI.infoBtn = info

  local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetJustifyH("LEFT")
  UI.info = info

  -- Selector row 1: class / spec / mode
  local row1 = CreateFrame("Frame", nil, f); row1:SetHeight(20)
  UI.classBtn = MakeButton(row1, function(_, button) UI.cycleClass(button == "RightButton" and -1 or 1) end)
  UI.classBtn:SetPoint("LEFT", 0, 0)
  UI.specBtn = MakeButton(row1, function(_, button) UI.cycleSpec(button == "RightButton" and -1 or 1) end)
  UI.autoBtn = MakeButton(row1, function() UI.toggleMode() end)
  -- No tooltip here on purpose: a button labelled AUTO / MANUAL explains itself,
  -- and a four-line panel covering the window to say so was just in the way.
  UI.autoBtn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.28, 0.28, 0.34, 1)
  end)
  UI.autoBtn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.18, 0.18, 0.22, 0.9)
  end)
  UI.row1 = row1

  -- Selector row 2: context
  local row2 = CreateFrame("Frame", nil, f); row2:SetHeight(20)
  UI.ctxBtn = MakeButton(row2, function(_, button) UI.cycleContext(button == "RightButton" and -1 or 1) end)
  UI.ctxBtn:SetPoint("LEFT", 0, 0)
  UI.gemBtn = MakeButton(row2, function()
    if UI.gemPopup and UI.gemPopup:IsShown() then UI.gemPopup:Hide()
    elseif UI.gemPopup then UI.gemPopup:Show() end
  end)
  UI.gemBtn:SetLabel("GEMS")
  UI.gemBtn:SetPoint("LEFT", UI.ctxBtn, "RIGHT", 6, 0)
  UI.enchBtn = MakeButton(row2, function()
    if UI.enchPopup and UI.enchPopup:IsShown() then UI.enchPopup:Hide()
    elseif UI.enchPopup then UI.enchPopup:Show() end
  end)
  UI.enchBtn:SetLabel("ENCH")
  UI.enchBtn:SetPoint("LEFT", UI.gemBtn, "RIGHT", 6, 0)
  UI.row2 = row2

  -- NOW advice line (trade advisor)
  local nowLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nowLine:SetWidth(268 - 2 * PAD); nowLine:SetJustifyH("LEFT")
  UI.nowLine = nowLine

  -- Priority
  local ph = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ph:SetJustifyH("LEFT")
  UI.prioHeader = ph
  UI.prio = {}
  for i = 1, PRIO_MAX do
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetJustifyH("LEFT")
    UI.prio[i] = t
  end



  -- Caps
  local ch = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ch:SetJustifyH("LEFT")
  ch:SetWordWrap(false)   -- a section header never wraps; too long = truncate
  UI.capHeader = ch
  UI.bars = {}
  for i = 1, BAR_MAX do UI.bars[i] = MakeBar(f) end
  UI.radar = MakeRadar(f)
  UI.radar:Hide()

  -- Hovered-item compare (footer)
  local ch2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ch2:SetJustifyH("LEFT")
  UI.compareHeader = ch2
  local cl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cl:SetWidth(268 - 2 * PAD); cl:SetJustifyH("LEFT")
  UI.compareLine = cl

  UI.frame = f
  BuildGemPopup()
  BuildEnchantPopup()
  BuildNotesPopup()
  return f
end

------------------------------------------------------------------------
-- Layout helper
local function PlaceRow(obj, y)
  obj:ClearAllPoints()
  obj:SetPoint("TOPLEFT", UI.frame, "TOPLEFT", PAD, y)
  obj:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -PAD, y)
end

------------------------------------------------------------------------
-- RETAIL path. Detect spec via GetSpecialization, read live secondaries, and
-- coach item level > primary > secondary priority (no caps). Fills the SAME
-- widgets as the classic Refresh; classic code is never touched on retail.
------------------------------------------------------------------------
local function RetailDetect()
  local _, detClass = UnitClass("player")
  local db = StatCoachDB
  local class, specName
  if db.manual then
    class = db.manualClass or detClass
  else
    class = detClass
    local idx = safe(GetSpecialization)
    if idx and type(GetSpecializationInfo) == "function" then
      local sid, name = safe(GetSpecializationInfo, idx)
      specName = RetailSpecKey(sid, name)
    end
  end
  local roster = ns.SpecData()
  local rc = roster and roster.classes and roster.classes[class]
  if not rc then
    class = (roster and roster.classOrder and roster.classOrder[1]) or class
    rc = roster and roster.classes and roster.classes[class]
  end
  -- Manual mode must always land on a real spec: a spec name left over from
  -- another class falls back to the first spec of the class now selected.
  if db.manual then
    specName = db.manualSpec
    if rc and not (specName and rc.specs and rc.specs[specName]) then
      specName = rc.specOrder and rc.specOrder[1]
    end
  end
  local sd = rc and specName and rc.specs and rc.specs[specName] or nil
  return class, specName, sd
end

-- Midnight 12.x: combat stats become "secret" values while in combat and any
-- arithmetic on them errors. Strip them to nil; the UI shows "(combat)" instead.
local function desecret(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok = pcall(function() return v + 0 end)
  if ok then return v end
  return nil
end

local function ReadSecondaries()
  return {
    Crit        = desecret(safe(GetCritChance)),
    Haste       = desecret(safe(GetHaste)),
    Mastery     = desecret(safe(GetMasteryEffect)),
    Versatility = desecret(safe(GetCombatRatingBonus, CR_VERSATILITY)),
  }
end

-- Raw secondary RATING - what the diminishing-returns thresholds are defined in.
-- Haste/Crit rating is one number for melee/ranged/spell, so the melee index is
-- fine for every spec. Same desecret guard as the percentages: in combat these
-- come back as secret values and the bars say "(combat)".
local CR_IDX = {
  Haste       = CR_HASTE_MELEE or 20,
  Crit        = CR_CRIT_MELEE or 9,
  Mastery     = CR_MASTERY or 26,
  Versatility = CR_VERSATILITY_DAMAGE_DONE or 29,
}
local function ReadRatings()
  local t = {}
  for name, idx in pairs(CR_IDX) do t[name] = desecret(safe(GetCombatRating, idx)) end
  return t
end

-- Where a rating sits against its DR ladder. Returns bracket (0 = below the first
-- threshold, 1..5 = paying 10..50% more per point), the rating over the threshold,
-- and the width of one bracket. nil dr = stat has no ladder in the data.
local function DRState(name, rating)
  local dr = D.retail and D.retail.DR and D.retail.DR[name]
  if not dr or not rating then return nil end
  local width = dr / 3
  local over = rating - dr
  local bracket = 0
  if over > 0 then bracket = math.min(5, math.ceil(over / width)) end
  return bracket, over, width, dr
end

local function RefreshRetail()
  if not UI.frame then return end
  local class, specName, sd = RetailDetect()
  curCtx.role = nil               -- classic scoring path stays off on retail
  curCtx.weights = {}
  curCtx.retailSd = sd or false   -- cache for retail gear-compare (tooltip + bags)
  wipe(bagCache)
  UI.gemBtn:Hide(); UI.enchBtn:Hide()   -- retail: gem/enchant = your #1 secondary (see notes)

  local level = UnitLevel("player") or 1
  local cc = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or { r = 1, g = 1, b = 1 }
  local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
  UI.info:SetText(string.format("Lv %d  |cff%s%s|r  \226\128\162  %s",
    level, hex, class or "?", specName or "no spec"))

  local manual = StatCoachDB.manual
  UI.classBtn:SetLabel(class or "?")
  UI.specBtn:SetLabel(specName or "?")
  UI.autoBtn:SetLabel(manual and "|cffffff00MANUAL|r" or "|cff40ff40AUTO|r")
  UI.classBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetPoint("LEFT", UI.classBtn, "RIGHT", 4, 0)
  -- Keep the row inside the frame: AUTO pins to the right edge, and the Spec
  -- button shrinks (text truncates) if a long spec name would overflow.
  UI.autoBtn:ClearAllPoints()
  UI.autoBtn:SetPoint("RIGHT", UI.autoBtn:GetParent(), "RIGHT", 0, 0)
  local rowW = UI.autoBtn:GetParent():GetWidth() or 0
  local maxSpec = rowW - UI.classBtn:GetWidth() - UI.autoBtn:GetWidth() - 12
  if maxSpec > 40 and UI.specBtn:GetWidth() > maxSpec then
    UI.specBtn:SetWidth(maxSpec)
    UI.specBtn.text:SetWidth(maxSpec - 12)
  end
  -- Row 2 is empty on retail: gems/enchants live in the notes, and there are no
  -- leveling/pre-raid/endgame tiers to cycle - the button only ever restated the
  -- flavor and did nothing when clicked.
  UI.ctxBtn:Hide()
  UI.row2:Hide()
  UI.prioHeader:SetText("|cffffd100PRIORITY|r")

  local display = {}
  if sd then
    -- No "(biggest upgrade)" / "(main stat)" tags: a numbered list already says
    -- which entry matters most, and the panel header already says the spec.
    display[#display + 1] = "Item Level"
    display[#display + 1] = (sd.primary or "Primary")
    for _, st in ipairs(sd.stats or {}) do display[#display + 1] = st end
  end
  for i = 1, PRIO_MAX do
    local t, e = UI.prio[i], display[i]
    if e then t:SetText("|cffaaaaaa" .. i .. ".|r  " .. e); t:Show()
    else t:SetText(""); t:Hide() end
  end

  -- Live secondaries against their diminishing-returns thresholds. Retail has no
  -- caps, but it has this: rating past the first DR point buys 10% less, and each
  -- further bracket 10% more. So the bar is "how far to the DR point", full = you
  -- are there, colour = which bracket you are paying. Where the spec's guide states
  -- a rating target (Sub Rogue haste, Elemental mastery) a tick marks it.
  -- These are always read off YOUR character - there is no way to read another
  -- spec's stats, you don't have them. Browsing someone else's spec in MANUAL
  -- therefore leaves a Shaman priority list above a Rogue's numbers, so say so
  -- rather than let the panel look like it half-updated.
  local sec, rat = ReadSecondaries(), ReadRatings()
  UI.capHeader:SetText("|cffffd100YOUR SECONDARIES|r  |cff888888(Diminishing Returns)|r")
  UI.capHeader:Show()
  -- Ordered by what the spec actually wants rather than a fixed Crit/Haste/Mastery
  -- list: your own numbers read in the spec's priority order is the comparison that
  -- answers "what should I chase next". All four always show.
  local SECONDARY = { Crit = true, Haste = true, Mastery = true, Versatility = true }
  local show, seen = {}, {}
  for _, name in ipairs((sd and sd.stats) or {}) do
    if SECONDARY[name] and not seen[name] then
      seen[name] = true
      show[#show + 1] = name
    end
  end
  for _, name in ipairs({ "Crit", "Haste", "Mastery", "Versatility" }) do
    if not seen[name] then show[#show + 1] = name end
  end
  local overDR, belowTarget = {}, {}
  for i = 1, BAR_MAX do
    local b, name = UI.bars[i], show[i]
    if name then
      local pct, r = sec[name], rat[name]
      local bracket, over, width, dr = DRState(name, r)
      local tgt = sd and sd.targets and sd.targets[name] and sd.targets[name][1]
      -- Label: stat name plus the guide target's NUMBER only. Spelling out every
      -- context ("~1100 raid / ~700 M+") ran into the value text and got clipped
      -- mid-word. The number is what you gear against; which context it belongs
      -- to is spelled out in the NOW line and in full behind the "i".
      if tgt then
        b.label:SetText(name .. "  |cff888888target ~" .. tgt[1] .. "|r")
      else
        b.label:SetText(name)
      end
      -- tick at the target, as a fraction of the DR ladder (clamped to the bar)
      if tgt and dr then
        b.bar.markFrac = math.min(1, tgt[1] / dr)
        local w = b.bar:GetWidth()
        if w and w > 0 then
          b.bar.mark:ClearAllPoints()
          b.bar.mark:SetPoint("LEFT", b.bar, "LEFT", w * b.bar.markFrac, 0)
        end
        b.bar.mark:Show()
      else
        b.bar.markFrac = nil
        b.bar.mark:Hide()
      end
      if r == nil or pct == nil then
        b.bar:SetValue(0)
        b.bar:SetStatusBarColor(0.3, 0.55, 0.9)
        b.val:SetText("|cff888888(combat)|r")
      elseif not dr then
        b.bar:SetValue(0)
        b.bar:SetStatusBarColor(0.3, 0.55, 0.9)
        b.val:SetText(fmt(pct) .. "%")
      else
        b.bar:SetValue(math.min(1, r / dr))
        if bracket == 0 then b.bar:SetStatusBarColor(0.3, 0.55, 0.9)      -- below DR: blue
        elseif bracket == 1 then b.bar:SetStatusBarColor(0.85, 0.65, 0.1) -- first bracket: gold
        else b.bar:SetStatusBarColor(0.8, 0.25, 0.2) end                  -- deeper: red
        local ratingTxt
        if bracket == 0 then
          ratingTxt = string.format("|cff888888%d / %d|r", math.floor(r + 0.5), dr)
        else
          ratingTxt = string.format("|cffffa000%d (+%d, -%d%%)|r",
            math.floor(r + 0.5), math.floor(over + 0.5), bracket * 10)
          overDR[#overDR + 1] = { name, bracket, over }
        end
        b.val:SetText(fmt(pct) .. "%   " .. ratingTxt)
        if tgt and r < tgt[1] then belowTarget[#belowTarget + 1] = { name, tgt[1] - r, tgt[2] } end
      end
      b:Show()
    else b:Hide() end
  end

  -- NOW line: the concrete "what to chase" answer built from the bars above.
  if sd then
    local top = (sd.stats and sd.stats[1]) or "your top secondary"
    local parts = { "Item level first, then " .. (sd.primary or "primary") .. ". Favor " .. top .. "." }
    for _, o in ipairs(overDR) do
      parts[#parts + 1] = string.format("%s is past its DR (+%d rating) - each point there buys %d%% less.",
        o[1], math.floor(o[3] + 0.5), o[2] * 10)
    end
    for _, t in ipairs(belowTarget) do
      parts[#parts + 1] = string.format("%s target (%s): %d rating to go.", t[1], t[3], math.floor(t[2] + 0.5))
    end
    UI.nowLine:SetText("|cffffd100NOW:|r |cffffffff" .. table.concat(parts, " ") .. "|r")
  else
    UI.nowLine:SetText("|cffffd100NOW:|r |cffffffffPick a specialization to get advice. Item level is always your biggest upgrade.|r")
  end
  UI.nowLine:Show()

  -- Balance radar, fed from ratings (see MakeRadar). Hidden while the client is
  -- withholding stats in combat, because an all-zero diamond would read as data.
  if sec.Crit or sec.Haste or sec.Mastery or sec.Versatility then
    UpdateRadar(UI.radar, sec, sd and sd.stats)
    UI.radar:Show()
  else
    UI.radar:Hide()
  end

  -- Notes behind the "i" icon (RefreshNotes just renders UI.infoParts - flavor-neutral)
  UI.infoParts = {}
  if sd and sd.notes then UI.infoParts[#UI.infoParts + 1] = sd.notes end
  -- Guide rating targets in full. The bar label only has room for the number, so
  -- this is where "which one is the raid target" actually gets answered.
  if sd and sd.targets then
    for _, stat in ipairs({ "Crit", "Haste", "Mastery", "Versatility" }) do
      local tl = sd.targets[stat]
      if tl then
        local parts = {}
        for _, t in ipairs(tl) do parts[#parts + 1] = "~" .. t[1] .. " rating (" .. t[2] .. ")" end
        UI.infoParts[#UI.infoParts + 1] =
          stat .. " target from the guide: " .. table.concat(parts, ", ") ..
          ". The tick on the bar marks the first one."
      end
    end
  end
  -- Versatility's live value used to be quoted here because it had no bar. It has
  -- one now, so the note keeps only the part the bars can't say.
  UI.infoParts[#UI.infoParts + 1] =
    "Retail has no stat caps - item level dominates. What it has is diminishing returns on " ..
    "secondary RATING (level 90): Haste 1320, Crit 1380, Mastery 1380, Versatility 1620. " ..
    "Rating past that point buys 10% less; every further bracket (about a third of the " ..
    "threshold) costs another 10%, down to -50%. The bars run 0 to that first threshold: " ..
    "blue = below it, gold = first bracket, red = deeper. Rating over the line is not " ..
    "wasted, it just buys less than the same rating in a stat still under its line.\n\n" ..
    "Mastery is the odd one out: its rating follows the same ladder as Crit, but the " ..
    "percentage it turns into is scaled per spec - so 50% Mastery from 575 rating is " ..
    "perfectly normal. Read the rating against the line, not the percentage."
  if D.retail and D.retail.GEM_NOTE then UI.infoParts[#UI.infoParts + 1] = D.retail.GEM_NOTE end
  if UI.notesPopup and UI.notesPopup:IsShown() then RefreshNotes(specName) end

  -- Panel footer compare is a classic feature; tooltips carry the verdict on retail
  UI.compareHeader:Hide()
  UI.compareLine:Hide()

  -- Layout (mirror of the classic Refresh's layout pass - without this, nothing
  -- is anchored and the window renders empty)
  local y = -34
  PlaceRow(UI.info, y); y = y - math.max(UI.info:GetStringHeight() + 4, 18)
  PlaceRow(UI.row1, y); y = y - 24
  if UI.row2:IsShown() then PlaceRow(UI.row2, y); y = y - 26 end
  if UI.nowLine:IsShown() then
    PlaceRow(UI.nowLine, y); y = y - (UI.nowLine:GetStringHeight() + 8)
  end
  PlaceRow(UI.prioHeader, y); y = y - math.max(UI.prioHeader:GetStringHeight() + 4, 16)
  for i = 1, PRIO_MAX do
    if UI.prio[i]:IsShown() then PlaceRow(UI.prio[i], y); y = y - 15 end
  end
  y = y - 6
  PlaceRow(UI.capHeader, y); y = y - math.max(UI.capHeader:GetStringHeight() + 5, 18)
  for i = 1, BAR_MAX do
    if UI.bars[i]:IsShown() then PlaceRow(UI.bars[i], y); y = y - 34 end
  end
  if UI.radar:IsShown() then
    PlaceRow(UI.radar, y); y = y - (RADAR_H + 6)
  end
  -- Fixed floor = the tallest layout (rogue: 6 priorities + 3 cap bars), so the
  -- window keeps ONE size no matter which class/spec/context you toggle to.
  UI.frame:SetHeight(math.max(-y + PAD, 430))
end

------------------------------------------------------------------------
-- FOREVER path. Everything here was read off the beta client (1.60.1, 18 Sep
-- 2026), nothing is carried over from Vanilla by assumption. The skill list lives
-- in C_SkillInfo and each line is a struct: name, rank, maxRank, modifier,
-- tempPoints, isHeader, skillID, skillLineCategoryID. Category 6 is "Weapon
-- Skills" and Defense (skill 95) sits in it. Lines are picked by id and category,
-- never by name - names are localized. Stat priorities are deliberately absent:
-- Forever's talents are new and unmapped, and a guessed weight is worse than none.
------------------------------------------------------------------------
local FOREVER_WEAPON_CATEGORY, FOREVER_DEFENSE_ID = 6, 95

-- Weapon type -> skill line. This is Blizzard's own table, from the Forever
-- character sheet (Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua, build
-- 1.60.1.69913), which resolves the equipped weapon the same way: item id ->
-- GetItemInfoInstant -> weapon subclass -> skill id, and Unarmed for an empty hand.
local FOREVER_WEAPON_SKILL = {
  [W.SWORD1] = 43,  [W.AXE1] = 44,  [W.BOW] = 45,    [W.GUN] = 46,   [W.MACE1] = 54,
  [W.SWORD2] = 55,  [W.STAFF] = 136, [W.MACE2] = 160, [W.AXE2] = 172, [W.DAGGER] = 173,
  [W.THROWN] = 176, [W.XBOW] = 226,  [W.WAND] = 228,  [W.POLE] = 229, [W.FIST] = 473,
}
-- Fist weapons: that same file maps them to 162 (Unarmed) while the constants next
-- to it name 473 (Fist Weapons). Whichever of the two the character has wins.
local FOREVER_UNARMED_ID, FOREVER_FIST_ID = 162, 473

-- Skill ids of what the character is holding: main hand, off-hand, ranged slot -
-- except for a hunter, whose bow or gun is the weapon that matters, so the ranged
-- slot leads there (a level-1 hunter otherwise gets coached on the dagger).
-- "have" is the set of skill ids the character actually owns.
local function ForeverEquippedSkills(have)
  local ids, seen = {}, {}
  local _, class = UnitClass("player")
  local order = (class == "HUNTER") and { 18, 16, 17 } or { 16, 17, 18 }
  for _, slot in ipairs(order) do
    local id
    local itemID = GetInventoryItemID("player", slot)
    if itemID then
      local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
      if classID == WEAPON_CLASS_ID then id = FOREVER_WEAPON_SKILL[subclassID] end
      if id == FOREVER_FIST_ID and not have[id] then id = FOREVER_UNARMED_ID end
    elseif slot == 16 then
      id = FOREVER_UNARMED_ID
    end
    if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
  end
  return ids, seen
end

local function ForeverSkills()
  local weapons, defense = {}, nil
  if not (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
    return weapons, defense
  end
  local n = safe(C_SkillInfo.GetNumSkillLines)
  if type(n) ~= "number" then return weapons, defense end
  for i = 1, n do
    local s = safe(C_SkillInfo.GetSkillLineInfo, i)
    if type(s) == "table" and not s.isHeader and s.skillLineCategoryID == FOREVER_WEAPON_CATEGORY then
      local rank, max = desecret(s.rank), desecret(s.maxRank)
      if rank and max and max > 0 then
        local line = { id = s.skillID, name = s.name or "?", rank = rank, max = max,
                       bonus = num(desecret(s.modifier)) + num(desecret(s.tempPoints)) }
        if s.skillID == FOREVER_DEFENSE_ID then defense = line else weapons[#weapons + 1] = line end
      end
    end
  end
  -- What you are holding comes first, in slot order; after that, whatever you
  -- have trained the most.
  local have = {}
  for _, line in ipairs(weapons) do have[line.id] = true end
  local order, equipped = ForeverEquippedSkills(have)
  local pos = {}
  for i, id in ipairs(order) do pos[id] = i end
  table.sort(weapons, function(a, b)
    local pa, pb = pos[a.id], pos[b.id]
    if pa or pb then
      if pa and pb then return pa < pb end
      return pa ~= nil
    end
    if a.rank ~= b.rank then return a.rank > b.rank end
    return a.name < b.name
  end)
  for _, line in ipairs(weapons) do line.equipped = equipped[line.id] or false end
  return weapons, defense
end

-- How much hit is enough. Forever's character sheet says it in words: the hit tooltip
-- is built from CR_<CLASS>_HIT_CAP_TOOLTIP (warrior, hunter and rogue have their own,
-- everyone else gets CR_DEFAULT_HIT_CAP_TOOLTIP), e.g. "To never miss Raid Bosses:
-- 8.00% Melee, 17.00% Spells, 27.00% Dual Wielding / To never miss Lvl %d Targets:
-- 5.00% Melee, 4.00% Spells, 24.00% Dual Wielding". The numbers are READ from that
-- text, by position rather than by word, so they follow the client's language and
-- any rebalancing Blizzard does. The constants are what the beta said on 20 Sep 2026
-- and are only the fallback for a text that no longer has the shape above.
local function ForeverCaps()
  local caps = { boss = { melee = 8, spell = 17, dual = 27 }, level = { melee = 5, spell = 4, dual = 24 }, fromGame = false }
  local _, class = UnitClass("player")
  local text = (class and rawget(_G, "CR_" .. class .. "_HIT_CAP_TOOLTIP")) or rawget(_G, "CR_DEFAULT_HIT_CAP_TOOLTIP")
  if type(text) ~= "string" then return caps end
  local n = {}
  for whole, frac in text:gmatch("(%d+)[%.,](%d+)%%") do
    local v = tonumber(whole .. "." .. frac)
    if v and v > 0 and v < 100 then n[#n + 1] = v end
  end
  if #n == 6 then
    caps.boss  = { melee = n[1], spell = n[2], dual = n[3] }
    caps.level = { melee = n[4], spell = n[5], dual = n[6] }
    caps.fromGame = true
  elseif #n == 4 then
    caps.boss  = { melee = n[1], spell = n[2] }
    caps.level = { melee = n[3], spell = n[4] }
    caps.fromGame = true
  end
  return caps
end

-- Measured on the beta on four classes (warrior, rogue, mage, paladin), melee and
-- ranged: every point a weapon skill sits below its maximum costs 0.04% crit with
-- that weapon. It is the same constant Blizzard's sheet uses for Defense.
local FOREVER_CRIT_PER_SKILL = 0.04

local function RefreshForever()
  if not UI.frame then return end
  local _, class = UnitClass("player")
  curCtx.role = nil
  curCtx.weights = {}
  curCtx.retailSd = false         -- no verdicts on Forever until there is data to stand on
  wipe(bagCache)
  UI.gemBtn:Hide(); UI.enchBtn:Hide(); UI.ctxBtn:Hide()
  UI.row1:Hide(); UI.row2:Hide()  -- class/spec browsing has nothing to browse yet
  UI.radar:Hide()
  UI.compareHeader:Hide(); UI.compareLine:Hide()

  local level = UnitLevel("player") or 1
  local cc = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or { r = 1, g = 1, b = 1 }
  local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
  UI.info:SetText(string.format("Lv %d  |cff%s%s|r  \226\128\162  Forever", level, hex, class or "?"))

  -- Your numbers, computed the way Forever's own character sheet computes them
  -- (Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua): hit is rating bonus
  -- PLUS the flat modifier, crit and haste come per attack type, block only counts
  -- with a shield, and the sheet hides a modifier that is zero - so does this.
  -- Which attack types a class sees is the one thing decided here: a mage has no
  -- use for melee hit, a hunter wants ranged next to melee.
  local lines = {}
  local SPELL_ONLY = { MAGE = true, WARLOCK = true, PRIEST = true }
  local HYBRID     = { PALADIN = true, SHAMAN = true, DRUID = true }
  local function pct(v) return "|cffffffff" .. fmt(v) .. "%|r" end
  local function sum(a, b)
    a, b = desecret(a), desecret(b)
    if a == nil and b == nil then return nil end
    return num(a) + num(b)
  end
  local function typed(label, melee, ranged, spell, always)
    local parts
    if SPELL_ONLY[class] then parts = { { nil, spell } }
    elseif class == "HUNTER" then parts = { { "ranged", ranged }, { "melee", melee } }
    elseif HYBRID[class] then parts = { { "melee", melee }, { "spell", spell } }
    else parts = { { nil, melee } } end
    local any, out = false, {}
    for _, part in ipairs(parts) do
      local v = part[2]
      if v == nil then
        -- withheld in combat: say so for the lines that always show, and leave a
        -- zero-hidden line hidden rather than advertise a stat you may not have
        if always then out[#out + 1] = "|cff888888(combat)|r"; any = true end
      else
        if v > 0 then any = true end
        out[#out + 1] = (part[1] and (part[1] .. " ") or "") .. pct(v)
      end
    end
    if any or always then lines[#lines + 1] = label .. "  " .. table.concat(out, " / ") end
  end
  local hitMelee  = sum(safe(GetCombatRatingBonus, CR_HIT_MELEE),  safe(GetHitModifier))
  local hitRanged = sum(safe(GetCombatRatingBonus, CR_HIT_RANGED), safe(GetRangedHitModifier))
  local hitSpell  = sum(safe(GetCombatRatingBonus, CR_HIT_SPELL),  safe(GetSpellHitModifier))
  typed("Crit", desecret(safe(GetCritChance)), desecret(safe(GetRangedCritChance)),
    desecret(safe(GetSpellCritChance)), true)
  local rangedHaste, ammoHaste = safe(GetRangedHaste)
  typed("Haste", desecret(safe(GetMeleeHaste)), sum(rangedHaste, ammoHaste),
    desecret(safe(UnitSpellHaste, "player")))
  if not SPELL_ONLY[class] then
    local exp, offExp = safe(GetExpertise)
    exp, offExp = desecret(exp), desecret(offExp)
    local _, offSpeed = safe(UnitAttackSpeed, "player")
    if exp and exp > 0 then
      lines[#lines + 1] = "Expertise  " .. pct(exp) .. ((offSpeed and offExp) and (" / " .. pct(offExp)) or "")
    end
    local arp = desecret(safe(GetArmorPenetration))
    if arp and arp > 0 then lines[#lines + 1] = "Armor penetration  |cffffffff" .. math.floor(arp + 0.5) .. "|r" end
  end
  local function avoid(label, v)
    v = desecret(v)
    if v and v > 0 then lines[#lines + 1] = label .. "  " .. pct(v) end
  end
  avoid("Dodge", safe(GetDodgeChance))
  avoid("Parry", safe(GetParryChance))
  local hasShield = C_PaperDollInfo and C_PaperDollInfo.OffhandHasShield and safe(C_PaperDollInfo.OffhandHasShield)
  if hasShield then
    local chance, value = desecret(safe(GetBlockChance)), desecret(safe(GetShieldBlock))
    if chance and chance > 0 then
      lines[#lines + 1] = "Block  " .. pct(chance) .. (value and ("  |cff888888blocks " .. math.floor(value + 0.5) .. "|r") or "")
    end
  end
  UI.prioHeader:SetText("|cffffd100YOUR NUMBERS|r")
  for i = 1, PRIO_MAX do
    local t, e = UI.prio[i], lines[i]
    if e then t:SetText("|cffaaaaaa" .. e .. "|r"); t:Show()
    else t:SetText(""); t:Hide() end
  end

  -- HIT: one bar per attack type the class fights with, against what the game says
  -- is enough. While leveling that is a target of your own level; from five levels
  -- below the level cap it is a raid boss, because that is the number gear is then
  -- chosen by. A value the client withholds in combat simply drops its bar.
  local caps = ForeverCaps()
  local maxLevel = safe(GetMaxPlayerLevel) or 60
  local vsBoss = level >= maxLevel - 5
  local target = vsBoss and caps.boss or caps.level
  local versus = vsBoss and "raid bosses" or ("level " .. level)                 -- on the bar label
  local aTarget = vsBoss and "a raid boss" or ("a level " .. level .. " target")   -- in a sentence
  local hitRows = {}
  local function hitRow(label, cur, cap)
    if cur and cap then hitRows[#hitRows + 1] = { label = label .. " vs " .. versus, cur = cur, cap = cap } end
  end
  if SPELL_ONLY[class] then hitRow("Spell hit", hitSpell, target.spell)
  elseif class == "HUNTER" then hitRow("Ranged hit", hitRanged, target.melee)
  elseif HYBRID[class] then hitRow("Melee hit", hitMelee, target.melee); hitRow("Spell hit", hitSpell, target.spell)
  else hitRow("Melee hit", hitMelee, target.melee) end

  -- WEAPON SKILL & DEFENSE: only what is in your hands, then Defense. A skill for a
  -- weapon you are not holding is noise, so it gets no bar. A pure caster never
  -- swings its staff and is not hit for its Defense: the only line it gets is the
  -- wand it actually fires.
  local weapons, defense = ForeverSkills()
  local skillRows = {}
  for _, sk in ipairs(weapons) do
    if sk.equipped and (not SPELL_ONLY[class] or sk.id == 228) and #skillRows < BAR_MAX - #hitRows - 1 then
      skillRows[#skillRows + 1] = sk
    end
  end
  if defense and not SPELL_ONLY[class] then skillRows[#skillRows + 1] = defense end
  local function critCost(sk)
    if SPELL_ONLY[class] or sk.id == FOREVER_DEFENSE_ID or sk.rank >= sk.max then return 0 end
    return (sk.max - sk.rank) * FOREVER_CRIT_PER_SKILL
  end
  -- Two decimals under 1%: at low level 0.16% and 0.24% are different answers, and
  -- one decimal would print both as 0.2%.
  local function costText(cost)
    return string.format(cost < 1 and "%.2f%%" or "%.1f%%", cost)
  end

  if not UI.fvHitHeader then
    local h = UI.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetJustifyH("LEFT"); h:SetWordWrap(false)
    UI.fvHitHeader = h
  end
  UI.fvHitHeader:SetText("|cffffd100HIT|r  |cff888888(what the game says is enough)|r")
  if #hitRows > 0 then UI.fvHitHeader:Show() else UI.fvHitHeader:Hide() end
  UI.capHeader:SetText("|cffffd100WEAPON SKILL & DEFENSE|r  |cff888888(rank / max)|r")
  if #skillRows > 0 then UI.capHeader:Show() else UI.capHeader:Hide() end

  for i = 1, BAR_MAX do
    local b = UI.bars[i]
    local h, sk = hitRows[i], skillRows[i - #hitRows]
    b.bar.markFrac = nil
    b.bar.mark:Hide()
    if h then
      local done = h.cur >= h.cap
      b.label:SetText(h.label)
      b.bar:SetValue(math.min(1, h.cur / h.cap))
      if done then b.bar:SetStatusBarColor(0.2, 0.7, 0.2) else b.bar:SetStatusBarColor(0.3, 0.55, 0.9) end
      b.val:SetText(fmt(h.cur) .. "% / " .. fmt(h.cap) .. "%" .. (done and "  |cff40ff40capped|r" or ""))
      b:Show()
    elseif sk then
      b.label:SetText(sk.name)
      b.bar:SetValue(math.min(1, sk.rank / sk.max))
      if sk.rank >= sk.max then b.bar:SetStatusBarColor(0.2, 0.7, 0.2)   -- at its maximum: green
      else b.bar:SetStatusBarColor(0.85, 0.65, 0.1) end                  -- room to grow: gold
      local txt = string.format("%d / %d", sk.rank, sk.max)
      if sk.bonus > 0 then txt = txt .. string.format("  |cff40ff40(+%d)|r", sk.bonus) end
      local cost = sk.equipped and critCost(sk) or 0
      if cost > 0 then txt = txt .. "  |cffff9040-" .. costText(cost) .. " crit|r" end
      b.val:SetText(txt)
      b:Show()
    else b:Hide() end
  end

  -- NOW: the one thing worth acting on. A weapon skill that is behind is the only
  -- thing a leveling character can fix on the spot, so it goes first; hit is only
  -- worth a sentence once there is some on the gear or the boss number applies.
  local top = weapons[1]
  local mainHit = hitRows[1]
  local now
  local topCost = (top and top.equipped) and critCost(top) or 0
  if topCost > 0 then
    now = string.format("%s is %d of %d - that is costing you %s crit with it. It only rises while you " ..
      "fight with that weapon.", top.name, top.rank, top.max, costText(topCost))
  elseif mainHit and mainHit.cur < mainHit.cap and (vsBoss or mainHit.cur > 0) then
    now = string.format("You have %.1f%% of the %.1f%% hit it takes to never miss %s - %.1f%% to go.",
      mainHit.cur, mainHit.cap, aTarget, mainHit.cap - mainHit.cur)
  elseif mainHit and mainHit.cur >= mainHit.cap then
    now = "You never miss " .. aTarget .. " any more. More hit does nothing - put the budget elsewhere."
  elseif top and not SPELL_ONLY[class] then
    now = top.name .. " is at its maximum. Nothing to fix right now."
  else
    now = "Nothing to fix right now."
  end
  UI.nowLine:SetText("|cffffd100NOW:|r |cffffffff" .. now .. "|r")
  UI.nowLine:Show()

  local defCap = 440
  local defText = rawget(_G, "DEFAULT_STATDEFENSE_TOOLTIP")
  if type(defText) == "string" then defCap = tonumber(defText:match("(%d%d%d)")) or defCap end
  UI.infoParts = {
    "StatCoach on World of Warcraft: Forever coaches from what the game itself states - nothing here is " ..
    "carried over from Classic by assumption.",
    string.format("HIT. Forever's own hit tooltip says that to never miss a target of your level you need " ..
      "%s%% melee or ranged hit and %s%% spell hit, and against raid bosses %s%% and %s%%.%s The bar " ..
      "switches to the raid boss number five levels below the level cap.",
      fmt(caps.level.melee), fmt(caps.level.spell), fmt(caps.boss.melee), fmt(caps.boss.spell),
      caps.level.dual and string.format(" While dual wielding it lists %s%% and %s%% instead.",
        fmt(caps.level.dual), fmt(caps.boss.dual)) or ""),
    "WEAPON SKILL. Every point a weapon skill sits below its maximum costs 0.04% crit with that weapon " ..
    "(measured on the beta), and the game's own text says it lowers your chance to hit as well. The " ..
    "maximum is five per character level.",
    string.format("DEFENSE. The game's Defense tooltip says %d Defense makes you immune to critical strikes " ..
      "from raid bosses. Crushing blows come from enemies three or more levels above you.", defCap),
    "Stat priorities and upgrade verdicts are still switched off on Forever: the published guides do not " ..
    "agree yet, and a copied list would be a guess. They come back on real data.",
  }
  if UI.notesPopup and UI.notesPopup:IsShown() then RefreshNotes("Forever") end

  -- Layout: what you can act on first (NOW, hit, weapon skill), your raw numbers last
  local y = -34
  PlaceRow(UI.info, y); y = y - math.max(UI.info:GetStringHeight() + 4, 18)
  PlaceRow(UI.nowLine, y); y = y - (UI.nowLine:GetStringHeight() + 8)
  if #hitRows > 0 then
    PlaceRow(UI.fvHitHeader, y); y = y - math.max(UI.fvHitHeader:GetStringHeight() + 5, 18)
    for i = 1, #hitRows do PlaceRow(UI.bars[i], y); y = y - 34 end
    y = y - 2
  end
  if #skillRows > 0 then
    PlaceRow(UI.capHeader, y); y = y - math.max(UI.capHeader:GetStringHeight() + 5, 18)
    for i = #hitRows + 1, BAR_MAX do
      if UI.bars[i]:IsShown() then PlaceRow(UI.bars[i], y); y = y - 34 end
    end
    y = y - 2
  end
  PlaceRow(UI.prioHeader, y); y = y - math.max(UI.prioHeader:GetStringHeight() + 4, 16)
  for i = 1, PRIO_MAX do
    if UI.prio[i]:IsShown() then PlaceRow(UI.prio[i], y); y = y - 15 end
  end
  UI.frame:SetHeight(math.max(-y + PAD, 300))
end

------------------------------------------------------------------------
-- MISTS path (Mists of Pandaria Classic 5.5.x). Caps like TBC - hit and expertise
-- against a raid boss - with specializations like retail. The cap numbers are the
-- game's own. Blizzard's Mists character sheet (Blizzard_CharacterFrame: Cata/
-- PaperDollFrame.lua + Mists/PaperDollFrameUtil.lua, build 5.5.4.69934) computes
--   miss  = base miss - hit rating bonus - hit modifier
--   dodge = base dodge - expertise
--   parry = base parry - the expertise left over once dodge is gone
-- with the base chance per level difference in PaperDollFrameUtil.Constants. That
-- table is read when the client has it loaded; MISTS_BASE is a copy of the same
-- numbers, so nothing here depends on the character sheet having been opened.
-- Both are fields on UI rather than locals: this file sits at Lua's 200-local
-- limit for one chunk.
------------------------------------------------------------------------
UI.MISTS_BASE = {
  BaseMissChancePhysical = { [0] = 3.0, [1] = 4.5, [2] = 6.0, [3] = 7.5 },
  BaseMissChanceSpell    = { [0] = 6.0, [1] = 9.0, [2] = 12.0, [3] = 15.0 },
  BaseEnemyDodgeChance   = { [0] = 3.0, [1] = 4.5, [2] = 6.0, [3] = 7.5 },
  BaseEnemyParryChance   = { [0] = 3.0, [1] = 4.5, [2] = 6.0, [3] = 7.5 },
}

UI.RefreshMists = function()
  if not UI.frame then return end
  local class, specName, sd = RetailDetect()
  curCtx.role = nil
  curCtx.weights = {}
  curCtx.retailSd = false         -- no item verdicts on Mists yet
  wipe(bagCache)
  UI.gemBtn:Hide(); UI.enchBtn:Hide(); UI.ctxBtn:Hide(); UI.row2:Hide()
  UI.radar:Hide()
  UI.compareHeader:Hide(); UI.compareLine:Hide()
  if UI.fvHitHeader then UI.fvHitHeader:Hide() end

  local level = UnitLevel("player") or 1
  local cc = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or { r = 1, g = 1, b = 1 }
  local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
  UI.info:SetText(string.format("Lv %d  |cff%s%s|r  \226\128\162  %s",
    level, hex, class or "?", specName or "no spec"))

  -- Class / spec row, as on retail: AUTO follows the character, MANUAL browses.
  local manual = StatCoachDB.manual
  UI.row1:Show()
  UI.classBtn:SetLabel(class or "?")
  UI.specBtn:SetLabel(specName or "?")
  UI.autoBtn:SetLabel(manual and "|cffffff00MANUAL|r" or "|cff40ff40AUTO|r")
  UI.classBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetPoint("LEFT", UI.classBtn, "RIGHT", 4, 0)
  UI.autoBtn:ClearAllPoints()
  UI.autoBtn:SetPoint("RIGHT", UI.autoBtn:GetParent(), "RIGHT", 0, 0)
  local rowW = UI.autoBtn:GetParent():GetWidth() or 0
  local maxSpec = rowW - UI.classBtn:GetWidth() - UI.autoBtn:GetWidth() - 12
  if maxSpec > 40 and UI.specBtn:GetWidth() > maxSpec then
    UI.specBtn:SetWidth(maxSpec)
    UI.specBtn.text:SetWidth(maxSpec - 12)
  end

  local function base(key, offset)
    local util = rawget(_G, "PaperDollFrameUtil")
    local t = type(util) == "table" and type(util.Constants) == "table" and util.Constants[key]
    return (type(t) == "table" and tonumber(t[offset])) or UI.MISTS_BASE[key][offset]
  end
  local function sum(a, b)
    a, b = desecret(a), desecret(b)
    if a == nil and b == nil then return nil end
    return num(a) + num(b)
  end
  local maxLevel = safe(GetMaxPlayerLevel) or 90
  local vsBoss = level >= maxLevel - 5
  local off = vsBoss and 3 or 0
  local versus = vsBoss and "a raid boss" or ("level " .. level)

  -- What the spec attacks with decides which caps it has: melee and ranged need hit
  -- and expertise, casters spell hit, healers nothing. A tank faces the boss, so
  -- parry counts for it; a damage dealer stands behind, where nothing is parried.
  local attack = sd and sd.attack
  local tank = sd and sd.role == "TANK"
  local reads = attack or ((sd and sd.primary == "Intellect") and "spell") or "melee"
  local hitCR = (attack == "ranged" and CR_HIT_RANGED) or (attack == "spell" and CR_HIT_SPELL) or CR_HIT_MELEE
  local e1, _, e3 = safe(rawget(_G, "GetExpertisePercent") or GetExpertise)
  local exp = desecret(reads == "ranged" and e3 or e1)
  local hit
  if reads == "spell" then hit = sum(safe(GetCombatRatingBonus, CR_HIT_SPELL), safe(GetSpellHitModifier))
  else hit = sum(safe(GetCombatRatingBonus, hitCR), safe(GetHitModifier)) end
  -- A caster's expertise counts toward spell hit in combat, but the character sheet
  -- leaves it out of the spell hit it shows. Players measured it on Mists Classic
  -- (Blizzard forums, "Expertise doesn't increase spell hit for casters") and every
  -- caster guide caps hit and expertise together at 15%. So it is added here.
  if attack == "spell" and hit and exp then hit = hit + exp end

  -- Rating per 1%: the character's own ratio whenever there is rating to read it
  -- from, else the level-cap number the data file carries (it is stated in the guides).
  local function perPct(cr)
    local r, b = desecret(safe(GetCombatRating, cr)), desecret(safe(GetCombatRatingBonus, cr))
    if r and b and r > 0 and b > 0 then return r / b end
    local roster = ns.SpecData()
    if level >= maxLevel and roster and roster.RATING_PER_PCT then return roster.RATING_PER_PCT end
    return nil
  end
  local function ratingOf(pct, cr)
    local p = perPct(cr)
    return p and math.floor(pct * p + 0.5) or nil
  end

  local rows = {}
  if attack and hit then
    rows[#rows + 1] = { kind = "hit", cr = hitCR, cur = hit,
      label = (attack == "spell" and "Spell hit") or (attack == "ranged" and "Ranged hit") or "Hit",
      cap = base(attack == "spell" and "BaseMissChanceSpell" or "BaseMissChancePhysical", off) }
  end
  if attack and attack ~= "spell" and exp then
    local dodge = base("BaseEnemyDodgeChance", off)
    rows[#rows + 1] = { kind = "dodge", cr = CR_EXPERTISE, cur = exp, cap = dodge,
      label = tank and "Expertise - dodge" or "Expertise" }
    if tank then
      rows[#rows + 1] = { kind = "parry", cr = CR_EXPERTISE, cur = math.max(0, exp - dodge),
        cap = base("BaseEnemyParryChance", off), label = "Expertise - parry" }
    end
  end

  UI.capHeader:SetText("|cffffd100" .. (attack == "spell" and "SPELL HIT" or "HIT & EXPERTISE") ..
    "|r  |cff888888(vs " .. versus .. ")|r")
  if #rows > 0 then UI.capHeader:Show() else UI.capHeader:Hide() end
  for i = 1, BAR_MAX do
    local b, r = UI.bars[i], rows[i]
    b.bar.markFrac = nil
    b.bar.mark:Hide()
    if r then
      local done = r.cur >= r.cap - 0.005
      b.label:SetText(r.label)
      b.bar:SetValue(r.cap > 0 and math.min(1, r.cur / r.cap) or 1)
      if done then b.bar:SetStatusBarColor(0.2, 0.7, 0.2) else b.bar:SetStatusBarColor(0.3, 0.55, 0.9) end
      b.val:SetText(string.format("%.2f%% / %.2f%%", r.cur, r.cap) .. (done and "  |cff40ff40capped|r" or ""))
      b:Show()
    else b:Hide() end
  end

  -- The stat list, each with the character's own number next to it.
  local list = (sd and sd.stats) or {}
  local function p2(v) v = desecret(v); return v and string.format("%.2f%%", v) or nil end
  local function big(v)
    v = desecret(v)
    if not v then return nil end
    v = math.floor(v + 0.5)
    return (type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(v)) or tostring(v)
  end
  local function unitStat(i) local _, eff = safe(UnitStat, "player", i); return eff end
  local function lowestSchool(fn)
    local m
    for school = 2, 7 do
      local v = desecret(safe(fn, school))
      if v and (not m or v < m) then m = v end
    end
    return m
  end
  local VALUE = {
    Strength  = function() return big(unitStat(1)) end,
    Agility   = function() return big(unitStat(2)) end,
    Stamina   = function() return big(unitStat(3)) end,
    Intellect = function() return big(unitStat(4)) end,
    Spirit    = function() return big(unitStat(5)) end,
    Hit       = function() return hit and p2(hit) end,
    Expertise = function() return exp and p2(exp) end,
    Mastery   = function() return p2((safe(GetMasteryEffect))) end,
    Crit      = function()
      if reads == "spell" then return p2(lowestSchool(GetSpellCritChance)) end
      return p2(safe(reads == "ranged" and GetRangedCritChance or GetCritChance))
    end,
    Haste     = function()
      if reads == "spell" then return p2(safe(UnitSpellHaste, "player")) end
      return p2(safe(reads == "ranged" and GetRangedHaste or GetMeleeHaste))
    end,
    ["Spell Power"] = function()
      if sd and sd.role == "HEALER" then return big(safe(GetSpellBonusHealing)) end
      return big(lowestSchool(GetSpellBonusDamage))
    end,
    ["Attack Power"] = function()
      local b, p, n = safe(reads == "ranged" and UnitRangedAttackPower or UnitAttackPower, "player")
      if b == nil then return nil end
      return big(num(desecret(b)) + num(desecret(p)) + num(desecret(n)))
    end,
    Armor = function() local _, eff = safe(UnitArmor, "player"); return big(eff) end,
    Dodge = function() return p2(safe(GetDodgeChance)) end,
    Parry = function() return p2(safe(GetParryChance)) end,
  }
  UI.prioHeader:SetText("|cffffd100PRIORITY|r")
  for i = 1, PRIO_MAX do
    local t, st = UI.prio[i], list[i]
    if st then
      local v = VALUE[st] and VALUE[st]()
      t:SetText("|cffaaaaaa" .. i .. ".|r  " .. st .. (v and ("  |cffffffff" .. v .. "|r") or ""))
      t:Show()
    else t:SetText(""); t:Hide() end
  end

  -- NOW: the one thing to do. Missing a cap first; rating past a cap next, since
  -- that rating can be reforged into something that works; else the next stat.
  local RATED = { Crit = true, Haste = true, Mastery = true, Spirit = true, Dodge = true, Parry = true }
  -- Where Spirit turns into hit for the spec, reforging it "into Hit" moves nothing.
  if sd and sd.spiritIsHit and attack then RATED.Spirit = nil end
  local function lowestRated()   -- where reforged rating comes from
    for i = #list, 1, -1 do if RATED[list[i]] then return list[i] end end
  end
  local function bestRated()     -- where surplus rating should go
    for _, st in ipairs(list) do if RATED[st] then return st end end
  end
  local now
  local short
  for _, r in ipairs(rows) do if r.cur < r.cap - 0.005 then short = r; break end end
  if not sd then
    now = "Pick a specialization to get advice."
  elseif not attack then
    now = string.format("Healers have no hit or expertise cap. Your best secondary stat is %s.",
      bestRated() or "Spirit")
  elseif not vsBoss then
    now = string.format("While leveling, %s and item level carry you. Hit and expertise start to " ..
      "matter at level %d, against raid bosses.", sd.primary or "your main stat", maxLevel - 5)
  elseif short then
    local left = short.cap - short.cur
    local src = lowestRated()
    local what = (short.kind == "hit") and "hit" or "expertise"
    local lead = (short.kind == "hit" and "You miss a raid boss %.2f%% of the time.")
      or (short.kind == "dodge" and "A raid boss dodges %.2f%% of your attacks.")
      or "A raid boss still parries %.2f%% of your attacks from the front."
    local need = ratingOf(left, short.cr)
    now = string.format(lead, left) ..
      (need and string.format(" About %d %s rating to go.", need, what) or "") ..
      (src and (" Reforge " .. src .. " into " .. (what == "hit" and "Hit" or "Expertise") .. ".") or "")
  else
    local over
    for _, r in ipairs(rows) do
      local last = r.kind == "hit" or r.kind == "parry" or (r.kind == "dodge" and not tank)
      if last and r.cur - r.cap > 0.5 then over = r; break end
    end
    local best = bestRated() or "your next stat"
    if over then
      local extra = over.cur - over.cap
      local spare = ratingOf(extra, over.cr)
      now = string.format("You have %.2f%% more %s than a raid boss needs%s. Reforge it into %s.",
        extra, over.kind == "hit" and "hit" or "expertise",
        spare and string.format(" - about %d rating", spare) or "", best)
    else
      now = string.format("%s capped. Your next best stat is %s.",
        attack == "spell" and "Spell hit is" or "Hit and expertise are", best)
    end
  end
  UI.nowLine:SetText("|cffffd100NOW:|r |cffffffff" .. now .. "|r")
  UI.nowLine:Show()

  -- Notes behind the "i" icon
  local dw = tonumber(rawget(_G, "DUAL_WIELD_HIT_PENALTY")) or 19
  UI.infoParts = {}
  if sd and sd.notes then UI.infoParts[#UI.infoParts + 1] = sd.notes end
  if sd and sd.capNote then UI.infoParts[#UI.infoParts + 1] = sd.capNote end
  -- Only the notes that fit the role: a mage has no use for dual wielding or parry,
  -- a healer for any of it.
  if attack == "spell" then
    UI.infoParts[#UI.infoParts + 1] = string.format("SPELL HIT. The game's own character sheet starts " ..
      "a raid boss at %.1f%% spell miss and takes your hit off that. Your expertise counts toward it " ..
      "too - hit and expertise together fill the %.1f%% - but the sheet leaves expertise out of the " ..
      "spell hit it shows. StatCoach adds it in, so the bar can read higher than the sheet.",
      base("BaseMissChanceSpell", 3), base("BaseMissChanceSpell", 3))
  elseif attack then
    UI.infoParts[#UI.infoParts + 1] = string.format("HIT. The game's own character sheet starts a raid " ..
      "boss at %.1f%% miss and takes your hit off that. Dual wielding adds %d%% to white swings only - " ..
      "special attacks use the %.1f%%, and that is the number the bar shows.",
      base("BaseMissChancePhysical", 3), dw, base("BaseMissChancePhysical", 3))
    UI.infoParts[#UI.infoParts + 1] = string.format("EXPERTISE. Expertise takes away a raid boss's " ..
      "%.1f%% dodge first, and only then its %.1f%% parry. A boss cannot parry what hits it from behind, " ..
      "so a damage dealer stops at %.1f%%; a tank faces it and needs %.1f%%.",
      base("BaseEnemyDodgeChance", 3), base("BaseEnemyParryChance", 3), base("BaseEnemyDodgeChance", 3),
      base("BaseEnemyDodgeChance", 3) + base("BaseEnemyParryChance", 3))
  end
  if attack then
    UI.infoParts[#UI.infoParts + 1] = "REFORGE. A reforger moves part of one secondary stat on an item " ..
      "into another the item does not already have. Take it from the lowest stat on your list, and put it " ..
      "into hit or expertise until they are capped."
  end
  if sd and sd.source then UI.infoParts[#UI.infoParts + 1] = sd.source end
  if UI.notesPopup and UI.notesPopup:IsShown() then RefreshNotes(specName) end

  -- Layout: NOW, then the caps you can act on, then the list
  local y = -34
  PlaceRow(UI.info, y); y = y - math.max(UI.info:GetStringHeight() + 4, 18)
  PlaceRow(UI.row1, y); y = y - 24
  PlaceRow(UI.nowLine, y); y = y - (UI.nowLine:GetStringHeight() + 8)
  if #rows > 0 then
    PlaceRow(UI.capHeader, y); y = y - math.max(UI.capHeader:GetStringHeight() + 5, 18)
    for i = 1, #rows do PlaceRow(UI.bars[i], y); y = y - 34 end
    y = y - 2
  end
  PlaceRow(UI.prioHeader, y); y = y - math.max(UI.prioHeader:GetStringHeight() + 4, 16)
  for i = 1, PRIO_MAX do
    if UI.prio[i]:IsShown() then PlaceRow(UI.prio[i], y); y = y - 15 end
  end
  UI.frame:SetHeight(math.max(-y + PAD, 300))
end

------------------------------------------------------------------------
-- ERA path (Classic Era 1.15.x - Season of Discovery and Hardcore realms run on the
-- same client). No specializations: the spec is the talent tree with the most
-- points, as on TBC. Era's own character sheet shows no hit at all (Blizzard_
-- CharacterFrame/Vanilla/PaperDollFrame.lua, build 1.15.9.69722), so hit is the
-- game's hit modifier and the cap is worked out from your weapon skill with the
-- attack table Classic players measured (github.com/magey/classic-warrior/wiki/
-- Attack-table; Wowhead's pages agree: 9% at 300 skill, 6% at 305):
--   gap = target defense - weapon skill               (a raid boss has 315)
--   gap > 10:  miss 5% + gap * 0.2%, and the first (gap - 10) * 0.2% of hit is ignored
--   gap <= 10: miss 5% + gap * 0.1%
-- Spells: a target of your level resists 4%, one three levels up 17%, and 99% is the
-- most that can land - so 3% and 16% of spell hit (Wowhead's spell hit table).
-- All fields on UI/ns: this file sits at Lua's 200-local limit for one chunk.
------------------------------------------------------------------------
UI.ERA_SPELL_MISS = { [0] = 4, [1] = 5, [2] = 6, [3] = 17 }

-- Talent hit that only counts for one school, which the game's spell hit number leaves
-- out. The game's data says why: these four are "Modifies Hit Chance (16)" effects on
-- certain spells, while the hit number adds up "Mod ... Hit Chance %" auras only -
-- Surefooted, which is one, measured inside it (Wowhead Classic spell pages 11222,
-- 29438, 18174, 15260 vs 19290; CharacterStatsClassic adds three of them by hand too).
-- Found by tier and column, never by index: this client's index order within a tree
-- is not the tree's layout (Improved Corruption, tier 1 column 3, reads as index 3).
-- Positions from LibClassicInspector's Era tables, which match the client's own tier
-- and column for every talent the dumps showed. maxRank is the identity check.
-- { tab, tier, column, maxRank, % per rank, schools, only for spec }
UI.ERA_SCHOOL_HIT = {
  MAGE    = { { 1, 1, 2, 5, 2, { [7] = true } },                              -- Arcane Focus
              { 3, 1, 3, 3, 2, { [3] = true, [5] = true } } },                -- Elemental Precision
  WARLOCK = { { 1, 1, 2, 5, 2, { [6] = true }, "Affliction" } },              -- Suppression
  PRIEST  = { { 3, 2, 3, 5, 2, { [6] = true } } },                            -- Shadow Focus
}

-- Class, spec and spec data. AUTO reads the talent tree with the most points (the
-- fifth return of GetTalentTabInfo on this client, read off the probe 24 Sep 2026);
-- a druid in bear form gets the bear list. MANUAL browses like everywhere else.
ns.EraPick = function()
  local E = D and D.era
  local _, class = UnitClass("player")
  local cd = E and E.classes[class or ""]
  local detected
  if cd and type(GetTalentTabInfo) == "function" then
    local best, bestPts = nil, 0
    for i = 1, 3 do
      local ok, _, _, _, _, pts = pcall(GetTalentTabInfo, i)
      pts = ok and tonumber(pts) or 0
      if pts > bestPts then best, bestPts = i, pts end
    end
    detected = best and cd.tabSpec[best]
    if detected == "Feral (Cat)" then
      local form = safe(GetShapeshiftFormID)
      if form == 5 or form == 8 then detected = "Feral (Bear)" end
    end
  end
  local pc, ps = class, detected
  local db = StatCoachDB
  if db and db.manual and E then
    if E.classes[db.manualClass or ""] then pc = db.manualClass end
    local pcd = E.classes[pc or ""]
    ps = (pcd and pcd.specs[db.manualSpec or ""] and db.manualSpec) or (pcd and pcd.specOrder[1])
  end
  local pcd = E and E.classes[pc or ""]
  return pc, ps, pcd and pcd.specs[ps or ""], detected
end

UI.RefreshEra = function()
  if not UI.frame then return end
  local class, specName, sd = ns.EraPick()
  curCtx.role = nil
  curCtx.weights = {}
  curCtx.retailSd = false         -- no item verdicts on Era yet
  wipe(bagCache)
  UI.gemBtn:Hide(); UI.enchBtn:Hide(); UI.ctxBtn:Hide(); UI.row2:Hide()
  UI.radar:Hide()
  UI.compareHeader:Hide(); UI.compareLine:Hide()

  -- Season of Discovery runs on this client, but its runes rewrite what each spec
  -- wants: the caps still hold there, the Era stat lists do not.
  local sodId = (Enum and Enum.SeasonID and Enum.SeasonID.SeasonOfDiscovery) or 2
  local sod = C_Seasons ~= nil and safe(C_Seasons.GetActiveSeason) == sodId

  local level = UnitLevel("player") or 1
  local cc = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or { r = 1, g = 1, b = 1 }
  local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
  UI.info:SetText(string.format("Lv %d  |cff%s%s|r  \226\128\162  %s%s",
    level, hex, class or "?", specName or "no talents yet", sod and "  \226\128\162  Season of Discovery" or ""))

  -- Class / spec row: AUTO follows the character, MANUAL browses.
  local manual = StatCoachDB.manual
  UI.row1:Show()
  UI.classBtn:SetLabel(class or "?")
  UI.specBtn:SetLabel(specName or "?")
  UI.autoBtn:SetLabel(manual and "|cffffff00MANUAL|r" or "|cff40ff40AUTO|r")
  UI.classBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetPoint("LEFT", UI.classBtn, "RIGHT", 4, 0)
  UI.autoBtn:ClearAllPoints()
  UI.autoBtn:SetPoint("RIGHT", UI.autoBtn:GetParent(), "RIGHT", 0, 0)
  local rowW = UI.autoBtn:GetParent():GetWidth() or 0
  local maxSpec = rowW - UI.classBtn:GetWidth() - UI.autoBtn:GetWidth() - 12
  if maxSpec > 40 and UI.specBtn:GetWidth() > maxSpec then
    UI.specBtn:SetWidth(maxSpec)
    UI.specBtn.text:SetWidth(maxSpec - 12)
  end

  -- Against whom: a target of your own level while leveling, a raid boss from five
  -- levels below the cap, because that is the number gear is then chosen by.
  local maxLevel = safe(GetMaxPlayerLevel) or 60
  local vsBoss = level >= maxLevel - 5
  local targetLevel = vsBoss and (maxLevel + 3) or level
  -- Before the first talent point there is no spec yet; the class still decides what
  -- it hits with, so the weapon skill and hit bars are there from level 1.
  local attack
  if sd then attack = sd.attack
  else attack = ({ MAGE = "spell", PRIEST = "spell", WARLOCK = "spell", HUNTER = "ranged" })[class or ""] or "melee" end
  local school = sd and sd.school
  local tank = sd and sd.role == "TANK"
  local function hitCap(skill, vsLevel)
    local gap = math.max(0, (vsLevel or targetLevel) * 5 - skill)
    if gap > 10 then return 5 + gap * 0.2 + (gap - 10) * 0.2 end
    return 5 + gap * 0.1
  end

  -- Weapon skill in your hands: base, plus what racials and items add
  local mhBase, mhMod, ohBase, ohMod = safe(UnitAttackBothHands, "player")
  local rBase, rMod = safe(UnitRangedAttack, "player")
  local mhSkill = num(mhBase) + num(mhMod)
  local rSkill = num(rBase) + num(rMod)

  local hitRows = {}
  local talentHit = 0
  if attack == "spell" then
    local spellHit = desecret(safe(GetSpellHitModifier))
    for _, t in ipairs(UI.ERA_SCHOOL_HIT[class or ""] or {}) do
      if school and t[6][school] and (not t[7] or t[7] == specName) then
        for i = 1, tonumber((safe(GetNumTalents, t[1]))) or 0 do
          local ok, _, _, tier, column, rank, maxRank = pcall(GetTalentInfo, t[1], i)
          if ok and tier == t[2] and column == t[3] then
            if maxRank == t[4] and rank and rank > 0 then talentHit = talentHit + rank * t[5] end
            break
          end
        end
      end
    end
    local d = math.min(3, math.max(0, targetLevel - level))
    if spellHit then
      hitRows[1] = { label = "Spell hit", cur = spellHit + talentHit, cap = UI.ERA_SPELL_MISS[d] - 1 }
    end
  elseif attack == "ranged" then
    -- The hit modifier carries gear AND talent hit: a level-52 hunter with Surefooted 3/3
    -- and 1% on the legs read 4 (24 Sep 2026). This client has no GetRangedHitModifier.
    local h = desecret(safe(rawget(_G, "GetRangedHitModifier") or GetHitModifier))
    -- Biznicks 247x128 Accurascope: +3% ranged hit the modifier does not include
    -- (enchant 2523; CharacterStatsClassic adds it the same way)
    local link = GetInventoryItemLink("player", 18)
    if h and link and tonumber(link:match("item:%d+:(%d*)") or "") == 2523 then h = h + 3 end
    if h then hitRows[1] = { label = "Ranged hit", cur = h, cap = hitCap(rSkill), skill = rSkill } end
  elseif attack == "melee" then
    local h = desecret(safe(GetHitModifier))
    if h then hitRows[1] = { label = "Hit", cur = h, cap = hitCap(mhSkill), skill = mhSkill } end
  end
  local versus = vsBoss and "raid bosses" or ("level " .. level)
  for _, r in ipairs(hitRows) do r.label = r.label .. " vs " .. versus end

  -- Weapon skill bars: only what is in your hands. Melee gets main hand (and off-hand
  -- when it holds a weapon), a hunter the bow or gun, a caster the wand it fires.
  -- Tanks get Defense on top. A weapon racial is already inside the base skill the
  -- game reports (a level-1 human reads 6 in maces: 1 plus the racial 5), so it
  -- raises the maximum too.
  local skillRows = {}
  local _, race = UnitRace("player")
  local racialKinds = RACIAL_WEAPONS[race or ""] or {}
  local function weaponRow(slot, hand, base, mod)
    local link = GetInventoryItemLink("player", slot)
    local kind = link and select(3, GetItemInfoInstant(link))
    if not link and slot ~= 16 then return end
    base = tonumber(base)
    if not base or base <= 0 then return end
    -- The weapon type alone fits the bar ("Main hand - Two-Handed Maces" was cut off in
    -- the client, 24 Sep 2026); the off-hand only says so when it is the same type.
    local name = kind or "Unarmed"
    if hand == "Wand" then name = hand
    elseif hand == "Off hand" and skillRows[1] and skillRows[1].kind == (kind or "unarmed") then name = hand end
    skillRows[#skillRows + 1] = { name = name, kind = kind or "unarmed",
      rank = base, max = level * 5 + (weaponBenefits(link, racialKinds) and 5 or 0),
      bonus = num(tonumber(mod)), weapon = true }
  end
  -- A druid fights in forms, where weapon skill does not apply: no weapon bars there.
  local druid = class == "DRUID"
  if attack == "melee" and not druid then
    weaponRow(16, "Main hand", mhBase, mhMod)
    if IsDualWielding() then weaponRow(17, "Off hand", ohBase, ohMod) end
  elseif attack == "ranged" then
    weaponRow(18, "Ranged", rBase, rMod)
  elseif GetInventoryItemLink("player", 18) and not druid then
    weaponRow(18, "Wand", rBase, rMod)
  end
  if tank then
    local base, mod = safe(UnitDefense, "player")
    base = tonumber(base)
    if base then
      skillRows[#skillRows + 1] = { name = "Defense", rank = base, max = level * 5, bonus = num(tonumber(mod)),
        cap = vsBoss and 440 or nil }
    end
  end
  local CRIT_PER_SKILL = 0.04   -- per point below the maximum (measured on Forever, same ruleset)
  local function critCost(sk)
    if not sk.weapon or sk.rank >= sk.max then return 0 end
    return (sk.max - sk.rank) * CRIT_PER_SKILL
  end
  local function costText(cost) return string.format(cost < 1 and "%.2f%%" or "%.1f%%", cost) end

  if not UI.fvHitHeader then
    local h = UI.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetJustifyH("LEFT"); h:SetWordWrap(false)
    UI.fvHitHeader = h
  end
  UI.fvHitHeader:SetText(attack == "spell" and "|cffffd100SPELL HIT|r  |cff888888(the most that can land)|r"
    or "|cffffd100HIT|r  |cff888888(what it takes to never miss)|r")
  if #hitRows > 0 then UI.fvHitHeader:Show() else UI.fvHitHeader:Hide() end
  UI.capHeader:SetText("|cffffd100" .. (tank and "WEAPON SKILL & DEFENSE" or "WEAPON SKILL") ..
    "|r  |cff888888(skill / max)|r")
  if #skillRows > 0 then UI.capHeader:Show() else UI.capHeader:Hide() end

  for i = 1, BAR_MAX do
    local b = UI.bars[i]
    local h, sk = hitRows[i], skillRows[i - #hitRows]
    b.bar.markFrac = nil
    b.bar.mark:Hide()
    if h then
      local done = h.cur >= h.cap - 0.005
      b.label:SetText(h.label)
      b.bar:SetValue(math.min(1, h.cur / h.cap))
      if done then b.bar:SetStatusBarColor(0.2, 0.7, 0.2) else b.bar:SetStatusBarColor(0.3, 0.55, 0.9) end
      b.val:SetText(fmt(h.cur) .. "% / " .. fmt(h.cap) .. "%" .. (done and "  |cff40ff40capped|r" or ""))
      b:Show()
    elseif sk then
      local total = sk.rank + sk.bonus
      local goal = sk.cap or sk.max
      local shown = sk.cap and total or sk.rank
      b.label:SetText(sk.name .. (sk.cap and " vs raid bosses" or ""))
      b.bar:SetValue(math.min(1, shown / goal))
      if shown >= goal then b.bar:SetStatusBarColor(0.2, 0.7, 0.2)
      else b.bar:SetStatusBarColor(0.85, 0.65, 0.1) end
      local txt = string.format("%d / %d", shown, goal)
      if not sk.cap and sk.bonus > 0 then txt = txt .. string.format("  |cff40ff40(+%d)|r", sk.bonus) end
      local cost = critCost(sk)
      if cost > 0 then txt = txt .. "  |cffff9040-" .. costText(cost) .. " crit|r" end
      b.val:SetText(txt)
      b:Show()
    else b:Hide() end
  end

  -- The stat list, each with the character's own number next to it. Not on Season
  -- of Discovery, where the Era guides do not apply.
  local list = (not sod and sd and sd.stats) or {}
  local reads = attack or "spell"
  local function p2(v) v = desecret(v); return v and string.format("%.2f%%", v) or nil end
  local function big(v)
    v = desecret(v)
    if not v then return nil end
    v = math.floor(v + 0.5)
    return (type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(v)) or tostring(v)
  end
  local function unitStat(i) local _, eff = safe(UnitStat, "player", i); return eff end
  local mainHit = hitRows[1]
  local VALUE = {
    Strength  = function() return big(unitStat(1)) end,
    Agility   = function() return big(unitStat(2)) end,
    Stamina   = function() return big(unitStat(3)) end,
    Intellect = function() return big(unitStat(4)) end,
    Spirit    = function() return big(unitStat(5)) end,
    Hit       = function() return mainHit and p2(mainHit.cur) end,
    ["Spell Hit"] = function() return mainHit and p2(mainHit.cur) end,
    Crit      = function() return p2(safe(reads == "ranged" and GetRangedCritChance or GetCritChance)) end,
    ["Spell Crit"] = function() return p2(safe(GetSpellCritChance, school or 2)) end,
    Haste     = function() return p2(safe(GetMeleeHaste)) end,
    ["Spell Damage"]  = function() return big(safe(GetSpellBonusDamage, school or 2)) end,
    ["Healing Power"] = function() return big(safe(GetSpellBonusHealing)) end,
    ["Attack Power"] = function()
      local b, p, n = safe(reads == "ranged" and UnitRangedAttackPower or UnitAttackPower, "player")
      if b == nil then return nil end
      return big(num(desecret(b)) + num(desecret(p)) + num(desecret(n)))
    end,
    ["Weapon Skill"] = function() return mhSkill > 0 and tostring(mhSkill) or nil end,
    Defense = function() local b, m = safe(UnitDefense, "player"); return b and tostring(num(b) + num(m)) end,
    Armor = function() local _, eff = safe(UnitArmor, "player"); return big(eff) end,
    Dodge = function() return p2(safe(GetDodgeChance)) end,
  }
  UI.prioHeader:SetText("|cffffd100PRIORITY|r" .. (vsBoss and "" or "  |cff888888(for level 60 raiding)|r"))
  for i = 1, PRIO_MAX do
    local t, st = UI.prio[i], list[i]
    if st then
      local v = VALUE[st] and VALUE[st]()
      t:SetText("|cffaaaaaa" .. i .. ".|r  " .. st .. (v and ("  |cffffffff" .. v .. "|r") or ""))
      t:Show()
    else t:SetText(""); t:Hide() end
  end

  -- NOW: the one thing to do. A weapon skill that lags is the one thing a leveling
  -- character can fix on the spot, so it goes first; then hit; then the next stat.
  local IS_HIT = { Hit = true, ["Spell Hit"] = true, ["Weapon Skill"] = true }
  local function nextStat()
    for _, st in ipairs(list) do if not IS_HIT[st] then return st end end
  end
  -- (a caster's wand gets its bar, but never the NOW line)
  local lag
  if attack == "melee" or attack == "ranged" then
    for _, sk in ipairs(skillRows) do if sk.weapon and sk.rank < sk.max then lag = sk; break end end
  end
  local now
  if lag then
    -- it only costs hit while the skill sits below the target's defense
    local hurtsHit = lag.rank + lag.bonus < targetLevel * 5
    now = string.format("Your %s skill is %d of %d - that costs you %s crit%s. " ..
      "It only rises while you fight with that weapon.", lag.kind, lag.rank, lag.max, costText(critCost(lag)),
      hurtsHit and " and raises the hit you need" or "")
  elseif not sd then
    now = level < 10 and "Talents start at level 10 - StatCoach reads your spec from where you spend them."
      or "Spend a talent point and StatCoach reads your spec from it."
  elseif sd.role == "HEALER" then
    now = "Healers have no hit cap." .. (list[1] and (" " .. list[1] .. " comes first for you.") or "")
  elseif mainHit and mainHit.cur < mainHit.cap - 0.005 and (vsBoss or mainHit.cur > 0) then
    local left = mainHit.cap - mainHit.cur
    if attack == "spell" then
      -- 1% of spells is always resisted, on top of what hit can remove
      now = string.format("%s resists %.1f%% of your spells - %.1f%% more spell hit to go.",
        vsBoss and "A raid boss" or ("A level " .. level .. " target"), left + 1, left)
    else
      now = string.format("You miss %s %.1f%% of the time - %.1f%% more hit to go.",
        vsBoss and "a raid boss" or ("a level " .. level .. " target"), left, left)
    end
    if vsBoss and mainHit.skill and mainHit.skill < targetLevel * 5 - 10 and not druid then
      now = now .. string.format(" %d more weapon skill would lower the cap to %.1f%%.",
        targetLevel * 5 - 10 - mainHit.skill, hitCap(targetLevel * 5 - 10))
    elseif list[1] and not IS_HIT[list[1]] then
      now = now .. " Your guide still ranks " .. list[1] .. " above it."
    end
  elseif mainHit and mainHit.cur >= mainHit.cap - 0.005 then
    local nx = nextStat()
    now = (sd.dw and "Hit is capped for your specials; past it, hit still helps your white swings."
      or "Hit is capped - more does nothing.") .. (nx and (" Your next stat is " .. nx .. ".") or "")
  else
    -- only a stat the guide put first; no list (Season of Discovery), no stat named
    local nx = nextStat()
    now = (nx and string.format("While leveling, %s carries you.", nx) or "Nothing to fix right now.") ..
      string.format(" The hit bar switches to raid bosses at level %d.", maxLevel - 5)
  end
  UI.nowLine:SetText("|cffffd100NOW:|r |cffffffff" .. now .. "|r")
  UI.nowLine:Show()

  -- Notes behind the "i" icon, only the ones that fit the role
  UI.infoParts = {}
  if sod then
    UI.infoParts[#UI.infoParts + 1] = "SEASON OF DISCOVERY. Runes change what each spec wants, so the " ..
      "Classic Era stat lists are switched off here. Hit caps and weapon skill work the same, and stay on."
  elseif sd and sd.notes then
    UI.infoParts[#UI.infoParts + 1] = sd.notes
  end
  if attack == "melee" or attack == "ranged" then
    local skill = mainHit and mainHit.skill or 300
    UI.infoParts[#UI.infoParts + 1] = string.format("HIT. A raid boss has 315 defense. At 300 weapon skill " ..
      "you miss it 8%% of the time, and because the gap is over 10 points the game also ignores your first " ..
      "1%% of hit - so you need 9%%. At 305 the gap is 10, and 6%% does it. Against raid bosses your skill " ..
      "of %d puts the cap at %.1f%%.%s",
      skill, hitCap(skill, maxLevel + 3),
      sd and sd.dw and " Dual wielding adds 19% to white swings only; specials use the cap above." or "")
    if not druid then
      UI.infoParts[#UI.infoParts + 1] = "WEAPON SKILL. The maximum is five per level. Every point below it " ..
        "costs about 0.04% crit and raises the hit you need; extra skill from racials and items lowers it."
    end
  elseif attack == "spell" then
    UI.infoParts[#UI.infoParts + 1] = "SPELL HIT. A raid boss resists 17% of your spells, and 1% always gets " ..
      "resisted - so 16% spell hit is the cap (3% against a target of your level)." ..
      (talentHit > 0 and string.format(" The game's spell hit number leaves out talents that only work for " ..
        "one school; StatCoach adds your %d%% from them.", talentHit) or "")
  end
  if tank then
    UI.infoParts[#UI.infoParts + 1] = "DEFENSE. 440 defense stops raid bosses from landing critical strikes on you."
  end
  if not sod and sd and sd.source then UI.infoParts[#UI.infoParts + 1] = sd.source end
  if UI.notesPopup and UI.notesPopup:IsShown() then RefreshNotes(specName) end

  -- Layout: NOW, then what you can act on (hit, weapon skill), then the list
  local y = -34
  PlaceRow(UI.info, y); y = y - math.max(UI.info:GetStringHeight() + 4, 18)
  PlaceRow(UI.row1, y); y = y - 24
  PlaceRow(UI.nowLine, y); y = y - (UI.nowLine:GetStringHeight() + 8)
  if #hitRows > 0 then
    PlaceRow(UI.fvHitHeader, y); y = y - math.max(UI.fvHitHeader:GetStringHeight() + 5, 18)
    for i = 1, #hitRows do PlaceRow(UI.bars[i], y); y = y - 34 end
    y = y - 2
  end
  if #skillRows > 0 then
    PlaceRow(UI.capHeader, y); y = y - math.max(UI.capHeader:GetStringHeight() + 5, 18)
    for i = #hitRows + 1, BAR_MAX do
      if UI.bars[i]:IsShown() then PlaceRow(UI.bars[i], y); y = y - 34 end
    end
    y = y - 2
  end
  if #list > 0 then
    PlaceRow(UI.prioHeader, y); y = y - math.max(UI.prioHeader:GetStringHeight() + 4, 16)
    UI.prioHeader:Show()
    for i = 1, PRIO_MAX do
      if UI.prio[i]:IsShown() then PlaceRow(UI.prio[i], y); y = y - 15 end
    end
  else
    UI.prioHeader:Hide()
  end
  UI.frame:SetHeight(math.max(-y + PAD, 300))
end

------------------------------------------------------------------------
-- Refresh: fill everything in
------------------------------------------------------------------------
function Refresh()
  if not UI.frame then return end
  if FOREVER then return RefreshForever() end
  if MISTS then return UI.RefreshMists() end
  if ns.ERA then return UI.RefreshEra() end
  if RETAIL then return RefreshRetail() end
  local class, spec, context = Resolve()
  local cd = D.classes[class]
  local sd = cd.specs[spec]
  local s = ReadStats()
  curCtx.role = sd.role
  curCtx.weights = sd.weights or D.WEIGHTS[sd.role] or {}
  curCtx.context = context
  curCtx.charTotal = nil   -- gear changed or context flipped: total is stale
  wipe(bagCache)

  local level = UnitLevel("player") or 1
  local cc = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]) or { r = 1, g = 1, b = 1 }
  local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
  local ctxLabel = ({ leveling = "Leveling", preraid = "Pre-raid", endgame = "Endgame" })[context] or "Leveling"
  UI.info:SetText(string.format("Lv %d  |cff%s%s|r  \226\128\162  %s  (%s)",
    level, hex, class, spec, ctxLabel))

  local manual = StatCoachDB.manual
  UI.classBtn:SetLabel(class)
  UI.specBtn:SetLabel(spec)
  UI.autoBtn:SetLabel(manual and "|cffffff00MANUAL|r" or "|cff40ff40AUTO|r")
  UI.classBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetAlpha(manual and 1 or 0.45)
  UI.specBtn:SetPoint("LEFT", UI.classBtn, "RIGHT", 4, 0)
  -- Keep the row inside the frame: AUTO pins to the right edge, and the Spec
  -- button shrinks (text truncates) if a long spec name would overflow.
  UI.autoBtn:ClearAllPoints()
  UI.autoBtn:SetPoint("RIGHT", UI.autoBtn:GetParent(), "RIGHT", 0, 0)
  local rowW = UI.autoBtn:GetParent():GetWidth() or 0
  local maxSpec = rowW - UI.classBtn:GetWidth() - UI.autoBtn:GetWidth() - 12
  if maxSpec > 40 and UI.specBtn:GetWidth() > maxSpec then
    UI.specBtn:SetWidth(maxSpec)
    UI.specBtn.text:SetWidth(maxSpec - 12)
  end

  -- Classic keeps row 2: here the context button really does cycle
  -- leveling / pre-raid / endgame, and gems + enchants have their own popups.
  UI.row2:Show()
  UI.ctxBtn:Show()
  UI.ctxBtn:SetLabel("Context: " .. ctxLabel)

  -- Just "PRIORITY": the context already stands in the title line AND on the
  -- Context button - a third repeat was noise, not information.
  UI.prioHeader:SetText("|cffffd100PRIORITY|r")

  -- Build the live (cap-aware) display list + the NOW trade advice
  local base = resolveList(sd, context)
  local display = buildDisplay(context, sd.role, base, s)
  local nowText = nowAdvice(context, sd.role, base, s)

  for i = 1, PRIO_MAX do
    local t, e = UI.prio[i], display[i]
    if e then
      if e.done then
        t:SetText("|cff666666" .. i .. ". " .. e.text .. "  (capped)|r")
      else
        t:SetText("|cffaaaaaa" .. i .. ".|r  " .. e.text)
      end
      t:Show()
    else t:SetText(""); t:Hide() end
  end

  if nowText then
    UI.nowLine:SetText("|cffffd100NOW:|r |cffffffff" .. nowText .. "|r")
    UI.nowLine:Show()
  else UI.nowLine:Hide() end

  -- Spec note gathered for the info tooltip (combined with the caps note below)
  local noteText = (context ~= "leveling") and sd.notes or nil

  -- Gems live in the popup; keep it updated (belowHit swaps the yellow socket)
  local belowHit = false
  if sd.role == "caster" then belowHit = s.spellHitTotal < D.CAP.spellHitPct
  elseif sd.role == "ranged" then belowHit = s.rangedHitTotal < s.capRangedHit
  elseif sd.role == "melee" or sd.role == "meleeDW" then belowHit = s.meleeHitTotal < s.capMeleeHit end
  RefreshGems(sd.role, belowHit, spec, context ~= "endgame")
  RefreshEnchants(sd.role, spec)

  -- Caps exist at all levels, but you never reach them while leveling -> hide the section
  -- there (keep the info in the notes popup) and show the live bars only at 70.
  local showBars = (context ~= "leveling")
  local bars = showBars and CapBarsFor(sd.role, s) or {}
  if showBars then
    UI.capHeader:SetText("|cffffd100CAPS|r  |cff888888(live, vs boss +3)|r")
    UI.capHeader:Show()
  else
    UI.capHeader:Hide()
  end
  local capNote
  if not showBars then
    capNote = "Caps (hit 9% / expertise 26) are reached at 70 with gear - not a leveling concern."
  elseif #bars == 0 then
    if sd.role == "healer" then capNote = "No hard cap - balance throughput vs mana."
    elseif sd.role == "tankDruid" then capNote = "Bear: uncrittable via agility/resilience, not defense."
    else capNote = "" end
  else
    capNote = "Hit includes your talents AND Draenei aura (auto-detected from buffs). Debuffs on the boss (Misery / Totem of Wrath) lower the need further."
  end

  -- All notes gathered behind the info icon / Notes popup
  UI.infoParts = {}
  if noteText and noteText ~= "" then UI.infoParts[#UI.infoParts + 1] = noteText end
  if capNote and capNote ~= "" then UI.infoParts[#UI.infoParts + 1] = capNote end
  RefreshNotes(spec)

  for i = 1, BAR_MAX do
    local b, data = UI.bars[i], bars[i]
    if data then
      b.label:SetText(data.label)
      local col = data.done and { 0.25, 0.8, 0.25 } or { 0.85, 0.65, 0.1 }
      b.bar:SetStatusBarColor(col[1], col[2], col[3])
      b.bar:SetValue(data.frac)
      local curStr = (data.unit == "%") and (fmt(data.cur) .. "%") or tostring(math.floor(data.cur + 0.5))
      local tgtStr = (data.unit == "%") and (data.target .. "%") or tostring(data.target)
      local nt = data.done and ("|cff40ff40" .. data.needText .. "|r") or ("|cffffd100" .. data.needText .. "|r")
      b.val:SetText(curStr .. " / " .. tgtStr .. "  " .. nt)
      b:Show()
    else b:Hide() end
  end

  -- Hovered-item compare footer
  local hlabel, hhex
  if UI.hover then hlabel, hhex = verdictOf(UI.hover) end
  if hlabel then
    UI.compareHeader:SetText("|cffffd100HOVERED ITEM|r")
    UI.compareLine:SetText("|cff88aaff" .. UI.hover.name .. "|r  |cff" .. hhex .. hlabel .. "|r")
    UI.compareHeader:Show(); UI.compareLine:Show()
  else
    UI.compareHeader:Hide(); UI.compareLine:Hide()
  end

  -- Layout
  local y = -34
  PlaceRow(UI.info, y); y = y - math.max(UI.info:GetStringHeight() + 4, 18)
  PlaceRow(UI.row1, y); y = y - 24
  if UI.row2:IsShown() then PlaceRow(UI.row2, y); y = y - 26 end
  if UI.nowLine:IsShown() then
    PlaceRow(UI.nowLine, y); y = y - (UI.nowLine:GetStringHeight() + 8)
  end
  PlaceRow(UI.prioHeader, y); y = y - math.max(UI.prioHeader:GetStringHeight() + 4, 16)
  for i = 1, PRIO_MAX do
    if display[i] then PlaceRow(UI.prio[i], y); y = y - 15 end
  end
  if UI.capHeader:IsShown() then
    y = y - 6
    PlaceRow(UI.capHeader, y); y = y - math.max(UI.capHeader:GetStringHeight() + 5, 18)
  end
  for i = 1, BAR_MAX do
    if bars[i] then PlaceRow(UI.bars[i], y); y = y - 34 end
  end
  if UI.compareLine:IsShown() then
    y = y - 8
    PlaceRow(UI.compareHeader, y); y = y - math.max(UI.compareHeader:GetStringHeight() + 4, 15)
    PlaceRow(UI.compareLine, y); y = y - (UI.compareLine:GetStringHeight() + 4)
  end

  -- Fixed floor = the tallest layout (rogue: 6 priorities + 3 cap bars), so the
  -- window keeps ONE size no matter which class/spec/context you toggle to.
  UI.frame:SetHeight(math.max(-y + PAD, 430))
end

------------------------------------------------------------------------
-- Mode / cycle actions
------------------------------------------------------------------------
local function indexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end return 1 end

-- The two flavors browse different rosters: retail has 13 classes and 39 specs,
-- classic the 9 TBC ones. Everything below works off whichever pair applies.
local function browseTables()
  if RETAIL or MISTS then local r = ns.SpecData(); return r.classOrder, r.classes end
  if ns.ERA then return D.era.classOrder, D.era.classes end
  return D.classOrder, D.classes
end

local function currentPick()
  if RETAIL or MISTS then local c, s = RetailDetect(); return c, s end
  if ns.ERA then local c, s = ns.EraPick(); return c, s end
  local c, s = Resolve(); return c, s
end

UI.cycleClass = function(dir)
  if not StatCoachDB.manual then return end
  dir = dir or 1
  local order, classes = browseTables()
  local class = StatCoachDB.manualClass or DetectClass()
  if not classes[class] then class = order[1] end
  local n = #order
  local i = indexOf(order, class)
  local nextClass = order[((i - 1 + dir) % n) + 1]
  StatCoachDB.manualClass = nextClass
  StatCoachDB.manualSpec = classes[nextClass].specOrder[1]
  Refresh()
end

UI.cycleSpec = function(dir)
  if not StatCoachDB.manual then return end
  dir = dir or 1
  local order, classes = browseTables()
  local class = StatCoachDB.manualClass or DetectClass()
  if not classes[class] then class = order[1] end
  local cd = classes[class]
  local _, curSpec = currentPick()
  local so = cd.specOrder
  local n = #so
  local i = indexOf(so, curSpec)
  StatCoachDB.manualClass = class
  StatCoachDB.manualSpec = so[((i - 1 + dir) % n) + 1]
  Refresh()
end

UI.toggleMode = function()
  local db = StatCoachDB
  if db.manual then
    db.manual = false
  else
    -- Seed manual mode with whatever is already on screen, so the first click
    -- only changes the mode - you start browsing from where you actually are.
    local class, spec = currentPick()
    db.manual = true
    db.manualClass = class
    db.manualSpec = spec
  end
  Refresh()
end

UI.cycleContext = function(dir)
  if RETAIL or MISTS or ns.ERA then return end   -- no leveling/preraid/endgame tiers there (yet)
  dir = dir or 1
  local order = { "leveling", "preraid", "endgame" }
  local _, _, cur = Resolve()
  local n = #order
  local i = indexOf(order, cur)
  StatCoachDB.contextMode = order[((i - 1 + dir) % n) + 1]
  Refresh()
end

-- Close the main window and every StatCoach popup (gems / enchants)
UI.hideAll = function()
  if UI.frame then UI.frame:Hide() end
  if UI.gemPopup then UI.gemPopup:Hide() end
  if UI.enchPopup then UI.enchPopup:Hide() end
  if UI.notesPopup then UI.notesPopup:Hide() end
  StatCoachDB.shown = false
end

------------------------------------------------------------------------
-- Debounce refresh
------------------------------------------------------------------------
local pending
local function ScheduleRefresh()
  if pending then return end
  pending = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.15, function() pending = false; Refresh() end)
  else pending = false; Refresh() end
end

------------------------------------------------------------------------
-- Minimap button (toggle the window without typing /stc)
------------------------------------------------------------------------
-- Every badge in the addon is registered here so a surface can be switched off
-- and the ones already drawn disappear with it, instead of lingering until the
-- window happens to redraw.
local badgeHolders = {}
local function BadgeSurfaceOn(surface)
  local b = StatCoachDB and StatCoachDB.badges
  return not (surface and b and b[surface] == false)
end
-- Both switches must work in BOTH directions at once, without waiting for the
-- window to redraw - a bag that is already open and idle would otherwise make
-- the switch look one-way.
--
-- Rather than each switch remembering what it hid, a badge remembers the ITEM
-- it was drawn for, and the switches just ask the question again. That is what
-- keeps the master switch and the per-surface ones from treading on each other:
-- turn everything off, turn one surface off, turn everything back on, and that
-- one surface correctly stays hidden.
local function HideBadge(holder)
  if not holder then return end
  holder.scLink = nil
  holder:Hide()
end

-- Assigned further down, where the badge visuals live. Declared here because
-- every settings switch above needs to redraw badges that are already up.
local ApplyGlowBadge

-- Re-decides every badge that is currently on screen. Each one remembers the
-- item it was drawn for, so this can simply ask the question again - which
-- makes EVERY setting take effect at once: the master switch, the per-surface
-- ones, the threshold, the armour filter, the badge size and the pulse. The
-- alternative was a special case per setting, and the ones without a special
-- case are exactly the ones that look broken.
local function RefreshBadges()
  local master = not StatCoachDB or StatCoachDB.bagBadge
  for _, h in ipairs(badgeHolders) do
    local pct = (master and h.scLink and BadgeSurfaceOn(h.scSurface))
      and bagUpgradePct(h.scLink) or nil
    if pct and ApplyGlowBadge then
      ApplyGlowBadge(h, pct)
      h:Show()
    else
      h:Hide()
    end
  end
end

-- Everything below is APPEARANCE. The weights and the caps are deliberately not
-- in here: knowing where TBC's caps sit, and scoring a capped stat at nearly
-- nothing without being told to, is the whole point of the addon. Pawn already
-- exists for people who want to tune weights, and a StatCoach whose numbers you
-- can break is just a worse Pawn.
local UPGRADE_FLOORS = {
  { 1,  "anything (1%)" },
  { 5,  "5%" },
  { 10, "10%" },
  { 25, "big upgrades only (25%)" },
}
local BADGE_SIZES = { 14, 18, 22, 26 }
local ICON_SIZES = { 12, 14, 18, 22 }

-- Which surfaces the upgrade badge may draw on, in the order they appear in the
-- menu. Everything is on until switched off, so a new surface never arrives
-- silently disabled for someone who has settings saved from an older version.
local BADGE_SURFACES = {
  { "bags",    "Bags" },
  { "quest",   "Quest rewards" },
  { "vendor",  "Vendor" },
  { "loot",    "Loot" },
  { "roll",    "Loot rolls" },
  { "craft",   "Crafting" },
  { "bank",    "Bank" },
  { "mail",    "Mail" },
  { "auction", "Auction house" },
  { "trade",   "Trade" },
  { "atlas",   "AtlasLoot" },
}

-- Right-click settings menu -- tries the modern Menu API, falls back to EasyMenu
local settingsMenuFrame
local function ShowSettingsMenu(anchor)
  local db = StatCoachDB
  db.badges = db.badges or {}
  local function toggleSurface(key)
    -- Spelled out rather than an and/or one-liner: the value being flipped is
    -- false-or-nil, and that idiom cannot express it - "(x == false) or nil"
    -- evaluates to nil in both directions, so the switch never actually
    -- switched off. Absent still means on, so turning it back on removes the key.
    if db.badges[key] == false then db.badges[key] = nil else db.badges[key] = false end
    RefreshBadges()
    wipe(bagCache)
  end
  local function applyScale(s) db.scale = s; if UI.frame then UI.frame:SetScale(s) end end
  local function resetPos()
    db.point, db.x, db.y = "CENTER", 0, 0
    if UI.frame then UI.frame:ClearAllPoints(); UI.frame:SetPoint("CENTER") end
  end
  local function hideMinimap()
    if not db.minimap.hide then StatCoach_ToggleMinimap() end
  end

  -- 1) modern Menu API (Anniversary / retail-based client)
  if MenuUtil and MenuUtil.CreateContextMenu then
    local ok = pcall(MenuUtil.CreateContextMenu, anchor or UIParent, function(_, root)
      root:CreateTitle("StatCoach")
      root:CreateCheckbox("Tooltip verdict line", function() return db.tooltip end,
        function() db.tooltip = not db.tooltip end)
      root:CreateCheckbox("Gem hint on empty sockets", function() return db.gemHints ~= false end,
        function() db.gemHints = (db.gemHints == false) or nil end)
      root:CreateCheckbox("Upgrade badges", function() return db.bagBadge end,
        function() db.bagBadge = not db.bagBadge; RefreshBadges(); wipe(bagCache) end)
      local where = root:CreateButton("Show badges in")
      for _, sf in ipairs(BADGE_SURFACES) do
        where:CreateCheckbox(sf[2], function() return db.badges[sf[1]] ~= false end,
          function() toggleSurface(sf[1]) end)
      end
      local floorSub = root:CreateButton("Flag upgrades above")
      for _, f in ipairs(UPGRADE_FLOORS) do
        floorSub:CreateRadio(f[2], function() return (db.minUpgrade or 1) == f[1] end,
          function() db.minUpgrade = f[1]; wipe(bagCache); RefreshBadges() end)
      end
      root:CreateCheckbox("Pulse the badge", function() return not db.noPulse end,
        function() db.noPulse = not db.noPulse or nil; RefreshBadges() end)
      local badgeSub = root:CreateButton("Badge size")
      for _, n in ipairs(BADGE_SIZES) do
        badgeSub:CreateRadio(tostring(n), function() return (db.badgeSize or 18) == n end,
          function() db.badgeSize = n; RefreshBadges() end)
      end
      local iconSub = root:CreateButton("Tooltip icon size")
      for _, n in ipairs(ICON_SIZES) do
        iconSub:CreateRadio(tostring(n), function() return (db.iconSize or 14) == n end,
          function() db.iconSize = n end)
      end
      root:CreateCheckbox("Hide off-type armour entirely", function() return db.armorStrict end,
        function() db.armorStrict = not db.armorStrict; wipe(bagCache); RefreshBadges() end)
      local scaleSub = root:CreateButton("Window scale")
      for _, s in ipairs({ 0.9, 1.0, 1.1, 1.25 }) do
        scaleSub:CreateRadio(math.floor(s * 100) .. "%", function() return (db.scale or 1) == s end,
          function() applyScale(s) end)
      end
      root:CreateButton("Reset position", resetPos)
      root:CreateButton("Hide minimap button", hideMinimap)
    end)
    if ok then return end
  end

  -- 2) legacy EasyMenu fallback
  if type(EasyMenu) == "function" then
    settingsMenuFrame = settingsMenuFrame or CreateFrame("Frame", "StatCoachSettingsMenu", UIParent, "UIDropDownMenuTemplate")
    local menu = {
      { text = "StatCoach", isTitle = true, notCheckable = true },
      { text = "Tooltip verdict line", keepShownOnClick = true, checked = function() return db.tooltip end,
        func = function() db.tooltip = not db.tooltip end },
      { text = "Gem hint on empty sockets", keepShownOnClick = true,
        checked = function() return db.gemHints ~= false end,
        func = function() db.gemHints = (db.gemHints == false) or nil end },
      { text = "Upgrade badges", keepShownOnClick = true, checked = function() return db.bagBadge end,
        func = function() db.bagBadge = not db.bagBadge; RefreshBadges(); wipe(bagCache) end },
      { text = "Show badges in", notCheckable = true, hasArrow = true, menuList = (function()
          local t = {}
          for _, sf in ipairs(BADGE_SURFACES) do
            t[#t + 1] = { text = sf[2], keepShownOnClick = true,
              checked = function() return db.badges[sf[1]] ~= false end,
              func = function() toggleSurface(sf[1]) end }
          end
          return t
        end)() },
      { text = "Flag upgrades above", notCheckable = true, hasArrow = true, menuList = (function()
          local t = {}
          for _, f in ipairs(UPGRADE_FLOORS) do
            t[#t + 1] = { text = f[2], checked = function() return (db.minUpgrade or 1) == f[1] end,
              func = function() db.minUpgrade = f[1]; wipe(bagCache); RefreshBadges() end }
          end
          return t
        end)() },
      { text = "Pulse the badge", keepShownOnClick = true, checked = function() return not db.noPulse end,
        func = function() db.noPulse = not db.noPulse or nil; RefreshBadges() end },
      { text = "Badge size", notCheckable = true, hasArrow = true, menuList = (function()
          local t = {}
          for _, n in ipairs(BADGE_SIZES) do
            t[#t + 1] = { text = tostring(n), checked = function() return (db.badgeSize or 18) == n end,
              func = function() db.badgeSize = n; RefreshBadges() end }
          end
          return t
        end)() },
      { text = "Tooltip icon size", notCheckable = true, hasArrow = true, menuList = (function()
          local t = {}
          for _, n in ipairs(ICON_SIZES) do
            t[#t + 1] = { text = tostring(n), checked = function() return (db.iconSize or 14) == n end,
              func = function() db.iconSize = n end }
          end
          return t
        end)() },
      { text = "Hide off-type armour entirely", keepShownOnClick = true,
        checked = function() return db.armorStrict end,
        func = function() db.armorStrict = not db.armorStrict; wipe(bagCache); RefreshBadges() end },
      { text = "Window scale", notCheckable = true, hasArrow = true, menuList = {
        { text = "90%",  checked = function() return (db.scale or 1) == 0.9 end,  func = function() applyScale(0.9) end },
        { text = "100%", checked = function() return (db.scale or 1) == 1.0 end,  func = function() applyScale(1.0) end },
        { text = "110%", checked = function() return (db.scale or 1) == 1.1 end,  func = function() applyScale(1.1) end },
        { text = "125%", checked = function() return (db.scale or 1) == 1.25 end, func = function() applyScale(1.25) end },
      }},
      { text = "Reset position", notCheckable = true, func = resetPos },
      { text = "Hide minimap button", notCheckable = true, func = hideMinimap },
      { text = "Close", notCheckable = true, func = function() end },
    }
    local ok = pcall(EasyMenu, menu, settingsMenuFrame, "cursor", 0, 0, "MENU")
    if ok then return end
  end

  print("|cffffd100StatCoach|r: couldn't open settings (MenuUtil=" .. tostring(MenuUtil ~= nil)
    .. ", EasyMenu=" .. tostring(type(EasyMenu)) .. "). Send me this line.")
end

-- LibDBIcon, not a hand-rolled button. Two independent signals asked for it:
-- a CurseForge comment on TrinketCoach ("only dragable in a circle") and
-- Leatrix Plus, which puts a "please ask the author to use LibDBIcon" tooltip
-- on every button it does not recognise. The library gives free placement
-- around any minimap shape, a saved position, hide/show, and it is what
-- Leatrix / HidingBar / ElvUI / SexyMap all know how to collect. On retail it
-- also registers us in the Addon Compartment, so hiding the button never
-- loses the way in; on classic /stc is the way back.
local LDB    = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
local MM_NAME = "StatCoach"

local mmObject = LDB and LDB:NewDataObject(MM_NAME, {
  type = "launcher",
  icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
  OnClick = function(self, button)
    if button == "RightButton" then ShowSettingsMenu(self)
    elseif UI.frame and UI.frame:IsShown() then UI.hideAll()
    elseif UI.frame then UI.frame:Show(); StatCoachDB.shown = true; Refresh() end
  end,
  -- Left-click is guessable on a button whose whole job is clicking; RIGHT-click
  -- is not, and it is where every setting lives - including which windows the
  -- upgrade badges may draw in. A menu nobody can find is a menu nobody has.
  -- Plain AddLine, not AddDoubleLine: a double line pins its halves to opposite
  -- edges and the tooltip is as wide as its longest line, so two short words
  -- ended up with a canyon between them. Stacked and left-aligned reads as one
  -- list, with the clickable part gold and the explanation grey.
  OnTooltipShow = function(tt)
    tt:AddLine("StatCoach")
    tt:AddLine("|cffd9b85aRight-click|r for settings and badge options", 0.6, 0.6, 0.6)
    tt:AddLine("|cffd9b85a/stc minimap|r hides this button", 0.5, 0.5, 0.5)
  end,
})

-- Global on purpose: the settings menu (built earlier in the file) calls it.
function StatCoach_ToggleMinimap()
  local db = StatCoachDB
  db.minimap.hide = not db.minimap.hide
  if DBIcon and DBIcon:IsRegistered(MM_NAME) then
    if db.minimap.hide then DBIcon:Hide(MM_NAME) else DBIcon:Show(MM_NAME) end
  end
  print("|cffffd100StatCoach|r: minimap button " .. (db.minimap.hide
    and "hidden - /stc opens the window, /stc minimap brings the button back" or "shown") .. ".")
end

-- Called once the saved variables exist. StatCoachDB.minimap is the table
-- LibDBIcon owns (hide, minimapPos, lock); the old minimapHidden /
-- minimapX/Y / minimapAngle fields from the hand-rolled button are migrated
-- and dropped.
local function CreateMinimapButton()
  local db = StatCoachDB
  db.minimap = db.minimap or {}
  if db.minimapHidden ~= nil then
    db.minimap.hide = db.minimapHidden and true or nil
    db.minimapHidden = nil
  end
  db.minimapX, db.minimapY, db.minimapAngle = nil, nil, nil
  if DBIcon and mmObject and not DBIcon:IsRegistered(MM_NAME) then
    DBIcon:Register(MM_NAME, mmObject, db.minimap)
    if DBIcon.AddButtonToCompartment then DBIcon:AddButtonToCompartment(MM_NAME) end
  end
end
------------------------------------------------------------------------
-- Glow badge: the shared visual for "this item is an upgrade", drawn on bag
-- items (via Baganator) and quest reward buttons alike. A small frame, not a
-- bare FontString: a FontString can't hold a glow behind itself. The frame
-- carries a star-burst glow (ADD blend, same texture action buttons use for
-- procs) with the number/skull on top in the damage font.
------------------------------------------------------------------------
local BADGE_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"

-- Global on purpose: the settings menu is built earlier in the file than the
-- badge code, so it cannot see a local declared down here.
function StatCoachPulseOn()
  return not (StatCoachDB and StatCoachDB.noPulse)
end

-- surface = which switch in "Show badges in" owns this badge. Registering here
-- rather than at each call site is deliberate: the bag and quest paths build
-- their badges directly instead of going through BadgeButton, so a register
-- kept in BadgeButton missed exactly the surface people turn off first.
local function CreateGlowBadge(parent, surface)
  local holder = CreateFrame("Frame", nil, parent)
  holder.scSurface = surface
  badgeHolders[#badgeHolders + 1] = holder
  holder:SetSize(18, 18)
  local glow = holder:CreateTexture(nil, "ARTWORK")
  glow:SetTexture("Interface\\Cooldown\\star4")
  glow:SetBlendMode("ADD")
  glow:SetPoint("CENTER")
  local text = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  text:SetPoint("CENTER")
  -- Pulse (slow breathe in/out, like an actionbar proc). Every tier plays it;
  -- the skull still stands out via colour and the icon itself.
  local ag = glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local alpha = ag:CreateAnimation("Alpha")
  alpha:SetFromAlpha(0.35); alpha:SetToAlpha(0.95); alpha:SetDuration(0.8)
  local scale = ag:CreateAnimation("Scale")
  scale:SetScaleFrom(0.85, 0.85); scale:SetScaleTo(1.12, 1.12); scale:SetDuration(0.8)
  holder.glow, holder.text, holder.pulse = glow, text, ag
  -- Hiding a frame STOPS its animations, and both Baganator and the quest UI
  -- hide/show these constantly - without this the pulse dies after the first
  -- refresh and the badge goes static. Restart it every time we come back.
  holder:SetScript("OnShow", function(self)
    if self.scOn and StatCoachPulseOn() and not self.pulse:IsPlaying() then self.pulse:Play() end
  end)
  return holder
end

-- Same tiers and colours as the tooltip verdict: green + (solid), gold + (10%+),
-- purple skull (25%+ / empty slot). The skull texture is height 0 = follows the
-- font size, so everything scales together via /stc badge N.
ApplyGlowBadge = function(holder, pct, tier)
  local size = (StatCoachDB and StatCoachDB.badgeSize) or 18
  if holder.scSize ~= size then
    -- DAMAGE_TEXT_FONT (skurri) is the fat font floating combat numbers use -
    -- it reads "bold" at any size; THICKOUTLINE keeps it crisp on busy icons.
    holder.text:SetFont(DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT, size, "THICKOUTLINE")
    holder:SetSize(size, size)
    holder.glow:SetSize(size * 2.1, size * 2.1)
    holder.scSize = size
  end
  local r, g, b
  -- tier comes from GearCoach at vendors: the skull is "this IS the goal" and
  -- the gold + is "the road there", regardless of how big the raw upgrade is.
  -- "green" caps an ordinary upgrade at the green + so the vendor never shows
  -- a second skull with a different meaning. No tier = the usual %-ladder.
  if tier == "bis" then holder.text:SetText(BADGE_SKULL); r, g, b = 0.75, 0.35, 1
  elseif tier == "budget" then holder.text:SetText("+"); r, g, b = 1, 0.82, 0
  elseif tier == "green" then holder.text:SetText("+"); r, g, b = 0.3, 1, 0.3
  elseif pct >= 25 then holder.text:SetText(BADGE_SKULL); r, g, b = 0.75, 0.35, 1
  elseif pct >= 10 then holder.text:SetText("+"); r, g, b = 1, 0.82, 0
  else holder.text:SetText("+"); r, g, b = 0.3, 1, 0.3 end
  holder.text:SetTextColor(r, g, b)
  holder.glow:SetVertexColor(r, g, b, 0.9)
  holder.scOn = true     -- OnShow reads this to revive the pulse after a Hide
  -- Some people cannot stand animated UI, and a badge that sits still is still
  -- a badge. Stopping the group leaves the glow wherever the animation was, so
  -- put the alpha back to something deliberate.
  if StatCoachPulseOn() then
    if not holder.pulse:IsPlaying() then holder.pulse:Play() end
  else
    if holder.pulse:IsPlaying() then holder.pulse:Stop() end
    holder.glow:SetAlpha(0.75)
  end
end

------------------------------------------------------------------------
-- Baganator: the glow badge as a corner widget on bag items
-- (uses the same public API as the itemtier reference addon)
------------------------------------------------------------------------
local function SetupBaganatorBadge()
  if UI.baganatorDone then return end
  local baganator = rawget(_G, "Baganator")
  if not baganator then UI.bagStatus = "Baganator not loaded"; return end
  if not (baganator.API and baganator.API.RegisterCornerWidget) then
    UI.bagStatus = "this Baganator version has NO RegisterCornerWidget API"
    return
  end

  -- Baganator calls this for every item it draws, inside its own layout pass:
  -- an error thrown in here takes the whole bag window down with it. Our badge
  -- is never worth someone's bags, so the real work runs inside a pcall and a
  -- failure just means "no badge on this item".
  local function OnUpdateInner(holder, details)
    local link = details and details.itemLink
    if not link then return nil end          -- item data not ready; Baganator retries
    local pct = BadgeSurfaceOn("bags") and bagUpgradePct(link) or nil
    if pct then
      holder.scLink = link
      ApplyGlowBadge(holder, pct)
      -- Break out of Baganator's corner-slot layout and anchor exactly like the
      -- default-bag overlay: centered on the icon's top-left corner, above count
      -- text. Baganator re-anchors on every layout pass, so re-assert each update.
      local btn = holder:GetParent()
      if btn then
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", btn, "TOPLEFT", 5, -5)
        holder:SetFrameLevel(btn:GetFrameLevel() + 5)
      end
      return true
    end
    holder.scOn = false
    holder.pulse:Stop()
    return false
  end

  local function OnUpdate(holder, details)
    local ok, res = pcall(OnUpdateInner, holder, details)
    if ok then return res end
    if not UI.bagErrShown then
      UI.bagErrShown = true   -- once per session; the bags keep working
      print("|cffffd100StatCoach|r: badge skipped in Baganator (" .. tostring(res) .. ")")
    end
    return false
  end

  local ok, err = pcall(baganator.API.RegisterCornerWidget,
    "StatCoach Upgrade", "statcoach_upgrade",
    OnUpdate, function(parent) return CreateGlowBadge(parent, "bags") end,
    { corner = "top_left", priority = 3 })
  if ok then
    UI.baganatorDone = true
    UI.bagStatus = "registered OK - if no '+', enable 'StatCoach Upgrade' in Baganator settings -> icon corners"
  else
    UI.bagStatus = "register FAILED: " .. tostring(err)
  end
end

------------------------------------------------------------------------
-- Quest reward badges: the glow badge directly on the reward buttons, visible
-- at the moment of choice without hovering (the same surface Pawn picked).
-- Works without Baganator - it anchors on Blizzard's own quest UI.
------------------------------------------------------------------------
local function UpdateQuestBadges()
  local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
  if not rf or not rf.RewardButtons then return end
  for _, btn in pairs(rf.RewardButtons) do
    local holder = btn.scBadge
    local pct
    if btn:IsShown() and btn.type and btn.GetID then
      -- questLog set = viewing from the quest log; nil = talking to the NPC.
      -- Non-item rewards (currency/spells) yield no equip location in evalItem
      -- and fall through to "no badge" naturally.
      local link
      if QuestInfoFrame.questLog then
        link = GetQuestLogItemLink(btn.type, btn:GetID())
      else
        link = GetQuestItemLink(btn.type, btn:GetID())
      end
      pct = (link and BadgeSurfaceOn("quest")) and bagUpgradePct(link) or nil
    end
    if pct then
      if not holder then
        holder = CreateGlowBadge(btn, "quest")
        holder:SetPoint("CENTER", btn.Icon or btn, "TOPLEFT", 5, -5)
        btn.scBadge = holder
      end
      holder.scLink = link
      ApplyGlowBadge(holder, pct)
      holder:Show()
    elseif holder then
      HideBadge(holder)
    end
  end
end

if type(QuestInfo_Display) == "function" then
  hooksecurefunc("QuestInfo_Display", function()
    UpdateQuestBadges()
    -- Item data often isn't cached the instant the panel opens; one delayed
    -- pass catches the stragglers without polling.
    C_Timer.After(0.3, UpdateQuestBadges)
  end)
end

------------------------------------------------------------------------
-- Badges on the other places items show up. Every surface is the same three
-- steps - find the button, ask for its link, put the shared badge on it - so
-- they all go through one helper. Each hook is guarded on the global existing:
-- a frame Blizzard renames on some client simply gets no badges rather than
-- throwing, which is how the bag hook below already behaves.
------------------------------------------------------------------------
-- pos = { point, relativePoint, x, y }; the default sits on an item icon's
-- top-left corner. Rows that are pure TEXT (the trade skill list) pass their
-- own so the badge lands beside the name instead of on top of it.
local function BadgeButton(btn, link, anchor, pos, surface)
  if not btn then return end
  local pct = (link and BadgeSurfaceOn(surface)) and bagUpgradePct(link) or nil
  -- At a vendor, three questions get three icons - when GearCoach is loaded to
  -- answer the first two: SKULL "this is your BiS", GOLD + "the road there"
  -- (pre-raid picks and last season's honor pieces), GREEN + "an upgrade right
  -- now" for everything off the lists. BiS/road show even when the piece is
  -- not an upgrade - the goal does not stop being the goal because you own it.
  -- Without GearCoach, vendor badges keep the ordinary %-ladder.
  local tier
  if link and surface == "vendor" and type(_G.GearCoach_BisTier) == "function" then
    local id = tonumber(link:match("item:(%d+)"))
    tier = id and _G.GearCoach_BisTier(id) or nil
    if not tier and pct then
      -- The green + covers armor and jewelry only. A weapon is a SPEC decision,
      -- not a stat delta - a dagger can out-score a Fury warrior's sword and
      -- still be wrong - and any weapon actually worth buying is on the lists
      -- and just got its skull or gold + above. Weapons off the lists stay bare.
      local classID = select(6, GetItemInfoInstant(link))
      local WEAPON = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
      if classID ~= WEAPON then tier = "green" end
      -- And when the piece you WEAR in that slot is on your GearCoach list, the
      -- list already made the call - PvP gear spends half its budget on stamina
      -- and resilience, which a dps stat-score prices at nothing, so any plain
      -- stat-stick "beats" it on paper. The curated choice outranks the math:
      -- a dressed slot holds its tongue at the vendor.
      if tier == "green" then
        local equipLoc = select(4, GetItemInfoInstant(link))
        local slots = equipLoc and SLOTMAP[equipLoc]
        for _, slot in ipairs(slots or {}) do
          local eq = GetInventoryItemLink("player", slot)
          local eqId = eq and tonumber(eq:match("item:(%d+)"))
          if eqId and _G.GearCoach_BisTier(eqId, true) then tier = nil; break end
        end
      end
    end
    if not tier then pct = nil end   -- vendor shows the three curated icons, nothing else
  end
  local holder = btn.scBadge
  if pct or tier then
    if not holder then
      holder = CreateGlowBadge(btn, surface)
      holder:SetPoint(pos and pos[1] or "CENTER", anchor or btn,
                      pos and pos[2] or "TOPLEFT",
                      pos and pos[3] or 5, pos and pos[4] or -5)
      btn.scBadge = holder
    end
    holder.scLink = link
    ApplyGlowBadge(holder, pct or 0, tier)
    holder:Show()
  elseif holder then
    HideBadge(holder)
  end
end

-- VENDOR. The one that earns its keep day to day: "is this worth buying".
if type(MerchantFrame_UpdateMerchantInfo) == "function" then
  hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    for i = 1, perPage do
      local btn = _G["MerchantItem" .. i .. "ItemButton"]
      local index = ((MerchantFrame and MerchantFrame.page or 1) - 1) * perPage + i
      BadgeButton(btn, btn and btn:IsShown() and GetMerchantItemLink(index) or nil, nil, nil, "vendor")
    end
  end)
end

-- LOOT. Deciding what to roll on, before it is in a bag to compare against.
if type(LootFrame_Update) == "function" then
  hooksecurefunc("LootFrame_Update", function()
    for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do
      local btn = _G["LootButton" .. i]
      local slot = btn and btn:IsShown() and btn:GetID() or nil
      BadgeButton(btn, slot and GetLootSlotLink(slot) or nil, nil, nil, "loot")
    end
  end)
end

-- BANK. Where the "why am I still keeping this" pile lives. Bag-slot buttons
-- inside the bank are ordinary container buttons and the bag hook below already
-- covers them; this is the bank's own 28 slots.
if type(BankFrameItemButton_Update) == "function" then
  local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  hooksecurefunc("BankFrameItemButton_Update", function(btn)
    if not btn or btn.isBag or not btn.GetID or not getLink then return end
    BadgeButton(btn, getLink(BANK_CONTAINER or -1, btn:GetID()), nil, nil, "bank")
  end)
end

-- MAIL. The open letter, not the inbox list: attachments are where the choice
-- is, and a letter can carry more than the one item the list shows.
if type(OpenMail_Update) == "function" then
  hooksecurefunc("OpenMail_Update", function()
    local mailID = InboxFrame and InboxFrame.openMailID
    for i = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
      local btn = _G["OpenMailAttachmentButton" .. i]
      local link = (mailID and btn and btn:IsShown()) and GetInboxItemLink(mailID, i) or nil
      BadgeButton(btn, link, nil, nil, "mail")
    end
  end)
end

-- AUCTION HOUSE, browse results. The list is paged and scrolled, so the row
-- index is the scroll offset plus the row - not the row on its own.
if type(AuctionFrameBrowse_Update) == "function" then
  hooksecurefunc("AuctionFrameBrowse_Update", function()
    local offset = (FauxScrollFrame_GetOffset and BrowseScrollFrame)
      and FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    for i = 1, (NUM_BROWSE_TO_DISPLAY or 8) do
      local btn = _G["BrowseButton" .. i]
      local link = (btn and btn:IsShown()) and GetAuctionItemLink("list", offset + i) or nil
      BadgeButton(btn, link, nil, nil, "auction")
    end
  end)
end

-- TRADE, the other player's side. What you are being handed is the half worth
-- judging; your own side you already decided on.
if type(TradeFrame_Update) == "function" then
  hooksecurefunc("TradeFrame_Update", function()
    for i = 1, (MAX_TRADE_ITEMS or 7) do
      local btn = _G["TradeRecipientItem" .. i .. "ItemButton"]
      local link = (btn and btn:IsShown()) and GetTradeTargetItemLink(i) or nil
      BadgeButton(btn, link, nil, nil, "trade")
    end
  end)
end

-- LOOT ROLLS. The shortest decision window in the game - need or greed, on a
-- timer, usually with three other people waiting - so the badge is worth more
-- here than anywhere else. The tooltip already carried a verdict; this puts it
-- on the icon so it is readable without hovering at all.
if type(GroupLootFrame_OpenNewFrame) == "function" then
  hooksecurefunc("GroupLootFrame_OpenNewFrame", function()
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
      local f = _G["GroupLootFrame" .. i]
      local link = (f and f:IsShown() and f.rollID) and GetLootRollItemLink(f.rollID) or nil
      BadgeButton(f, link, f and (f.IconFrame or _G["GroupLootFrame" .. i .. "IconFrame"]), nil, "roll")
    end
  end)
end

-- CRAFTING. Standing at the anvil with the mats in your bags is a decision,
-- and TBC is full of crafted gear worth wearing. The list rows are plain TEXT,
-- not item icons, so the badge sits at the right-hand edge rather than covering
-- the recipe name. Headers and enchant recipes produce no equippable link and
-- fall through to no badge on their own.
if type(TradeSkillFrame_Update) == "function" then
  hooksecurefunc("TradeSkillFrame_Update", function()
    local offset = (FauxScrollFrame_GetOffset and TradeSkillListScrollFrame)
      and FauxScrollFrame_GetOffset(TradeSkillListScrollFrame) or 0
    for i = 1, (TRADE_SKILLS_DISPLAYED or 8) do
      local btn = _G["TradeSkillSkill" .. i]
      local link = (btn and btn:IsShown()) and GetTradeSkillItemLink(offset + i) or nil
      BadgeButton(btn, link, btn, { "RIGHT", "RIGHT", -6, 0 }, "craft")
    end
  end)
end

-- ATLASLOOT. A third-party list, so this is the one hook that can break when
-- someone else ships an update - it is guarded accordingly and simply does
-- nothing if their button API moves. Their buttons carry the item on
-- .ItemID, and Button.Proto is a public table, so no internals are poked.
local atlasHooked = false
local function SetupAtlasLootBadges()
  if atlasHooked then return true end
  local B = rawget(_G, "AtlasLoot")
  B = B and B.Button
  if not (B and type(B.AddType) == "function") then return false end
  -- AddType hands back the EXISTING type table when it is already registered,
  -- so this reads their item type rather than declaring anything.
  local ok, Item = pcall(B.AddType, B, "Item", "i")
  if not (ok and Item and type(Item.Refresh) == "function") then return false end

  -- Refresh, not SetContentTable. SetContentTable only files the raw row away
  -- in __atlaslootinfo - the ItemID does not exist yet when it returns, which
  -- is why the first attempt at this badged nothing at all. Refresh runs after
  -- the item is resolved, and AtlasLoot calls it again when data arrives for a
  -- row that was still uncached, so late items fix themselves with no retry.
  hooksecurefunc(Item, "Refresh", function(btn)
    if not (btn and btn.ItemID) then return end
    BadgeButton(btn, select(2, GetItemInfo(btn.ItemID)), btn.icon or btn, nil, "atlas")
  end)
  if type(Item.OnClear) == "function" then
    hooksecurefunc(Item, "OnClear", function(btn)
      if btn and btn.scBadge then HideBadge(btn.scBadge) end
    end)
  end
  atlasHooked = true
  return true
end

------------------------------------------------------------------------
-- Default Blizzard bags: the same glow badge with NO bag addon required.
-- We hook Blizzard's own container buttons, which always exist. Two paths,
-- guarded by capability (not by flavor) so whichever this client has is used:
--   classic-style: global ContainerFrame_Update(frame)
--   modern-style:  frame:UpdateItems() on each container frame instance
-- If Baganator (or another bag addon) replaces the default bags, these frames
-- are simply hidden and the hooks draw nothing - no conflict, no cost.
------------------------------------------------------------------------
local function BadgeContainerButton(btn, link)
  local pct = (link and BadgeSurfaceOn("bags")) and bagUpgradePct(link) or nil
  local holder = btn.scBadge
  if pct then
    if not holder then
      holder = CreateGlowBadge(btn, "bags")
      holder:SetFrameLevel(btn:GetFrameLevel() + 5)  -- above count text / cooldowns
      holder:SetPoint("CENTER", btn, "TOPLEFT", 5, -5)
      btn.scBadge = holder
    end
    holder.scLink = link
    ApplyGlowBadge(holder, pct)
    holder:Show()
  elseif holder then
    HideBadge(holder)
  end
end

local CGetContainerLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

if type(ContainerFrame_Update) == "function" then
  hooksecurefunc("ContainerFrame_Update", function(frame)
    local bag = frame:GetID()
    local fname = frame:GetName()
    for i = 1, (frame.size or 0) do
      local btn = _G[fname .. "Item" .. i]
      if btn then
        BadgeContainerButton(btn, CGetContainerLink(bag, btn:GetID()))
      end
    end
  end)
end

do
  -- Modern clients: UpdateItems lives as a COPY on each frame instance (mixins
  -- are copied at creation), so hooking the mixin table after the fact does
  -- nothing - each existing frame must be hooked individually.
  local function HookModernBag(frame)
    if not (frame and type(frame.UpdateItems) == "function" and frame.EnumerateValidItems) then return end
    hooksecurefunc(frame, "UpdateItems", function(self)
      for _, btn in self:EnumerateValidItems() do
        if btn and btn.GetBagID then
          BadgeContainerButton(btn, CGetContainerLink(btn:GetBagID(), btn:GetID()))
        end
      end
    end)
  end
  for i = 1, 13 do HookModernBag(_G["ContainerFrame" .. i]) end
  HookModernBag(rawget(_G, "ContainerFrameCombinedBags"))
end

------------------------------------------------------------------------
-- Character-pane cap tooltips (classic only): hovering a combat stat row on
-- the paperdoll appends the live cap bars - the same data as the window's
-- CAPS section - to Blizzard's own stat tooltip. Only rows whose tooltip
-- mentions a cap-related stat get the block, so Strength/Spirit stay clean.
-- Retail hooks the same way but shows the DR ladder instead (block below).
------------------------------------------------------------------------
-- Shared by both flavors' character-pane tooltips.
-- REAL status bars inside the tooltip, not text pretending to be one. Each cap
-- reserves a blank tooltip line, and a pooled StatusBar (same look as the
-- window's cap bars) is anchored onto that line's FontString - so the bars ride
-- along wherever the tooltip goes and vanish with it. Fill = progress, colour =
-- status (red / gold / green), text is secondary.
local tipBars = {}
local function GetTipBar(i)
  local b = tipBars[i]
  if b then return b end
  b = CreateFrame("StatusBar", nil, GameTooltip, "BackdropTemplate")
  b:SetHeight(13)
  b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b:SetMinMaxValues(0, 1)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0.05, 0.05, 0.06, 0.9)
  b:SetBackdropBorderColor(0, 0, 0, 1)
  -- TWO texts on the bar (label left, numbers right) - the third, centred one
  -- is what collided on narrow tooltips, so the need-rating lives only in the
  -- StatCoach window now. Compact: one line per cap.
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", 4, 0)
  b.value = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.value:SetPoint("RIGHT", -4, 0)
  tipBars[i] = b
  return b
end
local function HideTipBars()
  for _, b in ipairs(tipBars) do b:Hide() end
end


if not RETAIL and not MISTS and not ns.ERA then
  -- Every row in the Melee/Ranged/Spell/Defenses panels gets the cap block;
  -- only the Base Stats rows stay clean. Blacklist beats whitelist here: the
  -- panels' titles vary ("Bonus Damage", "Mana Regen", "Resilience", ...) and a
  -- keyword whitelist kept missing rows. Read the SHOWN tooltip's title - the
  -- rows build their tooltips three different ways, the title is always there.
  -- These read Blizzard's OWN stat-row tooltips, so the words to look for have
  -- to come from the client, not from English. Every list below is the game's
  -- wording PLUS the English one it replaces: these are all widening `find`
  -- checks, so keeping both can only ever match more, never less, and an
  -- English client behaves exactly as it did before.
  local function words(englishList, ...)
    local seen, out = {}, {}
    for i = 1, select("#", ...) do
      local v = rawget(_G, (select(i, ...)))
      if type(v) == "string" and v ~= "" then
        v = v:lower()
        if not seen[v] then seen[v] = true; out[#out + 1] = v end
      end
    end
    for _, v in ipairs(englishList) do
      if not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    return out
  end

  local BASE_STATS = words({ "strength", "agility", "stamina", "intellect", "spirit" },
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT")
  local W_HIT     = words({ "hit" }, "STAT_HIT_CHANCE")
  local W_EXP     = words({ "expertise", "weapon skill" }, "STAT_EXPERTISE")
  local W_DEFENSE = words({ "defense", "armor" }, "DEFENSE", "STAT_CATEGORY_DEFENSE", "STAT_ARMOR")
  local W_AVOID   = words({ "dodge", "parry", "block", "resilience" },
    "STAT_DODGE", "STAT_PARRY", "STAT_BLOCK", "STAT_RESILIENCE")

  local function anyWord(low, list)
    for _, w in ipairs(list) do
      if low:find(w, 1, true) then return true end
    end
    return false
  end
  -- Titles carry EMBEDDED COLOUR CODES ("|cffffffffAgility 301...") - strip them
  -- before matching, or anchored patterns ("starts with agility") never fire.
  local function TooltipTitle()
    local fs = _G["GameTooltipTextLeft1"]
    local t = fs and fs:GetText()
    if type(t) ~= "string" then return "" end
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):lower())
  end
  local function TooltipWantsCaps()
    local low = TooltipTitle()
    if low == "" then return false end
    for _, w in ipairs(BASE_STATS) do
      if low:sub(1, #w) == w then return false end   -- plain compare: a stat name is not a pattern
    end
    return true
  end

  -- Which cap kinds does the hovered stat row ask about? Hovering a cap stat
  -- shows just ITS bar(s); hovering anything without a cap (Crit, Damage,
  -- Power, ...) shows the full overview. nil = no specific match = show all.
  local function WantedKinds()
    local low = TooltipTitle()
    if anyWord(low, W_HIT) then return { hit = true } end
    if anyWord(low, W_EXP) then return { expertise = true } end
    if anyWord(low, W_DEFENSE) then return { defense = true, avoid = true } end
    if anyWord(low, W_AVOID) then return { avoid = true, defense = true } end
    return nil
  end

  local function AddCapLines(tt)
    HideTipBars()
    local role = curCtx and curCtx.role
    if not role then return false end
    local bars = CapBarsFor(role, ReadStats())
    if #bars == 0 then
      -- Healers have no hard caps - say so instead of silence, so an empty
      -- block never reads as "the addon is broken".
      tt:AddLine(" ")
      tt:AddLine("StatCoach: no hard caps for this spec", 0.6, 0.6, 0.6)
      return true
    end
    -- Filter to the hovered stat's caps. A cap-stat with NO matching bar for
    -- this spec (Armor on a DPS, Expertise on a hunter) shows nothing at all -
    -- an unrelated overview there is noise, not help. Stats with no cap-kind
    -- (Crit, Damage, Power...) keep the full overview.
    local kinds = WantedKinds()
    if kinds then
      local filtered = {}
      for _, b in ipairs(bars) do
        if kinds[b.kind] then filtered[#filtered+1] = b end
      end
      if #filtered == 0 then return false end
      bars = filtered
    end
    tt:AddLine(" ")
    tt:AddLine("StatCoach - caps (vs boss +3)", 1, 0.82, 0)
    for i, b in ipairs(bars) do
      tt:AddLine(" ")   -- reserve the vertical space the bar sits on
      local lineFS = _G["GameTooltipTextLeft" .. tt:NumLines()]
      local bar = GetTipBar(i)
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", lineFS, "TOPLEFT", 0, 1)
      bar:SetPoint("RIGHT", tt, "RIGHT", -10, 0)
      bar:SetValue(b.frac)
      if b.done then bar:SetStatusBarColor(0.2, 0.75, 0.25)
      elseif b.frac >= 0.5 then bar:SetStatusBarColor(0.85, 0.65, 0.1)
      else bar:SetStatusBarColor(0.8, 0.25, 0.2) end
      bar.label:SetText(b.label)
      if b.done then
        bar.value:SetText("|cff40ff40capped|r")
      else
        local cur = (b.unit == "%") and (fmt(b.cur) .. "%") or tostring(math.floor(b.cur + 0.5))
        local tgt = (b.unit == "%") and (b.target .. b.unit) or tostring(b.target)
        bar.value:SetText(cur .. " / " .. tgt)
      end
      bar:Show()
    end
    return true
  end

  -- Hook the TOOLTIP, not the stat rows: the rows build their tooltips three
  -- different ways (static .tooltip field, OnEnter-built, and whatever the Hit
  -- row does), and hooking each row missed some. Every path ends in GameTooltip
  -- showing - so decide there: owner inside the character frame + cap-related
  -- title = append the block. scCapsAdded guards the re-Show() recursion.
  local function OwnerIsCharacterPane(owner)
    local cf = rawget(_G, "CharacterFrame")
    local node = owner
    for _ = 1, 4 do
      if not node then return false end
      if node == cf then return true end
      node = node:GetParent()
    end
    return false
  end

  -- Append runs deferred ONE frame: some rows (Hit Rating) Show() first and add
  -- their body text after - waiting a frame means we always append LAST. All
  -- gates are evaluated inside the deferred call, because at schedule time the
  -- new row's owner/title may not be set yet.
  local function ScheduleCapAppend(tt)
    if tt.scCapsPending then return end
    tt.scCapsPending = true
    C_Timer.After(0, function()
      tt.scCapsPending = nil
      if tt.scCapsAdded or not tt:IsShown() then return end
      -- Paperdoll tab only: keeps Reputation/Skills-tab tooltips (also children
      -- of CharacterFrame) from getting a caps block they have no business with.
      local pd = rawget(_G, "PaperDollFrame")
      if not (pd and pd:IsVisible()) then return end
      local owner = tt:GetOwner()
      if not owner or not OwnerIsCharacterPane(owner) then return end
      -- Owner must be an actual STAT ROW (PlayerStatFrameLeft1..6 / Right1..6).
      -- Everything in CharacterFrame owns tooltips - the Reputation/Skills/PvP
      -- tab buttons included - and they all passed the looser gates.
      local oname = owner:GetName()
      if type(oname) ~= "string" or not oname:find("^PlayerStatFrame") then return end
      local _, itemLink = tt:GetItem()
      if itemLink then return end        -- equipped-item tooltips: never touch
      if TooltipWantsCaps() and AddCapLines(tt) then
        tt.scCapsAdded = true
        tt:Show()
      end
    end)
  end
  GameTooltip:HookScript("OnShow", ScheduleCapAppend)
  -- CRUCIAL: moving between stat rows REUSES the shown tooltip (no Hide/Show) -
  -- OnTooltipCleared is the only signal a new row took over. Without this, the
  -- first row's bars stay glued in place for every later row.
  GameTooltip:HookScript("OnTooltipCleared", function(tt)
    tt.scCapsAdded = nil
    HideTipBars()
    ScheduleCapAppend(tt)
  end)
  GameTooltip:HookScript("OnHide", function(tt)
    tt.scCapsAdded = nil
    HideTipBars()
  end)
  UI.capRowsHooked = "GameTooltip OnShow (covers all stat rows)"
end

------------------------------------------------------------------------
-- Character-pane DR tooltips (retail only): hovering Crit / Haste / Mastery /
-- Versatility on the paperdoll appends that stat's diminishing-returns bar -
-- the same data as the window's YOUR SECONDARIES section - to Blizzard's own
-- stat tooltip. Retail's stat rows are pooled frames (no PlayerStatFrame*
-- names) but each carries `.stat` = "HASTE" / "CRITCHANCE" / "MASTERY" /
-- "VERSATILITY", which is a cleaner gate than a name ever was.
------------------------------------------------------------------------
if RETAIL and not FOREVER then   -- the DR ladder is a level-90 retail rule
  local STAT_KEY = { CRITCHANCE = "Crit", HASTE = "Haste", MASTERY = "Mastery", VERSATILITY = "Versatility" }

  local function AddDRLines(tt, name)
    HideTipBars()
    local r = ReadRatings()[name]
    local bracket, over, width, dr = DRState(name, r)
    if not dr then return false end
    tt:AddLine(" ")
    tt:AddLine("StatCoach - diminishing returns", 1, 0.82, 0)
    tt:AddLine(" ")   -- reserve the line the bar sits on
    local lineFS = _G["GameTooltipTextLeft" .. tt:NumLines()]
    local bar = GetTipBar(1)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", lineFS, "TOPLEFT", 0, 1)
    bar:SetPoint("RIGHT", tt, "RIGHT", -10, 0)
    bar.label:SetText(name)
    if r == nil then
      bar:SetValue(0)
      bar:SetStatusBarColor(0.3, 0.55, 0.9)
      bar.value:SetText("|cff888888(combat)|r")
    else
      bar:SetValue(math.min(1, r / dr))
      if bracket == 0 then bar:SetStatusBarColor(0.3, 0.55, 0.9)
      elseif bracket == 1 then bar:SetStatusBarColor(0.85, 0.65, 0.1)
      else bar:SetStatusBarColor(0.8, 0.25, 0.2) end
      if bracket == 0 then
        bar.value:SetText(string.format("%d / %d", math.floor(r + 0.5), dr))
      else
        bar.value:SetText(string.format("|cffffa000%d (+%d, -%d%%)|r",
          math.floor(r + 0.5), math.floor(over + 0.5), bracket * 10))
      end
    end
    bar:Show()
    if r ~= nil then
      if bracket == 0 then
        tt:AddLine(string.format("%d rating below the DR line - full value per point.",
          math.floor(dr - r + 0.5)), 0.6, 0.6, 0.6, true)
      else
        tt:AddLine(string.format("Past the DR line by %d rating - each point there buys %d%% less.",
          math.floor(over + 0.5), bracket * 10), 0.6, 0.6, 0.6, true)
      end
    end
    local sd = curCtx and curCtx.retailSd
    local tgts = sd and sd.targets and sd.targets[name]
    if tgts then
      local parts = {}
      for _, tg in ipairs(tgts) do parts[#parts + 1] = "~" .. tg[1] .. " (" .. tg[2] .. ")" end
      tt:AddLine("Guide target: " .. table.concat(parts, " / "), 0.7, 0.7, 0.7, true)
    end
    return true
  end

  local function ScheduleDRAppend(tt)
    if tt.scCapsPending then return end
    tt.scCapsPending = true
    C_Timer.After(0, function()
      tt.scCapsPending = nil
      if tt.scCapsAdded or not tt:IsShown() then return end
      local pd = rawget(_G, "PaperDollFrame")
      if not (pd and pd:IsVisible()) then return end
      local owner = tt:GetOwner()
      local key = owner and type(owner) == "table" and rawget(owner, "stat")
      local name = key and STAT_KEY[key]
      if not name then return end
      local ok, _, itemLink = pcall(tt.GetItem, tt)
      if ok and itemLink then return end
      if AddDRLines(tt, name) then
        tt.scCapsAdded = true
        tt:Show()
      end
    end)
  end
  GameTooltip:HookScript("OnShow", ScheduleDRAppend)
  GameTooltip:HookScript("OnTooltipCleared", function(tt)
    tt.scCapsAdded = nil
    HideTipBars()
    ScheduleDRAppend(tt)
  end)
  GameTooltip:HookScript("OnHide", function(tt)
    tt.scCapsAdded = nil
    HideTipBars()
  end)
  UI.capRowsHooked = "GameTooltip OnShow (retail: owner.stat gate)"
end

------------------------------------------------------------------------
-- Events + init
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("COMBAT_RATING_UPDATE")
if RETAIL then ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") end  -- retail spec swaps
-- Mists: spec swaps too. pcall, as for Forever: an unknown event is an error.
if MISTS then pcall(ev.RegisterEvent, ev, "PLAYER_SPECIALIZATION_CHANGED") end
-- Forever: skill-ups move the bars. pcall because registering an event the client
-- does not know is an error, and the event list of that client is not published.
if FOREVER then pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED") end
if ns.ERA then
  pcall(ev.RegisterEvent, ev, "SKILL_LINES_CHANGED")
  pcall(ev.RegisterEvent, ev, "UPDATE_SHAPESHIFT_FORM")   -- a feral druid's list follows bear form
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    StatCoachDB = StatCoachDB or {}
    local db = StatCoachDB
    db.badges = db.badges or {}   -- per-surface badge switches; absent = on
    -- Diagnostics are for reading once, not for living in the database. Both
    -- /stc stats and /stc globals write a snapshot; drop it at the next login so
    -- a debugging session cannot quietly leave 20 KB behind forever.
    db.statCheck, db.globals, db.panelDump = nil, nil, nil
    db.locked = nil   -- window lock removed in 1.1.15; drop the leftover key
    db.point = db.point or "CENTER"; db.x = db.x or 0; db.y = db.y or 0
    if db.contextMode ~= "leveling" and db.contextMode ~= "preraid" and db.contextMode ~= "endgame" then
      db.contextMode = nil  -- let Resolve() pick by level
    end
    if db.shown == nil then db.shown = true end
    if db.tooltip == nil then db.tooltip = true end
    if db.bagBadge == nil then db.bagBadge = true end
    if db.scale == nil then db.scale = 1 end
    if db.armorStrict == nil then db.armorStrict = false end
    if db.iconSize == nil then db.iconSize = 14 end
    if db.badgeSize == nil then db.badgeSize = 18 end
    BuildUI()
    CreateMinimapButton()
    if not db.shown then UI.frame:Hide() end
    Refresh()
    SetupBaganatorBadge()
    atlasHooked = SetupAtlasLootBadges()
  elseif UI.frame then
    SetupBaganatorBadge()   -- retry until Baganator's API is available
    if not atlasHooked then atlasHooked = SetupAtlasLootBadges() end
    ScheduleRefresh()
  end
end)

------------------------------------------------------------------------
-- Slash
------------------------------------------------------------------------
-- Public, for GearCoach: "what should this slot be enchanted with?" Answers for
-- the character's LIVE role (talents), which is the enchant you would actually
-- buy right now. Returns name, sourceText-or-nil; nil for slots with no enchant.
function StatCoach_EnchantFor(slot)
  local role = curCtx and curCtx.role
  if not role or RETAIL then return nil end
  for _, e in ipairs((D.ENCHANTS or {})[role] or {}) do
    if e.slot == slot then
      return e.ench, e.vendor and e.vendor.where or nil
    end
  end
  return nil
end

-- /stc dump: write what the panel shows RIGHT NOW into SavedVariables - every line,
-- every bar with its text, fill and colour, and where each one sits - so wording and
-- layout can be read off disk after a /reload and held against the numbers the game
-- reports, instead of from a screenshot. Works on every flavor; shows nothing.
local function DumpPanel()
  if not UI.frame then return end
  Refresh()
  local function text(fs)
    if fs and fs.GetText and fs:IsShown() then return fs:GetText() end
    return nil
  end
  local function box(o)   -- where it sits, to catch text running into text
    if not (o and o.GetTop and o:GetTop()) then return nil end
    return { top = math.floor(o:GetTop() + 0.5), bottom = math.floor(o:GetBottom() + 0.5),
             left = math.floor(o:GetLeft() + 0.5), right = math.floor(o:GetRight() + 0.5) }
  end
  local function sec(v) return (issecretvalue and issecretvalue(v)) and true or false end
  local _, class = UnitClass("player")
  local d = {
    when = date("%Y-%m-%d %H:%M:%S"),
    flavor = FOREVER and "forever" or (MISTS and "mists") or (ns.ERA and "era") or (RETAIL and "retail" or "classic"),
    class = class, level = UnitLevel("player"),
    frame = box(UI.frame), frameShown = UI.frame:IsShown() and true or false,
    inCombat = UnitAffectingCombat("player") and true or false,
    secret = {   -- which sheet inputs the game hides from addons right now (true = secret)
      hitRating = sec(safe(GetCombatRatingBonus, CR_HIT_MELEE)), meleeHit = sec(safe(GetHitModifier)),
      rangedHit = sec(safe(GetRangedHitModifier)), spellHit = sec(safe(GetSpellHitModifier)),
      crit = sec(safe(GetCritChance)), rangedCrit = sec(safe(GetRangedCritChance)), spellCrit = sec(safe(GetSpellCritChance)),
    },
    info = text(UI.info), now = text(UI.nowLine), nowBox = box(UI.nowLine),
    hitHeader = text(UI.fvHitHeader), capHeader = text(UI.capHeader), prioHeader = text(UI.prioHeader),
    lines = {}, bars = {},
  }
  for i = 1, PRIO_MAX do
    local t = text(UI.prio[i])
    if t then d.lines[#d.lines + 1] = { text = t, box = box(UI.prio[i]) } end
  end
  for i = 1, BAR_MAX do
    local b = UI.bars[i]
    if b and b:IsShown() then
      local r, g, bl = b.bar:GetStatusBarColor()
      d.bars[#d.bars + 1] = {
        label = b.label:GetText(), value = b.val:GetText(), fill = b.bar:GetValue(),
        color = string.format("%.2f,%.2f,%.2f", r or 0, g or 0, bl or 0),
        labelCut = (b.label.IsTruncated and b.label:IsTruncated()) and true or false,
        box = box(b),
      }
    end
  end
  if MISTS then
    local function v(fn, ...) local ok, a, b, c = pcall(fn, ...); if ok then return { a, b, c } end end
    local util = rawget(_G, "PaperDollFrameUtil")
    d.raw = {
      interface = select(4, GetBuildInfo()),
      spec = v(GetSpecializationInfo, (safe(GetSpecialization)) or 0),
      hitRatingMelee = v(GetCombatRating, CR_HIT_MELEE), hitBonusMelee = v(GetCombatRatingBonus, CR_HIT_MELEE),
      hitRatingRanged = v(GetCombatRating, CR_HIT_RANGED), hitBonusRanged = v(GetCombatRatingBonus, CR_HIT_RANGED),
      hitRatingSpell = v(GetCombatRating, CR_HIT_SPELL), hitBonusSpell = v(GetCombatRatingBonus, CR_HIT_SPELL),
      expRating = v(GetCombatRating, CR_EXPERTISE), expBonus = v(GetCombatRatingBonus, CR_EXPERTISE),
      hitModifier = v(GetHitModifier), spellHitModifier = v(GetSpellHitModifier),
      expertise = v(GetExpertise), expertisePercent = rawget(_G, "GetExpertisePercent") and v(GetExpertisePercent),
      spirit = v(UnitStat, "player", 5),
      sheetMissMelee = rawget(_G, "GetMeleeMissChance") and v(GetMeleeMissChance, 3, true),
      sheetMissSpell = rawget(_G, "GetSpellMissChance") and v(GetSpellMissChance, 3),
      constantsLoaded = (type(util) == "table" and type(util.Constants) == "table") and true or false,
    }
  end
  if ns.ERA then
    -- Every return, as text, so a nil in the middle cannot cut the list short
    local function v(fn, ...)
      local r = { pcall(fn, ...) }
      if not r[1] then return { error = tostring(r[2]) } end
      local out = {}
      for i = 2, 9 do out[#out + 1] = tostring(r[i]) end
      return out
    end
    -- Talents with points in them, and every tooltip line on the gear that speaks of
    -- hit or skill: the two things the game's hit numbers may or may not include.
    local talents = {}
    for tab = 1, 3 do
      for i = 1, tonumber((safe(GetNumTalents, tab))) or 0 do
        local ok, name, _, tier, col, rank, maxRank = pcall(GetTalentInfo, tab, i)
        if ok and rank and rank > 0 then
          talents[#talents + 1] = string.format("%d/%d %s tier %s col %s %s/%s", tab, i, tostring(name),
            tostring(tier), tostring(col), tostring(rank), tostring(maxRank))
        end
      end
    end
    local gear = {}
    for slot = 1, 18 do
      local link = GetInventoryItemLink("player", slot)
      if link then
        local lines = {}
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        if pcall(scanTip.SetHyperlink, scanTip, link) then
          for i = 2, scanTip:NumLines() do
            local fs = _G["StatCoachScanTipTextLeft" .. i]
            local t = fs and fs:GetText()
            if t and (t:lower():find("hit") or t:lower():find("skill")) then lines[#lines + 1] = t end
          end
        end
        gear[#gear + 1] = { slot = slot, link = link, lines = lines }
      end
    end
    local spellCrit = {}
    for school = 2, 7 do spellCrit[school - 1] = tostring(safe(GetSpellCritChance, school)) end
    d.raw = {
      interface = select(4, GetBuildInfo()),
      season = C_Seasons and v(C_Seasons.GetActiveSeason), form = v(GetShapeshiftFormID),
      tabs = { v(GetTalentTabInfo, 1), v(GetTalentTabInfo, 2), v(GetTalentTabInfo, 3) },
      hitModifier = v(GetHitModifier), spellHitModifier = v(GetSpellHitModifier),
      rangedHitModifier = rawget(_G, "GetRangedHitModifier") and v(GetRangedHitModifier) or "absent",
      attackBothHands = v(UnitAttackBothHands, "player"), rangedAttack = v(UnitRangedAttack, "player"),
      defense = v(UnitDefense, "player"), crit = v(GetCritChance), rangedCrit = v(GetRangedCritChance),
      spellCrit = spellCrit, talents = talents, gear = gear,
    }
  end
  StatCoachDB.panelDump = d
  print("|cffffd100StatCoach|r: panel written (" .. #d.bars .. " bars, " .. #d.lines .. " lines) - /reload saves it to disk.")
end

SLASH_STATCOACH1 = "/statcoach"
SLASH_STATCOACH2 = "/stc"
SlashCmdList["STATCOACH"] = function(msg)
  msg = (msg or ""):lower():gsub("%s+", "")
  if msg == "dump" then
    DumpPanel()
  elseif msg == "reset" then
    StatCoachDB.point, StatCoachDB.x, StatCoachDB.y = "CENTER", 0, 0
    if UI.frame then UI.frame:ClearAllPoints(); UI.frame:SetPoint("CENTER") end
    print("|cffffd100StatCoach|r: position reset.")
  elseif msg == "tooltip" then
    StatCoachDB.tooltip = not StatCoachDB.tooltip
    print("|cffffd100StatCoach|r: tooltip verdict " .. (StatCoachDB.tooltip and "ON" or "OFF") .. ".")
  elseif msg == "bag" then
    SetupBaganatorBadge()
    print("|cffffd100StatCoach|r bag badge: " .. (UI.bagStatus or "not attempted yet"))
  elseif msg == "caps" then
    print("|cffffd100StatCoach|r cap tooltips: " .. tostring(UI.capRowsHooked or "not active (retail has no caps)"))
  elseif msg == "stats" then
    -- Reads every equipped item TWICE: once with the patterns built from this
    -- client's own wordings, once with the old hand-written English ones. On an
    -- English client the two must agree on every number - that is the whole
    -- proof that the rewrite did not change what anyone already sees. Any red
    -- line is a pattern that lost or gained something, and says which stat.
    -- Written to SavedVariables as well as printed. Chat output cannot be read
    -- back off disk, and asking anyone to retype thirty numbers off a screenshot
    -- is how transcription errors get mistaken for bugs.
    local report = { at = date("%c"), locale = GetLocale(), build = select(1, GetBuildInfo()), lines = {} }
    -- Same lookup the aura check uses, recorded so the id can be confirmed too.
    -- Retail removed the GetSpellInfo global in 12.0 and C_Spell.GetSpellInfo
    -- hands back a table; TBC still has the old one. Prefer the new, fall
    -- back to the old, and never call a nil (9 Sep 2026 migration scan).
    local function spellName(id)
      if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
      end
      return GetSpellInfo and GetSpellInfo(id)
    end
    report.heroicPresence = tostring(spellName(HEROIC_PRESENCE))
    report.inspiringPresence = tostring(spellName(INSPIRING_PRESENCE))
    local diffs = 0
    report.patternCount = #PARSE_LOCALE
    print("|cffffd100StatCoach|r stat patterns (from client wordings | old English):")
    for slot = 1, 18 do
      local link = GetInventoryItemLink("player", slot)
      if link then
        local a = statTableFromTooltip(link, PARSE_LOCALE)
        local b = statTableFromTooltip(link, PARSE)
        local keys, diff = {}, false
        for k in pairs(a) do keys[k] = true end
        for k in pairs(b) do keys[k] = true end
        local bits = {}
        for k in pairs(keys) do
          local x, y = a[k] or 0, b[k] or 0
          -- __socketColors is a TABLE of colour counts, not a number, and
          -- this loop compares and prints numbers: an equipped item with an
          -- empty socket crashed the whole report on "concatenate a table".
          -- Reached first on retail (9 Sep 2026) once the GetSpellInfo call
          -- above stopped failing ahead of it; TBC had the same hole.
          if type(x) == "number" and type(y) == "number" then
            if x ~= y then diff = true end
            bits[#bits + 1] = k .. " " .. x .. "|" .. y .. (x ~= y and " <<" or "")
          end
        end
        table.sort(bits)
        if diff then diffs = diffs + 1 end
        local row = (GetItemInfo(link) or link) .. "  " .. table.concat(bits, ", ")
        report.lines[#report.lines + 1] = (diff and "DIFF " or "same ") .. row
        print((diff and "|cffff8080" or "|cff88cc88") .. row .. "|r")
      end
    end
    report.diffCount = diffs
    StatCoachDB.statCheck = report
    print(("green = the two agree, red = they differ (<< marks the stat). %d of %d items differ.")
      :format(diffs, #report.lines))
    print("Saved to StatCoachDB.statCheck - /reload writes it to disk.")
  elseif msg == "globals" then
    -- The tooltip has to stay the stat source on this client, so the way to make
    -- it speak other languages is to build its patterns from the game's OWN
    -- wordings. This captures them; it is the input to that rewrite, not part of
    -- it. Harmless to run, writes nothing but a record of what the client says.
    local out = { at = date("%c"), locale = GetLocale(),
                  build = select(1, GetBuildInfo()), strings = {} }
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "string"
         and (k:find("^ITEM_MOD_") or k:find("^EMPTY_SOCKET") or k:find("^STAT_")) then
        out.strings[k] = v
      end
    end
    for _, k in ipairs({ "DPS_TEMPLATE", "ARMOR", "RESISTANCE0_NAME", "ITEM_SOCKET_BONUS",
                         "ITEM_SET_BONUS", "ITEM_SET_NAME", "SHIELD_BLOCK", "BLOCK_CHANCE",
                         "ITEM_SPELL_TRIGGER_ONEQUIP", "ITEM_SPELL_TRIGGER_ONUSE" }) do
      local v = rawget(_G, k)
      if type(v) == "string" then out.strings[k] = v end
    end
    local n = 0
    for _ in pairs(out.strings) do n = n + 1 end
    StatCoachDB.globals = out
    print(("|cffffd100StatCoach|r: captured %d wordings to StatCoachDB.globals - /reload writes it to disk."):format(n))
  elseif msg == "armor" then
    StatCoachDB.armorStrict = not StatCoachDB.armorStrict
    print("|cffffd100StatCoach|r: off-type armor is now "
      .. (StatCoachDB.armorStrict and "HIDDEN (strict filter)" or "shown with a scoring penalty (default)") .. ".")
  elseif msg:match("^icon") then
    -- msg has whitespace stripped, so "/stc icon 20" arrives as "icon20"
    local n = tonumber(msg:match("^icon(%d+)$"))
    if n then
      StatCoachDB.iconSize = math.max(10, math.min(30, n))
      print("|cffffd100StatCoach|r: upgrade icon size set to " .. StatCoachDB.iconSize .. ".")
    else
      print("|cffffd100StatCoach|r: icon size is " .. (StatCoachDB.iconSize or 14)
        .. ". Use /stc icon 10-30 (default 14).")
    end
  elseif msg:match("^badge") then
    local n = tonumber(msg:match("^badge(%d+)$"))
    if n then
      StatCoachDB.badgeSize = math.max(10, math.min(30, n))
      wipe(bagCache)
      print("|cffffd100StatCoach|r: bag badge size set to " .. StatCoachDB.badgeSize
        .. " (reopen your bags to see it).")
    else
      print("|cffffd100StatCoach|r: bag badge size is " .. (StatCoachDB.badgeSize or 18)
        .. ". Use /stc badge 10-30 (default 18).")
    end
  elseif msg == "calib" then
    StatCoachDB.calib = not StatCoachDB.calib
    local n = StatCoachDB.pctlog and #StatCoachDB.pctlog or 0
    print("|cffffd100StatCoach|r: percent calibration logging "
      .. (StatCoachDB.calib and "ON" or "OFF") .. " (" .. n .. " verdicts on file"
      .. (n >= 500 and " - FULL" or "") .. "). /reload writes to disk.")
  elseif msg == "calibwipe" then
    StatCoachDB.pctlog, StatCoachDB.calib = nil, nil
    print("|cffffd100StatCoach|r: calibration log deleted.")
  elseif msg == "minimap" then
    StatCoach_ToggleMinimap()
  elseif UI.frame and UI.frame:IsShown() then
    UI.hideAll()
  elseif UI.frame then
    UI.frame:Show(); StatCoachDB.shown = true; Refresh()
  end
end
