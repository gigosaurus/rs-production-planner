-- Checks for values that the plan modules get from their callers.
-- It does not use the game API. Tests run it outside the game client.
local Validate = {}

-- Gives true for a whole number, for example the value of a var.
-- n % 1 is not 0 for a fraction, NaN and infinity.
function Validate.isInteger(n)
    return type(n) == "number" and n % 1 == 0
end

-- Gives true for a whole number more than 0, for example a count of items.
function Validate.isPositiveInteger(n)
    return Validate.isInteger(n) and n > 0
end

-- Gives true for a whole number of 0 or more, for example a Made count.
function Validate.isNonNegativeInteger(n)
    return Validate.isInteger(n) and n >= 0
end

-- Gives true when set has the key value, for example a Target mode.
-- The keys of set are the permitted values, and each key has the value true.
function Validate.isOneOf(value, set)
    return set[value] == true
end

return Validate
