# Effects are a table keyed by source, and expected mode rounds to whole actions

An Effect changes the yield of a Recipe (#31). Many Effects change a large group of Recipes. For example, one worn item can change all Herblore Recipes. If each Recipe listed its Effects, the recipe data would repeat each Effect many times.

## The Effects table

The Effects are a hand-written table in `data/effects.lua`, apart from the Recipes. It is a module, as the recipe data is (ADR 0013). Each entry has a source, for example a worn item. Each Effect of a source names the Recipes that it changes in one of these ways:

- a skill: all Recipes that have that skill in their skill requirements;
- a category tag: all Recipes that have that tag. A Recipe can have a list of tags;
- one Recipe.

An Effect has one of two kinds:

- **Save an Input:** a chance that an action does not use an Input.
- **Extra Output:** a chance that an action makes more of an Output.

Each chance is a whole number, for example a percent. A float such as 1.05 is not exact. 20 × 1.05 can then give 20.999…, and floor gives 20, not 21.

## Active sources

The Basis lists the sources that the player has. The Plan counts only the Effects of these sources. `Plan.calculate` does not find the sources. Another part of the plugin fills the list.

## Planning mode

- **Conservative:** the Plan counts each Effect at zero. The Plan is the same as a Plan with no Effects.
- **Expected:** the Plan counts each Effect at its average. The Plan then gives a Planning assumption.

Planning mode has a global value. An Input item can also have its own value. This value is for an ingredient that is hard to get. For example, the global value is conservative, but Primal extract is expected, so the player gathers less of it. An item that has no value of its own uses the global value.

The value of an item applies only where the item is an Input. It does not change the Step that makes the item. In a Step:

- **Save an Input:** the Plan uses the mode of that Input.
- **Extra Output:** each Input amount uses the mode of that Input. The actions for an Input are the actions in its mode. The Step shows the largest of these action counts. The Plan counts the Output of the Step in the mode that gives that count.

For example, a Step makes 100 potions. An Effect gives a 5% chance of 1 extra potion. Primal extract is expected, and Vial of water is conservative. In expected mode the Step needs 96 actions, and in conservative mode it needs 100. The Plan gives 96 Primal extract and 100 Vial of water. The Step shows 100 actions.

## Rounding in expected mode

The Plan keeps whole actions and whole items. Each rounding gives the player enough items:

- **Output** = floor(actions × average Output of each action).
- **Actions** = the smallest whole number that gives the need. This is ceil(need ÷ average Output of each action).
- **Inputs** = ceil(actions × average use of each action).

For example, an action has a 5% chance to make 2 items, not 1. The average Output is 1.05. 19 actions make 19 items. 20 actions make 21 items. A need of 2 gives 2 actions. A need of 100 gives 96 actions. An Output that the Plan does not need is a Leftover.

The Plan rounds at each Step. A Step then gives whole items to the next Step.

## Considered Options

- **Effects as a field of each Recipe:** rejected. One source changes many Recipes, so the data repeats it.
- **The Plan counts all Effects in the table:** rejected. The player does not always have the source.
- **Fractions through the chain, with rounding only at the end:** rejected. It can save at most one action for each Step, and Effects are small. It also makes it harder for a recipe Loop to become stable (ADR 0010).
- **Round each average to the nearest whole number:** rejected. It can give fewer items than the need.
- **The value of an item applies to the Step that makes it:** rejected. The player wants to plan less of an ingredient that is hard to get. That is a value for an Input.
- **A Step is expected when one of its Inputs is expected:** rejected. The Inputs that are easy to get then lose their margin.
- **A Step is expected only when all of its Inputs are expected:** rejected. The value of one Input then often has no result.
