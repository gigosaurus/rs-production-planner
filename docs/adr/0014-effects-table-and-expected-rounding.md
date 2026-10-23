# Effects are a table keyed by Effect source, and expected mode rounds to whole actions

Amends ADR 0011.

An Effect changes the yield of a Recipe (#31). Many Effects change a large group of Recipes. For example, one worn item can change all Herblore Recipes. If each Recipe listed its Effects, the recipe data would repeat each Effect many times.

## The Effects table

The Effects are a hand-written table in `data/effects.lua`, apart from the Recipes. It is a module, as the recipe data is (ADR 0013). The table is keyed by Effect source, for example a worn item, a portable or a perk rank. Each Effect of an Effect source names the Recipes that it changes in one of these ways:

- a skill: all Recipes that have that skill in their skill requirements;
- a Recipe tag: all Recipes that have that tag. A Recipe can have a list of Recipe tags;
- one Recipe, by its `id` (#30).

An Effect has no list of exceptions. For example, Portable well changes all Herblore Recipes except combination potions. The Recipes that it changes get the Recipe tag `well`, and the Effect names that tag.

## Kinds of Effect

An Effect has one of three kinds:

- **Save an Input:** a chance that an action does not use an Input. The Effect names the Inputs that it saves: all Inputs, all Inputs except the first, or a list of items. It also says if one roll saves each of these Inputs or one of them at random. For one at random, each of the Inputs gets an equal part of the chance. For example, Scroll of cleansing saves one secondary Input at 10%. With two secondary Inputs, each one has 5%.
- **Extra Output:** a chance that an action makes a quantity more of one Output. A potion dose counts in the Dose pool (ADR 0005). For example, Botanist's amulet gives a potion of 4 doses in place of 3 doses. This is 1 extra dose.
- **Multiplied Output:** a chance that an action makes more of all of its Outputs, for example two times. The Plan applies it after the Extra Output Effects.

An Effect that gives a different item, for example a Baron shark in place of a shark, is not in this ADR.

Each chance is a fraction: a whole-number numerator and a whole-number denominator, for example 1/3 or 5/100. A percent cannot hold all chances. The game has chances such as 0.1% and 1/3. A float is not exact. For example, 100 × 1.15 gives 114.99…, and floor gives 114, not 115. With fractions, the Plan can calculate with whole numbers only.

Each Effect rolls on its own. Two save Effects on one Input then give an average use of (1 − p₁) × (1 − p₂) for each action.

## Effect conditions

An Effect can have a list of Effect conditions. An Effect condition is a fact that is true or false, for example "in the desert". It can also be "Effect source X is active". The Plan counts an Effect only when its Effect source is active and all its Effect conditions are true.

For example, the Brooch of the Gods adds 5% to the chance of Portable well. The Brooch of the Gods is its own Effect source. Its Effect is an Extra Output of 1 at 5% for the Recipe tag `well`, with the Effect condition "Portable well is active". The average is then 10%, the same as in the game.

## Rank groups

An Effect source can be in a Rank group. For example, each rank of the Fortune perk is its own Effect source: "Fortune 1", "Fortune 2" and so on. Fortune on level-20 gear is also its own Effect source. When more than one Effect source of a Rank group is active, the Plan counts only the strongest one. This is how perks work in the game.

## Active Effect sources and Effect conditions

The Basis lists the active Effect sources and the true Effect conditions. The Plan counts only the Effects of these Effect sources. `Plan.calculate` does not find them. Another part of the plugin fills the lists. It detects them where it can, and the player sets the others.

An Effect source or an Effect condition is a fact about one character. ADR 0008 saves such facts for each character. The plugin saves the ones that the player sets in `char:<displayName>:settings`. It does not save the ones that it detects, because it detects them again.

## Planning mode

- **Conservative:** the Plan counts each Effect at zero. The Plan is the same as a Plan with no Effects.
- **Expected:** the Plan counts each Effect at its average.

When the Plan counts one or more Effects at their average, it gives a Planning assumption.

Planning mode has a global value. A Recipe can also have its own value. This value is for a Step that is hard, for example a Step that needs a hard Input, or a large amount of an Input. A Recipe that has no value of its own uses the global value. The value of a Recipe applies to all Inputs and Outputs of its Step. A Recipe with no Inputs, for example cutting a tree, uses the same rule.

The values are in `global:settings`, as `{ [recipe id] = mode }` in the Planning mode field. They are global, because they say how to plan (ADR 0008).

For example, the global value is conservative. The player sets the Recipe of a potion to expected, because it uses Primal extract. Each action uses 1 Primal extract and 1 Vial of water. An Effect gives a 5% chance of 1 extra potion. To make 100 potions, the Step needs 96 actions, 96 Primal extract and 96 Vial of water.

## Rounding in expected mode

The Plan keeps whole actions and whole items. Each rounding gives the player enough items:

- **Output** = floor(actions × average Output of each action).
- **Actions** = the smallest whole number that gives the need. This is ceil(need ÷ average Output of each action).
- **Inputs** = ceil(actions × average use of each action).

For example, an action has a 5% chance to make 2 items, not 1. The average Output is 1.05. 19 actions make 19 items. 20 actions make 21 items. A need of 2 gives 2 actions. A need of 100 gives 96 actions. An Output that the Plan does not need is a Leftover.

The Plan rounds at each Step. A Step then gives whole items to the next Step.

An average is not certain. If the player gets fewer extra items than the average, the Plan calculates again from Counted stock (ADR 0003). It then gives more actions or a Shortage.

## Considered Options

- **Effects as a field of each Recipe:** rejected. One Effect source changes many Recipes, so the data repeats it.
- **The Plan counts all Effects in the table:** rejected. The player does not always have the Effect source.
- **A chance as a percent or a float:** rejected. A percent cannot hold 0.1% or 1/3, and a float is not exact.
- **Add the chances of two Effects:** rejected. Since July 2023, Fletching adds them. The wiki gives no rule for other skills. Separate rolls never plan fewer Inputs than added chances. The difference is at most p₁ × p₂.
- **A list of exceptions in an Effect:** rejected. Two ways to name a group are harder to check than one.
- **A field that changes the chance of an Effect when a fact is true:** rejected. An Effect condition "Effect source X is active" does the same with no new field.
- **A rank number in the Basis:** rejected. The Basis then holds numbers, not only facts that are true or false. A Rank group does the same.
- **Fractions through the chain, with rounding only at the end:** rejected. It can save at most one action for each Step, and Effects are small. It also makes it harder for a Loop to become stable (ADR 0010).
- **Round each average to the nearest whole number:** rejected. It can give fewer items than the need.
- **A value for each Input item:** rejected. The player cannot plan one Step that needs a large amount of an Input that is easy to get. The value of an item applies in all Steps. It also needs rules for a Step whose Inputs have different values, and for a Step with no Inputs.
- **A value for each Input item and for each Recipe:** rejected. It has the most rules, and it keeps the Steps whose Inputs have different values.
