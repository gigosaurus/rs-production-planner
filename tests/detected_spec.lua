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

    it("counts only the backpack when there is no Bank snapshot", function()
        local backpack = { { configName = "COAL", count = 5 } }

        expectEqual(Detected.count(backpack, nil), { COAL = 5 })
    end)

    it("gives an empty table when the backpack and the bank are empty", function()
        expectEqual(Detected.count({}, {}), {})
    end)
end)

describe("Detected.count with bad input", function()
    local function expectError(backpack, bank, text)
        local ok, message = pcall(Detected.count, backpack, bank)

        expectEqual(ok, false)
        expectEqual(message:find(text, 1, true) ~= nil, true)
    end

    for _, case in ipairs({
        { name = "nil", value = nil },
        { name = "a number", value = 5 },
    }) do
        it("stops with an error for a config name that is " .. case.name, function()
            local bank = { { configName = "COAL", count = 1 }, { configName = case.value, count = 1 } }

            expectError(
                {},
                bank,
                "The adapter gave a bank slot with a bad config name. The config name must be a string. The value is "
                    .. tostring(case.value)
                    .. "."
            )
        end)
    end

    for _, case in ipairs({
        { name = "0", value = 0 },
        { name = "negative", value = -1 },
        { name = "a fraction", value = 1.5 },
        { name = "nil", value = nil },
        { name = "a string", value = "1" },
    }) do
        it("stops with an error for a count that is " .. case.name, function()
            local backpack = { { configName = "COAL", count = case.value } }

            expectError(
                backpack,
                nil,
                "The adapter gave a backpack slot with a bad count. "
                    .. "The count must be a whole number more than 0. The value is "
                    .. tostring(case.value)
                    .. "."
            )
        end)
    end

    it("names the bank in the error for a bad bank slot", function()
        expectError({}, { { configName = "COAL", count = 0 } }, "The adapter gave a bank slot with a bad count.")
    end)

    it("names the backpack in the error for a bad backpack slot", function()
        expectError({ { configName = 5, count = 1 } }, {}, "The adapter gave a backpack slot with a bad config name.")
    end)

    it("stops with an error for a backpack that is not a table", function()
        expectError(nil, {}, "The adapter gave a bad backpack. The backpack must be a table. The value is nil.")
    end)

    it("stops with an error for a bank that is not a table or nil", function()
        expectError({}, 5, "The adapter gave a bad bank. The bank must be a table or nil. The value is 5.")
    end)
end)
