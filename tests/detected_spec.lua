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

    -- ADR 0007: the config name of a Noted item is CERT_<name>.
    it("counts a Noted item as the item", function()
        local backpack = { { configName = "CERT_RUNE_BAR", count = 500 } }
        local bank = { { configName = "RUNE_BAR", count = 40 } }

        expectEqual(Detected.count(backpack, bank), { RUNE_BAR = 540 })
    end)

    it("removes CERT_ only at the start of the config name", function()
        local backpack = { { configName = "RUNE_CERT_BAR", count = 1 } }

        expectEqual(Detected.count(backpack, {}), { RUNE_CERT_BAR = 1 })
    end)

    it("gives an empty table when the backpack and the bank are empty", function()
        expectEqual(Detected.count({}, {}), {})
    end)
end)
