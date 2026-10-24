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
| 61 | 155 | Quest complete. The value is a quest ID. | Likely |
| 62 | 2,646 | An unlock. The value is an ID. | Unknown |
| 63 | 316 | Invention discovery. The value is a discovery index. | Likely |
| 64 | 297 | A facility or station, perhaps. | Unknown |
| 67 | 123 | No value. Only on house furniture. | Unknown |

### Type 61

Evidence that the value is a quest ID:

- 34 Cannonball: Dwarf Cannon. 8 Blurite: The Knight's Sword. 20 Cooked chompy: Big Chompy Bird Hunting. 108 Dart tips: The Tourist Trap. 198 Bacon: Bringing Home the Bacon. 143 Spirit shields: Summer's End. 103 Spears: Tai Bwo Wannai Trio.
- Some items also have `USE_REQUIRES_QUEST1` or `WEAR_REQUIRES_QUEST1`. On 21 of 50 such items, the value is the same as the type 61 value. For example, Cannonball has `USE_REQUIRES_QUEST1 = 34`. On the other 29 items the values are different. To wear an item can need a different quest.

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

Our guess: the value refers to a separate unlock condition, perhaps a var, a varbit or a Struct row. The value alone does not tell us the condition.

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
- If `RECIPE_XP_SCALE_STACK_N` is `false`, the value is for one output item. If it is `true` or not there, the value is for one action. **Likely.** Evidence: on the 346 compared recipes with the flag `false` (mostly ammunition), the XP agrees with the wiki per item, not per action. Bolts: 1.5 XP each, 10 bolts for each action, and the wiki gives 15 XP for 10 bolts.
- The wiki often gives XP for a batch, for example darts ×10 or Mechanised chinchompa ×50. Per output item, the XP agrees in 5,568 cases. **Confirmed.**
- A recipe has up to 2 XP entries. The two entries can name the same skill. Then the total is the sum. For example, Asgarnian ale is 9 + 248 = 25.7 XP, and the wiki gives 25.7. **Likely**: perhaps one entry is a step.
- The second entry can be a different skill. For example, Mining accumulator gives 660 Invention XP and 150 Crafting XP. **Confirmed.**
- 667 objects have `RECIPE_XP_TYPE_1` but no value. 367 objects have the value 0, of which 325 are Farming. `RECIPE_XP_GIVE_NO_XP = 1` is on 43 player-owned fort buildings.
- Normal runes (for example Fire rune, 554) have only `RECIPE_XP_TYPE_1 = 12`, with no value and no recipe. Runecrafting at an altar is not a recipe.
- About 150 compared recipes have no stack and still have different XP. Examples: Ruby amulet (game 85, wiki 4), Pat of butter (40.5, 22.5), Papaya seedling (1.0, 1.2). Some are name collisions. Some can be real differences.

## Ingredients and tools

- `RECIPE_INGREDIENT_TYPE_N` is an Obj. `RECIPE_INGREDIENT_NUMBER_N` is the count for one action. A recipe has up to 10 ingredients. **Confirmed.**
- `RECIPE_INGREDIENT_n_MULTIPLE` replaces `TYPE_n` with a Struct. The export has 433 different Structs. Examples: `SMITHING_MULTI_INGREDIENT_BRONZE_BAR`, `_BRONZE_BAR2`, `_BRONZE_BAR4`, `SMITHING_MULTI_INGREDIENT_COPPER`, `ARROWS_FEATHER_INGREDIENT_MULTI`, `VIAL_WATER_INGREDIENT_MULTI`. The wiki shows the plain item, for example Bronze bar. **Unknown**: what the Struct holds. Perhaps the alternatives and the count. The export does not expand Structs.
- `RECIPE_TOOL_TYPE_N` is an Obj that the player must hold, and that the recipe does not use up. Hammer on 2,086 objects, Saw on 614. **Likely.**
- `RECIPE_TOOL_XP_TYPE_N` is on 35 tools, for example Tinderbox (17, Firemaking) and Crystal pickaxe (13, Mining). **Unknown.**

### Invention materials

**Likely.** Invention recipes use `INVENT_MATERIAL_DUMMY` (Obj 36365) as an ingredient. `RECIPE_INGREDIENT_EXTRA_INFO_N` gives the material for ingredient `N`. The IDs agree across all compared recipes:

| ID | Material | ID | Material |
|---|---|---|---|
| 1 | Junk | 22 | Padded parts |
| 2 | Simple parts | 105 | Heavy components |
| 3 | Base parts | 108 | Protective components |
| 7 | Spiritual parts | 110 | Precious components |
| 12 | Cover parts | 116 | Dextrous components |
| 15 | Crafted parts | | |
| 18 | Deflecting parts | | |

The full export has 77 different `EXTRA_INFO` values. The table gives only the ones that we matched.

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

## Next steps

1. Probe `params` and `GetParamValue` on an Obj. Record the result in `client-behaviour.md`.
2. Probe a Struct from `RECIPE_INGREDIENT_n_MULTIPLE`, for example `SMITHING_MULTI_INGREDIENT_BRONZE_BAR2`. Find its params.
3. Read quest configs for the type 61 values and check the quest names.
4. Find what type 62, 64 and 67 values and show conditions refer to.
5. Check the levels and XP in "Differences from the wiki to check in game".
6. Decide which sources the plugin must know, and if the wiki must give the sources that the params do not have.
7. Write the ADR that replaces ADR 0016.
