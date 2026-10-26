local Adapter = require("plan/adapter")
local Assumed = require("plan/assumed")
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
-- assumed maps each item to the Assumed stock of Alice, added when she had no Detected stock.
local function storeWith(targets, assumed)
    local store = fakeStore()
    local saved = Saved.new(store)
    Saved.loadGlobal(saved)
    Saved.changeGlobal(saved, "plan", { targets = targets })
    if assumed then
        local states = { Alice = Assumed.new() }
        for item, amount in pairs(assumed) do
            Assumed.add(states, "Alice", item, amount, {})
        end
        Saved.loadCharacter(saved, "Alice")
        Saved.change(saved, "Alice", "assumed", states.Alice)
    end
    Saved.write(saved)
    return store
end

local BREAD = { id = 1, item = "BREAD", count = 5, mode = Plan.HAVE }
local RECIPES = {
    BREAD = { { verb = "Bake", output = 2, actionLimit = 60, inputs = { { item = "DOUGH", count = 1 } } } },
}

local STACKABLE = {}

-- Gives the facts of one tick with the given Inventory slots.
local function facts(inventory)
    return { inventory = inventory, recipes = RECIPES, levels = {}, stackable = STACKABLE }
end

local function slot(configName, count)
    return { id = 1, configName = configName, count = count }
end

-- Gives an Adapter on a store with the BREAD Target, with Alice logged in.
local function loggedIn(assumed)
    local adapter = Adapter.new(storeWith({ BREAD }, assumed))
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

        it("gives no diff for the first Plan", function()
            local adapter = loggedIn()

            local result = Adapter.tick(adapter, facts({}))

            expectEqual(result.diff, nil)
        end)

        it("gives nothing when the Basis did not change", function()
            local adapter = loggedIn()
            Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))

            expectEqual(Adapter.tick(adapter, facts({ slot("DOUGH", 1) })), nil)
        end)

        it("calculates again when Counted stock changed, and gives the diff", function()
            local adapter = loggedIn()
            Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))

            local result = Adapter.tick(adapter, facts({ slot("DOUGH", 3) }))

            expectEqual({ result.plan.shortages, result.diff.covered }, { {}, { "DOUGH" } })
        end)

        it("calculates again when a level changed", function()
            local adapter = loggedIn()
            local before = facts({})
            before.levels = { COOKING = 1 }
            Adapter.tick(adapter, before)
            local after = facts({})
            after.levels = { COOKING = 2 }

            expectEqual(Adapter.tick(adapter, after) ~= nil, true)
        end)
    end)

    describe("bank", function()
        it("counts the Bank snapshot with the Inventory", function()
            local adapter = loggedIn()

            Adapter.bank(adapter, { slot("DOUGH", 1) })
            local result = Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 1 } })
        end)

        it("does not count empty slots and placeholder slots in the bank", function()
            local adapter = loggedIn()

            Adapter.bank(adapter, { { id = -1, configName = "", count = 0 }, slot("DOUGH", 1), slot("BREAD", 0) })
            local result = Adapter.tick(adapter, facts({}))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 2 } })
        end)

        it("tells if the bank of the character was seen", function()
            local adapter = loggedIn()
            local before = Adapter.bankSeen(adapter)

            Adapter.bank(adapter, {})

            expectEqual({ before, Adapter.bankSeen(adapter) }, { false, true })
        end)
    end)

    describe("Assumed stock", function()
        it("is used up by a rise in the Inventory", function()
            local adapter = loggedIn({ DOUGH = 2 })
            Adapter.tick(adapter, facts({}))

            local result = Adapter.tick(adapter, facts({ slot("DOUGH", 2) }))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 1 } })
        end)

        it("is not used up by the first Bank snapshot", function()
            local adapter = loggedIn({ DOUGH = 2 })
            Adapter.tick(adapter, facts({}))

            Adapter.bank(adapter, { slot("DOUGH", 2) })
            local result = Adapter.tick(adapter, facts({}))

            expectEqual(result.plan.shortages, {})
        end)

        it("is used up by a rise in a later Bank snapshot", function()
            local adapter = loggedIn({ DOUGH = 2 })
            Adapter.bank(adapter, {})
            Adapter.tick(adapter, facts({}))

            Adapter.bank(adapter, { slot("DOUGH", 2) })
            local result = Adapter.tick(adapter, facts({}))

            expectEqual(result.plan.shortages, { { item = "DOUGH", count = 1 } })
        end)
    end)

    describe("login and leave", function()
        it("gives nothing after leave, until the next login", function()
            local adapter = loggedIn()
            Adapter.tick(adapter, facts({}))

            Adapter.leave(adapter)
            local away = Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))
            Adapter.login(adapter, "Alice")
            local back = Adapter.tick(adapter, facts({ slot("DOUGH", 1) }))

            expectEqual({ away, back.plan.shortages, back.diff }, { nil, { { item = "DOUGH", count = 2 } }, nil })
        end)

        it("gives a Plan on the first tick after a login, also when the Basis did not change", function()
            local adapter = loggedIn()
            Adapter.tick(adapter, facts({}))

            Adapter.leave(adapter)
            Adapter.login(adapter, "Alice")

            expectEqual(Adapter.tick(adapter, facts({})) ~= nil, true)
        end)

        it("uses the Bank snapshot of the character that logged in", function()
            local adapter = loggedIn()
            Adapter.bank(adapter, { slot("DOUGH", 1) })

            Adapter.leave(adapter)
            Adapter.login(adapter, "Bob")
            local bob = { Adapter.bankSeen(adapter), Adapter.tick(adapter, facts({})).plan.shortages }
            Adapter.leave(adapter)
            Adapter.login(adapter, "Alice")
            local alice = { Adapter.bankSeen(adapter), Adapter.tick(adapter, facts({})).plan.shortages }

            expectEqual(
                { bob, alice },
                { { false, { { item = "DOUGH", count = 3 } } }, { true, { { item = "DOUGH", count = 2 } } } }
            )
        end)
    end)

    describe("save", function()
        it("keeps the Bank snapshot for a new Adapter on the same store", function()
            local store = storeWith({ BREAD })
            local first = Adapter.new(store)
            Adapter.login(first, "Alice")
            Adapter.bank(first, { slot("DOUGH", 1) })

            Adapter.save(first)
            local second = Adapter.new(store)
            Adapter.login(second, "Alice")

            expectEqual(
                { Adapter.bankSeen(second), Adapter.tick(second, facts({})).plan.shortages },
                { true, { { item = "DOUGH", count = 2 } } }
            )
        end)

        it("keeps the Assumed stock that is left for a new Adapter on the same store", function()
            local store = storeWith({ BREAD }, { DOUGH = 2 })
            local first = Adapter.new(store)
            Adapter.login(first, "Alice")
            Adapter.tick(first, facts({}))
            Adapter.tick(first, facts({ slot("DOUGH", 1) }))

            Adapter.save(first)
            local second = Adapter.new(store)
            Adapter.login(second, "Alice")

            expectEqual(
                Adapter.tick(second, facts({ slot("DOUGH", 1) })).plan.shortages,
                { { item = "DOUGH", count = 1 } }
            )
        end)

        it("gives a problem for a part that the store does not save", function()
            local store = storeWith({ BREAD }, { DOUGH = 2 })
            local adapter = Adapter.new(store)
            Adapter.login(adapter, "Alice")
            Adapter.bank(adapter, { slot("DOUGH", 1) })
            function store.Set()
                return false
            end

            expectEqual(Adapter.save(adapter), { { key = "char:Alice:bank", kind = Saved.NOT_SAVED } })
        end)
    end)

    describe("load", function()
        it("gives a problem for a saved part with an unknown version", function()
            local store = storeWith({ BREAD }, { DOUGH = 2 })
            store.values["char:Alice:reserves"] = { v = 99 }

            local _, problems = Adapter.new(store)

            expectEqual(problems, { { key = "char:Alice:reserves", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("gives a problem at the login of a new character with an unknown version", function()
            local store = storeWith({ BREAD })
            store.values["char:Bob:reserves"] = { v = 99 }
            local adapter = Adapter.new(store)

            expectEqual(Adapter.login(adapter, "Bob"), { { key = "char:Bob:reserves", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("does not read a saved character again at its login", function()
            local store = storeWith({ BREAD }, { DOUGH = 2 })
            local adapter = Adapter.new(store)
            local reads = 0
            local get = store.Get
            function store.Get(...)
                reads = reads + 1
                return get(...)
            end

            Adapter.login(adapter, "Alice")

            expectEqual(reads, 0)
        end)
    end)
end)
