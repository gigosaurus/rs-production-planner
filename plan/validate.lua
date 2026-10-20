-- Checks for values that the plan modules get from the view.
-- It does not use the game API. Tests run it outside the game client.
local Validate = {}

-- Gives true for a whole number more than 0, for example a count of items.
-- n % 1 is not 0 for a fraction, NaN and infinity.
function Validate.isPositiveInteger(n)
    return type(n) == "number" and n % 1 == 0 and n > 0
end

return Validate
