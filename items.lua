return {
	PlaceObj('ModItemOptionToggle', {
		'name', "sbdr_crafting_items",
		'DisplayName', T(548200001007, "Crafting items to squad bag"),
		'Help', T(548200001003, "Allows moving crafting items to the squad bag"),
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "sbdr_skill_mags",
		'DisplayName', T(548200001008, "Skill mags to squad bag"),
		'Help', T(548200001004, "Allows moving skill magazines to the squad bag"),
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "sbdr_valuables",
		'DisplayName', T(548200001009, "Valuables to squad bag"),
		'Help', T(548200001005, "Allows moving valuables (and money bags) to the squad bag"),
		'DefaultValue', true,
	}),
	PlaceObj('ModItemOptionToggle', {
		'name', "sbdr_auto_move_to_bag",
		'DisplayName', T(548200001010, "Automatically move items to bag"),
		'Help', T(548200001006, "Enable to move items from merc inventories to the squad bag automatically. Note: this will only be triggered on game start/load or when the mod options are changed."),
		'DefaultValue', true,
	}),
	PlaceObj('ModItemCode', {
		'CodeFileName', "Code/Script.lua",
	}),
	PlaceObj('ModItemCode', {
		'name', "Allocation",
		'CodeFileName', "Code/Allocation.lua",
	}),
	PlaceObj('ModItemLocTable', {
		'language', "English",
		'filename', "Languages/en.csv",
	}),
}