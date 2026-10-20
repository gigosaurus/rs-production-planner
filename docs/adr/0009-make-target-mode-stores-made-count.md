# Target mode Make stores a Made count

Amends ADR 0003.

A Plan has a Target mode: Have or Make. Have is ADR 0003. Make is for a player who sells products during the Plan. For example, the player makes 100 Shark but sells each inventory to buy more Raw shark. Their Counted stock of Shark never gets near 100.

In Make, each Target has a stored Made count. Remaining for a Target = Target − Made count. Counted stock of the Target item does not count. Intermediates and Raw materials still use live Counted stock. A Make Plan is Complete when each Made count reaches its Target. It then stays Complete. A Made count never falls on its own.

## How the plugin finds the Made count

Made count = rises in Detected stock of the Target item (backpack and bank together, as in ADR 0004), minus rises from known other sources. Falls are ignored. A rise does not count when:

- **It is a pickup.** The rise occurs in the same server tick as a decrease of a ground stack of the same item (`ObjStackEntityRemoved`, or `ObjStackEntityChanged` with a lower count). The plugin excludes up to the size of that decrease. This applies to all ground stacks, so loot does not count. Verified by probe (`probes/drop-shop-probe/`).
- **A shop is open.** An inventory whose `configName` contains "SHOP" is open (`InventoryAdded` / `InventoryRemoved`). Verified in many shops.
- **It comes from the GE.** For each character, the plugin saves the last `soldCount` of each GE slot. An increase on a BUY offer for a Target item adds to a GE amount. So do the items that come back from an aborted SELL offer. Rises use up the GE amount first, so the timing of collection does not matter. **Unverified.** We cannot test the GE. If the guess is wrong, bought items count as made.

Also:

- The first Bank snapshot of a character is not a rise. It is the starting point for the bank part.
- For each character, the plugin saves the last Detected count of each Target. A rise between sessions counts on the next load.

## Made count scope

The plugin keeps two Made counts for each Target: one for each character (ADR 0008), and one for all characters. Each rise adds to both. Made count scope selects which count the Plan uses. A change of scope then loses nothing.

## Edits

- The player can set the selected Made count directly. A reset sets it to 0.
- A change to the amount of a Target keeps its Made count. Removing a Target deletes its Made counts.
- Have → Make sets all Made counts to 0. Make → Have deletes them.

## Considered Options

- **A fall in the Inputs and a rise in the Output in the same tick:** rejected. An Effect that saves the Inputs gives an Output rise with no fall in the Inputs. This occurs often.
- **Chat messages:** rejected for now. They need the `chatAccess` permission and are fragile. Messages such as "Your sign of the porter has sent an item to your bank" can be a future addition.
- **Track drops, and let later rises use up a dropped amount:** rejected. If a dropped stack disappears, the dropped amount stays, and the next items that the player makes do not count.
- **Exclude rises when the money pouch falls:** rejected. Some shops take other currencies. The open-shop rule covers them.
- **Exclude trades:** not possible. The docs name no trade inventory, and we cannot test one.

## Consequences

- The plugin stores progress, which ADR 0003 rejects. It does this only in Make, and only for Targets. Steps still show only what remains.
- In Make, the Plan shows one Planning assumption: `Made counts can include items that you bought, traded or took back out of storage. Edit the count to correct it.` This covers trades, storages that the plugin does not read, GE purchases while the plugin is off, and a wrong GE guess.
- A name change resets the Made counts of that character (ADR 0008).
- ADR 0003 said that the plugin saves only Targets and settings. That was already wrong. ADR 0008 lists the saved data.
