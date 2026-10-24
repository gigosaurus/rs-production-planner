# Recipe params in Obj configs

Findings from 2026-10-24. No probe has verified them yet. Each finding gives a confidence:

- **Confirmed**: many items agree with the wiki, with no contradiction.
- **Likely**: the data fits, but a probe must check it.
- **Unknown**: we have a guess or nothing.

## Decision

The plugin reads recipe data at runtime from `config.Obj` params. This replaces the wiki Bucket pipeline of ADR 0016. An ADR must record this decision.

The params do not give every way to get an item. See "What the params do not give". We can still need the wiki for some sources.

## Source

- `config.Obj.FromID(id)` gives a table with `params`. The keys are param config names, for example `RECIPE_XP_VALUE_1`.
- A param that refers to a config gives a userdata, for example an Obj or a Struct.
- `api-signatures.md` documents `GetParamValue(param : ParamType)`. It does not document a `params` table with names as keys. A probe must confirm that table and add it to `client-behaviour.md`.

## Method

1. A plugin exported every Obj to the `items` table of `objects/objects.sqlite3`: 63,935 objects, IDs 0 to 64,356. The export does not expand Structs.
2. Scripts counted each `RECIPE_*` key and its values.
3. A script got all 15,954 rows of the wiki `recipe` bucket. It matched the rows to game recipes by output name and skill level, and compared the XP.
4. An earlier pass on a partial export compared 207 items in detail: levels, XP, ingredients and output counts.
5. A second export (PR #88) got other config kinds into the `configs` table: 6,041 Params, 35,926 Structs, 536 Quests, 8,791 Enums and 10,894 VarPlayers. VarPlayer rows leave out `value`. Quest rows include the progress of the account that ran the export (`hasFinishedQuest` and similar), so this document does not use those fields.

The wiki can be wrong. A difference is not proof that the game data is correct. The matching uses item names, and some names are shared by more than one item.

## Size

| Count | Objects |
|---|---|
| Objects with a `RECIPE_*` param | 7,839 |
| Objects with a requirement | 7,361 |
| Objects with an ingredient | 7,690 |
| Different output items, including dummy recipes | 6,313 |

## Comparison with the wiki

13,729 wiki rows have an output.

| Result | Wiki rows |
|---|---|
| The game has a recipe with the same skill and level | 6,777 |
| The game has a recipe for the item, but with a different method | 268 |
| The game has a recipe for the item; the wiki row gives no skill | 361 |
| The game has no recipe for the item | 6,323 |

846 game recipe outputs have no wiki row. Examples: teleport tablets, part-made pies, unfinished summoning pouches, `Guthix balance (unfinished)`.

For the rows with the same method, the XP agrees in 5,638 cases and differs in 534. See "XP" for the cause of most differences.

## Param counts

| Param | Objects | Highest `N` |
|---|---|---|
| `RECIPE_REQUIREMENT_TYPE_N` / `_VALUE_N` | 7,362 | 5 |
| `RECIPE_INGREDIENT_TYPE_N` | 7,081 | 10 |
| `RECIPE_XP_TYPE_N` | 7,049 | 2 |
| `RECIPE_INGREDIENT_NUMBER_N` | 6,994 | 10 |
| `RECIPE_XP_VALUE_N` | 6,391 | 2 |
| `RECIPE_TOOL_TYPE_N` | 2,962 | 2 |
| `RECIPE_INGREDIENT_n_MULTIPLE` | 1,791 | 10 |
| `RECIPE_CYCLES` | 1,465 | - |
| `RECIPE_IS_MEMBERS_ONLY` | 1,034 | - |
| `RECIPE_OVERRIDE_STACK_MAKE_LIMIT` | 779 | - |
| `RECIPE_SLOTS_NEEDED` | 672 | - |
| `RECIPE_MAKE_STACK_SIZE` | 524 | - |
| `RECIPE_IGNORE_BOB` | 343 | - |
| `RECIPE_SHOW_CONDITION` | 324 | - |
| `RECIPE_NON_DUMMY_OBJ` | 279 | - |
| `RECIPE_EXTRA_INV_SPACE_REQUIRED` | 274 | - |
| `RECIPE_HIDE_WHEN_LOCKED` | 261 | - |
| `RECIPE_SHOW_CONDITION_TYPE_N` / `_VALUE_N` | 245 | 1 |
| `RECIPE_INGREDIENT_n_SCALE_STACK` | 149 | 2 |
| `RECIPE_INGREDIENT_EXTRA_INFO_N` | 187 | 10 |
| `RECIPE_DEFAULT_QUANTITY` | 215 | - |
| `RECIPE_CAN_BE_BOOSTED` | 197 | - |
| `RECIPE_XP_SCALE_STACK_N` | 151 | 1 |
| `RECIPE_INGREDIENT_EXTRA_AMOUNT_CHECK_N` | 110 | 5 |
| Others | fewer than 60 each | - |

## Param definitions

**Confirmed.** Each Param config gives `valueType` and `defaultValue`. The docs say that `GetParamValue` gives `defaultValue` when an item does not have the param. So a missing recipe param means its default.

| Param | Type | Default |
|---|---|---|
| `RECIPE_REQUIREMENT_TYPE_N`, `_VALUE_N` (N = 1 to 5) | INTEGER | 0 |
| `RECIPE_INGREDIENT_TYPE_N` (N = 1 to 18) | OBJ | -1 (none) |
| `RECIPE_INGREDIENT_NUMBER_N` (N = 1 to 18) | INTEGER | 0 |
| `RECIPE_INGREDIENT_N_MULTIPLE` (N = 1 to 10) | STRUCT | -1 (none) |
| `RECIPE_INGREDIENT_N_SCALE_STACK` (N = 1 to 18) | BOOLEAN | `true` |
| `RECIPE_INGREDIENT_EXTRA_INFO_N` (N = 1 to 18) | INTEGER | 0 |
| `RECIPE_TOOL_TYPE_N` (N = 1 to 3) | OBJ | -1 (none) |
| `RECIPE_TOOL_N_MULTIPLE` (N = 1 to 3) | STRUCT | -1 (none) |
| `RECIPE_XP_TYPE_N`, `_VALUE_N` (N = 1, 2) | INTEGER | 0 |
| `RECIPE_XP_SCALE_STACK_N` (N = 1, 2) | BOOLEAN | `true` |
| `RECIPE_MAKE_STACK_SIZE` | INTEGER | 1 |
| `RECIPE_CYCLES` | INTEGER | 0 |
| `RECIPE_BATCH_SIZE` | INTEGER | 1 |
| `RECIPE_CAN_BE_BOOSTED` | BOOLEAN | `true` |
| `RECIPE_IS_MEMBERS_ONLY` | BOOLEAN | `false` |
| `RECIPE_SLOTS_NEEDED` | INTEGER | 1 |
| `RECIPE_ADD_TO_INV` | BOOLEAN | `true` |
| `RECIPE_IMPROVEMENT_LEVEL` | INTEGER | -1 |
| `RECIPE_SHOW_CONDITION_TYPE_N`, `_VALUE_N` (N = 1 to 3) | INTEGER | 0 |
| `RECIPE_NON_DUMMY_OBJ`, `RECIPE_MULTI_OBJECT_OVERRIDE` | OBJ | -1 (none) |
| `RECIPE_NAME_OVERRIDE`, `RECIPE_MULTI_NAME_OVERRIDE`, `RECIPE_MESSAGE` | STRING | empty |
| `RECIPE_GRAPHIC` | SPRITE | -1 |
| `INVENT_CLIENT_RECIPE` | DBROW | -1 |

Notes:

- Recipes can have up to 18 ingredients and 3 tools. The export showed only up to 10 ingredients and 2 tools.
- `RECIPE_REQUIREMENT_VALUE_N` is a plain INTEGER. The type does not tell us what a type 62 or 64 value refers to.
- `INVENT_CLIENT_RECIPE` points to a DBRow. The probe does not export DBRows.

## Skill codes

**Confirmed.** `RECIPE_REQUIREMENT_TYPE_N` and `RECIPE_XP_TYPE_N` use the same codes for skills. The codes are not the `SkillType` enum. They follow the order of the RS3 stats interface, starting at 1. The full export has examples of every code except 1, 2, 3 and 5.

| Code | Skill | Example | Code | Skill | Example |
|---|---|---|---|---|---|
| 1 | Attack | - | 16 | Cooking | Shrimps |
| 2 | Strength | - | 17 | Firemaking | Pyre logs |
| 3 | Ranged | - | 18 | Woodcutting | Split log |
| 4 | Magic | Orbs | 19 | Fletching | Bows |
| 5 | Defence | - | 20 | Slayer | Poisoned traps |
| 6 | Constitution | Portents (second requirement) | 21 | Farming | Seedlings |
| 7 | Prayer | Blessed spirit shields | 22 | Construction | Planks, furniture |
| 8 | Agility | Thoroughly swept rug | 23 | Hunter | Traps, birdhouses |
| 9 | Herblore | Unfinished potions | 24 | Summoning | Pouches |
| 10 | Thieving | Camouflage outfit piece | 25 | Dungeoneering | Dungeoneering outfit piece |
| 11 | Crafting | Vial | 26 | Divination | Transmuted fish |
| 12 | Runecrafting | Tiaras | 27 | Invention | Gizmo shells |
| 13 | Mining | Gemstone golem outfit piece | 28 | Archaeology | Restored artefacts |
| 14 | Smithing | Arrowheads | 29 | Necromancy | Ritual glyphs |
| 15 | Fishing | Shark outfit piece | | | |

Codes 1, 2, 3 and 5 follow from the order. **Likely.**

## Requirements

`RECIPE_REQUIREMENT_TYPE_N` gives the kind. `RECIPE_REQUIREMENT_VALUE_N` gives the value. A recipe has up to 5 requirements.

| Type | Count | Meaning | Confidence |
|---|---|---|---|
| 1 to 29 | - | Skill level. The value is the level. | Confirmed |
| 61 | 155 | Quest complete. The value is the `QUEST_ID` param of the quest, not its config ID. | Confirmed |
| 62 | 2,646 | An unlock. The value is an ID, perhaps of a varbit or a DBRow. | Unknown |
| 63 | 316 | Invention discovery. The value is a discovery index. | Likely |
| 64 | 297 | A facility or station, perhaps. | Unknown |
| 67 | 123 | No value. Only on house furniture. | Unknown |

### Type 61

**Confirmed.** The value is the `QUEST_ID` param of a Quest config. It is not the Quest config ID: 364 of 365 quests with a `QUEST_ID` have a different config ID. Only Dwarf Cannon has the same value (34) for both.

To find the quest, search the Quest configs for `QUEST_ID = value`. All 25 values give the quest that the wiki gives:

| Value | Quest | Example item |
|---|---|---|
| 8 | The Knight's Sword | Blurite sword |
| 10 | Fate of the Gods | Divine simulacrum I |
| 20 | Big Chompy Bird Hunting | Cooked chompy |
| 30 | Desert Treasure | Paddewwa teleport |
| 34 | Dwarf Cannon | Cannonball |
| 41 | The Eyes of Glouphrie | Crystal staff |
| 43 | A Fairy Tale II - Cure a Queen | Portable fairy ring |
| 67 | Legends' Quest | Holy water |
| 70 | Lunar Diplomacy | Moonclan teleport |
| 81 | Observatory Quest | Unstrung emblem |
| 102 | Swan Song | Raw monkfish |
| 103 | Tai Bwo Wannai Trio | Bronze spear |
| 108 | The Tourist Trap | Bronze dart tip |
| 127 | The Path of Glouphrie | Crystal chime |
| 132 | As a First Resort | Potion flask |
| 143 | Summer's End | Arcane spirit shield |
| 146 | In Pyre Need | Phoenix pouch |
| 176 | Ritual of the Mahjarrat | Armadyl battlestaff |
| 196 | The Brink of Extinction | Obsidian bar |
| 198 | Bringing Home the Bacon | Bacon |
| 310 | Azzanadra's Quest | Pontifex observation ring |
| 313 | City of Senntisten | Pontifex shadow ring |
| 339 | Kili Row | Lesser unensouled bar |
| 365 | Hearts of Sanguine | Antisanguine (3) |
| 371 | Heralds of Crimson | Extreme antisanguine (3) |

The same numbering appears elsewhere. Cannonball has `USE_REQUIRES_QUEST1 = 34`, and an achievement Struct uses `TASK_REQUIREMENT_1_TYPE = 61` with value 70 (Lunar Diplomacy). So the requirement codes are perhaps a shared system, not only for recipes.

### Type 62

2,646 requirements with 306 different values. An object can have up to 3 of them.

| Value | Items | Wiki |
|---|---|---|
| 187 | 1,317 smithing items, for example arrowheads | Anvil |
| 5 | 350 Dungeoneering items (`RAND_*` configs) | Daemonheim |
| 188 | 113 burial weapons | - |
| 87 | 39 divine rocks and bubbles | - |
| 321 to 324, 186, 194 | Masterwork bow, armour and parts | - |
| 95, 148 | Teleport tablets | Lectern |
| 329, 330 | Ensouled bars and thread | Ensoul material |
| 189 | Dragon sq shield, spirit shields | Anvil |
| 190, 8 | Spears (both values on each spear) | Barbarian anvil |
| 300 to 312 | Deathwarden armour, several on each item | - |
| 7 | Brutal arrows | Partial completion of Zogre Flesh Eaters |
| 27, 28 | Clean sito foil, Clean volencia moss | Partial completion of Jungle Potion |
| 30 | Barbarian mixes | Barbarian Herblore training |
| 35 | Leathers, also the Lunar Tan Leather spell | - |
| 36 | Bane arrows | Partial completion of Ritual of the Mahjarrat |
| 209, 210, 120 | Elder, batch and supreme overloads | - |

Our guess: the value refers to a separate unlock condition. We compared the values with the IDs of every exported kind. None gives sensible names:

- As a `QUEST_ID`, 187 (arrowheads) would be One Piercing Note, and 5 (Daemonheim) would be Ernest the Chicken.
- As a VarPlayer ID, 187 is `SS_INVITED` and 35 is `MUSICLENGTH`.
- As a Struct or Enum ID, the names are unrelated, for example cosmetic packs and bookcase entries.

So the value is probably a varbit or a DBRow. The probe exports neither. The API documents a lookup only for `var.VarPlayer` and `var.VarClient`.

### Type 64

| Value | Items | Our guess |
|---|---|---|
| 1 | 244 restored Archaeology artefacts | Archaeologist's workbench |
| 2 | 8 Archaeology soils | Soil screening mesh |
| 17 | 12 planks | Sawmill |
| 22 | 9 overloads | - |
| 23 | 6 unfinished overloads | - |
| 25 | 18 Primal crossbow marks | - |

### Type 67

Only on 123 house furniture items, with Construction. It has no value. Perhaps "build in a player-owned house".

### Show conditions

**Unknown.** `RECIPE_SHOW_CONDITION_TYPE_1` is always 69. `RECIPE_SHOW_CONDITION_VALUE_1` is 212 on 241 objects, nearly all restored Archaeology artefacts. Perhaps the recipe shows only when a condition is true, for example a found artefact.

## XP

- `RECIPE_XP_VALUE_N` is XP × 10. Clean lantadyme is 131, which is 13.1 XP. **Confirmed.**
- If `RECIPE_XP_SCALE_STACK_N` is `false`, the value is for one output item. If it is `true`, the value is for one action. The Param default is `true`, so a recipe without the param gives XP for one action. **Confirmed.** Evidence: on the 346 compared recipes with the flag `false` (mostly ammunition), the XP agrees with the wiki per item, not per action. Bolts: 1.5 XP each, 10 bolts for each action, and the wiki gives 15 XP for 10 bolts.
- The wiki often gives XP for a batch, for example darts ×10 or Mechanised chinchompa ×50. Per output item, the XP agrees in 5,568 cases. **Confirmed.**
- A recipe has up to 2 XP entries. The two entries can name the same skill. Then the total is the sum. For example, Asgarnian ale is 9 + 248 = 25.7 XP, and the wiki gives 25.7. **Likely**: perhaps one entry is a step.
- The second entry can be a different skill. For example, Mining accumulator gives 660 Invention XP and 150 Crafting XP. **Confirmed.**
- 667 objects have `RECIPE_XP_TYPE_1` but no value. 367 objects have the value 0, of which 325 are Farming. `RECIPE_XP_GIVE_NO_XP = 1` is on 43 player-owned fort buildings.
- Normal runes (for example Fire rune, 554) have only `RECIPE_XP_TYPE_1 = 12`, with no value and no recipe. Runecrafting at an altar is not a recipe.
- About 150 compared recipes have no stack and still have different XP. Examples: Ruby amulet (game 85, wiki 4), Pat of butter (40.5, 22.5), Papaya seedling (1.0, 1.2). Some are name collisions. Some can be real differences.

## Ingredients and tools

- `RECIPE_INGREDIENT_TYPE_N` is an Obj. `RECIPE_INGREDIENT_NUMBER_N` is the count for one action. A recipe has up to 10 ingredients. **Confirmed.**
- `RECIPE_INGREDIENT_n_MULTIPLE` replaces `TYPE_n` with a Struct. **Confirmed**: the Struct lists alternatives. Each alternative has its own `RECIPE_INGREDIENT_TYPE_N` and `RECIPE_INGREDIENT_NUMBER_N`, and any one of them satisfies the ingredient. Recipes refer to 433 of these Structs, with 2 to 8 alternatives each. Examples:

| Struct | Alternatives |
|---|---|
| `SMITHING_MULTI_INGREDIENT_STEEL_BAR` | 1 × `SMITHING_HOPPER_DUMMY` (`EXTRA_INFO` 20), or 1 × Steel bar |
| `SMITHING_MULTI_INGREDIENT_ELDER_RUNE_BAR16` | 16 from the hopper (`EXTRA_INFO` 29), or 16 × Elder rune bar |
| `SMITHING_MULTI_INGREDIENT_PHASMATITE` | Hopper, Phasmatite, or `SMITHING_OREBOX_DUMMY` (all `EXTRA_INFO` 14) |
| `NAILS_INGREDIENT_MULTI_4` | 4 of any of 7 nail types |
| `DIV_BOON_INGREDIENT_MULTI1` | 100 × Pale energy, or 100 × Flickering energy |
| `POF_ANIMAL_TROUGH_RAW_GREAT_WHITE_SHARK_MULTIPLE` | The item, or its noted form |

  - The number in the Struct name (`BAR2`, `BAR16`) is the count in each alternative.
  - `RECIPE_MULTI_NAME_OVERRIDE` and `RECIPE_MULTI_OBJECT_OVERRIDE` give the name and item to show, for example "Steel bar". This is what the wiki shows.
  - `SMITHING_HOPPER_DUMMY` and `SMITHING_OREBOX_DUMMY` mean bars in the forge storage and ores in an ore box. **Likely.** For them, `EXTRA_INFO` seems to be the metal: 14 Phasmatite, 20 Steel, 27 Necronium, 29 Elder rune, 44 Primal.
- `RECIPE_TOOL_TYPE_N` is an Obj that the player must hold, and that the recipe does not use up. Hammer on 2,086 objects, Saw on 614. **Likely.**
- `RECIPE_TOOL_XP_TYPE_N` is on 35 tools, for example Tinderbox (17, Firemaking) and Crystal pickaxe (13, Mining). **Unknown.**

### Invention materials

**Confirmed.** Invention recipes use `INVENT_MATERIAL_DUMMY` (Obj 36365) as an ingredient. `RECIPE_INGREDIENT_EXTRA_INFO_N` gives the material for ingredient `N`. The value is a key in the Enum `INVENT_MATERIAL_LIST_SORTED` (13170, 83 entries). The Enum gives a Struct for each material, for example 1 → `INVENT_MATERIAL_JUNK` (Struct 415) and 2 → `INVENT_MATERIAL_SIMPLE_PARTS` (416). The Enum agrees with all the IDs that we matched against the wiki:

| ID | Material | ID | Material |
|---|---|---|---|
| 1 | Junk | 22 | Padded parts |
| 2 | Simple parts | 105 | Heavy components |
| 3 | Base parts | 108 | Protective components |
| 7 | Spiritual parts | 110 | Precious components |
| 12 | Cover parts | 116 | Dextrous components |
| 15 | Crafted parts | | |
| 18 | Deflecting parts | | |

The Enum also gives 9 Tensile parts, 17 Flexible parts, 20 Spiked parts, 100 Precise components and 121 Subtle components.

The meaning of `EXTRA_INFO` depends on the dummy ingredient. `EXTRA_INFO` values 24 to 47 are not in the material Enum. They occur with `SMITHING_HOPPER_DUMMY` and `SMITHING_OREBOX_DUMMY`. See `_MULTIPLE` above.

## Output and timing

- `RECIPE_MAKE_STACK_SIZE` is the number of items that one action makes. Arrowheads 75, Cannonball 4, Dungeoneering runes 5. If it is not there, the count is 1. **Confirmed.**
- `RECIPE_CYCLES` is the time of one action in ticks. Common values: 5 (530 objects), 10 (383), 1 (148), 2 (142). This agrees with the wiki `ticks` field. **Confirmed.**
- `RECIPE_BATCH_SIZE` (8 objects) is on batch overload recipes and Primal extract. **Unknown**: perhaps the number of potions that one action makes.

## More than one recipe for an item

**Confirmed.** An Obj has one set of recipe params. But a dummy Obj can hold another recipe for a real item. `RECIPE_NON_DUMMY_OBJ` on the dummy points to the real item.

- 279 objects have `RECIPE_NON_DUMMY_OBJ`. They give other recipes for 196 items. 159 of these items also have their own recipe.
- Most dummies have `DUMMY` in the config name, but not all. For example `ARROW_SHAFT_OAK` gives Shaft from oak logs.
- The dummy recipes include methods that are not crafting skills:

| Real item | Dummy recipes |
|---|---|
| Shaft | 9: one for each log type |
| Snakeskin | 7: Canifis tanner, Temple Trekking hides |
| Leather, Hard leather | Canifis tanner (with coins), Lunar Tan Leather spell (Magic 83), Q200 version |
| Dragon leathers | Canifis tanner, Lunar Tan Leather spell, Wendlewick |
| Summoning scrolls | One for each pouch tier |
| Adrenaline renewal potion (4) | Improved recipes (+1, +2), an alternate recipe |

- Other dummy params: `RECIPE_NAME_OVERRIDE` (34 objects, for example "Antisanguine?"), `RECIPE_IMPROVEMENT_LEVEL` (36 objects: 0, 1 or 2 on Herblore "improved recipe" dummies).
- Some dummies with recipes have no `RECIPE_NON_DUMMY_OBJ`. Examples: `POT_OF_BUTTER_FROMCREAM_DUMMY`, `CHEESE_WHEEL_FROMBUTTER_DUMMY`, `DIV_DUMMY_BOON2`, `DINO_GAME_TRAP_BUILT_RECIPE_DUMMY`. **Unknown**: how to find their real item.

## What the params do not give

The wiki has methods that the params do not have:

- **Spells.** Molten glass has one game recipe: Crafting, sand and soda ash. The wiki has 7 methods, including Superglass Make. The game stores the Lunar Tan Leather spell as a dummy recipe, but it does not store Superglass Make, Plank Make or Humidify.
- **Machines and NPCs.** The wiki lists planks from a sawmill operator, a plank maker machine and a high-capacity plank maker. The game has only the Construction recipe.
- **Altars.** Runecrafting at an altar is not a recipe. Only Dungeoneering runes have recipes.
- **Items with no game recipe.** 6,323 wiki rows are for items with no game recipe. 3,380 of these rows have no skill: shops, rewards, NPC services, cosmetic overrides. The rows with a skill are mostly Invention augmentations, furniture workbench items, Creation kiln potions, compost bins, the Soul forge and more altars.

So the params cannot give every source of an item. If the plugin must know every source, it still needs the wiki or hand-written data for the rest.

### Spells

**Confirmed.** Each spell is a Struct, for example `MAGIC_SUPERGLASS` (14845), `MAGIC_PLANK_MAKE` (14859), `MAGIC_HUMIDIFY` (14830) and `MAGIC_STRING_JEWELLERY` (14851). The Struct gives:

- The Magic level: `COMBATV2_ABILITY_LEVEL_REQ`, for example 77 for Superglass Make.
- The rune costs: `COMBATV2_REQUIRES_<RUNE>_RUNES`, for example 10 air, 6 fire and 2 astral for Superglass Make.
- The spellbook (`COMBATV2_WHICH_SPELLBOOK`), and members only (`COMBATV2_ABILITY_IS_MEMBERS`).
- The unlock as text: `COMBATV2_ABILITY_UNLOCK_DESCRIPTION`, for example "Unlocked by completing the quest 'Dream Mentor'."

The Struct does not give the items that the spell uses or makes. For example, nothing says that Superglass Make turns sand and soda ash into molten glass. Only `COMBATV2_REQUIRES_OTHER_ITEMS = 1` (Plank Make) says that the spell needs more items.

### Machines

**Confirmed.** Enums give the input and output of some machines:

| Enum | Entries | Example |
|---|---|---|
| `INVENT_MACHINE_SAWMILL` (13179) | 11 | Oak logs → Oak plank |
| `INVENT_MACHINE_TANNER` (13177) | 21 | Red dragonhide → Red dragon leather; noted hides also work |
| `INVENT_MACHINE_UNF` (13178) | 24 | Unfinished potions |
| `INVENT_MACHINE_SMELTER` (13180) | 6 | Bars, with overrides in 13181 and 13182 |
| `CONSTRUCTION_HOUSING_SAWMILL_SIMPLE_LOGS_TO_PLANKS` (13148) | 11 | Planks |
| `PLAYER_FORT_SAWMILL_LOGS_TO_PLANKS` (16796) | 22 | Planks |

`INVENT_MACHINE_DBROWS` (13175) and `INVENT_MACHINE_HOTSPOT_DBROWS` (13176) point to DBRows with more machine data. The probe does not export DBRows.

These Enums give the items, but not the speed, the cost or the XP. A plugin that uses them would need more data from somewhere.

### Other links between items

Other params link one item to another, but have no recipe data (no skill, no ingredient count):

| Param | Objects |
|---|---|
| `PVP_TRADEABLE_VERSION` | 3,215 |
| `ITEM_DEGRADE_NEXTSTATE` | 2,806 |
| `INVENT_BASE_OBJECT` | 1,483 |
| `SMITHING_NEXT_UPGRADE` / `SMITHING_BASE_VERSION` | 1,356 / 1,187 |
| `INVENT_AUGMENTED_VERSION` | 1,121 |
| `ITEM_DEGRADE_FIXEDSTATE` | 1,016 |
| `INVENT_CHARGED_VERSION` | 754 |
| `POH_COST1_OBJ` to `POH_COST4_OBJ` | 576, 357, 95, 23 |
| `DYE_RESULT_*`, `TRAIL14_DYE_RESULT_*` | 230 each |
| `SMITHING_MASTERWORK_BREAKDOWN` | 147 |
| `CRAFTING_PROGRESS_PRODUCT` | 60 |
| `MAGIC_ALCH_DERIVED_ITEM` | 70 |

These could explain some of the "no game recipe" rows, for example Invention augmentation and dyes. We did not test this.

## Probe results in the game client

### Runtime scan

`probes/recipe-scan-timer-probe` scanned all Obj IDs 0 to 64,356. In each client Logic tick (50 each second), it read 250 Objs with `HasParam` and `GetParamValue` for 4 params.

- It found 63,935 valid Objs, 7,422 Objs with a recipe, 279 dummy recipes and 7,212 items with a recipe.
- It took 5.14 s. The probe set this time: 64,357 ÷ 250 ÷ 50 = 5.1 s. The real cost is lower.
- The longest frame was 0.030 s, against 0.014 s with no scan. The longest frame while reading every param of 50 Objs each tick was 0.026 s.
- `os.clock` is not available, so the probe could not measure the CPU time of each part.

So the plugin can build the item → recipes index at runtime in a few seconds, in parts, with little effect on the frame rate. A larger part each tick is probably possible.

`GetParamValue` on some params logs a client error and gives no value: `Failed to convert a config value to a plugin value, invalid ValueType (16)` (AREA) or `(4294967295)` (-1). `pcall` does not catch it. Read only the params that the plugin needs.

### Production recorder

`probes/production-recorder-probe` recorded a session of baking cakes (Uncooked cake → Cake):

- 4 actions, 4 server ticks apart. The Action time of Cake is 4 ticks. Cake has no `RECIPE_CYCLES`, so the params do not give this.
- The cake tin came back (the player saw it). The recipe params do not list it. This confirms that other Outputs must come from another source.
- Each action gave 189 XP in `SkillTransmit`. The recipe gives `RECIPE_XP_VALUE_1 = 1800`, which is 180 XP. So `SkillTransmit` gives whole XP, and a 5% bonus was active.
- `SkillTransmit.skill` gave 7, the `SkillType` value of Cooking. The recipe params use 16 for Cooking. The two numbering systems are different.

The first version of the probe did not log item changes, because of a bug in the probe (`Inventory.Find` gives one `Inv` in practice, not a list).

### DBTables and DBRows

The probe exported 264 DBTables. A DBTable gives only the value types of its columns, not data. Tables that can be important for recipes:

| ID | DBTable | Columns |
|---|---|---|
| 22 | `INVENT_MACHINE_TABLE` | 24 |
| 23 | `INVENT_MACHINE_HOTSPOTS` | 6 |
| 5 | `INVENT_BLUEPRINT_TABLE` | 17 |
| 4 | `INVENT_MATERIAL_TABLE` | 13 |
| 378 | `HERBLORE_POTION` | 3 |
| 293 | `RUNECRAFTING_ALTARS` | 2 |
| 235 | `NECRO_RITUAL_RECIPE` | 18 |
| 78 | `MC_CORE_RECIPE` | 6 |
| 180 | `SKILL_TRAINING_SITE` | 3 |

Other tables include `ARCH_RESTORATION`, `CONSTRUCTION_HOUSE_FURNITURE` and `ITEM_TABLE`.

The export got no DBRows. The probe treated each DBRow as missing. The cause is not known yet. A fixed probe logs the reason.

## Differences from the wiki to check in game

From the detailed pass on 207 items:

| Item | Field | Game | Wiki |
|---|---|---|---|
| Iron dart tip | Smithing level | 10 | 20 |
| Bronze spear | Smithing level | 1 | 5 |
| Swamp Titan scroll | Summoning level | 85 | 75 |
| Asgarnian ale (m) | Cooking level | 24 | 28 |
| Orange seedling | Farming XP | 1.0 | 1.2 |
| Spirit Mosquito scroll | Summoning XP | 0.5 | 0.2 |
| Holy water | Golden bowl count | 1 | 0.1 |

Ales: the wiki says one brewing vat makes 8 glasses and needs 8 beer glasses. The game recipe makes 1 and lists no glass. **Unknown**: how the plugin should model brewing.

## Data quirks

- `RECIPE_INGREDIENT_NUMBER_N = 0` occurs on Dungeoneering summoning pouches (for example 17935, Cub bloodrager pouch). These pouches also list Bones twice.
- Mithril hatchet (1355) has `RECIPE_INGREDIENT_NUMBER_2` but no `TYPE_2`.
- The exporter marks some refs `ancestor-reference`. They are on items without recipes, for example clue scrolls, and point at the item itself. This comes from the exporter, not from the recipe data.

## Unknown params

| Param | Objects | Values | Seen on |
|---|---|---|---|
| `RECIPE_OVERRIDE_STACK_MAKE_LIMIT` | 779 | 1, 1000, 60, 50, others | Dragon sq shield, farm animal feed |
| `RECIPE_SLOTS_NEEDED` | 672 | 0, -1, 4, 5 | Bronze bar, fort buildings |
| `RECIPE_IGNORE_BOB` | 343 | `true` | Bane arrows, farm seeds |
| `RECIPE_SHOW_CONDITION` | 324 | `true` | Archaeology |
| `RECIPE_EXTRA_INV_SPACE_REQUIRED` | 274 | 1 | Invention |
| `RECIPE_HIDE_WHEN_LOCKED` | 261 | 1 | Invention |
| `RECIPE_DEFAULT_QUANTITY` | 215 | 1 | Scrimshaws, blueprints |
| `RECIPE_CAN_BE_BOOSTED` | 197 | `false` | - |
| `RECIPE_INGREDIENT_n_SCALE_STACK` | 149 | `false` | - |
| `RECIPE_INGREDIENT_EXTRA_AMOUNT_CHECK_N` | 110 | `true` | Bane arrows, Ground mud runes |
| `RECIPE_MESSAGE` | 58 | Text, for example "You chisel some essence…" | - |
| `RECIPE_NO_MIXMATCH` | 55 | `true` | Bronze bar, divine bubbles |
| `ELFCITY_RECIPE_UNLOCK_COST` | 38 | 100,000 to 1,000,000 | Prifddinas combination potions |
| `RECIPE_USE_GAMELOGEVENT` | 18 | 1 | Boss weapons |
| `RECIPE_FULLY_CHARGED` | 12 | 1 | Refined anima core armour |
| `RECIPE_ADD_TO_INV` | 12 | `false` | Deathwarden armour |
| `RECIPE_ADD_TO_BANK` | 6 | `true` | Wilderness essence mine |
| `RECIPE_IGNORE_WICKED_POUCH`, `_RUNESTAFF`, `_RUNEPOUCH` | 6, 3, 1 | `true` | Ground mud runes |
| `RECIPE_USE_OBJ_OVERRIDE`, `RECIPE_GRAPHIC`, `RECIPE_CONSERVE_INFO_1` | 1 each | - | - |

Some names suggest a meaning. For example, `RECIPE_IGNORE_RUNEPOUCH` perhaps stops the recipe from using runes in a rune pouch. We did not test these guesses.

The Param defaults explain some values. For example, `RECIPE_CAN_BE_BOOSTED` defaults to `true`, so the 197 objects with `false` are the exceptions. `RECIPE_INGREDIENT_n_SCALE_STACK` and `RECIPE_ADD_TO_INV` also default to `true`, and only `false` appears on items.

## Next steps

1. Record in `client-behaviour.md` what the probes showed: an Obj `params` table keyed by name, Struct `paramValues`, and that `FromID` is not always a plain Lua function.
2. Find what type 62, 64 and 67 values and show conditions refer to. Type 62 is probably a varbit or a DBRow. Find whether the API can read either.
3. Export DBRows if the API allows it: `INVENT_CLIENT_RECIPE` and `INVENT_MACHINE_DBROWS` point to them.
4. Check the levels and XP in "Differences from the wiki to check in game".
5. Decide which sources the plugin must know, and if the wiki must give the sources that the params do not have (spells, NPCs, altars).
6. Write the ADR that replaces ADR 0016.
