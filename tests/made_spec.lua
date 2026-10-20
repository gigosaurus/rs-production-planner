local Made = require("plan/made")

describe("Made count", function()
    it("adds a rise in Detected stock to both counts", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 28 })
        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 28 })
    end)

    it("ignores a fall and counts a rise from the amount after it", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Alice", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 5 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 33 })
    end)

    it("starts a character that it has not seen at its first observation", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 50 } })
        Made.observe(states, "Bob", { detected = { SHARK = 53 } })

        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 3 })
    end)

    it("starts a Target that it has not seen at its first observation", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 46 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { ROCKTAIL = 6 })
    end)

    it("starts again from a first Bank snapshot", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 210 }, firstBank = true })
        Made.observe(states, "Alice", { detected = { SHARK = 214 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 4 })
    end)

    it("does not count a pickup, up to the ground stack decrease", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 17 }, groundDecrease = { SHARK = 5 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 2 })
    end)

    it("does not count a rise while a shop is open", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 30 }, shopOpen = true })
        Made.observe(states, "Alice", { detected = { SHARK = 31 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 1 })
    end)

    it("sets only the count of the current character in This character", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.set(states, "Alice", Made.CHARACTER, "SHARK", 50)

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 50 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 4 })
        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 54 })
    end)

    it("sets the other characters to 0 in All characters", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.set(states, "Alice", Made.ALL, "SHARK", 10)

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 10 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 0 })
        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 10 })
    end)

    it("sums only the states that it has for All characters", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        states.Bob = nil

        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 28 })
    end)

    it("does not change the states when it gives counts", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.counts(states, "Alice", Made.CHARACTER).SHARK = 0
        Made.counts(states, "Alice", Made.ALL).SHARK = 0

        expectEqual(Made.counts(states, "Carol", Made.CHARACTER), {})
        expectEqual(states.Carol, nil)
        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 28 })
    end)

    it("deletes the counts of a removed Target", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10, ROCKTAIL = 0 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 12, ROCKTAIL = 3 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.removeTarget(states, "SHARK")

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { ROCKTAIL = 3 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), {})
        expectEqual(Made.counts(states, "Alice", Made.ALL), { ROCKTAIL = 3 })
    end)

    it("starts a removed Target again when the player adds it again", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.removeTarget(states, "SHARK")
        Made.observe(states, "Alice", { detected = {} })
        Made.observe(states, "Alice", { detected = { SHARK = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 43 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 3 })
    end)

    it("deletes all counts on Make → Have", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 12 } })
        Made.stop(states)

        expectEqual(states, {})
    end)

    it("starts all characters again on Have → Make", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Bob", {
            detected = { SHARK = 4 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 12 } })
        Made.start(states, "Alice", { SHARK = 100 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 101 } })
        Made.observe(states, "Bob", { detected = { SHARK = 50 } })
        Made.observe(states, "Bob", { detected = { SHARK = 53 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 1 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 3 })
        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 4 })
    end)

    it("rejects an unknown Made count scope", function()
        local states = {}

        expectEqual(pcall(Made.counts, states, "Alice", "BOTH"), false)
    end)
end)

describe("Made count GE amount", function()
    local function offer(slot, type, stage, item, itemCount, soldCount)
        return { slot = slot, type = type, stage = stage, item = item, itemCount = itemCount, soldCount = soldCount }
    end

    it("does not count items that a BUY offer bought", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 3 })
    end)

    it("adds only the increase since the last update of the slot", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 8) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 20 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 2 })
    end)

    it("starts a new offer when the soldCount of the slot falls", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 100) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 110 } })
        Made.observe(states, "Alice", {
            detected = { SHARK = 110 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 30) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 142 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 2 })
    end)

    it("adds nothing for items that a SELL offer sold", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 8 })
    end)

    it("starts a new offer in a slot from 0", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.FINISHED, "RAW_SHARK", 100, 100) },
        })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 30) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 45 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 5 })
    end)

    it("does not count items that come back from an aborted SELL offer", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        local selling = offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 60)
        local aborting = offer(1, Made.SELL, Made.ABORTING, "SHARK", 100, 60)
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { selling } })
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(states, "Alice", { detected = { SHARK = 55 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 5 })
    end)

    it("adds nothing for an item that is not a Target", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 30) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 7 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { ROCKTAIL = 7 })
    end)

    it("rejects an unknown offer type", function()
        local states = {}
        local tick = { detected = { SHARK = 10 }, ge = { offer(1, "BYU", Made.ADDED, "SHARK", 100, 5) } }

        expectEqual(pcall(Made.observe, states, "Alice", tick), false)
    end)

    it("rejects an unknown offer stage", function()
        local states = {}
        local tick = { detected = { SHARK = 10 }, ge = { offer(1, Made.SELL, "ABORTNG", "SHARK", 100, 5) } }

        expectEqual(pcall(Made.observe, states, "Alice", tick), false)
    end)

    it("subtracts a pickup before the rise uses up the GE amount", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 3) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 15 }, groundDecrease = { SHARK = 4 } })
        Made.observe(states, "Alice", { detected = { SHARK = 17 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), {})
    end)

    it("keeps a GE amount for each character", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 3 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 4 })
        expectEqual(Made.counts(states, "Alice", Made.ALL), { SHARK = 7 })
    end)

    it("starts the GE slots from the offers on Have → Make", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20) })
        Made.stop(states)
        Made.start(states, "Alice", { SHARK = 80 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 80 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 80) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 90 } })
        Made.observe(states, "Alice", { detected = { SHARK = 140 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 50 })
    end)

    it("adds no GE amount for the offers on Have → Make", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", { detected = { SHARK = 80 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 70 })
    end)

    it("keeps the GE slots of other characters on Have → Make", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", {
            detected = { SHARK = 0 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", {
            detected = { SHARK = 0 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 8) },
        })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })

        expectEqual(Made.counts(states, "Bob", Made.CHARACTER), { SHARK = 1 })
    end)

    it("starts again at a load and keeps the counts", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 15 } })
        Made.load(states, "Alice", {})
        Made.observe(states, "Alice", { detected = { SHARK = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 42 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 7 })
    end)

    it("deletes the GE amount at a load", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.load(states, "Alice", { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) })
        Made.observe(states, "Alice", { detected = { SHARK = 10 } })
        Made.observe(states, "Alice", { detected = { SHARK = 15 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 5 })
    end)

    it("starts the GE slots from the offers at a load", function()
        local states = {}
        Made.start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20) })
        Made.load(states, "Alice", { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 80 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 80) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 90 } })
        Made.observe(states, "Alice", { detected = { SHARK = 140 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER), { SHARK = 50 })
    end)

    it("rejects an unknown offer stage at a load", function()
        local states = {}
        local ok, message = pcall(Made.load, states, "Alice", { offer(1, Made.BUY, "ADED", "SHARK", 100, 5) })

        expectEqual(ok, false)
        expectEqual(message:find("The GE offer stage ADED is unknown.", 1, true) ~= nil, true)
    end)
end)
