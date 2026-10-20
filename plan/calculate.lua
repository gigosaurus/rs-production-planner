-- Calculates the Plan from Targets, Recipes and Counted stock.
-- It does not use the game API. Tests run it outside the game client.
local Plan = {}

local function countedStock(request, item)
    return (request.detected[item] or 0) + ((request.assumed or {})[item] or 0) - ((request.reserves or {})[item] or 0)
end

local MAKE = "MAKE"

local function isMake(request)
    return request.targetMode == MAKE
end

local function madeCount(request, item)
    return (request.made or {})[item] or 0
end

local function isComplete(request)
    local wanted = {}
    for _, target in ipairs(request.targets) do
        wanted[target.item] = (wanted[target.item] or 0) + target.count
    end
    for item, count in pairs(wanted) do
        local covered = isMake(request) and madeCount(request, item) or countedStock(request, item)
        if covered < count then
            return false
        end
    end
    return true
end

local BACKPACK_SLOTS = 28

-- Finds how many actions of a Recipe the player can do with one backpack load.
local function batchHintFor(request, recipe)
    -- A stackable Input takes one slot, whatever its amount.
    local slots, perAction = BACKPACK_SLOTS, 0
    for _, input in ipairs(recipe.inputs) do
        if (request.stackable or {})[input.item] then
            slots = slots - 1
        else
            perAction = perAction + input.count
        end
    end
    if perAction == 0 then
        return recipe.actionLimit
    end
    return math.min(slots // perAction, recipe.actionLimit or math.huge)
end

-- Lists the requirements of a Recipe that the player does not meet.
local function flagsFor(request, recipe)
    local flags = {}
    for _, requirement in ipairs(recipe.skills or {}) do
        local current = (request.levels or {})[requirement.skill] or 0
        if current < requirement.level then
            flags[#flags + 1] = { skill = requirement.skill, level = requirement.level, current = current }
        end
    end
    for _, unlock in ipairs(recipe.unlocks or {}) do
        if not (request.unlocks or {})[unlock] then
            flags[#flags + 1] = { unlock = unlock }
        end
    end
    return flags
end

-- Marks each Waiting step with the position of the Flagged step that causes it.
-- A Flagged step is never also Waiting.
local function markWaiting(request, steps, recipeOf)
    local isTarget = {}
    for _, target in ipairs(request.targets) do
        isTarget[target.item] = true
    end

    local function causeOf(position, step)
        return #step.flags > 0 and position or step.waitsOn
    end

    -- A Step makes its own item and the other Outputs of its Recipe.
    local function makes(step, item)
        if step.item == item then
            return true
        end
        for _, other in ipairs(recipeOf[step].otherOutputs or {}) do
            if other.item == item then
                return true
            end
        end
        return false
    end

    local function makesTarget(step)
        for item in pairs(isTarget) do
            if makes(step, item) then
                return true
            end
        end
        return false
    end

    local changed = true
    local function wait(step, flaggedPosition)
        local earliest = math.min(step.waitsOn or flaggedPosition, flaggedPosition)
        if earliest ~= step.waitsOn then
            step.waitsOn = earliest
            changed = true
        end
    end

    -- A change in one pass can make more Steps Waiting in the other pass.
    -- Repeat both passes until no Step changes.
    while changed do
        changed = false

        -- A Step is Waiting when each Step that uses one of its Outputs is Flagged or Waiting.
        for _, step in ipairs(steps) do
            local earliest, allFlaggedOrWaiting = nil, true
            for position, user in ipairs(steps) do
                for _, input in ipairs(recipeOf[user].inputs) do
                    if makes(step, input.item) then
                        local by = causeOf(position, user)
                        if by then
                            earliest = math.min(earliest or by, by)
                        else
                            allFlaggedOrWaiting = false
                        end
                    end
                end
            end
            if #step.flags == 0 and not makesTarget(step) and allFlaggedOrWaiting and earliest then
                wait(step, earliest)
            end
        end

        -- A Step is Waiting when it uses an item that a Flagged or Waiting step makes.
        for _, step in ipairs(steps) do
            if #step.flags == 0 then
                for _, input in ipairs(recipeOf[step].inputs) do
                    for position, maker in ipairs(steps) do
                        local by = makes(maker, input.item) and causeOf(position, maker)
                        if by then
                            wait(step, by)
                        end
                    end
                end
            end
        end
    end
end

-- Finds the Next step. This is the first Step that the player can usefully do now.
local function findNext(request, steps, recipeOf)
    for position, step in ipairs(steps) do
        -- One inventory is the Batch hint, or less when fewer actions remain.
        local actions = math.min(step.batchHint or step.actions, step.actions)
        local ready = #step.flags == 0 and not step.waitsOn
        for _, input in ipairs(recipeOf[step].inputs) do
            local free = (request.detected[input.item] or 0) - ((request.reserves or {})[input.item] or 0)
            if free < input.count * actions then
                ready = false
            end
        end
        if ready then
            return position
        end
    end
end

-- Chooses the Recipe that the Plan uses for an item. It is nil for a Raw material.
-- Each part of the Plan must use this function, so that all parts use the same Recipe.
local function recipeFor(request, item)
    local recipes = request.recipes[item]
    return recipes and recipes[1]
end

-- Finds the Planning level of each item (ADR 0002).
-- The order list holds each item once, in the order that the search finds it.
local function planningLevels(request)
    -- Find each item in the Plan, through Inputs and other Outputs.
    local order, inPlan = {}, {}
    local function find(item)
        if inPlan[item] then
            return
        end
        inPlan[item] = true
        order[#order + 1] = item
        local recipe = recipeFor(request, item)
        if recipe then
            for _, input in ipairs(recipe.inputs) do
                find(input.item)
            end
            for _, other in ipairs(recipe.otherOutputs or {}) do
                find(other.item)
            end
        end
    end
    for _, target in ipairs(request.targets) do
        find(target.item)
    end

    local makers = {}
    for _, item in ipairs(order) do
        local recipe = recipeFor(request, item)
        for _, other in ipairs(recipe and recipe.otherOutputs or {}) do
            makers[other.item] = makers[other.item] or {}
            table.insert(makers[other.item], item)
        end
    end

    -- An item links to its Inputs and its other Outputs.
    -- An item that uses an other Output also links to the item whose Step makes it.
    -- These links make sure that the Plan knows the supply of an item before it calculates the need for the item.
    -- They also put the Step that makes an other Output before the Steps that use it.
    local function links(item)
        local recipe, linked = recipeFor(request, item), {}
        if not recipe then
            return linked
        end
        for _, input in ipairs(recipe.inputs) do
            linked[#linked + 1] = input.item
            for _, maker in ipairs(makers[input.item] or {}) do
                if maker ~= item then
                    linked[#linked + 1] = maker
                end
            end
        end
        for _, other in ipairs(recipe.otherOutputs or {}) do
            linked[#linked + 1] = other.item
        end
        return linked
    end

    -- The Planning level is the length of the longest path from a Target.
    -- An item that is already on the path of the search is a loop (issue 07).
    local levels, path = {}, {}
    local function visit(item, depth)
        for index, onPath in ipairs(path) do
            if onPath == item then
                local loop = { table.unpack(path, index) }
                loop[#loop + 1] = item
                error("The recipes contain a loop: " .. table.concat(loop, ", ") .. ".", 0)
            end
        end
        if levels[item] and levels[item] >= depth then
            return
        end
        levels[item] = depth
        path[#path + 1] = item
        for _, linked in ipairs(links(item)) do
            visit(linked, depth + 1)
        end
        path[#path] = nil
    end
    for _, target in ipairs(request.targets) do
        visit(target.item, 0)
    end
    return levels, order
end

local function deepestLevel(levels)
    local deepest = 0
    for _, level in pairs(levels) do
        deepest = math.max(deepest, level)
    end
    return deepest
end

local function newStep(request, item, recipe, actions)
    local step = {
        item = item,
        verb = recipe.verb,
        actions = actions,
        flags = flagsFor(request, recipe),
        batchHint = batchHintFor(request, recipe),
    }
    step.inputs = {}
    for _, input in ipairs(recipe.inputs) do
        step.inputs[#step.inputs + 1] = {
            item = input.item,
            perInventory = step.batchHint and input.count * step.batchHint,
            detected = request.detected[input.item] or 0,
        }
    end
    return step
end

-- Makes the Steps in production order. It totals the demand and the supply of each item at its Planning level.
-- It also gives the Recipe and the extra Output of each Step, the used supply of each item, and the Shortages.
local function stepsFor(request, levels, order)
    local stepsByLevel, recipeOf, extraOf = {}, {}, {}
    local shortBy = {}
    -- supply is the other Outputs of Steps. usedSupply is the part of it that the Plan uses.
    local supply, usedSupply = {}, {}
    local deepest = deepestLevel(levels)

    local demand, targetDemand = {}, {}
    for _, target in ipairs(request.targets) do
        demand[target.item] = (demand[target.item] or 0) + target.count
        targetDemand[target.item] = (targetDemand[target.item] or 0) + target.count
    end

    -- In Make, the Made count covers a Target. Counted stock of the Target item does not (ADR 0009).
    local function stillNeededFor(item)
        if isMake(request) and targetDemand[item] then
            local targetPart = math.max(0, targetDemand[item] - madeCount(request, item))
            -- Counted stock changes only the Intermediate part. Thus a Reserve of a Target item adds no need without it.
            local intermediateDemand = demand[item] - targetDemand[item]
            if intermediateDemand == 0 then
                return targetPart
            end
            return targetPart + math.max(0, intermediateDemand - countedStock(request, item))
        end
        return (demand[item] or 0) - countedStock(request, item)
    end

    for level = 0, deepest do
        stepsByLevel[level] = {}
        for _, item in ipairs(order) do
            if levels[item] == level then
                local stillNeeded = stillNeededFor(item)
                usedSupply[item] = math.max(0, math.min(stillNeeded, supply[item] or 0))
                local need = stillNeeded - (supply[item] or 0)
                local recipe = recipeFor(request, item)
                if need > 0 and recipe then
                    local actions = math.ceil(need / recipe.output)
                    local step = newStep(request, item, recipe, actions)
                    local steps = stepsByLevel[level]
                    steps[#steps + 1] = step
                    recipeOf[step] = recipe
                    extraOf[step] = actions * recipe.output - need
                    for _, input in ipairs(recipe.inputs) do
                        demand[input.item] = (demand[input.item] or 0) + input.count * actions
                    end
                    for _, other in ipairs(recipe.otherOutputs or {}) do
                        supply[other.item] = (supply[other.item] or 0) + other.count * actions
                    end
                elseif need > 0 then
                    shortBy[item] = need
                end
            end
        end
    end

    -- Production order starts at the deepest level (ADR 0002).
    local steps = {}
    for level = deepest, 0, -1 do
        for _, step in ipairs(stepsByLevel[level]) do
            steps[#steps + 1] = step
        end
    end
    return steps, recipeOf, extraOf, usedSupply, shortBy
end

local function leftoversFor(steps, recipeOf, extraOf, usedSupply)
    local leftovers = {}
    for _, step in ipairs(steps) do
        if extraOf[step] > 0 then
            leftovers[#leftovers + 1] = { item = step.item, count = extraOf[step] }
        end
        -- The used supply comes from the first Steps in production order.
        for _, other in ipairs(recipeOf[step].otherOutputs or {}) do
            local made = other.count * step.actions
            local used = math.min(made, usedSupply[other.item] or 0)
            usedSupply[other.item] = (usedSupply[other.item] or 0) - used
            if made > used then
                leftovers[#leftovers + 1] = { item = other.item, count = made - used }
            end
        end
    end
    return leftovers
end

-- A Shortage takes the position of the first Step that uses it.
-- A Shortage that no Step uses is a Target with no Recipe. It goes at the end.
local function shortagesFor(steps, recipeOf, order, shortBy)
    local shortages, listed = {}, {}
    local function listShortage(item)
        if shortBy[item] and not listed[item] then
            listed[item] = true
            shortages[#shortages + 1] = { item = item, count = shortBy[item] }
        end
    end
    for _, step in ipairs(steps) do
        for _, input in ipairs(recipeOf[step].inputs) do
            listShortage(input.item)
        end
    end
    for _, item in ipairs(order) do
        listShortage(item)
    end
    return shortages
end

local function targetLines(request)
    local targets = {}
    for _, target in ipairs(request.targets) do
        targets[#targets + 1] = {
            item = target.item,
            count = target.count,
            have = countedStock(request, target.item),
            made = isMake(request) and madeCount(request, target.item) or nil,
        }
    end
    return targets
end

function Plan.calculate(request)
    local levels, order = planningLevels(request)
    local steps, recipeOf, extraOf, usedSupply, shortBy = stepsFor(request, levels, order)
    markWaiting(request, steps, recipeOf)
    return {
        targets = targetLines(request),
        steps = steps,
        leftovers = leftoversFor(steps, recipeOf, extraOf, usedSupply),
        shortages = shortagesFor(steps, recipeOf, order, shortBy),
        next = findNext(request, steps, recipeOf),
        complete = isComplete(request),
    }
end

return Plan
