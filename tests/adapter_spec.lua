local Adapter = require("plan/adapter")
local Plan = require("plan/calculate")
local Saved = require("plan/saved")

-- Acts as PersistentDB (docs/client-behaviour.md): Set copies the value, and each Get gives a new copy.
local function fakeStore()
    local values = {}
    local function copy(value)
        if type(value) ~= "table" then
            return value
        end
        local result = {}
        for k, v in pairs(value) do
            result[k] = copy(v)
        end
        return result
    end
    local store = { values = values }
    function store.Get(_, key)
        return copy(values[key])
    end
    function store.Set(_, key, value)
        values[key] = copy(value)
        return true
    end
    return store
end

-- Gives a store that holds the given Targets as the saved plan.
local function storeWith(targets)
    local store = fakeStore()
    local saved = Saved.new(store)
    Saved.loadGlobal(saved)
    Saved.changeGlobal(saved, "plan", { targets = targets })
    Saved.write(saved)
    return store
end

local BREAD = { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE }
local RECIPES = {
    BREAD = { { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
}

-- Gives the facts of one tick with the given Inventory slots.
local function facts(inventory)
    return { inventory = inventory, recipes = RECIPES, levels = {}, stackable = {} }
end

local function slot(configName, count)
    return { id = 1, configName = configName, count = count }
end

-- Gives an Adapter on a store with the BREAD Target, with Alice logged in.
local function loggedIn()
    local adapter = Adapter.new(storeWith({ BREAD }))
    Adapter.login(adapter, "Alice")
    return adapter
end

describe("Adapter", function()
    describe("tick", function()
        it("gives a Plan from the Inventory", function()
            local adapter = loggedIn()

            local result = Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 2 } })
        end)

        it("does not count empty slots and placeholder slots", function()
            local adapter = loggedIn()
            local empty = { id = -1, configName = "", count = 0 }
            local placeholder = slot("DOUGH", 0)

            local result = Adapter.tick(adapter, facts({ empty, slot("DOUGH", 1), placeholder }))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 2 } })
        end)
    end)
end)
