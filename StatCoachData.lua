--[[ StatCoachData.lua
     Data table: rating constants, caps, and stat priority per class x spec x context.
     Everything here is "combat mechanics" (level 70, TBC), not item data -> Anniversary-safe.
     Talent-based hit is read LIVE by the engine, so the cap bars below carry the caps; priority lists say just the stat.
     Tune freely per raid phase. Values checked against Wowhead/Warcraft Tavern TBC guides.
]]--

local ADDON, ns = ...
ns.Data = ns.Data or {}
local D = ns.Data

D.version = "1.1.13"

-- Level 70: how much rating gives 1% (or 1 skill for expertise/defense)
D.RATING = {
  meleeHit  = 15.77,  -- rating per 1% melee/ranged hit
  spellHit  = 12.62,  -- rating per 1% spell hit
  crit      = 22.08,  -- rating per 1% crit (melee & spell)
  haste     = 15.77,  -- rating per 1% haste
  expertise = 3.94,   -- rating per 1 expertise skill (1 skill = 0.25% less dodge/parry)
  dodge     = 18.92,
  parry     = 18.92,
  block     = 7.88,
  defense   = 2.37,   -- rating per 1 defense skill
}

-- Targets/caps vs a raid boss (level 73 = "boss +3")
D.CAP = {
  meleeSpecialHitPct = 9,    -- yellow/special attacks always land at 9%
  meleeWhiteDWHitPct = 28,   -- DW auto-swings vs boss: 9% base miss + 19% DW penalty (24% is the EQUAL-level number, not boss)
  spellHitPct        = 16,   -- spells vs boss (talents are added to your CURRENT hit, live)
  expertiseSkill     = 26,   -- removes boss 6.5% dodge from behind (6.5 / 0.25)
  tankDefenseSkill   = 490,  -- "uncrittable" vs boss (base 350 + 140 from def)
  uncrushablePct     = 102.4,-- miss+dodge+parry+block vs boss: no crushing blows
  bossAvoidPenalty   = 2.4,  -- boss weapon skill 365 shaves 0.6% off each of miss/dodge/parry/block
  baseMissPct        = 5,    -- boss base chance to miss you
  feralUncritPct     = 5.6,  -- crit-taken reduction needed vs boss (resilience + defense)
}

-- Stat weights (value per point) for gear scoring. Cap-gated stats
-- (hit / expertise / spellHit / defense) are auto-zeroed by the engine once
-- you're capped -- that's what makes this smarter than Pawn. Tune freely.
-- A spec may override with its own `weights = {...}`.
D.WEIGHTS = {
  melee     = { strength=2.0, ap=1.0, crit=0.8, hit=1.3, expertise=1.0, haste=0.8, agility=0.6, stamina=0.1, armor=0.01, weaponDPS=6.0 },
  meleeDW   = { agility=1.5, ap=1.0, crit=0.9, hit=1.3, expertise=1.0, haste=0.9, strength=1.0, stamina=0.1, armor=0.01, weaponDPS=5.0 },
  ranged    = { agility=1.7, ap=1.0, crit=0.9, hit=1.3, haste=0.8, intellect=0.15, stamina=0.1, armor=0.01, weaponDPS=5.0 },
  caster    = { spellPower=1.0, spellHit=1.2, spellCrit=0.7, crit=0.7, spellHaste=0.8, haste=0.7, intellect=0.3, spirit=0.1, stamina=0.05 },
  healer    = { healing=1.0, spellPower=0.9, mp5=0.7, spellCrit=0.5, crit=0.5, intellect=0.4, spirit=0.3, spellHaste=0.5, stamina=0.05 },
  tank      = { stamina=1.0, defense=1.2, dodge=0.9, parry=0.9, blockValue=0.4, armor=0.05, hit=0.5, expertise=0.6, agility=0.5, strength=0.3, weaponDPS=1.5 },
  tankDruid = { stamina=1.0, agility=1.2, armor=0.15, dodge=0.8, hit=0.4, expertise=0.5, ap=0.3, strength=0.3, weaponDPS=2.0 },
}

-- Best TBC gem per SOCKET COLOUR, by role (Wowhead-standard gemming tables).
-- Each socket: { color, name, id? (for exact icon), hitName? (yellow swap while below hit cap) }.
-- Melee (str) table verified vs a Fury gemming guide; other roles are best-effort seeds.
D.GEMS = {
  melee = {
    { color="meta",   name="Relentless Earthstorm Diamond", id=32409 },
    { color="red",    name="Bold (Str)", id=32193, rare="Bold Living Ruby", rareId=24027, cheap="Living Ruby" },
    { color="yellow", name="Inscribed (Str+Crit)", id=32217, rare="Inscribed Noble Topaz", rareId=24058, hitName="Rigid (Hit)", hitId=32206, hitRare="Rigid Dawnstone", hitRareId=24051, cheap="Noble Topaz", hitCheap="Dawnstone" },
    { color="blue",   name="Sovereign (Str+Stam)", id=32211, rare="Sovereign Nightseye", rareId=24054, cheap="Nightseye" },
    { color="red",    label="Honor gem", name="Bold Ornate Ruby", id=28362 },
  },
  meleeDW = {
    { color="meta",   name="Relentless Earthstorm Diamond", id=32409 },
    { color="red",    name="Delicate (Agi)", id=32194, rare="Delicate Living Ruby", rareId=24028 },
    { color="yellow", name="Wicked (AP+Crit)", id=32222, rare="Wicked Noble Topaz", rareId=31868, hitName="Glinting (Agi+Hit)", hitId=32220, hitRare="Glinting Noble Topaz", hitRareId=24061 },
    { color="blue",   name="Shifting (Agi+Stam)", id=32212, rare="Shifting Nightseye", rareId=24055 },
    { color="red",    label="Honor gem", name="Bold Ornate Ruby", id=28362 },
  },
  ranged = {
    { color="meta",   name="Relentless Earthstorm Diamond", id=32409 },
    { color="red",    name="Delicate (Agi)", id=32194, rare="Delicate Living Ruby", rareId=24028 },
    { color="yellow", name="Wicked (AP+Crit)", id=32222, rare="Wicked Noble Topaz", rareId=31868, hitName="Glinting (Agi+Hit)", hitId=32220, hitRare="Glinting Noble Topaz", hitRareId=24061 },
    { color="blue",   name="Shifting (Agi+Stam)", id=32212, rare="Shifting Nightseye", rareId=24055 },
    { color="red",    label="Honor gem", name="Bold Ornate Ruby", id=28362 },
  },
  caster = {
    { color="meta",   name="Chaotic Skyfire Diamond", id=34220 },
    { color="red",    name="Runed (Spell Dmg)", id=32196, rare="Runed Living Ruby", rareId=24030 },
    { color="yellow", name="Reckless (SpDmg+Haste)", id=35760, rare="Reckless Noble Topaz", rareId=35316, hitName="Veiled (SpDmg+Hit)", hitId=32221, hitRare="Veiled Noble Topaz", hitRareId=31867 },
    { color="blue",   name="Glowing (SpDmg+Stam)", id=32215, rare="Glowing Nightseye", rareId=24056 },
    { color="red",    label="Honor gem", name="Runed Ornate Ruby", id=28118 },
  },
  healer = {
    { color="meta",   name="Insightful Earthstorm Diamond", id=25901 },
    { color="red",    name="Teardrop (Healing)", id=32195, rare="Teardrop Living Ruby", rareId=24029 },
    { color="yellow", name="Luminous (Heal+Int)", id=32219, rare="Luminous Noble Topaz", rareId=24060 },
    { color="blue",   name="Royal (Heal+MP5)", id=32216, rare="Royal Nightseye", rareId=24057 },
  },
  tank = {
    { color="meta",   name="Eternal Earthstorm Diamond", id=35501 },
    { color="red",    name="Bold (Str) / Subtle (Dodge)", id=32198, rare="Subtle Living Ruby", rareId=24032 },
    { color="yellow", name="Enduring (Def+Stam)", id=32223, rare="Enduring Talasite", rareId=24062 },
    { color="blue",   name="Solid (Stam)", id=32200, rare="Solid Star of Elune", rareId=24033 },
  },
  tankDruid = {
    { color="meta",   name="Powerful Earthstorm Diamond", id=25896 },
    { color="red",    name="Delicate (Agi)", id=32194, rare="Delicate Living Ruby", rareId=24028 },
    { color="yellow", name="Jagged (Crit+Stam)", id=32226, rare="Jagged Talasite", rareId=24067 },
    { color="blue",   name="Solid (Stam)", id=32200, rare="Solid Star of Elune", rareId=24033 },
  },
}

-- Best enchant per slot, by role (Wowhead-standard). Melee (str) verified vs a Fury
-- enchant guide; other roles are best-effort seeds. "-" = no common enchant for that slot.
-- vendor.rep = { requiredStanding, factionID... }. 6 = Honored, 7 = Revered,
-- 8 = Exalted. Faction ids verified against AtlasLootClassic's TBC tables.
-- Aldor (932) and Scryers (934) are listed together on purpose: they are the
-- either-or pair, and only the one you actually joined shows up in your
-- reputation pane, so whichever is found is the one that applies to you.
D.ENCHANTS = {
  melee = {
    { slot="Head",     ench="Glyph of Ferocity", id=29192, vendor={ rep={7,942}, map=1946, x=78.5, y=62.8, where="Cenarion Refuge, Zangarmarsh - Cenarion Expedition quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Vengeance (Aldor) / the Blade (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Greater Agility", spell=34004 },
    { slot="Chest",    ench="Exceptional Stats", spell=46502 },
    { slot="Bracer",   ench="Brawn (Str)", spell=27899 },
    { slot="Gloves",   ench="Major Strength", spell=33995 },
    { slot="Legs",     ench="Nethercobra Leg Armor", id=29535 },
    { slot="Boots",    ench="Cat's Swiftness", spell=34007 },
    { slot="Weapon",   ench="Mongoose / Executioner", spell=27984 },
    { slot="Ranged",   ench="Khorium Scope", id=23765 },
    { slot="Rings",    ench="Stats (Enchanter)", spell=27927 },
  },
  meleeDW = {
    { slot="Head",     ench="Glyph of Ferocity", id=29192, vendor={ rep={7,942}, map=1946, x=78.5, y=62.8, where="Cenarion Refuge, Zangarmarsh - Cenarion Expedition quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Vengeance (Aldor) / the Blade (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Greater Agility", spell=34004 },
    { slot="Chest",    ench="Exceptional Stats", spell=46502 },
    { slot="Bracer",   ench="Assault (AP)" },
    { slot="Gloves",   ench="Major Agility" },
    { slot="Legs",     ench="Nethercobra Leg Armor", id=29535 },
    { slot="Boots",    ench="Cat's Swiftness", spell=34007 },
    { slot="Weapon",   ench="Mongoose" },
    { slot="Ranged",   ench="Khorium Scope", id=23765 },
    { slot="Rings",    ench="Stats (Enchanter)", spell=27927 },
  },
  ranged = {
    { slot="Head",     ench="Glyph of Ferocity", id=29192, vendor={ rep={7,942}, map=1946, x=78.5, y=62.8, where="Cenarion Refuge, Zangarmarsh - Cenarion Expedition quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Vengeance (Aldor) / the Blade (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Greater Agility", spell=34004 },
    { slot="Chest",    ench="Exceptional Stats", spell=46502 },
    { slot="Bracer",   ench="Assault (AP)" },
    { slot="Gloves",   ench="Major Agility" },
    { slot="Legs",     ench="Nethercobra Leg Armor", id=29535 },
    { slot="Boots",    ench="Dexterity" },
    { slot="Ranged",   ench="Stabilized Eternium Scope" },
    { slot="Rings",    ench="Stats (Enchanter)", spell=27927 },
  },
  caster = {
    { slot="Head",     ench="Glyph of Power", vendor={ rep={7,1011}, map=1955, x=54.0, y=44.5, where="Shattrath, Lower City quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Discipline (Aldor) / the Orb (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Spell Penetration / Subtlety" },
    { slot="Chest",    ench="Exceptional Stats", spell=46502 },
    { slot="Bracer",   ench="Spellpower" },
    { slot="Gloves",   ench="Major Spellpower" },
    { slot="Legs",     ench="Runic Spellthread" },
    { slot="Boots",    ench="Boar's Speed" },
    { slot="Weapon",   ench="Soulfrost / Sunfire" },
    { slot="Rings",    ench="Spellpower (Enchanter)" },
  },
  healer = {
    { slot="Head",     ench="Glyph of Renewal", vendor={ rep={7,935}, map=1955, x=54.0, y=44.5, where="Shattrath - Sha'tar quartermaster, Terrace of Light (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Faith (Aldor) / the Oracle (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Subtlety" },
    { slot="Chest",    ench="Exceptional Stats", spell=46502 },
    { slot="Bracer",   ench="Superior Healing" },
    { slot="Gloves",   ench="Major Healing" },
    { slot="Legs",     ench="Mystic Spellthread" },
    { slot="Boots",    ench="Vitality" },
    { slot="Weapon",   ench="Major Healing" },
    { slot="Rings",    ench="Healing Power (Enchanter)" },
  },
  tank = {
    { slot="Head",     ench="Glyph of the Defender", vendor={ rep={7,989}, map=1446, x=65.0, y=49.5, where="Caverns of Time, Tanaris - Keepers of Time quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Warding (Aldor) / the Knight (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Steelweave (threat)" },
    { slot="Chest",    ench="Exceptional Health" },
    { slot="Bracer",   ench="Fortitude (Stam)" },
    { slot="Gloves",   ench="Major Strength", spell=33995 },
    { slot="Legs",     ench="Nethercleft Leg Armor" },
    { slot="Boots",    ench="Boar's Speed" },
    { slot="Weapon",   ench="Mongoose / Savagery" },
    { slot="Rings",    ench="Stats (Enchanter)", spell=27927 },
  },
  tankDruid = {
    { slot="Head",     ench="Glyph of Ferocity", id=29192, vendor={ rep={7,942}, map=1946, x=78.5, y=62.8, where="Cenarion Refuge, Zangarmarsh - Cenarion Expedition quartermaster (revered)" } },
    { slot="Shoulder", ench="Greater Inscr. of Warding (Aldor) / the Knight (Scryers)", vendor={ rep={8,932,934}, map=1955, x=54.0, y=44.5, where="Shattrath - Aldor/Scryer quartermaster on your faction's rise" } },
    { slot="Back",     ench="Greater Agility", spell=34004 },
    { slot="Chest",    ench="Exceptional Health" },
    { slot="Bracer",   ench="Fortitude (Stam)" },
    { slot="Gloves",   ench="Major Strength", spell=33995 },
    { slot="Legs",     ench="Nethercleft Leg Armor" },
    { slot="Boots",    ench="Boar's Speed" },
    { slot="Rings",    ench="Stats (Enchanter)", spell=27927 },
  },
}

-- role decides which cap bars we show:
--   "melee" / "meleeDW" -> Melee Hit(9%) + Expertise(26)
--   "ranged" -> Ranged Hit(9%)        "caster" -> Spell Hit(16%)
--   "healer" -> no hard cap           "tank"   -> Defense(490) + Hit + Expertise
--   "tankDruid" -> no def-cap (agility/resilience for uncrit)

D.classOrder = {"WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","WARLOCK","DRUID"}

D.classes = {

  WARRIOR = {
    tabSpec = {"Arms","Fury","Protection"},
    specOrder = {"Arms","Fury","Protection"},
    specs = {
      Arms = { role="melee",
        leveling = {"Hit","Crit","Strength","Attack Power","Stamina","Agility"},
        endgame  = {
          preraid = {"Hit","Expertise","Crit","Strength","Attack Power","Haste"},
          endgame = {"Hit","Expertise","Crit","Armor Pen","Strength","Attack Power","Haste"},
        },
        notes = "Crit above Strength (rage generation). Armor Pen becomes strong in raid gear (T6/SWP)." },
      Fury = { role="melee",
        weights = { strength=2.0, ap=1.0, crit=1.1, hit=1.3, expertise=1.2, haste=0.8, agility=0.6, stamina=0.1, armor=0.01, weaponDPS=5.0 },
        leveling = {"Hit","Crit","Strength","Attack Power","Stamina","Agility"},
        endgame  = {
          preraid = {"Hit","Expertise","Crit","Strength","Attack Power","Haste"},
          endgame = {"Hit","Expertise","Crit","Armor Pen","Strength","Attack Power","Haste"},
        },
        notes = "Crit is king after caps (Flurry + 200% crit dmg). 1 Str = 2 AP. Armor Pen strong from T6/SWP. Precision auto-counted." },
      Protection = { role="tank",
        leveling = {"Stamina","Strength","Defense","Dodge","Block Value"},
        endgame  = {"Defense","Stamina","Armor","Dodge","Parry","Expertise","Hit","Block Value"},
        notes = "Uncrittable (490 def) first, then Stamina + Armor (EHP). Expertise before Hit for threat." },
    },
  },

  PALADIN = {
    tabSpec = {"Holy","Protection","Retribution"},
    specOrder = {"Holy","Protection","Retribution"},
    specs = {
      Holy = { role="healer",
        leveling = {"Intellect","Healing (Spell Power)","Spell Crit","MP5","Stamina"},
        endgame  = {"Healing (Spell Power)","Intellect","MP5","Spell Crit","Spell Haste"},
        notes = "Illumination turns crit into mana return. Balance throughput vs mana." },
      Protection = { role="tank",
        leveling = {"Stamina","Defense","Intellect","Spell Power","Strength"},
        endgame  = {"Defense","Stamina","Spell Power","Hit","Dodge","Expertise","Block Value","Intellect"},
        notes = "Uncrittable first, then reach uncrushable (avoidance+block). Threat is spell-based (Consecration/Holy Shield)." },
      Retribution = { role="melee",
        leveling = {"Strength","Crit","Hit","Attack Power","Stamina","Intellect"},
        endgame  = {"Hit","Expertise","Strength","Attack Power","Crit","Haste"},
        notes = "Precision (from Prot tree) hit is auto-counted. Str > AP (Two-Handed Spec + Blessing of Kings)." },
    },
  },

  HUNTER = {
    tabSpec = {"Beast Mastery","Marksmanship","Survival"},
    specOrder = {"Beast Mastery","Marksmanship","Survival"},
    specs = {
      ["Beast Mastery"] = { role="ranged",
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina","Intellect"},
        endgame  = {"Hit","Agility","Attack Power","Crit","Haste","Intellect"},
        notes = "Ranged hit cap 9% (~142 rating). Draenei racial gives the raid +1% hit (not in the bar)." },
      Marksmanship = { role="ranged",
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina","Intellect"},
        endgame  = {"Hit","Agility","Attack Power","Crit","Haste","Intellect"},
        notes = "Ranged hit cap 9%. Draenei +1% hit is a raid buff, not shown in the bar." },
      Survival = { role="ranged",
        weights = { agility=2.0, crit=1.1, hit=1.1, ap=0.8, haste=0.4, intellect=0.15, stamina=0.1, armor=0.01, weaponDPS=4.0 },
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina","Intellect"},
        endgame  = {"Agility","Crit","Hit","Attack Power","Haste","Intellect"},
        notes = "Agility is #1 (Expose Weakness debuffs boss armor for the raid). Surefooted lowers the hit cap; auto-counted." },
    },
  },

  ROGUE = {
    tabSpec = {"Assassination","Combat","Subtlety"},
    specOrder = {"Assassination","Combat","Subtlety"},
    specs = {
      Assassination = { role="meleeDW",
        weights = { agility=1.6, crit=1.1, ap=0.7, hit=1.3, expertise=1.0, haste=0.7, strength=0.5, stamina=0.1, armor=0.01, weaponDPS=5.0 },
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina"},
        endgame  = {"Hit","Expertise","Agility","Crit","Attack Power","Haste"},
        notes = "Crit above raw AP (Seal Fate turns crits into combo points). Precision auto-counted." },
      Combat = { role="meleeDW",
        weights = { agility=1.5, haste=1.2, crit=1.0, ap=0.7, hit=1.3, expertise=1.0, strength=0.6, stamina=0.1, armor=0.01, weaponDPS=5.0 },
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina"},
        endgame  = {"Hit","Expertise","Agility","Haste","Crit","Attack Power"},
        notes = "Haste above raw AP (Combat Potency energy procs from faster swings). Precision auto-counted." },
      Subtlety = { role="meleeDW",
        leveling = {"Agility","Crit","Hit","Attack Power","Stamina"},
        endgame  = {"Hit","Expertise","Agility","Haste","Crit","Attack Power"},
        notes = "Off-meta for PvE; raw Attack Power sits near the bottom." },
    },
  },

  PRIEST = {
    tabSpec = {"Discipline","Holy","Shadow"},
    specOrder = {"Discipline","Holy","Shadow"},
    specs = {
      Discipline = { role="healer",
        weights = { spellHaste=1.1, healing=1.0, spellPower=1.0, spellCrit=0.7, spirit=0.6, intellect=0.5, mp5=0.4, stamina=0.05 },
        leveling = {"Intellect","Healing (Spell Power)","MP5","Spell Crit","Spirit"},
        endgame  = {"Spell Haste","Healing (Spell Power)","Spell Crit","Spirit","Intellect","MP5"},
        notes = "Once geared, Spell Haste is the #1 throughput gain. Spirit (via IDS) beats MP5." },
      Holy = { role="healer",
        weights = { spellHaste=1.1, healing=1.0, spellPower=1.0, spellCrit=0.7, spirit=0.6, intellect=0.5, mp5=0.4, stamina=0.05 },
        leveling = {"Intellect","Healing (Spell Power)","MP5","Spell Crit","Spirit"},
        endgame  = {"Spell Haste","Healing (Spell Power)","Spell Crit","Spirit","Intellect","MP5"},
        notes = "Spell Haste #1 when geared. Crit gives Inspiration + Holy Concentration mana. Spirit > MP5." },
      Shadow = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Stamina","Spirit"},
        endgame  = {"Spell Hit","Spell Power","Spell Crit","Spell Haste","Intellect"},
        notes = "Shadow Focus hit is auto-counted (you'll need little gear hit). Misery you cast lowers it further." },
    },
  },

  SHAMAN = {
    tabSpec = {"Elemental","Enhancement","Restoration"},
    specOrder = {"Elemental","Enhancement","Restoration"},
    specs = {
      Elemental = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Stamina"},
        endgame  = {"Spell Hit","Spell Power","Spell Crit","Spell Haste","Intellect"},
        notes = "Nature's Guidance hit is auto-counted. Your Totem of Wrath adds +3% hit to the raid too." },
      Enhancement = { role="meleeDW",
        leveling = {"Agility","Crit","Hit","Attack Power","Intellect","Stamina"},
        endgame  = {"Hit","Expertise","Attack Power","Crit","Agility","Haste"},
        notes = "Nature's Guidance melee hit is auto-counted. Str/AP first, then Crit rating > Agility. White hits scale to 28%; dual wield." },
      Restoration = { role="healer",
        leveling = {"Intellect","Healing (Spell Power)","MP5","Spell Crit"},
        endgame  = {"Healing (Spell Power)","MP5","Intellect","Spell Crit","Spell Haste"},
        notes = "Chain Heal machine. MP5 + healing first." },
    },
  },

  MAGE = {
    tabSpec = {"Arcane","Fire","Frost"},
    specOrder = {"Arcane","Fire","Frost"},
    specs = {
      Arcane = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Spirit"},
        endgame  = {"Spell Hit","Spell Power","Intellect","Spell Crit","Spell Haste"},
        notes = "Arcane Focus hit is auto-counted (~6% from gear). Very mana hungry -> Intellect over Crit; talents already give plenty of crit." },
      Fire = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Spirit"},
        endgame  = {"Spell Hit","Spell Power","Spell Crit","Spell Haste","Intellect"},
        notes = "Crit-heavy (Ignite/Combustion). Little talent hit, so most of the 16% comes from gear." },
      Frost = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Spirit"},
        endgame  = {"Spell Hit","Spell Power","Spell Haste","Intellect","Spell Crit"},
        notes = "Elemental Precision hit is auto-counted. Frost gears Crit last (only when nothing better is available). Rarely raid meta but solid." },
    },
  },

  WARLOCK = {
    tabSpec = {"Affliction","Demonology","Destruction"},
    specOrder = {"Affliction","Demonology","Destruction"},
    specs = {
      Affliction = { role="caster",
        leveling = {"Spell Power","Stamina","Intellect","Spell Crit","Spell Hit"},
        endgame  = {"Spell Hit","Spell Power","Spell Haste","Intellect","Spell Crit"},
        notes = "Suppression (up to 10% hit) is auto-counted. DoTs can't crit and don't tick faster -> Crit is lowest; Spell Power scales DoTs hardest." },
      Demonology = { role="caster",
        leveling = {"Spell Power","Stamina","Intellect","Spell Crit","Spell Hit"},
        endgame  = {"Spell Hit","Spell Power","Spell Haste","Spell Crit","Intellect"},
        notes = "Frequent Shadow Bolt -> Haste above Crit. Often support/Felguard. Any Suppression points are auto-counted." },
      Destruction = { role="caster",
        leveling = {"Spell Power","Stamina","Intellect","Spell Crit","Spell Hit"},
        endgame  = {"Spell Hit","Spell Power","Spell Crit","Spell Haste","Intellect"},
        notes = "Crit strong (Ruin/Devastation). Dipping Suppression lowers the gear hit you need." },
    },
  },

  DRUID = {
    tabSpec = {"Balance","Feral (Cat)","Restoration"},
    specOrder = {"Balance","Feral (Cat)","Feral (Bear)","Restoration"},
    specs = {
      Balance = { role="caster",
        leveling = {"Spell Power","Intellect","Spell Crit","Spell Hit","Spirit","Stamina"},
        endgame  = {"Spell Hit","Spell Power","Spell Crit","Spell Haste","Intellect"},
        notes = "Balance of Power hit (up to 4%) is auto-counted. Moonkin aura helps the raid." },
      ["Feral (Cat)"] = { role="melee",
        weights = { agility=2.0, strength=1.0, ap=1.0, crit=0.9, hit=1.1, expertise=0.9, haste=0.5, stamina=0.1, armor=0.01, weaponDPS=0.2 },
        leveling = {"Agility","Strength","Crit","Hit","Attack Power","Stamina"},
        endgame  = {"Hit","Expertise","Agility","Strength","Attack Power","Crit"},
        notes = "Cat = DPS. 9% special cap first. Agility gives crit + dodge + AP. No melee hit talent." },
      ["Feral (Bear)"] = { role="tankDruid",
        leveling = {"Stamina","Agility","Strength","Attack Power"},
        endgame  = {"Stamina","Agility","Armor","Hit","Expertise","Dodge","Attack Power"},
        notes = "Bears do NOT use defense for uncrit -> rely on agility/resilience. Stamina + armor is king." },
      Restoration = { role="healer",
        leveling = {"Intellect","Healing (Spell Power)","MP5","Spell Crit"},
        endgame  = {"Healing (Spell Power)","MP5","Intellect","Spell Haste","Spell Crit"},
        notes = "HoT machine (Lifebloom/Rejuv). Healing + haste (faster HoT ticks)." },
    },
  },
}
