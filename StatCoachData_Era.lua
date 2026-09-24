--[[ StatCoachData_Era.lua
     CLASSIC ERA data (1.15.x, level 60). Loaded only by StatCoach_Vanilla.toc.
     Pure tables, no API calls.

     The caps are NOT in here: the engine works them out from your weapon skill with
     the game's own attack table (see the ERA path in StatCoach.lua). This file carries,
     per talent tree, the stat order on Wowhead's WoW Classic stat page for it (read
     2026-09-24; every page says patch 1.15.8, updated 2025/03/20, Feral DPS 2023/11/21),
     what the spec attacks with (which caps apply) and the guide's point in a sentence.

     Where Wowhead has one page for a whole class (hunter, rogue, warlock, holy and
     discipline priest), every tree of it reads that page. Where it has none (Arms
     warrior, Protection paladin) the entry says so; Protection paladin gets no list.
]]--

local ADDON, ns = ...
ns.Data = ns.Data or {}
local D = ns.Data

D.era = D.era or {}
local E = D.era

E.classOrder = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- school: the spell school a caster's hit, crit and spell damage are read for
-- (2 holy, 3 fire, 4 nature, 5 frost, 6 shadow, 7 arcane - the game's own numbering).
-- dw: the spec dual wields in raids, so hit past the cap still helps white swings.
local WH = "Stat priority: Wowhead's WoW Classic "

E.classes = {
  WARRIOR = {
    tabSpec = { "Arms", "Fury", "Protection" },
    specOrder = { "Arms", "Fury", "Protection" },
    specs = {
      Arms = {
        role = "DAMAGER", primary = "Strength", attack = "melee",
        stats = { "Hit", "Strength", "Attack Power", "Agility", "Crit" },
        notes = "Hit to 9% (6% with 305 weapon skill), then strength and attack power, then agility and crit. Wowhead's Classic guide covers Fury only; Arms uses the same order.",
        source = WH .. "Fury Warrior guide, 2025/03/20.",
      },
      Fury = {
        role = "DAMAGER", primary = "Strength", attack = "melee", dw = true,
        stats = { "Hit", "Strength", "Attack Power", "Agility", "Crit" },
        notes = "Hit to 9% (6% with 305 weapon skill), then strength and attack power, then agility and crit. The guide aims for 5 to 8 extra weapon skill from racials or items.",
        source = WH .. "Fury Warrior guide, 2025/03/20.",
      },
      Protection = {
        role = "TANK", primary = "Strength", attack = "melee",
        stats = { "Hit", "Armor", "Stamina", "Agility", "Dodge" },
        notes = "Hit first. After that you gear for the fight: survival (armor, stamina, agility, dodge - the list shown) or threat (hit, agility, crit).",
        source = WH .. "Warrior Tank guide, 2025/03/20.",
      },
    },
  },
  PALADIN = {
    tabSpec = { "Holy", "Protection", "Retribution" },
    specOrder = { "Holy", "Protection", "Retribution" },
    specs = {
      Holy = {
        role = "HEALER", primary = "Intellect", school = 2,
        stats = { "Healing Power", "Intellect", "Spell Crit", "MP5", "Stamina", "Spirit" },
        notes = "Healing power first. Intellect, crit and MP5 all mean more mana to heal with; early on, when mana is tight, intellect climbs.",
        source = WH .. "Paladin Healing guide, 2025/03/20.",
      },
      Protection = {
        role = "TANK", primary = "Strength", attack = "melee",
        stats = {},
        notes = "No Classic guide publishes a stat order for Protection paladins, so StatCoach shows your caps and leaves the list empty rather than guess.",
      },
      Retribution = {
        role = "DAMAGER", primary = "Strength", attack = "melee",
        stats = { "Hit", "Strength", "Agility", "Crit", "Attack Power", "Stamina", "Intellect", "MP5" },
        notes = "Hit to 9% (the Precision talent gives 3%), then strength, then agility and crit - crit keeps Vengeance up.",
        source = WH .. "Retribution Paladin guide, 2025/03/20.",
      },
    },
  },
  HUNTER = {
    tabSpec = { "Beast Mastery", "Marksmanship", "Survival" },
    specOrder = { "Beast Mastery", "Marksmanship", "Survival" },
    specs = {},
  },
  ROGUE = {
    tabSpec = { "Assassination", "Combat", "Subtlety" },
    specOrder = { "Assassination", "Combat", "Subtlety" },
    specs = {},
  },
  PRIEST = {
    tabSpec = { "Discipline", "Holy", "Shadow" },
    specOrder = { "Discipline", "Holy", "Shadow" },
    specs = {
      Shadow = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 6,
        stats = { "Spell Hit", "Spell Damage", "MP5", "Intellect", "Spirit" },
        notes = "16% spell hit is the goal - Shadow Focus gives 10% of it. Then spell damage and MP5.",
        source = WH .. "Shadow Priest guide, 2025/03/20.",
      },
    },
  },
  SHAMAN = {
    tabSpec = { "Elemental", "Enhancement", "Restoration" },
    specOrder = { "Elemental", "Enhancement", "Restoration" },
    specs = {
      Elemental = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 4,
        stats = { "Spell Crit", "Spell Hit", "Spell Damage", "MP5", "Intellect", "Stamina" },
        notes = "Spell crit and spell hit are worth the same, thanks to Elemental Fury. Then spell damage; MP5 gains on long fights.",
        source = WH .. "Elemental Shaman guide, 2025/03/20.",
      },
      Enhancement = {
        role = "DAMAGER", primary = "Strength", attack = "melee",
        stats = { "Weapon Skill", "Crit", "Hit", "Strength", "Agility", "MP5", "Intellect", "Stamina" },
        notes = "The first 5 extra weapon skill drop your hit cap to 6% - more does little. Crit edges out hit, and hit is worth nothing past the cap.",
        source = WH .. "Enhancement Shaman guide, 2025/03/20.",
      },
      Restoration = {
        role = "HEALER", primary = "Intellect", school = 4,
        stats = { "Healing Power", "MP5", "Intellect", "Spell Crit", "Stamina", "Spirit" },
        notes = "Healing power and MP5 are equal: short fights favour healing power, long ones MP5.",
        source = WH .. "Shaman Healing guide, 2025/03/20.",
      },
    },
  },
  MAGE = {
    tabSpec = { "Arcane", "Fire", "Frost" },
    specOrder = { "Arcane", "Fire", "Frost" },
    specs = {
      Arcane = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 7,
        stats = { "Spell Hit", "Spell Damage", "Spell Crit", "Intellect", "Spell Penetration", "Spirit" },
        notes = "Wowhead's Classic mage guide gives orders for Frost and Fire only; Arcane follows the Frost one here. 16% spell hit first.",
        source = WH .. "Mage guide (Frost order), 2025/03/20.",
      },
      Fire = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 3,
        stats = { "Spell Hit", "Spell Crit", "Spell Damage", "Intellect", "Spell Penetration", "Spirit" },
        notes = "16% spell hit first - Elemental Precision gives 6%. Before Blackwing Lair gear the cap is out of reach, and 13-15% is common.",
        source = WH .. "Mage guide, 2025/03/20.",
      },
      Frost = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 5,
        stats = { "Spell Hit", "Spell Damage", "Spell Crit", "Intellect", "Spell Penetration", "Spirit" },
        notes = "16% spell hit first - Elemental Precision gives 6%. Before Blackwing Lair gear the cap is out of reach, and 13-15% is common.",
        source = WH .. "Mage guide, 2025/03/20.",
      },
    },
  },
  WARLOCK = {
    tabSpec = { "Affliction", "Demonology", "Destruction" },
    specOrder = { "Affliction", "Demonology", "Destruction" },
    specs = {},
  },
  DRUID = {
    tabSpec = { "Balance", "Feral (Cat)", "Restoration" },
    specOrder = { "Balance", "Feral (Cat)", "Feral (Bear)", "Restoration" },
    specs = {
      Balance = {
        role = "DAMAGER", primary = "Intellect", attack = "spell", school = 7,
        stats = { "Spell Hit", "Spell Crit", "Spell Damage", "Intellect", "Spirit", "Stamina" },
        notes = "Spell hit to 16% - Starfire's long cast makes a miss costly - then crit, which Nature's Grace feeds on, then spell damage.",
        source = WH .. "Balance Druid guide, 2025/03/20.",
      },
      ["Feral (Cat)"] = {
        role = "DAMAGER", primary = "Agility", attack = "melee",
        stats = { "Hit", "Crit", "Haste", "Agility", "Strength", "Attack Power" },
        notes = "Hit to 9%, then crit and haste; agility beats strength. The guide calls the hit cap a limit on hit's value, not a goal to reach at any price.",
        source = WH .. "Feral Druid DPS guide, 2023/11/21.",
      },
      ["Feral (Bear)"] = {
        role = "TANK", primary = "Agility", attack = "melee",
        stats = { "Hit", "Haste", "Crit", "Strength", "Stamina", "Agility", "Attack Power", "Defense" },
        notes = "Ranked by overall value to survival and threat. Bears cannot block or parry, so armor is their only mitigation; hit is never a must.",
        source = WH .. "Feral Druid Tank guide, 2025/03/20 (written for Season of Mastery, same rules as Era).",
      },
      Restoration = {
        role = "HEALER", primary = "Intellect", school = 4,
        stats = { "Healing Power" },
        notes = "Healing power is always the best stat. The guide gives no fixed order after it: crit suits Regrowth and Nature's Grace builds, intellect the Nature's Swiftness ones, and spirit or MP5 only help if you run out of mana.",
        source = WH .. "Druid Healing guide, 2025/03/20.",
      },
    },
  },
}

-- One page for the whole class: every tree reads it.
local function shared(class, spec)
  for _, name in ipairs(E.classes[class].specOrder) do
    local t = {}
    for k, v in pairs(spec) do t[k] = v end
    E.classes[class].specs[name] = t
  end
end

shared("HUNTER", {
  role = "DAMAGER", primary = "Agility", attack = "ranged",
  stats = { "Hit", "Agility", "Stamina", "Intellect", "Spirit", "Strength" },
  notes = "Hit to 9% - Surefooted gives 3% and a Biznicks scope 3% more. Then agility; once crit reaches its soft cap, attack power beats agility.",
  source = WH .. "Hunter guide (all three trees), 2025/03/20.",
})
shared("ROGUE", {
  role = "DAMAGER", primary = "Agility", attack = "melee", dw = true,
  stats = { "Hit", "Weapon Skill", "Agility", "Strength", "Attack Power", "Crit" },
  notes = "At least 9% hit (Precision gives 5%) and 308 weapon skill, which takes most of the sting out of glancing blows. Hit past 9% still helps your white swings.",
  source = WH .. "Rogue guide (all three trees), 2025/03/20.",
})
shared("WARLOCK", {
  role = "DAMAGER", primary = "Intellect", attack = "spell", school = 6,
  stats = { "Spell Damage", "Spell Hit", "Spell Crit", "Spell Penetration", "Intellect", "Stamina" },
  notes = "Spell damage, then hit, then crit - but the guide says to judge whole items with a sim, since the mix of stats on an item matters more than the order.",
  source = WH .. "Warlock guide (all three trees), 2025/03/20.",
})

-- Holy and Discipline share the healer page; Shadow keeps its own entry above.
for _, name in ipairs({ "Discipline", "Holy" }) do
  E.classes.PRIEST.specs[name] = {
    role = "HEALER", primary = "Intellect", school = 2,
    stats = { "Healing Power", "Spirit", "MP5", "Intellect", "Spell Crit", "Stamina" },
    notes = "Healing power first. Spirit for most raids; MP5 is as good or better on fights with no pause to regenerate.",
    source = WH .. "Priest Healing guide, 2025/03/20.",
  }
end
