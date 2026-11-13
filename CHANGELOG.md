# Changelog

All notable changes to **Enshrouded Summoner Overhaul** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Planned / In Progress
- Verify **Hollow Frost Mage** Coldheights chest aura VFX and ice-only `EnemyArsenalResource` override in-game.
- Explore additional elemental **Hollow Mage** variants (Fire / Lightning / Shroud) and bow/skeleton animation compatibility.
- **Phase 3 — Death Coil:** Active skull projectile spell (Fireball chassis + summoning skull VFX) dealing enemy damage and healing nearby friendly summons on impact.
- **Phase 4 — Polish & Settings:** Custom element-tinted UI spell icons, Alchemist workshop crafting mode alongside manual crafting toggle, `extended.mod.json` settings & `locales/`, and debug log cleanup.
- **Phase 5 — Dedicated Server:** Verify server/client parity on Enshrouded Dedicated Server.

---

## [0.1.0-alpha] - 2026-11-13

First playable alpha milestone (`fbd15c0`, `summoner_overhaul` `v0.1.0`).

### Added
- **Duration Overhaul:** Extended default `keen::ecs::LifeTime` duration on vanilla `Skeleton`-pool casted summon templates to `300s` (5 minutes).
- **Four Custom Eternal Summon Spells:** Cloned faction-swapped (`PlayerAlly`) enemy templates sharing Enshrouded's native `"Skeleton"` `keen::ecs::SpawnLimit` pool:
  - **Eternal Summon: Fell Ranger** (`Enemy_Fogger_Ranger_Armored_T3_01` chassis)
  - **Eternal Summon: Hollow Frost Mage** (`Enemy_Skeleton_Mage01` chassis)
  - **Eternal Summon: Vukah Storm Shaman** (`Enemy_Vukah_Shaman_Lightning` chassis)
  - **Eternal Summon: Fell Spore Mage** (`Enemy_Fogger_SporeHead_Mage01_AG2` chassis)
- **Pet Follow AI:** Configured `Enemy01BehaviorState` (`guardSetup` with `guardParent=true`, `startDistance=4.0`, `combatSetup.ignoreTamedAnimals=true`) and stripped roaming/patrol/return-home features from `enabledFeatures` / `disabledFeatures` so summons stay close to the player when idle.
- **Spell, Crafting & Localization Pipeline:**
  - Cloned Eternal spell items with unique deterministic GUIDs/ItemIds and wired `placedEntity` references cleanly without dirtying vanilla items.
  - Registered new spell items in `ItemRegistryResource`, recipes in `RecipeRegistryResource` and `FbUiBundle`, knowledge keys (`ItemKnowledge` / `GlobalKnowledge`), and cloned `keen::UiTextureResource` icons.
  - Added custom `En_Us` localized spell names and descriptions.
- **Hollow Frost Mage Refinement (pending final in-game sign-off):**
  - Replaced `VFX_SubEntity_Enemy_Skeleton_Melee_Chest_Smoke` chest sub-entity with a cloned Coldheights frost sub-entity (`VFX_SubEntity_SummonerOverhaul_Frost_Mage_Chest_Aura`).
  - Cloned `Enemy_Skeleton_Mage01`'s `EnemyArsenalResource` into `EnemyArsenalRegistryResource` keeping only the ranged ice attack (`dfded71c-06f5-40b4-97b7-a8d262f5ab06`) to prevent Flying Skull summoning without affecting wild Hollow Mages.

### Initial Scaffold
- `6d0d097`: Repository scaffold with [README.md](README.md), [ROADMAP.md](ROADMAP.md), `.gitignore`, `summoner_overhaul/mod.json`, and initial asset-patching prototype.
