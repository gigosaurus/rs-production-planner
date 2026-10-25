local Made = require("plan/made")

-- The Make Targets of the tests. Made gets the Detected stock of all items from its caller.
local SHARK = { id = 1, item = "SHARK", count = 100 }
local ROCKTAIL = { id = 2, item = "ROCKTAIL", count = 100 }

local function start(states, name, detected, offers)
    Made.startTarget(states, name, SHARK, detected, offers)
end

local function sharkCount(states, name, scope)
    return Made.counts(states, name, scope, { SHARK })[SHARK.id]
end

describe("Made count", function()
    it("adds a rise in Detected stock to both counts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 28)
        expectEqual(sharkCount(states, "Alice", Made.ALL), 28)
    end)

    it("ignores a fall and counts a rise from the amount after it", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Alice", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 5 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 33)
    end)

    it("starts a character that it has not seen at its first observation", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 50 } })
        Made.observe(states, "Bob", { detected = { SHARK = 53 } })

        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 3)
    end)

    it("starts to count an item with no Detected stock at its first observation", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.startTarget(states, "Alice", ROCKTAIL, {}, {})
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 46 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { SHARK, ROCKTAIL }), { [1] = 0, [2] = 6 })
    end)

    it("counts an item that is not in Detected stock as 0", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = {} })
        Made.observe(states, "Alice", { detected = { SHARK = 8 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 8)
    end)

    it("starts again from a first Bank snapshot", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 210 }, firstBank = true })
        Made.observe(states, "Alice", { detected = { SHARK = 214 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 4)
    end)

    it("does not count a pickup, up to the ground stack decrease", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 17 }, groundDecrease = { SHARK = 5 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 2)
    end)

    it("does not count a rise while a shop is open", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 30 }, shopOpen = true })
        Made.observe(states, "Alice", { detected = { SHARK = 31 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 1)
    end)

    it("sets only the count of the current character in This character", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.set(states, "Alice", Made.CHARACTER, SHARK, 50)

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 50)
        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 4)
        expectEqual(sharkCount(states, "Alice", Made.ALL), 54)
    end)

    it("sets the other characters to 0 in All characters", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.set(states, "Alice", Made.ALL, SHARK, 10)

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 10)
        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 0)
        expectEqual(sharkCount(states, "Alice", Made.ALL), 10)
    end)

    it("sums only the states that it has for All characters", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        states.Bob = nil

        expectEqual(sharkCount(states, "Alice", Made.ALL), 28)
    end)

    it("does not change the states when it gives counts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 38 } })
        Made.counts(states, "Alice", Made.CHARACTER, { SHARK })[1] = 0
        Made.counts(states, "Alice", Made.ALL, { SHARK })[1] = 0

        expectEqual(sharkCount(states, "Carol", Made.CHARACTER), 0)
        expectEqual(states.Carol, nil)
        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 28)
    end)

    it("starts a forgotten item again when the player adds a Target for it", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.stopTarget(states, SHARK, {})
        start(states, "Alice", {}, {})
        Made.observe(states, "Alice", { detected = { SHARK = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 43 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 3)
    end)

    it("deletes all states when no Make Target remains", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 12 } })
        Made.stopTarget(states, SHARK, {})

        expectEqual(states, {})
    end)

    it("starts all characters again when the first Make Target starts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Bob", {
            detected = { SHARK = 4 },
            ge = { { slot = 1, type = Made.BUY, stage = Made.ADDED, item = "SHARK", itemCount = 100, soldCount = 5 } },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 12 } })
        Made.stopTarget(states, SHARK, {})
        start(states, "Alice", { SHARK = 100 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 101 } })
        Made.observe(states, "Bob", { detected = { SHARK = 50 } })
        Made.observe(states, "Bob", { detected = { SHARK = 53 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 1)
        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 3)
        expectEqual(sharkCount(states, "Alice", Made.ALL), 4)
    end)

    it("rejects an unknown Made count scope", function()
        local states = {}

        expectEqual(pcall(Made.counts, states, "Alice", "BOTH", { SHARK }), false)
    end)

    for _, case in ipairs({
        { name = "a negative count", value = -3 },
        { name = "a fraction", value = 2.5 },
        { name = "no count", value = nil },
    }) do
        it("rejects " .. case.name .. " at an edit", function()
            local states = {}
            start(states, "Alice", { SHARK = 10 }, {})
            local ok, message = pcall(Made.set, states, "Alice", Made.CHARACTER, SHARK, case.value)

            expectEqual(ok, false)
            expectEqual(
                message:find("The Made count of SHARK must be a whole number of 0 or more.", 1, true) ~= nil,
                true
            )
        end)
    end
end)

describe("Made count GE amount", function()
    local function offer(slot, type, stage, item, itemCount, soldCount)
        return { slot = slot, type = type, stage = stage, item = item, itemCount = itemCount, soldCount = soldCount }
    end

    it("does not count items that a BUY offer bought", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 3)
    end)

    it("adds only the increase since the last update of the slot", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 8) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 20 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 2)
    end)

    it("starts a new offer when the soldCount of the slot falls", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
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

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 2)
    end)

    it("adds nothing for items that a SELL offer sold", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 8)
    end)

    it("starts a new offer in a slot from 0", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.SELL, Made.FINISHED, "RAW_SHARK", 100, 100) },
        })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 30) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 45 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 5)
    end)

    it("does not count items that come back from an aborted SELL offer", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        local selling = offer(1, Made.SELL, Made.ADDED, "SHARK", 100, 60)
        local aborting = offer(1, Made.SELL, Made.ABORTING, "SHARK", 100, 60)
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { selling } })
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(states, "Alice", { detected = { SHARK = 10 }, ge = { aborting } })
        Made.observe(states, "Alice", { detected = { SHARK = 55 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 5)
    end)

    it("gives the same count with an observation before the first Make Target", function()
        local bought = offer(0, Made.BUY, Made.FINISHED, "SHARK", 10, 10)
        local function collect(observeFirst)
            local states = {}
            if observeFirst then
                Made.observe(states, "Alice", { detected = {} })
            end
            start(states, "Alice", {}, { bought })
            Made.observe(states, "Alice", { detected = {}, ge = { bought } })
            Made.observe(states, "Alice", { detected = { SHARK = 10 } })
            return sharkCount(states, "Alice", Made.CHARACTER)
        end

        expectEqual(collect(true), collect(false))
    end)

    it("adds nothing for an item that is not a Make Target", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 30) },
        })
        Made.startTarget(states, "Alice", ROCKTAIL, { ROCKTAIL = 0 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 7 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { ROCKTAIL }), { [2] = 7 })
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
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 3) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 15 }, groundDecrease = { SHARK = 4 } })
        Made.observe(states, "Alice", { detected = { SHARK = 17 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 0)
    end)

    it("keeps a GE amount for each character", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Bob", { detected = { SHARK = 0 } })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.observe(states, "Bob", { detected = { SHARK = 4 } })
        Made.observe(states, "Alice", { detected = { SHARK = 18 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 3)
        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 4)
        expectEqual(sharkCount(states, "Alice", Made.ALL), 7)
    end)

    it("starts the GE slots from the offers when the first Make Target starts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20) })
        Made.stopTarget(states, SHARK, {})
        start(states, "Alice", { SHARK = 80 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 80 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 80) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 90 } })
        Made.observe(states, "Alice", { detected = { SHARK = 140 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 50)
    end)

    it("adds no GE amount for the offers when the first Make Target starts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", { detected = { SHARK = 80 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 70)
    end)

    it("starts again at a load and keeps the counts", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 15 } })
        Made.load(states, "Alice", {})
        Made.observe(states, "Alice", { detected = { SHARK = 40 } })
        Made.observe(states, "Alice", { detected = { SHARK = 42 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 7)
    end)

    it("keeps the GE amount at a load", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) },
        })
        Made.load(states, "Alice", { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 5) })
        Made.observe(states, "Alice", { detected = { SHARK = 10 } })
        Made.observe(states, "Alice", { detected = { SHARK = 15 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 0)
    end)

    it("does not count items that a BUY offer bought between sessions", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20) })
        Made.load(states, "Alice", { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 80 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 80) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 90 } })
        Made.observe(states, "Alice", { detected = { SHARK = 140 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 0)
    end)

    it("adds no GE amount at a load for an item that is not a Make Target", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, { offer(2, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 0) })
        Made.load(states, "Alice", { offer(2, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 30) })
        Made.startTarget(states, "Alice", ROCKTAIL, { ROCKTAIL = 0 }, {})
        Made.observe(states, "Alice", { detected = { SHARK = 10, ROCKTAIL = 30 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { ROCKTAIL }), { [2] = 30 })
    end)

    it("adds no GE amount at the first load of a character", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        Made.load(states, "Bob", { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70) })
        Made.observe(states, "Bob", { detected = { SHARK = 10 } })
        Made.observe(states, "Bob", { detected = { SHARK = 80 } })

        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 70)
    end)

    it("adds no GE amount at a load when the state has no saved slots", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {})
        states.Bob = Made.new()
        Made.load(states, "Bob", { offer(1, Made.BUY, Made.ADDED, "SHARK", 1000, 1000) })
        Made.observe(states, "Bob", { detected = { SHARK = 10 } })
        Made.observe(states, "Bob", { detected = { SHARK = 80 } })

        expectEqual(sharkCount(states, "Bob", Made.CHARACTER), 70)
    end)

    it("deletes the GE amount at a load when no offer has the item", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 0) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 50) },
        })
        Made.load(states, "Alice", { offer(2, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 0) })
        Made.observe(states, "Alice", { detected = { SHARK = 60 } })
        Made.observe(states, "Alice", { detected = { SHARK = 110 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 50)
    end)

    it("deletes the saved slots that have no offer at a load", function()
        local states = {}
        start(states, "Alice", { SHARK = 10 }, {
            offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20),
            offer(2, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 0),
        })
        Made.load(states, "Alice", { offer(2, Made.BUY, Made.ADDED, "ROCKTAIL", 100, 0) })
        Made.observe(states, "Alice", {
            detected = { SHARK = 10 },
            ge = { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 30) },
        })
        Made.observe(states, "Alice", { detected = { SHARK = 40 } })

        expectEqual(sharkCount(states, "Alice", Made.CHARACTER), 0)
    end)

    it("rejects an unknown offer stage at a load", function()
        local states = {}
        local ok, message = pcall(function()
            Made.load(states, "Alice", { offer(1, Made.BUY, "ADED", "SHARK", 100, 5) })
        end)

        expectEqual(ok, false)
        expectEqual(message:find("made_spec.lua:%d+: The GE offer stage ADED is unknown%.") ~= nil, true)
    end)

    it("changes no state when a load has an unknown offer stage", function()
        local function saved()
            local states = {}
            start(states, "Alice", { SHARK = 10 }, { offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 20) })
            return states
        end
        local states = saved()
        local ok, message = pcall(function()
            Made.load(states, "Alice", {
                offer(1, Made.BUY, Made.ADDED, "SHARK", 100, 70),
                offer(2, Made.BUY, "ADED", "SHARK", 100, 5),
            })
        end)

        expectEqual(ok, false)
        expectEqual(message:find("made_spec.lua:%d+: The GE offer stage ADED is unknown%.") ~= nil, true)
        expectEqual(states, saved())
    end)
end)

describe("Made count start values", function()
    local function bread(id)
        return { id = id, item = "BREAD", count = 100 }
    end

    -- The example of ADR 0012, for Targets a, b and d (ids 1, 2 and 4).
    it("keeps the counts of other Make Targets when a new Make Target starts at 0", function()
        local states = {}
        local a, b, d = bread(1), bread(2), bread(4)
        Made.startTarget(states, "Alice", a, { BREAD = 0 }, {})
        Made.startTarget(states, "Alice", b, { BREAD = 0 }, {})
        Made.observe(states, "Alice", { detected = { BREAD = 3 } })
        Made.observe(states, "Alice", { detected = { BREAD = 0 } })
        Made.observe(states, "Alice", { detected = { BREAD = 3 } })
        Made.startTarget(states, "Alice", d, { BREAD = 3 }, {})
        Made.observe(states, "Alice", { detected = { BREAD = 17 } })

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { a, b, d }), { [1] = 20, [2] = 20, [4] = 14 })
    end)

    it("subtracts the start value of each character in All characters", function()
        local states = {}
        local a, b = bread(1), bread(2)
        Made.startTarget(states, "Alice", a, { BREAD = 0 }, {})
        Made.observe(states, "Bob", { detected = { BREAD = 0 } })
        Made.observe(states, "Alice", { detected = { BREAD = 5 } })
        Made.observe(states, "Bob", { detected = { BREAD = 4 } })
        Made.startTarget(states, "Alice", b, { BREAD = 5 }, {})
        Made.observe(states, "Alice", { detected = { BREAD = 6 } })
        Made.observe(states, "Bob", { detected = { BREAD = 6 } })

        expectEqual(Made.counts(states, "Alice", Made.ALL, { a, b }), { [1] = 12, [2] = 3 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER, { a, b }), { [1] = 6, [2] = 2 })
    end)

    it("changes only the edited Target in This character", function()
        local states = {}
        local a, b = bread(1), bread(2)
        Made.startTarget(states, "Alice", a, { BREAD = 0 }, {})
        Made.startTarget(states, "Alice", b, { BREAD = 0 }, {})
        Made.observe(states, "Alice", { detected = { BREAD = 20 } })
        Made.set(states, "Alice", Made.CHARACTER, b, 5)

        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { a, b }), { [1] = 20, [2] = 5 })
    end)

    it("changes only the edited Target in All characters", function()
        local states = {}
        local a, b = bread(1), bread(2)
        Made.startTarget(states, "Alice", a, { BREAD = 0 }, {})
        Made.startTarget(states, "Alice", b, { BREAD = 0 }, {})
        Made.observe(states, "Bob", { detected = { BREAD = 0 } })
        Made.observe(states, "Alice", { detected = { BREAD = 20 } })
        Made.observe(states, "Bob", { detected = { BREAD = 4 } })
        Made.set(states, "Alice", Made.ALL, b, 7)

        expectEqual(Made.counts(states, "Alice", Made.ALL, { a, b }), { [1] = 24, [2] = 7 })
        expectEqual(Made.counts(states, "Bob", Made.CHARACTER, { a, b }), { [1] = 4, [2] = 0 })
    end)

    -- A start again sets the Made count to 0. A reset uses Made.set.
    it("stops with an error when a Make Target that has start values starts again", function()
        local states = {}
        local a = bread(1)
        Made.startTarget(states, "Alice", a, { BREAD = 0 }, {})
        Made.observe(states, "Alice", { detected = { BREAD = 40 } })
        local ok, message = pcall(function()
            Made.startTarget(states, "Alice", a, { BREAD = 40 }, {})
        end)

        expectEqual(ok, false)
        expectEqual(message:find("made_spec.lua:%d+: The Make Target 1 of BREAD has start values%.") ~= nil, true)
        expectEqual(Made.counts(states, "Alice", Made.CHARACTER, { a }), { [1] = 40 })
    end)
end)
