# The plugin contains hand-written recipe data

Amended by ADR 0007, ADR 0013 and ADR 0016.

The game API does not describe recipes. The recipe data must come from another source.

We put a hand-written Lua table in `resources/`. We write it from the public RuneScape Wiki. Then we check it in-game. We do not get recipes from the wiki at runtime. We do not read undocumented `DBRow` tables.

This choice has these advantages:

- The plugin works offline.
- The plugin does not need the `httpAccess` permission.
- The plugin does not parse wiki markup in Lua.
- The plugin uses only documented APIs.

The disadvantage is that we must update the table by hand when Jagex adds or changes recipes.

## Considered Options

- **Get recipes from the wiki at runtime:** rejected for now. Examine this option again if someone publishes a maintained wiki-data library for plugins.
- **Read undocumented `DBRow` tables:** rejected. No document says which tables contain recipes. Possibly no table contains them. The project uses only documented APIs.

## Consequences

The data refers to items by config name. The plugin checks these names when it loads. Config names are not always the same as display names. For example, the config name of "Clean lantadyme" is `LANTADYME`. Confirm each name in-game. Do not copy it from the wiki.
