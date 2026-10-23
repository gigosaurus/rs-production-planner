# Production Planner

A RuneScape plugin. The player tells it which items they want to make. The plugin gives a list of Shortages and a practical production order. It counts what the player already owns. This includes Intermediates.

## Planning

**Plan**:
The one current set of Targets, with the Steps, Shortages and Leftovers that the plugin calculates from them.
_Avoid_: Project, job, order list

**Target**:
An item, a quantity and a Target mode. When two Targets are for the same item, the same items count for each Target.
_Avoid_: Goal, request, order

**Basis**:
All the data that the plugin calculates a Plan from: the Targets, the Recipes, the stock counts, the Made counts, the skill levels and the Unlocks.
_Avoid_: Request, input (an Input is a Recipe term)

**Recipe**:
One way to make items. It has Inputs, Outputs, requirements, an Action limit and an Action time.
_Avoid_: Formula, craft

**Output**:
An item and quantity that a single action of a Recipe makes. A Recipe can have more than one Output.
_Avoid_: Product (in definitions), result, by-product

**Input**:
An item and quantity that a single action of a Recipe uses up.
_Avoid_: Ingredient (in definitions), material, component

**Intermediate**:
An item that a Recipe makes and that a different Recipe in the same Plan uses as an Input.
_Avoid_: Sub-component, partial

**Raw material**:
An item in a Plan that no available Recipe makes. The player must buy or gather it.
_Avoid_: Base item, leaf

**Step**:
One entry in the production order. It is one Recipe, done a whole number of times, or it is a Decant step.
_Avoid_: Task, job, action (an action is one performance of a Recipe, not a Step)

**Next step**:
The first Step in the production order that the player can usefully do now with the items they have.
_Avoid_: Current step, active step

**Former step**:
A Step that was in the previous calculation of the Plan and is not in the new one. Possible causes: the player did the Step, or the Plan does not need it now.
_Avoid_: Finished step, completed step, removed step

**Planning level**:
The deepest point at which an item appears in the Plan. Inputs, other Outputs and the Steps that use other Outputs all count. It decides when the Plan totals the demand and the supply of the item. All items in one Loop have the same Planning level. All Dose sizes of one Dose pool also have the same Planning level.
_Avoid_: Depth (on its own, because an item can appear at more than one depth)

**Loop**:
A group of items whose Recipes need each other. For example, A + B → D + C, and C → A. The player goes around a Loop many times.
_Avoid_: Cycle, circular recipe

**Seed**:
The stock that a Loop needs before it can start: the Inputs of one action of the first Step of the Loop. Only the Inputs that a Recipe of the Loop makes count.
_Avoid_: Starter, catalyst

**Shortage**:
The amount of a Raw material, or of a Seed, that the Plan still needs after it subtracts Counted stock.
_Avoid_: Missing, deficit, to-buy

**Leftover**:
Output that the Plan does not need. It occurs when Steps are rounded up to whole actions. It also occurs when a Recipe makes an Output that the Plan does not use, and when a Decant step puts the doses that remain into one container.
_Avoid_: Surplus, excess, waste

**Batch hint**:
The number of actions of a Step that the player can do with one full Inventory. The Inventory space and the Action limit decide it. When one action does not fit in the Inventory, the Step has no Batch hint. Then the Next step check uses all remaining actions of the Step.
_Avoid_: Inventory size, load

**Action limit**:
The largest number of actions of a Recipe that the game lets the player do at one time.
_Avoid_: Batch size, batch limit (a batch Recipe is a different thing)

**Action time**:
The number of game ticks that one action of a Recipe takes.
_Avoid_: Duration, speed

**Complete**:
The state of a Plan when each Target is met. A Have Target is met while Counted stock covers it. A Make Target is met when its Made count reaches its quantity, and then stays met.
_Avoid_: Done, finished

**Target mode**:
The setting of a Target that decides what its quantity means. Its options are Have and Make.
_Avoid_: Plan mode, goal mode

**Have**:
The Target mode in which the player aims to have the quantity in Counted stock.
_Avoid_: Keep, stock mode

**Make**:
The Target mode in which the player aims to make the quantity. The Target uses its Made count, not Counted stock.
_Avoid_: Produce, craft mode

**Made count**:
The number of the item of a Target that the player made since the Target changed to Make, or since the player added it as Make. The plugin counts rises in Detected stock and subtracts known other sources. The player can edit it. It never falls on its own.
_Avoid_: Progress, produced count, done count

**Start value**:
The number of the item that the plugin saw a character make before a Make Target started. Each Make Target has one start value on each character. On each character, the Made count of the Target is the number now minus the start value.
_Avoid_: Baseline, offset

**GE amount**:
The number of an item that the Grand Exchange gave a character and that the player did not collect yet. Rises in Detected stock use it up first, so they do not add to the Made count. Each character has one GE amount for each Make Target item.
_Avoid_: GE buffer, uncollected count

**Make need**:
The largest (quantity − Made count) of the Make Targets for an item. The need for an item is the larger of the Make need and the Have need, not the sum.
_Avoid_: Target part

**Have need**:
The largest quantity of the Have Targets for an item, plus the need of the Steps that use the item, minus Counted stock.
_Avoid_: Intermediate demand, Intermediate part

**Made count scope**:
The setting of a Plan that decides which Made counts the Plan uses. Its options are This character and All characters. All characters adds the Made counts of all characters together.
_Avoid_: Count mode, tracking mode

## Counted stock

**Counted stock**:
All the items that the Plan counts as owned: Detected stock plus Assumed stock, minus Reserves.
_Avoid_: Stock (on its own), Inventory (that is the in-game container), owned items, holdings

**Detected stock**:
The item counts that the plugin reads from the game: the live Inventory plus the Bank snapshot.
_Avoid_: Real stock, actual stock

**Inventory**:
The in-game container that the player carries items in. It has 28 slots.
_Avoid_: Backpack, stock, owned items

**Bank snapshot**:
The most recent copy of the contents of the bank of one named character. The plugin takes it while the bank is open.
_Avoid_: Bank cache, bank state

**Assumed stock**:
An amount that the player tells the plugin to count as owned, before the plugin detects it. For example, items that the player intends to buy.
_Avoid_: Manual adjustment, override, hypothetical stock

**Fulfilled**:
The state of Assumed stock when the rises in Detected stock since the player entered it cover all of it.
_Avoid_: Resolved, cleared

**Reserve**:
An amount of an item that the player does not want the Plan to use. Counted stock does not include it.
_Avoid_: Hold, lock, keep-back

**Noted item**:
The bank-note form of an item. Counted stock counts it as the item.
_Avoid_: Cert, certificate

## Potions

**Dose pool**:
All the doses of one potion, counted together, in all Dose sizes.
_Avoid_: Potion stock

**Dose size**:
The number of doses in one potion container, for example (3) or (4).
_Avoid_: Potion size, variant

**Decant step**:
A Step that moves doses between containers to get the Dose size that a Recipe or a Target needs. It has no Recipe.
_Avoid_: Combine, merge

## Recipe choice and requirements

**Default recipe**:
The Recipe with the highest priority for an item, from the Recipes that are currently available to the player.
_Avoid_: Primary recipe, best recipe

**Recipe override**:
A Recipe that the player chooses for an item. It replaces the Default recipe.
_Avoid_: Custom recipe, pinned recipe

**Superseded recipe**:
A Recipe that stops being available above a specified level, because a better Recipe replaces it.
_Avoid_: Legacy recipe, old recipe

**Unlock**:
A requirement that is not a skill level, for example a quest or a reward. The player confirms it by hand.
_Avoid_: Prerequisite, requirement (on its own)

**Flagged step**:
A Step whose level or Unlock requirement the player does not meet now. It stays in the Plan. It is the cause of each Waiting step that waits on it. It is never a Waiting step itself.
_Avoid_: Blocked step, locked step

**Waiting step**:
A Step that the player cannot usefully do until they can do a Flagged step. This occurs when all of its output goes only to Flagged or Waiting steps, or when it uses an item that a Flagged or Waiting step makes. A Step that is only short of Inputs is not Waiting.
_Avoid_: Held step, blocked step

## Effects and assumptions

**Effect**:
A thing that changes the yield of a Recipe: a chance to save an Input, or a chance of extra Output.
_Avoid_: Boost, perk, modifier

**Planning mode**:
The setting that decides how the Plan counts Effects: at zero (conservative) or at their average (expected). It has a global value and a value for each item.
_Avoid_: Risk level, safety mode

**Planning assumption**:
A simplification that the Plan uses. The plugin shows it with the Plan.
_Avoid_: Assumption (on its own, because it is easy to confuse with Assumed stock), caveat

## Account

**Account mode**:
The mode that tells if the character is an ironman. The plugin reads it from the game (ADR 0014). It decides if Shortages have the label buy or gather.
_Avoid_: Game mode, account type

## Platform

**Game client**:
The RuneScape program that the player runs. It loads the plugin and runs it.
_Avoid_: Client (on its own), game
