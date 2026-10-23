local Detected = require("plan/detected")

describe("Detected.count", function()
    it("adds the counts of an item in all slots of the backpack and the bank", function()
        local backpack = {
            { configName = "RUNE_BAR", count = 1 },
            { configName = "RUNE_BAR", count = 1 },
            { configName = "COAL", count = 1 },
        }
        local bank = {
            { configName = "RUNE_BAR", count = 40 },
            { configName = "IRON_ORE", count = 300 },
        }

        expectEqual(Detected.count(backpack, bank), { RUNE_BAR = 42, COAL = 1, IRON_ORE = 300 })
    end)

    it("gives an empty table when the backpack and the bank are empty", function()
        expectEqual(Detected.count({}, {}), {})
    end)
end)
