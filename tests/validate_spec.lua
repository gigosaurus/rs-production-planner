local Validate = require("plan/validate")

describe("Validate.isInteger", function()
    for _, case in ipairs({
        { name = "0", value = 0 },
        { name = "a negative number", value = -2147483647 },
        { name = "a whole float", value = 5.0 },
    }) do
        it("accepts " .. case.name, function()
            expectEqual(Validate.isInteger(case.value), true)
        end)
    end

    for _, case in ipairs({
        { name = "a fraction", value = 2.5 },
        { name = "NaN", value = 0 / 0 },
        { name = "infinity", value = math.huge },
        { name = "nil", value = nil },
        { name = "a string", value = "5" },
    }) do
        it("rejects " .. case.name, function()
            expectEqual(Validate.isInteger(case.value), false)
        end)
    end
end)

describe("Validate.isPositiveInteger", function()
    for _, case in ipairs({
        { name = "1", value = 1 },
        { name = "a large count", value = 2147483647 },
        { name = "a whole float", value = 5.0 },
    }) do
        it("accepts " .. case.name, function()
            expectEqual(Validate.isPositiveInteger(case.value), true)
        end)
    end

    for _, case in ipairs({
        { name = "0", value = 0 },
        { name = "a negative number", value = -10 },
        { name = "a fraction", value = 2.5 },
        { name = "NaN", value = 0 / 0 },
        { name = "infinity", value = math.huge },
        { name = "nil", value = nil },
        { name = "a string", value = "5" },
    }) do
        it("rejects " .. case.name, function()
            expectEqual(Validate.isPositiveInteger(case.value), false)
        end)
    end
end)

describe("Validate.isNonNegativeInteger", function()
    for _, case in ipairs({
        { name = "0", value = 0 },
        { name = "1", value = 1 },
        { name = "a whole float", value = 5.0 },
    }) do
        it("accepts " .. case.name, function()
            expectEqual(Validate.isNonNegativeInteger(case.value), true)
        end)
    end

    for _, case in ipairs({
        { name = "a negative number", value = -1 },
        { name = "a fraction", value = 2.5 },
        { name = "NaN", value = 0 / 0 },
        { name = "infinity", value = math.huge },
        { name = "nil", value = nil },
        { name = "a string", value = "5" },
    }) do
        it("rejects " .. case.name, function()
            expectEqual(Validate.isNonNegativeInteger(case.value), false)
        end)
    end
end)

describe("Validate.isOneOf", function()
    local set = { BUY = true, SELL = true }

    it("accepts a value in the set", function()
        expectEqual(Validate.isOneOf("SELL", set), true)
    end)

    for _, case in ipairs({
        { name = "a value not in the set", value = "SWAP" },
        { name = "a value in a different case", value = "buy" },
        { name = "nil", value = nil },
    }) do
        it("rejects " .. case.name, function()
            expectEqual(Validate.isOneOf(case.value, set), false)
        end)
    end
end)
