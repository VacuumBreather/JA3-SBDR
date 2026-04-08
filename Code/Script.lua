--- @module SquadBagDoneRight
--- @desc This mod handles moving specific crafting, skill, and valuable items to the squad bag automatically.

SquadBagDoneRight = SquadBagDoneRight or {}

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

local SquadBagItemClass = "SquadBagItem"

---------------------------------------------------------------------------------------------------
--- HELPER FUNCTIONS
---------------------------------------------------------------------------------------------------

--- Merges two arrays (t1 and t2) into a new table.
--- @param t1 table First table to merge.
--- @param t2 table Second table to merge.
--- @return table A new table containing elements from t1 followed by elements from t2.
local function ConcatTables(t1, t2)
    local result = {}
    for _, v in ipairs(t1) do
        result[#result + 1] = v
    end
    for _, v in ipairs(t2) do
        result[#result + 1] = v
    end
    return result
end

--- Gets the squad bag items for a specific squad.
--- @param squad_id string The unique ID of the squad.
--- @return table|nil The squad bag table if it exists.
local function GetSquadBag(squad_id)
    local squad = gv_Squads and gv_Squads[squad_id]
    return squad and squad.squad_bag
end

--- Returns a list of player-controlled squads in the specified sector.
--- @param sector_id string The ID of the sector to check.
--- @return table List of player squads in the sector.
local function GetSquadsInSector(sector_id)
    local squads = {}
    for _, squad in pairs(gv_Squads or {}) do
        if squad.CurrentSector == sector_id and squad.Side == "player1" then
            table.insert(squads, squad)
        end
    end
    return squads
end

--- Determines the sort priority of an inventory item.
--- @param item table The inventory item to check.
--- @return number The sort priority value (lower is higher priority).
local function GetSortPriority(item)
    local class = item.class
    if class == "Meds" then return 1 end
    if class == "Parts" then return 2 end
    if class == "BlackPowder" then return 3 end
    if IsKindOf(item, "Ammo") then return 4 end

	if class == "FlareAmmo" then return 5 end

	-- Mortar shells
   	if string.starts_with(class, "MortarShell_") then return 6 end

	-- Warheads
	if class == "Warhead_Frag" then return 7 end

	-- 40mm shells
   	if string.starts_with(class, "_40mm") then return 8 end

    -- Explosives
    if class == "C4" or class == "PETN" or class == "TNT" then return 9 end

    -- Detonators
    if class == "Combination_Detonator_Proximity" or
       class == "Combination_Detonator_Remote" or
       class == "Combination_Detonator_Time" then return 10 end

    -- Armor upgrades
    if class == "Combination_CeramicPlates" or
       class == "Combination_WeavePadding" or
       class == "Combination_Kompositum58" then return 11 end

    -- Weapon parts / Utility
    if class == "Combination_BalancingWeight" or class == "Combination_Sharpener" then return 12 end

    -- Weapon parts / Utility
    if class == "FineSteelPipe" or class == "OpticalLens" or class == "Microchip" then return 13 end

    -- Skill Magazines
    if string.starts_with(class, "SkillMag_") then return 14 end

    -- Consumables
    if class == "MetaviraShot" or class == "CombatStim" then return 15 end

    -- Valuables
    if IsKindOf(item, "Valuables") or class == "MoneyBag" then
        if IsKindOf(item, "InventoryStack") then
            return 16
        else
            return 17
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
	local classObj = g_Classes[className]
   	if not classObj then
		-- print("[SBDR] PatchClassInheritance: Class " .. tostring(className) .. " not found.")
		return
	end

	-- 1. CLONE __parents to avoid leaking to other MiscItem children (MetaviraShot, etc.)
    classObj.__parents = table.copy(classObj.__parents or {})

	if addClass then
		table.insert_unique(classObj.__parents, SquadBagItemClass)
	else
		table.remove_entry(classObj.__parents, SquadBagItemClass)
	end

	-- 2. CLONE __ancestors for safe IsKindOf checks
    classObj.__ancestors = table.copy(classObj.__ancestors or {})

	if addClass then
		classObj.__ancestors[SquadBagItemClass] = true
	else
		classObj.__ancestors[SquadBagItemClass] = nil
	end
end

--- Moves all eligible items from every hired merc's inventory to their respective squad bags.
function SquadBagDoneRight:MoveAllMercsInventoryToSquadBag()
	-- 1. Ensure we are in an active game session
	if not Game or not gv_Squads then
		return
	end

	-- print("[SBDR] MoveAllMercsInventoryToSquadBag: Starting...")

    -- 2. Iterate through all squads in the game
    for squad_id, squad in pairs(gv_Squads) do
        -- Only process player-controlled squads
        if squad.Side == "player1" and squad.units then
            for _, unit_id in ipairs(squad.units) do
                -- 3. Use the built-in MoveItemsToSquadBag for each unit
                -- This function handles the removal, insertion, and sorting
                MoveItemsToSquadBag(unit_id, squad_id)
            end
        end
		_SortItemsInBag(squad_id)
    end
end

--- Removes items from squad bags that are no longer eligible (e.g., due to option changes) and moves them to mercs or sector inventory.
function SquadBagDoneRight:EvictInvalidItems()
	if not Game or not gv_Squads then return end
	-- print("[SBDR] EvictInvalidItems: Starting...")

	for squad_id, squad in pairs(gv_Squads) do
		local bag = squad.squad_bag

		if bag and #bag > 0 then
			for i = #bag, 1, -1 do
				local item = bag[i]

				if item and not IsKindOf(item, SquadBagItemClass) then
					-- print("[SBDR] Evicting invalid item " .. tostring(item.class) .. " from squad " .. tostring(squad_id))
					table.remove(bag, i)
					local moved = false

					if squad.units then
						for _, merc_id in ipairs(squad.units) do
							local unit = gv_UnitData and gv_UnitData[merc_id]

							if not unit then goto continue end

							local canAdd, reason = unit:CanAddItem("Inventory", item)

							if canAdd then
								local added = unit:AddItem("Inventory", item)
								if added then
									moved = true
									break
								else
									print(string.format("[SBDR] [Warning] Moving item %s to merc %s failed", tostring(item.class), tostring(merc_id)))
								end
							end
							::continue::
						end
					end

					if not moved then
						local sector_id = squad.CurrentSector
						if sector_id then
							local sector_inv = GetSectorInventory(sector_id)
							if sector_inv then
								AddItemsToInventory(sector_inv, { item })
								moved = true
								-- print("[SBDR] Item " .. tostring(item.class) .. " moved to sector inventory " .. tostring(sector_id))
							end
						end
					end

					if not moved then
						print(string.format("[SBDR] [Warning] Unable to evict item %s from squad %s - item may be lost!", tostring(item.class), tostring(squad_id)))
					end
				end
			end
		end

		_SortItemsInBag(squad_id)
	end

	if gv_SquadBag then
		local current_squad = gv_SquadBag.squad_id
		gv_SquadBag:Clear()
		gv_SquadBag:SetSquadId(current_squad)
	end
end

--- Applies current mod options to item classes and refreshes the inventories.
function SquadBagDoneRight:UpdateProperties()
	-- print("[SBDR] UpdateProperties: Starting...")
	local options = CurrentModOptions
	if not options then
		print("[SBDR] [Warning] CurrentModOptions not found. Skipping update.")
		return
	end

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

	self:EvictInvalidItems()

	if options.sbdr_auto_move_to_bag then
		self:MoveAllMercsInventoryToSquadBag()
	end

	-- print("[SBDR] UpdateProperties: Finished.")
end

---------------------------------------------------------------------------------------------------
--- ENGINE OVERRIDING / PATCHING FUNCTIONS
---------------------------------------------------------------------------------------------------

--- Internal function to sort and stack items in a specific squad bag.
--- @param squad_id string The ID of the squad whose bag is to be sorted.
function _SortItemsInBag(squad_id)
	if not gv_Squads or not gv_Squads[squad_id] then
		-- print("[SBDR] _SortItemsInBag: Invalid squad_id " .. tostring(squad_id))
		return
	end

	local bag_items = GetSquadBag(squad_id)
	if not bag_items then return end

	local stacks = {}
	local non_stackables = {}
	for idx, item in ipairs(bag_items) do
		if item and not IsKindOf(item, "InventoryStack") then
			non_stackables[#non_stackables + 1] = item
		elseif item then
			for i = 1, #stacks do
				local bag_item = stacks[i]
				if bag_item.class == item.class then
					local to_add = Min(bag_item.MaxStacks - bag_item.Amount, item.Amount)
					if to_add>0 then
						bag_item.Amount = bag_item.Amount + to_add
						item.Amount = item.Amount - to_add
						if item.Amount==0 then
							DoneObject(item)
							item = false
							break
						end
					end
				end
			end
			if item and item.Amount and item.Amount>0 then
				stacks[#stacks + 1] = item
			end
		end
	end

	local all_items = ConcatTables(stacks, non_stackables)

	table.sort(all_items, function(a, b)
		local priority_a = GetSortPriority(a)
		local priority_b = GetSortPriority(b)

		if priority_a ~= priority_b then
			return priority_a < priority_b
		end

		-- Within the same priority group, secondary sorting
		if priority_a == 4 then -- Ammo
			local caliber_a = a.Caliber
			local caliber_b = b.Caliber
			if caliber_a == caliber_b then
				if a.Amount == b.Amount then
					return (a.class or "") < (b.class or "")
				else
					return (a.Amount or 0) > (b.Amount or 0)
				end
			else
				return (caliber_a or "") < (caliber_b or "")
			end
		elseif priority_a == 1 or priority_a == 2 then -- Meds, Parts
			return (a.Amount or 0) > (b.Amount or 0)
		elseif priority_a == 9 or priority_a == 10 or priority_a == 11 then -- SkillMags, Valuables
			if a.class == b.class then
				local amount_a = (IsKindOf(a, "InventoryStack") and a.Amount) or 1
				local amount_b = (IsKindOf(b, "InventoryStack") and b.Amount) or 1
				return amount_a > amount_b
			end
			return (a.class or "") < (b.class or "")
		else
			-- For other groups, sort by class name then amount
			if a.class == b.class then
				local amount_a = (IsKindOf(a, "InventoryStack") and a.Amount) or 1
				local amount_b = (IsKindOf(b, "InventoryStack") and b.Amount) or 1
				return amount_a > amount_b
			end
			return (a.class or "") < (b.class or "")
		end
	end)
	gv_Squads[squad_id].squad_bag = all_items

    -- Centralized UI Refresh
    if gv_SquadBag and gv_SquadBag.squad_id == squad_id then
        if InventoryUIResetSquadBag then InventoryUIResetSquadBag() end
        gv_SquadBag:SetSquadId(squad_id)
        if InventoryUIRespawn then InventoryUIRespawn() end
    end
end

-- Patching ItemIsFound to include SquadBag in its search.
local sbdr_old_ItemIsFound_eval = ItemIsFound.__eval
function ItemIsFound:__eval(obj, context)
	local result = sbdr_old_ItemIsFound_eval(self, obj, context)
	if result then return true end

	-- If not found on mercs or in containers, check the SquadBags in the sector
	local sector_id = self.Sector == "current" and gv_CurrentSectorId or self.Sector
	if not sector_id then return false end

	local squads = GetSquadsInSector(sector_id)
	if not squads then return false end

	local amount = self.Amount
	local cur_amount = 0

	for _, squad in ipairs(squads) do
		local bag = GetSquadBag(squad.UniqueId)
		if bag then
			for _, item in ipairs(bag) do
				if item and item.class == self.ItemId then
					cur_amount = cur_amount + (IsKindOf(item, "InventoryStack") and item.Amount or 1)
					if cur_amount >= amount then return true end
				end
			end
		end
	end
	return false
end

-- Patching ItemIsInMerc to include SquadBag in its check.
local sbdr_old_ItemIsInMerc_eval = ItemIsInMerc.__eval
function ItemIsInMerc:__eval(obj, context)
	local result = sbdr_old_ItemIsInMerc_eval(self, obj, context)
	if result then return true end

	-- Check player squad bags
	local sector_id = self.Sector == "current" and gv_CurrentSectorId or self.Sector
	local squads = self.Sector == "all_sectors" and GetPlayerMercSquads() or (sector_id and GetSquadsInSector(sector_id))
	if not squads then return false end

	local amount = self.Amount
	local cur_amount = 0

	for _, squad in ipairs(squads) do
		local bag = GetSquadBag(squad.UniqueId)
		if bag then
			for _, item in ipairs(bag) do
				if item and item.class == self.ItemId then
					cur_amount = cur_amount + (IsKindOf(item, "InventoryStack") and item.Amount or 1)
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
	if not items then return end
	if not gv_Squads or not gv_Squads[squad_id] then
		-- print("[SBDR] AddItemsToSquadBag: Invalid squad_id " .. tostring(squad_id))
		return
	end

	local bag = GetSquadBag(squad_id)
	if not bag then
		bag = {}
		gv_Squads[squad_id].squad_bag = bag
	end

	for i=#items,1, -1 do
		local item =  items[i]
		if item and IsKindOf(item, "SquadBagItem") then
			local count = IsKindOf(item, "InventoryStack") and item.Amount or 1
			for _, curitm in ipairs(bag) do
				if curitm and curitm.class == item.class and IsKindOf(curitm, "InventoryStack") and curitm.Amount < curitm.MaxStacks then
					local to_add = Min(curitm.MaxStacks - curitm.Amount, count)
					curitm.Amount = curitm.Amount + to_add
					count = count - to_add
					if to_add > 0 then
						Msg("SquadBagAddItem", curitm, to_add)
					end
					if count <= 0 then
						DoneObject(item)
						item = false
						break
					end
				end
			end
			if item and count > 0 then
				table.insert(bag, item)
				Msg("SquadBagAddItem", item, count)
			end
			table.remove(items, i)
		end
	end

	SortItemsInBag(squad_id)
end

--- Hook into ScrapItem to ensure squad bag sync when an item is scrapped from the squad bag UI.
local sbdr_old_ScrapItem = ScrapItem
function ScrapItem(inventory, slot_name, item, amount, squadBag, squadId)
	if not squadBag then
		if sbdr_old_ScrapItem then sbdr_old_ScrapItem(inventory, slot_name, item, amount, squadBag, squadId) end
		return
	end

	-- Identify the correct squad ID
	local squad_id = squadBag.squad_id

	-- If the ID is invalid, search for the item in all squad bags
	if not gv_Squads or not gv_Squads[squad_id] then
		if gv_Squads then
			for id, squad in pairs(gv_Squads) do
				if squad.squad_bag and table.find(squad.squad_bag, item) then
					squadBag.squad_id = id
					-- print("[SBDR] ScrapItem: Fixed squad_id for item " .. tostring(item and item.class))
					break
				end
			end
		end
	end

	if sbdr_old_ScrapItem then
		sbdr_old_ScrapItem(inventory, slot_name, item, amount, squadBag, squadId)
	end
end

--- Overrides SquadBag:RemoveItem to ensure persistent squad data is kept in sync.
--- @param slot_name string Name of the inventory slot.
--- @param item table The item being removed.
--- @param no_update boolean Whether to skip updating/sorting the bag.
function SquadBag:RemoveItem(slot_name, item, no_update)
	local removedItem, pos = Inventory.RemoveItem(self, slot_name, item, no_update)

	-- Identify the correct squad ID
	local squad_id = self.squad_id

	-- If the ID is invalid, search for the item in all squad bags
	if not gv_Squads or not gv_Squads[squad_id] then
		if gv_Squads then
			for id, squad in pairs(gv_Squads) do
				if squad.squad_bag and table.find(squad.squad_bag, item) then
					squad_id = id
					-- print("[SBDR] RemoveItem: Fixed squad_id for item " .. tostring(item and item.class))
					break
				end
			end
		end
	end

	-- Sync with the identified squad's data
	local squad = gv_Squads and gv_Squads[squad_id]
	if squad then
		local cdata = squad.squad_bag or {}
		table.remove_entry(cdata, item)
		squad.squad_bag = cdata -- Update the persistent data

		if not no_update then
			SortItemsInBag(squad_id)
		end
	else
		print(string.format("[SBDR] [Warning] Could not find squad for item %s during RemoveItem. Sync may fail.", tostring(item and item.class)))
	end

	return removedItem, pos
end

local sbdr_old_Combine2ItemsInternal = Combine2ItemsInternal

function Combine2ItemsInternal(recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)
    local is_bag1 = type(item1_context) == "number"
    local is_bag2 = type(item2_context) == "number"

    -- Special handling if BOTH ingredients are from a squad bag
    if is_bag1 and is_bag2 then
        local target_unit = GetContainerFromContainerNetId(unit_operator_id)

        -- Temporarily override AddItemsToInventory to redirect failed bag additions to the operator
        local sbdr_old_AddItemsToInventory = AddItemsToInventory
        local added_item_name
		local was_added = false

        _G.AddItemsToInventory = function(inventoryObj, items, bLog)
            local pos, reason = sbdr_old_AddItemsToInventory(inventoryObj, items, bLog)

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

        local status, err = procall(sbdr_old_Combine2ItemsInternal, recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)

        -- Restore original function
        _G.AddItemsToInventory = sbdr_old_AddItemsToInventory

        -- Log placement if it ended up in the target unit's inventory
        if status and was_added then
            CombatLog("important", T(435437836774, "Items acquired:"))
            local res = T{581384045758, " <amount> x <em><itemNameT></em> (<mercName>)", amount = 1, itemNameT = added_item_name, mercName = target_unit:GetDisplayName()}
            CombatLog("importanthelper", res)
        end

        if not status then error(err) end

        return
    end

    -- Default behavior for standard combinations
    return sbdr_old_Combine2ItemsInternal(recipe_id, outcome, outcome_hp, skill_type, unit_operator_id, item1_context, item1_pos, item2_context, item2_pos, item2)
end

---------------------------------------------------------------------------------------------------
--- EVENT HANDLERS / INITIALIZATION
---------------------------------------------------------------------------------------------------

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

--- Initializes attack state for a brand new campaign.
function OnMsg.InitSessionCampaignObjects()
	SquadBagDoneRight:UpdateProperties()
end

--- Validates persistent state and prepares target lists after loading a savegame.
function OnMsg.LoadSessionData()
	SquadBagDoneRight:UpdateProperties()
end

--- Re-applies mod options and updates inventories when options are changed.
function OnMsg.ApplyModOptions(mod_id)
	if mod_id == CurrentModId then
		SquadBagDoneRight:UpdateProperties()
	end
end

---------------------------------------------------------------------------------------------------
--- UI INJECTIONS
---------------------------------------------------------------------------------------------------

--- Helper to inject allocation buttons into an Inventory Context Menu XTemplate
--- @param xtemplate table The XTemplate object to patch.
local function PatchInventoryContextMenu(xtemplate)
	if not xtemplate then return end

	-- Robustly find the list container 'idPopupWindow'
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

	if not list then
		print("[SBDR] [Warning] Could not find idPopupWindow in Context Menu template: " .. tostring(xtemplate.id))
		return
	end

	-- Prevent duplicate injection
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

	-- Find the index of "scrap" or similar to insert before it
	local insert_idx = #list + 1
	for i, child in ipairs(list) do
		if child.Id == "scrap" or child.Id == "scrapall" or child.Id == "drop" then
			insert_idx = i
			break
		end
	end

	-- Common condition for showing allocation options
	local function AllocationCondition(parent, context, allocationType)
		-- print("[SBDR] AllocationCondition: Start for " .. tostring(allocationType))
		if not context then
			-- print("[SBDR] AllocationCondition: No context")
			return false
		end

		local ctx = context.context
		local slot_wnd = context.slot_wnd

		-- print("[SBDR] AllocationCondition: context.context type:", type(ctx), ctx and (IsKindOf(ctx, "Object") and ctx.class or "Not an object"))
		if slot_wnd then
			-- print("[SBDR] AllocationCondition: slot_wnd.slot_name:", slot_wnd.slot_name)
		end

		-- Try to find if we are in a squad bag
		local is_squad_bag = false
		if IsKindOf(ctx, "SquadBag") or (ctx and ctx.class == "SquadBag") then
			is_squad_bag = true
		elseif IsKindOf(slot_wnd, "SquadBag") or (slot_wnd and slot_wnd.class == "SquadBag") then
			is_squad_bag = true
		elseif slot_wnd and slot_wnd.slot_name == "SquadBag" then
			is_squad_bag = true
		end

		-- print("[SBDR] AllocationCondition: is_squad_bag=" .. tostring(is_squad_bag))

		-- Check if there are other player squads in the sector
		local unit_squad = context.unit and context.unit.Squad
		local sector_id = unit_squad and gv_Squads[unit_squad] and gv_Squads[unit_squad].CurrentSector or gv_CurrentSectorId

		-- In Satellite view, gv_CurrentSectorId is usually correct, but if we are right-clicking a squad bag
		-- from a squad that is NOT in the current sector, we need to handle that.
		if gv_SatelliteView and not unit_squad then
			-- If we are in satellite view and don't have a unit, try to get the sector from the squad bag context
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

		-- print("[SBDR] AllocationCondition: sector_id:", tostring(sector_id))

		if not sector_id then
			-- print("[SBDR] AllocationCondition: No sector_id")
			return false
		end

		local squads_count = 0
		for _, squad in pairs(gv_Squads or {}) do
			if squad.CurrentSector == sector_id and squad.Side == "player1" then
				squads_count = squads_count + 1
			end
		end

		-- print("[SBDR] AllocationCondition: squads_count:", squads_count)

		if not is_squad_bag then
			-- print("[SBDR] AllocationCondition: Not a squad bag. ctx:", tostring(ctx and ctx.class), "slot_wnd:", tostring(slot_wnd and slot_wnd.class))
			return false
		end

		if squads_count <= 1 then
			-- print("[SBDR] AllocationCondition: Only one squad in sector " .. tostring(sector_id))
			return false
		end

		-- Check item eligibility
		local function isEligible(item)
			if not item then return false end
			local class = item.class
			-- print("[SBDR] isEligible check for", tostring(class), "allocationType:", tostring(allocationType))
			if allocationType == "ammo" then
				local res = IsKindOf(item, "Ammo") or IsKindOf(item, "Ordnance") or class == "FlareAmmo" or (class and string.starts_with(class, "MortarShell_")) or (class and string.starts_with(class, "_40mm"))
				-- print("[SBDR] isEligible ammo result:", tostring(res))
				return res
			elseif allocationType == "craftables" then
				if class == "Parts" or table.find(SquadBagDoneRight.lists.craftingItems, class) then
					-- print("[SBDR] isEligible craftables result: true (found in craftingItems list or Parts)")
					return true
				end
				local res = IsKindOf(item, "Explosive") or IsKindOf(item, "Detonator")
				-- print("[SBDR] isEligible craftables result:", tostring(res), "(IsKindOf Explosive/Detonator)")
				return res
			elseif allocationType == "meds" then
				local res = class == "Meds" or class == "Medkit" or class == "FirstAidKit" or class == "Reanimationsset"
				-- print("[SBDR] isEligible meds result:", tostring(res))
				return res
			elseif allocationType == "all" then
				return true
			end
			return false
		end

		-- Handle single selection (InventoryContextMenu)
		if context.item then
			if isEligible(context.item) then
				-- print("[SBDR] AllocationCondition: Single item eligible:", context.item.class)
				return true
			end
		end

		-- Handle multi selection (InventoryContextMenuMulti)
		if context.items then
			for item, _ in pairs(context.items) do
				if isEligible(item) then
					-- print("[SBDR] AllocationCondition: Multi item eligible:", item.class)
					return true
				end
			end
		end

		-- print("[SBDR] AllocationCondition: No eligible items found for " .. tostring(allocationType))
		return false
	end

	-- Add ALLOCATE AMMO
	table.insert(list, insert_idx, PlaceObj('XTemplateTemplate', {
		'comment', "allocate ammo",
		'__condition', function (parent, context) return AllocationCondition(parent, context, "ammo") end,
		'__template', "ContextMenuButton",
		'Id', "allocateAmmo",
		'OnContextUpdate', function(self, context)
			-- print("[SBDR] on allocateAmmo update. Visible:", self.Visible, "Enabled:", self.enabled)
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
			-- print("[SBDR] on allocateCraftables update. Visible:", self.Visible, "Enabled:", self.enabled)
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
			-- print("[SBDR] on allocateMeds update. Visible:", self.Visible, "Enabled:", self.enabled)
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
			-- print("[SBDR] on allocateAll update. Visible:", self.Visible, "Enabled:", self.enabled)
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

	-- print("[SBDR] Injected allocation options into Context Menu: " .. tostring(xtemplate.id))

	-- Debug: verify the list actually has our items
	for i, child in ipairs(list) do
		if child.Id == "allocateAmmo" or child.Id == "allocateCraftables" or child.Id == "allocateMeds" or child.Id == "allocateAll" then
			-- print("[SBDR] Verified child in list at index " .. i .. ": " .. tostring(child.Id))
		end
	end
end

function OnMsg.ClassesPostprocess()
	-- print("[SBDR] ClassesPostprocess: Patching context menus...")
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end

function OnMsg.BinAssetsLoaded()
	-- print("[SBDR] BinAssetsLoaded: Patching context menus...")
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end

function OnMsg.DataLoaded()
	-- print("[SBDR] DataLoaded: Patching context menus...")
	PatchInventoryContextMenu(XTemplates.InventoryContextMenu)
	PatchInventoryContextMenu(XTemplates.InventoryContextMenuMulti)
end
