-- Enshrouded Summoner Overhaul (ShroudForge)
-- Phase 1 & 2:
--   - Longer Lasting Summons (5-minute duration patch)
--   - Faction-Swapped Ranged & Elemental Caster Summons (PlayerAlly + Pool: Skeleton)
--   - Eternal Staff Spell Items + Recipes

local CONFIG = {
    summon_duration_minutes = 5,
    -- When true, makes the new summon recipes free and craftable from the
    -- manual hand-crafting menu (no Alchemist required) for fast SP testing.
    test_mode_manual_craft = true,
}

local NS_PER_SECOND = 1000000000
local TARGET_DURATION_SECONDS = CONFIG.summon_duration_minutes * 60
local TARGET_DURATION_NS = TARGET_DURATION_SECONDS * NS_PER_SECOND

local VANILLA_ETERNAL_SKELETON_T5_GUID = "4147dce3-27fd-406f-9937-29b478a94046"
local VANILLA_ETERNAL_SKELETON_T7_GUID = "21e6d418-7981-40a1-90a6-ba1b69f4a4fa"

local function log_info(msg)
    if shroudforge and shroudforge.log and shroudforge.log.info then
        shroudforge.log.info(msg)
    else
        print(msg)
    end
end

local function hash_u32(str)
    -- Deterministic 32-bit FNV-1a hash for custom itemId / recipeId values
    local h = 2166136261
    for i = 1, #str do
        h = (h ~ string.byte(str, i)) * 16777619
        h = h % 4294967296
    end
    if h == 0 then h = 1 end
    return h
end

local function make_guid(seed_str)
    local p1 = hash_u32(seed_str .. ":1")
    local p2 = hash_u32(seed_str .. ":2")
    local p3 = hash_u32(seed_str .. ":3")
    local p4 = hash_u32(seed_str .. ":4")
    return string.format("%08x-%04x-4%03x-8%03x-%04x%08x",
        p1,
        p2 & 0xFFFF,
        (p2 >> 16) & 0x0FFF,
        p3 & 0x0FFF,
        (p3 >> 16) & 0xFFFF,
        p4
    )
end

local function is_casted_summon_template(tname, pool)
    local lower = string.lower(tname or "")
    local matched = (pool == "Skeleton")
        or string.find(lower, "necromancy_spell") ~= nil
        or (string.find(lower, "skeleton") ~= nil and string.find(lower, "spell") ~= nil)
    if not matched then return false end

    local excluded_terms = {
        "skull", "throwable", "grenade", "proc",
        "totem", "wisp", "projectile", "explosion", "zone", "spawner"
    }
    for _, term in ipairs(excluded_terms) do
        if string.find(lower, term) then return false end
    end
    if string.find(lower, "^vfx") then return false end
    return true
end

local function find_component(comps, typename)
    for _, comp in ipairs(comps) do
        if tostring(comp.type) == typename then
            return comp
        end
    end
    return nil
end

local function set_or_add_component(comps, typename, value_table)
    local existing = find_component(comps, typename)
    if existing then
        for k, v in pairs(value_table) do
            existing.value[k] = v
        end
        return true
    end
    table.insert(comps, {
        type = typename,
        value = value_table
    })
    return true
end

local function clone_component_from_fresh_ref(comps, ref_summon_res, typename, patch_fn)
    local existing = find_component(comps, typename)
    if existing then
        if patch_fn then patch_fn(existing.value) end
        return true
    end
    -- Reading ref_summon_res.data gives a fresh userdata copy without mutating the reference resource
    local fresh_ref_data = ref_summon_res and ref_summon_res.data
    local ref_comps = fresh_ref_data and fresh_ref_data.components
    local ref_comp = ref_comps and find_component(ref_comps, typename)
    if not ref_comp then
        log_info("[SummonerOverhaul] WARNING: Reference component not found: " .. typename)
        return false
    end
    if patch_fn then patch_fn(ref_comp.value) end
    table.insert(comps, ref_comp)
    return true
end

local function create_cloned_resource(type_obj, new_guid, new_data, label, part)
    -- Signature: create_resource(data, type_obj, guid, part)
    local ok, res = pcall(game.assets.create_resource, new_data, type_obj, new_guid, part or 0)
    if ok and res then
        log_info(string.format("[SummonerOverhaul] Created %s (%s)", label, tostring(res.guid or new_guid)))
        return res
    end
    log_info(string.format("[SummonerOverhaul] ERROR creating %s: %s", label, tostring(res)))
    return nil
end

local function find_always_unlocked_knowledge_id()
    local query_type = game.types.get("keen::GameKnowledgeQueryResourceDb")
    if not query_type then return nil end
    for _, resource in ipairs(game.assets.get_resources_by_type(query_type) or {}) do
        for _, query in ipairs((resource.data and resource.data.queries) or {}) do
            if query.name == "Unlock_Flame_Altar_PK" then
                for _, action in ipairs(query.actions or {}) do
                    if action.name == "NPC_Flame_Hint01" and action.query and action.query.knowledgeOrQueryId then
                        return action.query.knowledgeOrQueryId.value
                    end
                end
            end
        end
    end
    return nil
end

local function clone_enemy_as_summon(source_res, ref_summon_res, template_type, new_name, new_guid)
    local cloned = source_res.data
    cloned.name = new_name
    local comps = cloned.components

    -- 1. Swap faction to PlayerAlly
    set_or_add_component(comps, "keen::ecs::Faction", { faction = "PlayerAlly" })

    -- 2. Share the native Skeleton summon cap pool
    clone_component_from_fresh_ref(comps, ref_summon_res, "keen::ecs::SpawnLimit", function(val)
        val.spawnLimitPool = "Skeleton"
    end)

    -- 3. Apply summon duration
    clone_component_from_fresh_ref(comps, ref_summon_res, "keen::ecs::LifeTime", function(val)
        val.lifeTime.value = TARGET_DURATION_NS
    end)

    -- 4. Disable enemy loot and XP on player summons
    local loot = find_component(comps, "keen::ecs::RandomLoot")
    if loot and loot.value then
        loot.value.disableRandomLoot = true
    end
    local xp = find_component(comps, "keen::ecs::ExperienceSource")
    if xp and xp.value then
        xp.value.xpMod = 0
    end

    -- 5. Configure pet follow AI and disable idle wandering/patrol
    local strip_features = {
        Roaming = true,
        Patrol = true,
        RunAround = true,
        Sleep = true,
        Interact = true,
        MoveToMarker = true,
        Investigate = true,
        ReturnHome = true,
        FleeHome = true,
    }
    local function filter_feature_array(arr)
        if not arr then return nil end
        local out = {}
        local seen = {}
        for _, f in ipairs(arr) do
            local fs = tostring(f)
            if not strip_features[fs] and not seen[fs] then
                seen[fs] = true
                table.insert(out, fs)
            end
        end
        for _, req in ipairs({ "Move", "Rotate", "RotateWhileStanding", "Combat", "Run" }) do
            if not seen[req] then
                seen[req] = true
                table.insert(out, req)
            end
        end
        return out
    end

    local beh_comp = find_component(comps, "keen::ecs::Enemy01BehaviorState")
    if beh_comp and beh_comp.value then
        local beh = beh_comp.value
        if beh.guardSetup then
            beh.guardSetup.guardParent = true
            beh.guardSetup.canGuardPlayer = false
            beh.guardSetup.startDistance = 4.0
            beh.guardSetup.targetDistance = 2.0
            beh.guardSetup.maxArriveDistance = 1.5
            beh.guardSetup.useTargetOffsetsWhileTargetIsMoving = true
            beh.guardSetup.disableRunning = false
        end
        if beh.combatSetup then
            beh.combatSetup.maxPlayerTargetDistance = 1000.0
            beh.combatSetup.maxNonPlayerTargetDistance = 20.0
            beh.combatSetup.ignoreTamedAnimals = true
        end
        local filtered = filter_feature_array(beh.enabledFeatures)
        if filtered then
            beh.enabledFeatures = filtered
        end
    end

    local es_comp = find_component(comps, "keen::ecs::EnemySettings")
    if es_comp and es_comp.value then
        local es = es_comp.value
        local filtered = filter_feature_array(es.enabledFeatures)
        if filtered then
            es.enabledFeatures = filtered
        end
        local dis = {}
        local seen_d = {}
        if es.disabledFeatures then
            for _, f in ipairs(es.disabledFeatures) do
                local fs = tostring(f)
                seen_d[fs] = true
                table.insert(dis, fs)
            end
        end
        for fname, _ in pairs(strip_features) do
            if not seen_d[fname] then
                table.insert(dis, fname)
            end
        end
        es.disabledFeatures = dis
    end

    local res = create_cloned_resource(template_type, new_guid, cloned, "SummonTemplate:" .. new_name, source_res.part or 0)
    if res and res.data and res.data.components then
        local vbeh = find_component(res.data.components, "keen::ecs::Enemy01BehaviorState")
        local vfac = find_component(res.data.components, "keen::ecs::Faction")
        log_info(string.format("[SummonerOverhaul][VerifyTpl] %s comps=%d faction=%s guardParent=%s feats=%s",
            new_name, #res.data.components,
            vfac and vfac.value and tostring(vfac.value.faction) or "nil",
            vbeh and vbeh.value and vbeh.value.guardSetup and tostring(vbeh.value.guardSetup.guardParent) or "nil",
            vbeh and vbeh.value and tostring(vbeh.value.enabledFeatures) or "nil"))
    end
    return res
end

local function clone_vfx_sub_entity(src_res, template_type, new_name, new_guid, new_vfx_guid, new_slot)
    if not src_res or not src_res.data then return nil end
    local d = src_res.data
    local ok_n, orig_name = pcall(function() return d.name end)
    local ok_dn, orig_debug = pcall(function() return d.debugName end)
    local ok_oid, orig_oid = pcall(function() return d.objectId and tostring(d.objectId) or nil end)
    local vcomp = d.components and find_component(d.components, "keen::ecs::VfxComponentResource")
    local orig_vfx = vcomp and vcomp.value and tostring(vcomp.value.vfx) or nil
    local scomp = d.components and find_component(d.components, "keen::ecs::SlotAttachment")
    local ok_slot, orig_slot = pcall(function() return scomp and scomp.value and scomp.value.slot or nil end)

    if ok_n and orig_name ~= nil then pcall(function() d.name = new_name end) end
    if ok_dn and orig_debug ~= nil then pcall(function() d.debugName = new_name end) end
    if ok_oid and orig_oid ~= nil then pcall(function() d.objectId = new_guid end) end
    if vcomp and vcomp.value and new_vfx_guid then
        vcomp.value.vfx = new_vfx_guid
    end
    if ok_slot and orig_slot ~= nil and new_slot then
        pcall(function() scomp.value.slot = new_slot end)
    end

    local created = create_cloned_resource(template_type, new_guid, d, "VfxSubEntity:" .. new_name, src_res.part or 0)

    -- Restore in-memory handle on vanilla source template
    if ok_n and orig_name ~= nil then pcall(function() d.name = orig_name end) end
    if ok_dn and orig_debug ~= nil then pcall(function() d.debugName = orig_debug end) end
    if ok_oid and orig_oid ~= nil then pcall(function() d.objectId = orig_oid end) end
    if vcomp and vcomp.value and orig_vfx then
        vcomp.value.vfx = orig_vfx
    end
    if ok_slot and orig_slot ~= nil and new_slot then
        pcall(function() scomp.value.slot = orig_slot end)
    end
    return created
end

local function clone_enemy_arsenal_single_attack(ar_reg_type, src_arsenal_guid, new_arsenal_guid, keep_attack_guid)
    if not ar_reg_type then return false end
    local regs = game.assets.get_resources_by_type(ar_reg_type) or {}
    if #regs == 0 or not regs[1].data or not regs[1].data.arsenals then
        log_info("[SummonerOverhaul][MageArsenalClone] WARNING: EnemyArsenalRegistryResource missing/empty.")
        return false
    end
    local ar_reg = regs[1]
    local reg_data = ar_reg.data
    local src_ar = nil
    for _, ar in ipairs(reg_data.arsenals) do
        if tostring(ar.guid) == src_arsenal_guid then
            src_ar = ar
            break
        end
    end
    if not src_ar or not src_ar.attacks then
        log_info("[SummonerOverhaul][MageArsenalClone] WARNING: Could not find source arsenal " .. src_arsenal_guid)
        return false
    end

    local keep_atk = nil
    for _, atk in ipairs(src_ar.attacks) do
        if tostring(atk.guid) == keep_attack_guid then
            keep_atk = atk
            break
        end
    end
    if not keep_atk then
        log_info("[SummonerOverhaul][MageArsenalClone] WARNING: Could not find attack " .. keep_attack_guid)
        return false
    end

    local new_ar = {
        guid = new_arsenal_guid,
        attacks = { keep_atk },
        behaviors = src_ar.behaviors or {},
    }
    table.insert(reg_data.arsenals, new_ar)
    local ok_w, err_w = pcall(function()
        ar_reg.data = reg_data
    end)
    if not ok_w then
        log_info("[SummonerOverhaul][MageArsenalClone] ERROR writing arsenal registry: " .. tostring(err_w))
        return false
    end

    -- Verify both vanilla and cloned arsenals exist cleanly
    local v_data = ar_reg.data
    local found_src, found_new = 0, 0
    if v_data and v_data.arsenals then
        for _, ar in ipairs(v_data.arsenals) do
            local g = tostring(ar.guid)
            if g == src_arsenal_guid then found_src = ar.attacks and #ar.attacks or -1 end
            if g == new_arsenal_guid then found_new = ar.attacks and #ar.attacks or -1 end
        end
    end
    log_info(string.format("[SummonerOverhaul][MageArsenalClone] Committed new arsenal %s (src_attacks=%d, new_attacks=%d)",
        new_arsenal_guid, found_src, found_new))
    return found_new == 1
end

local function replace_subentity_template(tpl_res, old_sub_guid, new_sub_guid)
    if not tpl_res or not tpl_res.data or not tpl_res.data.components then return false end
    local d = tpl_res.data
    local se_comp = find_component(d.components, "keen::ecs::SubEntities")
    if not se_comp or not se_comp.value then return false end
    local ok_se, se_list = pcall(function() return se_comp.value.subEntities end)
    if not ok_se or not se_list then
        se_list = se_comp.value
    end
    local changed = false
    for idx, entry in pairs(se_list) do
        local ok_ref, ref_str = pcall(function() return tostring(entry.templateRef) end)
        if ok_ref and ref_str == old_sub_guid then
            entry.templateRef = new_sub_guid
            changed = true
            log_info(string.format("[SummonerOverhaul][FrostAura] Replaced SubEntities[%s].templateRef %s -> %s",
                tostring(idx), old_sub_guid, new_sub_guid))
        end
    end
    if changed then
        tpl_res.data = d
    else
        log_info("[SummonerOverhaul][FrostAura] WARNING: Could not match SubEntity " .. old_sub_guid .. "; value=" .. dump_val(se_comp.value, 2))
    end
    return changed
end

local function clone_spell_item(source_item_res, item_type, new_debug_name, new_guid, summon_template_guid)
    local cloned = source_item_res.data
    local orig_object_id = tostring(cloned.objectId)
    local orig_item_id = cloned.itemId.value
    local orig_debug_name = tostring(cloned.debugName)
    local eq = cloned.equipment
    local orig_placed_entity = eq and tostring(eq.placedEntity) or nil

    local new_item_id = hash_u32(new_debug_name)

    cloned.objectId = new_guid
    cloned.itemId = { value = new_item_id }
    cloned.debugName = new_debug_name

    if eq then
        eq.placedEntity = summon_template_guid
    end

    local created = create_cloned_resource(item_type, new_guid, cloned, "SpellItem:" .. new_debug_name, source_item_res.part or 0)

    -- Restore in-memory cached handle on the vanilla source resource so it is never left dirty
    cloned.objectId = orig_object_id
    cloned.itemId = { value = orig_item_id }
    cloned.debugName = orig_debug_name
    if eq and orig_placed_entity then
        eq.placedEntity = orig_placed_entity
    end

    return created, new_debug_name, new_guid, new_item_id
end

local function clone_item_ui_texture(source_guid, tex_type, new_guid, new_debug_name)
    if not tex_type then return nil end
    local src_tex = game.assets.get_resource(source_guid, tex_type)
    if not src_tex or not src_tex.data then
        log_info("[SummonerOverhaul] WARNING: Missing UiTextureResource for " .. tostring(source_guid))
        return nil
    end
    local tex_data = src_tex.data
    local orig_dbg = tostring(tex_data.debugName or "")
    tex_data.debugName = new_debug_name
    local created = create_cloned_resource(tex_type, new_guid, tex_data, "UiTexture:" .. new_debug_name, src_tex.part or 0)
    tex_data.debugName = orig_dbg
    return created
end

local function clone_ik_key(k)
    return { value = k.value }
end

local function clone_ik_lock(lk)
    local triggers = {}
    if lk.unlockTrigger then
        for _, t in ipairs(lk.unlockTrigger) do
            table.insert(triggers, t)
        end
    end
    return {
        unlockedLocaId = { value = lk.unlockedLocaId.value },
        keyLocaId = { value = lk.keyLocaId.value },
        unlockTrigger = triggers,
    }
end

local function clone_ik_val(v)
    local mask = {}
    if v.lockedKnowledgeMask then
        for _, m in ipairs(v.lockedKnowledgeMask) do
            table.insert(mask, tostring(m))
        end
    end
    return {
        itemId = { value = v.itemId.value },
        lockedKnowledgeMask = mask,
        nameLock = clone_ik_lock(v.nameLock),
        descriptionLock = clone_ik_lock(v.descriptionLock),
        loreLock = clone_ik_lock(v.loreLock),
        recipeLock = clone_ik_lock(v.recipeLock),
    }
end

local function clone_gk_key(k)
    return { id = { value = k.id.value } }
end

local function clone_wk_val(v)
    return {
        id = { id = { value = v.id.id.value } },
        sendToAnalytics = v.sendToAnalytics,
        hasOptionalPlayerProgression = v.hasOptionalPlayerProgression,
        isPlayerKnowledge = v.isPlayerKnowledge,
        type = tostring(v.type),
        expectedFlags = v.expectedFlags,
    }
end

local function clone_pk_val(v)
    return {
        id = { id = { value = v.id.id.value } },
        sendToAnalytics = v.sendToAnalytics,
        hasOptionalPlayerProgression = v.hasOptionalPlayerProgression,
        isPlayerKnowledge = v.isPlayerKnowledge,
        type = tostring(v.type),
        expectedFlags = v.expectedFlags,
        isAdditionalPlayerKnowledgePerFlag = v.isAdditionalPlayerKnowledgePerFlag,
        experienceGainId = { value = v.experienceGainId.value },
        unlockedSkillPoints = v.unlockedSkillPoints,
    }
end

local function get_key_id(k, is_gk)
    if is_gk then return k.id.value end
    return k.value
end

local function insert_bucket_map(map_obj, id_val, key_tbl, val_tbl, is_gk, clone_key_fn, clone_val_fn)
    local entries = map_obj.entries
    local keys = map_obj.keys
    local values = map_obj.values
    local n_buckets = #entries
    local b_lua = (id_val % n_buckets) + 1
    local bucket = entries[b_lua]
    local old_start = bucket.start
    local old_count = bucket.count

    -- Check for duplicate id already in this bucket
    for off = 1, old_count do
        if get_key_id(keys[old_start + off], is_gk) == id_val then
            return "exists"
        end
    end

    if old_count == 0 then
        local new_start = #keys
        table.insert(keys, key_tbl)
        table.insert(values, val_tbl)
        bucket.start = new_start
        bucket.count = 1
        return "inserted_empty"
    end

    -- Bucket collision: copy existing bucket items + new item to end and repoint bucket
    local copied_keys = {}
    local copied_vals = {}
    for off = 1, old_count do
        local idx = old_start + off
        table.insert(copied_keys, clone_key_fn(keys[idx]))
        table.insert(copied_vals, clone_val_fn(values[idx]))
    end
    local new_start = #keys
    for i = 1, old_count do
        table.insert(keys, copied_keys[i])
        table.insert(values, copied_vals[i])
    end
    table.insert(keys, key_tbl)
    table.insert(values, val_tbl)
    bucket.start = new_start
    bucket.count = old_count + 1
    return "inserted_collision(" .. tostring(old_count) .. ")"
end

local function run_pregame_patch()
    log_info(string.format("[SummonerOverhaul] Initializing v0.2.1 (Duration: %dm / %ds)...",
        CONFIG.summon_duration_minutes, TARGET_DURATION_SECONDS))

    local template_type = game.types.get("keen::ecs::TemplateResource")
    local item_type = game.types.get("keen::ItemInfo")
    local item_reg_type = game.types.get("keen::ItemRegistryResource")
    local recipe_reg_type = game.types.get("keen::RecipeRegistryResource")

    if not template_type or not item_type then
        log_info("[SummonerOverhaul] ERROR: Core resource types missing.")
        return
    end

    local templates = game.assets.get_resources_by_type(template_type) or {}
    local template_by_name = {}
    local patched_count = 0

    for _, res in ipairs(templates) do
        local data = res.data
        local tname = (data and data.name) or ""
        if tname ~= "" then
            template_by_name[tname] = res
        end

        local comps = data and data.components
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

            if is_casted_summon_template(tname, pool) and lt_comp then
                local current_lt = lt_comp.value.lifeTime.value
                if current_lt >= 5 * NS_PER_SECOND then
                    lt_comp.value.lifeTime.value = TARGET_DURATION_NS
                    res.data = data
                    patched_count = patched_count + 1
                end
            end
        end
    end
    log_info(string.format("[SummonerOverhaul] Duration patch applied to %d vanilla templates.", patched_count))

    -- Phase 1 & 2: Define custom ranged/caster summons
    local summon_defs = {
        {
            source_enemy = "Enemy_Fogger_Ranger_Armored_T3_01",
            new_template_name = "Player_Companion_SummonerOverhaul_Fell_Ranger",
            new_template_guid = make_guid("summoner_overhaul:template:fell_ranger"),
            source_spell_guid = VANILLA_ETERNAL_SKELETON_T5_GUID,
            new_item_name = "Ammo_SummonerOverhaul_Fell_Ranger_Eternal",
            new_item_guid = make_guid("summoner_overhaul:item:fell_ranger_eternal"),
            loca_key = "fell_ranger_eternal",
            display_name = "Eternal Summon: Fell Ranger",
            display_desc = "Summons an allied Fell Ranger armed with a Shroud bow that fires volleys at enemies.",
        },
        {
            source_enemy = "Enemy_Skeleton_Mage01",
            new_template_name = "Player_Companion_SummonerOverhaul_Hollow_Mage",
            new_template_guid = make_guid("summoner_overhaul:template:hollow_mage"),
            source_spell_guid = VANILLA_ETERNAL_SKELETON_T7_GUID,
            new_item_name = "Ammo_SummonerOverhaul_Hollow_Mage_Eternal",
            new_item_guid = make_guid("summoner_overhaul:item:hollow_mage_eternal"),
            loca_key = "hollow_mage_eternal",
            display_name = "Eternal Summon: Hollow Frost Mage",
            display_desc = "Summons an allied Hollow Frost Mage that bombards enemies with ice magic.",
            sub_vfx_replace = {
                old_sub_guid = "9f365b28-f4a8-42c5-b215-3cdc500bb116", -- VFX_SubEntity_Enemy_Skeleton_Melee_Chest_Smoke
                src_sub_guid = "ca1153d4-1728-4232-9334-9c13c3a86b6f", -- VFX_SubEntity_Wildlife_SpiderAnt_Light_Ranged_Coldheights
                new_sub_name = "VFX_SubEntity_SummonerOverhaul_Frost_Mage_Chest_Aura",
                new_sub_guid = make_guid("summoner_overhaul:template:frost_mage_chest_aura"),
                new_vfx_guid = nil, -- Keep Coldheights native frost VFX + VfxParametersTemplateComponent
                new_slot = "Chest",
            },
            arsenal_override = {
                src_arsenal_guid = "ad77d7d0-0ce3-439c-b238-fc619418e15a",
                new_arsenal_guid = make_guid("summoner_overhaul:arsenal:hollow_frost_mage"),
                keep_attack_guid = "dfded71c-06f5-40b4-97b7-a8d262f5ab06", -- Ice Bolt (EnsureFreePath, no summon cooldown)
            },
        },
        {
            source_enemy = "Enemy_Vukah_Shaman_Lightning",
            new_template_name = "Player_Companion_SummonerOverhaul_Vukah_Storm_Shaman",
            new_template_guid = make_guid("summoner_overhaul:template:vukah_storm_shaman"),
            source_spell_guid = VANILLA_ETERNAL_SKELETON_T5_GUID,
            new_item_name = "Ammo_SummonerOverhaul_Vukah_Storm_Shaman_Eternal",
            new_item_guid = make_guid("summoner_overhaul:item:vukah_storm_shaman_eternal"),
            loca_key = "vukah_storm_shaman_eternal",
            display_name = "Eternal Summon: Vukah Storm Shaman",
            display_desc = "Summons an allied Vukah Storm Shaman that hurls lightning spells at enemies.",
        },
        {
            source_enemy = "Enemy_Fogger_SporeHead_Mage01_AG2",
            new_template_name = "Player_Companion_SummonerOverhaul_Fell_Spore_Mage",
            new_template_guid = make_guid("summoner_overhaul:template:fell_spore_mage"),
            source_spell_guid = VANILLA_ETERNAL_SKELETON_T7_GUID,
            new_item_name = "Ammo_SummonerOverhaul_Fell_Spore_Mage_Eternal",
            new_item_guid = make_guid("summoner_overhaul:item:fell_spore_mage_eternal"),
            loca_key = "fell_spore_mage_eternal",
            display_name = "Eternal Summon: Fell Spore Mage",
            display_desc = "Summons an allied Fell Spore Mage that unleashes Shroud magic against enemies.",
        },
    }

    local items = game.assets.get_resources_by_type(item_type) or {}
    local item_by_guid = {}
    for _, item_res in ipairs(items) do
        item_by_guid[tostring(item_res.guid)] = item_res
    end
    local tex_type = game.types.get("keen::UiTextureResource")
    local ar_reg_type = game.types.get("keen::enemy::EnemyArsenalRegistryResource")

    local ref_summon_res = template_by_name["Player_Companion_Lesser_Skeleton_Weakling_Necromancy_Spell_1"]
    local created_items = {}
    for _, def in ipairs(summon_defs) do
        local enemy_res = template_by_name[def.source_enemy]
        local spell_res = item_by_guid[def.source_spell_guid]
        if not enemy_res then
            log_info("[SummonerOverhaul] WARNING: Missing enemy template: " .. def.source_enemy)
        elseif not spell_res then
            log_info("[SummonerOverhaul] WARNING: Missing base spell item: " .. def.source_spell_guid)
        else
            local new_tpl = clone_enemy_as_summon(enemy_res, ref_summon_res, template_type, def.new_template_name, def.new_template_guid)
            if new_tpl then
                if def.sub_vfx_replace then
                    local sv = def.sub_vfx_replace
                    local clone_src_guid = sv.src_sub_guid or sv.old_sub_guid
                    local src_sub = game.assets.get_resource(clone_src_guid, template_type)
                    if src_sub then
                        local new_sub = clone_vfx_sub_entity(src_sub, template_type, sv.new_sub_name, sv.new_sub_guid, sv.new_vfx_guid, sv.new_slot)
                        if new_sub then
                            replace_subentity_template(new_tpl, sv.old_sub_guid, tostring(new_sub.guid))
                        else
                            log_info("[SummonerOverhaul][FrostAura] WARNING: Failed to clone sub-entity " .. clone_src_guid)
                        end
                    else
                        log_info("[SummonerOverhaul][FrostAura] WARNING: Missing sub-entity " .. clone_src_guid)
                    end
                end
                if def.arsenal_override then
                    local ao = def.arsenal_override
                    if clone_enemy_arsenal_single_attack(ar_reg_type, ao.src_arsenal_guid, ao.new_arsenal_guid, ao.keep_attack_guid) then
                        local d = new_tpl.data
                        local ar_comp = d and d.components and find_component(d.components, "keen::ecs::EnemyArsenalReference")
                        if ar_comp and ar_comp.value then
                            ar_comp.value.arsenal = ao.new_arsenal_guid
                            new_tpl.data = d
                            local vr_comp = new_tpl.data and new_tpl.data.components and find_component(new_tpl.data.components, "keen::ecs::EnemyArsenalReference")
                            log_info(string.format("[SummonerOverhaul][MageArsenalClone] Assigned %s EnemyArsenalReference.arsenal = %s",
                                def.new_template_name, vr_comp and vr_comp.value and tostring(vr_comp.value.arsenal) or "nil"))
                        end
                    end
                end
                local actual_tpl_guid = tostring(new_tpl.guid)
                local new_item, item_name, item_guid, item_id = clone_spell_item(
                    spell_res, item_type, def.new_item_name, def.new_item_guid, actual_tpl_guid
                )
                if new_item then
                    local name_loca_guid = def.loca_key and make_guid("summoner_overhaul:loca:" .. def.loca_key .. ":name") or nil
                    local desc_loca_guid = def.loca_key and make_guid("summoner_overhaul:loca:" .. def.loca_key .. ":desc") or nil
                    local new_tex = clone_item_ui_texture(def.source_spell_guid, tex_type, tostring(new_item.guid), def.new_item_name .. "_icon")
                    table.insert(created_items, {
                        name = item_name,
                        guid = tostring(new_item.guid),
                        item_id = item_id,
                        has_tex = (new_tex ~= nil),
                        loca_name_guid = name_loca_guid,
                        loca_desc_guid = desc_loca_guid,
                        display_name = def.display_name,
                        display_desc = def.display_desc,
                        source_spell_guid = def.source_spell_guid,
                    })
                end
            end
        end
    end

    -- Register new items in ItemRegistryResource (itemRefs + dbgNames)
    if #created_items > 0 and item_reg_type then
        local regs = game.assets.get_resources_by_type(item_reg_type) or {}
        if #regs > 0 and regs[1].data then
            local reg_data = regs[1].data
            if reg_data.itemRefs then
                for _, info in ipairs(created_items) do
                    table.insert(reg_data.itemRefs, info.guid)
                    if reg_data.dbgNames then
                        table.insert(reg_data.dbgNames, info.name)
                    end
                end
                regs[1].data = reg_data
                local after_item_refs = #regs[1].data.itemRefs
                log_info(string.format("[SummonerOverhaul] Registered %d new spell items in ItemRegistryResource (itemRefs=%d, dbgNames=%d).",
                    #created_items, after_item_refs, regs[1].data.dbgNames and #regs[1].data.dbgNames or 0))
            end
        end
    end

    -- Add crafting recipes as pure Lua tables so vanilla recipes are never mutated
    local created_recipes = {}
    if #created_items > 0 and recipe_reg_type then
        local always_unlocked_id = find_always_unlocked_knowledge_id()
        local r_regs = game.assets.get_resources_by_type(recipe_reg_type) or {}
        for _, r_reg in ipairs(r_regs) do
            local r_data = r_reg.data
            if r_data and r_data.recipes then
                local before_count = #r_data.recipes
                local manual_rec, alchemist_rec, skeleton_rec = nil, nil, nil
                for _, rec in ipairs(r_data.recipes) do
                    local dn = string.lower(rec.debugName or "")
                    if dn == "ammo_spell_t0_firebolt_pk" then
                        manual_rec = rec
                    elseif not manual_rec and string.find(dn, "firebolt") then
                        manual_rec = rec
                    end
                    if not alchemist_rec and dn == "ammo_spell_t7_heal_channel_eternal" then
                        alchemist_rec = rec
                    end
                    if not skeleton_rec and rec.output and rec.output[1] then
                        local out_ref = tostring(rec.output[1].itemRef)
                        if out_ref == VANILLA_ETERNAL_SKELETON_T5_GUID or out_ref == VANILLA_ETERNAL_SKELETON_T7_GUID then
                            skeleton_rec = rec
                        end
                    end
                end

                local base_rec = CONFIG.test_mode_manual_craft and (manual_rec or skeleton_rec) or (alchemist_rec or skeleton_rec)
                if base_rec then
                    local base_workshop_guid = tostring(base_rec.workshopGuid)
                    local base_workshop_id = base_rec.workshopId and base_rec.workshopId.value or 0
                    local base_req_props = {}
                    if not CONFIG.test_mode_manual_craft and base_rec.requiredProps then
                        for _, prop in ipairs(base_rec.requiredProps) do
                            table.insert(base_req_props, { value = prop.value })
                        end
                    end
                    local base_knowledge
                    if CONFIG.test_mode_manual_craft and manual_rec and manual_rec.knowledgeRequirement then
                        local kr = manual_rec.knowledgeRequirement
                        base_knowledge = {
                            knowledgeOrQueryId = { value = kr.knowledgeOrQueryId.value },
                            compareValue = kr.compareValue,
                            compareOperator = tostring(kr.compareOperator),
                            type = tostring(kr.type),
                            isExplicitPlayerKnowledgeQuery = kr.isExplicitPlayerKnowledgeQuery,
                        }
                    elseif always_unlocked_id then
                        base_knowledge = {
                            knowledgeOrQueryId = { value = always_unlocked_id },
                            compareValue = 1,
                            compareOperator = "Equals",
                            type = "SimpleBool",
                            isExplicitPlayerKnowledgeQuery = false,
                        }
                    else
                        local kr = base_rec.knowledgeRequirement
                        base_knowledge = {
                            knowledgeOrQueryId = { value = kr.knowledgeOrQueryId.value },
                            compareValue = kr.compareValue,
                            compareOperator = tostring(kr.compareOperator),
                            type = tostring(kr.type),
                            isExplicitPlayerKnowledgeQuery = kr.isExplicitPlayerKnowledgeQuery,
                        }
                    end

                    local test_input = {
                        {
                            itemStack = {
                                itemRef = "bbb778fa-2ddb-4615-bf82-51d064a83ba4",
                                item = { value = 4109728689 },
                                count = 1,
                            },
                            inputItemCategory = {
                                categoryRef = "00000000-0000-0000-0000-000000000000",
                                category = { value = 0 },
                                count = 0,
                            },
                        }
                    }

                    for _, info in ipairs(created_items) do
                        local rec_id = hash_u32("recipe:" .. info.name)
                        local new_rec = {
                            recipeGuid = make_guid("summoner_overhaul:recipe:" .. info.name),
                            recipeId = { value = rec_id },
                            workshopGuid = base_workshop_guid,
                            workshopId = { value = base_workshop_id },
                            input = {},
                            output = {
                                {
                                    itemRef = info.guid,
                                    item = { value = info.item_id },
                                    count = 1,
                                }
                            },
                            craftingDuration = { value = 0 },
                            requiredProps = base_req_props,
                            requiredPropsMask = CONFIG.test_mode_manual_craft and 0 or base_rec.requiredPropsMask,
                            knowledgeRequirement = base_knowledge,
                            completionRequirementQuery = {
                                knowledgeOrQueryId = { value = rec_id },
                                compareValue = 2,
                                compareOperator = "Equals",
                                type = "SimpleFlag",
                                isExplicitPlayerKnowledgeQuery = true,
                            },
                            recipeName = "00000000-0000-0000-0000-000000000000",
                            debugName = "Recipe_" .. info.name,
                            level = 0,
                            comfortLevel = 0,
                            serverProgressLevel = 0,
                            requiredHappyNpcCount = 0,
                            requiredEnergy = 0,
                            waterAmount = 0,
                            waterCharges = 0,
                            levelRequirement = "None",
                            comfortLevelRequirement = "None",
                            serverProgressLevelRequirement = "None",
                            isCookingRecipe = false,
                            isUpgrade = false,
                            requiresSheltered = not CONFIG.test_mode_manual_craft,
                            showIsImportantLabel = false,
                        }

                        if CONFIG.test_mode_manual_craft then
                            new_rec.input = test_input
                        elseif skeleton_rec and skeleton_rec.input then
                            for _, inp in ipairs(skeleton_rec.input) do
                                table.insert(new_rec.input, {
                                    itemStack = {
                                        itemRef = tostring(inp.itemStack.itemRef),
                                        item = { value = inp.itemStack.item.value },
                                        count = inp.itemStack.count,
                                    },
                                    inputItemCategory = {
                                        categoryRef = tostring(inp.inputItemCategory.categoryRef),
                                        category = { value = inp.inputItemCategory.category.value },
                                        count = inp.inputItemCategory.count,
                                    },
                                })
                            end
                        end

                        table.insert(r_data.recipes, new_rec)
                        table.insert(created_recipes, {
                            recipe_id = rec_id,
                            debug_name = new_rec.debugName,
                            workshop_id = base_workshop_id,
                            anchor_recipe_id = base_rec.recipeId and base_rec.recipeId.value or 0,
                        })
                        log_info("[SummonerOverhaul] Added crafting recipe: " .. new_rec.debugName ..
                            string.format(" (id=%d workshopId=%d knowType=%s knowId=%d)",
                                rec_id, base_workshop_id, base_knowledge.type, base_knowledge.knowledgeOrQueryId.value))
                    end

                    r_reg.data = r_data
                    log_info(string.format("[SummonerOverhaul] Recipes registered: %d -> %d",
                        before_count, #r_reg.data.recipes))
                end
            end
        end
    end

    -- Register new items in ItemKnowledgeResource
    local ik_type = game.types.get("keen::ItemKnowledgeResource")
    local ik_list = ik_type and game.assets.get_resources_by_type(ik_type) or {}
    if #ik_list > 0 and #created_items > 0 then
        local ik_res = ik_list[1]
        local ik_data = ik_res.data
        local before_ik = #ik_data.keys
        for _, info in ipairs(created_items) do
            local k_tbl = { value = info.item_id }
            local v_tbl = {
                itemId = { value = info.item_id },
                lockedKnowledgeMask = { "Inspected" },
                nameLock = { unlockedLocaId = { value = 0 }, keyLocaId = { value = 0 }, unlockTrigger = {} },
                descriptionLock = { unlockedLocaId = { value = 0 }, keyLocaId = { value = 0 }, unlockTrigger = {} },
                loreLock = { unlockedLocaId = { value = 0 }, keyLocaId = { value = 0 }, unlockTrigger = {} },
                recipeLock = { unlockedLocaId = { value = 0 }, keyLocaId = { value = 0 }, unlockTrigger = {} },
            }
            local st = insert_bucket_map(ik_data, info.item_id, k_tbl, v_tbl, false, clone_ik_key, clone_ik_val)
            log_info(string.format("[SummonerOverhaul][IK] %s (%d): %s", info.name, info.item_id, st))
        end
        ik_res.data = ik_data
        log_info(string.format("[SummonerOverhaul][IK] keys before=%d after=%d", before_ik, #ik_res.data.keys))
    end

    -- Register new items and recipes in GameKnowledgeResource (worldKnowledge + playerKnowledge)
    local gk_type = game.types.get("keen::GameKnowledgeResource")
    local gk_list = gk_type and game.assets.get_resources_by_type(gk_type) or {}
    if #gk_list > 0 and (#created_items > 0 or #created_recipes > 0) then
        local gk_res = gk_list[1]
        local gk_data = gk_res.data
        local before_wk = #gk_data.worldKnowledge.keys
        local before_pk = #gk_data.playerKnowledge.keys

        for _, info in ipairs(created_items) do
            local st_wk = insert_bucket_map(
                gk_data.worldKnowledge,
                info.item_id,
                { id = { value = info.item_id } },
                {
                    id = { id = { value = info.item_id } },
                    sendToAnalytics = false,
                    hasOptionalPlayerProgression = false,
                    isPlayerKnowledge = false,
                    type = "Flags",
                    expectedFlags = 1,
                },
                true, clone_gk_key, clone_wk_val
            )
            local st_pk = insert_bucket_map(
                gk_data.playerKnowledge,
                info.item_id,
                { id = { value = info.item_id } },
                {
                    id = { id = { value = info.item_id } },
                    sendToAnalytics = false,
                    hasOptionalPlayerProgression = false,
                    isPlayerKnowledge = true,
                    type = "Flags",
                    expectedFlags = 65535,
                    isAdditionalPlayerKnowledgePerFlag = 1,
                    experienceGainId = { value = 0 },
                    unlockedSkillPoints = 0,
                },
                true, clone_gk_key, clone_pk_val
            )
            log_info(string.format("[SummonerOverhaul][GK] Item %s (%d): wk=%s pk=%s", info.name, info.item_id, st_wk, st_pk))
        end

        for _, rec in ipairs(created_recipes) do
            local st_pk = insert_bucket_map(
                gk_data.playerKnowledge,
                rec.recipe_id,
                { id = { value = rec.recipe_id } },
                {
                    id = { id = { value = rec.recipe_id } },
                    sendToAnalytics = false,
                    hasOptionalPlayerProgression = false,
                    isPlayerKnowledge = true,
                    type = "Flags",
                    expectedFlags = 3,
                    isAdditionalPlayerKnowledgePerFlag = 0,
                    experienceGainId = { value = 0 },
                    unlockedSkillPoints = 0,
                },
                true, clone_gk_key, clone_pk_val
            )
            log_info(string.format("[SummonerOverhaul][GK] Recipe %s (%d): pk=%s", rec.debug_name, rec.recipe_id, st_pk))
        end

        gk_res.data = gk_data
        log_info(string.format("[SummonerOverhaul][GK] wk keys %d->%d, pk keys %d->%d",
            before_wk, #gk_res.data.worldKnowledge.keys,
            before_pk, #gk_res.data.playerKnowledge.keys))
    end

    -- Register new recipes in FbUiBundle crafting trees so they appear in the UI
    local fb_type = game.types.get("keen::FbUiBundle")
    if fb_type and #created_recipes > 0 then
        local fb_res = game.assets.get_resource("46e14df6-fb8f-4f66-9463-e23b9e19e48e", fb_type)
        local fb_data = fb_res and fb_res.data
        local cr = fb_data and fb_data.menu and fb_data.menu.crafting and fb_data.menu.crafting.recipes
        if cr and cr.workshops and cr.trees then
            local ws_index_by_id = {}
            for wi, w in ipairs(cr.workshops) do
                ws_index_by_id[w.value] = wi
            end
            local ui_added = 0
            for _, rec in ipairs(created_recipes) do
                local ti = ws_index_by_id[rec.workshop_id]
                local tree = ti and cr.trees[ti]
                if tree and tree.groups then
                    local target_set = nil
                    local fallback_set = nil
                    for gi, grp in ipairs(tree.groups) do
                        for si, st in ipairs(grp.sets or {}) do
                            if not fallback_set and st.entries and #st.entries > 0 then
                                fallback_set = st
                            end
                            for _, en in ipairs(st.entries or {}) do
                                if en.value == rec.anchor_recipe_id then
                                    target_set = st
                                    log_info(string.format("[SummonerOverhaul][FbUi] Found anchor %d for ws=%d at grp=%d set=%d",
                                        rec.anchor_recipe_id, rec.workshop_id, gi, si))
                                    break
                                end
                            end
                            if target_set then break end
                        end
                        if target_set then break end
                    end
                    target_set = target_set or fallback_set
                    if target_set and target_set.entries then
                        local exists = false
                        for _, en in ipairs(target_set.entries) do
                            if en.value == rec.recipe_id then exists = true; break end
                        end
                        if not exists then
                            table.insert(target_set.entries, { value = rec.recipe_id })
                            ui_added = ui_added + 1
                            log_info(string.format("[SummonerOverhaul][FbUi] Added recipe %s (%d) to ws=%d UI set (entries=%d)",
                                rec.debug_name, rec.recipe_id, rec.workshop_id, #target_set.entries))
                        end
                    end
                else
                    log_info("[SummonerOverhaul][FbUi] WARNING: No UI tree found for workshopId=" .. tostring(rec.workshop_id))
                end
            end
            if ui_added > 0 then
                fb_res.data = fb_data
                log_info("[SummonerOverhaul][FbUi] Committed " .. tostring(ui_added) .. " recipes into FbUiBundle.")
            end
        end
    end

    -- Verify custom item UiTextureResource registration
    if tex_type then
        for _, info in ipairs(created_items) do
            local chk = game.assets.get_resource(info.guid, tex_type)
            log_info("[SummonerOverhaul][VerifyTex] " .. info.name .. " guid=" .. info.guid ..
                " tex_found=" .. tostring(chk ~= nil) ..
                " dbg=" .. (chk and chk.data and tostring(chk.data.debugName) or "nil"))
        end
    end

    -- Inject custom localization tags into LocaTagCollectionResource and assign custom name/desc GUIDs
    do
        local ok_loca, err_loca = pcall(function()
            local g38_type = game.types.get("keen::Game38ClientResources")
            local loca_type = game.types.get("keen::LocaTagCollectionResource")
            local loca_data_type = game.types.get("keen::LocaTagCollectionResourceData")
            local loca_tag_type = game.types.get("keen::LocaTag")
            if not (g38_type and loca_type and loca_data_type) then
                log_info("[SummonerOverhaul][Loca] Missing loca types.")
                return
            end
            local g38_list = game.assets.get_resources_by_type(g38_type) or {}
            if #g38_list == 0 or not g38_list[1].data or not g38_list[1].data.locaTagCollection then
                log_info("[SummonerOverhaul][Loca] Missing Game38ClientResources.locaTagCollection.")
                return
            end
            local lguid = tostring(g38_list[1].data.locaTagCollection)
            local lres = game.assets.get_resource(lguid, loca_type)
            local ldata = lres and lres.data
            if not ldata then
                log_info("[SummonerOverhaul][Loca] Missing LocaTagCollectionResource data.")
                return
            end

            local sample_hash = nil
            if #created_items > 0 then
                local sample_src = item_by_guid[created_items[1].source_spell_guid]
                if sample_src and sample_src.data and sample_src.data.name then
                    local sample_nguid = tostring(sample_src.data.name)
                    local hv = game.guid.hash(sample_nguid)
                    sample_hash = type(hv) == "table" and hv.value or hv
                end
            end

            local desired_tags = {}
            local desired_by_id = {}
            for _, info in ipairs(created_items) do
                if info.loca_name_guid and info.display_name then
                    local hv = game.guid.hash(info.loca_name_guid)
                    local id_u32 = type(hv) == "table" and hv.value or hv
                    local entry = { guid = info.loca_name_guid, id = id_u32, text = info.display_name }
                    table.insert(desired_tags, entry)
                    desired_by_id[id_u32] = info.display_name
                end
                if info.loca_desc_guid and info.display_desc then
                    local hv = game.guid.hash(info.loca_desc_guid)
                    local id_u32 = type(hv) == "table" and hv.value or hv
                    local entry = { guid = info.loca_desc_guid, id = id_u32, text = info.display_desc }
                    table.insert(desired_tags, entry)
                    desired_by_id[id_u32] = info.display_desc
                end
            end

            local function patch_content_ref(ref, label)
                if not ref or not ref.hash then return false end
                local c = game.assets.get_content(ref.hash)
                if not c then
                    log_info("[SummonerOverhaul][Loca] get_content nil for " .. label)
                    return false
                end
                local buf = c:read_data()
                local tbl = buf:read_resource(loca_data_type)
                if not tbl or not tbl.tags then
                    log_info("[SummonerOverhaul][Loca] read_resource failed for " .. label)
                    return false
                end

                local is_sorted = true
                local sample_found = nil
                local existing_idx = {}
                local ntags = #tbl.tags
                for i = 1, ntags do
                    local tag = tbl.tags[i]
                    local tid = tag.id.value
                    if sample_hash and tid == sample_hash then
                        sample_found = tag.text
                    end
                    if desired_by_id[tid] then
                        existing_idx[tid] = i
                    end
                    if is_sorted and i < ntags and tid > tbl.tags[i + 1].id.value then
                        is_sorted = false
                    end
                end
                log_info(string.format("[SummonerOverhaul][Loca] %s tags=%d sorted=%s sample_text=%q",
                    label, ntags, tostring(is_sorted), tostring(sample_found or "nil")))

                for _, entry in ipairs(desired_tags) do
                    local idx = existing_idx[entry.id]
                    if idx then
                        tbl.tags[idx].text = entry.text
                    else
                        local new_tag = {
                            id = { value = entry.id },
                            text = entry.text,
                            arguments = {},
                            genericArguments = 0,
                        }
                        if is_sorted then
                            local lo, hi = 1, #tbl.tags + 1
                            while lo < hi do
                                local mid = math.floor((lo + hi) / 2)
                                if tbl.tags[mid].id.value < entry.id then
                                    lo = mid + 1
                                else
                                    hi = mid
                                end
                            end
                            table.insert(tbl.tags, lo, new_tag)
                        else
                            table.insert(tbl.tags, new_tag)
                        end
                    end
                end

                local wbuf = buffer.create()
                wbuf:write_resource(loca_data_type, tbl)
                local new_c = game.assets.create_content(wbuf)
                ref.hash = {
                    size = new_c.size,
                    hash0 = new_c.hash0,
                    hash1 = new_c.hash1,
                    hash2 = new_c.hash2,
                }
                buf = nil
                tbl = nil
                wbuf = nil
                collectgarbage("collect")
                return true
            end

            local en_ok = false
            if ldata.languages then
                for _, lang_entry in ipairs(ldata.languages) do
                    if tostring(lang_entry.language) == "En_Us" then
                        en_ok = patch_content_ref(lang_entry.data, "En_Us")
                        break
                    end
                end
            end
            if en_ok then
                lres.data = ldata
            end
            log_info(string.format("[SummonerOverhaul][Loca] Patched %d tags (En_Us=%s).",
                #desired_tags, tostring(en_ok)))

            if en_ok then
                for _, info in ipairs(created_items) do
                    local ires = item_by_guid[info.guid] or game.assets.get_resource(info.guid, item_type)
                    if ires and ires.data then
                        local idata = ires.data
                        if info.loca_name_guid then idata.name = info.loca_name_guid end
                        if info.loca_desc_guid then idata.description = info.loca_desc_guid end
                        ires.data = idata
                    end
                end
            end
        end)
        if not ok_loca then
            log_info("[SummonerOverhaul][Loca] ERROR: " .. tostring(err_loca))
        end
    end

    -- Targeted inspection for Death Coil ImpactConfigs + Skeleton7 Pet AI features
    do
        local function dump_val(v, depth)
            depth = depth or 0
            local tv = type(v)
            if tv == "string" then return string.format("%q", v) end
            if tv ~= "table" and tv ~= "userdata" then return tostring(v) end
            if depth >= 4 then return tostring(v) end
            if tv == "userdata" then
                local ok_var, vtype, vval = pcall(function() return v.type, v.value end)
                if ok_var and vtype ~= nil then
                    return string.format("Variant(%s)=%s", tostring(vtype), dump_val(vval, depth + 1))
                end
            end
            local ok_iter, kvs = pcall(function()
                local out = {}
                local n = 0
                for k, val in pairs(v) do
                    n = n + 1
                    if n <= 30 then
                        table.insert(out, tostring(k) .. "=" .. dump_val(val, depth + 1))
                    end
                end
                if n > 30 then table.insert(out, "...(" .. tostring(n) .. ")") end
                return "{ " .. table.concat(out, ", ") .. " }"
            end)
            if ok_iter then return kvs end
            return tostring(v)
        end

        local want_comps = {
            ["keen::ecs::Impact"] = true,
            ["keen::ecs::ImpactConfiguration"] = true,
            ["keen::ecs::EntityTagContainer"] = true,
            ["keen::ecs::DamageMod"] = true,
            ["keen::ecs::VfxComponentResource"] = true,
            ["keen::ecs::ModelResource"] = true,
            ["keen::ecs::OnDestroy"] = true,
            ["keen::ecs::HomeToTarget"] = true,
            ["keen::ecs::Enemy01BehaviorState"] = true,
        }

        local function inspect_key_comps(label, guid)
            local res = game.assets.get_resource(guid, template_type)
            if not (res and res.data) then
                log_info("[SummonerOverhaul][DCInspect] " .. label .. " NOT FOUND (" .. guid .. ")")
                return
            end
            for _, c in ipairs(res.data.components or {}) do
                local ct = tostring(c.type)
                if want_comps[ct] then
                    if ct == "keen::ecs::Enemy01BehaviorState" and c.value then
                        local b = c.value
                        log_info(string.format("[SummonerOverhaul][DCInspect] %s.Enemy01BehaviorState class=%s feats=%s guard=%s",
                            label, tostring(b.enemyClass), dump_val(b.enabledFeatures, 0), dump_val(b.guardSetup, 0)))
                    else
                        log_info("[SummonerOverhaul][DCInspect] " .. label .. "." .. ct .. " = " .. dump_val(c.value, 0))
                    end
                end
            end
        end

        inspect_key_comps("Fireball7.Entity", "4fb3b34b-70f4-430e-977c-a7e089ebb965")
        inspect_key_comps("Fireball7.Explosion", "e10c447f-0b79-46ec-86cd-c86f7105a104")
        inspect_key_comps("SkullSummonProj", "c5ac5682-eb3f-442c-ba89-c3bd8642597e")
        inspect_key_comps("SkullSummonProj.Spawn", "35a92515-f04d-4daa-bd42-cb82e12764ce")
        inspect_key_comps("HealChannel7.Entity", "329feabf-6894-4e96-a111-2bb2fb0ef157")
        inspect_key_comps("HealChannel7.AoE", "2c411630-8a38-41a3-b3d2-a263609a1bdb")
        inspect_key_comps("Skeleton7.Entity", "d6d858ec-8df0-40e1-9aac-250558ff304e")

        local function inspect_all_comp_names(label, tpl_guid)
            local r = game.assets.get_resource(tpl_guid, template_type)
            if not (r and r.data and r.data.components) then
                log_info("[SummonerOverhaul][DCInspect] " .. label .. " NOT FOUND for allComps")
                return
            end
            local names = {}
            for _, c in ipairs(r.data.components) do
                table.insert(names, tostring(c.type))
            end
            log_info(string.format("[SummonerOverhaul][DCInspect] %s allComps(%d): %s", label, #names, table.concat(names, ", ")))
        end
        inspect_all_comp_names("HealChannel7.AoE", "2c411630-8a38-41a3-b3d2-a263609a1bdb")
        inspect_all_comp_names("SkullSummonProj.Spawn", "35a92515-f04d-4daa-bd42-cb82e12764ce")
        inspect_all_comp_names("Fireball7.Explosion", "e10c447f-0b79-46ec-86cd-c86f7105a104")

        local hc_aoe = game.assets.get_resource("2c411630-8a38-41a3-b3d2-a263609a1bdb", template_type)
        if hc_aoe and hc_aoe.data and hc_aoe.data.components then
            for _, c in ipairs(hc_aoe.data.components) do
                local ct = tostring(c.type)
                if not want_comps[ct] then
                    log_info("[SummonerOverhaul][DCInspect] HealChannel7.AoE." .. ct .. " = " .. dump_val(c.value, 0))
                end
            end
        end

        local function inspect_item_fields(label, item_res)
            if not (item_res and item_res.data) then return end
            local ok, err = pcall(function()
                local d = item_res.data
                local eq = d.equipment
                log_info(string.format("[SummonerOverhaul][DCInspect] Item %s: maxStack=%s rarity=%s consume=%s checkReq=%s vis=%s placed=%s prog=%s impEnt=%s",
                    label, tostring(d.maxStackSize), tostring(d.rarity),
                    eq and tostring(eq.placementConsume) or "nil",
                    (eq and eq.cursorConfig) and tostring(eq.cursorConfig.checkRequiredMaterialsOnPrimaryAction) or "nil",
                    eq and tostring(eq.visualEntity) or "nil",
                    eq and tostring(eq.placedEntity) or "nil",
                    eq and tostring(eq.program) or "nil",
                    eq and tostring(eq.impactEntity) or "nil"))
                if d.impactValues then
                    log_info("[SummonerOverhaul][DCInspect]   impactValues=" .. dump_val(d.impactValues, 0))
                end
                if eq and eq.requiredCraftingIngredients then
                    log_info("[SummonerOverhaul][DCInspect]   reqIng=" .. dump_val(eq.requiredCraftingIngredients, 0))
                end
            end)
            if not ok then
                log_info("[SummonerOverhaul][DCInspect] Item " .. label .. " inspect err: " .. tostring(err))
            end
        end
        inspect_key_comps("HealChain3.Entity", "3b25e6e9-5d83-4360-baea-5178ce43807a")
        inspect_all_comp_names("HealChain3.Entity", "3b25e6e9-5d83-4360-baea-5178ce43807a")

        for g, res in pairs(item_by_guid) do
            local dn = res.data and tostring(res.data.debugName) or ""
            if dn:find("Spell_") and (dn:find("Heal") or dn:find("Acid") or dn:find("Meteor") or dn:find("Eternal") or dn:find("Shroud") or dn:find("Skeleton") or dn:find("Frost")) then
                local eq = res.data.equipment
                local placed = eq and tostring(eq.placedEntity) or "nil"
                log_info(string.format("[SummonerOverhaul][DCInspect2] Spell %s (%s) placed=%s vis=%s",
                    dn, g, placed, eq and tostring(eq.visualEntity) or "nil"))
                if (dn:find("Acid") or dn:find("Meteor") or dn:find("Heal_Aura") or dn:find("Chain")) and placed ~= "00000000-0000-0000-0000-000000000000" and placed ~= "nil" then
                    inspect_key_comps(dn .. ".Placed", placed)
                    inspect_all_comp_names(dn .. ".Placed", placed)
                end
            end
        end

        -- 1. Probe types for Mage Arsenal / Sequences / VFX / Impacts
        local probe_type_names = {
            "keen::enemy::EnemyArsenalRegistryResource",
            "keen::ActorSequenceCollectionResource",
            "keen::ActorSequenceResource",
            "keen::AnimationGraphResource",
            "keen::ImpactRegistryResource",
            "keen::ImpactDefinition",
            "keen::VfxResource",
        }
        local found_types = {}
        for _, tname in ipairs(probe_type_names) do
            local tobj = game.types.get(tname)
            if tobj then
                found_types[tname] = tobj
                local rlist = game.assets.get_resources_by_type(tobj) or {}
                log_info(string.format("[SummonerOverhaul][MageArsenalDetail] Type %s -> count=%d", tname, #rlist))
            else
                log_info(string.format("[SummonerOverhaul][MageArsenalDetail] Type %s -> nil", tname))
            end
        end

        -- 2. Inspect ActorSequenceResource for Enemy_Skeleton_Mage01's two attacks
        local seq_type = game.types.get("keen::actor::ActorSequenceResource")
        for _, sq in ipairs({
            {"Atk1_11393442", "11393442-065e-424a-b076-d8038b68d8c7"},
            {"Atk2_e087e5bb", "e087e5bb-1cce-4bea-8cf4-76f204cad9d4"},
        }) do
            local sres = seq_type and game.assets.get_resource(sq[2], seq_type) or nil
            log_info(string.format("[SummonerOverhaul][MageArsenalDetail] Seq %s (%s) -> res=%s data=%s",
                sq[1], sq[2], tostring(sres ~= nil), sres and dump_val(sres.data, 2) or "nil"))
        end

        -- 3. Inspect VFX sub-entities in full detail (SlotAttachment, VfxComponent, VfxParametersTemplateComponent)
        local function dump_tpl_comps(label, guid_str, wanted_set)
            local r = game.assets.get_resource(guid_str, template_type)
            if not r or not r.data or not r.data.components then
                log_info("[SummonerOverhaul][VfxInspect2] " .. label .. " -> MISSING (" .. guid_str .. ")")
                return
            end
            for _, c in ipairs(r.data.components) do
                local ct = tostring(c.type)
                if not wanted_set or wanted_set[ct] then
                    log_info(string.format("[SummonerOverhaul][VfxInspect2] %s.%s = %s", label, ct, dump_val(c.value, 3)))
                end
            end
        end
        local vfx_sub_comps = {
            ["keen::ecs::SlotAttachment"] = true,
            ["keen::ecs::VfxComponent"] = true,
            ["keen::ecs::VfxComponentResource"] = true,
            ["keen::ecs::VfxParametersTemplateComponent"] = true,
        }
        for _, p in ipairs({
            {"Mage01.SubChest", "9f365b28-f4a8-42c5-b215-3cdc500bb116"},
            {"ColdheightsRangedSub", "ca1153d4-1728-4232-9334-9c13c3a86b6f"},
            {"Skel7.SubChest", "018604bc-b07d-4b3c-997b-00a0addfa800"},
            {"Skel7.SubRoot", "9852b802-6210-4122-82f6-d2bf5e0c277a"},
            {"FrostMageChestAuraClone", make_guid("summoner_overhaul:template:frost_mage_chest_aura")},
        }) do
            dump_tpl_comps(p[1], p[2], vfx_sub_comps)
        end

        -- 4. List all VFX_SubEntity* and VFX_Ability* templates + their SlotAttachment & VfxResource
        local sub_names = {}
        for tname, _ in pairs(template_by_name) do
            if tname:find("^VFX_SubEntity") or tname:find("^VFX_Ability") then
                table.insert(sub_names, tname)
            end
        end
        table.sort(sub_names)
        log_info(string.format("[SummonerOverhaul][VfxInspect2] Found %d VFX_SubEntity/VFX_Ability templates:", #sub_names))
        for _, tname in ipairs(sub_names) do
            local tres = template_by_name[tname]
            local slot_v, vfx_v = "-", "-"
            if tres and tres.data and tres.data.components then
                local sc = find_component(tres.data.components, "keen::ecs::SlotAttachment")
                if sc and sc.value then
                    local ok_s, sv = pcall(function() return sc.value.slot end)
                    if ok_s and sv then slot_v = tostring(sv) end
                end
                local vc = find_component(tres.data.components, "keen::ecs::VfxComponentResource")
                if vc and vc.value then vfx_v = tostring(vc.value.vfx) end
            end
            log_info(string.format("  %s (%s) slot=%s vfx=%s", tname, tostring(tres.guid), slot_v, vfx_v))
        end

        -- 5. Brief check on Player_Companion_SummonerOverhaul_Hollow_Mage components (skip huge Actor dump)
        local hmage = template_by_name["Player_Companion_SummonerOverhaul_Hollow_Mage"]
        if hmage and hmage.data and hmage.data.components then
            local ar_c = find_component(hmage.data.components, "keen::ecs::EnemyArsenalReference")
            local se_c = find_component(hmage.data.components, "keen::ecs::SubEntities")
            log_info("[SummonerOverhaul][MageArsenalDetail] HollowMageClone arsenal=" .. (ar_c and ar_c.value and tostring(ar_c.value.arsenal) or "nil"))
            log_info("[SummonerOverhaul][MageArsenalDetail] HollowMageClone SubEntities=" .. (se_c and dump_val(se_c.value, 2) or "nil"))
        end

        collectgarbage("collect")
    end
end

if type(runtime) == "table" and runtime.phase == "pregame" then
    run_pregame_patch()
    return {}
end

return {}
