# Game client behaviour

This file lists tested behaviour of the game client. This behaviour is different from `runescape-docs`, or the docs do not give it. Each fact gives the probe that found it. Use the tested behaviour, not the docs (ADR 0007).

Game client version for these tests: 950-1.

## Lua

- The game client stops a Lua call after 1000 ms. The error is `Maximum function execution time of 1000 ms exceeded`. The limit is for the total time of one call. Do slow work in parts, for example one part in each `Logic` tick. (`probes/persistentdb-probe`)
- `require` returns `nil` for a module that returns a function. Every module must return a table. (`probes/require-probe`)

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

## Inventory API

ADR 0007 gives the Inventory API facts: `isValid` and not `valid`, empty slots with id -1, Noted items as `CERT_<name>`, and the bank in one `InventoryAdded` event. (`probes/bank-probe`, `probes/stack-probe`)

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
