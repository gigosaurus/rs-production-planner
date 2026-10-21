# Client behaviour

This file lists tested client behaviour that differs from `runescape-docs` or that the docs do not give. Each fact gives the probe that found it. Use the tested behaviour, not the docs (ADR 0007).

Client version for these tests: 950-1.

## Lua

- The client stops a Lua call after 1000 ms with the error `Maximum function execution time of 1000 ms exceeded`. The time adds up across one call. Do slow work in parts, for example one part in each `Logic` tick. (`probes/persistentdb-probe`)
- `require` returns `nil` for a module that returns a function. Every module must return a table. (`probes/require-probe`)

## Inventory

ADR 0007 gives the inventory facts: `isValid` and not `valid`, empty slots with id -1, Noted items as `CERT_<name>`, and the bank in one `InventoryAdded` event. (`probes/bank-probe`, `probes/stack-probe`)

## PersistentDB

Tested on 2026-10-21 with `probes/persistentdb-probe`. The data survived `prl`. We did not test a full restart of the client.

### Numbers

- An untyped `Set` of a top-level integer gives a float back: `42` becomes `42.0`.
- `SetInt` and `GetInt` keep `42` as an integer. We did not test large values.
- In a table, small integers stay integers. A whole float becomes an integer: `3.0` becomes `3`.
- In a table, large integers lose precision. `2147483647` becomes `2147483648.0`. `4294967295` becomes `4294967296.0`. This looks like a 32-bit float. Do not save large counts, for example coins, as numbers in a table.

### Keys in a table

- String keys, integer keys, negative integer keys, sparse arrays and mixed tables come back correctly.
- A float key becomes an integer key: `1.5` becomes `2`.
- The client drops boolean keys and function fields. It gives no error.

### Size

- Each value has a size limit. The limit is not the number of entries:
  - A string of 127 KB fits.
  - 1000 entries `{ ["item i"] = i }` fit.
  - Only 681 entries `{ ["item i"] = { a, b, c } }` fit.

  The limit is probably near 128 KB of serialized data.
- When a value is too large, `Set` returns `false` and saves nothing. It gives no error. Always check the return value of `Set`.
- A table can have 145 levels at most.

### Other

- `Set` copies the table. Each `Get` returns a new table.
- `Set` can change the type of a key. A key that held an integer can then hold a table.
- `IterateEntries` returns `true`, not the number of entries.
- `GetInt`, `SetInt`, `GetStructuredData` and `SetStructuredData` exist. `PersistentDB` is a userdata.
- The first version of the probe crashed the client on `pon`. That version called `pcall(PersistentDB.Set, PersistentDB, ...)` and read `PersistentDB.GetFloat`. The second version did neither and did not crash. We did not find the cause. Call the methods with `:`, inside a Lua function.
