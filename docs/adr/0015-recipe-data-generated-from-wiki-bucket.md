# The recipe data is generated from the wiki Bucket at development time

Amends ADR 0001 and ADR 0013.

ADR 0001 says that we write the recipe data by hand. This is too slow for hundreds of Recipes. It also gives no way to find game updates (#46).

A development-time script now generates `data/recipes.lua`. The plugin still uses no wiki data at runtime. The plugin does not contain the scripts. The scripts are in `tools/`. They use Python 3.12 or later, with only the standard library.

## Files

- `tools/wiki-snapshot.json`: the raw rows that the script got from the wiki, checked in. The file header gives the source URL, the date and the licence.
- `tools/overrides.lua`: hand-written. It holds values that the wiki does not have or has wrong. Each entry gives a reason. A tested value also gives the date, the method (probe or manual) and the wiki edit, if there is one.
- `tools/config-names.lua`: the config name and the display name of each wiki item ID. A probe in the game client prints it. We copy the console output into the file.
- `data/recipes.lua`: generated from these three files. Nobody edits it by hand.

## Source

The wiki stores recipes in the Bucket extension. The script reads the `recipe` bucket and the `infobox_item` bucket with `api.php?action=bucket`. One query gives up to 5000 rows. The script asks only for the skills and items that we cover. It reads no wiki pages.

The wiki does not give these values as structured data. They come from `tools/overrides.lua`:

- The Action limit.
- Unlocks. The wiki gives them as free text.
- Effects.

## Wiki API guidelines

We follow `https://runescape.wiki/w/RuneScape:APIs` and the licence terms at `https://meta.weirdgloop.org/w/Licensing`. `tools/README.md` records the revision of the guidelines that we followed. The scripts:

- Send a descriptive User-Agent that names this project and its URL.
- Send one request at a time, with 1 second between requests.
- Send only GET requests.

## Nobody edits the wiki with a tool

Only a human edits the RuneScape Wiki, by hand, with their own account. An AI agent never edits the wiki. The scripts have no login, edit or post code. Code review rejects a change that adds it.

## Checks

- A CI test runs the generator again from the checked-in files. It fails when the output is different from `data/recipes.lua`.
- CI tests check the format of the data. The game checks the config names when the plugin loads (ADR 0013).
- Each Recipe has a `wiki` field with the page name. Each item has a `name` field from the wiki. A probe compares `name` with `ObjType.name` in the game. The UI does not use `name`. It reads `ObjType.name`.
- When the wiki does not give a value, we test it in the developer environment with a recorder probe. Cheats (`give`, `skillsetlevel`) prepare the character. When a cheat cannot prepare a test, we test by hand.
- When the wiki later agrees with an override, the generator warns that the override is not necessary.

## Updates

A scheduled GitHub Action runs each week. It gets the wiki rows again and compares them with the snapshot. It also lists new recipes in the skills that we cover, and it tells us when the API guidelines page changed. When it finds a difference, it opens an issue with the label `needs-triage`.

## Licence

Wiki content is CC BY-NC-SA 3.0. The plugin description says that the recipe data comes from the RuneScape Wiki, with a link. The `wiki` field gives a URL for each Recipe. The plugin is free. Possibly the share-alike term applies to `data/recipes.lua`. The project licence must allow this.

## Considered Options

- **Write all data by hand:** rejected. It is too slow, and it finds no updates.
- **Generate the final file with no hand-written values:** rejected. The wiki does not have the Action limit, Unlocks or Effects.
- **Read wiki pages, not the Bucket:** rejected. It needs thousands of requests.
- **Write the scripts in Lua:** rejected. Lua needs a library for HTTP. Python makes it clear that the scripts are not part of the plugin.
