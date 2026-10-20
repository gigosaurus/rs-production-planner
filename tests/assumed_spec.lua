local Assumed = require("plan/assumed")

local AMOUNT_ERROR = "The Assumed amount of SNAPE_GRASS must be a whole number more than 0."

describe("Assumed stock", function()
    it("adds a line with nothing arrived", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })

        expectEqual(Assumed.lines(state), { { item = "SNAPE_GRASS", remaining = 50, arrived = 0, entered = 50 } })
    end)

    it("decreases what remains by a rise in Detected stock", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        local changes = Assumed.observe(state, { SNAPE_GRASS = 36 })

        expectEqual(changes.arrived, { { item = "SNAPE_GRASS", count = 36 } })
        expectEqual(Assumed.lines(state), { { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 } })
    end)

    it("never increases what remains after a fall", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.observe(state, { SNAPE_GRASS = 36 })
        Assumed.observe(state, { SNAPE_GRASS = 30 })

        expectEqual(Assumed.lines(state)[1].remaining, 14)
    end)

    it("counts a rise from the amount after a fall", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.observe(state, { SNAPE_GRASS = 36 })
        Assumed.observe(state, { SNAPE_GRASS = 30 })
        Assumed.observe(state, { SNAPE_GRASS = 40 })

        expectEqual(Assumed.lines(state)[1].remaining, 4)
    end)

    it("removes and reports Assumed stock that is Fulfilled", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        local changes = Assumed.observe(state, { SNAPE_GRASS = 60 })

        expectEqual(changes.fulfilled, { "SNAPE_GRASS" })
        expectEqual(Assumed.lines(state), {})
    end)

    it("adds to the line of an item that is already assumed", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.observe(state, { SNAPE_GRASS = 36 })
        Assumed.add(state, "SNAPE_GRASS", 20, { SNAPE_GRASS = 36 })

        expectEqual(Assumed.lines(state), { { item = "SNAPE_GRASS", remaining = 34, arrived = 36, entered = 70 } })
    end)

    it("keeps the baseline of an item that is already assumed", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.add(state, "SNAPE_GRASS", 20, { SNAPE_GRASS = 10 })
        Assumed.observe(state, { SNAPE_GRASS = 10 })

        expectEqual(Assumed.lines(state)[1].remaining, 60)
    end)

    it("removes a line", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.add(state, "VIAL_OF_WATER", 20, { VIAL_OF_WATER = 0 })
        Assumed.remove(state, "SNAPE_GRASS")

        expectEqual(Assumed.lines(state), { { item = "VIAL_OF_WATER", remaining = 20, arrived = 0, entered = 20 } })
    end)

    it("uses up nothing when the bank is seen for the first time", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.rebase(state, { SNAPE_GRASS = 200 })
        Assumed.observe(state, { SNAPE_GRASS = 210 })

        expectEqual(Assumed.lines(state)[1].remaining, 40)
    end)

    it("gives what remains of each item for Plan.calculate", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        Assumed.add(state, "VIAL_OF_WATER", 20, { VIAL_OF_WATER = 0 })
        Assumed.observe(state, { SNAPE_GRASS = 36 })

        expectEqual(Assumed.remaining(state), { SNAPE_GRASS = 14, VIAL_OF_WATER = 20 })
    end)

    it("stops with an error for an amount of 0", function()
        local state = Assumed.new()
        local ok, message = pcall(Assumed.add, state, "SNAPE_GRASS", 0, { SNAPE_GRASS = 0 })

        expectEqual(ok, false)
        expectEqual(message:find(AMOUNT_ERROR, 1, true) ~= nil, true)
        expectEqual(Assumed.lines(state), {})
    end)

    it("stops with an error for a negative amount and keeps the line", function()
        local state = Assumed.new()
        Assumed.add(state, "SNAPE_GRASS", 50, { SNAPE_GRASS = 0 })
        local ok, message = pcall(Assumed.add, state, "SNAPE_GRASS", -10, { SNAPE_GRASS = 0 })

        expectEqual(ok, false)
        expectEqual(message:find(AMOUNT_ERROR, 1, true) ~= nil, true)
        expectEqual(Assumed.lines(state), { { item = "SNAPE_GRASS", remaining = 50, arrived = 0, entered = 50 } })
    end)

    for _, case in ipairs({
        { name = "a fraction", amount = 2.5 },
        { name = "NaN", amount = 0 / 0 },
        { name = "infinity", amount = math.huge },
        { name = "no amount", amount = nil },
        { name = "a string", amount = "5" },
    }) do
        it("stops with an error for " .. case.name, function()
            local state = Assumed.new()
            local ok, message = pcall(Assumed.add, state, "SNAPE_GRASS", case.amount, { SNAPE_GRASS = 0 })

            expectEqual(ok, false)
            expectEqual(message:find(AMOUNT_ERROR, 1, true) ~= nil, true)
            expectEqual(Assumed.lines(state), {})
        end)
    end

    it("names a nil item in the error for a bad amount", function()
        local ok, message = pcall(Assumed.add, Assumed.new(), nil, 0, {})

        expectEqual(ok, false)
        expectEqual(message:find("The Assumed amount of nil must be a whole number more than 0.", 1, true) ~= nil, true)
    end)
end)
