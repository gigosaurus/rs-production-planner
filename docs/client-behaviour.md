# Client behaviour

This file lists tested client behaviour that differs from `runescape-docs` or that the docs do not give. Each fact gives the probe that found it. Use the tested behaviour, not the docs (ADR 0007).

Client version for these tests: 950-1.

## Lua

- The client stops a Lua call after 1000 ms with the error `Maximum function execution time of 1000 ms exceeded`. The time adds up across one call. Do slow work in parts, for example one part in each `Logic` tick. (`probes/persistentdb-probe`)
- `require` returns `nil` for a module that returns a function. Every module must return a table. (`probes/require-probe`)

## Inventory

ADR 0007 gives the inventory facts: `isValid` and not `valid`, empty slots with id -1, Noted items as `CERT_<name>`, and the bank in one `InventoryAdded` event. (`probes/bank-probe`, `probes/stack-probe`)

## PersistentDB

Tested on 2026-10-21 with `probes/persistentdb-probe` and `probes/persistentdb-limits-probe`. The data survived `prl` and a full restart of the client.

### Numbers

PersistentDB saves numbers as 32-bit floats. `SetInt` saves a 32-bit signed integer. (`probes/persistentdb-limits-probe`)

- An untyped `Set` of a number gives a float back, with float32 precision. `42` becomes `42.0`. `16777217` becomes `16777216.0`. `0.1` becomes `0.10000000149011612`.
- In a table, numbers also have float32 precision. Integers are exact up to 2^24 (16,777,216) only. `16777217` becomes `16777216`. A whole number below 2^31 comes back as an integer. From 2^31 it comes back as a float.
- `SetInt` and `GetInt` are exact from -2,147,483,648 to 2,147,483,647. Values outside this range wrap. `SetInt` still returns `true`. `2^31` becomes `-2^31`, and `2^32` becomes `0`.
- A string keeps an integer exact. `"9007199254740993"` comes back unchanged.
- Do not save a count above 16,777,216 as a number in a table. Save it as a string, or save it with `SetInt` at the top level if it is not more than 2,147,483,647.

### Keys in a table

- String keys, integer keys, negative integer keys, sparse arrays and mixed tables come back correctly.
- A float key becomes an integer key: `1.5` becomes `2`.
- The client drops boolean keys and function fields. It gives no error.

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
- `GetInt`, `SetInt`, `GetStructuredData` and `SetStructuredData` exist. `PersistentDB` is a userdata.
- The first version of the probe crashed the client on `pon`. That version called `pcall(PersistentDB.Set, PersistentDB, ...)` and read `PersistentDB.GetFloat`. The second version did neither and did not crash. We did not find the cause. Call the methods with `:`, inside a Lua function.
