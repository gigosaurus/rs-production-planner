# Target mode for each Target

Amends ADR 0009 and ADR 0011.

ADR 0009 makes the Target mode a setting of the Plan. A player can want 10 Bread in Have and 100 Bread in Make at the same time (#28). Now each Target has its own Target mode. Each Target then has its own progress. ADR 0009 still applies to how the plugin finds the Made count, to Potion Targets and to Made count scope.

## Progress of a Target

- **Have:** the Counted stock of the item. It rises and falls. A Have Target can stop being met.
- **Make:** the Made count of the Target. It never falls on its own. A Step that uses the item does not decrease it. The plugin shows it up to the amount of the Target, for example 10/10, not 20/10.

The Plan is Complete when each Target is met.

## Made counts and start values

The plugin keeps one Made count for each item on each character, as in ADR 0009. Each Make Target also stores a start value for each character: the item count of that character when the Target changed to Make. The Made count of a Target = item count − start value, on each character. Made count scope then adds the characters as in ADR 0009. A character with no start value uses 0, because its item count starts at its first observation.

- **A Target changes to Make, or the player adds a Make Target:** the start values are the item counts at that time. The item counts of other Targets do not change. If no Make Target was for the item, the plugin starts to count the item at its next observation.
- **A Target changes to Have, or the player removes it:** the plugin deletes its start values. When no Make Target remains for the item, it also deletes the item counts.
- **The player edits the Made count of a Target:** the plugin changes only the start values of that Target. In This character, start value of the current character = item count − new value. In All characters, the start value of each other character is its item count. The sum is then the new value. Other Targets for the same item do not change.

## Need for an item

The need for an item is the largest need of its two modes:

- **Make need** = the largest (amount − Made count) of the Make Targets for the item.
- **Have need** = the largest amount of the Have Targets for the item + Intermediate demand − Counted stock.
- **Need** = max(Make need, Have need).

Counted stock covers the Have Targets and the Intermediate demand together, as in ADR 0002. In Make, a Step can use the items that a Make Target counts. For example, the Targets are 100 Bread (Make) and 5 Sandwich (Have), and each Sandwich uses 1 Bread. The Made count of Bread is 30, and Counted stock of Bread is 15. Make need = 70. Have need = 0 + 5 − 15, which is less than 0. The need is 70. The Sandwiches use 5 of the 70 Bread.

This replaces the rule of ADR 0009, Target part + Intermediate part. That rule plans 14 Shark for 10 Shark (Make) and 4 Shark soup, until the player makes the soup. ADR 0009 also says that 10 Shark complete that Plan. The new rule plans 10. If the player sells Shark before they make the soup, the next calculation adds the shortfall (ADR 0003).

## Saved data

The Target mode is a field of each Target in `global:plan`. It is no longer in `global:settings`. The `made` key of each character also holds the start values of each Make Target.

## Example

Sandwich uses 1 Bread. All counts start at 0.

| Event | a: Make 100 Bread | b: Make 10 Bread | c: Have 5 Sandwich | d: Make 25 Bread | e: Make 3 Sandwich | f: Have 50 Bread |
| --- | --- | --- | --- | --- | --- | --- |
| Make 3 Bread | 3 | 3 | 0 | | | |
| Make 3 Sandwich | 3 | 3 | 3 | | | |
| Make 3 Bread | 6 | 6 | 3 | | | |
| Add d, e and f | 6 | 6 | 3 | 0 | 0 | 3 |
| Make 14 Bread | 20 | 10 | 3 | 14 | 0 | 17 |
| Make 2 Sandwich | 20 | 10 | 5 | 14 | 2 | 15 |
| Sell 1 Sandwich | 20 | 10 | 4 | 14 | 2 | 15 |

At the end, the need for Sandwich is max(3 − 2, 5 − 4) = 1. The need for Bread is max(100 − 20, 50 + 1 − 15) = 80.

## Considered Options

- **One Target mode for the Plan:** rejected. The player cannot then want one item in Have and another item in Make.
- **The sum of Make need and Have need:** rejected. The Bread that a Step uses still counts towards a Make Target, so the sum plans too much.
- **A new Make Target shares the item count with no start value:** rejected. Items that the player made before the Target then count, and a new Target can be met at once.
- **A Make Target sets the item count to 0:** rejected. Other Make Targets for the item then lose their progress.
- **One start value for all characters:** rejected. A change of Made count scope then gives wrong progress.
