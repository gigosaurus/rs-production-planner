local GameRecipe = require("plan/gamerecipe")

-- The params of one Obj, as plain values (ADR 0017, docs/recipe-params.md).
-- An OBJ value is a config name. A STRUCT value is a table of the params of the Struct.
-- A missing param has its default value.
describe("GameRecipe.fromParams", function()
    it("gives nothing when the Obj has no recipe params", function()
        local item, recipes = GameRecipe.fromParams("LOGS", {})

        expectEqual(item, nil)
        expectEqual(recipes, nil)
    end)

    it("gives one Recipe for the Obj, with its Inputs", function()
        local item, recipes = GameRecipe.fromParams("RANARR_POTION_UNF", {
            RECIPE_INGREDIENT_TYPE_1 = "RANARR",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_INGREDIENT_TYPE_2 = "VIAL_WATER",
            RECIPE_INGREDIENT_NUMBER_2 = 1,
        })

        expectEqual(item, "RANARR_POTION_UNF")
        expectEqual(recipes, {
            {
                verb = "Make",
                output = 1,
                inputs = { { item = "RANARR", count = 1 }, { item = "VIAL_WATER", count = 1 } },
                skills = {},
                unlocks = {},
            },
        })
    end)

    it("uses the stack size as the output", function()
        local _, recipes = GameRecipe.fromParams("BRONZE_ARROW", {
            RECIPE_INGREDIENT_TYPE_1 = "HEADLESS_ARROW",
            RECIPE_INGREDIENT_NUMBER_1 = 15,
            RECIPE_MAKE_STACK_SIZE = 15,
        })

        expectEqual(recipes[1].output, 15)
        expectEqual(recipes[1].inputs, { { item = "HEADLESS_ARROW", count = 15 } })
    end)

    -- When SCALE_STACK is false, the count is for each output item.
    it("multiplies an Input count by the stack size when the ingredient does not scale with the stack", function()
        local _, recipes = GameRecipe.fromParams("BRONZE_DART", {
            RECIPE_INGREDIENT_TYPE_1 = "BRONZE_DART_TIP",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_INGREDIENT_1_SCALE_STACK = false,
            RECIPE_INGREDIENT_TYPE_2 = "FEATHER",
            RECIPE_INGREDIENT_NUMBER_2 = 10,
            RECIPE_MAKE_STACK_SIZE = 10,
        })

        expectEqual(recipes[1].inputs, { { item = "BRONZE_DART_TIP", count = 10 }, { item = "FEATHER", count = 10 } })
    end)

    it("reads up to 18 ingredients and skips the empty ones", function()
        local _, recipes = GameRecipe.fromParams("BIG_THING", {
            RECIPE_INGREDIENT_TYPE_3 = "PLANK",
            RECIPE_INGREDIENT_NUMBER_3 = 4,
            RECIPE_INGREDIENT_TYPE_18 = "NAILS",
            RECIPE_INGREDIENT_NUMBER_18 = 2,
        })

        expectEqual(recipes[1].inputs, { { item = "PLANK", count = 4 }, { item = "NAILS", count = 2 } })
    end)

    -- Requirement types 1 to 29 follow the order of the stats interface, not SkillType.
    it("gives skill requirements with the SkillType names", function()
        local _, recipes = GameRecipe.fromParams("SUPER_RESTORE_3", {
            RECIPE_INGREDIENT_TYPE_1 = "SNAPDRAGON_POTION_UNF",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_REQUIREMENT_TYPE_1 = 9,
            RECIPE_REQUIREMENT_VALUE_1 = 63,
            RECIPE_REQUIREMENT_TYPE_2 = 6,
            RECIPE_REQUIREMENT_VALUE_2 = 10,
        })

        expectEqual(recipes[1].skills, { { skill = "HERBLORE", level = 63 }, { skill = "HITPOINTS", level = 10 } })
    end)

    it("maps each of the 29 skill codes", function()
        local names = {
            "ATTACK",
            "STRENGTH",
            "RANGED",
            "MAGIC",
            "DEFENCE",
            "HITPOINTS",
            "PRAYER",
            "AGILITY",
            "HERBLORE",
            "THIEVING",
            "CRAFTING",
            "RUNECRAFTING",
            "MINING",
            "SMITHING",
            "FISHING",
            "COOKING",
            "FIREMAKING",
            "WOODCUTTING",
            "FLETCHING",
            "SLAYER",
            "FARMING",
            "CONSTRUCTION",
            "HUNTER",
            "SUMMONING",
            "DUNGEONEERING",
            "DIVINATION",
            "INVENTION",
            "ARCHAEOLOGY",
            "NECROMANCY",
        }
        for code, name in ipairs(names) do
            local _, recipes = GameRecipe.fromParams("X", {
                RECIPE_REQUIREMENT_TYPE_1 = code,
                RECIPE_REQUIREMENT_VALUE_1 = 1,
            })
            expectEqual(recipes[1].skills, { { skill = name, level = 1 } })
        end
    end)

    -- Unlock keys: decision on issue 24, 2026-10-25.
    it("gives Unlock keys with a named prefix", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_REQUIREMENT_TYPE_1 = 61,
            RECIPE_REQUIREMENT_VALUE_1 = 70,
            RECIPE_REQUIREMENT_TYPE_2 = 63,
            RECIPE_REQUIREMENT_VALUE_2 = 70,
            RECIPE_REQUIREMENT_TYPE_3 = 62,
            RECIPE_REQUIREMENT_VALUE_3 = 187,
            RECIPE_REQUIREMENT_TYPE_4 = 64,
            RECIPE_REQUIREMENT_VALUE_4 = 17,
            RECIPE_REQUIREMENT_TYPE_5 = 67,
        })

        expectEqual(recipes[1].unlocks, { "QUEST:70", "BLUEPRINT:70", "UNLOCK62:187", "UNLOCK64:17", "UNLOCK67:0" })
        expectEqual(recipes[1].skills, {})
    end)

    it("gives a requirement type that is not documented as an Unlock", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_REQUIREMENT_TYPE_1 = 65,
            RECIPE_REQUIREMENT_VALUE_1 = 3,
        })

        expectEqual(recipes[1].unlocks, { "UNLOCK65:3" })
    end)

    it("gives the Action time from RECIPE_CYCLES", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_TYPE_1 = "Y",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_CYCLES = 5,
        })

        expectEqual(recipes[1].actionTime, 5)
    end)

    it("gives no Action limit and no other Outputs", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_TYPE_1 = "Y",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_OVERRIDE_STACK_MAKE_LIMIT = 60,
        })

        expectEqual(recipes[1].actionLimit, nil)
        expectEqual(recipes[1].otherOutputs, nil)
    end)

    -- A dummy Obj holds another Recipe for a real item.
    it("gives the real item of a dummy Obj", function()
        local item, recipes = GameRecipe.fromParams("ARROW_SHAFT_OAK", {
            RECIPE_INGREDIENT_TYPE_1 = "OAK_LOGS",
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_NON_DUMMY_OBJ = "ARROW_SHAFT",
        })

        expectEqual(item, "ARROW_SHAFT")
        expectEqual(#recipes, 1)
    end)

    it("finds a Recipe that has only an ingredient with alternatives", function()
        local item = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_1_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "A",
                RECIPE_INGREDIENT_NUMBER_1 = 1,
            },
        })

        expectEqual(item, "X")
    end)

    -- Alternatives: one Recipe for each combination, in Struct order (issue 24, 2026-10-25).
    it("gives one Recipe for each alternative of an ingredient, in Struct order", function()
        local _, recipes = GameRecipe.fromParams("STEEL_PLATEBODY", {
            RECIPE_INGREDIENT_1_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "SMITHING_HOPPER_DUMMY",
                RECIPE_INGREDIENT_NUMBER_1 = 5,
                RECIPE_INGREDIENT_TYPE_2 = "STEEL_BAR",
                RECIPE_INGREDIENT_NUMBER_2 = 5,
            },
            RECIPE_INGREDIENT_TYPE_2 = "HAMMER_HEAD",
            RECIPE_INGREDIENT_NUMBER_2 = 1,
        })

        expectEqual(#recipes, 2)
        expectEqual(recipes[1].inputs, {
            { item = "SMITHING_HOPPER_DUMMY", count = 5 },
            { item = "HAMMER_HEAD", count = 1 },
        })
        expectEqual(recipes[2].inputs, { { item = "STEEL_BAR", count = 5 }, { item = "HAMMER_HEAD", count = 1 } })
    end)

    it("gives one Recipe for each combination of alternatives", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_1_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "A1",
                RECIPE_INGREDIENT_NUMBER_1 = 1,
                RECIPE_INGREDIENT_TYPE_2 = "A2",
                RECIPE_INGREDIENT_NUMBER_2 = 1,
            },
            RECIPE_INGREDIENT_2_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "B1",
                RECIPE_INGREDIENT_NUMBER_1 = 2,
                RECIPE_INGREDIENT_TYPE_2 = "B2",
                RECIPE_INGREDIENT_NUMBER_2 = 3,
            },
        })

        local inputs = {}
        for i, recipe in ipairs(recipes) do
            inputs[i] = recipe.inputs
        end
        expectEqual(inputs, {
            { { item = "A1", count = 1 }, { item = "B1", count = 2 } },
            { { item = "A1", count = 1 }, { item = "B2", count = 3 } },
            { { item = "A2", count = 1 }, { item = "B1", count = 2 } },
            { { item = "A2", count = 1 }, { item = "B2", count = 3 } },
        })
    end)

    it("multiplies an alternative count by the stack size when the ingredient does not scale with the stack", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_1_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "A",
                RECIPE_INGREDIENT_NUMBER_1 = 1,
            },
            RECIPE_INGREDIENT_1_SCALE_STACK = false,
            RECIPE_MAKE_STACK_SIZE = 10,
        })

        expectEqual(recipes[1].inputs, { { item = "A", count = 10 } })
    end)

    it("gives each alternative Recipe its own tables", function()
        local _, recipes = GameRecipe.fromParams("X", {
            RECIPE_INGREDIENT_1_MULTIPLE = {
                RECIPE_INGREDIENT_TYPE_1 = "A1",
                RECIPE_INGREDIENT_NUMBER_1 = 1,
                RECIPE_INGREDIENT_TYPE_2 = "A2",
                RECIPE_INGREDIENT_NUMBER_2 = 1,
            },
            RECIPE_REQUIREMENT_TYPE_1 = 14,
            RECIPE_REQUIREMENT_VALUE_1 = 30,
        })

        expectEqual(recipes[1].skills ~= recipes[2].skills, true)
        expectEqual(recipes[1].unlocks ~= recipes[2].unlocks, true)
    end)
end)
