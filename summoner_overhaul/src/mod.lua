-- Enshrouded Summoner Overhaul (ShroudForge)
-- Phase 0 / Starter Module:
--   1. Ports the Longer Lasting Summons duration patch.
--   2. Provides a toggleable schema inspector to discover exact component/resource
--      names for factions, spells, recipes, and skill tree nodes.

local CONFIG = {
    -- Duration in minutes for casted summons (ported from Longer Lasting Summons)
    summon_duration_minutes = 5,

    -- Set to true during Phase 0 to log matching template/spell/skill schemas
    -- to the ShroudForge console on startup. Set to false for normal play.
    inspect_assets = true,
}

local NS_PER_SECOND = 1000000000
local TARGET_DURATION_SECONDS = CONFIG.summon_duration_minutes * 60
local TARGET_DURATION_NS = TARGET_DURATION_SECONDS * NS_PER_SECOND

print(string.format("[SummonerOverhaul] Initializing v0.1.0 (Duration: %dm / %ds)...",
    CONFIG.summon_duration_minutes, TARGET_DURATION_SECONDS))

-- =========================================================================
-- HELPERS
-- =========================================================================

local function is_casted_summon_template(tname, pool)
    local lower = string.lower(tname or "")

    local matched = (pool == "Skeleton")
        or string.find(lower, "necromancy_spell") ~= nil
        or (string.find(lower, "skeleton") ~= nil and string.find(lower, "spell") ~= nil)

    if not matched then
        return false
    end

    -- Exclude transient procs, throwables, totems, wisps, and VFX
    local excluded_terms = {
        "skull", "throwable", "grenade", "proc",
        "totem", "wisp", "projectile", "explosion", "zone", "spawner"
    }
    for _, term in ipairs(excluded_terms) do
        if string.find(lower, term) then
            return false
        end
    end
    if string.find(lower, "^vfx") then
        return false
    end

    return true
end

local function log_component_types(tname, comps)
    local types = {}
    for _, comp in ipairs(comps) do
        table.insert(types, tostring(comp.type))
    end
    print(string.format("[SummonerOverhaul][Inspect] Template '%s' components: %s",
        tname, table.concat(types, ", ")))
end

-- =========================================================================
-- PHASE 0: DURATION PATCH + SCHEMA INSPECTION
-- =========================================================================

local templates = game.assets.get_resources_by_type("keen::ecs::TemplateResource")
if not templates or #templates == 0 then
    print("[SummonerOverhaul] WARNING: No keen::ecs::TemplateResource assets found.")
    return
end

local patched_count = 0
local inspect_keywords = {
    "hollow", "wretch", "scavenger", "ranger", "mage",
    "fireball", "heal", "necromancy", "summon"
}
local inspected_count = 0
local MAX_INSPECT_LOGS = 40

for _, res in ipairs(templates) do
    local data = res.data
    local tname = data.name or ""
    local lower = string.lower(tname)
    local comps = data.components

    if comps then
        local pool = "none"
        local lt_comp = nil

        for _, comp in ipairs(comps) do
            local typename = tostring(comp.type)
            if typename == "keen::ecs::SpawnLimit" then
                pool = tostring(comp.value.spawnLimitPool)
            elseif typename == "keen::ecs::LifeTime" then
                lt_comp = comp
            end
        end

        -- Apply duration patch to casted summons
        if is_casted_summon_template(tname, pool) and lt_comp then
            local current_lt = lt_comp.value.lifeTime.value
            if current_lt >= 5 * NS_PER_SECOND then
                local original_sec = math.floor(current_lt / NS_PER_SECOND)
                lt_comp.value.lifeTime.value = TARGET_DURATION_NS
                patched_count = patched_count + 1
                print(string.format("[SummonerOverhaul] Patched '%s' [Pool: %s]: %ds -> %ds",
                    tname, pool, original_sec, TARGET_DURATION_SECONDS))
            end
        end

        -- Schema inspection logging (Phase 0)
        if CONFIG.inspect_assets and inspected_count < MAX_INSPECT_LOGS then
            for _, kw in ipairs(inspect_keywords) do
                if string.find(lower, kw) then
                    log_component_types(tname, comps)
                    inspected_count = inspected_count + 1
                    break
                end
            end
        end
    end
end

print(string.format("[SummonerOverhaul] Duration patch applied to %d templates.", patched_count))

if CONFIG.inspect_assets then
    local skill_trees = game.assets.get_resources_by_type("keen::SkillTreeResource")
    print(string.format("[SummonerOverhaul][Inspect] SkillTreeResource count: %d",
        skill_trees and #skill_trees or 0))
end

