# Save each part in its own key, with counts as strings

Amends ADR 0008.

ADR 0008 says which data the plugin saves for each character and which data is global. This ADR says how the plugin saves it in PersistentDB. The limits come from `docs/client-behaviour.md`.

## Keys

Each part has its own key. Each key holds one table, except the bank key. The bank key holds one string (see Bank snapshot).

| Key | Contents |
| --- | --- |
| `char:<displayName>:bank` | Bank snapshot |
| `char:<displayName>:assumed` | Assumed stock, and the last Detected counts (ADR 0004) |
| `char:<displayName>:reserves` | Reserves |
| `char:<displayName>:unlocks` | Unlocks |
| `char:<displayName>:settings` | Account mode, Recipe overrides |
| `char:<displayName>:made` | Made counts, the GE amounts, and the last `soldCount` of each GE slot (ADR 0009) |
| `global:characters` | The display names of all characters that have saved data |
| `global:plan` | The Plan and its Targets |
| `global:settings` | Target mode, Made count scope, Planning mode, order of Shortages and order of Leftovers |

PersistentDB holds 128 KiB at most in one value. One table for each character can be larger than the limit. One key for each part keeps each value below the limit, and a write changes only the part that changed.

When the plugin first saves data for a character, it adds the display name to `global:characters`. Made count scope All characters (ADR 0009) reads the `made` key of each name in this list. The plugin does not use `IterateEntries` to find characters. `IterateEntries` gives each value to its callback, so it loads the Bank snapshot of each character.

## Bank snapshot

The bank key holds one string. The first line is the version, `v=1`. Each other line is one item: `<name>=<count>`, for example `Coins=1200000`. The count is the text after the last `=`. A line ends with `\n`.

In a table, each entry costs its key length plus about 40 bytes (`docs/client-behaviour.md`). With item names of about 15 characters and counts as strings, an entry costs about 60 to 100 bytes. A bank of 1000 items can then be near the limit. In one string, an item costs about 20 to 30 bytes, so about 4000 items fit. A top-level string holds 131,070 bytes at most.

## Counts

The plugin saves each count as a decimal string, for example `"120"`. It changes the string back to an integer when it loads the data.

PersistentDB saves numbers as 32-bit floats. A number is exact up to 16,777,216 only. Counts of coins can be larger. A string keeps each count exact. One rule for all counts is simpler than a different rule for large counts.

## Writes

A change marks its part as changed. In the next `Logic` tick, the plugin writes each changed part one time.

When `Set` returns `false`, the plugin logs an error and clears the mark. It tells the player one time in chat that the part is not saved. The next change to that part tries again. `Set` gives no other sign of a failure. A part that is too large then does not cause a large write in each tick.

Many changes can come in one tick, for example when the bank opens. One write for each part in each tick prevents many large writes. The client stops a Lua call after 1000 ms.

## Versions

Each saved table has a field `v`, the version of its format. The bank string has its version on the first line. The first version is 1. For each key, a list of migrate steps changes old data to the current version when the plugin loads it.

When `v` is larger than the version that the plugin knows, the plugin does not read or write that key. It tells the player. The plugin never deletes saved data without a prompt.

A key that does not exist gives the start values of ADR 0008.

## Considered Options

- **One table for each character, with the Bank snapshot in its own key:** rejected. Each write saves all the data of the character again.
- **The Bank snapshot as a table:** rejected. A large bank can be larger than the limit.
- **The Bank snapshot in many keys (`bank:1`, `bank:2`, ...):** rejected. The parts can get out of step.
- **Only the bank items that recipes use:** rejected. A new Target then needs the player to open the bank again.
- **`IterateEntries` to find the characters:** rejected. It loads all saved values, and can pass 1000 ms.
- **A retry in each tick after `Set` returns `false`:** rejected. A part that is too large never fits, so the plugin writes it in each tick for no result.
- **One key for each value:** rejected. Values that belong together can get out of step.
- **Counts as numbers, with strings only for large counts:** rejected. The plugin must then read two forms.
- **A write at once on each change:** rejected. The bank can cause many large writes in one tick.
- **A write only at shutdown:** rejected. A crash of the client loses all changes.
- **One version for all saved data:** rejected. A change to one part then needs a migration of all parts.
