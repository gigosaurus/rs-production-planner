local Made = require("plan/made")

describe("Made count", function()
    it("adds a rise in Detected stock to both counts", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 38 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 28 })
        expectEqual(Made.counts(state, "Alice", Made.ALL), { SHARK = 28 })
    end)

    it("ignores a fall and counts a rise from the amount after it", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 38 } })
        Made.observe(state, "Alice", { detected = { SHARK = 0 } })
        Made.observe(state, "Alice", { detected = { SHARK = 5 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 33 })
    end)

    it("starts a character that it has not seen at its first observation", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Bob", { detected = { SHARK = 50 } })
        Made.observe(state, "Bob", { detected = { SHARK = 53 } })

        expectEqual(Made.counts(state, "Bob", Made.CHARACTER), { SHARK = 3 })
    end)

    it("starts a Target that it has not seen at its first observation", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 10, ROCKTAIL = 40 } })
        Made.observe(state, "Alice", { detected = { SHARK = 10, ROCKTAIL = 46 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { ROCKTAIL = 6 })
    end)

    it("starts again from a first Bank snapshot", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 210 }, firstBank = true })
        Made.observe(state, "Alice", { detected = { SHARK = 214 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 4 })
    end)

    it("does not count a pickup, up to the ground stack decrease", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 17 }, groundDecrease = { SHARK = 5 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 2 })
    end)

    it("does not count a rise while a shop is open", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 30 }, shopOpen = true })
        Made.observe(state, "Alice", { detected = { SHARK = 31 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 1 })
    end)

    it("sets only the count of the selected scope", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 38 } })
        Made.set(state, "Alice", Made.CHARACTER, "SHARK", 50)
        Made.set(state, "Alice", Made.ALL, "SHARK", 0)
        Made.observe(state, "Alice", { detected = { SHARK = 40 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 52 })
        expectEqual(Made.counts(state, "Alice", Made.ALL), { SHARK = 2 })
    end)

    it("deletes the counts of a removed Target", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10, ROCKTAIL = 0 })
        Made.observe(state, "Bob", { detected = { SHARK = 0 } })
        Made.observe(state, "Alice", { detected = { SHARK = 12, ROCKTAIL = 3 } })
        Made.observe(state, "Bob", { detected = { SHARK = 4 } })
        Made.removeTarget(state, "SHARK")

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { ROCKTAIL = 3 })
        expectEqual(Made.counts(state, "Bob", Made.CHARACTER), {})
        expectEqual(Made.counts(state, "Alice", Made.ALL), { ROCKTAIL = 3 })
    end)

    it("starts a removed Target again when the player adds it again", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.removeTarget(state, "SHARK")
        Made.observe(state, "Alice", { detected = {} })
        Made.observe(state, "Alice", { detected = { SHARK = 40 } })
        Made.observe(state, "Alice", { detected = { SHARK = 43 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 3 })
    end)

    it("deletes all counts on Make → Have", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", { detected = { SHARK = 12 } })
        Made.stop(state)

        expectEqual(state, Made.new())
    end)

    it("starts all characters again on Have → Make", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Bob", { detected = { SHARK = 0 } })
        Made.observe(state, "Bob", {
            detected = { SHARK = 4 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 12 } })
        Made.start(state, "Alice", { SHARK = 100 })
        Made.observe(state, "Alice", { detected = { SHARK = 101 } })
        Made.observe(state, "Bob", { detected = { SHARK = 50 } })
        Made.observe(state, "Bob", { detected = { SHARK = 53 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 1 })
        expectEqual(Made.counts(state, "Bob", Made.CHARACTER), { SHARK = 3 })
        expectEqual(Made.counts(state, "Alice", Made.ALL), { SHARK = 4 })
    end)

    it("rejects an unknown Made count scope", function()
        local state = Made.new()

        expectEqual(pcall(Made.counts, state, "Alice", "BOTH"), false)
    end)
end)

describe("Made count GE amount", function()
    local function offer(slot, type, stage, item, itemCount, soldCount)
        return { slot = slot, type = type, stage = stage, item = item, itemCount = itemCount, soldCount = soldCount }
    end

    it("does not count items that a BUY offer bought", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 3 })
    end)

    it("adds only the increase since the last update of the slot", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 8) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 20 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 2 })
    end)

    it("adds nothing for items that a SELL offer sold", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 8 })
    end)

    it("starts a new offer in a slot from 0", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.FINISHED, "RAW_SHARK", 100, 100) },
        })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 30) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 45 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 5 })
    end)

    it("does not count items that come back from an aborted SELL offer", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        local selling = offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 60)
        local aborting = offer(1, Made.SELL, Made.ABORTING, "SHARK", 100, 60)
        Made.observe(state, "Alice", { detected = { SHARK = 10 }, ge = { selling } })
        Made.observe(state, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(state, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(state, "Alice", { detected = { SHARK = 55 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 5 })
    end)

    it("adds nothing for an item that is not a Target", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 30) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 10, ROCKTAIL = 0 } })
        Made.observe(state, "Alice", { detected = { SHARK = 10, ROCKTAIL = 7 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { ROCKTAIL = 7 })
    end)

    it("rejects an unknown offer type", function()
        local state = Made.new()
        local tick = { detected = { SHARK = 10 }, ge = { offer(1, "BYU", Made.ADDED, "SHARK", 100, 5) } }

        expectEqual(pcall(Made.observe, state, "Alice", tick), false)
    end)

    it("rejects an unknown offer stage", function()
        local state = Made.new()
        local tick = { detected = { SHARK = 10 }, ge = { offer(1, Made.SELL, "ABORTNG", "SHARK", 100, 5) } }

        expectEqual(pcall(Made.observe, state, "Alice", tick), false)
    end)

    it("subtracts a pickup before the rise uses up the GE amount", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 3) },
        })
        Made.observe(state, "Alice", { detected = { SHARK = 15 }, groundDecrease = { SHARK = 4 } })
        Made.observe(state, "Alice", { detected = { SHARK = 17 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), {})
    end)

    it("keeps a GE amount for each character", function()
        local state = Made.new()
        Made.start(state, "Alice", { SHARK = 10 })
        Made.observe(state, "Bob", { detected = { SHARK = 0 } })
        Made.observe(state, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(state, "Bob", { detected = { SHARK = 4 } })
        Made.observe(state, "Alice", { detected = { SHARK = 18 } })

        expectEqual(Made.counts(state, "Alice", Made.CHARACTER), { SHARK = 3 })
        expectEqual(Made.counts(state, "Bob", Made.CHARACTER), { SHARK = 4 })
        expectEqual(Made.counts(state, "Alice", Made.ALL), { SHARK = 7 })
    end)
end)
