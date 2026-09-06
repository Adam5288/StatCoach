--[[ StatCoachData_Retail.lua
     RETAIL (Mainline) data. Loaded only by StatCoach_Mainline.toc; only USED when
     the engine detects retail (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE). Pure tables,
     no API calls -> safe everywhere.

     Retail has NO hit/expertise/defense caps. Gear is driven by:
       1) Item level (by far the biggest factor)
       2) Primary stat (Str/Agi/Int - fixed by spec, scales with ilvl)
       3) Secondaries: Crit, Haste, Mastery, Versatility (diminishing returns, no caps)

     Spec keys MUST match GetSpecializationInfo() names exactly (English client).
     ALL 39 specs taken from the Wowhead SEASON 2 stat-priority page for each spec
     (13 Aug 2026), which is the authoritative source; the one-line "rough guideline"
     on the BiS pages disagreed with it for 6 specs and is not used. Every entry below
     was then read back and diffed against the harvested order - all 39 match.
     Where the guide marks stats as equal (written "=" or "Haste/Crit") the note says
     so; the array still has to pick an order, so tied stats are listed in the guide's
     own order and the note is what carries the tie.
     Watch out when re-harvesting: some pages write "Crit", others "Critical Strike",
     and a few use "/" rather than "=" for a tie. Missing the short form silently
     produces a wrong order.
     Retail priorities shift every patch/build - sim yourself on Raidbots for the
     real answer; these are the guide defaults. Some specs differ by hero talent
     (noted); the listed order is the guide's primary/default build.
]]--

local ADDON, ns = ...
ns.Data = ns.Data or {}
local D = ns.Data

D.retail = D.retail or {}
local RT = D.retail

RT.SECONDARY = { "Crit", "Haste", "Mastery", "Versatility" }

-- Specialization id -> the English spec key the tables below are written in.
--
-- GetSpecializationInfo returns the spec name in the CLIENT'S language, so on any
-- non-English client every lookup here missed and the panel fell back to "no spec
-- data". Spec ids are language-independent. (Found via a CurseForge report on
-- TrinketCoach, which had the identical bug; ids verified against
-- LibSpecialization, the table DBM ships.)
RT.SPECID = {
  [71]="Arms", [72]="Fury", [73]="Protection",                        -- Warrior
  [65]="Holy", [66]="Protection", [70]="Retribution",                 -- Paladin
  [253]="Beast Mastery", [254]="Marksmanship", [255]="Survival",      -- Hunter
  [259]="Assassination", [260]="Outlaw", [261]="Subtlety",            -- Rogue
  [256]="Discipline", [257]="Holy", [258]="Shadow",                   -- Priest
  [250]="Blood", [251]="Frost", [252]="Unholy",                       -- Death Knight
  [262]="Elemental", [263]="Enhancement", [264]="Restoration",        -- Shaman
  [62]="Arcane", [63]="Fire", [64]="Frost",                           -- Mage
  [265]="Affliction", [266]="Demonology", [267]="Destruction",        -- Warlock
  [268]="Brewmaster", [270]="Mistweaver", [269]="Windwalker",         -- Monk
  [102]="Balance", [103]="Feral", [104]="Guardian", [105]="Restoration", -- Druid
  [577]="Havoc", [581]="Vengeance", [1480]="Devourer",                -- Demon Hunter
  [1467]="Devastation", [1468]="Preservation", [1473]="Augmentation", -- Evoker
}

-- Diminishing returns on secondary RATING at level 90 (Midnight 12.0/12.1; Maxroll
-- "Stat Diminishing Returns" + Wowhead's DR guide, checked 15 Aug 2026). Retail has
-- no hard caps - THIS is the closest thing: rating above the first threshold buys
-- 10% less, and every further bracket (DR/3 rating wide: 440 / 460 / 460 / 540)
-- costs another 10%, flattening at -50% until the hard cap at 20 widths.
-- Crit/Haste/Vers thresholds are 30% from rating; Mastery uses Crit's rating
-- brackets (its % is spec-scaled, so it can never be stated as one number).
RT.DR = { Haste = 1320, Crit = 1380, Mastery = 1380, Versatility = 1620 }
RT.DR_HARDCAP_WIDTHS = 20   -- hard cap = DR + 20 bracket widths (8800 / 9200 / 9200 / 10800)

-- Guide rating targets. Only specs whose Wowhead stat page states one; a spec
-- without an entry has no target - do not invent one. Format: stat -> list of
-- { rating, "context" }, first entry = the default the bar marks.
-- Sub Rogue: "Haste (~1100 Haste)" single target / "(~700 Haste)" Mythic+.
-- Elemental: "Mastery to 1200 rating, then Haste/Crit".

RT.classOrder = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT",
                  "SHAMAN","MAGE","WARLOCK","MONK","DRUID","DEMONHUNTER","EVOKER" }

local SIM = "Stat values swing with gear/build - sim on Raidbots for your exact answer."

RT.classes = {
  WARRIOR = {
    specOrder = { "Arms", "Fury", "Protection" },
    specs = {
      Arms = { role="DAMAGER", primary="Strength",
        stats = { "Crit", "Haste", "Mastery", "Versatility" },
        notes = "Item level first. Crit leads, then Haste; Mastery and Versatility behind. Season 2 guide order. " .. SIM },
      Fury = { role="DAMAGER", primary="Strength",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. Season 2 guide order. " .. SIM },
      Protection = { role="TANK", primary="Strength",
        stats = { "Haste", "Crit", "Versatility", "Mastery" },
        notes = "Item level first. Haste, then Crit, Versatility, Mastery. Season 2 guide order. " .. SIM },
    },
  },
  PALADIN = {
    specOrder = { "Holy", "Protection", "Retribution" },
    specs = {
      Holy = { role="HEALER", primary="Intellect",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        notes = "Item level first. Mastery leads; Haste and Crit are equal behind it, then Versatility. Season 2 guide order. " .. SIM },
      Protection = { role="TANK", primary="Strength",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. Season 2 guide order. " .. SIM },
      Retribution = { role="DAMAGER", primary="Strength",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        notes = "Item level first. Mastery leads, then Haste; Crit and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  HUNTER = {
    specOrder = { "Beast Mastery", "Marksmanship", "Survival" },
    specs = {
      ["Beast Mastery"] = { role="DAMAGER", primary="Agility",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
      Marksmanship = { role="DAMAGER", primary="Agility",
        stats = { "Crit", "Mastery", "Versatility", "Haste" },
        notes = "Item level first. Crit leads, then Mastery, Versatility, Haste. Season 2 guide order. " .. SIM },
      Survival = { role="DAMAGER", primary="Agility",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  ROGUE = {
    specOrder = { "Assassination", "Outlaw", "Subtlety" },
    specs = {
      Assassination = { role="DAMAGER", primary="Agility",
        stats = { "Crit", "Haste", "Mastery", "Versatility" },
        notes = "Item level first. Crit leads, then Haste; Mastery and Versatility behind. Season 2 guide order. " .. SIM },
      Outlaw = { role="DAMAGER", primary="Agility",
        stats = { "Haste", "Crit", "Versatility", "Mastery" },
        notes = "Item level first. Haste leads, then Crit; Versatility and Mastery behind. Season 2 guide order. " .. SIM },
      Subtlety = { role="DAMAGER", primary="Agility",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        targets = { Haste = { { 1100, "raid" }, { 700, "M+" } } },
        notes = "Item level first. Mastery leads, then Haste; Crit and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  PRIEST = {
    specOrder = { "Discipline", "Holy", "Shadow" },
    specs = {
      Discipline = { role="HEALER", primary="Intellect",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. Season 2 guide order. " .. SIM },
      Holy = { role="HEALER", primary="Intellect",
        stats = { "Crit", "Versatility", "Mastery", "Haste" },
        notes = "Item level first. Crit leads; Versatility and Mastery are equal behind it, Haste last. Season 2 guide order. " .. SIM },
      Shadow = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  DEATHKNIGHT = {
    specOrder = { "Blood", "Frost", "Unholy" },
    specs = {
      Blood = { role="TANK", primary="Strength",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "San'layn order: Haste leads, then Mastery, Crit and Versatility equal. Deathbringer instead wants Crit first, Haste last. Season 2 guide order. " .. SIM },
      Frost = { role="DAMAGER", primary="Strength",
        stats = { "Crit", "Mastery", "Haste", "Versatility" },
        notes = "Item level first. Crit leads, then Mastery; Haste and Versatility behind. Season 2 guide order. " .. SIM },
      Unholy = { role="DAMAGER", primary="Strength",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  SHAMAN = {
    specOrder = { "Elemental", "Enhancement", "Restoration" },
    specs = {
      Elemental = { role="DAMAGER", primary="Intellect",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        targets = { Mastery = { { 1200, "then Haste/Crit" } } },
        notes = "Item level first. Mastery up to about 1200 rating, then Haste and Crit equal, Versatility last. Season 2 guide order. " .. SIM },
      Enhancement = { role="DAMAGER", primary="Agility",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        notes = "Item level first. Mastery and Haste are equal on top, then Crit, then Versatility. Season 2 guide order. " .. SIM },
      Restoration = { role="HEALER", primary="Intellect",
        stats = { "Crit", "Haste", "Versatility", "Mastery" },
        notes = "Item level first. Crit leads, then Haste; Versatility and Mastery behind. Season 2 guide order. " .. SIM },
    },
  },
  MAGE = {
    specOrder = { "Arcane", "Fire", "Frost" },
    specs = {
      Arcane = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. Season 2 guide order. " .. SIM },
      Fire = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Mastery", "Versatility", "Crit" },
        notes = "Item level first. Haste leads, then Mastery, Versatility, Crit. Season 2 guide order. " .. SIM },
      Frost = { role="DAMAGER", primary="Intellect",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  WARLOCK = {
    specOrder = { "Affliction", "Demonology", "Destruction" },
    specs = {
      Affliction = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Crit", "Versatility", "Mastery" },
        notes = "Item level first. Haste leads, then Crit; Versatility and Mastery behind. Season 2 guide order. " .. SIM },
      Demonology = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Crit", "Mastery", "Versatility" },
        notes = "Item level first. Haste and Crit are equal on top, then Mastery, then Versatility. Season 2 guide order. " .. SIM },
      Destruction = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        notes = "Item level first. Haste leads; Mastery and Crit are equal behind it, then Versatility. Season 2 guide order. " .. SIM },
    },
  },
  MONK = {
    specOrder = { "Brewmaster", "Mistweaver", "Windwalker" },
    specs = {
      Brewmaster = { role="TANK", primary="Agility",
        stats = { "Versatility", "Crit", "Mastery", "Haste" },
        notes = "Item level first. Versatility, Crit and Mastery are all equal; Haste last. Season 2 guide order. " .. SIM },
      Mistweaver = { role="HEALER", primary="Intellect",
        stats = { "Haste", "Crit", "Versatility", "Mastery" },
        notes = "Item level first. Haste leads, then Crit, Versatility, Mastery. Season 2 guide order. " .. SIM },
      Windwalker = { role="DAMAGER", primary="Agility",
        stats = { "Haste", "Crit", "Mastery", "Versatility" },
        notes = "Item level first. Haste leads, then Crit; Mastery and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
  DRUID = {
    specOrder = { "Balance", "Feral", "Guardian", "Restoration" },
    specs = {
      Balance = { role="DAMAGER", primary="Intellect",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        notes = "Item level first. Mastery leads; Haste and Crit are equal behind it, then Versatility. Season 2 guide order. " .. SIM },
      Feral = { role="DAMAGER", primary="Agility",
        stats = { "Mastery", "Haste", "Crit", "Versatility" },
        notes = "Item level first. Mastery leads, then Haste; Crit and Versatility behind. Season 2 guide order. " .. SIM },
      Guardian = { role="TANK", primary="Agility",
        stats = { "Haste", "Versatility", "Crit", "Mastery" },
        notes = "Item level first. Haste, then Versatility, Crit, Mastery. Season 2 guide order. " .. SIM },
      Restoration = { role="HEALER", primary="Intellect",
        stats = { "Haste", "Mastery", "Versatility", "Crit" },
        notes = "Item level first. Haste leads, then Mastery; Versatility and Crit behind. Season 2 guide order. " .. SIM },
    },
  },
  DEMONHUNTER = {
    specOrder = { "Havoc", "Vengeance", "Devourer" },
    specs = {
      Havoc = { role="DAMAGER", primary="Agility",
        stats = { "Crit", "Mastery", "Haste", "Versatility" },
        notes = "Item level first. Crit leads, then Mastery; Haste and Versatility behind. Season 2 guide order. " .. SIM },
      Vengeance = { role="TANK", primary="Agility",
        stats = { "Haste", "Crit", "Versatility", "Mastery" },
        notes = "Item level first. Haste, then Crit, Versatility, Mastery. Season 2 guide order. " .. SIM },
      -- Midnight's third Demon Hunter spec: ranged, and the only one that scales
      -- with Intellect rather than Agility.
      Devourer = { role="DAMAGER", primary="Intellect",
        stats = { "Haste", "Mastery", "Crit", "Versatility" },
        targets = { Haste = { { 800, "then Crit/Mastery" } } },
        notes = "Item level first. Haste leads, then Mastery; Crit and Versatility behind. " ..
          "The guide's second build wants Haste only up to about 800 rating (18-20%) and " ..
          "puts Crit and Mastery ahead of any Haste past that. Season 2 guide order. " .. SIM },
    },
  },
  EVOKER = {
    specOrder = { "Devastation", "Preservation", "Augmentation" },
    specs = {
      Devastation = { role="DAMAGER", primary="Intellect",
        stats = { "Crit", "Mastery", "Haste", "Versatility" },
        notes = "Item level first. Crit leads, then Mastery; Haste and Versatility behind. Season 2 guide order. " .. SIM },
      Preservation = { role="HEALER", primary="Intellect",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
      Augmentation = { role="DAMAGER", primary="Intellect",
        stats = { "Mastery", "Crit", "Haste", "Versatility" },
        notes = "Item level first. Mastery leads, then Crit; Haste and Versatility behind. Season 2 guide order. " .. SIM },
    },
  },
}

-- Retail gems/enchants are all secondary-stat based (one gem type per secondary);
-- the right pick is simply your #1 secondary from the priority list.
RT.GEM_NOTE = "Gems & enchants on retail: stack your #1 secondary stat (see priority list). No socket colours - any gem fits any socket."
