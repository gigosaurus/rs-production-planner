# Game client behaviour

This file lists tested behaviour of the game client. This behaviour is different from `runescape-docs`, or the docs do not give it. Each fact gives the probe that found it. Use the tested behaviour, not the docs (ADR 0007).

Game client version for these tests: 950-1.

## Lua

- The game client stops a Lua call after 1000 ms. The error is `Maximum function execution time of 1000 ms exceeded`. The limit is for the total time of one call. Do slow work in parts, for example one part in each `Logic` tick. (`probes/persistentdb-probe`)
- `require` returns `nil` for a module that returns a function. Every module must return a table. (`probes/require-probe`)
- `log` cuts text at `<`. The client possibly reads `<` as the start of a text tag. `log("count<1 5")` showed `count`. Do not put `<` in log text. (`probes/bank-placeholder-probe`)

## Vars

`VarPlayer.IRONMAN` (id 4818) tells if the character is an ironman. It is an Integer that holds bit flags. (`probes/account-mode-probe`, #52)

| Character | Value | Bits set |
| --- | --- | --- |
| Not ironman | 4096 | 12 |
| Ironman | 4097 | 12, 0 |
| Hardcore ironman | 4099 | 12, 1, 0 |
| Group ironman | 528385 | 19, 12, 0 |

- The game sets bit 0 for each ironman type.
- Bit 12 was set in each test. We do not know what it means.
- A `VarTransmit` event comes after each change. A new login is not necessary.

## Game state

Tested on 2026-10-25 with `probes/game-state-probe` (#25):

- `GameStateChanged` gives `oldState` and `newState` as plain numbers. `GameState.GAME` is 30 and `GameState.LOBBY` is 20.
- A logout gave one event: 30 (GAME) to 40 (LOADING). A teleport gave no event.
- After a logout and a new login, the plugin logged nothing more: no event, no `Logic` or `ServerLogic` log line, and no load line. `plist` still showed the plugin as on.

## Configs

Tested on client 951-1 with the plugin at the repo root (`main.lua`, #24):

- `config.Obj.FromID(id)` works. The ObjType page gives it, but `api-signatures.md` does not list it.
- An ObjType has `isValid`. The ObjType page does not list it. A full scan of ids 0 to 64,356 with `obj.isValid == true` found the same Objs as the 2026-10-24 export.
- `obj.params` and `struct.params` list the ParamTypes that the config has. `GetParamValue` on each listed param gives the value. An OBJ value is an ObjType with `configName`. A STRUCT value is a StructType.
- `config.Param[name]` gives the ParamType by config name. (`probes/recipe-scan-timer-probe`)
- `GetParamValue` on an AREA param logs a client error that `pcall` does not catch. Read only the params that you need. (`probes/recipe-scan-timer-probe`, `docs/recipe-params.md`)

## Inventory API

ADR 0007 gives the Inventory API facts: `isValid` and not `valid`, empty slots with id -1, Noted items as `CERT_<name>`, and the bank in one `InventoryAdded` event. (`probes/bank-probe`, `probes/stack-probe`)

### Bank placeholders

Tested on 2026-10-25 with `probes/bank-placeholder-probe` (#25):

- A bank placeholder is not an empty slot. Its slot has the real id, `configName` and `name` of the item, and the count 0. Remove a slot with count 0, as you remove an empty slot (id -1).
- `GetTotal` gives 0 for the item of a placeholder.
- `usedSlotCount` includes the placeholders. `freeSlotCount` is the number of empty slots (id -1).
- When "Withdraw All" leaves a placeholder, an `InventoryUpdated` event gives the slot. `GetSlot` on that index gives the item with count 0.
- `slotsUpdated` indexes start at 1, as `GetSlot` indexes do. Use them as they come.

## Vars

### Account mode

`VarPlayer.IRONMAN` (id 4818) is an Integer that holds bit flags. (`probes/account-mode-probe`)

| Character | Value | Bits set |
| --- | --- | --- |
| Not ironman | 4096 | 12 |
| Ironman | 4097 | 12, 0 |
| Hardcore ironman | 4099 | 12, 1, 0 |
| Group ironman | 528385 | 19, 12, 0 |

- Bit 0 is set for each ironman type.
- Bit 12 was always set. We do not know what it means.
- A `VarTransmit` event comes after each cheat (`!setironman`, `!sethardcore`, `!setgroupironman`). A new login is not necessary.
- After `prl` while the player was logged in, the start read gave 4096. This was the value after the last cheat. The probe did not start before login.

## PersistentDB

We tested PersistentDB on 2026-10-21 with `probes/persistentdb-probe` and `probes/persistentdb-limits-probe`. The data survived `prl`. It also survived a full restart of the game client. The probe cannot detect a restart. The person who ran the probe gave this fact.

### Numbers

PersistentDB saves numbers as 32-bit floats. (`probes/persistentdb-limits-probe`)

- When you `Set` a number at the top level, `Get` returns a float with float32 precision. `42` becomes `42.0`. `16777217` becomes `16777216.0`. `0.1` becomes `0.10000000149011612`.
- In a table, numbers also have float32 precision. Integers are exact up to 2^24 (16,777,216) only. `16777217` becomes `16777216`. The game client rounds each number to float32 first. When the rounded whole number is below 2^31, `Get` returns an integer. If not, `Get` returns a float. `2147483647` rounds to 2^31, so `Get` returns `2147483648.0`.
- `SetInt` and `GetInt` are not in the API reference. Do not use them in plugin code (ADR 0007). The probe found that they are exact from -2,147,483,648 to 2,147,483,647. A value outside this range wraps. `SetInt` still returns `true`. `2^31` becomes `-2^31`. `2^32` becomes `0`.
- A string keeps an integer exact. `Get` returns `"9007199254740993"` unchanged.
- Do not save a count above 16,777,216 as a number in a table. Save it as a string.

### Keys in a table

- `Get` returns string keys, integer keys, negative integer keys, sparse arrays and mixed tables correctly.
- A float key becomes an integer key: `1.5` becomes `2`.
- The game client removes boolean keys and function fields. It gives no error.

### Size

- Each value can hold 128 KiB (131,072 bytes) of serialized data. The limit is not the number of entries. (`probes/persistentdb-limits-probe`)
  - A top-level string fits up to 131,070 bytes.
  - A table `{ s = string }` has 41 bytes of overhead.
  - Each key costs its length plus about 40 bytes.
  - One entry `{ ["eNNNNN"] = 1 }` costs about 43 bytes. 3048 of these fit.
- When a value is too large, `Set` returns `false` and saves nothing. It gives no error. Always check the return value of `Set`.
- A table can have 145 levels at most.

### Other

- `Set` copies the table. Each `Get` returns a new table.
- `Set` can change the type of a key. A key that held an integer can then hold a table.
- `IterateEntries` returns `true`, not the number of entries.
- `GetInt`, `SetInt`, `GetStructuredData` and `SetStructuredData` exist, but they are not in the API reference. Do not use them. `PersistentDB` is a userdata.
- The first version of the probe crashed the game client on `pon`. That version called `pcall(PersistentDB.Set, PersistentDB, ...)` and read `PersistentDB.GetFloat`. The second version did neither and did not crash. We did not find the cause. Call the methods with `:`, inside a Lua function.
