local Assumed = require("plan/assumed")
local Saved = require("plan/saved")

-- Acts as PersistentDB (docs/client-behaviour.md): Set copies the value, each Get gives a new copy,
-- and each number has float32 precision. When full is true, Set saves nothing and returns false.
local function fakeStore()
    local values = {}
    local function copy(value)
        if type(value) == "number" then
            return string.unpack("f", string.pack("f", value))
        end
        if type(value) ~= "table" then
            return value
        end
        local result = {}
        for k, v in pairs(value) do
            result[k] = copy(v)
        end
        return result
    end
    local store = { values = values, sets = 0, full = false }
    function store.Get(_, key)
        return copy(values[key])
    end
    function store.Set(_, key, value)
        store.sets = store.sets + 1
        if store.full then
            return false
        end
        values[key] = copy(value)
        return true
    end
    return store
end

describe("Saved data", function()
    describe("Bank snapshot", function()
        it("loads the Bank snapshot that it wrote", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { SNAPE_GRASS = 5, COINS = 2147483647 })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, { SNAPE_GRASS = 5, COINS = 2147483647 })
        end)

        it("writes one line for each item after the version line", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { SNAPE_GRASS = 5, COINS = 1200000 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=1200000\nSNAPE_GRASS=5\n")
        end)

        it("reads the count after the last = of a line", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=1\nA=B=7\n")

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, { ["A=B"] = 7 })
        end)

        it("gives no Bank snapshot to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.bank, nil)
        end)
    end)

    describe("versions", function()
        it("gives no problems for a key at a known version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=1\nCOINS=5\n")

            local _, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(problems, {})
        end)

        it("does not read a key with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=2\nCOINS=5\n")

            local parts, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, nil)
            expectEqual(problems, { { key = "char:Alice:bank", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("does not read a key with no version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "COINS=5\n")

            local parts, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.bank, nil)
            expectEqual(problems, { { key = "char:Alice:bank", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("does not write a key with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:bank", "v=2\nCOINS=5\n")
            local saved = Saved.new(store)
            Saved.loadCharacter(saved, "Alice")
            Saved.change(saved, "Alice", "bank", { COINS = 9 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=2\nCOINS=5\n")
        end)
    end)

    describe("writes", function()
        it("writes a part that changed two times in one tick one time, with the last value", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.change(saved, "Alice", "bank", { COINS = 2 })
            Saved.write(saved)

            expectEqual(store.sets, 1)
            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=2\n")
        end)

        it("gives no problems when each part is saved", function()
            local saved = Saved.new(fakeStore())
            Saved.change(saved, "Alice", "bank", { COINS = 1 })

            expectEqual(Saved.write(saved), {})
        end)

        it("gives a problem when the store does not save a part", function()
            local store = fakeStore()
            store.full = true
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })

            expectEqual(Saved.write(saved), { { key = "char:Alice:bank", kind = Saved.NOT_SAVED } })
        end)

        it("does not try again in the next tick after the store does not save a part", function()
            local store = fakeStore()
            store.full = true
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.write(saved)
            Saved.write(saved)

            expectEqual(store.sets, 1)
        end)

        it("tries again after the next change to the part", function()
            local store = fakeStore()
            store.full = true
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "bank", { COINS = 1 })
            Saved.write(saved)
            store.full = false
            Saved.change(saved, "Alice", "bank", { COINS = 2 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:bank"], "v=1\nCOINS=2\n")
        end)
    end)

    describe("Assumed stock", function()
        local function assumedState()
            local state = Assumed.new()
            Assumed.add(state, "COINS", 20000001, { COINS = 16777217 })
            return state
        end

        it("loads the Assumed stock that it wrote", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "assumed", assumedState())
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.assumed, assumedState())
        end)

        it("writes each count as a decimal string", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "assumed", assumedState())
            Saved.write(saved)

            expectEqual(store.values["char:Alice:assumed"], {
                v = 1,
                entries = {
                    { item = "COINS", entered = "20000001", remaining = "20000001", baseline = "16777217" },
                },
            })
        end)

        it("gives no Assumed stock to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.assumed, Assumed.new())
        end)

        it("does not read Assumed stock with a newer version", function()
            local store = fakeStore()
            store:Set("char:Alice:assumed", { v = 2, entries = {} })

            local _, problems = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(problems, { { key = "char:Alice:assumed", kind = Saved.UNKNOWN_VERSION } })
        end)

        it("gives no Assumed stock when the version is newer", function()
            local store = fakeStore()
            store:Set("char:Alice:assumed", { v = 2, entries = { { item = "COINS" } } })

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.assumed, Assumed.new())
        end)
    end)

    describe("Reserves", function()
        it("loads the Reserves that it wrote", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "reserves", { COINS = 20000001, SNAPE_GRASS = 5 })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.reserves, { COINS = 20000001, SNAPE_GRASS = 5 })
        end)

        it("writes each count as a decimal string", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "reserves", { SNAPE_GRASS = 5 })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:reserves"], { v = 1, reserves = { SNAPE_GRASS = "5" } })
        end)

        it("gives no Reserves to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.reserves, {})
        end)
    end)

    describe("Unlocks", function()
        it("loads the Unlocks that it wrote", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "unlocks", { ZAROS_GODSWORD = true })
            Saved.write(saved)

            local parts = Saved.loadCharacter(Saved.new(store), "Alice")

            expectEqual(parts.unlocks, { ZAROS_GODSWORD = true })
        end)

        it("writes the Unlocks as a set", function()
            local store = fakeStore()
            local saved = Saved.new(store)
            Saved.change(saved, "Alice", "unlocks", { ZAROS_GODSWORD = true })
            Saved.write(saved)

            expectEqual(store.values["char:Alice:unlocks"], { v = 1, unlocks = { ZAROS_GODSWORD = true } })
        end)

        it("gives no Unlocks to a character that the plugin has not seen", function()
            local parts = Saved.loadCharacter(Saved.new(fakeStore()), "Alice")

            expectEqual(parts.unlocks, {})
        end)
    end)
end)
