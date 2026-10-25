# The recipe data comes from the game at runtime

Supersedes ADR 0016.
Amends ADR 0013.

ADR 0016 generates `data/recipes.lua` from the wiki Bucket at development time. The game client has better data. Each Obj config has `RECIPE_*` params that give its Recipe (`docs/recipe-params.md`). The game also gives each config name, so the ID probe of #64 is not necessary.

The plugin now builds the Recipes at runtime from the `RECIPE_*` params of each Obj. It scans all Objs in parts, over many frames. `probes/recipe-scan-timer-probe` did a full scan in about 5 s, with little effect on the frame rate.

## Mapping

`docs/recipe-params.md` gives the meaning of each param. The scan maps them to the input format of `Plan.calculate`:

- `output`: `RECIPE_MAKE_STACK_SIZE`. The default is 1.
- `inputs`: `RECIPE_INGREDIENT_TYPE_N` and `RECIPE_INGREDIENT_NUMBER_N`, up to 18. When `RECIPE_INGREDIENT_n_SCALE_STACK` is false, the count is for each output item, so the scan multiplies it by the stack size. `RECIPE_INGREDIENT_n_MULTIPLE` points to a Struct of alternatives.
- `skills`: requirement types 1 to 29. They follow the order of the stats interface, not `SkillType`.
- `unlocks`: type 61 is a quest (`QUEST_ID`). Type 63 is an Invention blueprint (`INVENT_BLUEPRINT_TABLE`). Types 62, 64 and 67 get names from the hand-written `data/unlocks.lua`.
- `actionTime`: `RECIPE_CYCLES`, in server ticks.
- More Recipes for an item: dummy Objs with `RECIPE_NON_DUMMY_OBJ`.
- Dose pools: the `POTION_STRUCT` param of each potion.

## Values that the game does not give

Decided in #24 on 2026-10-25:

- **Action limit:** optional. A Recipe without it uses only the Inventory space for its Batch hint. When all Inputs are stackable, the Step has no Batch hint.
- **Action time:** `nil` when the Recipe has no `RECIPE_CYCLES`. Only about 1,460 of 7,422 Recipes have it.
- **Other Outputs:** empty. #90 finds a source. For example, Cake gives back a Cake tin, but its params do not say so.

## Consequences

- The plugin uses no wiki data. The wiki snapshot, the overrides file, the weekly wiki check and the CC BY-NC-SA terms of ADR 0016 do not apply.
- A game update changes the Recipes with no change to the plugin.
- The Recipes are not ready at once when the plugin loads. The UI must handle a scan that has not finished.
- Some ways to get an item are not Recipes in the game, for example Superglass Make and Runecrafting at an altar (`docs/recipe-params.md`). The plan cannot use them.
- `api-signatures.md` documents `GetParamValue(param : ParamType)`, not a `params` table with names as keys. The scan uses only documented APIs, or APIs that a probe confirmed in `docs/client-behaviour.md`.

## Considered Options

- **Generate the data from the wiki Bucket (ADR 0016):** rejected. The game has the data, and the wiki can be wrong.
- **Action limit from `RECIPE_OVERRIDE_STACK_MAKE_LIMIT`, else 28:** rejected in #24. Only 779 Objs have the param.
- **A fixed default Action time:** rejected in #24.
