# StatCoach - Changelog


---

# StatCoach 1.1.21 (Retail)

*9 September 2026*

## Enchant icons are back

Every enchant row in the window had worn the same generic icon since 12.0 moved
spell textures to a new place. Each row shows its own spell icon again.

## /stc stats runs to the end again

The stat-pattern report stopped before it started on 12.0, and once past that it
could fail on an equipped item with an empty socket. Both are fixed: the report
runs through and prints every pattern.

---

# StatCoach 1.1.20 (Retail)

*1 September 2026*

## Gear locked to another class is silent now

An item that says "Classes: Paladin" scored like any other piece, so a warrior
browsing gear saw upgrade badges on things only a paladin can wear. Items locked
to a class that is not yours now show nothing anywhere - no badge, no verdict.
Works in every language, and gear your class genuinely shares is untouched.

## The verdict line got its own colours

The upgrade line used to borrow the tooltip's own colours - green like every
"Equip:" bonus, gold like every line the client highlights itself - and drowned in
them. It now speaks in colours nothing else in a tooltip uses: the StatCoach name
in mint, solid upgrades in mint-green, strong upgrades in amber. Big upgrades keep
their purple, and the meaning of each tier is unchanged - only the visibility.

The tier icon also moved to the END of the line on every verdict, so all lines read
the same way: the words and the percent first, the icon closing the line.

## Less clutter in the main window

The Context button never did anything on retail - there are no leveling or
endgame tiers to switch between - so it only restated the obvious and ignored
every click. It is gone now, along with the empty button row it sat on. The
PRIORITY header also no longer repeats what the title line already says.

---

# StatCoach 1.1.20 (TBC)

*26 August 2026*

## Hotfix: items with empty sockets broke the bag view

1.1.19 could fail on any item that has an empty socket. With Baganator installed
the bag window came up completely empty; on the default bags and in tooltips the
upgrade line simply stopped appearing. Fixed - and the badge is now walled off from
Baganator's layout entirely, so a fault in StatCoach can never take a bag addon
down with it again.

Everything 1.1.19 added is unchanged and working: the gem hint on empty sockets,
the epic/rare gem split, and its switch in the minimap menu.

---

# StatCoach 1.1.19 (TBC)

*26 August 2026*

## Empty sockets answer their own question

An empty socket says "Red Socket" and leaves it there. Now the gem you should put
in it stands on the same line, in the tooltip's own right-hand column - just the
gem's name, no extra lines and no icons. Red, yellow, blue and meta each get the
stone your role wants, and while you are still under the hit cap the yellow socket
asks for the hit gem instead, switching back on its own once you are capped.

**The gem matches the item.** An epic piece is worth an epic stone; anything below
epic is pointed at the affordable cut of the same gem instead - a Living Ruby
rather than a Crimson Spinel - because nobody should spend a raid's worth of gold
gemming a blue they replace next week.

It appears where there is something to gem for - on items worth taking - and
nowhere else, so browsing an auction house does not turn into a wall of gem
names. **Right-click the minimap button → Gem hint on empty sockets** turns it
off, and it has its own switch: the verdict line and the socket hint answer
different questions, so turning one off leaves the other alone.

## A mislabelled gem

The bear druid's yellow socket recommended "Jagged (Agi+Stam)". Jagged is critical
strike and stamina - a green gem cannot carry agility at all. The stone itself was
the right one to socket; only its label was wrong, and it now says so.

---

# StatCoach 1.1.18 (TBC)

*24 August 2026*

## The verdict line got its own colours

The upgrade line used to borrow the tooltip's own colours - green like every
"Equip:" bonus, gold like every line the client highlights itself - and drowned in
them. It now speaks in colours nothing else in a tooltip uses: the StatCoach name
in the Coach series' mint, solid upgrades in mint-green, strong upgrades in amber.
Big upgrades keep their purple, and the meaning of each tier is unchanged - only
the visibility.

The tier icon also moved to the END of the line on every verdict, so all lines read
the same way: the words and the percent first, the icon closing the line.

## Weapons know whose business they are

With GearCoach installed, a weapon at level 70 is judged by which spec it is built
for. Your own spec's weapon kinds are judged on stats exactly as always. A kind that
belongs to ANOTHER spec of your class - a two-hander in a dual-wielder's bags -
still gets its verdict, but that spec's icon opens the line, so one glance says
whose upgrade it is; it never gets a glowing badge in your bags. A kind no spec of
your class uses - a dagger, for a warrior - shows nothing at all.

Below level 70 nothing changes, and without GearCoach nothing changes anywhere.

---

# StatCoach 1.1.17 (TBC)

*21 August 2026*

## Vendor badges grow up when GearCoach is around

At a vendor, "is this bigger than what I am wearing" is the wrong question - a fresh
70 answers yes to everything, and the window drowns in badges. With GearCoach
installed, StatCoach now hands the vendor over to a curated view: a skull on your
actual best-in-slot, a gold + on the road there, and StatCoach's own badge capped at
a **green +** that only appears on armor that genuinely beats what you have on.
Weapons never get the green + at a vendor - if a weapon is right for your spec, the
list marks it; if it is not, no stat total makes it right.

Without GearCoach nothing changes anywhere: vendor badges keep the usual tiers, and
every other surface - bags, quests, loot, mail, trade - is untouched either way.

## Honor gems in the gem window

The GEMS window gained an "Honor gem" row: the stone worth buying with honor
instead of gold - one for the physical roles, one for the casters. Good stones,
paid in a currency a fresh 70 is already earning. The healer and tank lists are
unchanged - the honor vendor sells nothing that fits them.

## Gear locked to another class is silent now

An item that says "Classes: Paladin" scored like any other plate, so a warrior
browsing a vendor saw upgrade badges on gear only a paladin can wear. Items locked
to a class that is not yours now show nothing anywhere - no badge, no verdict.
Works in every language, and gear your class genuinely shares is untouched.

## Badges stop shouting about gear you already own

At a vendor, the skull and the gold + only mark pieces you are still missing.
Buy the belt, and the belt goes quiet - what you are wearing, carrying, or have
in the bank no longer gets sold to you.

And when the piece you are wearing in a slot is itself on your list, the green +
stays away from that slot entirely. PvP gear spends half its budget on stamina
and resilience, which a damage score prices at nothing - so a plain stat-stick
could read as an "upgrade" over the belt you deliberately bought. The list's
choice outranks the math.

## GearCoach can now ask about enchants

If you also run GearCoach, its gear lists show the right enchant on every row -
answered by StatCoach, which knows your build and where each enchant is bought.

## Two open popups no longer blend into each other

The GEMS, ENCH and notes windows open at the same spot, and two at once used to
interleave into one unreadable mess. Whichever you open - or click - now sits on
top of the other.

## Less repetition in the main window

The context ("Endgame", "Pre-raid") already stands in the title line and on the
Context button, so the PRIORITY header no longer repeats it a third time - and the
priority list says "Hit", not "Hit (to cap)", because the cap bars right below
carry the caps with live numbers.

---

# StatCoach 1.1.16 (Retail)

*20 August 2026*

## Gear your class cannot wear is no longer called an upgrade

StatCoach would tell a mage that a mail chestpiece was a big upgrade. The score leans hard
on item level, so a high-level piece the character can never put on beat the cloth it was
being measured against every single time.

Armour above your own armour type is now silent everywhere: no verdict in the tooltip, no
badge, no number at all. Below it nothing changes - a warrior is still shown cloth and
leather with the usual scoring penalty, because a warrior can genuinely wear them and
sometimes should.

Shields and weapons follow the same rule. A shield with intellect on it looks excellent to
a mage right up to the moment they try to equip it, and a two-handed axe is not a mage
upgrade at any item level.

## Upgrade badges beyond your bags

The glowing badge that marks an upgrade in your bags now also appears on quest rewards,
in the merchant window, on mail attachments, and on the other side of a trade - the
places where you decide whether an item is worth taking before it is yours.

## The settings menu grew up

**Right-click the minimap button.** Everything that used to be buried in slash commands
nobody finds now lives there:

- **Flag upgrades above** - how small an upgrade is still worth a badge: anything, 5%,
  10%, or big upgrades only. In good gear almost everything is a rounding error; while
  gearing up you want to see all of it. The score is unchanged either way, this is only
  how low StatCoach will open its mouth.
- **Show badges in** - each badge surface has its own switch, so you can keep the ones
  you use and silence the rest.
- **Pulse the badge** - off leaves the badge sitting still.
- **Badge size** and **tooltip icon size**.
- **Hide off-type armour entirely** rather than scoring it down.

Every one of them takes effect immediately, including on badges already on screen.

## The tooltip and the badge finally agree

The tooltip verdict used a gold arrow for both upgrade tiers, so a green "UPGRADE (+2%)"
came with a gold icon beside it while the badge on the item showed a green "+". The
tooltip now uses the same "+" and takes the tier colour with it.

## "Lock window" is gone

It locked the main window and nothing else - the popups stayed draggable - so a setting
people turned on to stop moving things by accident did not actually do that. The window
remembers where you put it anyway.

## Diagnostics clean up after themselves

`/stc stats` leaves a snapshot behind so it can be read back. It is now cleared at your
next login instead of staying on disk forever.

---

# StatCoach 1.1.16 (TBC)

*19 August 2026*

## Gear your class cannot wear is no longer called an upgrade

StatCoach would happily tell a mage that a mail chestpiece was a big upgrade. Every piece
was scored on its stats and its armour, and mail carries plenty of both, so gear the
character can never put on came out ahead of the cloth it was being measured against.

Armour above your own armour type is now silent everywhere: no verdict in the tooltip, no
badge in your bags, no number at all. Below it nothing changes - a warrior is still shown
cloth and leather with the usual scoring penalty, because a warrior can genuinely wear
them and sometimes should.

Levels count as well. A hunter at 39 has not learned mail yet, and a warrior at 39 has not
learned plate, so both stay quiet until the level that unlocks them.

## Shields and weapons follow the same rule

A shield with spell power on it looks excellent to a mage, right up to the moment they try
to equip it. Shields are now silent for the classes that never get to hold one.

Weapons work the same way: no more axes for mages, no maces for hunters, no daggers for
paladins, no two-handers for rogues, no wands for warriors. A weapon type you simply have
not been to a weapon master for yet is unaffected - untrained is not the same as never, so
those still get their verdict.

---

# StatCoach 1.1.15 (Retail)

## Upgrade badges show up where items do

The glowing badge that marks an upgrade in your bags now appears wherever an item is
offered to you: quest rewards, the merchant window, loot, loot rolls, the bank, mail
attachments, auction results, the other side of a trade, and AtlasLoot's lists.

**Right-click the minimap button → Show badges in** to switch off any of them you would
rather keep quiet. Every surface is listed separately, and everything is on until you say
otherwise.

## The settings menu grew up

Also under the right-click menu, and no longer buried in slash commands nobody finds:

- **Flag upgrades above** - how small an upgrade is still worth a badge: anything, 5%,
  10%, or big upgrades only. In good gear almost everything is a rounding error; while
  gearing up you want to see all of it. The score is unchanged either way, this is only
  how low StatCoach will open its mouth.
- **Pulse the badge** - off leaves the badge sitting still.
- **Badge size** and **tooltip icon size**.
- **Hide off-type armour entirely** rather than scoring it down.

Every one of them takes effect immediately, including on badges already on screen.

## The tooltip and the badge finally agree

The tooltip verdict used a gold arrow for both upgrade tiers, so a green "UPGRADE (+2%)"
came with a gold icon beside it while the badge on the item showed a green "+". The
tooltip now uses the same "+" and takes the tier colour with it.

## "Lock window" is gone

It locked the main window and nothing else - the popups stayed draggable - so a setting
people turned on to stop moving things by accident did not actually do that. The window
remembers where you put it anyway.

## Diagnostics clean up after themselves

`/stc stats` leaves a snapshot behind so it can be read back. It is now cleared at your
next login instead of staying on disk forever.

---

# StatCoach 1.1.15 (TBC)

## The cap bars pick the right stat on non-English clients

The last piece of the localisation work in 1.1.14, and the smallest.

Hovering a stat row on the character sheet appends the cap bars that row is about - hit
caps on Hit Rating, defense and avoidance on Armor, and so on. Which bars to show was
decided by reading Blizzard's own tooltip and looking for English words in it, so on any
other client no row matched: base stats got a cap block they have no use for, and every
other row showed the full set of bars instead of the one you asked about.

The words now come from the game itself. Nothing is removed - the English words are still
checked alongside - so an English client behaves exactly as it did before.

This one never showed a wrong number. It showed too many correct ones, which is why it
waited for its own release.

## Upgrade badges everywhere items show up

The glowing badge that marks an upgrade in your bags and on quest rewards now appears
wherever an item does:

- **Loot rolls** - need or greed, on a timer, with three people waiting. The shortest
  decision in the game now answers itself without hovering.
- **The merchant window** - deciding whether a vendor's list beats what you are wearing
  used to mean hovering every line.
- **The loot window**, **the bank**, **mail attachments**, **auction house results**, and
  **the other side of a trade**.
- **The crafting window** - standing at the anvil with the mats already in your bags is a
  decision, and this expansion is full of crafted gear worth wearing.
- **AtlasLoot** dungeon and raid lists, so a loot table shows at a glance which lines are
  worth reading.

All of them draw the same badge through one shared piece of code, so they cannot drift
apart from each other or from the bags.

## You decide where they show up

**Right-click the minimap button → Show badges in**, and switch off any surface you would
rather keep quiet. Every one is listed separately and everything is on until you say
otherwise, so a surface added in a later version never arrives silently disabled.

Switching one takes effect at once in both directions, without waiting for the window to
redraw. The checkbox above it is the master switch for all of them -
it used to be called "Bag upgrade badge", which stopped being true once badges appeared
anywhere other than bags.

## How much StatCoach talks is now yours to set

**Flag upgrades above** decides how small an upgrade is still worth a badge: anything,
5%, 10%, or big upgrades only. In raid gear almost everything is a rounding error and you
want the last option; while levelling you want the first. The score is unchanged either
way - this is only how low the addon will open its mouth.

Also in the menu, and no longer buried in slash commands nobody finds:

- **Pulse the badge** - off leaves the badge sitting still, for people who would rather
  the interface held still too.
- **Badge size** and **tooltip icon size**.
- **Hide off-type armour entirely** rather than scoring it down.

What is deliberately *not* in there: the stat weights and the caps. Knowing where TBC's
caps sit, and scoring a capped stat at nearly nothing without being told to, is the whole
point of the addon. Pawn already exists for tuning weights, and a StatCoach whose numbers
you can break is just a worse Pawn.

## Sockets now say what they are worth

An item with empty sockets reads as what it becomes once they are filled - that is the
version you will actually wear, and nobody leaves sockets empty. The verdict says so:

```
BIG UPGRADE  (+37%)   (once gemmed)
```

The number itself was never the problem. The credit was **one-sided**: your equipped item
was scored with its real gems, printed in its own tooltip, while a candidate was credited
for gems you do not own. Both sides are now scored the same way, which turns it into a
fair fight rather than your real gear against a candidate's wishful thinking.

A socket is still counted at 70% of a gem, and now that the assumption is stated the
discount has an honest job: you do not own them yet, and the estimate assumes the *best*
gem in every hole, which nobody actually does - people gem for the socket bonus, or buy
the cheaper cut.

Items without sockets are unaffected, and the badge and the tooltip take their number from
the same place, so they can never name different tiers for the same item.

## The tooltip and the badge finally agree

The tooltip verdict used a gold arrow for both upgrade tiers, so a green "UPGRADE (+2%)"
came with a gold icon next to it while the badge on the item showed a green "+". The
tooltip now uses the same "+" and takes the tier colour with it.

The glow and the pulse stay on the badge. A tooltip line is static text, so nothing can
animate inside it.

## The enchant list says whether you can actually buy it

Every vendor enchant in this expansion sits behind a reputation, and knowing where the
quartermaster stands is no use if you are not welcome there. Hovering an enchant now says
which side of that you are on:

- *You can buy this now (Cenarion Expedition - Revered)*
- *Needs Exalted with The Aldor - you are Honored*
- *Needs Exalted - you have not joined either faction yet*

Aldor and Scryers sort themselves out. The lookup reads your reputation pane rather than
asking by id, and the pane only lists factions you actually have - so whichever of the two
turns up is the one that applies to you, without the addon ever having to ask which side
you picked.

The enchant names themselves are left alone. Several are long enough to wrap already, and
a marker in front of every row buys a glance at the cost of the thing you came to read.

## "Lock window" is gone

It locked the main window and nothing else - the gem, enchant and notes popups stayed
draggable - so a setting people turned on to stop moving things by accident did not
actually do that. Half a lock is worse than none, and the window remembers where you put
it anyway.

## Diagnostics clean up after themselves

`/stc stats` and `/stc globals` leave a snapshot behind so it can be read back. It is now
cleared at your next login instead of staying on disk forever.

---

# StatCoach 1.1.14 (TBC)

## StatCoach works on non-English clients

1.1.13 fixed the retail spec lookup. This release is the same class of bug, five more
times over, on the classic side - and here it was not showing nothing, it was quietly
showing the **wrong numbers**, which is worse.

StatCoach was reading the game's **text** and matching it against English words. The game
answers in the client's own language, so on any other client:

- **The gear compare scored every item as if it had no stats.** Item stats were read by
  parsing the tooltip for hand-written English phrases like "Improves hit rating by". Not
  one of them matched, so upgrade percentages were meaningless. Those patterns are now
  built at load from the game's **own** wordings, so they read whatever language the
  client speaks.
- **Talent hit read zero.** Precision, Nature's Guidance, Surefooted, Suppression, Shadow
  Focus, Arcane Focus, Elemental Precision and Balance of Power all counted for nothing.
  They count now.
- **Draenei aura hit was missed.** Heroic Presence and Inspiring Presence now count.
- **Weapon-skill racials were missed**, so human, orc, dwarf and troll players were shown
  the standard hit and expertise caps instead of their lower racial ones.
- **Armor type was not recognised**, so a leather piece could be called an upgrade for a
  plate class.

The caps one mattered most day to day: the bar looked completely normal, it was just
pointing at the wrong number.

## Shamans were given the mage's Elemental Precision

Found while fixing the above, and this one affected **English clients too**.

Mage and shaman both have a talent called Elemental Precision, and they are not worth the
same: 1% spell hit per rank for a mage, 2% for a shaman. Because talents were looked up by
name there was only one entry for both, and shamans got the mage's value - half their real
talent hit, which pushed the spell hit cap bar too far to the left.

An elemental shaman with three points in it now reads 6% instead of 3%.

## Feral attack power is no longer counted as attack power

A side effect of reading the game's wordings rather than approximations of them. The old
pattern stopped at "Increases attack power by 40", which also matched "Increases attack
power by 40 **in Cat, Bear, Dire Bear, and Moonkin forms only**" - so a druid's feral AP
was scored as if it applied in every form. The game's own wording ends in a full stop,
which the feral line does not have, so the two no longer collide.

## Nothing changed for English clients, and that is checked

Every equipped item is read twice - once with the new patterns, once with the old English
ones - and the two agree on every number across a full set of gear. `/stc stats` runs that
comparison yourself: green where the two agree, red with the stat named where they do not.

Weapon DPS is still read from the tooltip, but its line is now found via the game's own
wording too. One line has no wording to build from - the flat "39 Block" on shields - and
stays English until Blizzard ships a string for it.

---

# StatCoach 1.1.13 (Retail)

## Non-English clients now find their spec

On any client that is not in English, the retail panel could not match your
specialization and showed no spec data at all — no priority list, no advice. It now
detects your spec correctly in every client language.

If you play on an English client, nothing changes for you.

## Devourer Demon Hunter added

Midnight's third Demon Hunter spec had no entry and fell through to "no data". It is in
now: Haste first, then Mastery, with Crit and Versatility behind — and it is the only
Demon Hunter spec that scales with Intellect rather than Agility.

Its guide states a rating target, so the bar carries a tick at **800 Haste**: past that
point the guide puts Crit and Mastery ahead of more Haste.

That takes StatCoach to 40 retail specs.

---

# StatCoach 1.1.12 (Retail)

## YOUR SECONDARIES now answers "how far to go", not just "what I have"

Retail has no hard caps, but it has the next best thing: diminishing returns on
secondary rating. At level 90 that line sits at Haste 1320, Crit 1380, Mastery 1380,
Versatility 1620 — rating past it buys 10% less, and each further bracket another 10%,
down to -50%.

Each bar now runs from 0 to its stat's threshold:

- **Blue** = under the line, **gold** = first bracket (-10%), **red** = deeper.
- The right side shows your rating against the threshold ("810 / 1380"), or how far over
  and at what penalty ("1720 (+340, -10%)").
- Where a spec's guide states a **rating target**, a tick marks it on the bar and the
  label says so: Subtlety Rogue Haste ~1100 (raid) / ~700 (M+), Elemental Shaman Mastery
  to 1200. No other spec gets a target, because no other guide states one.
- The **NOW** line uses the same numbers: "Haste is past its DR (+340 rating) — each
  point there buys 10% less", or "Haste target (raid): 290 rating to go".

The bars still order themselves by your spec's priority, and the "i" note explains the
ladder with the actual numbers.

## Character sheet: hover Crit / Haste / Mastery / Versatility

Hover a secondary on the paperdoll and the tooltip grows the stat's bar, your rating
against the line, a plain sentence about what that means, and the guide target where one
exists. Other stats stay untouched.

## MANUAL mode works on retail — browse all 13 classes and 39 specs

MANUAL lets you look at any spec's stat priority without being that spec. The Class and
Spec buttons now walk the full retail roster, the header says which spec you are looking
at, and AUTO snaps you back to your own. Switching class always lands on a real spec of
that class.

## The minimap button moves freely

- **Drag it anywhere around the minimap.** Round or square, it follows the shape
  instead of being locked to a circle.
- **Button collectors pick it up** out of the box.
- **Round icon, no brass ring.**
- Right-click still opens the settings menu; **`/stc minimap`** or the menu hides the
  button, and the same command brings it back.
- **StatCoach is in the Addon Compartment** at the top of the minimap, so hiding the
  button never loses you the way in.
- Your saved position carries over the first time you log in.

## Small thing

The hover tooltip on the AUTO / MANUAL button is gone — the button says what it does.

Stat priorities are unchanged from 1.1.11: all 39 specs still match their guides.

---

# StatCoach 1.1.12 (TBC)

## The minimap button moves freely

- **Drag it anywhere around the minimap.** Round or square, it follows the shape
  instead of being locked to a circle.
- **Button collectors pick it up** out of the box.
- **Round icon, no brass ring** — it takes up far less of the minimap.
- Right-click still opens the settings menu; **`/stc minimap`** or the menu hides the
  button, and the same command brings it back. `/stc` opens the window either way.
- Your saved position carries over the first time you log in.

## Small thing

The hover tooltip on the AUTO / MANUAL button is gone — the button says what it does.

Stat priorities, caps and gear scoring are unchanged from 1.1.11.

---

# StatCoach 1.1.11 (Retail)

Season 2 stat priorities. Retail-only release — nothing in this build changes TBC, so
there is no 1.1.11 for the Classic file.

## 20 of 39 specs changed stat order

All 39 specs have been re-read from the Wowhead class guides for Season 2.

| spec | was | now |
|---|---|---|
| Fury Warrior | Mastery, Haste, Vers, Crit | **Haste, Mastery, Crit, Vers** |
| Arcane Mage | Mastery, Vers, Crit, Haste | **Haste, Mastery, Crit, Vers** |
| Blood DK | Crit, Vers, Mastery, Haste | **Haste, Mastery, Crit, Vers** |
| Destruction Warlock | Crit, Haste, Mastery, Vers | **Haste, Mastery, Crit, Vers** |
| Augmentation Evoker | Crit, Haste, Mastery, Vers | **Mastery, Crit, Haste, Vers** |

If an item stopped being recommended after this update, that is why — the stat behind it
moved down your spec's list.

## Where the numbers come from

Every spec is taken from its own Wowhead **stat-priority page**, not from the one-line
summary on the BiS pages. Those two sources disagree for six specs, and the BiS one-liner
is the one that is wrong — it cost Protection Warrior, Protection Paladin, Unholy,
Guardian, Restoration Druid and Vengeance a wrong order before it was caught. Each of the
39 entries was then read back out of the addon and diffed against the source; all 39 match.

## Ties are now stated instead of hidden

The guides mark some stats as equal to each other, and StatCoach has to store *some*
order. Where that happens, the note now says so — for example Enhancement reads
"Mastery and Haste are equal on top", and Brewmaster "Versatility, Crit and Mastery are
all equal; Haste last". Previously the notes stayed silent and the arbitrary order looked
like a real ranking.

Two specifics worth calling out:

- **Blood DK** genuinely splits by hero talent: San'layn wants Haste first, Deathbringer
  wants Crit first and Haste last. The note says both; the stored order is San'layn.
- **Elemental Shaman** wants Mastery only up to about 1200 rating, then Haste and Crit.

Item level still outweighs stat order in nearly every case, and Raidbots remains the real
answer for your character.

---

# StatCoach 1.1.10 (TBC)

_(Shipped as 1.1.10 on 11 Aug 2026. There is no TBC 1.1.11 - the 1.1.11 release is retail-only.)_

## Scoring fix: off-type armor was counted twice

Since 1.1.8 armor has a real weight in the score, which means the armor you give up by
wearing leather on a plate class is already priced in. The old flat 10% penalty on
off-type armor counted that same loss a second time — and because it applied to your
**equipped** item as the baseline, it quietly made same-armor-class candidates look
about 10% better than they were.

Found in a real case: plate tank shoulders (parry, no crit, no hit) scored "+2% upgrade"
over strictly better leather DPS shoulders on a hit-capped Fury warrior. They now
correctly score as a downgrade and stay silent.

If you never want off-type armor suggested at all, that is what `/stc armor` is for —
unchanged.

## Cap tooltips stay where they belong

The live cap bars appeared on the Reputation, Skills and PvP tab buttons as well as on
the stat rows — those buttons live inside the character frame, so they passed the old
check. The tooltip block is now tied to the stat rows themselves.

---

# StatCoach 1.1.9 (Retail)

## Upgrade badges - bigger, everywhere, impossible to miss

- **Bag badges no longer require Baganator**: they now draw directly on Blizzard's
  default bags too. (Custom bag addons are not covered yet -
  tooltip verdicts work everywhere regardless.)
- **Quest reward badges - new**: the badge appears directly on quest reward buttons, both
  at the NPC and in the quest log, so you see the right pick before you choose.
- The badge itself is **bold, glowing and pulsing**: damage-number font, colour-matched
  star-burst glow, and a slow actionbar-proc pulse. Same tiers as the tooltip verdict:
  green + (solid), gold + (10%+), purple skull (25%+). Size: `/stc badge 10-30`.

## New options

- **Strict armor filter** (`/stc armor`): by default off-type armor is shown with a scoring
  penalty; toggle strict and it disappears from verdicts and badges entirely. Applies to
  every armor class including Monk, Demon Hunter and Evoker.
- **Upgrade icon size** (`/stc icon 10-30`): the arrow/skull on tooltip verdicts, sized
  your way (default 14).

*(The live cap bars added in this version are a TBC feature - retail has no hit/expertise/
defense caps, so nothing changes on your character sheet here.)*

---

# StatCoach 1.1.9 (TBC)

## Live cap bars on your character sheet - new

- Hover a combat stat on the character pane and **real, coloured progress bars appear
  right in the tooltip**: green = capped, gold = getting close, red = far off. One glance,
  no reading required.
- The bars are context-aware: hovering Hit shows your hit caps, Expertise shows expertise,
  Defense/Dodge/Parry/Block show the tank caps - and stats with no cap (Crit, Damage,
  Power...) show the full overview. Base stats stay clean, and a defensive stat on a spec
  with no defensive caps shows nothing instead of noise.
- Specs without hard caps (healers) get an honest one-liner instead of silence.

## Two new cap bars

- **Uncrushable (tanks): the famous 102.4%.** Miss + dodge + parry + block against a boss,
  live, with the 2.4% boss-skill penalty already deducted. Passive gear value only -
  Shield Block / Holy Shield uptime is your rotation's job.
- **Feral uncrit: 5.6% crit reduction** via resilience + defense above 350. Feral tanks
  previously saw "no hard caps" - they have exactly one, and now it has a bar.

## Cap corrections - please read

- **Dual-wield white cap corrected: 24% -> 28%.** 24% is the equal-level number; against
  a +3 boss the white miss is 9% base + 19% dual-wield penalty. Scoring, advice text and
  the cap bar all use the corrected number.
- **Weapon-skill racials are now counted.** Human (swords/maces), Orc (axes), Dwarf (guns)
  and Troll (bows) get their real caps: Hit 9% -> 6%, DW white 28% -> 25%, Expertise
  26 -> 24. Applies only while every equipped weapon benefits, and bars are tagged
  "(racial)" so you can see why your cap is lower. Scoring, gem hit-swaps and the NOW
  advice all follow the adjusted caps.
- "White (DW)" renamed to **"Auto-attacks (DW)"** so you don't need theorycraft jargon
  to read your own caps.

## Upgrade badges - bigger, everywhere, impossible to miss

- **Bag badges no longer require Baganator**: they now draw directly on Blizzard's
  default bags too. (Custom bag addons are not covered yet -
  tooltip verdicts work everywhere regardless.)
- **Quest reward badges - new**: the badge appears directly on quest reward buttons, both
  at the NPC and in the quest log, so you see the right pick before you choose.
- The badge itself is **bold, glowing and pulsing**: damage-number font, colour-matched
  star-burst glow, and a slow actionbar-proc pulse. Same tiers as the tooltip verdict:
  green + (solid), gold + (10%+), purple skull (25%+). Size: `/stc badge 10-30`.

## New options

- **Strict armor filter** (`/stc armor`): by default off-type armor is shown with a scoring
  penalty; toggle strict and it disappears from verdicts and badges entirely.
- **Upgrade icon size** (`/stc icon 10-30`): the arrow/skull on tooltip verdicts, sized
  your way (default 14).

---

# StatCoach 1.1.8 (Retail)

## Scoring accuracy — please read

Upgrade percentages will look different after this update. That is intentional: four scoring bugs were found and fixed, and the old numbers were too high on many items.

- **Socket bonuses are no longer counted as real stats.** An item showing a socket bonus was credited with it even when the sockets were empty.
- **Set bonuses no longer inflate a single piece.** A line like "(2) Set: Increases attack power by 40" was parsed as if that one item granted the whole set bonus. This affected every class.
- **Empty sockets are worth less.** They were credited at the full value of a socketed gem; they now count at 70%, since an empty socket is potential, not a stat.
- **Armor is no longer free.** Melee and ranged specs weighted armor at zero, so losing several hundred armor cost nothing in the score.

## Spec weights

- **All 39 specs re-verified** against current spec guides for Midnight 12.1, with 33 corrections to stat priorities.

## Tooltip verdicts

- Upgrades are much easier to spot: **BIG UPGRADE** (25%+) is purple with a skull icon, regular upgrades are gold or green with an arrow.
- Added spacing above the verdict line so it separates from the item's own stats.
- **Fixed false upgrades with two-handers.** Hovering an off-hand or held item while a two-hander was equipped compared it against an empty slot and reported a big upgrade. One-handers equipped alongside a two-hander are now scored against the correct slot.
- Removed the "vs equipped" line.

## Other

- Window no longer resizes when switching class or spec — all menus now match the widest one.
- Related-addon note moved into the info button instead of taking up space in the main view.

---

# StatCoach 1.1.8 (TBC)

## Scoring accuracy — please read

Upgrade percentages will look different after this update. That is intentional: four scoring bugs were found and fixed, and the old numbers were too high on many items.

- **Socket bonuses are no longer counted as real stats.** An item showing "Socket Bonus: +6 Attack Power" was credited with that bonus even when the sockets were empty.
- **Set bonuses no longer inflate a single piece.** A line like "(2) Set: Increases attack power by 40" was parsed as if that one item granted the whole set bonus. This affected all nine classes.
- **Empty sockets are worth less.** They were credited at the full value of a socketed gem; they now count at 70%, since an empty socket is potential, not a stat.
- **Armor is no longer free.** Melee and ranged specs weighted armor at zero, so losing several hundred armor cost nothing in the score.

On the reported test case these four together took a +34.5% verdict down to +0.8% — below the 1% threshold, so the item is now correctly silent instead of recommended.

## Tooltip verdicts

- Upgrades are much easier to spot: **BIG UPGRADE** (25%+) is purple with a skull icon, regular upgrades are gold or green with an arrow.
- Added spacing above the verdict line so it separates from the item's own stats.
- **Fixed false upgrades with two-handers.** Hovering a shield, off-hand or held item while a two-hander was equipped compared it against an empty slot and reported a big upgrade. One-handers equipped alongside a two-hander are now scored against the correct slot.
- Removed the "vs equipped" line.

## Enchant vendor pins

- **ENCH rows are now clickable** and place a TomTom waypoint on the vendor that sells the enchant, with the arrow pointing the way.
- Pins are capped at two at a time and are never persistent, so they can't crowd out or overwrite your own waypoints. Survives a TomTom reinstall or profile change.
- Fixed a data error: "Glyph of Healing" is actually **Glyph of Renewal**.
- Glyph of Ferocity vendor corrected to Cenarion Expedition in Zangarmarsh.

## Other

- Window no longer resizes when switching class or spec — all menus now match the widest one.
- Related-addon note moved into the info button instead of taking up space in the main view.

---

# StatCoach 1.1.2
Scoring calibration audit + more upgrade surfaces:
- Upgrade verdict now shows on QUEST LOG rewards, quest-giver reward choices and dungeon LOOT ROLLS (these tooltips hide the item link from normal hooks).
- Healing power now parsed ("+22 Healing" gems and "Increases healing done by up to X") - healer items were badly under-scored.
- Spell haste, spell crit gem lines, +defense rating, armor and shield block value now parsed.
- Empty equipment slots now count as score 0, so any usable item is correctly flagged as an upgrade for an empty slot (tooltip + bag badge).

# StatCoach 1.1.1
- Empty sockets now count: each is credited as a standard gem for your role, so a better item with unfilled sockets is no longer beaten by your gemmed equipped one.

# StatCoach 1.1
- **Retail (Mainline) support** - one addon, both flavors. Auto-detects your client: retail gets spec detection, Item Level > primary > secondary priority for all 39 specs, a live secondaries readout, and an ilvl-aware gear compare on tooltips and bags.
- **Dual-wield white-hit coaching (TBC)**: a second cap bar (24%) appears when you actually dual-wield, gear scoring keeps ~40% of hit's value between 9% and 24%, and the NOW advisor explains it.
- **Draenei aura auto-detected (TBC)**: Heroic/Inspiring Presence (+1% hit) is read live from your buffs, so the hit bar is exact in groups.
- TOC bumped to 2.5.6 (no more "Out of date" flag).
- More real gem icons (Delicate, Teardrop, Glowing, Royal, Veiled hit-swap - verified Wowhead IDs).

# StatCoach 1.0
First public release.

- Live stat-priority list for all 9 classes / 27 specs, context-aware (Leveling / Pre-raid / Endgame).
- All 27 specs' stat priorities cross-checked against Wowhead, Icy Veins and Warcraft Tavern TBC guides.
- Cap coach with live talent/racial hit reading (Melee/Ranged 9%, Spell 16%, Expertise 26, Defense 490).
- Trade advisor ("NOW:" line) telling you what to favour or trade toward right now.
- Cap-aware gear compare on the item tooltip - upgrades only, counts socketed gems and Equip effects, armor-type aware, weapon DPS scored by role.
- Two-handers compared against main-hand + off-hand combined, so a 2H is never shown as an upgrade for a dual-wielding spec.
- Tooltip line added synchronously - no flicker/jump on hover, plays nicely with comparison-tooltip addons.
- Bag upgrade badge (green + / gold ++) for Baganator, Bagnon and default bags.
- Gems and Enchants popups with real in-game icons and the recommended choice per socket/slot (plus a cheaper option while leveling/pre-raid).
- Movable window, minimap button, ESC to close, adjustable scale, right-click settings menu.
