# Calculate the Plan again from Counted stock, and store no progress

Amended by ADR 0009 (Target mode Make).

The plugin calculates the Plan again from the start each time Counted stock changes. Counted stock changes when the backpack, the bank, Assumed stock or Reserves change. The plugin does not record which Steps are done. Progress shows because the products of finished Steps are now in Counted stock.

We chose this instead of a checklist that the player ticks. It cannot get out of step with the game. It also tells the player "you already have these intermediates, make these next" with no extra work. The plugin saves no progress. ADR 0008 lists the saved data.

## Consequences

When the player uses finished products, a Complete Plan becomes incomplete again. For example, the player drinks some of the potions. This is intended. For this reason, the plugin keeps the Targets until the player clears them.
