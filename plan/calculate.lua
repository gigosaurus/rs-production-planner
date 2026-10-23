-- Calculates the Plan from Targets, Recipes and Counted stock.
-- It does not use the game API. Tests run it outside the game client.
local Validate = require("plan/validate")

local Plan = {}

local REQUIRED_FIELDS = { "targets", "recipes", "detected" }
local OPTIONAL_FIELDS = { "assumed", "reserves", "stackable", "levels", "unlocks", "pools" }
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
-- poolOf gives the Dose pool and the Dose size of each item in a pool (ADR 0005).
-- poolSizes gives the Dose sizes of each pool, smallest first. They come from readPools.
local function withDefaults(basis, poolOf, poolSizes)
    local filled = copyOf(basis)
    for _, field in ipairs(OPTIONAL_FIELDS) do
        filled[field] = filled[field] or {}
    end
    filled.chosenRecipes = {}
    filled.poolOf, filled.poolSizes = poolOf, poolSizes
    -- decants marks the Decant steps. The verb of a Recipe can also be "Decant".
    filled.decants = {}
    return filled
end

-- Chooses the Recipe that the Plan uses for an item. It is nil for a Raw material.
-- Each part of the Plan must use this function, so that all parts use the same Recipe.
-- It gives a copy with an empty list for each optional list that is missing. It makes one copy for each item.
-- In a Dose pool, only the smallest Dose size with a Recipe has a Recipe (issue 29). Recipe choice is issue 30.
local function poolRecipeItem(basis, pool)
    for _, size in ipairs(basis.poolSizes[pool]) do
        local item = basis.pools[pool][size]
        if (basis.recipes[item] or {})[1] then
            return item
        end
    end
end

local function recipeFor(basis, item)
    local chosen = basis.chosenRecipes
    if chosen[item] == nil then
        local recipe = (basis.recipes[item] or {})[1]
        local inPool = basis.poolOf[item]
        if inPool and poolRecipeItem(basis, inPool.pool) ~= item then
            recipe = nil
        end
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

local DECANT = "Decant"

local function isDecant(basis, step)
    return basis.decants[step] == true
end

-- Gives the Inputs of one action of a Step. A Decant step has no Recipe. Its Inputs are for all its actions.
local function inputsOf(basis, step)
    if isDecant(basis, step) then
        return step.inputs
    end
    return recipeFor(basis, step.item).inputs
end

-- Gives the other Outputs of a Step. A Decant step has none.
local function otherOutputsOf(basis, step)
    if isDecant(basis, step) then
        return {}
    end
    return recipeFor(basis, step.item).otherOutputs
end

-- The Target modes. Callers use these names, not the strings.
-- The code compares with the locals, so a change to Plan.HAVE or Plan.MAKE has no effect.
local HAVE = "HAVE"
local MAKE = "MAKE"
Plan.HAVE = HAVE
Plan.MAKE = MAKE
local TARGET_MODES = { [HAVE] = true, [MAKE] = true }

-- Each Target has its own Target mode (ADR 0012).
local function isMake(target)
    return target.mode == MAKE
end

-- Checks the Dose pools. It gives the Dose pool and the Dose size of each item, and the Dose sizes of each pool.
-- The Dose sizes of a pool are 1 to N with no gap, so the doses that remain after a Decant step always fit one Dose size.
-- Stops with an error at the line of the caller of Plan.calculate.
local function readPools(pools)
    if type(pools) ~= "table" then
        error("The Dose pools must be a table.", 4)
    end
    local poolOf, poolSizes = {}, {}
    for pool, items in pairs(pools) do
        local name = tostring(pool)
        if type(items) ~= "table" then
            error("The Dose pool " .. name .. " must be a table.", 4)
        end
        local sizes = {}
        for size, item in pairs(items) do
            if not Validate.isPositiveInteger(size) then
                error("The Dose pool " .. name .. " has a Dose size that is not a whole number more than 0.", 4)
            end
            if type(item) ~= "string" then
                error("The item of Dose size " .. size .. " in the Dose pool " .. name .. " must be a string.", 4)
            end
            if poolOf[item] then
                error("The item " .. item .. " is in the Dose pools two times.", 4)
            end
            poolOf[item] = { pool = pool, size = size }
            sizes[#sizes + 1] = size
        end
        table.sort(sizes)
        if #sizes == 0 or sizes[#sizes] ~= #sizes then
            error("The Dose sizes of the Dose pool " .. name .. " must start at 1 and have no gap.", 4)
        end
        poolSizes[pool] = sizes
    end
    return poolOf, poolSizes
end

-- Stops with an error at the line of the caller of Plan.calculate when the Basis is not complete.
-- It gives the Dose pool maps of readPools.
local function checkBasis(basis)
    for _, field in ipairs(REQUIRED_FIELDS) do
        if basis[field] == nil then
            error("The Basis has no " .. field .. ".", 3)
        end
    end
    local poolOf, poolSizes = readPools(basis.pools or {})
    -- The diff matches the Target lines by id (issue 28).
    local ids = {}
    for _, target in ipairs(basis.targets) do
        local item = tostring(target.item)
        if not Validate.isPositiveInteger(target.id) then
            error("The Target id of " .. item .. " must be a whole number more than 0.", 3)
        end
        if ids[target.id] then
            error("Two Targets have the id " .. tostring(target.id) .. ".", 3)
        end
        ids[target.id] = true
        if not Validate.isOneOf(target.mode, TARGET_MODES) then
            error("The Target mode " .. tostring(target.mode) .. " of " .. item .. " is unknown.", 3)
        end
        if not Validate.isPositiveInteger(target.count) then
            error("The Target count of " .. item .. " must be a whole number more than 0.", 3)
        end
        if isMake(target) then
            if not Validate.isNonNegativeInteger(target.made) then
                error("The Made count of " .. item .. " must be a whole number of 0 or more.", 3)
            end
            -- A Decant step also raises the Made count of an item. Thus Make cannot count a Dose pool yet (issue 58).
            if poolOf[target.item] then
                error("A Make Target of " .. item .. " is not possible, because the item is in a Dose pool.", 3)
            end
        elseif target.made ~= nil then
            error("A Have Target of " .. item .. " has a Made count.", 3)
        end
    end
    return poolOf, poolSizes
end

-- Gives the need of the Targets of each item. Two Targets can be for the same item.
-- They do not add together: the same items count for each Target. Thus the largest need is the need (issue 16).
-- haveCounts is the largest count of the Have Targets. makeNeeds is the largest remaining quantity of the Make Targets.
local function targetNeeds(basis)
    local haveCounts, makeNeeds = {}, {}
    for _, target in ipairs(basis.targets) do
        local item = target.item
        if isMake(target) then
            makeNeeds[item] = math.max(makeNeeds[item] or 0, target.count - target.made)
        else
            haveCounts[item] = math.max(haveCounts[item] or 0, target.count)
        end
    end
    return haveCounts, makeNeeds
end

local function isMet(basis, target)
    local progress = isMake(target) and target.made or countedStock(basis, target.item)
    return progress >= target.count
end

local function isComplete(basis)
    for _, target in ipairs(basis.targets) do
        if not isMet(basis, target) then
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
local function markWaiting(basis, steps)
    local function causeOf(position, step)
        return #step.flags > 0 and position or step.waitsOn
    end

    -- A Step makes its own item and the other Outputs of its Recipe.
    local function makes(step, item)
        if step.item == item then
            return true
        end
        for _, other in ipairs(otherOutputsOf(basis, step)) do
            if other.item == item then
                return true
            end
        end
        return false
    end

    local function makesTarget(step)
        for _, target in ipairs(basis.targets) do
            if makes(step, target.item) then
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
                for _, input in ipairs(inputsOf(basis, user)) do
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
                for _, input in ipairs(inputsOf(basis, step)) do
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
        for _, input in ipairs(inputsOf(basis, step)) do
            -- The Inputs of a Decant step are for all its actions.
            local needed = isDecant(basis, step) and input.count or input.count * actions
            if freeDetected(basis, input.item) < needed then
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
        -- The Plan can use each Dose size of a pool.
        local inPool = basis.poolOf[item]
        if inPool then
            for _, size in ipairs(basis.poolSizes[inPool.pool]) do
                find(basis.pools[inPool.pool][size])
            end
        end
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

    -- Gives each item of the Dose pool of item, or only item when it is not in a pool.
    local function doseSizeItems(item)
        local inPool = basis.poolOf[item]
        if not inPool then
            return { item }
        end
        local items = {}
        for _, size in ipairs(basis.poolSizes[inPool.pool]) do
            items[#items + 1] = basis.pools[inPool.pool][size]
        end
        return items
    end

    -- An item links to its Inputs and its other Outputs.
    -- An item that uses an other Output also links to the item whose Step makes it.
    -- These links make sure that the Plan knows the supply of an item before it calculates the need for the item.
    -- They also put the Step that makes an other Output before the Steps that use it.
    -- The links of an item do not change, so the function makes them one time for each item.
    local linksOf = {}
    local function links(item)
        if linksOf[item] then
            return linksOf[item]
        end
        local recipe, linked = recipeFor(basis, item), {}
        linksOf[item] = linked
        if not recipe then
            return linked
        end
        for _, input in ipairs(recipe.inputs) do
            linked[#linked + 1] = input.item
            -- A Decant step can give a Dose size from each Dose size of the pool.
            for _, usable in ipairs(doseSizeItems(input.item)) do
                for _, maker in ipairs(makers[usable] or {}) do
                    if maker ~= item then
                        linked[#linked + 1] = maker
                    end
                end
            end
        end
        for _, other in ipairs(recipe.otherOutputs) do
            linked[#linked + 1] = other.item
        end
        return linked
    end

    -- All items of a Dose pool have the same Planning level, because the Plan calculates them together.
    -- The search uses one node for each pool. Config names have no spaces, so a node name cannot be an item.
    local function nodeOf(item)
        local inPool = basis.poolOf[item]
        return inPool and "Dose pool " .. inPool.pool or item
    end
    local itemsOfNode = {}
    for _, item in ipairs(order) do
        local node = nodeOf(item)
        itemsOfNode[node] = itemsOfNode[node] or {}
        table.insert(itemsOfNode[node], item)
    end
    -- A node links to each node that one of its items links to.
    -- A link between two items of one pool is a link from the node to itself.
    local linkedNodesOf = {}
    local function linkedNodes(node)
        if linkedNodesOf[node] then
            return linkedNodesOf[node]
        end
        local linked = {}
        linkedNodesOf[node] = linked
        for _, item in ipairs(itemsOfNode[node]) do
            for _, other in ipairs(links(item)) do
                linked[#linked + 1] = nodeOf(other)
            end
        end
        return linked
    end

    -- Puts the nodes into groups. Each node in a group links to each other node of the group.
    -- A link can go through other nodes of the group.
    -- This is the method of Tarjan for strongly connected components.
    local groupOf, index, lowest, stack, onStack = {}, {}, {}, {}, {}
    local nextIndex = 0
    local function connect(node)
        nextIndex = nextIndex + 1
        index[node], lowest[node] = nextIndex, nextIndex
        stack[#stack + 1] = node
        onStack[node] = true
        for _, linked in ipairs(linkedNodes(node)) do
            if not index[linked] then
                connect(linked)
                lowest[node] = math.min(lowest[node], lowest[linked])
            elseif onStack[linked] then
                lowest[node] = math.min(lowest[node], index[linked])
            end
        end
        if lowest[node] == index[node] then
            local group = {}
            repeat
                local member = table.remove(stack)
                onStack[member] = nil
                groupOf[member] = group
                group[#group + 1] = member
            until member == node
        end
    end
    for _, target in ipairs(basis.targets) do
        local node = nodeOf(target.item)
        if not index[node] then
            connect(node)
        end
    end

    -- A group is a Loop when it has more than one node, or when its node links to itself.
    local function isLoop(group)
        for _, linked in ipairs(linkedNodes(group[1])) do
            if linked == group[1] then
                return true
            end
        end
        return #group > 1
    end
    local loopOf, loopOfGroup = {}, {}
    for _, item in ipairs(order) do
        local group = groupOf[nodeOf(item)]
        if isLoop(group) then
            loopOfGroup[group] = loopOfGroup[group] or {}
            table.insert(loopOfGroup[group], item)
            loopOf[item] = loopOfGroup[group]
        end
    end
    -- The Plan cannot calculate a Dose pool in a Loop yet (issue 61).
    for _, item in ipairs(order) do
        if loopOf[item] and basis.poolOf[item] then
            error("The Plan cannot calculate a Loop with a Dose pool: " .. table.concat(loopOf[item], ", ") .. ".", 3)
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
            for _, linked in ipairs(linkedNodes(member)) do
                if groupOf[linked] ~= group then
                    visit(groupOf[linked], depth + 1)
                end
            end
        end
    end
    for _, target in ipairs(basis.targets) do
        visit(groupOf[nodeOf(target.item)], 0)
    end

    local levels = {}
    for _, item in ipairs(order) do
        levels[item] = levelOf[groupOf[nodeOf(item)]]
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
local function loopOrder(basis, items, targetItems, order, loop)
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
        if targetItems[item] or usedOutside[item] then
            return true
        end
        for _, other in ipairs(recipeFor(basis, item).otherOutputs) do
            if targetItems[other.item] or usedOutside[other.item] then
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
        -- Each remaining Step must come after a different one. The rule gives no first Step.
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
local function stepsFor(basis, levels, loopOf, order)
    local stepsByLevel, extraOf = {}, {}
    -- poolLeftoversOf gives the Leftovers of a Dose pool, after the last Step of the pool.
    local poolLeftoversOf = {}
    local shortBy = {}
    -- supply is the other Outputs of Steps. usedSupply is the part of it that the Plan uses.
    local supply, usedSupply = {}, {}
    local deepest = deepestLevel(levels)

    local haveCounts, makeNeeds = targetNeeds(basis)
    local demand = copyOf(haveCounts)
    local targetItems = {}
    for _, target in ipairs(basis.targets) do
        targetItems[target.item] = true
    end

    -- seeded is the Seed Shortage of each item. The Steps count it as stock (ADR 0010).
    local seeded = {}
    local function ownedFor(item)
        return countedStock(basis, item) + (seeded[item] or 0)
    end

    -- One Counted stock covers both the Have Targets and the Steps that use the item.
    -- The Made count covers a Make Target, and Counted stock does not. The Steps can use the items that a Make Target counts.
    -- Thus the need is the larger of the two needs, not the sum (ADR 0012).
    local function stillNeededFor(item)
        local haveNeed = (demand[item] or 0) - ownedFor(item)
        local makeNeed = makeNeeds[item]
        if makeNeed == nil then
            return haveNeed
        end
        -- With no Have Target and no Step that uses the item, a Reserve of the item adds no need.
        if (demand[item] or 0) == 0 then
            return makeNeed
        end
        return math.max(makeNeed, haveNeed)
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

    -- supplyLevelOf gives the lowest Planning level of a Step that makes the item as an other Output.
    local supplyLevelOf = {}
    local function record(item, result, level)
        usedSupply[item] = result.used
        shortBy[item] = result.short
        if result.step then
            extraOf[result.step] = result.extra
            local steps = stepsByLevel[level]
            steps[#steps + 1] = result.step
            for _, other in ipairs(recipeFor(basis, item).otherOutputs) do
                supplyLevelOf[other.item] = math.min(supplyLevelOf[other.item] or level, level)
            end
        end
    end

    -- decantsAfter gives the Decant steps that come after the Steps of a Planning level.
    -- A Decant step that can use other Outputs comes after the Steps that make them.
    -- The Steps that use a Dose size link to these Steps, so they come after the Decant step.
    local decantsAfter = {}

    -- Adds the Steps of a Dose pool. The Plan counts the pool as doses (ADR 0005).
    -- A Recipe makes the doses that Counted stock and the other Outputs of Steps do not give.
    -- Then Decant steps give each Dose size that is short. A Decant step takes the smallest Dose size first.
    -- The demand and the Decant steps take containers from the sources in the order of POOL_SOURCES.
    -- The doses that remain after a Decant step go into one container.
    -- The made containers that the Plan does not use are Leftovers of the pool.
    -- The other Outputs that the Plan does not use are Leftovers of the Steps that make them.
    local POOL_SOURCES = { "counted", "supplied", "made" }
    local function addPoolSteps(level, pool)
        local items, sizes = basis.pools[pool], basis.poolSizes[pool]
        -- spare gives the containers of each source and Dose size that the demand does not use.
        local balance, short, doses = {}, {}, 0
        local spare = { counted = {}, supplied = {}, made = {} }
        local lastStep, decantLevel
        for _, size in ipairs(sizes) do
            local item = items[size]
            if (supply[item] or 0) > 0 then
                decantLevel = math.min(decantLevel or supplyLevelOf[item], supplyLevelOf[item])
            end
            local counted, supplied, demanded = countedStock(basis, item), supply[item] or 0, demand[item] or 0
            balance[size] = counted + supplied - demanded
            spare.counted[size] = math.max(0, counted - demanded)
            spare.supplied[size] = math.max(0, math.min(supplied, balance[size]))
            spare.made[size] = 0
            doses = doses + balance[size] * size
        end
        for _, size in ipairs(sizes) do
            local recipe = recipeFor(basis, items[size])
            if doses < 0 and recipe then
                lastStep = newStep(basis, items[size], recipe, math.ceil(-doses / size))
                record(items[size], { used = 0, step = lastStep, extra = 0 }, level)
                addStep(lastStep, 1)
                balance[size] = balance[size] + lastStep.actions * recipe.output
                spare.made[size] = math.max(0, balance[size]) - spare.counted[size] - spare.supplied[size]
                doses = 0
                break
            end
        end
        -- With no Recipe, the Shortage is in containers of the largest Dose size.
        -- The player gets them before the Decant steps, so they count as Counted stock.
        if doses < 0 then
            local largest = sizes[#sizes]
            local count = math.ceil(-doses / largest)
            shortBy[items[largest]] = count
            balance[largest] = balance[largest] + count
            spare.counted[largest] = math.max(0, balance[largest]) - spare.supplied[largest]
        end
        for _, size in ipairs(sizes) do
            short[size] = math.max(0, -balance[size])
        end
        for _, size in ipairs(sizes) do
            if short[size] > 0 then
                local step = { item = items[size], verb = DECANT, actions = short[size], flags = {}, inputs = {} }
                local missing = short[size] * size
                for _, from in ipairs(sizes) do
                    local wanted, taken = math.max(0, math.ceil(missing / from)), 0
                    for _, source in ipairs(POOL_SOURCES) do
                        local take = math.min(spare[source][from], wanted - taken)
                        spare[source][from] = spare[source][from] - take
                        taken = taken + take
                    end
                    if taken > 0 then
                        missing = missing - taken * from
                        step.inputs[#step.inputs + 1] = {
                            item = items[from],
                            count = taken,
                            detected = basis.detected[items[from]] or 0,
                        }
                    end
                end
                if missing < 0 then
                    spare.made[-missing] = spare.made[-missing] + 1
                end
                extraOf[step] = 0
                basis.decants[step] = true
                local steps = decantLevel and decantsAfter[decantLevel] or stepsByLevel[level]
                steps[#steps + 1] = step
                lastStep = step
            end
        end
        for _, size in ipairs(sizes) do
            usedSupply[items[size]] = (supply[items[size]] or 0) - spare.supplied[size]
        end
        if lastStep then
            poolLeftoversOf[lastStep] = {}
            for _, size in ipairs(sizes) do
                if spare.made[size] > 0 then
                    table.insert(poolLeftoversOf[lastStep], { item = items[size], count = spare.made[size] })
                end
            end
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
    -- Each item uses the newest Steps. For the items before it, these are the Steps of this pass.
    -- For the other items, these are the Steps of the pass before.
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
            local sorted = not changed and loopOrder(basis, withSteps, targetItems, order, loop)
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
        stepsByLevel[level], decantsAfter[level] = {}, {}
        local poolsDone = {}
        for _, item in ipairs(order) do
            local loop, inPool = loopOf[item], basis.poolOf[item]
            if levels[item] == level and inPool then
                -- The Plan calculates all Dose sizes of a pool together.
                if not poolsDone[inPool.pool] then
                    poolsDone[inPool.pool] = true
                    addPoolSteps(level, inPool.pool)
                end
            elseif levels[item] == level and not loop then
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
        for _, step in ipairs(decantsAfter[level]) do
            steps[#steps + 1] = step
        end
    end
    return steps, extraOf, usedSupply, shortBy, poolLeftoversOf
end

local function leftoversFor(basis, steps, extraOf, usedSupply, poolLeftoversOf)
    -- notYetMade is the part of the used supply that no Step before this one makes.
    local leftovers, notYetMade = {}, copyOf(usedSupply)
    for _, step in ipairs(steps) do
        if extraOf[step] > 0 then
            leftovers[#leftovers + 1] = { item = step.item, count = extraOf[step] }
        end
        for _, leftover in ipairs(poolLeftoversOf[step] or {}) do
            leftovers[#leftovers + 1] = leftover
        end
        -- The used supply comes from the first Steps in production order.
        for _, other in ipairs(otherOutputsOf(basis, step)) do
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
        for _, input in ipairs(inputsOf(basis, step)) do
            listShortage(input.item)
        end
    end
    for _, item in ipairs(order) do
        listShortage(item)
    end
    return shortages
end

-- Gives one line for each Target, in the order of the Targets (issue 28).
-- A line has a Made count only in Make. It is the raw value, also when it is more than the count.
local function targetLines(basis)
    local targets = {}
    for _, target in ipairs(basis.targets) do
        targets[#targets + 1] = {
            id = target.id,
            item = target.item,
            mode = target.mode,
            count = target.count,
            have = countedStock(basis, target.item),
            made = target.made,
        }
    end
    return targets
end

local function assumptionsFor(basis, steps)
    for _, step in ipairs(steps) do
        if isDecant(basis, step) then
            -- The plugin does not track empty vials (ADR 0005).
            return { "The Plan assumes that you have the empty vials to decant." }
        end
    end
    return {}
end

function Plan.calculate(basis)
    basis = withDefaults(basis, checkBasis(basis))
    local order = itemsInPlan(basis)
    checkActionLimits(basis, order)
    local levels, loopOf = planningLevels(basis, order)
    local steps, extraOf, usedSupply, shortBy, poolLeftoversOf = stepsFor(basis, levels, loopOf, order)
    markWaiting(basis, steps)
    markLoops(steps, loopOf)
    return {
        targets = targetLines(basis),
        steps = steps,
        leftovers = leftoversFor(basis, steps, extraOf, usedSupply, poolLeftoversOf),
        shortages = shortagesFor(basis, steps, order, shortBy),
        assumptions = assumptionsFor(basis, steps),
        next = findNext(basis, steps),
        complete = isComplete(basis),
    }
end

return Plan
