-- Gives the Recipes of one Obj from its RECIPE_* params (ADR 0017, docs/recipe-params.md).
-- The adapter reads the params and gives them as plain values. Tests run this module outside the game client.
-- An OBJ value is a config name. A STRUCT value is a table of the params of the Struct.
-- A missing param has its default value.

local GameRecipe = {}

local MAX_INGREDIENTS = 18
local MAX_REQUIREMENTS = 5

-- Requirement types 1 to 29 follow the order of the stats interface, not SkillType.
local SKILLS = {
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

-- Unlock keys have a named prefix (issue 24, 2026-10-25). All other types are UNLOCK<type>.
local UNLOCK_PREFIXES = { [61] = "QUEST", [63] = "BLUEPRINT" }

-- Gives the alternatives of a Struct, in Struct order.
local function alternativesOf(struct)
    local alternatives = {}
    for n = 1, MAX_INGREDIENTS do
        local item = struct["RECIPE_INGREDIENT_TYPE_" .. n]
        if item ~= nil then
            alternatives[#alternatives + 1] = { item = item, count = struct["RECIPE_INGREDIENT_NUMBER_" .. n] or 0 }
        end
    end
    return alternatives
end

-- Gives a list of ingredients. Each ingredient is a list of its alternatives.
-- When SCALE_STACK is false, the count is for each output item.
local function ingredientsOf(params, output)
    local ingredients = {}
    for n = 1, MAX_INGREDIENTS do
        local multiple = params["RECIPE_INGREDIENT_" .. n .. "_MULTIPLE"]
        local alternatives
        if multiple ~= nil then
            alternatives = alternativesOf(multiple)
        elseif params["RECIPE_INGREDIENT_TYPE_" .. n] ~= nil then
            alternatives = {
                {
                    item = params["RECIPE_INGREDIENT_TYPE_" .. n],
                    count = params["RECIPE_INGREDIENT_NUMBER_" .. n] or 0,
                },
            }
        end
        if alternatives then
            local scale = params["RECIPE_INGREDIENT_" .. n .. "_SCALE_STACK"] == false and output or 1
            for _, alternative in ipairs(alternatives) do
                alternative.count = alternative.count * scale
            end
            ingredients[#ingredients + 1] = alternatives
        end
    end
    return ingredients
end

-- Gives one list of Inputs for each combination of alternatives.
local function combinationsOf(ingredients)
    local combinations = { {} }
    for _, alternatives in ipairs(ingredients) do
        local next = {}
        for _, inputs in ipairs(combinations) do
            for _, alternative in ipairs(alternatives) do
                local copy = { table.unpack(inputs) }
                copy[#copy + 1] = { item = alternative.item, count = alternative.count }
                next[#next + 1] = copy
            end
        end
        combinations = next
    end
    return combinations
end

local function requirementsOf(params)
    local skills, unlocks = {}, {}
    for n = 1, MAX_REQUIREMENTS do
        local requirementType = params["RECIPE_REQUIREMENT_TYPE_" .. n] or 0
        local value = params["RECIPE_REQUIREMENT_VALUE_" .. n] or 0
        if SKILLS[requirementType] then
            skills[#skills + 1] = { skill = SKILLS[requirementType], level = value }
        elseif requirementType ~= 0 then
            local prefix = UNLOCK_PREFIXES[requirementType] or ("UNLOCK" .. requirementType)
            unlocks[#unlocks + 1] = prefix .. ":" .. value
        end
    end
    return skills, unlocks
end

local function copyList(list)
    local copy = {}
    for i, entry in ipairs(list) do
        copy[i] = entry
    end
    return copy
end

-- Gives the item and its Recipes, or nil when the Obj has no recipe params.
-- A dummy Obj gives the real item that RECIPE_NON_DUMMY_OBJ names.
function GameRecipe.fromParams(configName, params)
    local output = params.RECIPE_MAKE_STACK_SIZE or 1
    local ingredients = ingredientsOf(params, output)
    local skills, unlocks = requirementsOf(params)
    if #ingredients == 0 and #skills == 0 and #unlocks == 0 then
        return nil
    end
    local cycles = params.RECIPE_CYCLES or 0
    local recipes = {}
    for _, inputs in ipairs(combinationsOf(ingredients)) do
        recipes[#recipes + 1] = {
            verb = "Make",
            output = output,
            inputs = inputs,
            skills = copyList(skills),
            unlocks = copyList(unlocks),
            actionTime = cycles > 0 and cycles or nil,
        }
    end
    return params.RECIPE_NON_DUMMY_OBJ or configName, recipes
end

return GameRecipe
