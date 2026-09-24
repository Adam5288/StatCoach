# -*- coding: utf-8 -*-
"""Build StatCoachData_Mists.lua from the harvested Mists of Pandaria Classic stat pages.

Input : one JSON file per class (CoachProbe/mists_stats/<CLASS>.json), each spec with
        specId, spec, role, primary, priorityNormalized, ties, caps, spiritToHit,
        url, source, pageUpdated, notes.
Output: StatCoachData_Mists.lua next to this folder's parent - plain tables, no API.

The engine takes the caps from the game itself; this file carries the order of the
stats per specialization, what the spec attacks with, and the level-90 rating that
buys 1% hit and expertise, which is only used when a character has no rating to
read the ratio from.

    python Tools/build_mists_data.py [path/to/mists_stats]
"""
import glob
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(HERE), "CoachProbe", "mists_stats")
OUT = os.path.join(HERE, "StatCoachData_Mists.lua")

CLASS_ORDER = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
               "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID"]
TOKENS = {"Strength", "Agility", "Intellect", "Spirit", "Stamina", "Hit", "Expertise", "Crit",
          "Haste", "Mastery", "Spell Power", "Attack Power", "Weapon Damage", "Armor", "Dodge", "Parry"}
ROLES = {"DAMAGER", "TANK", "HEALER"}

# The harvest records the stat a page LEADS with as "primary" for a few tanks, but the
# engine uses "primary" for the class's main attribute. Bear-form druids scale with
# Agility; the Guardian page merely lists Stamina first. Override, never guess more.
PRIMARY_OVERRIDE = {104: "Agility"}


def ties_text(ties):
    """The harvest wrote ties three ways: ["Hit", "Expertise"] (one tie as a flat token
    list), [["Hit", "Expertise"]] (list of ties) and ["Hit = Expertise (...)"] (prose)."""
    if not ties:
        return []
    if all(isinstance(t, str) for t in ties) and all(t in TOKENS for t in ties):
        return [" = ".join(ties)]
    out = []
    for t in ties:
        out.append(" = ".join(t) if isinstance(t, list) else str(t))
    return out


def dedupe(stats):
    """A page can name a stat twice (Blood: Expertise to 7.5%, and again later toward
    15%). The numbered list shows each stat once, at its first place."""
    seen, out = set(), []
    for t in stats:
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def attack_of(cls, spec):
    if spec["role"] == "HEALER":
        return None
    if cls == "HUNTER":
        return "ranged"
    if spec["role"] == "DAMAGER" and spec["primary"] == "Intellect":
        return "spell"
    return "melee"


def main():
    files = {os.path.basename(f)[:-5]: f for f in glob.glob(os.path.join(SRC, "*.json"))}
    missing = [c for c in CLASS_ORDER if c not in files]
    if missing:
        sys.exit("missing class files: " + ", ".join(missing))

    # The harvest's own "notes" are research notes ("the page says ..."); what a player
    # reads comes from notes_player.json, one entry per spec id, all 34 required.
    player_notes = json.load(io.open(os.path.join(SRC, "notes_player.json"), encoding="utf-8"))
    problems, specid, classes, rating_votes = [], {}, [], []
    harvested = set()
    for cls in CLASS_ORDER:
        data = json.load(io.open(files[cls], encoding="utf-8"))
        harvested.add(data.get("harvested"))
        specs = data["specs"]
        entries = []
        for sp in specs:
            name, sid = sp["spec"], sp["specId"]
            if sp["role"] not in ROLES:
                problems.append("%s %s: role %r" % (cls, name, sp["role"]))
            stats = dedupe(sp.get("priorityNormalized") or [])
            primary = PRIMARY_OVERRIDE.get(sid, sp.get("primary"))
            bad = [t for t in stats if t not in TOKENS]
            if bad:
                problems.append("%s %s: unknown stat tokens %s" % (cls, name, bad))
            if len(stats) < 3:
                problems.append("%s %s: only %d stats" % (cls, name, len(stats)))
            specid[sid] = name
            caps = sp.get("caps") or {}
            for pk, rk in (("hitPct", "hitRating"), ("expertisePct", "expertiseRating")):
                p, r = caps.get(pk), caps.get(rk)
                if isinstance(p, (int, float)) and isinstance(r, (int, float)) and p > 0 and r > 0:
                    rating_votes.append(round(r / p, 1))
            note = player_notes.get(str(sid))
            if not note:
                problems.append("%s %s: no player note in notes_player.json" % (cls, name))
            for word in ("page", "Page", "harvest", "comment"):
                if note and word in note:
                    problems.append("%s %s: player note says %r" % (cls, name, word))
            entries.append({
                "name": name, "role": sp["role"], "primary": primary,
                "attack": attack_of(cls, dict(sp, primary=primary)), "stats": [t for t in stats if t in TOKENS],
                "notes": (note or "").strip(),
                "capNote": "",
                "spiritIsHit": bool(sp.get("spiritToHit")),
                "source": "Stat priority: Wowhead's Mists of Pandaria Classic %s %s guide%s." % (
                    name, cls.title() if cls != "DEATHKNIGHT" else "Death Knight",
                    (", " + str(sp["pageUpdated"])) if sp.get("pageUpdated") else "")
                    if sp.get("source", "wowhead") == "wowhead" else
                    "Stat priority: %s (%s)." % (sp.get("source"), sp.get("url")),
            })
        classes.append((cls, entries))

    if problems:
        sys.exit("refusing to write - fix the harvest first:\n  " + "\n  ".join(problems))

    # The level-90 rating per 1%: every guide that states both a percent and a rating
    # votes. They must agree; a split vote is a harvest error, not a number to average.
    votes = sorted(set(rating_votes))
    if not votes:
        sys.exit("no guide stated a rating next to a percent - cannot set RATING_PER_PCT")
    if max(votes) - min(votes) > 1.0:
        sys.exit("guides disagree on rating per 1%%: %s" % votes)
    per_pct = max(set(rating_votes), key=rating_votes.count)

    L = []
    L.append("--[[ StatCoachData_Mists.lua")
    L.append("     MISTS OF PANDARIA CLASSIC data (5.5.x, level 90). Loaded only by StatCoach_Mists.toc.")
    L.append("     Pure tables, no API calls. GENERATED by Tools/build_mists_data.py from the harvest in")
    L.append("     CoachProbe/mists_stats (%s) - edit the harvest and rebuild, not this file." % ", ".join(sorted(h for h in harvested if h)))
    L.append("")
    L.append("     The caps are NOT in here: the engine reads them from the game (see the MISTS path")
    L.append("     in StatCoach.lua). This file carries, per specialization, the order of the stats on")
    L.append("     Wowhead's Mists of Pandaria Classic stat priority page, what the spec attacks with")
    L.append("     (which caps apply), and the guide's notes.")
    L.append("]]--")
    L.append("")
    L.append("local ADDON, ns = ...")
    L.append("ns.Data = ns.Data or {}")
    L.append("local D = ns.Data")
    L.append("")
    L.append("D.mists = D.mists or {}")
    L.append("local M = D.mists")
    L.append("")
    L.append("-- Hit and expertise rating per 1%% at level 90, as the guides state it (%d of them agree)." % len(rating_votes))
    L.append("-- Only used when the character has no hit or expertise rating to read the ratio from.")
    L.append("M.RATING_PER_PCT = %s" % (int(per_pct) if per_pct == int(per_pct) else per_pct))
    L.append("")
    L.append("-- Specialization id -> the English key below. Ids are language-independent.")
    L.append("M.SPECID = {")
    for sid in sorted(specid):
        L.append("  [%d] = %s," % (sid, lua_str(specid[sid])))
    L.append("}")
    L.append("")
    L.append("M.classOrder = { " + ", ".join(lua_str(c) for c in CLASS_ORDER) + " }")
    L.append("")
    L.append("M.classes = {")
    for cls, entries in classes:
        L.append("  %s = {" % cls)
        L.append("    specOrder = { " + ", ".join(lua_str(e["name"]) for e in entries) + " },")
        L.append("    specs = {")
        for e in entries:
            key = e["name"] if e["name"].isidentifier() else "[" + lua_str(e["name"]) + "]"
            L.append("      %s = {" % key)
            L.append("        role = %s, primary = %s, attack = %s," % (
                lua_str(e["role"]), lua_str(e["primary"]), lua_str(e["attack"]) if e["attack"] else "nil"))
            L.append("        stats = { " + ", ".join(lua_str(t) for t in e["stats"]) + " },")
            if e["spiritIsHit"]:
                L.append("        spiritIsHit = true,")
            if e["notes"]:
                L.append("        notes = %s," % lua_str(e["notes"]))
            if e["capNote"]:
                L.append("        capNote = %s," % lua_str(e["capNote"]))
            L.append("        source = %s," % lua_str(e["source"]))
            L.append("      },")
        L.append("    },")
        L.append("  },")
    L.append("}")
    io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    print("wrote %s: %d specs, RATING_PER_PCT %s (votes %s)" % (OUT, len(specid), per_pct, votes))


if __name__ == "__main__":
    main()
