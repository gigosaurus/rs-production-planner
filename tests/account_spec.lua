local Account = require("plan/account")

-- Values from probes/account-mode-probe (docs/client-behaviour.md)
describe("Account.isIronman", function()
    for _, case in ipairs({
        { name = "not ironman", value = 4096, ironman = false },
        { name = "ironman", value = 4097, ironman = true },
        { name = "hardcore ironman", value = 4099, ironman = true },
        { name = "group ironman", value = 528385, ironman = true },
        { name = "a value of 0", value = 0, ironman = false },
        { name = "a negative value with bit 0", value = -2147483647, ironman = true },
    }) do
        it("gives " .. tostring(case.ironman) .. " for " .. case.name, function()
            expectEqual(Account.isIronman(case.value), case.ironman)
        end)
    end

    local VALUE_ERROR = "The value of VarPlayer.IRONMAN must be a whole number."

    for _, case in ipairs({
        { name = "nil", value = nil },
        { name = "a fraction", value = 4097.5 },
        { name = "a string", value = "4097" },
    }) do
        it("stops with an error for " .. case.name, function()
            local ok, message = pcall(Account.isIronman, case.value)

            expectEqual(ok, false)
            expectEqual(message:find(VALUE_ERROR, 1, true) ~= nil, true)
        end)
    end
end)
