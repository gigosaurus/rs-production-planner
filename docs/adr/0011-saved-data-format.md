# Save each part in its own key, with counts as strings

Amends ADR 0008.

ADR 0008 says which data the plugin saves for each character and which data is global. This ADR says how the plugin saves it in PersistentDB. The limits come from `docs/client-behaviour.md`.

## Keys

Each part has its own key. Each key holds one table.

| Key | Contents |
| --- | --- |
| `char:<displayName>:bank` | Bank snapshot |
| `char:<displayName>:assumed` | Assumed stock, and the last Detected counts (ADR 0004) |
| `char:<displayName>:reserves` | Reserves |
| `char:<displayName>:unlocks` | Unlocks |
| `char:<displayName>:settings` | Account mode, Recipe overrides |
| `char:<displayName>:made` | Made counts, and the amounts that the plugin uses to calculate them |
| `global:plan` | The Plan and its Targets |
| `global:settings` | Target mode, Made count scope, Planning mode, order of Shortages and order of Leftovers |

PersistentDB holds 128 KiB at most in one value. A Bank snapshot of about 1000 items is about 70 KB. One table for each character can be larger than the limit. One key for each part keeps each value below the limit, and a write changes only the part that changed.

## Counts

The plugin saves each count as a decimal string, for example `"120"`. It changes the string back to an integer when it loads the data.

PersistentDB saves numbers as 32-bit floats. A number is exact up to 16,777,216 only. Counts of coins can be larger. A string keeps each count exact. One rule for all counts is simpler than a different rule for large counts.

## Writes

A change marks its part as changed. In the next `Logic` tick, the plugin writes each changed part one time.

When `Set` returns `false`, the plugin logs an error and keeps the part marked as changed. `Set` gives no other sign of a failure.

Many changes can come in one tick, for example when the bank opens. One write for each part in each tick prevents many large writes. The client stops a Lua call after 1000 ms.

## Versions

Each saved table has a field `v`, the version of its format. The first version is 1. For each key, a list of migrate steps changes old data to the current version when the plugin loads it.

When `v` is larger than the version that the plugin knows, the plugin does not read or write that key. It tells the player. The plugin never deletes saved data without a prompt.

A key that does not exist gives the start values of ADR 0008.

## Considered Options

- **One table for each character, with the Bank snapshot in its own key:** rejected. Each write saves all the data of the character again.
- **One key for each value:** rejected. Values that belong together can get out of step.
- **Counts as numbers, with strings only for large counts:** rejected. The plugin must then read two forms.
- **A write at once on each change:** rejected. The bank can cause many large writes in one tick.
- **A write only at shutdown:** rejected. A crash of the client loses all changes.
- **One version for all saved data:** rejected. A change to one part then needs a migration of all parts.
