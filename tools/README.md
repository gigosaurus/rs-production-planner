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
