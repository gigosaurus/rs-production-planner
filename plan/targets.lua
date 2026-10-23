-- Keeps the Targets of the Plan, as ADR 0012 describes. Each Target has an id, an item, a count and a Target mode.
-- It does not use the game API. Tests run it outside the game client.
local CountText = require("plan/counttext")
local Plan = require("plan/calculate")
local Validate = require("plan/validate")

local Targets = {}

local MODES = { [Plan.HAVE] = true, [Plan.MAKE] = true }

-- Gives a Plan with no Targets.
function Targets.new()
    return { targets = {} }
end

-- Gives the saved form of the Targets. Saved adds the version.
-- PersistentDB keeps an id exact up to 16,777,216, so the id stays a number.
function Targets.encode(plan)
    local targets = {}
    for index, target in ipairs(plan.targets) do
        targets[index] =
            { id = target.id, item = target.item, count = CountText.text(target.count), mode = target.mode }
    end
    return { targets = targets }
end

local function targetOf(value, ids)
    if type(value) ~= "table" or type(value.item) ~= "string" or not Validate.isOneOf(value.mode, MODES) then
        return nil
    end
    local count = CountText.count(value.count)
    if not Validate.isPositiveInteger(value.id) or ids[value.id] or not count then
        return nil
    end
    local id = math.tointeger(value.id)
    ids[id] = true
    return { id = id, item = value.item, count = count, mode = value.mode }
end

-- Gives the Targets from their saved form, or nil when the data is bad.
-- Two Targets with one id are bad data, because Plan.calculate does not accept them.
function Targets.decode(value)
    if type(value.targets) ~= "table" then
        return nil
    end
    local plan, ids = Targets.new(), {}
    for index, saved in ipairs(value.targets) do
        local target = targetOf(saved, ids)
        if not target then
            return nil
        end
        plan.targets[index] = target
    end
    return plan
end

return Targets
