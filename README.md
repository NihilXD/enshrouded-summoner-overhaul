# Enshrouded Summoner Overhaul

A ShroudForge mod for **Enshrouded** that transforms summoning from a passive, single-archetype mechanic into a full class overhaul—introducing ranged and elemental caster summons, a shared summon capacity pool, an active "Death Coil" skull projectile that heals nearby minions on hit, and configurable summon duration & scaling.

> **Status:** In active development (Phase 1 / Schema Discovery).  
> Built on top of the asset-patching foundation from [longer_lasting_summons](./longer_lasting_summons).

---

## Planned Features

- **Expanded Summon Pool (Faction-Swapped Entities):**
  - **Archer Summons** (e.g., Scavenger Ranger–based friendly entities)
  - **Elemental Spellcaster Summons** (e.g., Hollow Mage / Shroud Caster–based friendly entities for Fire, Ice, Acid, etc.)
- **Spell & Crafting Integration:**
  - Consumable summoning skulls and/or Eternal Staff Spell variants craftable at the Alchemist.
- **Shared Summon Cap:**
  - New summons share Enshrouded's native `Skeleton` spawn limit pool (`keen::ecs::SpawnLimit`), integrating organically with *Advanced Necromancy* and *Totem Mastery* talents.
- **Active "Death Coil" Spell:**
  - A direct-fire projectile using the summoning skull model on a Fireball-style chassis.
  - Deals damage on impact and heals nearby friendly summons for a percentage scaled by **Summon Damage** modifiers.
- **Duration & Scaling:**
  - Configurable summon duration (ported from *Longer Lasting Summons*, defaulting to 5 minutes) and summon damage scaling.
- **Dedicated Server & Client Parity:**
  - Server-authoritative entity spawning, caps, and `OnHit` healing, paired with client-side assets, icons, and localization.

---

## Project Structure

```text
Enshrouded Summoner Overhaul/
├── README.md
├── ROADMAP.md
├── longer_lasting_summons/       # Reference mod (EML/ShroudForge Lua duration patch)
└── summoner_overhaul/            # Main ShroudForge mod
    ├── mod.json
    └── src/
        └── mod.lua
```

---

## Development Setup (ShroudForge)

1. Install **Enshrouded** (clean install).
2. Download the latest release ZIP from [bonsaibauer/shroudforge](https://github.com/bonsaibauer/shroudforge/releases/latest) and extract it into your Enshrouded root directory (next to `enshrouded.exe`).
3. Copy or symlink `summoner_overhaul/` into `<Enshrouded>/mods/summoner_overhaul/`.
4. Launch the game via ShroudForge and check the ShroudForge console/logs.

---

## Multiplayer / Dedicated Server Note

Because Enshrouded dedicated servers are authoritative over entity spawning, faction alignment, and `SpawnLimit` caps, **both the dedicated server and all connecting clients** must have ShroudForge and `summoner_overhaul` installed.

