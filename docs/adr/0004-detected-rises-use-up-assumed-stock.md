# Rises in Detected stock use up Assumed stock

The plugin stores Assumed stock as an amount to add to Detected stock. After the player enters an assumption, Detected stock of that item can rise. Each rise decreases the assumption by the same amount, until the assumption is Fulfilled. A fall in Detected stock never increases the assumption again. The plugin measures the rise on the backpack and the bank together. Items that the player moves between them do not count.

The obvious alternative is "assume I have N in total" (Counted stock = max(detected, N)). This alternative counts items twice when the player turns the item into a different item. The item falls while its product rises. The assumption then covers the item again, and the player does not see this.

## Consequences

The plugin always shows Assumed stock as Assumed stock. It can be only a plan, or an intention to buy. The player must never think that they actually have these items.
