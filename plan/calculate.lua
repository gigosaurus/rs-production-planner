-- Calculates the Plan from Targets, Recipes and Counted stock.
-- It does not use the game API. Tests run it outside the game client.
local Validate = require("plan/validate")

local Plan = {}

local REQUIRED_FIELDS = { "targets", "recipes", "detected", "targetMode" }
local OPTIONAL_FIELDS = { "assumed", "reserves", "made", "stackable", "levels", "unlocks" }
local OPTIONAL_RECIPE_LISTS = { "otherOutputs", "skills", "unlocks" }

local function copyOf(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

-- Gives a copy of the Basis with an empty table for each optional field that is missing.
-- The tables of the caller do not change.
-- recipeFor fills the Recipes, because the Plan uses only some of them.
local function withDefaults(basis)
    local filled = copyOf(basis)
    for _, field in ipairs(OPTIONAL_FIELDS) do
        filled[field] = filled[field] or {}
    end
    filled.chosenRecipes = {}
    return filled
end

-- Chooses the Recipe that the Plan uses for an item. It is nil for a Raw material.
-- Each part of the Plan must use this function, so that all parts use the same Recipe.
-- It gives a copy with an empty list for each optional list that is missing. It makes one copy for each item.
local function recipeFor(basis, item)
    local chosen = basis.chosenRecipes
    if chosen[item] == nil then
        local recipe = (basis.recipes[item] or {})[1]
        -- false marks a Raw material, so that the next call does not look again.
        chosen[item] = false
        if recipe then
            chosen[item] = copyOf(recipe)
            for _, field in ipairs(OPTIONAL_RECIPE_LISTS) do
                chosen[item][field] = chosen[item][field] or {}
            end
        end
    end
    return chosen[item] or nil
end

local function countedStock(basis, item)
    return (basis.detected[item] or 0) + (basis.assumed[item] or 0) - (basis.reserves[item] or 0)
end

-- Gives the amount of an item that the player has now and can use: Detected stock minus Reserves.
-- It does not include Assumed stock, because the player does not have it yet.
local function freeDetected(basis, item)
    return (basis.detected[item] or 0) - (basis.reserves[item] or 0)
end

-- The Target modes. Callers use these names, not the strings.
-- The code compares with the locals, so a change to Plan.HAVE or Plan.MAKE has no effect.
local HAVE = "HAVE"
local MAKE = "MAKE"
Plan.HAVE = HAVE
Plan.MAKE = MAKE
local TARGET_MODES = { [HAVE] = true, [MAKE] = true }

local function isMake(basis)
    return basis.targetMode == MAKE
end

-- Stops with an error at the line of the caller of Plan.calculate when the Basis is not complete.
local function checkBasis(basis)
    for _, field in ipairs(REQUIRED_FIELDS) do
        if basis[field] == nil then
            error("The Basis has no " .. field .. ".", 3)
        end
    end
    if not Validate.isOneOf(basis.targetMode, TARGET_MODES) then
        error("The Target mode " .. tostring(basis.targetMode) .. " is unknown.", 3)
    end
    for _, target in ipairs(basis.targets) do
        if not Validate.isPositiveInteger(target.count) then
            error("The Target count of " .. tostring(target.item) .. " must be a whole number more than 0.", 3)
        end
    end
end

local function madeCount(basis, item)
    return basis.made[item] or 0
end

-- Gives the amount of each Target item. Two Targets can be for the same item.
-- They do not add together: the same items count for each Target. Thus the largest Target is the amount (issue 16).
local function targetTotals(basis)
    local totals = {}
    for _, target in ipairs(basis.targets) do
        totals[target.item] = math.max(totals[target.item] or 0, target.count)
    end
    return totals
end

local function isComplete(basis, totals)
    for item, count in pairs(totals) do
        local covered = isMake(basis) and madeCount(basis, item) or countedStock(basis, item)
        if covered < count then
            return false
        end
    end
    return true
end

local INVENTORY_SLOTS = 28

-- Finds how many actions of a Recipe the player can do with one full Inventory.
-- It gives nil (no hint) when one action does not fit in the Inventory.
local function batchHintFor(basis, recipe)
    -- A stackable Input takes one slot, whatever its amount.
    local slots, perAction = INVENTORY_SLOTS, 0
    for _, input in ipairs(recipe.inputs) do
        if basis.stackable[input.item] then
            slots = slots - 1
        else
            perAction = perAction + input.count
        end
    end
    if slots < 0 then
        return nil
    end
    if perAction == 0 then
        return recipe.actionLimit
    end
    local fit = slots // perAction
    if fit < 1 then
        return nil
    end
    return math.min(fit, recipe.actionLimit)
end

-- Lists the requirements of a Recipe that the player does not meet.
local function flagsFor(basis, recipe)
    local flags = {}
    for _, requirement in ipairs(recipe.skills) do
        local current = basis.levels[requirement.skill] or 0
        if current < requirement.level then
            flags[#flags + 1] = { skill = requirement.skill, level = requirement.level, current = current }
        end
    end
    for _, unlock in ipairs(recipe.unlocks) do
        if not basis.unlocks[unlock] then
            flags[#flags + 1] = { unlock = unlock }
        end
    end
    return flags
end

-- Marks each Waiting step with the position of the Flagged step that causes it.
-- A Flagged step is never also Waiting.
local function markWaiting(basis, steps, totals)
    local function causeOf(position, step)
        return #step.flags > 0 and position or step.waitsOn
    end

    -- A Step makes its own item and the other Outputs of its Recipe.
    local function makes(step, item)
        if step.item == item then
            return true
        end
        for _, other in ipairs(recipeFor(basis, step.item).otherOutputs) do
            if other.item == item then
                return true
            end
        end
        return false
    end

    local function makesTarget(step)
        for item in pairs(totals) do
            if makes(step, item) then
                return true
            end
        end
        return false
    end

    -- Gives true when the Step changes.
    local function wait(step, flaggedPosition)
        local earliest = math.min(step.waitsOn or flaggedPosition, flaggedPosition)
        if earliest == step.waitsOn then
            return false
        end
        step.waitsOn = earliest
        return true
    end

    local changed = true

    -- A change in one pass can make more Steps Waiting in the other pass.
    -- Repeat both passes until no Step changes.
    while changed do
        changed = false

        -- A Step is Waiting when each Step that uses one of its Outputs is Flagged or Waiting.
        for _, step in ipairs(steps) do
            local earliest, allFlaggedOrWaiting = nil, true
            for position, user in ipairs(steps) do
                for _, input in ipairs(recipeFor(basis, user.item).inputs) do
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
                changed = wait(step, earliest) or changed
            end
        end

        -- A Step is Waiting when it uses an item that a Flagged or Waiting step makes.
        for _, step in ipairs(steps) do
            if #step.flags == 0 then
                for _, input in ipairs(recipeFor(basis, step.item).inputs) do
                    for position, maker in ipairs(steps) do
                        local by = makes(maker, input.item) and causeOf(position, maker)
                        if by then
                            changed = wait(step, by) or changed
                        end
                    end
                end
            end
        end
    end
end

-- Finds the Next step. This is the first Step that the player can usefully do now.
-- It uses the Loop marks, so markLoops must run first.
local function findNext(basis, steps)
    for position, step in ipairs(steps) do
        -- One full Inventory is the Batch hint, or less when fewer actions remain. With no Batch hint, it is all remaining actions.
        local actions = math.min(step.batchHint or step.actions, step.actions)
        -- A Loop returns its Inputs, so a Step with a Loop mark is ready with one action (ADR 0010).
        -- The only Step of a Loop has no mark. No other Step returns its Inputs.
        if step.loopWith then
            actions = 1
        end
        local ready = #step.flags == 0 and not step.waitsOn
        for _, input in ipairs(recipeFor(basis, step.item).inputs) do
            if freeDetected(basis, input.item) < input.count * actions then
                ready = false
            end
        end
        if ready then
            return position
        end
    end
end

-- Marks each Step in a Loop with the positions of the other Steps of the Loop (ADR 0010).
-- A Step with no other Step in its Loop gets no mark.
local function markLoops(steps, loopOf)
    for _, step in ipairs(steps) do
        local loop, others = loopOf[step.item], {}
        for position, other in ipairs(steps) do
            if loop and other ~= step and loopOf[other.item] == loop then
                others[#others + 1] = position
            end
        end
        step.loopWith = #others > 0 and others or nil
    end
end

-- Finds each item in the Plan, through Inputs and other Outputs.
-- The table order holds each item once, in the sequence that the search finds it.
local function itemsInPlan(basis)
    local order, inPlan = {}, {}
    local function find(item)
        if inPlan[item] then
            return
        end
        inPlan[item] = true
        order[#order + 1] = item
        local recipe = recipeFor(basis, item)
        if recipe then
            for _, input in ipairs(recipe.inputs) do
                find(input.item)
            end
            for _, other in ipairs(recipe.otherOutputs) do
                find(other.item)
            end
        end
    end
    for _, target in ipairs(basis.targets) do
        find(target.item)
    end
    return order
end

-- Each Recipe that the Plan uses must have an Action limit (issue 2, section 1).
-- The check does not depend on stock, so that a data error shows at once.
local function checkActionLimits(basis, order)
    for _, item in ipairs(order) do
        local recipe = recipeFor(basis, item)
        if recipe and not recipe.actionLimit then
            error("The Recipe for " .. item .. " has no Action limit.", 3)
        end
    end
end

-- Finds the Planning level of each item (ADR 0002).
-- It also gives the Loop of each item that is in a Loop (ADR 0010).
-- A Loop is a list of its items in the order of the search.
local function planningLevels(basis, order)
    local makers = {}
    for _, item in ipairs(order) do
        local recipe = recipeFor(basis, item)
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
        local recipe, linked = recipeFor(basis, item), {}
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
        for _, other in ipairs(recipe.otherOutputs) do
            linked[#linked + 1] = other.item
        end
        return linked
    end

    -- Puts the items into groups: each item in a group links to each other item of the group, through other items of the group.
    -- This is the method of Tarjan for strongly connected components.
    local groupOf, index, lowest, stack, onStack = {}, {}, {}, {}, {}
    local nextIndex = 0
    local function connect(item)
        nextIndex = nextIndex + 1
        index[item], lowest[item] = nextIndex, nextIndex
        stack[#stack + 1] = item
        onStack[item] = true
        for _, linked in ipairs(links(item)) do
            if not index[linked] then
                connect(linked)
                lowest[item] = math.min(lowest[item], lowest[linked])
            elseif onStack[linked] then
                lowest[item] = math.min(lowest[item], index[linked])
            end
        end
        if lowest[item] == index[item] then
            local group = {}
            repeat
                local member = table.remove(stack)
                onStack[member] = nil
                groupOf[member] = group
                group[#group + 1] = member
            until member == item
        end
    end
    for _, target in ipairs(basis.targets) do
        if not index[target.item] then
            connect(target.item)
        end
    end

    -- A group is a Loop when it has more than one item, or when its item links to itself.
    local function isLoop(group)
        for _, linked in ipairs(links(group[1])) do
            if linked == group[1] then
                return true
            end
        end
        return #group > 1
    end
    local loopOf, loopOfGroup = {}, {}
    for _, item in ipairs(order) do
        local group = groupOf[item]
        if isLoop(group) then
            loopOfGroup[group] = loopOfGroup[group] or {}
            table.insert(loopOfGroup[group], item)
            loopOf[item] = loopOfGroup[group]
        end
    end

    -- The Planning level is the length of the longest path from a Target. All items of one group have the same level.
    -- The links between groups contain no Loop, so the search stops.
    local levelOf = {}
    local function visit(group, depth)
        if levelOf[group] and levelOf[group] >= depth then
            return
        end
        levelOf[group] = depth
        for _, member in ipairs(group) do
            for _, linked in ipairs(links(member)) do
                if groupOf[linked] ~= group then
                    visit(groupOf[linked], depth + 1)
                end
            end
        end
    end
    for _, target in ipairs(basis.targets) do
        visit(groupOf[target.item], 0)
    end

    local levels = {}
    for _, item in ipairs(order) do
        levels[item] = levelOf[groupOf[item]]
    end
    return levels, loopOf
end

local function deepestLevel(levels)
    local deepest = 0
    for _, level in pairs(levels) do
        deepest = math.max(deepest, level)
    end
    return deepest
end

-- Makes a Step that uses recipe to make the amount need of item.
-- It also gives the extra Output: the Output above the need, because the Step does whole actions. It is a Leftover.
local function newStep(basis, item, recipe, need)
    local actions = math.ceil(need / recipe.output)
    local step = {
        item = item,
        verb = recipe.verb,
        actions = actions,
        flags = flagsFor(basis, recipe),
        batchHint = batchHintFor(basis, recipe),
    }
    step.inputs = {}
    for _, input in ipairs(recipe.inputs) do
        step.inputs[#step.inputs + 1] = {
            item = input.item,
            perInventory = step.batchHint and input.count * step.batchHint,
            detected = basis.detected[input.item] or 0,
        }
    end
    return step, actions * recipe.output - need
end

-- The largest number of times that the Plan calculates the items of one Loop (ADR 0010).
local PASS_LIMIT = 1000

-- Puts the items of the Steps of one Loop in production order (ADR 0010).
-- items is in the order of the search. That order decides a tie.
-- loop is all items of the Loop, also the items with no Step.
local function loopOrder(basis, items, totals, order, loop)
    local inLoop = {}
    for _, item in ipairs(loop) do
        inLoop[item] = true
    end

    -- The Step of an item makes the item and the other Outputs of its Recipe.
    local function makesOnly(item, made)
        if item ~= made then
            return false
        end
        for _, other in ipairs(recipeFor(basis, item).otherOutputs) do
            if other.item ~= made then
                return false
            end
        end
        return true
    end

    -- A Step that turns an Input into a different item comes before a Step that makes only that Input.
    local function mustComeBefore(first, second)
        for _, input in ipairs(recipeFor(basis, first).inputs) do
            if makesOnly(second, input.item) and not makesOnly(first, input.item) then
                return true
            end
        end
        return false
    end

    -- An Output goes toward the Target when it is a Target or an Input of a Recipe outside the Loop.
    local usedOutside = {}
    for _, item in ipairs(order) do
        local recipe = recipeFor(basis, item)
        if recipe and not inLoop[item] then
            for _, input in ipairs(recipe.inputs) do
                usedOutside[input.item] = true
            end
        end
    end
    local function goesOut(item)
        if totals[item] or usedOutside[item] then
            return true
        end
        for _, other in ipairs(recipeFor(basis, item).otherOutputs) do
            if totals[other.item] or usedOutside[other.item] then
                return true
            end
        end
        return false
    end

    local remaining, sorted = { table.unpack(items) }, {}
    while #remaining > 0 do
        local candidates = {}
        for _, item in ipairs(remaining) do
            local free = true
            for _, other in ipairs(remaining) do
                free = free and not (other ~= item and mustComeBefore(other, item))
            end
            if free then
                candidates[#candidates + 1] = item
            end
        end
        -- Each remaining Step must come after a different one. The rule contradicts itself.
        if #candidates == 0 then
            candidates = remaining
        end
        local chosen = candidates[1]
        for _, item in ipairs(candidates) do
            if goesOut(item) then
                chosen = item
                break
            end
        end
        sorted[#sorted + 1] = chosen
        for index, item in ipairs(remaining) do
            if item == chosen then
                table.remove(remaining, index)
                break
            end
        end
    end
    return sorted
end

-- Makes the Steps in production order. It totals the demand and the supply of each item at its Planning level.
-- It also gives the extra Output of each Step, the used supply of each item, and the Shortages.
local function stepsFor(basis, levels, loopOf, order, totals)
    local stepsByLevel, extraOf = {}, {}
    local shortBy = {}
    -- supply is the other Outputs of Steps. usedSupply is the part of it that the Plan uses.
    local supply, usedSupply = {}, {}
    local deepest = deepestLevel(levels)

    local demand = copyOf(totals)

    -- seeded is the Seed Shortage of each item. The Steps count it as stock (ADR 0010).
    local seeded = {}
    local function ownedFor(item)
        return countedStock(basis, item) + (seeded[item] or 0)
    end

    -- In Make, the Made count covers a Target. Counted stock of the Target item does not (ADR 0009).
    local function stillNeededFor(item)
        if isMake(basis) and totals[item] then
            local targetPart = math.max(0, totals[item] - madeCount(basis, item))
            -- Counted stock changes only the Intermediate part. Thus, with no Intermediate part, a Reserve of the item adds no need.
            local intermediateDemand = demand[item] - totals[item]
            if intermediateDemand == 0 then
                return targetPart
            end
            return targetPart + math.max(0, intermediateDemand - ownedFor(item))
        end
        return (demand[item] or 0) - ownedFor(item)
    end

    -- Calculates the Step for an item from the current demand and supply. It changes no table.
    local function planItem(item)
        local stillNeeded = stillNeededFor(item)
        local result = { used = math.max(0, math.min(stillNeeded, supply[item] or 0)) }
        local need = stillNeeded - (supply[item] or 0)
        local recipe = recipeFor(basis, item)
        if need > 0 and recipe then
            result.step, result.extra = newStep(basis, item, recipe, need)
        elseif need > 0 then
            result.short = need
        end
        return result
    end

    -- Adds the demand and the supply that a Step causes. A sign of -1 removes them.
    local function addStep(step, sign)
        if not step then
            return
        end
        local recipe = recipeFor(basis, step.item)
        for _, input in ipairs(recipe.inputs) do
            demand[input.item] = (demand[input.item] or 0) + sign * input.count * step.actions
        end
        for _, other in ipairs(recipe.otherOutputs) do
            supply[other.item] = (supply[other.item] or 0) + sign * other.count * step.actions
        end
    end

    local function record(item, result, level)
        usedSupply[item] = result.used
        shortBy[item] = result.short
        if result.step then
            extraOf[result.step] = result.extra
            local steps = stepsByLevel[level]
            steps[#steps + 1] = result.step
        end
    end

    local function actionsOf(result)
        return result and result.step and result.step.actions or 0
    end

    -- A Recipe of the Loop makes the item, as its Output or as an other Output.
    local function loopMakes(loop, item)
        for _, member in ipairs(loop) do
            if member == item then
                return true
            end
            for _, other in ipairs(recipeFor(basis, member).otherOutputs) do
                if other.item == item then
                    return true
                end
            end
        end
        return false
    end

    -- Only the Inputs that the Loop makes count.
    -- A Step outside the Loop makes each other Input before the Loop starts, or it is a Shortage.
    local function canDoOneAction(item, loop)
        for _, input in ipairs(recipeFor(basis, item).inputs) do
            if loopMakes(loop, input.item) and ownedFor(input.item) < input.count then
                return false
            end
        end
        return true
    end

    -- A Loop needs stock to start: the Seed. It is the Loop Inputs of one action of the first Step.
    -- The Loop needs no Seed when the player can do one action of any Step of the Loop.
    -- Gives true when it adds a Seed Shortage.
    local function addSeed(sorted, loop)
        for _, item in ipairs(sorted) do
            if canDoOneAction(item, loop) then
                return false
            end
        end
        local added = false
        for _, input in ipairs(sorted[1] and recipeFor(basis, sorted[1]).inputs or {}) do
            local short = input.count - ownedFor(input.item)
            if loopMakes(loop, input.item) and short > 0 then
                seeded[input.item] = (seeded[input.item] or 0) + short
                added = true
            end
        end
        return added
    end

    -- Calculates all items of a Loop in passes, until no amount changes (ADR 0010).
    -- Each item uses the newest Steps: the Steps of the items before it in this pass, and of the other items in the pass before.
    -- It gives false when the Loop reaches the pass limit.
    local function planLoop(loop, level)
        local results = {}
        for _ = 1, PASS_LIMIT do
            local changed = false
            for _, item in ipairs(loop) do
                local old = results[item]
                results[item] = planItem(item)
                addStep(old and old.step, -1)
                addStep(results[item].step, 1)
                changed = changed or actionsOf(results[item]) ~= actionsOf(old)
            end
            local withSteps = {}
            for _, item in ipairs(loop) do
                if results[item].step then
                    withSteps[#withSteps + 1] = item
                end
            end
            local sorted = not changed and loopOrder(basis, withSteps, totals, order, loop)
            local newSeed = sorted and addSeed(sorted, loop)
            if sorted and not newSeed then
                for _, item in ipairs(loop) do
                    if not results[item].step then
                        record(item, results[item], level)
                    end
                end
                for _, item in ipairs(sorted) do
                    record(item, results[item], level)
                end
                return true
            end
            -- A new Seed Shortage changes the stock. Then the Loop starts again with no Steps.
            -- From more actions, the passes can stop at more actions than the Loop needs.
            if newSeed then
                for _, item in ipairs(loop) do
                    addStep(results[item].step, -1)
                end
                results = {}
            end
        end
        return false
    end

    for level = 0, deepest do
        stepsByLevel[level] = {}
        for _, item in ipairs(order) do
            local loop = loopOf[item]
            if levels[item] == level and not loop then
                local result = planItem(item)
                record(item, result, level)
                addStep(result.step, 1)
            elseif levels[item] == level and loop[1] == item and not planLoop(loop, level) then
                -- A Loop that gains nothing never becomes stable.
                error("The Plan cannot calculate a Loop: " .. table.concat(loop, ", ") .. ", " .. loop[1] .. ".", 3)
            end
        end
    end

    -- The Shortage of an item is its Seed part and the need that remains after it.
    for item, count in pairs(seeded) do
        shortBy[item] = (shortBy[item] or 0) + count
    end

    -- Production order starts at the deepest level (ADR 0002).
    local steps = {}
    for level = deepest, 0, -1 do
        for _, step in ipairs(stepsByLevel[level]) do
            steps[#steps + 1] = step
        end
    end
    return steps, extraOf, usedSupply, shortBy
end

local function leftoversFor(basis, steps, extraOf, usedSupply)
    -- notYetMade is the part of the used supply that no Step before this one makes.
    local leftovers, notYetMade = {}, copyOf(usedSupply)
    for _, step in ipairs(steps) do
        if extraOf[step] > 0 then
            leftovers[#leftovers + 1] = { item = step.item, count = extraOf[step] }
        end
        -- The used supply comes from the first Steps in production order.
        for _, other in ipairs(recipeFor(basis, step.item).otherOutputs) do
            local made = other.count * step.actions
            local used = math.min(made, notYetMade[other.item] or 0)
            notYetMade[other.item] = (notYetMade[other.item] or 0) - used
            if made > used then
                leftovers[#leftovers + 1] = { item = other.item, count = made - used }
            end
        end
    end
    return leftovers
end

-- A Shortage takes the position of the first Step that uses it.
-- A Shortage that no Step uses is a Target with no Recipe. It goes at the end.
local function shortagesFor(basis, steps, order, shortBy)
    local shortages, listed = {}, {}
    local function listShortage(item)
        if shortBy[item] and not listed[item] then
            listed[item] = true
            shortages[#shortages + 1] = { item = item, count = shortBy[item] }
        end
    end
    for _, step in ipairs(steps) do
        for _, input in ipairs(recipeFor(basis, step.item).inputs) do
            listShortage(input.item)
        end
    end
    for _, item in ipairs(order) do
        listShortage(item)
    end
    return shortages
end

-- Gives one line for each Target item, in the order of the first Target for it (issue 16).
local function targetLines(basis, totals)
    local targets, listed = {}, {}
    for _, target in ipairs(basis.targets) do
        local item = target.item
        if not listed[item] then
            listed[item] = true
            targets[#targets + 1] = {
                item = item,
                count = totals[item],
                have = countedStock(basis, item),
                made = isMake(basis) and madeCount(basis, item) or nil,
            }
        end
    end
    return targets
end

function Plan.calculate(basis)
    checkBasis(basis)
    basis = withDefaults(basis)
    local order = itemsInPlan(basis)
    checkActionLimits(basis, order)
    local levels, loopOf = planningLevels(basis, order)
    local totals = targetTotals(basis)
    local steps, extraOf, usedSupply, shortBy = stepsFor(basis, levels, loopOf, order, totals)
    markWaiting(basis, steps, totals)
    markLoops(steps, loopOf)
    return {
        targets = targetLines(basis, totals),
        steps = steps,
        leftovers = leftoversFor(basis, steps, extraOf, usedSupply),
        shortages = shortagesFor(basis, steps, order, shortBy),
        next = findNext(basis, steps),
        complete = isComplete(basis, totals),
    }
end

return Plan
