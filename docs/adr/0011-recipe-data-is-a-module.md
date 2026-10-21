# The recipe data is a Lua module in `data/`, not a resource

Amends ADR 0001.

ADR 0001 puts the recipe data in `resources/`. The API reference says that plugin resources are only `.png` and `.ogg` files. We tested this in-game on 2026-10-21 with `probes/recipe-data-probe`:

- `require("resources/recipes")` loads a Lua table from `resources/`.
- `Plugin.resources` does not list the `.lua` file.

`resources/` works only through `require`. The reference page does not describe this. We put the recipe data in `data/recipes.lua`. `require` loads it as it loads all other modules. The module returns a table.

## Consequences

`resources/` contains only sprites and audio, as the reference page says.

The plugin checks each config name with `config.Obj[name]`. A name that does not exist gives `nil`. It does not raise an error. `config.Obj` also contains functions, for example `FromID`. A name is valid only if `config.Obj[name]` is not `nil` and is not a function.

Config names are case-sensitive: `config.Obj.LANTADYME` is an item, and `config.Obj.lantadyme` is `nil`.
