# Plan potions as a Dose pool, not as a separate item for each Dose size

The Plan counts all Dose sizes of one potion together, as doses. A Recipe Input names the Dose size that it needs. The Plan adds a Decant step when it must move pooled doses into different containers to get that Dose size. For example, 4× (3) becomes 3× (4). This changes the decant problem into simple arithmetic. The cost is that the recipe data must say which items are in each Dose pool. If each Dose size was a separate item, the Plan would not see items that the player can easily use.

## Consequences

The plugin does not track empty vials. The Plan assumes that decanting is always possible. The Plan lists this as a Planning assumption. Flasks are not part of the pool. They are a separate product that the player makes from the pool.

A Target of N potions of Dose size (k) is a Target of N × k doses of the pool. For example, 100× (4) is 400 doses. Made counts use the same rule (ADR 0009).
