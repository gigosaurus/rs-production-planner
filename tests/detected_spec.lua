local Detected = require("plan/detected")

describe("Detected.count", function()
    it("adds the counts of an item in all slots of the Inventory and the bank", function()
        local inventory = {
            { configName = "RUNE_BAR", count = 1 },
            { configName = "RUNE_BAR", count = 1 },
            { configName = "COAL", count = 1 },
        }
        local bank = {
            { configName = "RUNE_BAR", count = 40 },
            { configName = "IRON_ORE", count = 300 },
        }

        expectEqual(Detected.count(inventory, bank), { RUNE_BAR = 42, COAL = 1, IRON_ORE = 300 })
    end)

    -- ADR 0007: the config name of a Noted item is CERT_<name>.
    it("counts a Noted item as the item", function()
        local inventory = { { configName = "CERT_RUNE_BAR", count = 500 } }
        local bank = { { configName = "RUNE_BAR", count = 40 } }

        expectEqual(Detected.count(inventory, bank), { RUNE_BAR = 540 })
    end)

    it("removes CERT_ only at the start of the config name", function()
        local inventory = { { configName = "RUNE_CERT_BAR", count = 1 } }

        expectEqual(Detected.count(inventory, {}), { RUNE_CERT_BAR = 1 })
    end)

    it("counts only the Inventory when there is no Bank snapshot", function()
        local inventory = { { configName = "COAL", count = 5 } }

        expectEqual(Detected.count(inventory, nil), { COAL = 5 })
    end)

    it("gives an empty table when the Inventory and the bank are empty", function()
        expectEqual(Detected.count({}, {}), {})
    end)
end)

describe("Detected.count with bad input", function()
    local function expectError(inventory, bank, text)
        local ok, message = pcall(Detected.count, inventory, bank)

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
            local inventory = { { configName = "COAL", count = case.value } }

            expectError(
                inventory,
                nil,
                "The adapter gave an Inventory slot with a bad count. "
                    .. "The count must be a whole number more than 0. The value is "
                    .. tostring(case.value)
                    .. "."
            )
        end)
    end

    it("names the bank in the error for a bad bank slot", function()
        expectError({}, { { configName = "COAL", count = 0 } }, "The adapter gave a bank slot with a bad count.")
    end)

    it("names the Inventory in the error for a bad Inventory slot", function()
        expectError({ { configName = 5, count = 1 } }, {}, "The adapter gave an Inventory slot with a bad config name.")
    end)

    for _, case in ipairs({
        { name = "a number", value = 5 },
        { name = "a string", value = "COAL" },
    }) do
        it("stops with an error for an Inventory slot that is " .. case.name, function()
            expectError(
                { case.value },
                nil,
                "The adapter gave a bad Inventory slot. The slot must be a table. The value is "
                    .. tostring(case.value)
                    .. "."
            )
        end)
    end

    it("names the bank in the error for a bank slot that is not a table", function()
        expectError({}, { 5 }, "The adapter gave a bad bank slot. The slot must be a table. The value is 5.")
    end)

    for _, case in ipairs({
        {
            name = "a gap",
            value = { [1] = { configName = "RUNE_BAR", count = 40 }, [3] = { configName = "COAL", count = 10 } },
        },
        { name = "a key that is not a slot number", value = { first = { configName = "COAL", count = 1 } } },
    }) do
        it("stops with an error for a bank with " .. case.name, function()
            expectError(
                {},
                case.value,
                "The adapter gave a bank with a gap or a key that is not a slot number. The bank must be a list."
            )
        end)
    end

    it("names the Inventory in the error for an Inventory with a gap", function()
        expectError(
            { [2] = { configName = "COAL", count = 1 } },
            nil,
            "The adapter gave an Inventory with a gap or a key that is not a slot number. "
                .. "The Inventory must be a list."
        )
    end)

    it("stops with an error for an Inventory that is not a table", function()
        expectError(nil, {}, "The adapter gave a bad Inventory. The Inventory must be a table. The value is nil.")
    end)

    it("stops with an error for a bank that is not a table or nil", function()
        expectError({}, 5, "The adapter gave a bad bank. The bank must be a table or nil. The value is 5.")
    end)
end)

describe("Detected.count error position", function()
    -- The error must point at the line that calls Detected.count. A tail call removes that line, so keep the result.
    local function expectCallerLine(inventory)
        local line
        local ok, message = pcall(function()
            line = debug.getinfo(1, "l").currentline + 1
            local stock = Detected.count(inventory, nil)
            return stock
        end)

        expectEqual(ok, false)
        expectEqual(message:match("^tests/detected_spec%.lua:(%d+):"), tostring(line))
    end

    for _, case in ipairs({
        { name = "a bad Inventory", inventory = nil },
        { name = "a slot that is not a table", inventory = { 5 } },
        { name = "a slot with a bad count", inventory = { { configName = "COAL", count = 0 } } },
        { name = "an Inventory with a gap", inventory = { [2] = { configName = "COAL", count = 1 } } },
    }) do
        it("points at the caller for " .. case.name, function()
            expectCallerLine(case.inventory)
        end)
    end
end)
