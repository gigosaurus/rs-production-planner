local Plan = require("plan/calculate")

local function bakeBread(detected, assumed, reserves)
    return Plan.calculate({
        targets = { { item = "BREAD", count = 5 } },
        recipes = {
            BREAD = { { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
        },
        detected = detected,
        assumed = assumed,
        reserves = reserves,
    })
end

local function stepFor(plan, item)
    for _, step in ipairs(plan.steps) do
        if step.item == item then
            return step
        end
    end
end

describe("Plan.calculate", function()
    it("rounds a Step up to whole actions", function()
        local plan = bakeBread({ DOUGH = 10 })

        expectEqual(#plan.steps, 1)
        expectEqual(plan.steps[1].item, "BREAD")
        expectEqual(plan.steps[1].actions, 3)
    end)

    it("lists the extra Output as a Leftover", function()
        local plan = bakeBread({ DOUGH = 10 })

        expectEqual(plan.leftovers, { { item = "BREAD", count = 1 } })
    end)

    it("lists an other Output that the Plan does not use as a Leftover", function()
        local plan = Plan.calculate({
            targets = { { item = "COCONUT_MILK", count = 3 } },
            recipes = {
                COCONUT_MILK = {
                    {
                        verb = "Pour",
                        output = 1,
                        actionLimit = 60,
                        otherOutputs = { { item = "COCONUT_SHELL", count = 1 } },
                        inputs = { { item = "VIAL", count = 1 }, { item = "COCONUT_OPEN", count = 1 } },
                    },
                },
            },
            detected = { VIAL = 3, COCONUT_OPEN = 3 },
        })

        expectEqual(plan.leftovers, { { item = "COCONUT_SHELL", count = 3 } })
    end)

    describe("other Outputs as supply", function()
        local pourMilk = {
            verb = "Pour",
            output = 1,
            actionLimit = 60,
            otherOutputs = { { item = "COCONUT_SHELL", count = 1 } },
            inputs = { { item = "VIAL", count = 1 }, { item = "COCONUT_OPEN", count = 1 } },
        }
        local makeBowl =
            { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "COCONUT_SHELL", count = 1 } } }

        it("subtracts an other Output from the demand for that item", function()
            local plan = Plan.calculate({
                targets = { { item = "COCONUT_MILK", count = 3 }, { item = "SHELL_BOWL", count = 3 } },
                recipes = { COCONUT_MILK = { pourMilk }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
            })

            expectEqual(plan.shortages, {})
            expectEqual(plan.leftovers, {})
        end)

        it("puts the Step that makes an other Output before the Steps that use it", function()
            local plan = Plan.calculate({
                targets = { { item = "SHELL_BOWL", count = 3 }, { item = "COCONUT_MILK", count = 3 } },
                recipes = { COCONUT_MILK = { pourMilk }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
            })

            local order = {}
            for i, step in ipairs(plan.steps) do
                order[i] = step.item
            end
            expectEqual(order, { "COCONUT_MILK", "SHELL_BOWL" })
        end)

        it("uses an other Output from a Step that is deeper in the recipe tree", function()
            local plan = Plan.calculate({
                targets = { { item = "FRUIT_BOWL", count = 3 } },
                recipes = {
                    FRUIT_BOWL = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "COCONUT_SHELL", count = 1 }, { item = "MILK_JUG", count = 1 } },
                        },
                    },
                    MILK_JUG = {
                        {
                            verb = "Fill",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "COCONUT_MILK", count = 1 } },
                        },
                    },
                    COCONUT_MILK = { pourMilk },
                },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
            })

            expectEqual(plan.shortages, {})
        end)

        it("makes a Step Waiting when it uses an other Output of a Flagged step", function()
            local flaggedPour = {
                verb = "Pour",
                output = 1,
                actionLimit = 60,
                otherOutputs = { { item = "COCONUT_SHELL", count = 1 } },
                inputs = { { item = "VIAL", count = 1 }, { item = "COCONUT_OPEN", count = 1 } },
                skills = { { skill = "COOKING", level = 50 } },
            }
            local plan = Plan.calculate({
                targets = { { item = "COCONUT_MILK", count = 3 }, { item = "SHELL_BOWL", count = 3 } },
                recipes = { COCONUT_MILK = { flaggedPour }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
                levels = { COOKING = 10 },
            })

            expectEqual(plan.steps[1].item, "COCONUT_MILK")
            expectEqual(stepFor(plan, "SHELL_BOWL").waitsOn, 1)
        end)

        it("does not make a Step Waiting when a Step that can go ahead uses its other Output", function()
            local plan = Plan.calculate({
                targets = { { item = "MILK_JUG", count = 3 }, { item = "SHELL_BOWL", count = 3 } },
                recipes = {
                    MILK_JUG = {
                        {
                            verb = "Fill",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "COCONUT_MILK", count = 1 } },
                            skills = { { skill = "COOKING", level = 50 } },
                        },
                    },
                    COCONUT_MILK = { pourMilk },
                    SHELL_BOWL = { makeBowl },
                },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
                levels = { COOKING = 10 },
            })

            expectEqual(stepFor(plan, "COCONUT_MILK").waitsOn, nil)
        end)

        -- Both Steps make COCONUT_SHELL. The Plan uses 4 of the 5.
        it("takes the used part of an other Output from the first Steps in production order", function()
            local plan = Plan.calculate({
                targets = {
                    { item = "COCONUT_MILK", count = 3 },
                    { item = "COCONUT_FLESH", count = 3 },
                    { item = "SHELL_BOWL", count = 4 },
                },
                recipes = {
                    COCONUT_MILK = { pourMilk },
                    COCONUT_FLESH = {
                        {
                            verb = "Scoop",
                            output = 2,
                            actionLimit = 60,
                            otherOutputs = { { item = "COCONUT_SHELL", count = 1 } },
                            inputs = { { item = "COCONUT_OPEN", count = 1 } },
                        },
                    },
                    SHELL_BOWL = { makeBowl },
                },
                detected = { VIAL = 3, COCONUT_OPEN = 5 },
            })

            expectEqual(plan.steps[1].item, "COCONUT_MILK")
            expectEqual(
                plan.leftovers,
                { { item = "COCONUT_FLESH", count = 1 }, { item = "COCONUT_SHELL", count = 1 } }
            )
        end)
    end)

    it("lists the uncovered amount of a Raw material as a Shortage", function()
        local plan = bakeBread({ DOUGH = 1 })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 2 } })
    end)

    it("decreases a Shortage by Assumed stock", function()
        local plan = bakeBread({ DOUGH = 1 }, { DOUGH = 1 })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 1 } })
    end)

    it("increases a Shortage by a Reserve", function()
        local plan = bakeBread({ DOUGH = 3 }, nil, { DOUGH = 2 })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 2 } })
    end)

    it("adds the part of a Reserve that the player does not have to the Shortage", function()
        local plan = bakeBread({}, nil, { DOUGH = 2 })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 5 } })
    end)

    it("ignores a Reserve of an item that the Plan does not use", function()
        local plan = bakeBread({ DOUGH = 3 }, nil, { COAL = 10 })

        expectEqual(plan.shortages, {})
    end)

    it("gives each Target with its Counted stock", function()
        local plan = bakeBread({ BREAD = 3 }, { BREAD = 1 })

        expectEqual(plan.targets, { { item = "BREAD", count = 5, have = 4 } })
    end)

    it("is Complete when Counted stock covers each Target", function()
        local plan = bakeBread({ BREAD = 5 })

        expectEqual(plan.complete, true)
    end)

    it("is not Complete when Counted stock does not cover a Target", function()
        local plan = Plan.calculate({
            targets = { { item = "BREAD", count = 5 }, { item = "CAKE", count = 1 } },
            recipes = {},
            detected = { BREAD = 5 },
        })

        expectEqual(plan.complete, false)
    end)

    it("is not Complete when a Reserve decreases Counted stock below a Target", function()
        local plan = bakeBread({ BREAD = 5 }, nil, { BREAD = 1 })

        expectEqual(plan.complete, false)
    end)

    -- This is the example in ADR 0002.
    it("subtracts Counted stock once from the total demand for an item", function()
        local plan = Plan.calculate({
            targets = { { item = "B", count = 2 }, { item = "C", count = 3 } },
            recipes = {
                A = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "ORE", count = 1 } } } },
                B = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "A", count = 10 } } } },
                C = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "A", count = 100 } } } },
            },
            detected = { A = 1, ORE = 1000 },
        })

        expectEqual(stepFor(plan, "A").actions, 319)
    end)

    -- This is the second case in ADR 0002. C is at depth 1 under D. C is at depth 2 under B.
    it("totals demand for an item at its Planning level", function()
        local plan = Plan.calculate({
            targets = { { item = "D", count = 1 } },
            recipes = {
                B = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "C", count = 1 } } } },
                C = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "ORE", count = 1 } } } },
                D = {
                    {
                        verb = "Make",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "B", count = 1 }, { item = "C", count = 1 } },
                    },
                },
            },
            detected = { C = 1, ORE = 10 },
        })

        local stepsForC = 0
        for _, step in ipairs(plan.steps) do
            if step.item == "C" then
                stepsForC = stepsForC + 1
            end
        end
        expectEqual(stepsForC, 1)
        expectEqual(stepFor(plan, "C").actions, 1)
    end)

    it("decreases the demand below an Intermediate by its Counted stock", function()
        local plan = Plan.calculate({
            targets = { { item = "D", count = 1 } },
            recipes = {
                B = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "ORE", count = 1 } } } },
                D = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "B", count = 10 } } } },
            },
            detected = { B = 4 },
        })

        expectEqual(stepFor(plan, "B").actions, 6)
        expectEqual(plan.shortages, { { item = "ORE", count = 6 } })
    end)

    it("puts the Steps of deeper Planning levels first", function()
        local plan = Plan.calculate({
            targets = { { item = "BREAD", count = 1 } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
                DOUGH = { { verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "FLOUR", count = 1 } } } },
            },
            detected = { FLOUR = 1 },
        })

        local order = {}
        for i, step in ipairs(plan.steps) do
            order[i] = step.item
        end
        expectEqual(order, { "DOUGH", "BREAD" })
    end)

    -- The search finds SALT before FLOUR. The Step that uses FLOUR comes first.
    it("lists Shortages in the order of the first Step that uses them", function()
        local plan = Plan.calculate({
            targets = { { item = "BREAD", count = 1 } },
            recipes = {
                BREAD = {
                    {
                        verb = "Bake",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "SALT", count = 1 }, { item = "DOUGH", count = 1 } },
                    },
                },
                DOUGH = { { verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "FLOUR", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(plan.shortages, { { item = "FLOUR", count = 1 }, { item = "SALT", count = 1 } })
    end)

    -- The search finds CAKE first.
    it("lists a Target with no Recipe after the Shortages that Steps use", function()
        local plan = Plan.calculate({
            targets = { { item = "CAKE", count = 1 }, { item = "BREAD", count = 1 } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 1 }, { item = "CAKE", count = 1 } })
    end)

    it("lists Leftovers in the order of the Step that makes them", function()
        local plan = Plan.calculate({
            targets = { { item = "BREAD", count = 5 } },
            recipes = {
                BREAD = { { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
                DOUGH = { { verb = "Mix", output = 2, actionLimit = 60, inputs = { { item = "FLOUR", count = 1 } } } },
            },
            detected = { FLOUR = 10 },
        })

        expectEqual(plan.leftovers, { { item = "DOUGH", count = 1 }, { item = "BREAD", count = 1 } })
    end)

    it("flags a Step for each skill level that the player does not have", function()
        local plan = Plan.calculate({
            targets = { { item = "SUPER_RESTORE", count = 1 } },
            recipes = {
                SUPER_RESTORE = {
                    {
                        verb = "Mix",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "SNAPDRAGON", count = 1 } },
                        skills = { { skill = "HERBLORE", level = 63 }, { skill = "COOKING", level = 10 } },
                    },
                },
            },
            detected = { SNAPDRAGON = 1 },
            levels = { HERBLORE = 61, COOKING = 10 },
        })

        expectEqual(stepFor(plan, "SUPER_RESTORE").flags, { { skill = "HERBLORE", level = 63, current = 61 } })
    end)

    it("flags a Step for each Unlock that the player does not have", function()
        local plan = Plan.calculate({
            targets = { { item = "TROLL_POTION", count = 1 } },
            recipes = {
                TROLL_POTION = {
                    {
                        verb = "Mix",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "HERB", count = 1 } },
                        unlocks = { "EADGARS_RUSE", "DRUIDIC_RITUAL" },
                    },
                },
            },
            detected = { HERB = 1 },
            unlocks = { DRUIDIC_RITUAL = true },
        })

        expectEqual(stepFor(plan, "TROLL_POTION").flags, { { unlock = "EADGARS_RUSE" } })
    end)

    -- This is the interim behaviour in issue 07.
    it("stops with an error that names the items in a recipe loop", function()
        local ok, err = pcall(Plan.calculate, {
            targets = { { item = "BUCKET_OF_WATER", count = 5 } },
            recipes = {
                BUCKET_OF_WATER = {
                    { verb = "Fill", output = 1, actionLimit = 60, inputs = { { item = "BUCKET", count = 1 } } },
                },
                BUCKET = {
                    {
                        verb = "Empty",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "BUCKET_OF_WATER", count = 1 } },
                    },
                },
            },
            detected = {},
        })

        expectEqual(ok, false)
        expectEqual(err, "The recipes contain a loop: BUCKET_OF_WATER, BUCKET, BUCKET_OF_WATER.")
    end)

    -- Each Recipe must have an Action limit (issue 2, section 1).
    it("stops with an error that names the item when its Recipe has no Action limit", function()
        local ok, err = pcall(Plan.calculate, {
            targets = { { item = "BREAD", count = 1 } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(ok, false)
        expectEqual(err, "The Recipe for BREAD has no Action limit.")
    end)

    describe("Batch hint", function()
        local function batchHint(inputs, actionLimit, stackable)
            local plan = Plan.calculate({
                targets = { { item = "POTION", count = 100 } },
                recipes = { POTION = { { verb = "Mix", output = 1, inputs = inputs, actionLimit = actionLimit } } },
                detected = {},
                stackable = stackable,
            })
            return plan.steps[1].batchHint
        end

        it("divides the backpack by the non-stackable Inputs of one action", function()
            local hint = batchHint({ { item = "HERB_UNF", count = 1 }, { item = "SNAPE_GRASS", count = 1 } }, 60)

            expectEqual(hint, 14)
        end)

        it("keeps one slot for each stackable Input", function()
            local hint = batchHint(
                { { item = "GRIMY_RANARR", count = 1 }, { item = "SWAMP_TAR", count = 15 } },
                60,
                { SWAMP_TAR = true }
            )

            expectEqual(hint, 27)
        end)

        it("uses the Action limit when it is lower than the backpack space", function()
            local hint = batchHint({ { item = "GRIMY_RANARR", count = 1 } }, 10)

            expectEqual(hint, 10)
        end)

        it("uses the Action limit when all Inputs are stackable", function()
            local hint = batchHint(
                { { item = "FIRE_RUNE", count = 5 }, { item = "COSMIC_RUNE", count = 1 } },
                60,
                { FIRE_RUNE = true, COSMIC_RUNE = true }
            )

            expectEqual(hint, 60)
        end)

        it("gives each Input for one inventory, with its Detected stock", function()
            local plan = Plan.calculate({
                targets = { { item = "POTION", count = 100 } },
                recipes = {
                    POTION = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "HERB_UNF", count = 1 }, { item = "SNAPE_GRASS", count = 1 } },
                        },
                    },
                },
                detected = { HERB_UNF = 30 },
            })

            expectEqual(plan.steps[1].inputs, {
                { item = "HERB_UNF", perInventory = 14, detected = 30 },
                { item = "SNAPE_GRASS", perInventory = 14, detected = 0 },
            })
        end)
    end)

    describe("Next step", function()
        -- Two Targets that do not depend on each other. Each Step needs 1 Input for each action.
        local function twoSteps(stock)
            stock.targets = { { item = "CLEAN_RANARR", count = 28 }, { item = "CLEAN_TOADFLAX", count = 28 } }
            stock.recipes = {
                CLEAN_RANARR = {
                    { verb = "Clean", output = 1, actionLimit = 60, inputs = { { item = "GRIMY_RANARR", count = 1 } } },
                },
                CLEAN_TOADFLAX = {
                    {
                        verb = "Clean",
                        output = 1,
                        actionLimit = 60,
                        inputs = { { item = "GRIMY_TOADFLAX", count = 1 } },
                    },
                },
            }
            return Plan.calculate(stock)
        end

        it("is the first Step with Detected stock for one inventory of each Input", function()
            local plan = twoSteps({ detected = { GRIMY_RANARR = 27, GRIMY_TOADFLAX = 28 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)

        it("does not count Reserves", function()
            local plan =
                twoSteps({ detected = { GRIMY_RANARR = 28, GRIMY_TOADFLAX = 28 }, reserves = { GRIMY_RANARR = 1 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)

        it("does not count Assumed stock", function()
            local plan =
                twoSteps({ detected = { GRIMY_RANARR = 10, GRIMY_TOADFLAX = 28 }, assumed = { GRIMY_RANARR = 18 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)

        it("needs only the remaining actions when they are fewer than the Batch hint", function()
            local plan = twoSteps({ detected = { CLEAN_RANARR = 18, GRIMY_RANARR = 10 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_RANARR")
        end)

        it("is nil when no Step is ready", function()
            local plan = twoSteps({ detected = {} })

            expectEqual(plan.next, nil)
        end)

        it("is not a Flagged step", function()
            local plan = Plan.calculate({
                targets = { { item = "CLEAN_RANARR", count = 28 }, { item = "CLEAN_TOADFLAX", count = 28 } },
                recipes = {
                    CLEAN_RANARR = {
                        {
                            verb = "Clean",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "GRIMY_RANARR", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 25 } },
                        },
                    },
                    CLEAN_TOADFLAX = {
                        {
                            verb = "Clean",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "GRIMY_TOADFLAX", count = 1 } },
                        },
                    },
                },
                detected = { GRIMY_RANARR = 28, GRIMY_TOADFLAX = 28 },
                levels = { HERBLORE = 10 },
            })

            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)

        it("is not a Waiting step", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 14 }, { item = "CLEAN_TOADFLAX", count = 28 } },
                recipes = {
                    SUPER_RESTORE = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                    SNAPDRAGON_UNF = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON", count = 1 } },
                        },
                    },
                    CLEAN_TOADFLAX = {
                        {
                            verb = "Clean",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "GRIMY_TOADFLAX", count = 1 } },
                        },
                    },
                },
                detected = { SNAPDRAGON = 14, GRIMY_TOADFLAX = 28 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "SNAPDRAGON_UNF")
            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)
    end)

    describe("Waiting steps", function()
        local mixRestore = {
            verb = "Mix",
            output = 1,
            actionLimit = 60,
            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
            skills = { { skill = "HERBLORE", level = 63 } },
        }
        local makeUnf = { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON", count = 1 } } }

        it("makes a Step Waiting when its Output goes only to a Flagged step", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 1 } },
                recipes = { SUPER_RESTORE = { mixRestore }, SNAPDRAGON_UNF = { makeUnf } },
                detected = { SNAPDRAGON = 1 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "SNAPDRAGON_UNF")
            expectEqual(plan.steps[1].waitsOn, 2)
            expectEqual(plan.steps[2].waitsOn, nil)
        end)

        it("makes a Step Waiting when its Output reaches a Flagged step through other Steps", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 1 } },
                recipes = {
                    SUPER_RESTORE = { mixRestore },
                    SNAPDRAGON_UNF = { makeUnf },
                    SNAPDRAGON = {
                        {
                            verb = "Clean",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "GRIMY_SNAPDRAGON", count = 1 } },
                        },
                    },
                },
                detected = { GRIMY_SNAPDRAGON = 1 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "SNAPDRAGON")
            expectEqual(plan.steps[1].waitsOn, 3)
        end)

        it("does not make a Step Waiting when a Step that uses its Output can go ahead", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 1 }, { item = "OTHER_POTION", count = 1 } },
                recipes = {
                    SUPER_RESTORE = { mixRestore },
                    OTHER_POTION = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                        },
                    },
                    SNAPDRAGON_UNF = { makeUnf },
                },
                detected = { SNAPDRAGON = 2 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(stepFor(plan, "SNAPDRAGON_UNF").waitsOn, nil)
        end)

        it("makes a Step Waiting when it uses an item that a Flagged step makes", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE_4", count = 1 } },
                recipes = {
                    SUPER_RESTORE_4 = {
                        {
                            verb = "Decant",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SUPER_RESTORE_3", count = 1 } },
                        },
                    },
                    SUPER_RESTORE_3 = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                },
                detected = { SNAPDRAGON_UNF = 1 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "SUPER_RESTORE_3")
            expectEqual(plan.steps[2].waitsOn, 1)
        end)

        it("names the first Flagged step in production order when more than one causes the wait", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 1 }, { item = "OTHER_POTION", count = 1 } },
                recipes = {
                    SUPER_RESTORE = { mixRestore },
                    OTHER_POTION = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 70 } },
                        },
                    },
                    SNAPDRAGON_UNF = { makeUnf },
                },
                detected = { SNAPDRAGON = 2 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[2].item, "SUPER_RESTORE")
            expectEqual(plan.steps[1].waitsOn, 2)
        end)

        -- D uses B and C. B uses C, so C comes first in production order.
        it("names the first Flagged step in production order when a Step uses items of more than one", function()
            local plan = Plan.calculate({
                targets = { { item = "D", count = 1 } },
                recipes = {
                    B = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "C", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                    C = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "ORE", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                    D = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "B", count = 1 }, { item = "C", count = 1 } },
                        },
                    },
                },
                detected = { ORE = 2 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "C")
            expectEqual(stepFor(plan, "D").waitsOn, 1)
        end)

        it("does not make a Step Waiting when its Output goes to a Target and to a Flagged step", function()
            local plan = Plan.calculate({
                targets = { { item = "SHARK", count = 10 }, { item = "SHARK_SOUP", count = 4 } },
                recipes = {
                    SHARK = {
                        { verb = "Cook", output = 1, actionLimit = 60, inputs = { { item = "RAW_SHARK", count = 1 } } },
                    },
                    SHARK_SOUP = {
                        {
                            verb = "Make",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SHARK", count = 1 } },
                            skills = { { skill = "COOKING", level = 80 } },
                        },
                    },
                },
                detected = { RAW_SHARK = 14 },
                levels = { COOKING = 70 },
            })

            expectEqual(stepFor(plan, "SHARK").waitsOn, nil)
        end)

        it("makes a Step Waiting when it uses an item that a Waiting step makes", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE_FLASK", count = 1 } },
                recipes = {
                    SUPER_RESTORE_FLASK = {
                        {
                            verb = "Fill",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SUPER_RESTORE_4", count = 1 } },
                        },
                    },
                    SUPER_RESTORE_4 = {
                        {
                            verb = "Decant",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SUPER_RESTORE_3", count = 1 } },
                        },
                    },
                    SUPER_RESTORE_3 = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                },
                detected = { SNAPDRAGON_UNF = 1 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[3].item, "SUPER_RESTORE_FLASK")
            expectEqual(plan.steps[3].waitsOn, 1)
        end)

        it("makes a Step Waiting when its Output goes only to a Waiting step", function()
            local plan = Plan.calculate({
                targets = { { item = "SUPER_RESTORE_FLASK", count = 1 } },
                recipes = {
                    SUPER_RESTORE_FLASK = {
                        {
                            verb = "Fill",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SUPER_RESTORE_3", count = 1 }, { item = "FLASK", count = 1 } },
                        },
                    },
                    SUPER_RESTORE_3 = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 60,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                            skills = { { skill = "HERBLORE", level = 63 } },
                        },
                    },
                    FLASK = {
                        { verb = "Blow", output = 1, actionLimit = 60, inputs = { { item = "GLASS", count = 1 } } },
                    },
                },
                detected = { SNAPDRAGON_UNF = 1, GLASS = 1 },
                levels = { HERBLORE = 61 },
            })

            expectEqual(plan.steps[1].item, "SUPER_RESTORE_3")
            expectEqual(stepFor(plan, "FLASK").waitsOn, 1)
        end)
    end)

    it("uses Target mode Have when the Target mode is HAVE", function()
        local plan = Plan.calculate({
            targets = { { item = "BREAD", count = 5 } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            targetMode = "HAVE",
            made = { BREAD = 5 },
            detected = { BREAD = 2, DOUGH = 10 },
        })

        expectEqual(stepFor(plan, "BREAD").actions, 3)
        expectEqual(plan.complete, false)
        expectEqual(plan.targets, { { item = "BREAD", count = 5, have = 2 } })
    end)

    describe("Target mode Make", function()
        local function makeBread(made, detected)
            return Plan.calculate({
                targets = { { item = "BREAD", count = 5 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                targetMode = "MAKE",
                made = made,
                detected = detected,
            })
        end

        it("makes the Target minus its Made count, even with Counted stock of the Target", function()
            local plan = makeBread({ BREAD = 1 }, { BREAD = 10, DOUGH = 10 })

            expectEqual(stepFor(plan, "BREAD").actions, 2)
        end)

        it("does not decrease the need for the Target by its Assumed stock", function()
            local plan = Plan.calculate({
                targets = { { item = "BREAD", count = 5 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                targetMode = "MAKE",
                made = {},
                detected = { DOUGH = 10 },
                assumed = { BREAD = 3 },
            })

            expectEqual(stepFor(plan, "BREAD").actions, 5)
        end)

        it("does not add a Reserve of the Target to its need", function()
            local plan = Plan.calculate({
                targets = { { item = "BREAD", count = 5 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                targetMode = "MAKE",
                made = {},
                detected = { DOUGH = 10 },
                reserves = { BREAD = 3 },
            })

            expectEqual(stepFor(plan, "BREAD").actions, 5)
        end)

        it("decreases the demand for Intermediates and Raw materials by their Counted stock", function()
            local plan = Plan.calculate({
                targets = { { item = "BREAD", count = 5 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                    DOUGH = {
                        { verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "FLOUR", count = 1 } } },
                    },
                },
                targetMode = "MAKE",
                made = {},
                detected = { DOUGH = 2, FLOUR = 1 },
            })

            expectEqual(stepFor(plan, "DOUGH").actions, 3)
            expectEqual(plan.shortages, { { item = "FLOUR", count = 2 } })
        end)

        it("is Complete when the Made count covers each Target", function()
            local plan = makeBread({ BREAD = 5 }, {})

            expectEqual(plan.complete, true)
        end)

        it("is not Complete when only Counted stock covers a Target", function()
            local plan = makeBread({ BREAD = 4 }, { BREAD = 5 })

            expectEqual(plan.complete, false)
        end)

        it("gives each Target with its Made count and its Counted stock", function()
            local plan = makeBread({ BREAD = 4 }, { BREAD = 2 })

            expectEqual(plan.targets, { { item = "BREAD", count = 5, made = 4, have = 2 } })
        end)

        describe("a Target item that is also an Intermediate", function()
            local function makeSharkAndSoup(made, detected)
                return Plan.calculate({
                    targets = { { item = "SHARK", count = 10 }, { item = "SHARK_SOUP", count = 4 } },
                    recipes = {
                        SHARK = {
                            {
                                verb = "Cook",
                                output = 1,
                                actionLimit = 60,
                                inputs = { { item = "RAW_SHARK", count = 1 } },
                            },
                        },
                        SHARK_SOUP = {
                            { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "SHARK", count = 1 } } },
                        },
                    },
                    targetMode = "MAKE",
                    made = made,
                    detected = detected,
                })
            end

            it("covers the Target part by the Made count and the Intermediate part by Counted stock", function()
                local plan = makeSharkAndSoup({ SHARK = 3 }, { SHARK = 1 })

                expectEqual(stepFor(plan, "SHARK").actions, 10)
            end)

            it("does not let a Made count above the Target cover the Intermediate part", function()
                local plan = makeSharkAndSoup({ SHARK = 12 }, {})

                expectEqual(stepFor(plan, "SHARK").actions, 4)
            end)

            it("does not let spare Counted stock cover the Target part", function()
                local plan = makeSharkAndSoup({ SHARK = 3 }, { SHARK = 10 })

                expectEqual(stepFor(plan, "SHARK").actions, 7)
            end)

            it("lets the same items count in the Made count and in Counted stock", function()
                local plan = makeSharkAndSoup({ SHARK = 10 }, { SHARK = 10 })

                expectEqual(stepFor(plan, "SHARK"), nil)
            end)
        end)
    end)
end)
