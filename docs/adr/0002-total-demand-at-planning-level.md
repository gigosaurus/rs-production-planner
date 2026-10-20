# Total the demand for each item at its Planning level, then subtract Counted stock once

Each item has a Planning level. This is the deepest point at which the item appears in the recipe tree. The Plan processes the items one level at a time, from the Targets downwards. For each item, the Plan adds the demand from every parent. Then it subtracts Counted stock. Then it expands the remaining amount into the Inputs of the item.

A simpler recursive expansion subtracts Counted stock separately in each branch. This is wrong for two reasons:

- It counts the same Counted stock against more than one branch.
- It expands an item before it knows all the demand for that item. For example, D needs B and C. B also needs C.

Example: the Targets are 2× B and 3× C. B needs 10× A. C needs 100× A. The player owns 1× A. The demand for A is 20 + 300 = 320. The Plan makes 319.

## Consequences

Owned Intermediates decrease the demand for all items below them. The production order starts at the deepest level. This makes sure that the Plan makes an item before the items that use it. Do not change this into a depth-first recursion.

## Amendment, 2026-10-20: other Outputs

A Recipe can have more than one Output (#7). For example, Coconut milk also makes a Coconut shell. The Plan counts an Output that is not the item of the Step as supply of that item. For this reason, a Planning level is now the length of the longest path from a Target through three kinds of link:

- an item to each Input of its Recipe
- an item to each other Output of its Recipe
- an item whose Recipe uses an other Output, to the item whose Recipe makes it

The second link makes sure that the Plan knows all the supply of an item before it calculates the need for the item. The third link puts the Step that makes an other Output before the Steps that use it. The Plan subtracts Counted stock and supply from the demand. Supply that the Plan does not use is a Leftover. If the links make a loop, the Plan stops with an error (#7).
