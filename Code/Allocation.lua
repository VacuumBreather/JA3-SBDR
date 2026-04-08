--- @module ModAllocation
--- @desc Handles ammo and craftables allocation among squads in the same sector.

if not SquadBagDoneRight then SquadBagDoneRight = {} end

local function GetSquadsInSector(sector_id)
    local squads = {}
    for _, squad in pairs(gv_Squads or {}) do
        if squad.CurrentSector == sector_id and squad.Side == "player1" then
            table.insert(squads, squad)
        end
    end
    return squads
end

--- Allocates ammo in the squad bags of all squads in the current sector according to the weapons being used.
--- @param sector_id string Optional sector ID to use.
function SquadBagDoneRight:AllocateAmmoInSector(sector_id, squads)
    sector_id = sector_id or gv_CurrentSectorId
    if not sector_id then return end
    
    squads = squads or GetSquadsInSector(sector_id)
    if #squads <= 1 then
        -- print("[SBDR] AllocateAmmoInSector: Not enough squads in sector " .. tostring(sector_id))
        return 
    end

    -- print("[SBDR] AllocateAmmoInSector: Starting for sector " .. tostring(sector_id))

    -- 1. Gather all ammo from all squad bags in the sector
    local total_ammo = {} -- { [caliber] = { [class] = { items = {}, total_amount = 0 } } }
    for _, squad in ipairs(squads) do
        local bag = squad.squad_bag or {}
        local count = 0
        for i = #bag, 1, -1 do
            local item = bag[i]
            if IsKindOf(item, "Ammo") or IsKindOf(item, "Ordnance") or item.class == "FlareAmmo" or string.starts_with(item.class, "MortarShell_") or string.starts_with(item.class, "_40mm") then
                local caliber = item.Caliber or "Other"
                -- Specific mapping for Warheads if they don't have it set correctly or for legacy reasons
                if item.class == "Warhead_Frag" then caliber = "Warhead" end
                
                total_ammo[caliber] = total_ammo[caliber] or {}
                total_ammo[caliber][item.class] = total_ammo[caliber][item.class] or { items = {}, total_amount = 0 }
                
                local amt = (item.Amount or 1)
                table.insert(total_ammo[caliber][item.class].items, item)
                total_ammo[caliber][item.class].total_amount = total_ammo[caliber][item.class].total_amount + amt
                -- print(string.format("[SBDR] AllocateAmmoInSector: Collected %d of %s from squad %s (caliber: %s)", amt, item.class, tostring(squad.UniqueId), caliber))
                table.remove(bag, i)
                count = count + amt
            end
        end
        -- print(string.format("[SBDR] AllocateAmmoInSector: Collected total %d ammo items from squad %s", count, tostring(squad.UniqueId)))
    end

    -- 2. Calculate total mag size per caliber for each squad
    local squad_needs = {} -- { [squad_id] = { [caliber] = total_mag_size } }
    local total_needs_per_caliber = {} -- { [caliber] = total_mag_size_all_squads }

    for _, squad in ipairs(squads) do
        local squad_id = squad.UniqueId
        squad_needs[squad_id] = {}
        -- print(string.format("[SBDR] AllocateAmmoInSector: Calculating needs for squad %s", tostring(squad_id)))
        
        for _, unit_id in ipairs(squad.units or {}) do
            local unit = gv_UnitData[unit_id]
            if unit then
                unit:ForEachItem("FirearmBase", function(item)
                    local caliber = item.Caliber
                    if caliber then
                        local mag_size = item.MagazineSize or 0
                        squad_needs[squad_id][caliber] = (squad_needs[squad_id][caliber] or 0) + mag_size
                        total_needs_per_caliber[caliber] = (total_needs_per_caliber[caliber] or 0) + mag_size
                        -- print(string.format("[SBDR] AllocateAmmoInSector:   Weapon %s found for unit %s, adding %d to caliber %s need", item.class, tostring(unit_id), mag_size, caliber))
                    end
                end)
                -- Heavy weapons (Mortars, Rocket Launchers)
                unit:ForEachItem("HeavyWeapon", function(item)
                    local caliber = item.Caliber
                    if not caliber and IsKindOf(item, "Mortar") then caliber = "MortarShell" end
                    if caliber then
                        local mag_size = item.MagazineSize or 1
                        squad_needs[squad_id][caliber] = (squad_needs[squad_id][caliber] or 0) + mag_size
                        total_needs_per_caliber[caliber] = (total_needs_per_caliber[caliber] or 0) + mag_size
                        -- print(string.format("[SBDR] AllocateAmmoInSector:   Heavy weapon %s found for unit %s, adding %d to caliber %s need", item.class, tostring(unit_id), mag_size, caliber))
                    end
                end)
            end
        end
        for cal, need in pairs(squad_needs[squad_id]) do
             -- print(string.format("[SBDR] AllocateAmmoInSector: Squad %s need for %s is %d", tostring(squad_id), cal, need))
        end
    end

    -- 3. Distribute ammo back to squads
    for caliber, classes in pairs(total_ammo) do
        local total_need = total_needs_per_caliber[caliber] or 0
        local caliber_total_amount = 0
        for _, data in pairs(classes) do
            caliber_total_amount = caliber_total_amount + data.total_amount
        end
        -- print(string.format("[SBDR] AllocateAmmoInSector: Distributing %s (Total amount across types: %d, Total need: %d)", caliber, caliber_total_amount, total_need))
        
        for class_id, data in pairs(classes) do
            local remaining_amount = data.total_amount
            -- print(string.format("[SBDR] AllocateAmmoInSector: Type %s, Total: %d", class_id, remaining_amount))
            
            if total_need > 0 then
                -- Distribute proportionally
                for i, squad in ipairs(squads) do
                    local squad_id = squad.UniqueId
                    local squad_need = squad_needs[squad_id][caliber] or 0
                    local share = 0
                    
                    if i == #squads then
                        share = remaining_amount
                    else
                        share = MulDivRound(data.total_amount, squad_need, total_need)
                        share = Min(share, remaining_amount)
                    end
                    
                    if share > 0 then
                        local new_item = PlaceInventoryItem(class_id)
                        if IsKindOf(new_item, "InventoryStack") then
                            new_item.Amount = share
                        end
                        squad.squad_bag = squad.squad_bag or {}
                        table.insert(squad.squad_bag, new_item)
                        remaining_amount = remaining_amount - share
                        -- print(string.format("[SBDR] AllocateAmmoInSector:   -> Squad %s gets %d of %s (proportional, squad need %d / total need %d)", tostring(squad_id), share, class_id, squad_need, total_need))
                    end
                end
            else
                -- No squad uses this caliber, distribute by squad member count
                local total_units = 0
                for _, squad in ipairs(squads) do
                    total_units = total_units + #(squad.units or {})
                end
                
                -- print(string.format("[SBDR] AllocateAmmoInSector: No direct need for %s, distributing by squad member count (total units: %d)", class_id, total_units))
                for i, squad in ipairs(squads) do
                    local squad_id = squad.UniqueId
                    local num_units = #(squad.units or {})
                    local share = 0
                    
                    if total_units > 0 then
                        if i == #squads then
                            share = remaining_amount
                        else
                            share = MulDivRound(data.total_amount, num_units, total_units)
                            share = Min(share, remaining_amount)
                        end
                    else
                        -- Fallback for empty squads (shouldn't happen in player1 squads usually)
                        share = (i == #squads) and remaining_amount or (data.total_amount / #squads)
                    end
                    
                    if share > 0 then
                        local new_item = PlaceInventoryItem(class_id)
                        if IsKindOf(new_item, "InventoryStack") then
                            new_item.Amount = share
                        end
                        squad.squad_bag = squad.squad_bag or {}
                        table.insert(squad.squad_bag, new_item)
                        remaining_amount = remaining_amount - share
                        -- print(string.format("[SBDR] AllocateAmmoInSector:   -> Squad %s gets %d of %s (weighted share, %d units)", tostring(squad_id), share, class_id, num_units))
                    end
                end
            end
            
            -- Clean up old items
            for _, item in ipairs(data.items) do
                DoneObject(item)
            end
        end
    end

    -- Re-sort all bags. UI is refreshed in _SortItemsInBag.
    for _, squad in ipairs(squads) do
        -- print(string.format("[SBDR] AllocateAmmoInSector: Sorting bag for squad %s", tostring(squad.UniqueId)))
        _SortItemsInBag(squad.UniqueId)
    end
end

--- Allocates craftables according to skills.
--- @param sector_id string Optional sector ID to use.
function SquadBagDoneRight:AllocateCraftablesInSector(sector_id, squads)
    sector_id = sector_id or gv_CurrentSectorId
    if not sector_id then return end
    
    squads = squads or GetSquadsInSector(sector_id)
    if #squads <= 1 then 
        -- print("[SBDR] AllocateCraftablesInSector: Not enough squads in sector " .. tostring(sector_id))
        return 
    end

    -- print("[SBDR] AllocateCraftablesInSector: Starting for sector " .. tostring(sector_id))

    -- Define item groups
    local explosives_items = { "C4", "PETN", "TNT", "Combination_Detonator_Proximity", "Combination_Detonator_Remote", "Combination_Detonator_Time" }
    local mechanical_items = { "FineSteelPipe", "OpticalLens", "Microchip", "Combination_BalancingWeight", "Combination_Sharpener", "Parts" }
    local armor_upgrades = { "Combination_CeramicPlates", "Combination_WeavePadding", "Combination_Kompositum58" }

    local function distribute_group(item_list, skill_name)
        local total_items = {} -- { [class] = total_amount }
        local items_to_destroy = {}

        -- Collect items
        for _, squad in ipairs(squads) do
            local bag = squad.squad_bag or {}
            local squad_item_count = 0
            for i = #bag, 1, -1 do
                local item = bag[i]
                if table.find(item_list, item.class) then
                    local amt = (IsKindOf(item, "InventoryStack") and item.Amount or 1)
                    total_items[item.class] = (total_items[item.class] or 0) + amt
                    -- print(string.format("[SBDR] AllocateCraftablesInSector: Collected %d of %s from squad %s", amt, item.class, tostring(squad.UniqueId)))
                    table.insert(items_to_destroy, item)
                    table.remove(bag, i)
                    squad_item_count = squad_item_count + amt
                end
            end
            if squad_item_count > 0 then
                -- print(string.format("[SBDR] AllocateCraftablesInSector: Collected total %d items from list in squad %s", squad_item_count, tostring(squad.UniqueId)))
            end
        end

        if next(total_items) == nil then 
            -- print("[SBDR] AllocateCraftablesInSector: No items found for skill " .. skill_name)
            return 
        end

        -- Determine max skills (ignoring mercs with skill < 60)
        local squad_skills = {}
        local total_skill = 0
        for _, squad in ipairs(squads) do
            local max_skill = 0
            for _, unit_id in ipairs(squad.units or {}) do
                local unit = gv_UnitData[unit_id]
                if unit then
                    local skill_val = unit[skill_name] or 0
                    if skill_val >= 60 then
                        max_skill = Max(max_skill, skill_val)
                    else
                        -- print(string.format("[SBDR] AllocateCraftablesInSector: Ignoring merc %s in squad %s (skill %d < 60)", tostring(unit_id), tostring(squad.UniqueId), skill_val))
                    end
                end
            end
            squad_skills[squad.UniqueId] = max_skill
            total_skill = total_skill + max_skill
            -- print(string.format("[SBDR] AllocateCraftablesInSector: Squad %s effective max %s skill: %d", tostring(squad.UniqueId), skill_name, max_skill))
        end

        -- Distribute
        for class_id, total_amount in pairs(total_items) do
            local remaining = total_amount
            -- print(string.format("[SBDR] AllocateCraftablesInSector: Distributing %d of %s (Total skill: %d)", total_amount, class_id, total_skill))
            for i, squad in ipairs(squads) do
                local share = 0
                if total_skill > 0 then
                    if i == #squads then
                        share = remaining
                    else
                        share = MulDivRound(total_amount, squad_skills[squad.UniqueId], total_skill)
                        share = Min(share, remaining)
                    end
                else
                    -- No skill at all (all squads either have no mercs or all below 60), distribute by squad member count
                    local total_units = 0
                    for _, s in ipairs(squads) do
                        total_units = total_units + #(s.units or {})
                    end
                    
                    local num_units = #(squad.units or {})
                    if total_units > 0 then
                        if i == #squads then
                            share = remaining
                        else
                            share = MulDivRound(total_amount, num_units, total_units)
                            share = Min(share, remaining)
                        end
                    else
                        -- Fallback for empty squads
                        share = (i == #squads) and remaining or (total_amount / #squads)
                    end
                end

                if share > 0 then
                    -- print(string.format("[SBDR] AllocateCraftablesInSector:   -> Squad %s gets %d of %s (share based on skill %d)", tostring(squad.UniqueId), share, class_id, squad_skills[squad.UniqueId] or 0))
                    local new_item = PlaceInventoryItem(class_id)
                    if IsKindOf(new_item, "InventoryStack") then
                        new_item.Amount = share
                    end
                    squad.squad_bag = squad.squad_bag or {}
                    table.insert(squad.squad_bag, new_item)
                    remaining = remaining - share
                end
            end
        end

        for _, item in ipairs(items_to_destroy) do
            DoneObject(item)
        end
    end

    distribute_group(explosives_items, "Explosives")
    distribute_group(mechanical_items, "Mechanical")
    distribute_group(armor_upgrades, "Mechanical")

    -- Re-sort all bags. UI is refreshed in _SortItemsInBag.
    for _, squad in ipairs(squads) do
        -- print(string.format("[SBDR] AllocateCraftablesInSector: Sorting bag for squad %s", tostring(squad.UniqueId)))
        _SortItemsInBag(squad.UniqueId)
    end
end

--- Allocates meds according to med kits.
--- @param sector_id string Optional sector ID to use.
function SquadBagDoneRight:AllocateMedsInSector(sector_id, squads)
    sector_id = sector_id or gv_CurrentSectorId
    if not sector_id then return end
    
    squads = squads or GetSquadsInSector(sector_id)
    if #squads <= 1 then 
        -- print("[SBDR] AllocateMedsInSector: Not enough squads in sector " .. tostring(sector_id))
        return 
    end

    -- print("[SBDR] AllocateMedsInSector: Starting for sector " .. tostring(sector_id))

    local total_meds = 0
    local items_to_destroy = {}

    -- 1. Collect all Meds from all squad bags
    for _, squad in ipairs(squads) do
        local bag = squad.squad_bag or {}
        -- print(string.format("[SBDR] AllocateMedsInSector: Scanning squad %s bag", tostring(squad.UniqueId)))
        for i = #bag, 1, -1 do
            local item = bag[i]
            if item.class == "Meds" then
                local amt = (item.Amount or 1)
                total_meds = total_meds + amt
                -- print(string.format("[SBDR] AllocateMedsInSector: Collected %d Meds from squad %s", amt, tostring(squad.UniqueId)))
                table.insert(items_to_destroy, item)
                table.remove(bag, i)
            end
        end
    end

    if total_meds > 0 then
        -- 2. Determine "need" based on med kits
        local squad_needs = {}
        local total_need = 0
        for _, squad in ipairs(squads) do
            local has_kit = false
            for _, unit_id in ipairs(squad.units or {}) do
                local unit = gv_UnitData[unit_id]
                if unit and (unit:GetItem("Medkit") or unit:GetItem("FirstAidKit") or unit:GetItem("Reanimationsset")) then
                    has_kit = true
                    break
                end
            end
            local need = has_kit and 1 or 0
            squad_needs[squad.UniqueId] = need
            total_need = total_need + need
            -- print(string.format("[SBDR] AllocateMedsInSector: Squad %s has kit: %s", tostring(squad.UniqueId), tostring(has_kit)))
        end

        -- 3. Distribute back
        local remaining = total_meds
        for i, squad in ipairs(squads) do
            local share = 0
            if total_need > 0 then
                if i == #squads then
                    share = remaining
                else
                    share = MulDivRound(total_meds, squad_needs[squad.UniqueId], total_need)
                    share = Min(share, remaining)
                end
            else
                -- No one has a medkit, distribute by squad member count
                local total_units = 0
                for _, s in ipairs(squads) do
                    total_units = total_units + #(s.units or {})
                end
                
                local num_units = #(squad.units or {})
                if total_units > 0 then
                    if i == #squads then
                        share = remaining
                    else
                        share = MulDivRound(total_meds, num_units, total_units)
                        share = Min(share, remaining)
                    end
                else
                    -- Fallback for empty squads
                    share = (i == #squads) and remaining or (total_meds / #squads)
                end
            end

            if share > 0 then
                -- print(string.format("[SBDR] AllocateMedsInSector:   -> Squad %s gets %d Meds (need %d/%d)", tostring(squad.UniqueId), share, squad_needs[squad.UniqueId] or 0, total_need))
                local new_item = PlaceInventoryItem("Meds")
                new_item.Amount = share
                squad.squad_bag = squad.squad_bag or {}
                table.insert(squad.squad_bag, new_item)
                remaining = remaining - share
            end
        end

        -- Clean up
        for _, item in ipairs(items_to_destroy) do
            DoneObject(item)
        end

        -- Re-sort all bags. UI is refreshed in _SortItemsInBag.
        for _, squad in ipairs(squads) do
            -- print(string.format("[SBDR] AllocateMedsInSector: Sorting bag for squad %s", tostring(squad.UniqueId)))
            _SortItemsInBag(squad.UniqueId)
        end
    end
end

--- Allocates all squad bag items (ammo, craftables, meds) in a sector.
--- @param sector_id string Optional sector ID to use.
function SquadBagDoneRight:AllocateAllInSector(sector_id)
    sector_id = sector_id or gv_CurrentSectorId
    if not sector_id then return end

    local squads = GetSquadsInSector(sector_id)
    if #squads <= 1 then 
        -- print("[SBDR] AllocateAllInSector: Not enough squads in sector " .. tostring(sector_id))
        return 
    end

    -- print("[SBDR] AllocateAllInSector: Starting for sector " .. tostring(sector_id))
    self:AllocateAmmoInSector(sector_id, squads)
    self:AllocateCraftablesInSector(sector_id, squads)
    self:AllocateMedsInSector(sector_id, squads)
    -- print("[SBDR] AllocateAllInSector: Finished.")
end
