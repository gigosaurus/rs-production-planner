-- Calculates the Plan from Targets, Recipes and Counted stock.
-- It does not use the game API. Tests run it outside the game client.
local Plan = {}

local function countedStock(input, item)
    return (input.detected[item] or 0) + ((input.assumed or {})[item] or 0) - ((input.reserves or {})[item] or 0)
end

local MAKE = "MAKE"

local function isMake(input)
    return input.targetMode == MAKE
end

local function madeCount(input, item)
    return (input.made or {})[item] or 0
end

local function isComplete(input)
    local wanted = {}
    for _, target in ipairs(input.targets) do
        wanted[target.item] = (wanted[target.item] or 0) + target.count
    end
    for item, count in pairs(wanted) do
        local covered = isMake(input) and madeCount(input, item) or countedStock(input, item)
        if covered < count then return false end
    end
    return true
end

local BACKPACK_SLOTS = 28

-- Finds how many actions of a Recipe the player can do with one backpack load.
local function batchHintFor(input, recipe)
    -- A stackable Input takes one slot, whatever its amount.
    local slots, perAction = BACKPACK_SLOTS, 0
    for _, recipeInput in ipairs(recipe.inputs) do
        if (input.stackable or {})[recipeInput.item] then
            slots = slots - 1
        else
            perAction = perAction + recipeInput.count
        end
    end
    if perAction == 0 then
        return recipe.actionLimit
    end
    return math.min(slots // perAction, recipe.actionLimit or math.huge)
end

-- Lists the requirements of a Recipe that the player does not meet.
local function flagsFor(input, recipe)
    local flags = {}
    for _, requirement in ipairs(recipe.skills or {}) do
        local current = (input.levels or {})[requirement.skill] or 0
        if current < requirement.level then
            flags[#flags + 1] = { skill = requirement.skill, level = requirement.level, current = current }
        end
    end
    for _, unlock in ipairs(recipe.unlocks or {}) do
        if not (input.unlocks or {})[unlock] then
            flags[#flags + 1] = { unlock = unlock }
        end
    end
    return flags
end

-- Marks each Waiting step with the position of the Flagged step that causes it.
-- A Flagged step is never also Waiting.
local function markWaiting(input, steps, recipeOf)
    local isTarget = {}
    for _, target in ipairs(input.targets) do
        isTarget[target.item] = true
    end

    local function blockedBy(position, step)
        return #step.flags > 0 and position or step.waitsOn
    end

    -- A Step makes its own item and the other Outputs of its Recipe.
    local function makes(step, item)
        if step.item == item then return true end
        for _, other in ipairs(recipeOf[step].otherOutputs or {}) do
            if other.item == item then return true end
        end
        return false
    end

    local function makesTarget(step)
        for item in pairs(isTarget) do
            if makes(step, item) then return true end
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
            local earliest, allBlocked = nil, true
            for position, user in ipairs(steps) do
                for _, recipeInput in ipairs(recipeOf[user].inputs) do
                    if makes(step, recipeInput.item) then
                        local by = blockedBy(position, user)
                        if by then
                            earliest = math.min(earliest or by, by)
                        else
                            allBlocked = false
                        end
                    end
                end
            end
            if #step.flags == 0 and not makesTarget(step) and allBlocked and earliest then
                wait(step, earliest)
            end
        end

        -- A Step is Waiting when it uses an item that a Flagged or Waiting step makes.
        for _, step in ipairs(steps) do
            if #step.flags == 0 then
                for _, recipeInput in ipairs(recipeOf[step].inputs) do
                    for position, maker in ipairs(steps) do
                        local by = makes(maker, recipeInput.item) and blockedBy(position, maker)
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
local function findNext(input, steps, recipeOf)
    for position, step in ipairs(steps) do
        -- One inventory is the Batch hint, or less when fewer actions remain.
        local actions = math.min(step.batchHint or step.actions, step.actions)
        local ready = #step.flags == 0 and not step.waitsOn
        for _, recipeInput in ipairs(recipeOf[step].inputs) do
            local free = (input.detected[recipeInput.item] or 0) - ((input.reserves or {})[recipeInput.item] or 0)
            if free < recipeInput.count * actions then
                ready = false
            end
        end
        if ready then
            return position
        end
    end
end

-- Finds the Planning level of each item (ADR 0002).
-- The order list holds each item once, in the order that the search finds it.
local function planningLevels(input)
    local function recipeFor(item)
        local recipes = input.recipes[item]
        return recipes and recipes[1]
    end

    -- Find each item in the Plan, through Inputs and other Outputs.
    local order, inPlan = {}, {}
    local function find(item)
        if inPlan[item] then return end
        inPlan[item] = true
        order[#order + 1] = item
        local recipe = recipeFor(item)
        if recipe then
            for _, recipeInput in ipairs(recipe.inputs) do find(recipeInput.item) end
            for _, other in ipairs(recipe.otherOutputs or {}) do find(other.item) end
        end
    end
    for _, target in ipairs(input.targets) do find(target.item) end

    local makers = {}
    for _, item in ipairs(order) do
        local recipe = recipeFor(item)
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
        local recipe, linked = recipeFor(item), {}
        if not recipe then return linked end
        for _, recipeInput in ipairs(recipe.inputs) do
            linked[#linked + 1] = recipeInput.item
            for _, maker in ipairs(makers[recipeInput.item] or {}) do
                if maker ~= item then linked[#linked + 1] = maker end
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
        if levels[item] and levels[item] >= depth then return end
        levels[item] = depth
        path[#path + 1] = item
        for _, linked in ipairs(links(item)) do
            visit(linked, depth + 1)
        end
        path[#path] = nil
    end
    for _, target in ipairs(input.targets) do
        visit(target.item, 0)
    end
    return levels, order
end

function Plan.calculate(input)
    local stepsByLevel, recipeOf, extraOf = {}, {}, {}
    local shortBy = {}
    -- supply is the other Outputs of Steps. usedSupply is the part of it that the Plan uses.
    local supply, usedSupply = {}, {}
    local levels, order = planningLevels(input)
    local deepest = 0
    for _, level in pairs(levels) do
        deepest = math.max(deepest, level)
    end

    local demand, targetDemand = {}, {}
    for _, target in ipairs(input.targets) do
        demand[target.item] = (demand[target.item] or 0) + target.count
        targetDemand[target.item] = (targetDemand[target.item] or 0) + target.count
    end

    -- In Make, the Made count covers a Target. Counted stock of the Target item does not (ADR 0009).
    local function stillNeededFor(item)
        if isMake(input) and targetDemand[item] then
            local targetPart = math.max(0, targetDemand[item] - madeCount(input, item))
            -- Counted stock changes only the Intermediate part. Thus a Reserve of a Target item adds no need without it.
            local intermediateDemand = demand[item] - targetDemand[item]
            if intermediateDemand == 0 then return targetPart end
            return targetPart + math.max(0, intermediateDemand - countedStock(input, item))
        end
        return (demand[item] or 0) - countedStock(input, item)
    end

    for level = 0, deepest do
        stepsByLevel[level] = {}
        for _, item in ipairs(order) do
            if levels[item] == level then
                local stillNeeded = stillNeededFor(item)
                usedSupply[item] = math.max(0, math.min(stillNeeded, supply[item] or 0))
                local need = stillNeeded - (supply[item] or 0)
                local recipes = input.recipes[item]
                if need > 0 and recipes then
                    local recipe = recipes[1]
                    local actions = math.ceil(need / recipe.output)
                    local steps = stepsByLevel[level]
                    local step = { item = item, verb = recipe.verb, actions = actions, flags = flagsFor(input, recipe), batchHint = batchHintFor(input, recipe) }
                    steps[#steps + 1] = step
                    recipeOf[step] = recipe
                    step.inputs = {}
                    for _, recipeInput in ipairs(recipe.inputs) do
                        step.inputs[#step.inputs + 1] = {
                            item = recipeInput.item,
                            perInventory = step.batchHint and recipeInput.count * step.batchHint,
                            detected = input.detected[recipeInput.item] or 0,
                        }
                    end
                    extraOf[step] = actions * recipe.output - need
                    for _, recipeInput in ipairs(recipe.inputs) do
                        demand[recipeInput.item] = (demand[recipeInput.item] or 0) + recipeInput.count * actions
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

    markWaiting(input, steps, recipeOf)

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

    -- A Shortage takes the position of the first Step that uses it.
    -- A Shortage that no Step uses is a Target with no Recipe. It goes at the end.
    local shortages, listed = {}, {}
    local function listShortage(item)
        if shortBy[item] and not listed[item] then
            listed[item] = true
            shortages[#shortages + 1] = { item = item, count = shortBy[item] }
        end
    end
    for _, step in ipairs(steps) do
        for _, recipeInput in ipairs(recipeOf[step].inputs) do
            listShortage(recipeInput.item)
        end
    end
    for _, item in ipairs(order) do
        listShortage(item)
    end

    local targets = {}
    for _, target in ipairs(input.targets) do
        targets[#targets + 1] = {
            item = target.item, count = target.count, have = countedStock(input, target.item),
            made = isMake(input) and madeCount(input, target.item) or nil,
        }
    end

    return {
        targets = targets, steps = steps, leftovers = leftovers, shortages = shortages,
        next = findNext(input, steps, recipeOf), complete = isComplete(input),
    }
end

return Plan
