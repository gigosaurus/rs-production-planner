# Recipe data tools

These scripts make the recipe data at development time (ADR 0015). The plugin does not contain them. They use Python 3.12 or later, with only the standard library.

## Nobody edits the wiki with a tool

Only a human edits the RuneScape Wiki, by hand, with their own account. An AI agent never edits the wiki. The scripts send only GET requests. They have no login, edit or post code. Code review rejects a change that adds it.

## Files

- `scope.json`: hand-written. A JSON list of the wiki item names that we cover, for example `"Super restore (3)"`. Use the wiki name, for example `"Snapdragon potion (unfinished)"`, not `"(unf)"`.
- `wiki-snapshot.json`: written by `fetch.py`. Do not edit it.
- `fetch.py`: gets the rows from the wiki.

## Get the wiki rows

```sh
python3 tools/fetch.py
```

The script reads `tools/scope.json` and writes `tools/wiki-snapshot.json`. It does these steps:

1. It gets the `infobox_item` rows of the scope items. A scope item with no row is an error.
2. It gets the `recipe` rows of the pages of these items. It keeps a row only when its first Output is a scope item.
3. It gets the `infobox_item` rows of each Input and Output in the kept rows.

The snapshot header gives the source URL, the date and the licence. The script parses `production_json`, and sorts the rows and the keys. A diff then shows each changed value on its own line.

## Make `data/recipes.lua`

```sh
python3 tools/generate.py
```

The script reads `tools/wiki-snapshot.json`, `tools/overrides.lua` and `tools/config-names.lua`. It sends no requests. It needs `lua5.4` and `stylua`. Nobody edits `data/recipes.lua` by hand.

The file returns `{ recipes, items, pools, unlocks }`:

- **`recipes`:** `{ ITEM = { recipe, ... } }`, in the format that `Plan.calculate` reads. Each Recipe also has `id` and `wiki` (the page name).
- **`items`:** `{ ITEM = { name = "..." } }`. The name is the wiki name. The UI reads `ObjType.name`, not this name.
- **`pools`:** `{ POOL = { ITEM_1, ITEM_2, ... } }`, the items of each Dose size, from size 1 (ADR 0005).
- **`unlocks`:** `{ KEY = "Display text" }`.

Rules:

- **Item:** the script finds the `infobox_item` row with the page and the name of each Input and Output. `tools/config-names.lua` gives the config name of its item ID. When there is more than one item ID, an item override chooses one.
- **Recipe id:** `<Output config name>_x<Output quantity>_<hash>`. The hash is the first 6 hex characters of SHA-256 of the sorted, unique Input config names, joined with `,`. A Recipe with no Inputs has no hash.
- **Verb:** the facility of the row. If the row has no facility, the override.
- **Dose pool:** an Input or Output with a Dose size (`portion`) puts all versions of its wiki page in a pool. The size comes from the version, for example `(3)`. The pool key is the page name in upper case, for example `SUPER_RESTORE`. A pool with a gap is an error.
- **Unlocks:** only from `tools/overrides.lua`. A Recipe that names an unknown Unlock is an error.
- **Order:** the Recipes of one item are sorted by id.
- The script gives all errors together, and writes no file when there is an error.

Warnings:

- A row whose ticks, level or quantity is not a whole number. The script skips the row.
- A wiki name that is different from the game name in `tools/config-names.lua`, unless a `gameName` override gives that game name.
- A wiki row with a quest, when its Recipe has no Unlocks.
- A version of a Dose pool page that is not a Dose size.
- An override that is not necessary: a verb on a row with a facility, an item id when the wiki gives only that ID, a `gameName` equal to the wiki name, an override for a Recipe id that no wiki row has, or an Unlock that no Recipe names.

`tools/overrides.lua` gives each value as `{ value = ..., reason = "..." }`. A tested value also gives the date, the method (`probe` or `manual`) and the wiki edit, if there is one:

```lua
return {
    recipes = {
        SUPER_RESTORE_3_x1_ab12cd = {
            actionLimit = {
                value = 14,
                reason = "The wiki has no Action limit.",
                tested = { date = "2026-10-23", method = "probe" },
            },
            verb = { value = "Mix", reason = "The row has no facility." },
            unlocks = { value = { "DRUIDIC_RITUAL" }, reason = "Herblore needs the quest." },
        },
        CLEAN_RANARR_x1_9f00aa = { skip = { reason = "Zahur cleans herbs. It is not a player action." } },
    },
    items = {
        Coins = { id = { value = 995, reason = "Page Coins also has the 1B coin." } },
        ["Snapdragon potion (unfinished)"] = {
            gameName = { value = "Snapdragon potion (unf)", reason = "The game uses a short name." },
        },
    },
    unlocks = {
        DRUIDIC_RITUAL = { text = "Druidic Ritual", reason = "Herblore needs the quest." },
    },
}
```

## Tests

```sh
python3 -m unittest discover -s tools/tests
```

The tests send no requests.

## Wiki API guidelines

We follow the API guidelines at <https://runescape.wiki/w/RuneScape:APIs>. This page redirects to `Help:APIs`. We followed revision [37037574](https://runescape.wiki/w/Help:APIs?oldid=37037574) of 2026-05-10. The scripts:

- Send the User-Agent `rs-production-planner-recipe-tools (https://github.com/gigosaurus/rs-production-planner)`.
- Send one request at a time, with 1 second between requests.
- Send only GET requests.

## Licence

Wiki content is CC BY-NC-SA 3.0. See <https://meta.weirdgloop.org/w/Licensing>.
