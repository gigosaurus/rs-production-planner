# The recipe data is a Lua module in `data/`, not a resource

Amends ADR 0001.
Amended by ADR 0016.
Amended by ADR 0017 (recipe data from the game at runtime).

ADR 0001 puts the recipe data in `resources/`. The API reference says that plugin resources are only `.png` and `.ogg` files. We tested this in-game on 2026-10-21 with `probes/recipe-data-probe`:

- `require("resources/recipes")` loads a Lua table from `resources/`.
- `Plugin.resources` does not list the `.lua` file. It lists a `.png` file in the same folder.

`resources/` works only through `require`. The reference page does not describe this. We put the recipe data in `data/recipes.lua`. `require` loads it as it loads all other modules. The module returns a table.

We do not put the recipe data in `plan/`. `plan/` contains logic. The recipe data is hand-written from the wiki. It changes when Jagex adds or changes recipes, not when the logic changes. It also gets a different review: each name and amount is compared with the game. A separate folder can also get its own luacheck rules if the long table lines need them.

## Consequences

`resources/` contains only sprites and audio, as the reference page says.

CI runs luacheck and stylua on `data/`, as it does on `plan/` and `tests/`. `data/.gitkeep` keeps the folder until `data/recipes.lua` exists, because both tools fail on a folder that does not exist.

The plugin checks each config name with `config.Obj[name]`. A name that does not exist gives `nil`. It does not raise an error. `config.Obj` also contains values that are not items, for example `FromID`. `config.Obj.FromID` is a userdata, as an item is. Indexing it raises an error. A value that is not `nil` does not prove that the name is an item. A name is valid only if `config.Obj[name].configName` is equal to the name. Read `configName` in `pcall`.

Config names are case-sensitive: `config.Obj.LANTADYME` is an item. `config.Obj.lantadyme` and `config.Obj.Lantadyme` are `nil`.
