# Effects are a table keyed by source, and expected mode rounds to whole actions

An Effect changes the yield of a Recipe (#31). Many Effects change a large group of Recipes. For example, one worn item can change all Herblore Recipes. If each Recipe listed its Effects, the recipe data would repeat each Effect many times.

## The Effects table

The Effects are a hand-written table, apart from the Recipes. Each entry has a source, for example a worn item. Each Effect of a source names the Recipes that it changes in one of these ways:

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
