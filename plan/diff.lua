-- Finds what changed between two calculations of the Plan.
-- It does not use the game API. Tests run it outside the game client.
local Diff = {}

local function isHeld(step)
    return #step.flags > 0 or step.waitsOn ~= nil
end

-- A Step in one Plan is the same Step in the other when it is for the same item.
local function stepsByItem(plan)
    local byItem = {}
    for _, step in ipairs(plan.steps) do
        byItem[step.item] = step
    end
    return byItem
end

local function nextItem(plan)
    return plan.next and plan.steps[plan.next].item
end

local function positionOf(plan, item)
    for position, step in ipairs(plan.steps) do
        if step.item == item then return position end
    end
end

-- The Next step moves backwards when the old Next step is still in the Plan, after the new one.
local function movedBackwards(before, after)
    local oldPosition = nextItem(before) and positionOf(after, nextItem(before))
    return oldPosition ~= nil and after.next ~= nil and after.next < oldPosition
end

function Diff.compare(before, after)
    local beforeSteps, afterSteps = stepsByItem(before), stepsByItem(after)
    local finished, back, ready = {}, {}, {}
    for _, step in ipairs(before.steps) do
        if not afterSteps[step.item] then
            finished[#finished + 1] = step.item
        end
    end
    for _, step in ipairs(after.steps) do
        local earlier = beforeSteps[step.item]
        if not earlier then
            back[#back + 1] = step.item
        elseif isHeld(earlier) and not isHeld(step) then
            ready[#ready + 1] = step.item
        end
    end
    local nextChange
    if nextItem(before) ~= nextItem(after) then
        nextChange = { from = nextItem(before), to = nextItem(after), backwards = movedBackwards(before, after) }
    end

    local stillShort, covered = {}, {}
    for _, shortage in ipairs(after.shortages) do
        stillShort[shortage.item] = true
    end
    for _, shortage in ipairs(before.shortages) do
        if not stillShort[shortage.item] then
            covered[#covered + 1] = shortage.item
        end
    end

    local haveBefore, targets = {}, {}
    for _, target in ipairs(before.targets) do
        haveBefore[target.item] = target.have
    end
    for _, target in ipairs(after.targets) do
        local by = target.have - (haveBefore[target.item] or target.have)
        if by ~= 0 then
            targets[#targets + 1] = { item = target.item, by = by }
        end
    end

    -- complete is true when the Plan became Complete. It is false when the Plan stopped being Complete.
    local complete
    if after.complete ~= before.complete then
        complete = after.complete
    end

    return {
        finished = finished, back = back, ready = ready, next = nextChange, covered = covered,
        targets = targets, complete = complete,
    }
end

return Diff
