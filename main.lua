-- Production Planner. The adapter between the game client and the plan/ modules.
-- It builds the Recipes from the game at runtime (ADR 0017).
local GameRecipe = require("plan/gamerecipe")
local ObjParams = require("plan/objparams")

-- Decisions on issue 24, 2026-10-25.
local IDS_PER_TICK = 250
local GAP = 1000

-- The first set of issue 24: the Super restore (4) Plan. The plugin logs their Recipes for a check in game.
local FIRST_SET =
    { "UNIDENTIFIED_RANARR", "RANARR_WEED", "RANARRVIAL", "SNAPDRAGONVIAL", "_3DOSE2RESTORE", "_4DOSE2RESTORE" }

local EVENT_NAME = "productionPlanner"

local recipes = nil

-- Gives the config name and the recipe params of an Obj id, or nil when the id has no Obj.
local function readObj(id)
    local obj = config.Obj.FromID(id)
    if obj == nil or obj.isValid ~= true then
        return nil
    end
    return obj.configName, ObjParams.read(obj)
end

local function listText(list, format)
    local parts = {}
    for i, entry in ipairs(list) do
        parts[i] = format(entry)
    end
    return table.concat(parts, ", ")
end

local function recipeText(recipe)
    return "output "
        .. recipe.output
        .. "; inputs "
        .. listText(recipe.inputs, function(input)
            return input.count .. " " .. input.item
        end)
        .. "; skills "
        .. listText(recipe.skills, function(skill)
            return skill.skill .. " " .. skill.level
        end)
        .. "; unlocks "
        .. table.concat(recipe.unlocks, ", ")
        .. "; xp "
        .. listText(recipe.xp, function(xp)
            return xp.amount .. " " .. xp.skill
        end)
        .. "; action time "
        .. tostring(recipe.actionTime)
end

local function logFirstSet()
    for _, item in ipairs(FIRST_SET) do
        local list = recipes[item] or {}
        log("[Production Planner] " .. item .. ": " .. #list .. " Recipes")
        for i, recipe in ipairs(list) do
            log("[Production Planner]   " .. i .. ": " .. recipeText(recipe))
        end
    end
end

local scan = GameRecipe.newScan(readObj, GAP)

Event.Logic.Subscribe(EVENT_NAME, function()
    if recipes ~= nil then
        return
    end
    if scan:step(IDS_PER_TICK) then
        recipes = scan:recipes()
        local count = 0
        for _ in pairs(recipes) do
            count = count + 1
        end
        log("[Production Planner] The Recipe scan is done. " .. count .. " items have a Recipe.")
        logFirstSet()
    end
end)

function PluginShutdown()
    Event.Logic.Unsubscribe(EVENT_NAME)
end
