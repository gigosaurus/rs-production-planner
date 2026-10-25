-- Gives the Recipes of one Obj from its RECIPE_* params (ADR 0017, docs/recipe-params.md).
-- The adapter reads the params and gives them as plain values. Tests run this module outside the game client.
-- An OBJ value is a config name. A STRUCT value is a table of the params of the Struct.
-- A missing param has its default value.

local GameRecipe = {}

local MAX_INGREDIENTS = 18
local MAX_REQUIREMENTS = 5
local MAX_XP = 2

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

-- Gives the XP of one action. The value is XP x 10, with the skill codes of the requirements.
-- When XP_SCALE_STACK is false, the value is for each output item.
local function xpOf(params, output)
    local xp = {}
    for n = 1, MAX_XP do
        local skill = SKILLS[params["RECIPE_XP_TYPE_" .. n] or 0]
        if skill then
            local scale = params["RECIPE_XP_SCALE_STACK_" .. n] == false and output or 1
            xp[#xp + 1] = { skill = skill, amount = (params["RECIPE_XP_VALUE_" .. n] or 0) * scale / 10 }
        end
    end
    return xp
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
    local xp = xpOf(params, output)
    local recipes = {}
    for _, inputs in ipairs(combinationsOf(ingredients)) do
        recipes[#recipes + 1] = {
            verb = "Make",
            output = output,
            inputs = inputs,
            skills = copyList(skills),
            unlocks = copyList(unlocks),
            xp = copyList(xp),
            actionTime = cycles > 0 and cycles or nil,
        }
    end
    return params.RECIPE_NON_DUMMY_OBJ or configName, recipes
end

local Index = {}
Index.__index = Index

-- Collects the Recipes of many Objs. Add the Objs in Obj id order.
function GameRecipe.newIndex()
    return setmetatable({ own = {}, dummies = {} }, Index)
end

function Index:add(configName, params)
    local item, recipes = GameRecipe.fromParams(configName, params)
    if item == nil then
        return
    end
    local lists = item == configName and self.own or self.dummies
    local list = lists[item] or {}
    lists[item] = list
    for _, recipe in ipairs(recipes) do
        list[#list + 1] = recipe
    end
end

-- Gives { ITEM = { recipe, ... } } in priority order (issue 24, 2026-10-25):
-- the Recipes of the item's own Obj, then the Recipes of dummy Objs by Obj id.
function Index:recipes()
    local all = {}
    for item, list in pairs(self.own) do
        all[item] = { table.unpack(list) }
    end
    for item, list in pairs(self.dummies) do
        local merged = all[item] or {}
        all[item] = merged
        for _, recipe in ipairs(list) do
            merged[#merged + 1] = recipe
        end
    end
    return all
end

local Scan = {}
Scan.__index = Scan

-- Reads Obj ids from 0 in parts. read(id) gives the config name and the params, or nil when the id has no Obj.
-- The API gives no count of Objs. So the scan stops after gap ids in a row with no Obj (issue 24, 2026-10-25).
function GameRecipe.newScan(read, gap)
    return setmetatable({ read = read, gap = gap, nextID = 0, missed = 0, index = GameRecipe.newIndex() }, Scan)
end

-- Reads up to idCount Obj ids. Gives true when the scan is done.
function Scan:step(idCount)
    for _ = 1, idCount do
        if self:isDone() then
            break
        end
        local configName, params = self.read(self.nextID)
        if configName ~= nil then
            self.missed = 0
            self.index:add(configName, params)
        else
            self.missed = self.missed + 1
        end
        self.nextID = self.nextID + 1
    end
    return self:isDone()
end

function Scan:isDone()
    return self.missed >= self.gap
end

-- Gives the Recipes, or nil before the scan is done.
function Scan:recipes()
    if not self:isDone() then
        return nil
    end
    return self.index:recipes()
end

return GameRecipe
