# Development Roadmap — Enshrouded Summoner Overhaul

This roadmap tracks the design and implementation of the **Enshrouded Summoner Overhaul** mod using **ShroudForge** (`.kfc` asset patching + Lua runtime hooks).

---

## Phase 0: Environment & Schema Discovery
- [x] Set up repository structure and port *Longer Lasting Summons* reference.
- [ ] Clean install of Enshrouded + **ShroudForge** mod loader.
- [ ] Run `summoner_overhaul` asset-inspector pass to document exact `keen::*` resource types and component schemas:
  - `keen::ecs::TemplateResource` (faction, AI behavior, `SpawnLimit`, `LifeTime`, combat stats)
  - Existing summon spells / Eternal spells / summoning skull items
  - `keen::SkillTreeResource` (*Advanced Necromancy*, *Totem Mastery*, Summon Damage nodes)
  - Fireball & Heal Cascade spell/projectile/OnHit components
  - Alchemist crafting recipe resource structures

---

## Phase 1: Entity Faction Swapping (Archers & Elemental Casters)
- [ ] Identify target ranged & caster enemy templates (e.g., Scavenger Rangers, Hollow Mages, Shroud Casters).
- [ ] Clone/override templates with unique IDs and swap faction alignment to player-friendly / enemy-hostile.
- [ ] Verify AI behavior: follows player, attacks hostile enemies, does not draw aggro from player or friendly NPCs.
- [ ] Assign `keen::ecs::SpawnLimit` pool (`spawnLimitPool = "Skeleton"`) so new summons share the native summon cap.

---

## Phase 2: Spell Integration, Recipes & Shared Cap
- [ ] Duplicate existing summoning skull / Eternal spell item & spell definitions with unique IDs.
- [ ] Point spawn payloads to the new Archer and Elemental Caster templates.
- [ ] Add Alchemist crafting recipes for each new summon spell/item.
- [ ] Verify shared cap behavior with *Advanced Necromancy* and *Totem Mastery* talents (and optionally expose cap scaling / config options via `extended.mod.json`).

---

## Phase 3: Active "Death Coil" Spell (Skull Projectile + AoE Summon Heal)
- [ ] Clone Fireball staff spell chassis (speed, trajectory, collision, staff cast animation).
- [ ] Replace fireball mesh/VFX with the summoning skull 3D asset.
- [ ] Implement `OnHit` hook/payload:
  - Deal damage scaled by the player's **Summon Damage** modifier.
  - Query active friendly summons within impact radius and apply a heal tick scaled by **Summon Damage**.
- [ ] Add Alchemist recipe / Eternal variant for the Death Coil spell.

---

## Phase 4: Duration, Scaling, UI & Localization
- [ ] Port configurable summon duration from *Longer Lasting Summons* (preserving vanilla timers on throwables, totems, wisps, and procs).
- [ ] Tune HP, damage, and Intelligence / Summon Damage scaling across all new summons.
- [ ] Add custom inventory icons and localized names/descriptions for all new spells and items.
- [ ] Add ShroudForge `extended.mod.json` settings UI (duration slider, cap options, debug logging toggle).

---

## Phase 5: Dedicated Server Parity & Release
- [ ] Test mod execution on an Enshrouded Dedicated Server with matching client installs.
- [ ] Verify server-authoritative cap enforcement, faction sync, and `OnHit` healing across multiple connected players.
- [ ] Package release build and documentation.

