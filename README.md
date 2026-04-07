# Squad Bag Done Right

This mod streamlines inventory management by automatically moving eligible items from merc inventories to their respective squad bags and providing advanced redistribution tools for your squads.

This is an updated version of the original *Crafting items to Squad bag* mod and fixes the bugs and shortcomings of that mod.

---

## Key Features

- **Immediate effect:** Unlike the old mod, changing the item categories in the mod options has immediate effect. No reloading of a save or restarting of the game necessary.
- **Scrapping and cashing in:** Cashing in or scrapping item stacks in the squad bag now works for the new items.
- **Non-stackable items:** Non-stackable items like the big valuables (Figurine, Golden Dog, etc.) will no longer vanish when moving them to the squad bag.
- **Automatic Item Movement:** Automatically moves crafting materials, skill books, and valuables to the squad bag upon game start/load or when mod options are changed. *(Can be toggled in options.)*
- **Context Menu Allocation:** Right-click on Ammo or Craftables in any squad bag to redistribute them across all player squads in the current sector using proportional allocation based on the total magazine size of weapons in each squad. Supports standard ammo, 40mm, mortar shells, flares, and HE rockets (Ordnance).
- **Skill-Based Crafting Allocation:** Redistributes explosives and detonators based on the highest Explosive skill in each squad, and other craftables (like steel pipes) based on the highest Mechanical skill.
- **Minimum Skill Threshold:** Allocation only considers mercs with a relevant skill of 60 or higher to ensure items go to the most capable hands.
- **Improved Sorting:** New items are sorted properly — gun powder ends up next to parts and meds, then comes ammo, heavy ammo, craftables (first explosives, then mechanics items), and finally valuables.
- **Data Integrity & Safety:** Includes robust "Evict Invalid Items" logic and extensive safety checks to prevent item loss or crashes. When you deactivate a category, items are automatically moved back to merc inventories or, if those are full, to the sector stash.
- **Multilingual Support:** Fully localized in all Jagged Alliance 3 supported languages.

---

## Technical Information

> **Before uninstalling:** Make sure you deactivate the item categories in the mod options and create a new save first. Deactivating the categories moves items safely back to inventories or the sector stash. Save after that has happened — then you can uninstall safely.
