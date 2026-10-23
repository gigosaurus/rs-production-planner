-- Gives Account mode from the value of VarPlayer.IRONMAN (ADR 0014).
-- The adapter reads the var and gives its value. Tests run this module outside the game client.
local Account = {}

-- Gives true when the character is an ironman, a hardcore ironman or a group ironman.
-- The var holds bit flags. Bit 0 is set for each ironman type (docs/client-behaviour.md).
function Account.isIronman(varValue)
    if type(varValue) ~= "number" or varValue % 1 ~= 0 then
        error("The value of VarPlayer.IRONMAN must be a whole number. The value is " .. tostring(varValue) .. ".", 2)
    end
    return varValue % 2 == 1
end

return Account
