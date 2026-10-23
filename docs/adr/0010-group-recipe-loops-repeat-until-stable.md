# Group recipe Loops and calculate each Loop again until it is stable

Amends ADR 0002.

Recipe data can contain a Loop (#7). For example, Recipe X is A + B → D + C, and Recipe R is C → A. The Target is 10× D. The player owns 1× A and 10× B. The Plan does 10 X and 9 R. 1× C is a Leftover. The player goes around the Loop many times.

ADR 0002 gives each item one Planning level. The items in a Loop have no single level, so the search for Planning levels does not stop.

## Decision

- **Group.** The Plan finds each Loop in the links of ADR 0002. It treats the items of the Loop as one group with one Planning level. Outside Loops, ADR 0002 does not change.
- **Calculate again until stable.** Inside a group, the Plan calculates the demand, the supply and the actions of each Step again and again, until no amount changes. Each Step uses actions = max(0, ⌈need ÷ output⌉), so Leftovers need no special rule.
- **Pass limit.** The Plan stops after 1000 passes. The limit is a named constant in `plan/calculate.lua`.
- **No gain.** A Loop that gains nothing never becomes stable. For example, Fill bucket and Empty bucket give back only what goes in. When a Loop reaches the pass limit, the Plan stops with an error that names the items in the Loop.
- **Seed.** A Loop needs stock to start, before it returns any. The Seed is the Inputs of one action of the first Step of the Loop. Only the Inputs that a Recipe of the Loop makes count, as an Output or as an other Output. A Step outside the Loop makes each other Input before the Loop starts, or that Input is a Shortage. If the player owns less than the Seed, the difference is a Shortage.
  - When the player can do one action of any Step of the Loop, the Loop needs no Seed. For example, the player has 0× A and 1× C: R can start, so A is not a Shortage.
  - The Steps count the Seed Shortage as stock. For example, the player owns 0× A and 10× B: the Plan does 10 X and 9 R, 1× C is a Leftover, and 1× A is a Shortage. The Plan then does not change when the player gets the A.
  - After the Plan adds a Seed Shortage, it calculates the Loop again from no Steps. From the larger amounts of the passes before, the passes can stop at more actions than the Loop needs.
  - The Shortage of an item is its Seed part and the need that remains after it. Thus the Seed part of a Raw material does not count two times.
- **Order.** Inside a Loop, a Step that turns A into a different item comes before a Step that makes only A. A Step that makes A and also a different item is not "only A". If this rule contradicts itself, the first Step is the Step whose Output goes out of the Loop toward the Target. If there is still a tie, the order of the recipe data decides. The recipe data has no fixed order, so this is the order in which the search from the Targets finds the items.
- **Next step.** A Step in a Loop is ready when the player has the Inputs for one action. Outside Loops, the Batch hint rule does not change. With the order rule, the Next step then changes between the Steps of the Loop: X when the player has an A, and R when the player has no A.
- **Mark.** Each Step in a Loop shows a mark that names the other Steps of the Loop, for example `Loop: repeat with R`. A Step with no other Step in its Loop has no mark.

## Considered Options

- **Recipe loops are a data error:** rejected. Real recipes can give back an Input, as in the example.
- **Path rule.** When the Plan expands an item, it does not use a Recipe that needs an item above it on the same path. It treats that item as a Raw material: rejected. In the example, it gives a Shortage of 9× A. The player needs none.
- **Order rule only:** rejected. It sets the production order, but it does not calculate amounts.
- **Linear equations:** rejected for now. They get the amounts in one step, and they find a Loop with no gain exactly. But a Leftover makes supply ≥ demand, which is not an equation. The Plan does not know before the calculation which items have a Leftover. That needs linear programming. Examine this option again if a real Loop reaches the pass limit.

## Consequences

- A Loop with a very small gain needs many passes. If it reaches the pass limit, the player sees the Loop error by mistake.
- Recipe choice (#30) can make new Loops. The rules here apply to them.
