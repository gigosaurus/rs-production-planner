local Plan = require("plan/calculate")

local function bakeBread(detected, assumed, reserves)
    return Plan.calculate({
        targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE } },
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

    it("uses the largest of two Targets for the same item, in each order", function()
        local function plan(bread, first, second)
            return Plan.calculate({
                targets = {
                    { id = 1, item = "BREAD", count = first or 2, mode = Plan.HAVE },
                    { id = 2, item = "BREAD", count = second or 5, mode = Plan.HAVE },
                },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                detected = { DOUGH = 10, BREAD = bread },
            })
        end

        expectEqual(plan(0).steps[1].actions, 3)
        expectEqual(plan(4).complete, false)
        expectEqual(plan(5).complete, true)
        expectEqual(plan(0, 5, 2).steps[1].actions, 3)
        expectEqual(plan(4, 5, 2).complete, false)
    end)

    it("gives one Target line for each Target, also for two Targets for the same item", function()
        local plan = Plan.calculate({
            targets = {
                { id = 1, item = "BREAD", count = 2, mode = Plan.HAVE },
                { id = 2, item = "CAKE", count = 1, mode = Plan.HAVE },
                { id = 3, item = "BREAD", count = 5, mode = Plan.HAVE },
            },
            recipes = {},
            detected = { BREAD = 4 },
        })

        expectEqual(plan.targets, {
            { id = 1, item = "BREAD", mode = Plan.HAVE, count = 2, have = 4 },
            { id = 2, item = "CAKE", mode = Plan.HAVE, count = 1, have = 0 },
            { id = 3, item = "BREAD", mode = Plan.HAVE, count = 5, have = 4 },
        })
    end)

    it("does not change the tables of the caller", function()
        -- The Basis has no optional fields and the Recipe has no optional lists.
        local function newBasis()
            return {
                targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                detected = { DOUGH = 10 },
            }
        end
        local basis = newBasis()

        Plan.calculate(basis)

        expectEqual(basis, newBasis())
    end)

    it("lists an other Output that the Plan does not use as a Leftover", function()
        local plan = Plan.calculate({
            targets = { { id = 1, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE } },
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
                targets = {
                    { id = 1, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "SHELL_BOWL", count = 3, mode = Plan.HAVE },
                },
                recipes = { COCONUT_MILK = { pourMilk }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
            })

            expectEqual(plan.shortages, {})
            expectEqual(plan.leftovers, {})
        end)

        it("lists only the unused part of an other Output from two Steps as a Leftover", function()
            local grateCoconut = {
                verb = "Grate",
                output = 1,
                actionLimit = 60,
                otherOutputs = { { item = "COCONUT_SHELL", count = 1 } },
                inputs = { { item = "COCONUT_OPEN", count = 1 } },
            }
            local plan = Plan.calculate({
                targets = {
                    { id = 1, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "GRATED_COCONUT", count = 2, mode = Plan.HAVE },
                    { id = 3, item = "SHELL_BOWL", count = 4, mode = Plan.HAVE },
                },
                recipes = { COCONUT_MILK = { pourMilk }, GRATED_COCONUT = { grateCoconut }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 5 },
            })

            expectEqual(plan.leftovers, { { item = "COCONUT_SHELL", count = 1 } })
        end)

        it("puts the Step that makes an other Output before the Steps that use it", function()
            local plan = Plan.calculate({
                targets = {
                    { id = 1, item = "SHELL_BOWL", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE },
                },
                recipes = { COCONUT_MILK = { pourMilk }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
            })

            local order = {}
            for i, step in ipairs(plan.steps) do
                order[i] = step.item
            end
            expectEqual(order, { "COCONUT_MILK", "SHELL_BOWL" })
        end)

        it("uses an other Output from a Step at a deeper Planning level", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "FRUIT_BOWL", count = 3, mode = Plan.HAVE } },
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
                targets = {
                    { id = 1, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "SHELL_BOWL", count = 3, mode = Plan.HAVE },
                },
                recipes = { COCONUT_MILK = { flaggedPour }, SHELL_BOWL = { makeBowl } },
                detected = { VIAL = 3, COCONUT_OPEN = 3 },
                levels = { COOKING = 10 },
            })

            expectEqual(plan.steps[1].item, "COCONUT_MILK")
            expectEqual(stepFor(plan, "SHELL_BOWL").waitsOn, 1)
        end)

        it("does not make a Step Waiting when a Step that can go ahead uses its other Output", function()
            local plan = Plan.calculate({
                targets = {
                    { id = 1, item = "MILK_JUG", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "SHELL_BOWL", count = 3, mode = Plan.HAVE },
                },
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

        -- Both Steps make COCONUT_SHELL: COCONUT_MILK makes 3, then COCONUT_FLESH makes 2. The Plan uses 2.
        -- From the first Steps, each Step has a Leftover: 1 and 2. From the last Steps, only COCONUT_MILK has one: 3.
        it("takes the used part of an other Output from the first Steps in production order", function()
            local plan = Plan.calculate({
                targets = {
                    { id = 1, item = "COCONUT_MILK", count = 3, mode = Plan.HAVE },
                    { id = 2, item = "COCONUT_FLESH", count = 4, mode = Plan.HAVE },
                    { id = 3, item = "SHELL_BOWL", count = 2, mode = Plan.HAVE },
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
                { { item = "COCONUT_SHELL", count = 1 }, { item = "COCONUT_SHELL", count = 2 } }
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

    it("ignores a Reserve of an item that the Plan does not use", function()
        local plan = bakeBread({ DOUGH = 3 }, nil, { COAL = 10 })

        expectEqual(plan, bakeBread({ DOUGH = 3 }))
    end)

    it("adds the part of a Reserve that the player does not have to the Shortage", function()
        local plan = bakeBread({}, nil, { DOUGH = 2 })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 5 } })
    end)

    it("gives each Target with its Counted stock", function()
        local plan = bakeBread({ BREAD = 3 }, { BREAD = 1 })

        expectEqual(plan.targets, { { id = 1, item = "BREAD", mode = Plan.HAVE, count = 5, have = 4 } })
    end)

    it("is Complete when Counted stock covers each Target", function()
        local plan = bakeBread({ BREAD = 5 })

        expectEqual(plan.complete, true)
    end)

    it("is not Complete when Counted stock does not cover a Target", function()
        local plan = Plan.calculate({
            targets = {
                { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE },
                { id = 2, item = "CAKE", count = 1, mode = Plan.HAVE },
            },
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
            targets = {
                { id = 1, item = "B", count = 2, mode = Plan.HAVE },
                { id = 2, item = "C", count = 3, mode = Plan.HAVE },
            },
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
            targets = { { id = 1, item = "D", count = 1, mode = Plan.HAVE } },
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
            targets = { { id = 1, item = "D", count = 1, mode = Plan.HAVE } },
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
            targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
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
            targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
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
            targets = {
                { id = 1, item = "CAKE", count = 1, mode = Plan.HAVE },
                { id = 2, item = "BREAD", count = 1, mode = Plan.HAVE },
            },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(plan.shortages, { { item = "DOUGH", count = 1 }, { item = "CAKE", count = 1 } })
    end)

    it("lists Leftovers in the order of the Step that makes them", function()
        local plan = Plan.calculate({
            targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE } },
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
            targets = { { id = 1, item = "SUPER_RESTORE", count = 1, mode = Plan.HAVE } },
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
            targets = { { id = 1, item = "TROLL_POTION", count = 1, mode = Plan.HAVE } },
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

    -- This is the interim behaviour in issue 7.
    it("stops with an error that names the items in a Loop", function()
        local ok, err = pcall(Plan.calculate, {
            targets = { { id = 1, item = "BUCKET_OF_WATER", count = 5, mode = Plan.HAVE } },
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
        expectEqual(err, "The Plan cannot calculate a Loop: BUCKET_OF_WATER, BUCKET, BUCKET_OF_WATER.")
    end)

    it("gives the line of the caller in a Loop error", function()
        local ok, err = pcall(function()
            Plan.calculate({
                targets = { { id = 1, item = "BUCKET_OF_WATER", count = 5, mode = Plan.HAVE } },
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
        end)

        expectEqual(ok, false)
        expectEqual(type(err), "string")
        expectEqual(err:find("calculate_spec.lua:%d+: The Plan cannot calculate a Loop: ") ~= nil, true)
    end)

    -- Each Recipe must have an Action limit (issue 2, section 1).
    it("stops with an error that names the item when its Recipe has no Action limit", function()
        local ok, err = pcall(Plan.calculate, {
            targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(ok, false)
        expectEqual(err, "The Recipe for BREAD has no Action limit.")
    end)

    -- The check does not depend on stock. Thus a data error shows at once, not later in a session.
    it("stops with an error when stock covers an item whose Recipe has no Action limit", function()
        local ok, err = pcall(Plan.calculate, {
            targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, inputs = { { item = "DOUGH", count = 1 } } } },
            },
            detected = { BREAD = 1 },
        })

        expectEqual(ok, false)
        expectEqual(err, "The Recipe for BREAD has no Action limit.")
    end)

    it("gives the line of the caller in a Recipe error", function()
        local ok, err = pcall(function()
            Plan.calculate({
                targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
                recipes = {
                    BREAD = { { verb = "Bake", output = 1, inputs = { { item = "DOUGH", count = 1 } } } },
                },
                detected = {},
            })
        end)

        expectEqual(ok, false)
        expectEqual(type(err), "string")
        expectEqual(err:find("calculate_spec.lua:%d+: The Recipe for BREAD has no Action limit%.") ~= nil, true)
    end)

    -- The check covers only the Recipes that the Plan uses (issue 2, section 1).
    it("does not stop when a Recipe that the Plan does not use has no Action limit", function()
        local ok = pcall(Plan.calculate, {
            targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
            recipes = {
                BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
                CAKE = { { verb = "Bake", output = 1, inputs = { { item = "BATTER", count = 1 } } } },
            },
            detected = {},
        })

        expectEqual(ok, true)
    end)

    describe("Basis check", function()
        local function breadBasis()
            return {
                targets = { { id = 1, item = "BREAD", count = 1, mode = Plan.HAVE } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                detected = {},
            }
        end

        local function errorOf(basis)
            local ok, err = pcall(Plan.calculate, basis)
            expectEqual(ok, false)
            return err
        end

        -- A typo in the Target mode must not give a Plan in Have (issue 14).
        it("stops with an error that names an unknown Target mode and its item", function()
            local basis = breadBasis()
            basis.targets[1].mode = "MAKES"

            expectEqual(errorOf(basis), "The Target mode MAKES of BREAD is unknown.")
        end)

        it("stops with an error for a Target with no Target mode", function()
            local basis = breadBasis()
            basis.targets[1].mode = nil

            expectEqual(errorOf(basis), "The Target mode nil of BREAD is unknown.")
        end)

        -- Each caller must give each required field (issue 14).
        for _, field in ipairs({ "targets", "recipes", "detected" }) do
            it("stops with an error when the Basis has no " .. field, function()
                local basis = breadBasis()
                basis[field] = nil

                expectEqual(errorOf(basis), "The Basis has no " .. field .. ".")
            end)
        end

        it("gives the line of the caller in the error", function()
            local basis = breadBasis()
            basis.detected = nil
            local ok, err = pcall(function()
                Plan.calculate(basis)
            end)

            expectEqual(ok, false)
            expectEqual(err:find("calculate_spec.lua:%d+: The Basis has no detected%.") ~= nil, true)
        end)

        -- The diff matches the Target lines by id (issue 28).
        for _, case in ipairs({
            { name = "no id", id = nil },
            { name = "an id of 0", id = 0 },
            { name = "an id that is a fraction", id = 1.5 },
            { name = "an id that is NaN", id = 0 / 0 },
            { name = "an id that is a string", id = "a" },
        }) do
            it("stops with an error for a Target with " .. case.name, function()
                local basis = breadBasis()
                basis.targets[1].id = case.id

                expectEqual(errorOf(basis), "The Target id of BREAD must be a whole number more than 0.")
            end)
        end

        it("stops with an error when two Targets have the same id", function()
            local basis = breadBasis()
            basis.targets[2] = { id = 1, item = "CAKE", count = 1, mode = Plan.HAVE }

            expectEqual(errorOf(basis), "Two Targets have the id 1.")
        end)

        it("accepts two Targets for the same item with different ids", function()
            local basis = breadBasis()
            basis.targets[2] = { id = 2, item = "BREAD", count = 2, mode = Plan.HAVE }

            expectEqual(#Plan.calculate(basis).targets, 2)
        end)

        -- The player types the Target count. A bad count is a fault in the view (issue 43).
        for _, case in ipairs({
            { name = "0", count = 0 },
            { name = "-5", count = -5 },
            { name = "2.5", count = 2.5 },
            { name = "nil", count = nil },
            { name = 'the string "5"', count = "5" },
        }) do
            it("stops with an error for a Target count of " .. case.name, function()
                local basis = breadBasis()
                basis.targets[1].count = case.count

                expectEqual(errorOf(basis), "The Target count of BREAD must be a whole number more than 0.")
            end)
        end

        it("checks the count of each Target, not only the first", function()
            local basis = breadBasis()
            basis.targets[2] = { id = 2, item = "CAKE", count = 0, mode = Plan.HAVE }

            expectEqual(errorOf(basis), "The Target count of CAKE must be a whole number more than 0.")
        end)

        it("gives the line of the caller in a Target count error", function()
            local basis = breadBasis()
            basis.targets[1].count = 0
            local ok, err = pcall(function()
                Plan.calculate(basis)
            end)

            expectEqual(ok, false)
            expectEqual(err:find("calculate_spec.lua:%d+: The Target count of BREAD") ~= nil, true)
        end)

        for _, case in ipairs({
            { name = "-1", made = -1 },
            { name = "2.5", made = 2.5 },
            { name = "nil", made = nil },
            { name = 'the string "3"', made = "3" },
        }) do
            it("stops with an error for a Made count of " .. case.name .. " in a Make Target", function()
                local basis = breadBasis()
                basis.targets[1].mode = Plan.MAKE
                basis.targets[1].made = case.made

                expectEqual(errorOf(basis), "The Made count of BREAD must be a whole number of 0 or more.")
            end)
        end

        it("accepts a Made count of 0 in a Make Target", function()
            local basis = breadBasis()
            basis.targets[1].mode = Plan.MAKE
            basis.targets[1].made = 0

            expectEqual(#Plan.calculate(basis).targets, 1)
        end)

        it("stops with an error for a Made count in a Have Target", function()
            local basis = breadBasis()
            basis.targets[1].made = 0

            expectEqual(errorOf(basis), "A Have Target of BREAD has a Made count.")
        end)
    end)

    describe("Batch hint", function()
        local function batchHint(inputs, actionLimit, stackable)
            local plan = Plan.calculate({
                targets = { { id = 1, item = "POTION", count = 100, mode = Plan.HAVE } },
                recipes = {
                    POTION = { { verb = "Mix", output = 1, inputs = inputs, actionLimit = actionLimit or 60 } },
                },
                detected = {},
                stackable = stackable,
            })
            return plan.steps[1].batchHint
        end

        it("divides the Inventory by the non-stackable Inputs of one action", function()
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

        it("uses the Action limit when it is lower than the Inventory space", function()
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

        it("gives each Input for one full Inventory, with its Detected stock", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "POTION", count = 100, mode = Plan.HAVE } },
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

        it("is nil when one action needs more non-stackable Input than the Inventory holds", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "STATUE", count = 1, mode = Plan.HAVE } },
                recipes = {
                    STATUE = {
                        { verb = "Carve", output = 1, actionLimit = 60, inputs = { { item = "CLAY", count = 29 } } },
                    },
                },
                detected = {},
            })

            expectEqual(plan.steps[1].batchHint, nil)
            expectEqual(plan.steps[1].inputs, { { item = "CLAY", detected = 0 } })
        end)

        it("is nil when the stackable Inputs need more slots than the Inventory holds", function()
            local inputs, stackable = {}, {}
            for index = 1, 29 do
                local item = "RUNE_" .. index
                inputs[index] = { item = item, count = 1 }
                stackable[item] = true
            end

            expectEqual(batchHint(inputs, 60, stackable), nil)
        end)

        it("is nil when the stackable Inputs leave no slot for the non-stackable Inputs", function()
            local inputs, stackable = { { item = "GRIMY_RANARR", count = 1 } }, {}
            for index = 1, 28 do
                local item = "RUNE_" .. index
                inputs[#inputs + 1] = { item = item, count = 1 }
                stackable[item] = true
            end

            expectEqual(batchHint(inputs, 60, stackable), nil)
        end)
    end)

    describe("Next step", function()
        -- Two Targets that do not depend on each other. Each Step needs 1 Input for each action.
        local function twoSteps(stock)
            stock.targets = {
                { id = 1, item = "CLEAN_RANARR", count = 28, mode = Plan.HAVE },
                { id = 2, item = "CLEAN_TOADFLAX", count = 28, mode = Plan.HAVE },
            }
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

        it("is the first Step with Detected stock for one full Inventory of each Input", function()
            local plan = twoSteps({ detected = { GRIMY_RANARR = 27, GRIMY_TOADFLAX = 28 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_TOADFLAX")
        end)

        it("is the first ready Step in production order when more than one is ready", function()
            local plan = twoSteps({ detected = { GRIMY_RANARR = 28, GRIMY_TOADFLAX = 28 } })

            expectEqual(plan.steps[plan.next].item, "CLEAN_RANARR")
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

        -- One action needs 29 Clay. Thus the Step has no Batch hint.
        local function carveStatues(detected)
            return Plan.calculate({
                targets = { { id = 1, item = "STATUE", count = 2, mode = Plan.HAVE } },
                recipes = {
                    STATUE = {
                        { verb = "Carve", output = 1, actionLimit = 60, inputs = { { item = "CLAY", count = 29 } } },
                    },
                },
                detected = detected,
            })
        end

        it("needs all remaining actions when the Step has no Batch hint", function()
            local plan = carveStatues({ CLAY = 58 })

            expectEqual(plan.next, 1)
        end)

        it("is not a Step with no Batch hint and too few Inputs for all remaining actions", function()
            local plan = carveStatues({ CLAY = 57 })

            expectEqual(plan.next, nil)
        end)

        it("is not a Flagged step", function()
            local plan = Plan.calculate({
                targets = {
                    { id = 1, item = "CLEAN_RANARR", count = 28, mode = Plan.HAVE },
                    { id = 2, item = "CLEAN_TOADFLAX", count = 28, mode = Plan.HAVE },
                },
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
                targets = {
                    { id = 1, item = "SUPER_RESTORE", count = 14, mode = Plan.HAVE },
                    { id = 2, item = "CLEAN_TOADFLAX", count = 28, mode = Plan.HAVE },
                },
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
                targets = { { id = 1, item = "SUPER_RESTORE", count = 1, mode = Plan.HAVE } },
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
                targets = { { id = 1, item = "SUPER_RESTORE", count = 1, mode = Plan.HAVE } },
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
                targets = {
                    { id = 1, item = "SUPER_RESTORE", count = 1, mode = Plan.HAVE },
                    { id = 2, item = "OTHER_POTION", count = 1, mode = Plan.HAVE },
                },
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
                targets = { { id = 1, item = "SUPER_RESTORE_4", count = 1, mode = Plan.HAVE } },
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
                targets = {
                    { id = 1, item = "SUPER_RESTORE", count = 1, mode = Plan.HAVE },
                    { id = 2, item = "OTHER_POTION", count = 1, mode = Plan.HAVE },
                },
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
                targets = { { id = 1, item = "D", count = 1, mode = Plan.HAVE } },
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
                targets = {
                    { id = 1, item = "SHARK", count = 10, mode = Plan.HAVE },
                    { id = 2, item = "SHARK_SOUP", count = 4, mode = Plan.HAVE },
                },
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
                targets = { { id = 1, item = "SUPER_RESTORE_FLASK", count = 1, mode = Plan.HAVE } },
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
                targets = { { id = 1, item = "SUPER_RESTORE_FLASK", count = 1, mode = Plan.HAVE } },
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

    it("gives a Have Target line with no Made count", function()
        local plan = bakeBread({ BREAD = 2, DOUGH = 10 })

        expectEqual(plan.targets[1].made, nil)
    end)

    describe("Target mode Make", function()
        local function makeBread(made, detected)
            return Plan.calculate({
                targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.MAKE, made = made } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                detected = detected,
            })
        end

        it("makes the Target minus its Made count, even with Counted stock of the Target", function()
            local plan = makeBread(1, { BREAD = 10, DOUGH = 10 })

            expectEqual(stepFor(plan, "BREAD").actions, 2)
        end)

        it("uses the largest remaining quantity of two Make Targets for the same item", function()
            local function plan(madeA, madeB)
                return Plan.calculate({
                    targets = {
                        { id = 1, item = "BREAD", count = 100, mode = Plan.MAKE, made = madeA },
                        { id = 2, item = "BREAD", count = 25, mode = Plan.MAKE, made = madeB },
                    },
                    recipes = {
                        BREAD = {
                            { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                        },
                    },
                    detected = { DOUGH = 100 },
                })
            end

            expectEqual(stepFor(plan(20, 14), "BREAD").actions, 80)
            expectEqual(stepFor(plan(90, 0), "BREAD").actions, 25)
            expectEqual(plan(99, 25).complete, false)
            expectEqual(plan(100, 25).complete, true)
        end)

        it("does not add a Reserve of the Target to its need", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.MAKE, made = 0 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                },
                detected = { DOUGH = 10 },
                reserves = { BREAD = 10 },
            })

            expectEqual(stepFor(plan, "BREAD").actions, 5)
        end)

        it("decreases the demand for Intermediates and Raw materials by their Counted stock", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "BREAD", count = 5, mode = Plan.MAKE, made = 0 } },
                recipes = {
                    BREAD = {
                        { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } },
                    },
                    DOUGH = {
                        { verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "FLOUR", count = 1 } } },
                    },
                },
                detected = { DOUGH = 2, FLOUR = 1 },
            })

            expectEqual(stepFor(plan, "DOUGH").actions, 3)
            expectEqual(plan.shortages, { { item = "FLOUR", count = 2 } })
        end)

        it("is Complete when the Made count covers each Target", function()
            local plan = makeBread(5, {})

            expectEqual(plan.complete, true)
        end)

        it("is not Complete when only Counted stock covers a Target", function()
            local plan = makeBread(4, { BREAD = 5 })

            expectEqual(plan.complete, false)
        end)

        it("gives each Target with its raw Made count and its Counted stock", function()
            local plan = makeBread(7, { BREAD = 2 })

            expectEqual(plan.targets, { { id = 1, item = "BREAD", mode = Plan.MAKE, count = 5, made = 7, have = 2 } })
        end)

        describe("a Target item that is also an Intermediate", function()
            local function makeSharkAndSoup(made, detected)
                return Plan.calculate({
                    targets = {
                        { id = 1, item = "SHARK", count = 10, mode = Plan.MAKE, made = made },
                        { id = 2, item = "SHARK_SOUP", count = 4, mode = Plan.MAKE, made = 0 },
                    },
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
                    detected = detected,
                })
            end

            -- The soup can use the Shark that the Make Target counts (ADR 0012).
            it("makes the larger of the Make need and the need of the Steps, not the sum", function()
                local plan = makeSharkAndSoup(0, {})

                expectEqual(stepFor(plan, "SHARK").actions, 10)
            end)

            it("uses the Make need when it is larger", function()
                local plan = makeSharkAndSoup(3, { SHARK = 1 })

                expectEqual(stepFor(plan, "SHARK").actions, 7)
            end)

            it("uses the need of the Steps when the Made count covers the Target", function()
                local plan = makeSharkAndSoup(12, {})

                expectEqual(stepFor(plan, "SHARK").actions, 4)
            end)

            it("does not let spare Counted stock cover the Make need", function()
                local plan = makeSharkAndSoup(3, { SHARK = 10 })

                expectEqual(stepFor(plan, "SHARK").actions, 7)
            end)

            it("lets the same items count in the Made count and in Counted stock", function()
                local plan = makeSharkAndSoup(10, { SHARK = 10 })

                expectEqual(stepFor(plan, "SHARK"), nil)
            end)
        end)
    end)

    describe("Have and Make Targets together", function()
        local recipes = {
            BREAD = { { verb = "Bake", output = 1, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
            SANDWICH = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "BREAD", count = 1 } } } },
        }

        local function breadPlan(targets, detected, reserves)
            return Plan.calculate({ targets = targets, recipes = recipes, detected = detected, reserves = reserves })
        end

        it("makes the Make need when it is larger than the Have need", function()
            local plan = breadPlan({
                { id = 1, item = "BREAD", count = 10, mode = Plan.HAVE },
                { id = 2, item = "BREAD", count = 100, mode = Plan.MAKE, made = 30 },
            }, { BREAD = 15, DOUGH = 100 })

            expectEqual(stepFor(plan, "BREAD").actions, 70)
        end)

        it("makes the Have need when it is larger than the Make need", function()
            local plan = breadPlan({
                { id = 1, item = "BREAD", count = 20, mode = Plan.HAVE },
                { id = 2, item = "BREAD", count = 10, mode = Plan.MAKE, made = 8 },
            }, { BREAD = 5, DOUGH = 100 })

            expectEqual(stepFor(plan, "BREAD").actions, 15)
        end)

        it("adds a Reserve to the Have need", function()
            local targets = {
                { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE },
                { id = 2, item = "BREAD", count = 5, mode = Plan.MAKE, made = 0 },
            }

            expectEqual(stepFor(breadPlan(targets, { DOUGH = 100 }), "BREAD").actions, 5)
            expectEqual(stepFor(breadPlan(targets, { DOUGH = 100 }, { BREAD = 3 }), "BREAD").actions, 8)
        end)

        -- The example of ADR 0012, at its end. The ids 1 to 6 are the Targets a to f.
        local function examplePlan()
            return breadPlan({
                { id = 1, item = "BREAD", count = 100, mode = Plan.MAKE, made = 20 },
                { id = 2, item = "BREAD", count = 10, mode = Plan.MAKE, made = 20 },
                { id = 3, item = "SANDWICH", count = 5, mode = Plan.HAVE },
                { id = 4, item = "BREAD", count = 25, mode = Plan.MAKE, made = 14 },
                { id = 5, item = "SANDWICH", count = 3, mode = Plan.MAKE, made = 2 },
                { id = 6, item = "BREAD", count = 50, mode = Plan.HAVE },
            }, { BREAD = 15, SANDWICH = 4, DOUGH = 100 })
        end

        it("makes the need of each item in the example of ADR 0012", function()
            local plan = examplePlan()

            expectEqual(stepFor(plan, "SANDWICH").actions, 1)
            expectEqual(stepFor(plan, "BREAD").actions, 80)
        end)

        it("gives one Target line for each Target, in the order of the Targets", function()
            local plan = examplePlan()

            expectEqual(plan.targets, {
                { id = 1, item = "BREAD", mode = Plan.MAKE, count = 100, made = 20, have = 15 },
                { id = 2, item = "BREAD", mode = Plan.MAKE, count = 10, made = 20, have = 15 },
                { id = 3, item = "SANDWICH", mode = Plan.HAVE, count = 5, have = 4 },
                { id = 4, item = "BREAD", mode = Plan.MAKE, count = 25, made = 14, have = 15 },
                { id = 5, item = "SANDWICH", mode = Plan.MAKE, count = 3, made = 2, have = 4 },
                { id = 6, item = "BREAD", mode = Plan.HAVE, count = 50, have = 15 },
            })
        end)

        it("is not Complete when a Have Target is not met, even when each Make Target is met", function()
            local plan = breadPlan({
                { id = 1, item = "BREAD", count = 5, mode = Plan.MAKE, made = 5 },
                { id = 2, item = "SANDWICH", count = 5, mode = Plan.HAVE },
            }, { SANDWICH = 4 })

            expectEqual(plan.complete, false)
        end)

        it("is Complete when each Target is met", function()
            local plan = breadPlan({
                { id = 1, item = "BREAD", count = 5, mode = Plan.MAKE, made = 5 },
                { id = 2, item = "SANDWICH", count = 5, mode = Plan.HAVE },
            }, { SANDWICH = 5 })

            expectEqual(plan.complete, true)
        end)
    end)

    describe("Dose pools", function()
        local restorePool = {
            SUPER_RESTORE = {
                [1] = "SUPER_RESTORE_1",
                [2] = "SUPER_RESTORE_2",
                [3] = "SUPER_RESTORE_3",
                [4] = "SUPER_RESTORE_4",
            },
        }

        it("decants other Dose sizes to the Dose size of a Target", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "SUPER_RESTORE_4", count = 3, mode = Plan.HAVE } },
                recipes = {},
                pools = restorePool,
                detected = { SUPER_RESTORE_3 = 4 },
            })

            expectEqual(plan.steps, {
                {
                    item = "SUPER_RESTORE_4",
                    verb = "Decant",
                    actions = 3,
                    flags = {},
                    inputs = { { item = "SUPER_RESTORE_3", count = 4, detected = 4 } },
                },
            })
            expectEqual(plan.shortages, {})
            expectEqual(plan.leftovers, {})
            expectEqual(plan.assumptions, { "The Plan assumes that you have the empty vials to decant." })
            expectEqual(plan.complete, false)
        end)

        it("makes doses with the Recipe of one Dose size, then decants them to the Dose size of a Target", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "SUPER_RESTORE_4", count = 3, mode = Plan.HAVE } },
                recipes = {
                    SUPER_RESTORE_3 = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 14,
                            inputs = {
                                { item = "SNAPDRAGON_UNF", count = 1 },
                                { item = "RED_SPIDERS_EGGS", count = 1 },
                            },
                        },
                    },
                },
                pools = restorePool,
                detected = { SNAPDRAGON_UNF = 4, RED_SPIDERS_EGGS = 4 },
            })

            expectEqual(#plan.steps, 2)
            expectEqual(plan.steps[1].item, "SUPER_RESTORE_3")
            expectEqual(plan.steps[1].verb, "Mix")
            expectEqual(plan.steps[1].actions, 4)
            expectEqual(plan.steps[2], {
                item = "SUPER_RESTORE_4",
                verb = "Decant",
                actions = 3,
                flags = {},
                inputs = { { item = "SUPER_RESTORE_3", count = 4, detected = 0 } },
            })
            expectEqual(plan.shortages, {})
            expectEqual(plan.leftovers, {})
        end)

        it("uses the Recipe of the smallest Dose size when more than one Dose size has a Recipe", function()
            local function mix(item)
                return { { verb = "Mix", output = 1, actionLimit = 14, inputs = { { item = item, count = 1 } } } }
            end
            local plan = Plan.calculate({
                targets = { { id = 1, item = "SUPER_RESTORE_3", count = 2, mode = Plan.HAVE } },
                recipes = { SUPER_RESTORE_4 = mix("FOUR_DOSE_INPUT"), SUPER_RESTORE_3 = mix("THREE_DOSE_INPUT") },
                pools = restorePool,
                detected = { FOUR_DOSE_INPUT = 2, THREE_DOSE_INPUT = 2 },
            })

            expectEqual(#plan.steps, 1)
            expectEqual(plan.steps[1].item, "SUPER_RESTORE_3")
            expectEqual(plan.steps[1].actions, 2)
        end)

        it("puts the doses that remain after a Decant step in one container, and lists it as a Leftover", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "SUPER_RESTORE_4", count = 1, mode = Plan.HAVE } },
                recipes = {},
                pools = restorePool,
                detected = { SUPER_RESTORE_1 = 2, SUPER_RESTORE_3 = 3 },
            })

            expectEqual(plan.steps[1].inputs, {
                { item = "SUPER_RESTORE_1", count = 2, detected = 2 },
                { item = "SUPER_RESTORE_3", count = 1, detected = 3 },
            })
            expectEqual(plan.leftovers, { { item = "SUPER_RESTORE_1", count = 1 } })
        end)

        it("lists the made containers that the Plan does not use as a Leftover", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "SUPER_RESTORE_3", count = 1, mode = Plan.HAVE } },
                recipes = {
                    SUPER_RESTORE_3 = {
                        {
                            verb = "Mix",
                            output = 2,
                            actionLimit = 14,
                            inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                        },
                    },
                },
                pools = restorePool,
                detected = { SNAPDRAGON_UNF = 1 },
            })

            expectEqual(#plan.steps, 1)
            expectEqual(plan.leftovers, { { item = "SUPER_RESTORE_3", count = 1 } })
        end)

        it("decants for a Recipe Input that names a Dose size, before the Step that uses it", function()
            local plan = Plan.calculate({
                targets = { { id = 1, item = "MIXED_DRINK", count = 3, mode = Plan.HAVE } },
                recipes = {
                    MIXED_DRINK = {
                        {
                            verb = "Mix",
                            output = 1,
                            actionLimit = 14,
                            inputs = { { item = "SUPER_RESTORE_4", count = 1 } },
                        },
                    },
                },
                pools = restorePool,
                detected = { SUPER_RESTORE_3 = 4 },
            })

            expectEqual(#plan.steps, 2)
            expectEqual(plan.steps[1].verb, "Decant")
            expectEqual(plan.steps[1].item, "SUPER_RESTORE_4")
            expectEqual(plan.steps[1].actions, 3)
            expectEqual(plan.steps[2].item, "MIXED_DRINK")
            expectEqual(plan.steps[2].actions, 3)
            expectEqual(plan.next, 1)
            expectEqual(plan.shortages, {})
        end)
    end)
end)
