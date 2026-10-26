-- The Recipe graph of the Plan (issue 39). Plan.calculate builds it from the Basis at the start of each calculation.
-- It gives the Recipe of each item, the items in the Plan, the Planning levels, the Loops and the Dose pools.
-- The other parts of the Plan ask the graph. They do not read the Inputs or the other Outputs of a Recipe themselves.
-- It does not use the game API. Tests run it through Plan.calculate.
local Graph = {}
Graph.__index = Graph

local OPTIONAL_RECIPE_LISTS = { "otherOutputs", "skills", "unlocks" }
local NONE = {}

local function copyOf(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

-- In a Dose pool, only the smallest Dose size with a Recipe has a Recipe (issue 29).
local function poolRecipeItem(basis, pool)
    for _, size in ipairs(basis.poolSizes[pool]) do
        local item = basis.pools[pool][size]
        if (basis.recipes[item] or {})[1] then
            return item
        end
    end
end

-- Gives the Recipe that the Plan uses for an item. It is nil for a Raw material.
-- Each part of the Plan must use this function, so that all parts use the same Recipe.
-- It chooses the Recipe at the first call for the item, because the Plan uses only some Recipes. Recipe choice is issue 30.
-- It gives a copy with an empty list for each optional list that is missing. It makes one copy for each item.
function Graph:recipe(item)
    local chosen = self.chosen
    if chosen[item] == nil then
        local recipe = (self.basis.recipes[item] or {})[1]
        local inPool = self.poolOf[item]
        if inPool and poolRecipeItem(self.basis, inPool.pool) ~= item then
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

-- Gives the Inputs of one action of the Recipe of an item. A Raw material has none.
function Graph:inputs(item)
    local recipe = self:recipe(item)
    return recipe and recipe.inputs or NONE
end

-- Gives the other Outputs of the Recipe of an item. A Raw material has none.
function Graph:otherOutputs(item)
    local recipe = self:recipe(item)
    return recipe and recipe.otherOutputs or NONE
end

-- The Recipe of an item makes the item and its other Outputs.
function Graph:makes(item, made)
    if item == made then
        return true
    end
    for _, other in ipairs(self:otherOutputs(item)) do
        if other.item == made then
            return true
        end
    end
    return false
end

-- The Recipe of an item makes only that item: it has no other Output of a different item.
function Graph:makesOnly(item, made)
    if item ~= made then
        return false
    end
    for _, other in ipairs(self:otherOutputs(item)) do
        if other.item ~= made then
            return false
        end
    end
    return true
end

-- Gives the Dose pool and the Dose size of an item, or nil when it is not in a pool (ADR 0005).
function Graph:pool(item)
    return self.poolOf[item]
end

-- Gives each item of a Dose pool, smallest Dose size first.
function Graph:poolItems(pool)
    local items = {}
    for _, size in ipairs(self.poolSizes[pool]) do
        items[#items + 1] = self.pools[pool][size]
    end
    return items
end

-- Gives each item of the Dose pool of item, or only item when it is not in a pool.
function Graph:doseSizeItems(item)
    local inPool = self.poolOf[item]
    return inPool and self:poolItems(inPool.pool) or { item }
end

-- Gives the Planning level of an item (ADR 0002).
function Graph:level(item)
    return self.levels[item]
end

-- Gives the Loop of an item, or nil when it is not in a Loop (ADR 0010).
-- A Loop is a list of its items in the order of the search.
function Graph:loop(item)
    return self.loopOf[item]
end

-- Finds each item in the Plan, through Inputs and other Outputs.
-- The table order holds each item once, in the sequence that the search finds it.
local function itemsInPlan(graph, targets)
    local order, inPlan = {}, {}
    local function find(item)
        if inPlan[item] then
            return
        end
        inPlan[item] = true
        order[#order + 1] = item
        -- The Plan can use each Dose size of a pool.
        for _, usable in ipairs(graph:doseSizeItems(item)) do
            find(usable)
        end
        for _, input in ipairs(graph:inputs(item)) do
            find(input.item)
        end
        for _, other in ipairs(graph:otherOutputs(item)) do
            find(other.item)
        end
    end
    for _, target in ipairs(targets) do
        find(target.item)
    end
    return order
end

-- Gives the links of each item.
-- An item links to its Inputs and its other Outputs.
-- An item that uses an other Output also links to the item whose Step makes it.
-- These links make sure that the Plan knows the supply of an item before it calculates the need for the item.
-- They also put the Step that makes an other Output before the Steps that use it.
local function itemLinks(graph)
    local makers = {}
    for _, item in ipairs(graph.order) do
        for _, other in ipairs(graph:otherOutputs(item)) do
            makers[other.item] = makers[other.item] or {}
            table.insert(makers[other.item], item)
        end
    end
    local linksOf = {}
    for _, item in ipairs(graph.order) do
        local linked = {}
        linksOf[item] = linked
        for _, input in ipairs(graph:inputs(item)) do
            linked[#linked + 1] = input.item
            -- A Decant step can give a Dose size from each Dose size of the pool.
            for _, usable in ipairs(graph:doseSizeItems(input.item)) do
                for _, maker in ipairs(makers[usable] or {}) do
                    if maker ~= item then
                        linked[#linked + 1] = maker
                    end
                end
            end
        end
        for _, other in ipairs(graph:otherOutputs(item)) do
            linked[#linked + 1] = other.item
        end
    end
    return linksOf
end

-- Finds the Planning level and the Loop of each item (ADR 0002, ADR 0010).
-- Stops with an error at the line of the caller of Plan.calculate.
local function findLevels(graph, targets)
    local linksOf = itemLinks(graph)

    -- All items of a Dose pool have the same Planning level, because the Plan calculates them together.
    -- The search uses one node for each pool. Config names have no spaces, so a node name cannot be an item.
    local function nodeOf(item)
        local inPool = graph.poolOf[item]
        return inPool and "Dose pool " .. inPool.pool or item
    end
    local itemsOfNode = {}
    for _, item in ipairs(graph.order) do
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
            for _, other in ipairs(linksOf[item]) do
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
    for _, target in ipairs(targets) do
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
    for _, item in ipairs(graph.order) do
        local group = groupOf[nodeOf(item)]
        if isLoop(group) then
            loopOfGroup[group] = loopOfGroup[group] or {}
            table.insert(loopOfGroup[group], item)
            loopOf[item] = loopOfGroup[group]
        end
    end
    -- The Plan cannot calculate a Dose pool in a Loop yet (issue 61).
    for _, item in ipairs(graph.order) do
        if loopOf[item] and graph.poolOf[item] then
            error("The Plan cannot calculate a Loop with a Dose pool: " .. table.concat(loopOf[item], ", ") .. ".", 4)
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
    for _, target in ipairs(targets) do
        visit(groupOf[nodeOf(target.item)], 0)
    end

    local levels, deepest = {}, 0
    for _, item in ipairs(graph.order) do
        levels[item] = levelOf[groupOf[nodeOf(item)]]
        deepest = math.max(deepest, levels[item])
    end
    return levels, loopOf, deepest
end

-- Puts the items of the Steps of one Loop in production order (ADR 0010).
-- items is in the order of the search. That order decides a tie.
-- loop is all items of the Loop, also the items with no Step.
function Graph:loopOrder(items, loop)
    local inLoop = {}
    for _, item in ipairs(loop) do
        inLoop[item] = true
    end

    -- A Step that turns an Input into a different item comes before a Step that makes only that Input.
    local function mustComeBefore(first, second)
        for _, input in ipairs(self:inputs(first)) do
            if self:makesOnly(second, input.item) and not self:makesOnly(first, input.item) then
                return true
            end
        end
        return false
    end

    -- An Output goes toward the Target when it is a Target or an Input of a Recipe outside the Loop.
    local usedOutside = {}
    for _, item in ipairs(self.order) do
        if not inLoop[item] then
            for _, input in ipairs(self:inputs(item)) do
                usedOutside[input.item] = true
            end
        end
    end
    local function goesOut(item)
        if self.targetItems[item] or usedOutside[item] then
            return true
        end
        for _, other in ipairs(self:otherOutputs(item)) do
            if self.targetItems[other.item] or usedOutside[other.item] then
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
        for position, item in ipairs(remaining) do
            if item == chosen then
                table.remove(remaining, position)
                break
            end
        end
    end
    return sorted
end

-- Builds the graph from a Basis with its Dose pool maps: poolOf and poolSizes (ADR 0005).
-- order holds each item in the Plan once, in the order of the search. deepest is the largest Planning level.
-- Stops with an error at the line of the caller of Plan.calculate.
function Graph.build(basis)
    local graph = setmetatable({
        basis = basis,
        chosen = {},
        pools = basis.pools,
        poolOf = basis.poolOf,
        poolSizes = basis.poolSizes,
        targetItems = {},
    }, Graph)
    for _, target in ipairs(basis.targets) do
        graph.targetItems[target.item] = true
    end
    graph.order = itemsInPlan(graph, basis.targets)
    graph.levels, graph.loopOf, graph.deepest = findLevels(graph, basis.targets)
    return graph
end

return Graph
