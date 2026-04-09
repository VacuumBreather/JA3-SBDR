--- @module SquadBagDoneRight
--- @desc This mod handles moving specific crafting, skill, and valuable items to the squad bag automatically.

-- Use rawget to bypass the engine's strict mode check for undefined globals
if rawget(_G, "SquadBagDoneRight") == nil then
	SquadBagDoneRight = {}
end
SquadBagDoneRight.SquadBagItemClass = "SquadBagItem"
SquadBagDoneRight.InventoryStackClass = "InventoryStack"

SquadBagDoneRight.lists = {
	craftingItems = {
		"BlackPowder", "C4", "Combination_BalancingWeight", "Combination_CeramicPlates",
		"Combination_Detonator_Proximity", "Combination_Detonator_Remote", "Combination_Detonator_Time",
		"Combination_Kompositum58", "Combination_Sharpener", "Combination_WeavePadding",
		"FineSteelPipe", "Microchip", "OpticalLens", "PETN", "TNT"
	},
	skillMagazines = {
		"SkillMag_Agility", "SkillMag_Dexterity", "SkillMag_Explosives", "SkillMag_Health",
		"SkillMag_Leadership", "SkillMag_Marksmanship", "SkillMag_Mechanical", "SkillMag_Medical",
		"SkillMag_Strength", "SkillMag_Wisdom"
	},
	valuables = {
		"BigDiamond", "ChippedSapphire", "GoldBar", "MoneyBag", "TinyDiamonds",
		"TreasureFigurine", "TreasureGoldenDog", "TreasureIdol", "TreasureMask", "TreasureTablet"
	}
}

local SquadBagItemClass = SquadBagDoneRight.SquadBagItemClass
local InventoryStackClass = SquadBagDoneRight.InventoryStackClass

---------------------------------------------------------------------------------------------------
--- HELPER FUNCTIONS
---------------------------------------------------------------------------------------------------

--- Merges two arrays (t1 and t2) into a new table.
--- @param t1 table First table to merge.
--- @param t2 table Second table to merge.
--- @return table A new table containing elements from t1 followed by elements from t2.
-- Helper functions for common mod operations
local function ConcatTables(t1, t2)
	-- Creates a new table containing elements from both input tables
	local result = {}

	-- Add elements from the first table
	for _, v in ipairs(t1) do
		result[#result + 1] = v
	end

	-- Add elements from the second table
	for _, v in ipairs(t2) do
		result[#result + 1] = v
	end

	return result
end

--- Gets the squad bag items for a specific squad.
--- @param squad_id string The unique ID of the squad.
--- @return table|nil The squad bag table if it exists.
local function GetSquadBag(squad_id)
	-- Retrieve squad from the global squad table and return its bag
	local squad = gv_Squads and gv_Squads[squad_id]
	return squad and squad.squad_bag
end

--- Returns a list of player-controlled squads in the specified sector.
--- @param sector_id string The ID of the sector to check.
--- @return table List of player squads in the sector.
local function GetSquadsInSector(sector_id)
	local squads = {}

	-- Scan all squads and filter by sector and side
	for _, squad in pairs(gv_Squads or {}) do
		if squad.CurrentSector == sector_id and squad.Side == "player1" then
			table.insert(squads, squad)
		end
	end

	return squads
end

--- Determines the sort priority of an inventory item for organizing the squad bag.
--- @param item table The inventory item to check.
--- @return number The sort priority value (lower is higher priority).
local function GetSortPriority(item)
	local class = item.class
	local options = CurrentModOptions or {}

	-- Priority mapping for organized inventory using mod options
	if class == "Meds" then return tonumber(options.sbdr_priority_meds) or 1 end
	if class == "Parts" then return tonumber(options.sbdr_priority_parts) or 2 end
	if class == "BlackPowder" then return tonumber(options.sbdr_priority_blackpowder) or 3 end
	if IsKindOf(item, "Ammo") then return tonumber(options.sbdr_priority_ammo) or 4 end

	-- Flare ammo
	if class == "FlareAmmo" then return tonumber(options.sbdr_priority_flareammo) or 5 end

	-- Mortar shells
	if string.starts_with(class, "MortarShell_") then return tonumber(options.sbdr_priority_mortarshells) or 6 end

	-- Warheads
	if class == "Warhead_Frag" then return tonumber(options.sbdr_priority_warheads) or 7 end

	-- 40mm shells
	if string.starts_with(class, "_40mm") then return tonumber(options.sbdr_priority_40mmshells) or 8 end

	-- Explosives
	if class == "C4" or class == "PETN" or class == "TNT" then return tonumber(options.sbdr_priority_explosives) or 9 end

	-- Detonators
	if class == "Combination_Detonator_Proximity" or
	   class == "Combination_Detonator_Remote" or
	   class == "Combination_Detonator_Time" then
		return tonumber(options.sbdr_priority_detonators) or 10
	end

	-- Armor upgrades
	if class == "Combination_CeramicPlates" or
	   class == "Combination_WeavePadding" or
	   class == "Combination_Kompositum58" then
		return tonumber(options.sbdr_priority_armorupgrades) or 11
	end

	-- Weapon parts / Utility
	if class == "Combination_BalancingWeight" or class == "Combination_Sharpener" then
		return tonumber(options.sbdr_priority_tools) or 12
	end

	-- Weapon parts / Utility
	if class == "FineSteelPipe" or class == "OpticalLens" or class == "Microchip" then
		return tonumber(options.sbdr_priority_misc_craftables) or 13
	end

	-- Skill Magazines
	if string.starts_with(class, "SkillMag_") then return tonumber(options.sbdr_priority_skillmags) or 14 end

	-- Valuables: prioritize stackable valuables over non-stackable ones
	if IsKindOf(item, "Valuables") or class == "MoneyBag" then
		if IsKindOf(item, InventoryStackClass) then
			return tonumber(options.sbdr_priority_valuables_stackable) or 15
		else
			return tonumber(options.sbdr_priority_valuables_single) or 16
		end
	end

	return 100 -- Default for unknown items
end

---------------------------------------------------------------------------------------------------
--- MOD-SPECIFIC FUNCTIONS
---------------------------------------------------------------------------------------------------

--- Updates the class inheritance of a specified class to include or remove SquadBagItemClass.
--- @param className string The name of the class to patch.
--- @param addClass boolean Whether to add (true) or remove (false) the SquadBagItemClass from inheritance.
function SquadBagDoneRight:PatchClassInheritance(className, addClass)
	-- Access the engine's class object
	local classObj = g_Classes[className]

	if not classObj then
		return
	end

	-- 1. CLONE __parents to avoid leaking changes to other sibling classes in the hierarchy
	classObj.__parents = table.copy(classObj.__parents or {})

	-- Add or remove the SquadBagItem marker class from parents list
	if addClass then
		table.insert_unique(classObj.__parents, SquadBagItemClass)
	else
		table.remove_entry(classObj.__parents, SquadBagItemClass)
	end

	-- 2. CLONE __ancestors to ensure IsKindOf checks correctly detect the new parent
	classObj.__ancestors = table.copy(classObj.__ancestors or {})

	-- Update the ancestor lookup table for efficient IsKindOf evaluation
	if addClass then
		classObj.__ancestors[SquadBagItemClass] = true
	else
		classObj.__ancestors[SquadBagItemClass] = nil
	end
end

--- Moves all eligible items from every hired merc's inventory to their respective squad bags.
function SquadBagDoneRight:MoveAllMercsInventoryToSquadBag()
	-- 1. Ensure we are in an active game session before proceeding
	if not Game or not gv_Squads then
		return
	end

	-- Suppress UI refreshes during bulk move for performance
	self.suppress_ui_refresh = true

	-- 2. Iterate through all squads to identify candidates for inventory moving
	for squad_id, squad in pairs(gv_Squads) do
		-- Only process player-controlled squads that have units and a valid bag
		if squad.Side == "player1" and squad.units and squad.squad_bag then
			local moved_items = {} -- Log of items to move: [{ unit, slot_name, item, moved_amount }]
			local bag_copy = table.copy(squad.squad_bag) -- Transactional work: operate on a copy first

			-- --- Verification Step: Record total quantity per class BEFORE the move ---
			local amounts_before = {} -- Map: class -> total_amount
			local function add_to_before(class, amount)
				amounts_before[class] = (amounts_before[class] or 0) + amount
			end

			-- Count current amounts already in the squad bag
			for _, item in ipairs(squad.squad_bag) do
				add_to_before(item.class, IsKindOf(item, InventoryStackClass) and item.Amount or 1)
			end

			-- Iterate through all units (mercenaries) in the current squad
			for _, unit_id in ipairs(squad.units) do
				local unit = gv_UnitData and gv_UnitData[unit_id]

				if unit then
					-- Scan unit inventory for items flagged as squad bag candidates
					unit:ForEachItem(SquadBagItemClass, function(item, slot_name)
						local original_amount = IsKindOf(item, InventoryStackClass) and item.Amount or 1
						add_to_before(item.class, original_amount)

						local remaining_amount = original_amount
						local moved_amount = 0

						-- PHASE 1: Try to merge items into existing stacks in the bag copy
						if IsKindOf(item, InventoryStackClass) then
							for _, bag_item in ipairs(bag_copy) do
								-- Match class and check for stack capacity
								if bag_item.class == item.class and bag_item.Amount < bag_item.MaxStacks then
									local to_add = Min(bag_item.MaxStacks - bag_item.Amount, remaining_amount)

									if to_add > 0 then
										bag_item.Amount = bag_item.Amount + to_add
										remaining_amount = remaining_amount - to_add
										moved_amount = moved_amount + to_add
									end

									-- Stop if the entire stack has been merged
									if remaining_amount <= 0 then
										break
									end
								end
							end
						end

						-- PHASE 2: Add any remaining amount as new item entries in the bag copy
						if remaining_amount > 0 then
							local new_item

							if IsKindOf(item, InventoryStackClass) then
								-- Recreate a new stack object for the bag
								new_item = PlaceInventoryItem(item.class)
								if new_item then
									new_item.Amount = remaining_amount
								end
							else
								-- Recreate a new non-stackable object
								new_item = PlaceInventoryItem(item.class)
							end

							if new_item then
								table.insert(bag_copy, new_item)
								moved_amount = moved_amount + remaining_amount
								remaining_amount = 0
							else
								-- Error: cannot recreate the item, aborting this item's move to prevent loss
								print(string.format("[SBDR] [Error] Failed to recreate item %s for squad bag", tostring(item.class)))
							end
						end

						-- If simulation succeeded for any amount, log it for final application
						if moved_amount > 0 then
							table.insert(moved_items, { unit = unit, slot_name = slot_name, item = item, moved_amount = moved_amount })
						end
					end)
				end
			end

			-- --- Verification Step: Check total quantity per class AFTER the simulated move ---
			local amounts_after = {} -- Map: class -> total_amount
			local function add_to_after(class, amount)
				amounts_after[class] = (amounts_after[class] or 0) + amount
			end

			-- Count amounts in the updated bag copy
			for _, item in ipairs(bag_copy) do
				add_to_after(item.class, IsKindOf(item, InventoryStackClass) and item.Amount or 1)
			end

			-- Count amounts remaining in mercenaries (original - moved_amount)
			for _, unit_id in ipairs(squad.units) do
				local unit = gv_UnitData and gv_UnitData[unit_id]

				if unit then
					unit:ForEachItem(SquadBagItemClass, function(item, slot_name)
						local current_total = IsKindOf(item, InventoryStackClass) and item.Amount or 1
						local was_moved = 0

						-- Determine how much of this specific item was slated to be moved
						for _, move in ipairs(moved_items) do
							if move.item == item then
								was_moved = was_moved + move.moved_amount
							end
						end

						-- The remainder must still exist in the unit for the checksum to pass
						add_to_after(item.class, current_total - was_moved)
					end)
				end
			end

			-- --- Integrity Check: Compare Before and After checksums ---
			local verified = true

			for class, before_total in pairs(amounts_before) do
				if before_total ~= (amounts_after[class] or 0) then
					verified = false
					print(string.format("[SBDR] [Error] Verification failed for item %s: before=%d, after=%d", class, before_total, amounts_after[class] or 0))
					break
				end
			end

			-- --- Final Transactional Commitment ---
			if verified then
				-- 3. Replace the actual squad bag with our validated copy
				squad.squad_bag = bag_copy

				-- 4. Final Cleanup: Only remove/destroy original objects once the bag is safely updated
				for _, move in ipairs(moved_items) do
					if IsKindOf(move.item, InventoryStackClass) then
						-- Deduct the moved amount from the source item
						move.item.Amount = move.item.Amount - move.moved_amount

						-- If the stack is exhausted, remove and destroy the object
						if move.item.Amount <= 0 then
							move.unit:RemoveItem(move.slot_name, move.item)
							DoneObject(move.item)
						end
					else
						-- Non-stackables are always fully moved and destroyed
						move.unit:RemoveItem(move.slot_name, move.item)
						DoneObject(move.item)
					end

					-- Send message for UI/logic hooks
					Msg("SquadBagAddItem", move.item, move.moved_amount)
				end
			else
				-- Rollback: Clean up newly created objects from the failed simulation
				for _, item in ipairs(bag_copy) do
					local is_original = false
					for _, orig in ipairs(squad.squad_bag) do
						if orig == item then is_original = true; break end
					end
					if not is_original then
						DoneObject(item)
					end
				end
				print("[SBDR] [Error] Verification failed in MoveAllMercsInventoryToSquadBag. Transaction aborted to prevent item loss.")
			end
		end

		-- Sort the bag after modification
		_SortItemsInBag(squad_id)
	end

	-- Re-enable UI refreshes
	self.suppress_ui_refresh = false

	-- Final UI refresh for the currently viewed squad bag
	if gv_SquadBag and gv_SquadBag.squad_id and gv_Squads[gv_SquadBag.squad_id] then
		_SortItemsInBag(gv_SquadBag.squad_id)
	end
end

--- Removes items from squad bags that are no longer eligible (e.g., due to option changes)
--- and moves them back to mercenary inventories or the sector stash.
function SquadBagDoneRight:EvictInvalidItems()
	if not Game or not gv_Squads then
		return
	end

	-- Suppress UI refreshes during bulk eviction
	self.suppress_ui_refresh = true

	for squad_id, squad in pairs(gv_Squads) do
		local bag = squad.squad_bag

		if bag and #bag > 0 then
			-- 1. Simulation: Identify disqualified items using a copy of the bag
			local bag_copy = table.copy(bag)
			local items_to_evict = {}

			for i = #bag_copy, 1, -1 do
				local item = bag_copy[i]
				-- Check if item is still allowed in squad bag based on current options
				if item and not IsKindOf(item, SquadBagItemClass) then
					table.remove(bag_copy, i)
					table.insert(items_to_evict, item)
				end
			end

			if #items_to_evict > 0 then
				-- 2. Checksum Before: Count total quantities before eviction
				local checksum_before = {}
				for _, item in ipairs(bag) do
					local amt = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
					checksum_before[item.class] = (checksum_before[item.class] or 0) + amt
				end

				-- 3. Checksum After (Simulation): Sum bag copy and eviction list
				local checksum_after = {}
				for _, item in ipairs(bag_copy) do
					local amt = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
					checksum_after[item.class] = (checksum_after[item.class] or 0) + amt
				end
				for _, item in ipairs(items_to_evict) do
					local amt = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
					checksum_after[item.class] = (checksum_after[item.class] or 0) + amt
				end

				-- Verification check
				local verified = true
				for class, count_before in pairs(checksum_before) do
					if count_before ~= (checksum_after[class] or 0) then
						verified = false
						print(string.format("[SBDR] [Error] EvictInvalidItems: Verification failed for %s", class))
						break
					end
				end

				-- --- Final Application ---
				if verified then
					-- 4. Replace persistent bag with simulation results
					squad.squad_bag = bag_copy

					-- 5. Physically move evicted item objects to valid locations
					for _, item in ipairs(items_to_evict) do
						local moved = false

						-- Priority 1: Move back to mercenaries in the same squad
						if squad.units then
							for _, merc_id in ipairs(squad.units) do
								local unit = gv_UnitData and gv_UnitData[merc_id]
								if unit then
									local canAdd = unit:CanAddItem("Inventory", item)
									if canAdd then
										local added = unit:AddItem("Inventory", item)
										if added then
											moved = true
											break
										end
									end
								end
							end
						end

						-- Priority 2: Move to Sector Stash (unlimited capacity)
						if not moved then
							local sector_id = squad.CurrentSector
							if sector_id then
								local sector_inv = GetSectorInventory(sector_id)
								if sector_inv then
									-- Sector inventory always has space
									AddItemsToInventory(sector_inv, { item })
									moved = true
								end
							end
						end

						-- Safety Fallback: if all else fails, keep it in the bag
						if not moved then
							table.insert(squad.squad_bag, item)
							print(string.format("[SBDR] [Warning] Unable to evict item %s - returning to squad bag.", tostring(item.class)))
						end
					end
				else
					print("[SBDR] [Error] EvictInvalidItems: Verification failed. Eviction aborted for squad " .. tostring(squad_id))
				end
			end
		end

		-- Clean up and sort the bag after eviction
		_SortItemsInBag(squad_id)
	end

	self.suppress_ui_refresh = false

	-- Refresh current UI bag if it was modified
	if gv_SquadBag then
		local current_squad = gv_SquadBag.squad_id
		if current_squad and gv_Squads[current_squad] then
			_SortItemsInBag(current_squad)
		end
	end
end

--- Re-evaluates mod options, patches class markers, and updates all inventories accordingly.
function SquadBagDoneRight:UpdateProperties()
	local options = CurrentModOptions

	if not options then
		print("[SBDR] [Warning] CurrentModOptions not found. Skipping update.")
		return
	end

	-- Apply class patching based on mod toggles
	local craft_opt = options.sbdr_crafting_items
	if craft_opt ~= nil then
		for _, item in ipairs(self.lists.craftingItems) do
			self:PatchClassInheritance(item, craft_opt)
		end
	end

	local skill_opt = options.sbdr_skill_mags
	if skill_opt ~= nil then
		for _, item in ipairs(self.lists.skillMagazines) do
			self:PatchClassInheritance(item, skill_opt)
		end
	end

	local valuables_opt = options.sbdr_valuables
	if valuables_opt ~= nil then
		for _, item in ipairs(self.lists.valuables) do
			self:PatchClassInheritance(item, valuables_opt)
		end
	end

	-- Remove items that no longer match the active options
	self:EvictInvalidItems()

	-- If auto-move is enabled, sweep all inventories to the bag
	if options.sbdr_auto_move_to_bag then
		self:MoveAllMercsInventoryToSquadBag()
	end
end

---------------------------------------------------------------------------------------------------
--- ENGINE OVERRIDING / PATCHING FUNCTIONS
---------------------------------------------------------------------------------------------------

--- Internal function to sort and stack items in a specific squad bag.
--- @param squad_id string The ID of the squad whose bag is to be sorted.
function _SortItemsInBag(squad_id)
	-- Safety check: ensure squad and bag exist
	if not gv_Squads or not gv_Squads[squad_id] then
		return
	end

	local bag = gv_Squads[squad_id].squad_bag
	if not bag or #bag == 0 then
		return
	end

	-- 1. Checksum Before: Record total quantity per class before sorting/merging
	local checksum_before = {}
	local items_to_destroy = {} -- Track original items for safe destruction after verification
	for _, item in ipairs(bag) do
		if item then
			local amount = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
			checksum_before[item.class] = (checksum_before[item.class] or 0) + amount
			table.insert(items_to_destroy, item)
		end
	end

	-- 2. Transactional Stacking: Re-organize items into a new list of objects
	local stacks = {}
	local non_stackables = {}

	for _, original_item in ipairs(bag) do
		if original_item then
			local amount = (IsKindOf(original_item, InventoryStackClass) and original_item.Amount) or 1
			local class = original_item.class

			if not IsKindOf(original_item, InventoryStackClass) then
				-- Handle non-stackable items: recreate a fresh object
				local new_item = PlaceInventoryItem(class)
				if new_item then
					non_stackables[#non_stackables + 1] = new_item
				else
					print(string.format("[SBDR] [Error] _SortItemsInBag: Failed to recreate non-stackable %s", class))
				end
			else
				-- Handle stackable items: merge into existing simulation stacks or create new ones
				local remaining = amount
				-- Attempt to fill existing partially-filled stacks in the simulation list
				for _, stack in ipairs(stacks) do
					if stack.class == class and stack.Amount < stack.MaxStacks then
						local to_add = Min(stack.MaxStacks - stack.Amount, remaining)
						stack.Amount = stack.Amount + to_add
						remaining = remaining - to_add
						if remaining <= 0 then break end
					end
				end

				-- Create new stacks for any remaining quantity
				while remaining > 0 do
					local new_stack = PlaceInventoryItem(class)
					if new_stack then
						local to_add = Min(new_stack.MaxStacks, remaining)
						new_stack.Amount = to_add
						stacks[#stacks + 1] = new_stack
						remaining = remaining - to_add
					else
						-- Fatal error in item recreation
						print(string.format("[SBDR] [Error] _SortItemsInBag: Failed to recreate stackable %s", class))
						remaining = 0
					end
				end
			end
		end
	end

	-- Combine stackable and non-stackable items into a single list
	local all_items = ConcatTables(stacks, non_stackables)

	-- 3. Checksum After: Verify total quantity matches the starting state
	local checksum_after = {}
	for _, item in ipairs(all_items) do
		local amount = (IsKindOf(item, InventoryStackClass) and item.Amount) or 1
		checksum_after[item.class] = (checksum_after[item.class] or 0) + amount
	end

	local verified = true
	for class, count_before in pairs(checksum_before) do
		if count_before ~= (checksum_after[class] or 0) then
			verified = false
			print(string.format("[SBDR] [Error] _SortItemsInBag: Verification failed for %s (before: %d, after: %d)", class, count_before, checksum_after[class] or 0))
			break
		end
	end

	-- --- Final Commitment ---
	if verified then
		-- 4. Apply Sort Priority Logic
		table.sort(all_items, function(a, b)
			local priority_a = GetSortPriority(a)
			local priority_b = GetSortPriority(b)

			-- First sort by the primary priority group
			if priority_a ~= priority_b then
				return priority_a < priority_b
			end

			-- Secondary sort logic for specific groups (Ammo, Meds, Valuables)
			if IsKindOf(a, "Ammo") then -- Ammo group
				local caliber_a = a.Caliber
				local caliber_b = b.Caliber

				if caliber_a == caliber_b then
					-- Same caliber: sort by class then by descending amount
					if a.Amount == b.Amount then
						return (a.class or "") < (b.class or "")
					else
						return (a.Amount or 0) > (b.Amount or 0)
					end
				else
					return (caliber_a or "") < (caliber_b or "")
				end
			elseif a.class == "Meds" or a.class == "Parts" then -- Meds, Parts
				-- Sort by descending amount
				return (a.Amount or 0) > (b.Amount or 0)
			elseif string.starts_with(a.class, "SkillMag_") or IsKindOf(a, "Valuables") or a.class == "MoneyBag" then -- SkillMags, Valuables
				-- Sort by class name, then descending amount
				if a.class == b.class then
					local amount_a = (IsKindOf(a, InventoryStackClass) and a.Amount) or 1
					local amount_b = (IsKindOf(b, InventoryStackClass) and b.Amount) or 1
					return amount_a > amount_b
				end
				return (a.class or "") < (b.class or "")
			else
				-- Generic fallback: sort by class name, then descending amount
				if a.class == b.class then
					local amount_a = (IsKindOf(a, InventoryStackClass) and a.Amount) or 1
					local amount_b = (IsKindOf(b, InventoryStackClass) and b.Amount) or 1
					return amount_a > amount_b
				end
				return (a.class or "") < (b.class or "")
			end
		end)

		-- Update the persistent bag data with the verified and sorted list
		gv_Squads[squad_id].squad_bag = all_items

		-- 5. Cleanup: Safely destroy the original objects now that replacements are active
		for _, item in ipairs(items_to_destroy) do
			DoneObject(item)
		end
	else
		-- Rollback: Verification failed, destroy the simulation objects to avoid duplication
		for _, item in ipairs(all_items) do
			DoneObject(item)
		end
		print("[SBDR] [Warning] _SortItemsInBag: Verification failed. Sorting aborted to prevent item loss.")
	end

	-- --- UI Synchronization ---
	-- Skip if we are mid-batch (to avoid flickering/performance hit)
	if SquadBagDoneRight.suppress_ui_refresh then
		return
	end

	-- Force refresh the open inventory UI if it corresponds to the modified squad
	if gv_SquadBag and gv_SquadBag.squad_id == squad_id then
		if InventoryUIResetSquadBag then InventoryUIResetSquadBag() end
		gv_SquadBag:SetSquadId(squad_id)
		if InventoryUIRespawn then InventoryUIRespawn() end
	end
end

-- Patching ItemIsFound to include SquadBag in its search logic.
-- This ensures that items needed for quests or interactions can be detected in player bags.
local sbdr_old_ItemIsFound_eval = ItemIsFound.__eval
function ItemIsFound:__eval(obj, context)
	-- First check standard locations (mercenary inventories and containers)
	local result = sbdr_old_ItemIsFound_eval(self, obj, context)
	if result then return true end

	-- Resolve sector context
	local sector_id = self.Sector == "current" and gv_CurrentSectorId or self.Sector
	if not sector_id then return false end

	-- Check player squad bags in the specified sector
	local squads = GetSquadsInSector(sector_id)
	if not squads then return false end

	local amount = self.Amount
	local cur_amount = 0

	for _, squad in ipairs(squads) do
		local bag = GetSquadBag(squad.UniqueId)

		if bag then
			-- Scan squad bag for matching item class and sum up quantities
			for _, item in ipairs(bag) do
				if item and item.class == self.ItemId then
					cur_amount = cur_amount + (IsKindOf(item, InventoryStackClass) and item.Amount or 1)
					if cur_amount >= amount then return true end
				end
			end
		end
	end

	return false
end

-- Patching ItemIsInMerc to include SquadBag in its check.
-- Similar to ItemIsFound, but specifically for "Is this item on the merc/squad" checks.
local sbdr_old_ItemIsInMerc_eval = ItemIsInMerc.__eval
function ItemIsInMerc:__eval(obj, context)
	-- First check standard mercenary inventories
	local result = sbdr_old_ItemIsInMerc_eval(self, obj, context)
	if result then return true end

	-- Identify candidate squads based on sector parameters
	local sector_id = self.Sector == "current" and gv_CurrentSectorId or self.Sector
	local squads = self.Sector == "all_sectors" and GetPlayerMercSquads() or (sector_id and GetSquadsInSector(sector_id))

	if not squads then
		return false
	end

	local amount = self.Amount
	local cur_amount = 0

	for _, squad in ipairs(squads) do
		local bag = GetSquadBag(squad.UniqueId)

		if bag then
			-- Accumulate total amount found across candidate squad bags
			for _, item in ipairs(bag) do
				if item and item.class == self.ItemId then
					cur_amount = cur_amount + (IsKindOf(item, InventoryStackClass) and item.Amount or 1)
					if cur_amount >= amount then return true end
				end
			end
		end
	end

	return false
end

--- Overrides global AddItemsToSquadBag to handle stacking correctly and ensure proper UI refresh.
--- @param squad_id string The ID of the squad whose bag items are being added to.
--- @param items table The list of items to add.
function AddItemsToSquadBag(squad_id, items)
	-- Skip if input is invalid
	if not items then return end

	-- Ensure squad exists
	if not gv_Squads or not gv_Squads[squad_id] then
		return
	end

	-- Initialize squad bag if missing
	local bag = GetSquadBag(squad_id)
	if not bag then
		bag = {}
		gv_Squads[squad_id].squad_bag = bag
	end

	-- Process items from end to start for safe removal from input table
	for i = #items, 1, -1 do
		local item = items[i]

		-- Only move items tagged as SquadBagItem candidates
		if item and IsKindOf(item, SquadBagItemClass) then
			local count = IsKindOf(item, InventoryStackClass) and item.Amount or 1

			-- Attempt to merge into existing stacks in the bag
			for _, curitm in ipairs(bag) do
				if curitm and curitm.class == item.class and IsKindOf(curitm, InventoryStackClass) and curitm.Amount < curitm.MaxStacks then
					local to_add = Min(curitm.MaxStacks - curitm.Amount, count)
					curitm.Amount = curitm.Amount + to_add
					count = count - to_add

					-- Trigger add message for UI updates
					if to_add > 0 then
						Msg("SquadBagAddItem", curitm, to_add)
					end

					-- If the item stack is exhausted, destroy the source object
					if count <= 0 then
						DoneObject(item)
						item = false
						break
					end
				end
			end

			-- If item wasn't fully merged, insert it as a new entry
			if item and count > 0 then
				table.insert(bag, item)
				Msg("SquadBagAddItem", item, count)
			end

			-- Remove from the incoming item list
			table.remove(items, i)
		end
	end

	-- Re-sort the bag after adding new items
	SortItemsInBag(squad_id)
end

--- Hook into ScrapItem to ensure squad bag sync when an item is scrapped from the squad bag UI.
local sbdr_old_ScrapItem = ScrapItem
function ScrapItem(inventory, slot_name, item, amount, squadBag, squadId)
	-- If not a squad bag operation, call original logic
	if not squadBag then
		if sbdr_old_ScrapItem then sbdr_old_ScrapItem(inventory, slot_name, item, amount, squadBag, squadId) end
		return
	end

	-- Attempt to recover the correct squad ID for persistence sync
	local squad_id = squadBag.squad_id

	-- Fallback search if ID is missing or mismatched
	if not gv_Squads or not gv_Squads[squad_id] then
		if gv_Squads then
			for id, squad in pairs(gv_Squads) do
				if squad.squad_bag and table.find(squad.squad_bag, item) then
					squadBag.squad_id = id
					break
				end
			end
		end
	end

	-- Call original scrap logic
	if sbdr_old_ScrapItem then
		sbdr_old_ScrapItem(inventory, slot_name, item, amount, squadBag, squadId)
	end
end

--- Overrides SquadBag:RemoveItem to ensure persistent squad data is kept in sync with the UI object.
--- @param slot_name string Name of the inventory slot.
--- @param item table The item being removed.
--- @param no_update boolean Whether to skip updating/sorting the bag.
function SquadBag:RemoveItem(slot_name, item, no_update)
	-- Perform standard inventory removal
	local removedItem, pos = Inventory.RemoveItem(self, slot_name, item, no_update)

	-- Resolve squad ID for the bag
	local squad_id = self.squad_id

	-- Search all squads if the bag ID is invalid
	if not gv_Squads or not gv_Squads[squad_id] then
		if gv_Squads then
			for id, squad in pairs(gv_Squads) do
				if squad.squad_bag and table.find(squad.squad_bag, item) then
					squad_id = id
					break
				end
			end
		end
	end

	-- Sync the persistent gv_Squads bag data
	local squad = gv_Squads and gv_Squads[squad_id]

	if squad then
		local cdata = squad.squad_bag or {}
		table.remove_entry(cdata, item)
		squad.squad_bag = cdata -- Commit update to persistent storage

		-- Sort the bag unless suppressed
		if not no_update then
			SortItemsInBag(squad_id)
		end
	else
		-- Log failure to sync persistent data
		print(string.format("[SBDR] [Warning] Could not find squad for item %s during RemoveItem. Sync may fail.", tostring(item and item.class)))
	end

	return removedItem, pos
end

-- Specialized handling for Item Combinations (crafting) involving squad bags.
local sbdr_old_Combine2ItemsInternal = Combine2ItemsInternal
function Combine2ItemsInternal(recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)
	local is_bag1 = type(item1_context) == "number" -- Context is a net ID if it's a squad bag
	local is_bag2 = type(item2_context) == "number"

	-- Redirect logic if BOTH items are pulled from squad bags
	if is_bag1 and is_bag2 then
		local target_unit = GetContainerFromContainerNetId(unit_operator_id)

		-- Temporarily wrap AddItemsToInventory to handle overflow to the operator's inventory
		local sbdr_old_AddItemsToInventory = AddItemsToInventory
		local added_item_name
		local was_added = false

		_G.AddItemsToInventory = function(inventoryObj, items, bLog)
			local pos, reason = sbdr_old_AddItemsToInventory(inventoryObj, items, bLog)

			-- If addition to squad bag failed, redirect to the crafting operator unit
			if not pos and IsKindOf(inventoryObj, "SquadBag") and target_unit then
				local combined_item = items[1]
				added_item_name = combined_item and combined_item.DisplayName

				pos, reason = sbdr_old_AddItemsToInventory(target_unit, items, IsKindOf("UnitProperties", target_unit))

				if pos then
					was_added = true
				end
			end

			return pos, reason
		end

		-- Execute original combination logic with our wrapper active
		local status, err = procall(sbdr_old_Combine2ItemsInternal, recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)

		-- Cleanup wrapper
		_G.AddItemsToInventory = sbdr_old_AddItemsToInventory

		-- Log acquisition in the combat log if item was redirected
		if status and was_added then
			CombatLog("important", T(435437836774, "Items acquired:"))
			local res = T{581384045758, " <amount> x <em><itemNameT></em> (<mercName>)", amount = 1, itemNameT = added_item_name, mercName = target_unit:GetDisplayName()}
			CombatLog("importanthelper", res)
		end

		if not status then error(err) end

		return
	end

	-- Use default engine behavior for other combination types
	return sbdr_old_Combine2ItemsInternal(recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)
end

---------------------------------------------------------------------------------------------------
--- EVENT HANDLERS / INITIALIZATION
---------------------------------------------------------------------------------------------------

-- Triggered when a unit joins a new player squad.
-- Re-allocates inventory across all squads in the sector to ensure balanced supplies.
function OnMsg.UnitJoinedPlayerSquad(squad_id, unit_id)
	local squad = gv_Squads[squad_id]
	if squad and squad.CurrentSector then
		SquadBagDoneRight:AllocateAllInSector(squad.CurrentSector)
	end
end

-- Overriding the global OnChangeUnitSquad to use our new allocation logic.
-- The original function is buggy and doesn't handle split squads as well as our sector-wide re-balancing.
function OnChangeUnitSquad(unit, prevSquad, newSquad)
	-- We rely on UnitJoinedPlayerSquad to trigger a full sector-wide re-allocation
	-- which is more robust than trying to calculate a partial share during the move.
end

--- Initializes mod state for a brand new campaign.
function OnMsg.InitSessionCampaignObjects()
	SquadBagDoneRight:UpdateProperties()
end

--- Validates persistent state and prepares target lists after loading a savegame.
function OnMsg.LoadSessionData()
	SquadBagDoneRight:UpdateProperties()
end

--- Re-applies mod options and updates inventories when options are changed by the user.
function OnMsg.ApplyModOptions(mod_id)
	if mod_id == CurrentModId then
		SquadBagDoneRight:UpdateProperties()
	end
end

---------------------------------------------------------------------------------------------------
--- UI INJECTIONS
---------------------------------------------------------------------------------------------------

--- Helper to inject custom allocation buttons into the Inventory Context Menu XTemplate.
--- @param xtemplate table The XTemplate object to patch.
local function PatchInventoryContextMenu(xtemplate)
	if not xtemplate then return end

	-- Robustly find the list container 'idPopupWindow' within the menu structure
	local list = false
	local function find_list(node)
		if type(node) ~= "table" then return end

		if node.Id == "idPopupWindow" then
			list = node
			return true
		end

		for _, child in ipairs(node) do
			if find_list(child) then return true end
		end
	end
	find_list(xtemplate)

	-- If the container isn't found, log a warning and abort injection
	if not list then
		print("[SBDR] [Warning] Could not find idPopupWindow in Context Menu template: " .. tostring(xtemplate.id))
		return
	end

	-- Cleanup: remove any previous injections of our custom buttons to avoid duplicates during mod reloads
	local existing = table.find(list, "Id", "allocateAmmo")
	while existing do
		table.remove(list, existing)
		existing = table.find(list, "Id", "allocateAmmo")
	end

	local existing2 = table.find(list, "Id", "allocateCraftables")
	while existing2 do
		table.remove(list, existing2)
		existing2 = table.find(list, "Id", "allocateCraftables")
	end

	local existing3 = table.find(list, "Id", "allocateAll")
	while existing3 do
		table.remove(list, existing3)
		existing3 = table.find(list, "Id", "allocateAll")
	end

	local existing4 = table.find(list, "Id", "allocateMeds")
	while existing4 do
		table.remove(list, existing4)
		existing4 = table.find(list, "Id", "allocateMeds")
	end

	-- Determine the best insertion point (usually before standard destructive actions like 'scrap' or 'drop')
	local insert_idx = #list + 1
	for i, child in ipairs(list) do
		if child.Id == "scrap" or child.Id == "scrapall" or child.Id == "drop" then
			insert_idx = i
			break
		end
	end

	-- Visibility condition for the custom context menu entries
	local function AllocationCondition(parent, context, allocationType)
		if not context then
			return false
		end

		local ctx = context.context
		local slot_wnd = context.slot_wnd

		-- Check if the context menu is being opened from a Squad Bag
		local is_squad_bag = false
		if IsKindOf(ctx, "SquadBag") or (ctx and ctx.class == "SquadBag") then
			is_squad_bag = true
		elseif IsKindOf(slot_wnd, "SquadBag") or (slot_wnd and slot_wnd.class == "SquadBag") then
			is_squad_bag = true
		elseif slot_wnd and slot_wnd.slot_name == "SquadBag" then
			is_squad_bag = true
		end

		-- Verify if there are multiple player squads in the sector to actually perform allocation
		local unit_squad = context.unit and context.unit.Squad
		local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

		-- Handle sector resolution in Satellite view vs Tactical view
		if gv_SatelliteView and not unit_squad then
			if ctx and ctx.squad_id then
				local sq = gv_Squads[ctx.squad_id]
				if sq then
					sector_id = sq.CurrentSector
				end
			elseif slot_wnd and slot_wnd.context and slot_wnd.context.squad_id then
				local sq = gv_Squads[slot_wnd.context.squad_id]
				if sq then
					sector_id = sq.CurrentSector
				end
			end
		end

		-- Perform sector lookup for squads
		if not sector_id then
			return false
		end

		-- Count number of player squads in the identified sector
		local squads_count = 0
		for _, squad in pairs(gv_Squads or {}) do
			if squad.CurrentSector == sector_id and squad.Side == "player1" then
				squads_count = squads_count + 1
			end
		end

		-- Visibility Logic: must be a squad bag context and there must be more than one squad to re-allocate
		if not is_squad_bag then
			return false
		end

		if squads_count <= 1 then
			return false
		end

		-- Helper to check if an item matches the requested allocation category
		local function isEligible(item)
			if not item then return false end
			local class = item.class

			if allocationType == "ammo" then
				-- Check for various ammo and ordnance types
				return IsKindOf(item, "Ammo") or IsKindOf(item, "Ordnance") or class == "FlareAmmo" or (class and string.starts_with(class, "MortarShell_")) or (class and string.starts_with(class, "_40mm"))
			elseif allocationType == "craftables" then
				-- Check for crafting parts and materials
				if class == "Parts" or table.find(SquadBagDoneRight.lists.craftingItems, class) then
					return true
				end
				return IsKindOf(item, "Explosive") or IsKindOf(item, "Detonator")
			elseif allocationType == "meds" then
				-- Check for medical supplies
				return class == "Meds" or class == "Medkit" or class == "FirstAidKit" or class == "Reanimationsset"
			elseif allocationType == "all" then
				-- Everything in the bag
				return true
			end

			return false
		end

		-- Evaluate eligibility for single-item context menus
		if context.item then
			if isEligible(context.item) then
				return true
			end
		end

		-- Evaluate eligibility for multi-item selection menus
		if context.items then
			for item, _ in pairs(context.items) do
				if isEligible(item) then
					return true
				end
			end
		end

		return false
	end

	-- --- Button Injections ---

	-- 1. ALLOCATE AMMO Button
	table.insert(list, insert_idx, PlaceObj('XTemplateTemplate', {
		'comment', "allocate ammo",
		'__condition', function (parent, context) return AllocationCondition(parent, context, "ammo") end,
		'__template', "ContextMenuButton",
		'Id', "allocateAmmo",
		'OnContextUpdate', function(self, context)
		end,
		'OnPress', function (self, gamepad)
			local context = self:ResolveId("node").context
			if not context then return end
			local unit_squad = context.unit and context.unit.Squad
			local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

			-- Consistent with AllocationCondition logic for sector determination
			if gv_SatelliteView and not unit_squad then
				local ctx = context.context
				local slot_wnd = context.slot_wnd

				if ctx and ctx.squad_id then
					local sq = gv_Squads[ctx.squad_id]
					if sq then sector_id = sq.CurrentSector end
				elseif slot_wnd and slot_wnd.context and slot_wnd.context.squad_id then
					local sq = gv_Squads[slot_wnd.context.squad_id]
					if sq then sector_id = sq.CurrentSector end
				end
			end

			SquadBagDoneRight:AllocateAmmoInSector(sector_id)
		end,
		'Text', T(548200001001, "Allocate Ammo"),
	}))
	insert_idx = insert_idx + 1

	-- Add ALLOCATE CRAFTABLES
	table.insert(list, insert_idx, PlaceObj('XTemplateTemplate', {
		'comment', "allocate craftables",
		'__condition', function (parent, context) return AllocationCondition(parent, context, "craftables") end,
		'__template', "ContextMenuButton",
		'Id', "allocateCraftables",
		'OnContextUpdate', function(self, context)
		end,
		'OnPress', function (self, gamepad)
			local context = self:ResolveId("node").context
			if not context then return end
			local unit_squad = context.unit and context.unit.Squad
			local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

			-- Consistent with AllocationCondition logic for sector determination
			if gv_SatelliteView and not unit_squad then
				local ctx = context.context
				local slot_wnd = context.slot_wnd

				if ctx and ctx.squad_id then
					local sq = gv_Squads[ctx.squad_id]
					if sq then sector_id = sq.CurrentSector end
				elseif slot_wnd and slot_wnd.context and slot_wnd.context.squad_id then
					local sq = gv_Squads[slot_wnd.context.squad_id]
					if sq then sector_id = sq.CurrentSector end
				end
			end

			SquadBagDoneRight:AllocateCraftablesInSector(sector_id)
		end,
		'Text', T(548200001002, "Allocate Craftables"),
	}))
	insert_idx = insert_idx + 1

	-- Add ALLOCATE MEDS
	table.insert(list, insert_idx, PlaceObj('XTemplateTemplate', {
		'comment', "allocate meds",
		'__condition', function (parent, context) return AllocationCondition(parent, context, "meds") end,
		'__template', "ContextMenuButton",
		'Id', "allocateMeds",
		'OnContextUpdate', function(self, context)
		end,
		'OnPress', function (self, gamepad)
			local context = self:ResolveId("node").context
			if not context then return end
			local unit_squad = context.unit and context.unit.Squad
			local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

			-- Consistent with AllocationCondition logic for sector determination
			if gv_SatelliteView and not unit_squad then
				local ctx = context.context
				local slot_wnd = context.slot_wnd

				if ctx and ctx.squad_id then
					local sq = gv_Squads[ctx.squad_id]
					if sq then sector_id = sq.CurrentSector end
				elseif slot_wnd and slot_wnd.context and slot_wnd.context.squad_id then
					local sq = gv_Squads[slot_wnd.context.squad_id]
					if sq then sector_id = sq.CurrentSector end
				end
			end

			SquadBagDoneRight:AllocateMedsInSector(sector_id)
		end,
		'Text', T(548200001012, "Allocate Meds"),
	}))
	insert_idx = insert_idx + 1

	-- Add ALLOCATE ALL
	table.insert(list, insert_idx, PlaceObj('XTemplateTemplate', {
		'comment', "allocate all",
		'__condition', function (parent, context) return AllocationCondition(parent, context, "all") end,
		'__template', "ContextMenuButton",
		'Id', "allocateAll",
		'OnContextUpdate', function(self, context)
		end,
		'OnPress', function (self, gamepad)
			local context = self:ResolveId("node").context
			if not context then return end
			local unit_squad = context.unit and context.unit.Squad
			local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

			-- Consistent with AllocationCondition logic for sector determination
			if gv_SatelliteView and not unit_squad then
				local ctx = context.context
				local slot_wnd = context.slot_wnd

				if ctx and ctx.squad_id then
					local sq = gv_Squads[ctx.squad_id]
					if sq then sector_id = sq.CurrentSector end
				elseif slot_wnd and slot_wnd.context and slot_wnd.context.squad_id then
					local sq = gv_Squads[slot_wnd.context.squad_id]
					if sq then sector_id = sq.CurrentSector end
				end
			end

			SquadBagDoneRight:AllocateAllInSector(sector_id)
		end,
		'Text', T(548200001011, "Allocate All"),
	}))
end

function OnMsg.ClassesPostprocess()
	-- Inject buttons when classes are ready
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end

function OnMsg.BinAssetsLoaded()
	-- Inject buttons when assets are loaded
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end

function OnMsg.DataLoaded()
	-- Inject buttons when data is loaded
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end
