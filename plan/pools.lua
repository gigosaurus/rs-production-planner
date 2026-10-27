-- The Dose pool stage of the Plan (ADR 0005, issue 39). The Plan counts a pool as doses.
-- It does not use the game API. Tests run it through Plan.calculate.
local Pools = {}

local DECANT = "Decant"

-- The demand and the Decant steps take Counted stock first, then the other Outputs of Steps,
-- then the containers that the Recipe makes.
local POOL_SOURCES = { "counted", "supplied", "made" }

-- Calculates the Steps of one Dose pool from the totals of the Plan. It changes no table of totals.
-- A Recipe makes the doses that Counted stock and the other Outputs of Steps do not give.
-- Then Decant steps give each Dose size that is short. A Decant step takes the smallest Dose size first.
-- The doses that remain after a Decant step go into one container.
-- The made containers that the Plan does not use are Leftovers of the pool.
-- The other Outputs that the Plan does not use are Leftovers of the Steps that make them.
--
-- totals has:
-- - stock(item): the Counted stock of an item. detected(item): its Detected stock.
-- - demand and supply: the totals of each item. supply is the other Outputs of Steps.
-- - supplyLevelOf: the lowest Planning level of a Step that makes the item as an other Output.
-- newStep(item, recipe, need) makes a Step.
--
-- It gives a table with:
-- - step: the Step of the Recipe of the pool, or nil.
-- - decants: the Decant steps, in order.
-- - decantLevel: the Decant steps come after the Steps of this Planning level. It is nil when no other Output is in the pool.
--   A Step that uses a Dose size links to each Step that makes an other Output in the same pool.
--   Thus that Step comes after the Decant steps.
-- - short: the Shortage { item, count }, or nil. With no Recipe, it is in containers of the largest Dose size.
-- - used: the used supply of each item of the pool.
-- - last: the last Step of the pool, or nil. leftovers: the Leftovers of the pool, after that Step.
function Pools.plan(graph, pool, totals, newStep)
    -- The Dose sizes of a pool are 1 to N with no gap, so the index of an item is its Dose size.
    local items, sizes = graph:poolItems(pool), graph:doseSizes(pool)
    local result = { decants = {}, used = {}, leftovers = {} }
    -- spare gives the containers of each source and Dose size that the demand does not use.
    local balance, short, doses = {}, {}, 0
    local spare = { counted = {}, supplied = {}, made = {} }
    for _, size in ipairs(sizes) do
        local item = items[size]
        local counted, supplied, demanded = totals.stock(item), totals.supply[item] or 0, totals.demand[item] or 0
        if supplied > 0 then
            local level = totals.supplyLevelOf[item]
            result.decantLevel = math.min(result.decantLevel or level, level)
        end
        balance[size] = counted + supplied - demanded
        spare.counted[size] = math.max(0, counted - demanded)
        spare.supplied[size] = math.max(0, math.min(supplied, balance[size]))
        spare.made[size] = 0
        doses = doses + balance[size] * size
    end
    for _, size in ipairs(sizes) do
        local recipe = graph:recipe(items[size])
        if doses < 0 and recipe then
            result.step = newStep(items[size], recipe, math.ceil(-doses / size))
            result.last = result.step
            balance[size] = balance[size] + result.step.actions * recipe.output
            spare.made[size] = math.max(0, balance[size]) - spare.counted[size] - spare.supplied[size]
            doses = 0
            break
        end
    end
    -- The player gets the Shortage before the Decant steps, so it counts as Counted stock.
    if doses < 0 then
        local largest = sizes[#sizes]
        local count = math.ceil(-doses / largest)
        result.short = { item = items[largest], count = count }
        balance[largest] = balance[largest] + count
        spare.counted[largest] = math.max(0, balance[largest]) - spare.supplied[largest]
    end
    for _, size in ipairs(sizes) do
        short[size] = math.max(0, -balance[size])
    end
    for _, size in ipairs(sizes) do
        if short[size] > 0 then
            local step =
                { item = items[size], verb = DECANT, decant = true, actions = short[size], flags = {}, inputs = {} }
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
                        detected = totals.detected(items[from]),
                    }
                end
            end
            if missing < 0 then
                spare.made[-missing] = spare.made[-missing] + 1
            end
            result.decants[#result.decants + 1] = step
            result.last = step
        end
    end
    for _, size in ipairs(sizes) do
        result.used[items[size]] = (totals.supply[items[size]] or 0) - spare.supplied[size]
    end
    for _, size in ipairs(sizes) do
        if spare.made[size] > 0 then
            table.insert(result.leftovers, { item = items[size], count = spare.made[size] })
        end
    end
    return result
end

return Pools
