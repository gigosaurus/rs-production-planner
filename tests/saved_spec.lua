local Saved = require("plan/saved")

-- Acts as PersistentDB (docs/client-behaviour.md): Set copies the value, each Get gives a new copy,
-- and each number has float32 precision.
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
end)
