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

describe("GameRecipe.newIndex", function()
    local function recipeParams(input)
        return { RECIPE_INGREDIENT_TYPE_1 = input, RECIPE_INGREDIENT_NUMBER_1 = 1 }
    end

    local function dummyParams(input, item)
        local params = recipeParams(input)
        params.RECIPE_NON_DUMMY_OBJ = item
        return params
    end

    local function firstInputs(recipes)
        local items = {}
        for i, recipe in ipairs(recipes) do
            items[i] = recipe.inputs[1].item
        end
        return items
    end

    it("gives the Recipes of each item", function()
        local index = GameRecipe.newIndex()
        index:add("RANARR", recipeParams("GRIMY_RANARR"))
        index:add("LOGS", {})

        local recipes = index:recipes()

        expectEqual(firstInputs(recipes.RANARR), { "GRIMY_RANARR" })
        expectEqual(recipes.LOGS, nil)
    end)

    -- Order: decision on issue 24, 2026-10-25.
    it("puts the Recipes of the item's own Obj before the Recipes of dummy Objs", function()
        local index = GameRecipe.newIndex()
        index:add("ARROW_SHAFT_OAK", dummyParams("OAK_LOGS", "ARROW_SHAFT"))
        index:add("ARROW_SHAFT", recipeParams("LOGS"))

        expectEqual(firstInputs(index:recipes().ARROW_SHAFT), { "LOGS", "OAK_LOGS" })
    end)

    it("keeps the dummy Objs in the order that they were added", function()
        local index = GameRecipe.newIndex()
        index:add("ARROW_SHAFT_OAK", dummyParams("OAK_LOGS", "ARROW_SHAFT"))
        index:add("ARROW_SHAFT_WILLOW", dummyParams("WILLOW_LOGS", "ARROW_SHAFT"))
        index:add("ARROW_SHAFT_MAPLE", dummyParams("MAPLE_LOGS", "ARROW_SHAFT"))

        expectEqual(firstInputs(index:recipes().ARROW_SHAFT), { "OAK_LOGS", "WILLOW_LOGS", "MAPLE_LOGS" })
    end)

    it("gives an item with only dummy Recipes", function()
        local index = GameRecipe.newIndex()
        index:add("ARROW_SHAFT_OAK", dummyParams("OAK_LOGS", "ARROW_SHAFT"))

        expectEqual(firstInputs(index:recipes().ARROW_SHAFT), { "OAK_LOGS" })
    end)
end)

-- The scan reads the Objs in parts, so that one call stays short.
describe("GameRecipe.newScan", function()
    local objs = {
        [0] = { "GRIMY_RANARR", {} },
        [1] = { "RANARR", { RECIPE_INGREDIENT_TYPE_1 = "GRIMY_RANARR", RECIPE_INGREDIENT_NUMBER_1 = 1 } },
        [3] = { "VIAL_WATER", { RECIPE_INGREDIENT_TYPE_1 = "VIAL", RECIPE_INGREDIENT_NUMBER_1 = 1 } },
    }

    -- Gives the config name and the params of an Obj id, or nil when the id has no Obj.
    local function read(id)
        local obj = objs[id]
        if obj then
            return obj[1], obj[2]
        end
    end

    local function recordingRead(readIDs)
        return function(id)
            readIDs[#readIDs + 1] = id
            return read(id)
        end
    end

    it("reads the given number of Obj ids in each part, from id 0", function()
        local readIDs = {}
        local scan = GameRecipe.newScan(recordingRead(readIDs), 3)

        scan:step(2)

        expectEqual(readIDs, { 0, 1 })
    end)

    it("is not done until it has read the last Obj id", function()
        local scan = GameRecipe.newScan(read, 3)

        expectEqual(scan:step(3), false)
        expectEqual(scan:step(1), true)
    end)

    it("gives the Recipes when it is done", function()
        local scan = GameRecipe.newScan(read, 3)
        scan:step(10)

        local recipes = scan:recipes()

        expectEqual(recipes.RANARR[1].inputs, { { item = "GRIMY_RANARR", count = 1 } })
        expectEqual(recipes.VIAL_WATER[1].inputs, { { item = "VIAL", count = 1 } })
        expectEqual(recipes.GRIMY_RANARR, nil)
    end)

    it("gives no Recipes before it is done", function()
        local scan = GameRecipe.newScan(read, 3)
        scan:step(2)

        expectEqual(scan:recipes(), nil)
    end)

    it("reads no more ids after it is done", function()
        local readIDs = {}
        local scan = GameRecipe.newScan(recordingRead(readIDs), 1)
        scan:step(5)
        scan:step(5)

        expectEqual(readIDs, { 0, 1 })
    end)
end)
