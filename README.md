# StatCoach

**Live stat-priority, cap coach and cap-aware gear compare — one addon, two flavors: Burning Crusade Classic (Anniversary, 2.5.x) and retail.**

StatCoach reads your class, spec and level *live* and tells you which stats to favour right now, how far you are from the caps that actually matter, and whether the item under your cursor is a real upgrade — using cap-aware math instead of Pawn's flat weights.

---

## What it does

- **Priority list, live.** Detects your class/spec (most-points talent tab on TBC, the real spec on retail) and shows the correct stat order for your current context. Stats you've already capped sink to the bottom so the top of the list is always what to chase next.
- **Cap coach.** Bars for the caps that matter to your role — Melee/Ranged special hit (9%), Spell hit (16%), Expertise (26 skill), Tank Defense (490) — showing your current value and how much rating you still need. **Talent and racial hit are read from your live character**, so the "to cap" number is true for *your* build, not a generic table.
- **Trade advisor.** A one-line "NOW:" call on what to favour or trade toward this moment (e.g. *"Below Hit cap — favour Hit, even trading AP for it"* → *"Hit capped. Now favour Expertise"*).
- **Cap-aware gear compare.** Hover any item and StatCoach adds one line to the tooltip — it only speaks up on **upgrades** (percent gain), staying quiet on sidegrades and downgrades. It parses the real tooltip, so it counts **socketed gems and Equip effects** that stat-only addons miss, is **armor-type aware**, and scores **weapon DPS by role** (a warrior's bow is a stat-stick, not a weapon).
- **Bag upgrade badge.** A green `+` (or gold `++` for a big jump) on bag items that beat what you're wearing. Works in Baganator, Bagnon and the default bags.
- **Gems & Enchants popups.** Per socket colour and per slot, with real in-game icons and the Wowhead-standard choice for your spec (plus a cheaper alternative while leveling/pre-raid).
- **3-tier context (TBC).** Leveling → Pre-raid → Endgame, switchable, because the right priorities change as you gear up.
- **Movable window**, minimap button, ESC to close, adjustable scale, and a right-click settings menu.

## Why it's different from Pawn

Pawn multiplies each stat by a fixed weight. StatCoach knows your **caps** and your **live character**: once you're hit-capped, more hit is worth ~0 and the score reflects that instantly. It answers *"which stat should I favour or trade toward now?"* — a question a flat weight can't. The two work well side by side.

## Usage

| Command | Effect |
|---|---|
| `/statcoach` or `/stc` | Toggle the window |
| `/stc reset` | Reset window position |
| `/stc tooltip` | Toggle the tooltip upgrade line |
| `/stc bag` | Bag-badge diagnostic |
| `/stc minimap` | Show/hide the minimap button |

- **Left-click** the minimap button to toggle the window; **right-click** for settings; **drag** to move it.
- Click the **"i"** button in the window for spec and cap notes.

## Install

Drop the `StatCoach` folder into your client's AddOns directory:

```
World of Warcraft\_anniversary_\Interface\AddOns\      (Burning Crusade Classic)
World of Warcraft\_retail_\Interface\AddOns\           (retail)
```

Then `/reload` or restart the client. Requires an **English client** (talent names and tooltip parsing are English).

Released builds are on [CurseForge](https://www.curseforge.com/wow/addons/statcoach) and [Wago](https://addons.wago.io/addons/statcoach) as separate TBC and retail packages.

## Repository layout

One source tree serves both flavors. The client picks its own TOC:

| File | Used by |
|---|---|
| `StatCoach.toc` | TBC Classic (`## Interface: 20506`) |
| `StatCoach_Mainline.toc` | Retail (`## Interface: 120007, 120100`) |
| `StatCoach.lua` | All logic, both flavors |
| `StatCoachData.lua` | TBC data: 27 specs, caps, gems, enchants |
| `StatCoachData_Retail.lua` | Retail data: 39 specs, loaded only by the Mainline TOC |
| `Libs/` | LibStub, CallbackHandler, LibDataBroker, LibDBIcon (minimap button) |

The retail TOC loads both data files; the TBC TOC loads only `StatCoachData.lua`, so retail data never reaches a Classic client.

## Contributing

Pull requests are welcome — bug fixes, spec-data corrections and integrations especially.

A few things worth knowing before you open one:

- **Say what you measured.** Stat priorities and cap numbers in this addon are meant to be verifiable. A PR that changes a number is much easier to merge with a source or an in-game reading attached.
- **Both flavors.** If a change touches shared logic in `StatCoach.lua`, say which client(s) you tested it on. A retail-only API will break the Classic client and vice versa.
- **Keep it English.** UI strings and code are English throughout.
- **One idea per PR.** Easier to review, easier to revert.

Open an issue first if you want to discuss a larger feature before building it.

## Notes

- Stat priorities for all 27 TBC specs are cross-checked against Wowhead, Icy Veins and Warcraft Tavern guides; retail covers all 39 specs.
- Stat *weights* for gear scoring are a curated first pass — tuned per role/spec and improving over time.
- The only bundled libraries are LibStub, CallbackHandler, LibDataBroker and LibDBIcon, all embedded under `Libs/`. No other dependencies.

## Licence

All rights reserved. The source is public so it can be read, discussed and improved through pull requests; it is not licensed for redistribution or for republishing as a separate addon.
