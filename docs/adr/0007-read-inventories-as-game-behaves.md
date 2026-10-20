# Read inventories as the game behaves, not as the API reference says

Amends ADR 0001.

We tested the Inventory API in-game on 2026-10-19 with `probes/bank-probe` and `probes/stack-probe`. It does not behave as its reference page says. The plugin follows the tested behaviour in these ways:

- Check validity with `inv.isValid`. The documented `valid` is always `nil`.
- `GetSlot` also returns an object for an empty slot. This object has the id -1, the name `""` and the count 0. Find empty slots by their id, not by `nil`.
- The config name of a Noted item is `CERT_<name>`. When the plugin reads Detected stock, it removes the prefix and counts the item as `<name>`. The plugin never calculates in advance which items can be noted. The prefix appears only on items that can be noted.
- The bank arrives in full in one `InventoryAdded` event when the player opens it. The plugin takes the Bank snapshot from that event. `InventoryUpdated` events keep the snapshot up to date.

Do not change these back to match the API reference.

ADR 0001 says that the project uses only documented APIs. This ADR makes that rule more precise. The project reads game data only through documented APIs. When a documented API behaves differently from its reference page, the project follows the tested behaviour.
