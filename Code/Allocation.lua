--- @module ModAllocation
--- @desc Handles ammo and craftables allocation among squads in the same sector.

-- Use rawget to bypass the engine's strict mode check for undefined globals
if rawget(_G, "SquadBagDoneRight") == nil then
	SquadBagDoneRight = {}
end
local InventoryStackClass = SquadBagDoneRight.InventoryStackClass or "InventoryStack"
local SquadBagItemClass = SquadBagDoneRight.SquadBagItemClass or "SquadBagItem"

-- Helper to find player squads in a specific sector
local function GetSquadsInSector(sector_id)
	local squads = {}
	-- Loop through all global squads and filter by sector and player ownership
	for _, squad in pairs(gv_Squads or {}) do
		if squad.CurrentSector == sector_id and squad.Side == "player1" then
			table.insert(squads, squad)
		end
	end
	return squads
end

--- Allocates ammo in the squad bags of all squads in the current sector according to the weapons being used.
--- @param sector_id string Optional sector ID to use.
--- @param squads table Optional pre-filtered list of squads.
function SquadBagDoneRight:AllocateAmmoInSector(sector_id, squads)
	sector_id = sector_id or gv_CurrentSectorId
	if not sector_id then return end

	-- Ensure there are at least two squads to balance between
	squads = squads or GetSquadsInSector(sector_id)
	if #squads <= 1 then
		return
	end

	-- 1. COLLECTION PHASE: Gather all ammo from all player squad bags in the sector
	local total_ammo = {} -- Map: { [caliber] = { [class] = { items = {}, total_amount = 0 } } }
	local items_to_destroy = {} -- List of original item objects to be removed later
	for _, squad in ipairs(squads) do
		local bag = squad.squad_bag or {}
		-- Traverse bag backwards to safely remove items while iterating
		for i = #bag, 1, -1 do
			local item = bag[i]
			-- Identify ammo, ordnance, and heavy weapon shells
			if IsKindOf(item, "Ammo") or IsKindOf(item, "Ordnance") or item.class == "FlareAmmo" or string.starts_with(item.class, "MortarShell_") or string.starts_with(item.class, "_40mm") then
				local caliber = item.Caliber or "Other"
				-- Manual override for certain item classes if needed
				if item.class == "Warhead_Frag" then caliber = "Warhead" end

				-- Group items by caliber and class ID
				total_ammo[caliber] = total_ammo[caliber] or {}
				total_ammo[caliber][item.class] = total_ammo[caliber][item.class] or { items = {}, total_amount = 0 }

				local amt = (item.Amount or 1)
				total_ammo[caliber][item.class].total_amount = total_ammo[caliber][item.class].total_amount + amt

				-- Store for safe destruction and remove from the current bag
				table.insert(items_to_destroy, item)
				table.remove(bag, i)
			end
		end
	end

	-- 2. NEEDS ASSESSMENT: Calculate the total magazine capacity for each caliber per squad
	local squad_needs = {} -- Map: { [squad_id] = { [caliber] = total_mag_size } }
	local total_needs_per_caliber = {} -- Map: { [caliber] = total_mag_size_all_squads }

	for _, squad in ipairs(squads) do
		local squad_id = squad.UniqueId
		squad_needs[squad_id] = {}

		-- Check every mercenary's equipment
		for _, unit_id in ipairs(squad.units or {}) do
			local unit = gv_UnitData[unit_id]
			if unit then
				-- Check standard firearms
				unit:ForEachItem("FirearmBase", function(item)
					local caliber = item.Caliber
					if caliber then
						local mag_size = item.MagazineSize or 0
						squad_needs[squad_id][caliber] = (squad_needs[squad_id][caliber] or 0) + mag_size
						total_needs_per_caliber[caliber] = (total_needs_per_caliber[caliber] or 0) + mag_size
					end
				end)
				-- Check heavy weapons (Mortars, Rocket Launchers)
				unit:ForEachItem("HeavyWeapon", function(item)
					local caliber = item.Caliber
					if not caliber and IsKindOf(item, "Mortar") then caliber = "MortarShell" end
					if caliber then
						local mag_size = item.MagazineSize or 1
						squad_needs[squad_id][caliber] = (squad_needs[squad_id][caliber] or 0) + mag_size
						total_needs_per_caliber[caliber] = (total_needs_per_caliber[caliber] or 0) + mag_size
					end
				end)
			end
		end
	end

	-- 3. DISTRIBUTION PHASE: Allocate gathered ammo back to squads based on needs
	local new_items_per_squad = {} -- Map: { [squad_id] = { new_item1, new_item2, ... } }
	local success = true

	for caliber, classes in pairs(total_ammo) do
		local total_need = total_needs_per_caliber[caliber] or 0

		for class_id, data in pairs(classes) do
			local remaining_amount = data.total_amount

			if total_need > 0 then
				-- OPTION A: Distribute ammo proportionally based on weapon magazine capacity
				for i, squad in ipairs(squads) do
					local squad_id = squad.UniqueId
					local squad_need = squad_needs[squad_id][caliber] or 0
					local share = 0

					-- Last squad gets the remainder to avoid rounding loss
					if i == #squads then
						share = remaining_amount
					else
						share = MulDivRound(data.total_amount, squad_need, total_need)
						share = Min(share, remaining_amount)
					end

					if share > 0 then
						-- Create new item stack for the share
						local new_item = PlaceInventoryItem(class_id)
						if new_item then
							if IsKindOf(new_item, InventoryStackClass) then
								new_item.Amount = share
							end
							new_items_per_squad[squad_id] = new_items_per_squad[squad_id] or {}
							table.insert(new_items_per_squad[squad_id], new_item)
							remaining_amount = remaining_amount - share
						else
							success = false
							break
						end
					end
				end
			else
				-- OPTION B: No squad uses this caliber, distribute equally by squad member count
				local total_units = 0
				for _, squad in ipairs(squads) do
					total_units = total_units + #(squad.units or {})
				end

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
						-- Fallback for squads with no units
						share = (i == #squads) and remaining_amount or (data.total_amount / #squads)
					end

					if share > 0 then
						local new_item = PlaceInventoryItem(class_id)
						if new_item then
							if IsKindOf(new_item, InventoryStackClass) then
								new_item.Amount = share
							end
							new_items_per_squad[squad_id] = new_items_per_squad[squad_id] or {}
							table.insert(new_items_per_squad[squad_id], new_item)
							remaining_amount = remaining_amount - share
						else
							success = false
							break
						end
					end
				end
			end
			if not success then break end
		end
		if not success then break end
	end

	-- 4. INTEGRITY CHECK: Verification checksum before finalizing the transaction
	if success then
		local checksum_before = {} -- class -> total_amount
		for caliber, classes in pairs(total_ammo) do
			for class_id, data in pairs(classes) do
				checksum_before[class_id] = (checksum_before[class_id] or 0) + data.total_amount
			end
		end

		local checksum_after = {} -- class -> total_amount
		for squad_id, items in pairs(new_items_per_squad) do
			for _, item in ipairs(items) do
				local amt = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
				checksum_after[item.class] = (checksum_after[item.class] or 0) + amt
			end
		end

		-- Confirm quantities are identical across all classes
		for class_id, before_total in pairs(checksum_before) do
			if before_total ~= (checksum_after[class_id] or 0) then
				success = false
				print(string.format("[SBDR] [Error] AllocateAmmoInSector: Verification failed for %s (before: %d, after: %d)", class_id, before_total, checksum_after[class_id] or 0))
				break
			end
		end
	end

	-- 5. FINAL COMMITMENT: Apply changes only if verified
	if success then
		-- Add the new redistributed items to the persistent squad bag data
		for squad_id, items in pairs(new_items_per_squad) do
			local squad = gv_Squads[squad_id]
			if squad then
				squad.squad_bag = squad.squad_bag or {}
				for _, itm in ipairs(items) do
					table.insert(squad.squad_bag, itm)
				end
			end
		end

		-- Clean up the original item objects
		for _, item in ipairs(items_to_destroy) do
			DoneObject(item)
		end
	else
		-- ROLLBACK: On error or verification failure, restore original items to the first squad
		local first_squad = squads[1]
		if first_squad then
			first_squad.squad_bag = first_squad.squad_bag or {}
			for _, item in ipairs(items_to_destroy) do
				table.insert(first_squad.squad_bag, item)
			end
		end

		-- Destroy any transient item objects created during the failed distribution
		for _, items in pairs(new_items_per_squad) do
			for _, itm in ipairs(items) do
				DoneObject(itm)
			end
		end
	end

	-- Re-sort and refresh all bags affected in the sector
	for _, squad in ipairs(squads) do
		_SortItemsInBag(squad.UniqueId)
	end
end

--- Allocates craftables back to squads based on mercenary skills in the sector.
--- @param sector_id string Optional sector ID to use.
--- @param squads table Optional pre-filtered list of squads.
function SquadBagDoneRight:AllocateCraftablesInSector(sector_id, squads)
	sector_id = sector_id or gv_CurrentSectorId
	if not sector_id then return end

	-- Ensure there are at least two squads to balance between
	squads = squads or GetSquadsInSector(sector_id)
	if #squads <= 1 then
		return
	end

	-- Define logical item groups for skill-based distribution
	local explosives_items = { "C4", "PETN", "TNT", "Combination_Detonator_Proximity", "Combination_Detonator_Remote", "Combination_Detonator_Time", "BlackPowder" }
	local mechanical_items = { "FineSteelPipe", "OpticalLens", "Microchip", "Combination_BalancingWeight", "Combination_Sharpener" }
	local armor_upgrades = { "Combination_CeramicPlates", "Combination_WeavePadding", "Combination_Kompositum58" }
	local parts_items = { "Parts" }

	-- Helper function to redistribute a specific group of items based on a mercenary skill
	local function distribute_group(item_list, skill_name, sum_skills)
		local total_items = {} -- Map: { [class] = total_amount }
		local items_to_destroy = {} -- List of original objects to be removed later

		-- 1. COLLECTION: Sweep all squads for items in the current group
		for _, squad in ipairs(squads) do
			local bag = squad.squad_bag or {}
			for i = #bag, 1, -1 do
				local item = bag[i]
				if item and table.find(item_list, item.class) then
					local amt = (IsKindOf(item, InventoryStackClass) and item.Amount or 1)
					total_items[item.class] = (total_items[item.class] or 0) + amt
					table.insert(items_to_destroy, item)
					table.remove(bag, i) -- Remove from squad bag to keep persistent state clean for simulation
				end
			end
		end

		-- Exit if no items from this group were found in the sector
		if next(total_items) == nil then
			return
		end

		-- 2. ASSESSMENT: Determine the "effective skill" for each squad for distribution weighting
		local squad_skills = {}
		local total_skill = 0
		for _, squad in ipairs(squads) do
			local squad_effective_skill = 0
			if sum_skills then
				-- Multi-skill weighting: Sum the highest level of each relevant skill found in the squad
				for _, s in ipairs(skill_name) do
					local max_s = 0
					for _, unit_id in ipairs(squad.units or {}) do
						local unit = gv_UnitData[unit_id]
						local val = unit and unit[s] or 0
						-- Ignore skills below the competency threshold (60)
						if val >= 60 then
							max_s = Max(max_s, val)
						end
					end
					squad_effective_skill = squad_effective_skill + max_s
				end
			else
				-- Single-skill weighting: Take the highest relevant skill value found across all squad members
				for _, unit_id in ipairs(squad.units or {}) do
					local unit = gv_UnitData[unit_id]
					if unit then
						for _, s in ipairs(skill_name) do
							local val = unit[s] or 0
							if val >= 60 then
								squad_effective_skill = Max(squad_effective_skill, val)
							end
						end
					end
				end
			end

			squad_skills[squad.UniqueId] = squad_effective_skill
			total_skill = total_skill + squad_effective_skill
		end

		-- 3. DISTRIBUTION: Create and assign new items based on weighted skill shares
		local new_items = {} -- Map: { [squad_id] = { new_item1, ... } }
		local success = true

		for class_id, total_amount in pairs(total_items) do
			local remaining = total_amount
			for i, squad in ipairs(squads) do
				local share = 0
				if total_skill > 0 then
					-- CASE A: At least one squad has a qualified specialist
					if i == #squads then
						share = remaining
					else
						share = MulDivRound(total_amount, squad_skills[squad.UniqueId], total_skill)
						share = Min(share, remaining)
					end
				else
					-- CASE B: No specialist found, distribute equally by mercenary count
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
					-- Create a fresh object for the share
					local new_item = PlaceInventoryItem(class_id)
					if new_item then
						if IsKindOf(new_item, InventoryStackClass) then
							new_item.Amount = share
						end
						new_items[squad.UniqueId] = new_items[squad.UniqueId] or {}
						table.insert(new_items[squad.UniqueId], new_item)
						remaining = remaining - share
					else
						success = false
						break
					end
				end
			end
			if not success then break end
		end

		-- 4. INTEGRITY CHECK: Verification checksum for the item group
		if success then
			local checksum_before = 0
			for _, count in pairs(total_items) do
				checksum_before = checksum_before + count
			end

			local checksum_after = 0
			for _, items in pairs(new_items) do
				for _, itm in ipairs(items) do
					checksum_after = checksum_after + ((IsKindOf(itm, InventoryStackClass) and itm.Amount) or 1)
				end
			end

			if checksum_before ~= checksum_after then
				success = false
				print(string.format("[SBDR] [Error] AllocateCraftablesInSector: Verification failed (before: %d, after: %d)", checksum_before, checksum_after))
			end
		end

		-- 5. FINAL COMMITMENT: Apply changes only if verified
		if success then
			-- Assign the new redistributed items to squad bags
			for squad_id, items in pairs(new_items) do
				local squad = gv_Squads[squad_id]
				if squad then
					squad.squad_bag = squad.squad_bag or {}
					for _, itm in ipairs(items) do
						table.insert(squad.squad_bag, itm)
					end
				end
			end

			-- Safely destroy the original objects
			for _, item in ipairs(items_to_destroy) do
				DoneObject(item)
			end
		else
			-- ROLLBACK: Restore original items to the first squad if distribution failed
			local first_squad = squads[1]
			if first_squad then
				first_squad.squad_bag = first_squad.squad_bag or {}
				for _, item in ipairs(items_to_destroy) do
					table.insert(first_squad.squad_bag, item)
				end
			end

			-- Destroy any transient item objects created during the failed pass
			for _, items in pairs(new_items) do
				for _, itm in ipairs(items) do
					DoneObject(itm)
				end
			end
		end
	end

	-- Execute distribution for each logical craftable group
	distribute_group(explosives_items, { "Explosives" })
	distribute_group(mechanical_items, { "Mechanical" })
	distribute_group(armor_upgrades, { "Mechanical" })
	distribute_group(parts_items, { "Mechanical", "Explosives" }, true)

	-- Re-sort and refresh all bags in the sector
	for _, squad in ipairs(squads) do
		_SortItemsInBag(squad.UniqueId)
	end
end

--- Redistributes Meds across squads in the sector based on which squads have medical kits.
--- @param sector_id string Optional sector ID to use.
--- @param squads table Optional pre-filtered list of squads.
function SquadBagDoneRight:AllocateMedsInSector(sector_id, squads)
	sector_id = sector_id or gv_CurrentSectorId
	if not sector_id then return end

	-- Ensure there are at least two squads to balance between
	squads = squads or GetSquadsInSector(sector_id)
	if #squads <= 1 then
		return
	end

	local total_meds = 0
	local items_to_destroy = {}

	-- 1. COLLECTION PHASE: Sweep all squad bags for "Meds" (the resource)
	local collected_meds = {}
	for _, squad in ipairs(squads) do
		local bag = squad.squad_bag or {}
		for i = #bag, 1, -1 do
			local item = bag[i]
			if item.class == "Meds" then
				local amt = (item.Amount or 1)
				total_meds = total_meds + amt
				table.insert(collected_meds, item)
				table.remove(bag, i) -- Simulation safety: remove from persistent bag before redistribute
			end
		end
	end

	-- Only proceed if there are Meds to allocate
	if total_meds > 0 then
		-- 2. NEEDS ASSESSMENT: Check which squads have a designated medic or medical kits
		local squad_needs = {}
		local total_need = 0
		for _, squad in ipairs(squads) do
			local has_kit = false
			for _, unit_id in ipairs(squad.units or {}) do
				local unit = gv_UnitData[unit_id]
				-- A squad "needs" meds if they have a kit capable of using them
				if unit and (unit:GetItem("Medkit") or unit:GetItem("FirstAidKit") or unit:GetItem("Reanimationsset")) then
					has_kit = true
					break
				end
			end
			local need = has_kit and 1 or 0
			squad_needs[squad.UniqueId] = need
			total_need = total_need + need
		end

		-- 3. DISTRIBUTION PHASE: Allocate shares into new Meds objects
		local remaining = total_meds
		local new_items = {}
		local success = true

		for i, squad in ipairs(squads) do
			local share = 0
			if total_need > 0 then
				-- CASE A: At least one squad has medical equipment
				if i == #squads then
					share = remaining
				else
					share = MulDivRound(total_meds, squad_needs[squad.UniqueId], total_need)
					share = Min(share, remaining)
				end
			else
				-- CASE B: No kits found, distribute equally by mercenary count
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
				-- Create new Meds object for the share
				local new_item = PlaceInventoryItem("Meds")
				if new_item then
					new_item.Amount = share
					new_items[squad.UniqueId] = new_item
					remaining = remaining - share
				else
					success = false
					break
				end
			end
		end

		-- 4. INTEGRITY CHECK: Verification checksum for total meds count
		if success then
			local checksum_after = 0
			for _, itm in pairs(new_items) do
				checksum_after = checksum_after + (itm.Amount or 1)
			end

			if total_meds ~= checksum_after then
				success = false
				print(string.format("[SBDR] [Error] AllocateMedsInSector: Verification failed (before: %d, after: %d)", total_meds, checksum_after))
			end
		end

		-- 5. FINAL COMMITMENT: Apply changes only if verified
		if success then
			-- Assign new Meds objects to squad bags
			for squad_id, new_item in pairs(new_items) do
				local squad = gv_Squads[squad_id]
				if squad then
					squad.squad_bag = squad.squad_bag or {}
					table.insert(squad.squad_bag, new_item)
				end
			end

			-- Destroy original Meds objects
			for _, item in ipairs(collected_meds) do
				DoneObject(item)
			end
		else
			-- ROLLBACK: Restore original items if distribution failed
			local first_squad = squads[1]
			if first_squad then
				first_squad.squad_bag = first_squad.squad_bag or {}
				for _, item in ipairs(collected_meds) do
					table.insert(first_squad.squad_bag, item)
				end
			end

			-- Destroy transient objects
			for _, item in pairs(new_items) do
				DoneObject(item)
			end
		end

		-- Re-sort and refresh bags in the sector
		for _, squad in ipairs(squads) do
			_SortItemsInBag(squad.UniqueId)
		end
	end
end

--- Comprehensive entry point to allocate all supply types (ammo, craftables, meds) across a sector.
--- @param sector_id string Optional sector ID to use.
function SquadBagDoneRight:AllocateAllInSector(sector_id)
	sector_id = sector_id or gv_CurrentSectorId
	if not sector_id then return end

	-- Find player squads
	local squads = GetSquadsInSector(sector_id)
	if #squads <= 1 then
		return
	end

	-- Suppress UI refreshes during individual allocation steps to prevent refresh spam
	self.suppress_ui_refresh = true

	-- Sequence the specific supply allocations
	self:AllocateAmmoInSector(sector_id, squads)
	self:AllocateCraftablesInSector(sector_id, squads)
	self:AllocateMedsInSector(sector_id, squads)

	-- Restore UI refreshes
	self.suppress_ui_refresh = false

	-- Final batch UI refresh: re-sort bags and force UI respawn for all sector squads
	for _, squad in ipairs(squads) do
		_SortItemsInBag(squad.UniqueId)
	end
end
