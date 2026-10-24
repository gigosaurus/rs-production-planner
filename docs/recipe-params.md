# Recipe params in Obj configs

Findings from 2026-10-24. These are not yet verified by a probe. Each finding gives a confidence:

- **Confirmed**: many items agree with the wiki, with no contradiction.
- **Likely**: the data fits, but a probe must check it.
- **Unknown**: we have a guess or nothing.

## Decision

The plugin reads recipe data at runtime from `config.Obj` params. This replaces the wiki Bucket pipeline of ADR 0016. An ADR must record this decision.

## Source

- `config.Obj.FromID(id)` gives a table with `params`. The keys are param config names, for example `RECIPE_XP_VALUE_1`.
- A param that refers to a config gives a userdata, for example an Obj or a Struct.
- `api-signatures.md` documents `GetParamValue(param : ParamType)`. It does not document a `params` table with names as keys. A probe must confirm that table and add it to `client-behaviour.md`.

## Method

1. A plugin exported every Obj to `objects/objects.sqlite3`. The export was not complete: 36,650 objects, IDs 0 to 36,918.
2. Scripts counted each `RECIPE_*` key and its values.
3. A script took 207 items: a random sample and items with rare params. It got their rows from the wiki `recipe` bucket (279 rows) and compared levels, XP, ingredients and output counts.

The wiki can be wrong. A difference is not proof that the game data is correct.

## Summary of the comparison

| Check | Same | Different |
|---|---|---|
| Level | 171 | 5 |
| XP | 164 | 18 |
| Output count | 166 | 10 |
| Ingredient count | 225 | 15 |

The wiki has no recipe for 31 of the items. Most differences have one cause: the wiki gives a batch, and the game gives one unit.

## Param counts

From the partial export.

| Param | Objects | Highest `N` |
|---|---|---|
| `RECIPE_REQUIREMENT_TYPE_N` / `_VALUE_N` | 2,842 | 4 |
| `RECIPE_INGREDIENT_NUMBER_N` | 2,681 | 8 |
| `RECIPE_INGREDIENT_TYPE_N` | 2,659 | 8 |
| `RECIPE_XP_TYPE_N` / `_VALUE_N` | 2,650 | 2 |
| `RECIPE_TOOL_TYPE_N` | 874 | 2 |
| `RECIPE_MAKE_STACK_SIZE` | 404 | - |
| `RECIPE_IS_MEMBERS_ONLY` | 337 | - |
| `RECIPE_INGREDIENT_n_MULTIPLE` (n = 1, 2, 4) | 367 | - |
| `RECIPE_CAN_BE_BOOSTED` | 155 | - |
| `RECIPE_NON_DUMMY_OBJ` | 107 | - |
| `RECIPE_CYCLES` | 60 | - |

## Skill codes

**Confirmed.** `RECIPE_REQUIREMENT_TYPE_N` and `RECIPE_XP_TYPE_N` use the same codes for skills. The codes are not the `SkillType` enum. They follow the order of the RS3 stats interface, starting at 1:

| Code | Skill | Code | Skill | Code | Skill |
|---|---|---|---|---|---|
| 1 | Attack | 11 | Crafting | 21 | Farming |
| 2 | Strength | 12 | Runecrafting | 22 | Construction |
| 3 | Ranged | 13 | Mining | 23 | Hunter |
| 4 | Magic | 14 | Smithing | 24 | Summoning |
| 5 | Defence | 15 | Fishing | 25 | Dungeoneering |
| 6 | Constitution | 16 | Cooking | 26 | Divination |
| 7 | Prayer | 17 | Firemaking | 27 | Invention |
| 8 | Agility | 18 | Woodcutting | 28 | Archaeology |
| 9 | Herblore | 19 | Fletching | 29 | Necromancy |
| 10 | Thieving | 20 | Slayer | | |

The export shows codes 4, 6, 7, 9, 11 to 19, 21, 22, 24, 26 and 27. The other codes follow from the order.

- Code 6 (Constitution) occurs only on portents, as a second requirement. **Likely.**
- The data does not show codes 23, 25, 28 and 29. **Likely.**

## Requirements

`RECIPE_REQUIREMENT_TYPE_N` gives the kind. `RECIPE_REQUIREMENT_VALUE_N` gives the value. A recipe has up to 4 requirements.

| Type | Meaning | Confidence | Evidence |
|---|---|---|---|
| 1 to 29 | Skill level. The value is the level. | Confirmed | 171 of 176 levels agree with the wiki. |
| 61 | Quest complete. The value is a quest ID. | Likely | 34 Cannonball: Dwarf Cannon. 8 Blurite: The Knight's Sword. 20 Cooked chompy: Big Chompy Bird Hunting. 108 Dart tips: The Tourist Trap. 198 Bacon: Bringing Home the Bacon. 143 Spirit shields: Summer's End. 103 Spears: Tai Bwo Wannai Trio. |
| 62 | An unlock. The value is an ID. | Unknown | See below. |
| 63 | Invention discovery. The value is a discovery index. | Likely | Each Invention item has its own value. 70 = Augmented armour, and the wiki `discovery` field agrees. |
| 64 | Unknown | Unknown | Only on the 4 planks, always value 17. Perhaps the sawmill. |

### Type 62

836 requirements. An item can have two of them. For example, Bronze spear has 62 = 8 and 62 = 190. The wiki shows different things for different values:

| Value | Items | Wiki |
|---|---|---|
| 5 | 342 Dungeoneering items (`RAND_*` configs) | Daemonheim |
| 187 | 161 smithing items, for example arrowheads | Anvil |
| 189 | Dragon sq shield, spirit shields | Anvil |
| 190 | Spears | Barbarian anvil |
| 7 | Brutal arrows | Partial completion of Zogre Flesh Eaters |
| 27, 28 | Clean sito foil, Clean volencia moss | Partial completion of Jungle Potion |
| 30 | Barbarian mixes | Barbarian Herblore training |
| 35 | Leathers | Tanner |
| 36 | Bane arrows | Partial completion of Ritual of the Mahjarrat |
| 87 | Divine rocks | - |
| 63, 64, 65, 70 | One for each Tetsu or Seasinger item | - |

Our guess: the value refers to a separate unlock condition, perhaps a var, a varbit or a Struct row. The value alone does not tell us the condition.

## XP

- `RECIPE_XP_VALUE_N` is XP × 10. Clean lantadyme is 131, which is 13.1 XP. **Confirmed.**
- The value is for one unit of output. The wiki often gives a batch: darts and bolts ×10, brutal arrows ×6, Mechanised chinchompa ×50, Green charm ×10. **Confirmed.**
- A recipe has up to 2 XP entries. The two entries can name the same skill. Then the total is the sum. For example, Asgarnian ale is 9 + 248 = 25.7 XP, and the wiki gives 25.7. **Likely**: perhaps one entry is a step, for example adding the hops.
- The second entry can be a different skill. Invention items often give Crafting XP, for example Mining accumulator gives 660 Invention and 150 Crafting. **Confirmed.**
- 24 objects have XP but no requirement. 216 objects have requirements but no XP.
- Normal runes (for example Fire rune, 554) have only `RECIPE_XP_TYPE_1 = 12`, with no value and no recipe. Runecrafting at an altar is not stored as a recipe. Only the Dungeoneering runes have full recipes.

## Ingredients

- `RECIPE_INGREDIENT_TYPE_N` is an Obj. `RECIPE_INGREDIENT_NUMBER_N` is the count for one action. A recipe has up to 8 ingredients. **Confirmed.**
- `RECIPE_INGREDIENT_n_MULTIPLE` replaces `TYPE_n` with a Struct. **Likely**: the Struct holds the alternatives and the count. Examples: `SMITHING_MULTI_INGREDIENT_BRONZE_BAR`, `SMITHING_MULTI_INGREDIENT_BRONZE_BAR2`, `SMITHING_MULTI_INGREDIENT_BRONZE_BAR4`, `ARROWS_FEATHER_INGREDIENT_MULTI`, `VIAL_WATER_INGREDIENT_MULTI`, `PLANTPOT_COMPOST_MULTI`. The export has 88 different Structs. In each case the wiki shows the plain item, for example Bronze bar. **Unknown**: what the Struct contains, and if the number in the name (`BAR2`, `BAR4`) is the bar count.
- `RECIPE_TOOL_TYPE_N` is an Obj that the player must hold, for example Hammer, Chisel or Ammo mould. It is not used up. **Likely.**

### Invention materials

**Likely.** Invention recipes use `INVENT_MATERIAL_DUMMY` (Obj 36365) as the ingredient. `RECIPE_INGREDIENT_EXTRA_INFO_N` gives the material for ingredient `N`. The IDs agree across all compared recipes:

| ID | Material | ID | Material |
|---|---|---|---|
| 1 | Junk | 22 | Padded parts |
| 2 | Simple parts | 105 | Heavy components |
| 3 | Base parts | 108 | Protective components |
| 7 | Spiritual parts | 110 | Precious components |
| 12 | Cover parts | 116 | Dextrous components |
| 15 | Crafted parts | | |
| 18 | Deflecting parts | | |

## Output and timing

- `RECIPE_MAKE_STACK_SIZE` is the number of items that one action makes. Arrowheads 75, Cannonball 4, Dungeoneering runes 5. If it is not there, the count is 1. **Confirmed.**
- `RECIPE_CYCLES` is the time of one action in ticks. Planks 2, Invention items 3 or 5. This agrees with the wiki `ticks` field. **Confirmed.** Only 60 objects have it.

## One recipe for each item

**Confirmed.** An Obj has one set of recipe params, so it has one recipe. The wiki has more methods for some items:

- Planks: 6 methods on the wiki. The game has one: Construction, 1 log, 2 ticks, which matches the wiki's "using sawmill".
- Molten glass: 7 methods on the wiki.
- Raw trout and other fish: the game recipe is the Divination transmutation. It is not a Fishing recipe. Gathered items have no recipe.

The plugin cannot learn other methods from the params.

## Differences from the wiki

### Batch sizes

The wiki gives these values for a batch. The game gives them for one unit. These are not errors.

| Item | Game | Wiki |
|---|---|---|
| Adamant dart, XP | 15 | 150 |
| Bronze brutal, XP | 1.4 | 8.4 |
| Mechanised chinchompa, XP | 143 | 7,150 |
| Green charm, XP | 13.4 | 134 |

### Ales

The wiki says one brewing vat makes 8 glasses and needs 8 beer glasses. The game recipe makes 1 and lists no glass. **Unknown**: how the plugin should model brewing.

### Levels and XP to check in game

| Item | Field | Game | Wiki |
|---|---|---|---|
| Iron dart tip | Smithing level | 10 | 20 |
| Bronze spear | Smithing level | 1 | 5 |
| Swamp Titan scroll | Summoning level | 85 | 75 |
| Asgarnian ale (m) | Cooking level | 24 | 28 |
| Orange seedling | Farming XP | 1.0 | 1.2 |
| Spirit Mosquito scroll | Summoning XP | 0.5 | 0.2 |
| Holy water | Golden bowl count | 1 | 0.1 |

### No wiki recipe

The wiki has no recipe for 31 sampled items with game recipes. Most are unfinished summoning pouches, for example `Granite crab pouch(u)`, 6-dose potions, for example `Supreme magic potion (6)`, and spells, for example `Lvl-1 enchant`.

## Data quirks

- `RECIPE_INGREDIENT_NUMBER_N = 0` occurs only on Dungeoneering summoning pouches (for example 17935, Cub bloodrager pouch). These pouches also list Bones twice.
- Mithril hatchet (1355) has `RECIPE_INGREDIENT_NUMBER_2` but no `TYPE_2`.
- The exporter marks some refs `ancestor-reference`. All 128 are on items without recipes, for example clue scrolls, and point at the item itself. This comes from the exporter, not from the recipe data.

## Unknown params

We do not know what these params do:

| Param | Objects | Values |
|---|---|---|
| `RECIPE_NON_DUMMY_OBJ` | 107 | An Obj |
| `RECIPE_INGREDIENT_EXTRA_AMOUNT_CHECK_N` | 51 | `true` |
| `RECIPE_OVERRIDE_STACK_MAKE_LIMIT` | 78 | 1, 50, 60 |
| `RECIPE_DEFAULT_QUANTITY` | 74 | 1 |
| `RECIPE_XP_SCALE_STACK_N` | 99 | `true` or `false` |
| `RECIPE_INGREDIENT_n_SCALE_STACK` | 152 | `false` |
| `RECIPE_EXTRA_INV_SPACE_REQUIRED` | 90 | 1 |
| `RECIPE_SLOTS_NEEDED` | 34 | 0, -1 |
| `RECIPE_NO_MIXMATCH` | 33 | `true` |
| `RECIPE_HIDE_WHEN_LOCKED` | 30 | 1 |
| `RECIPE_TOOL_XP_TYPE_N` | 29 | Skill codes |
| `RECIPE_SHOW_CONDITION` | 13 | `true` |
| `RECIPE_IGNORE_BOB`, `_RUNEPOUCH`, `_RUNESTAFF`, `_WICKED_POUCH` | 1 to 8 | `true` |
| `ELFCITY_RECIPE_UNLOCK_COST` | 26 | 100,000 to 500,000 |

Some names suggest a meaning. For example, `RECIPE_IGNORE_RUNEPOUCH` perhaps stops the recipe from using runes in a rune pouch. We did not test these guesses.

## Next steps

1. Probe `params` and `GetParamValue` on an Obj. Record the result in `client-behaviour.md`.
2. Probe a Struct from `RECIPE_INGREDIENT_n_MULTIPLE`, for example `SMITHING_MULTI_INGREDIENT_BRONZE_BAR2`. Find its params.
3. Read quest configs for the type 61 values and check the quest names.
4. Find what type 62 values refer to.
5. Check the levels and XP in "Levels and XP to check in game".
6. Run the analysis again when the export is complete.
7. Write the ADR that replaces ADR 0016.
