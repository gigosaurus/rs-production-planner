local Validate = require("plan/validate")

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
