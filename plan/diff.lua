-- Finds what changed between two calculations of the Plan.
-- It does not use the game API. Tests run it outside the game client.
local Diff = {}

local function isFlaggedOrWaiting(step)
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
        if step.item == item then
            return position
        end
    end
end

-- The Next step moves backwards when the old Next step is still in the Plan, after the new one.
local function movedBackwards(before, after)
    local oldPosition = nextItem(before) and positionOf(after, nextItem(before))
    return oldPosition ~= nil and after.next ~= nil and after.next < oldPosition
end

function Diff.compare(before, after)
    local beforeSteps, afterSteps = stepsByItem(before), stepsByItem(after)
    local former, back, ready = {}, {}, {}
    for _, step in ipairs(before.steps) do
        if not afterSteps[step.item] then
            former[#former + 1] = step.item
        end
    end
    for _, step in ipairs(after.steps) do
        local earlier = beforeSteps[step.item]
        if not earlier then
            back[#back + 1] = step.item
        elseif isFlaggedOrWaiting(earlier) and not isFlaggedOrWaiting(step) then
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

    -- In Make, the report uses the Made count of a Target. In Have, it uses Counted stock (ADR 0009).
    -- A line has a Made count only in Make. When the Target mode changes, the two values are not comparable.
    -- Plan.calculate gives one line for each Target. Until the diff matches lines by id, it reports each item one time (issue 28).
    local lineBefore, targets, reported = {}, {}, {}
    for _, target in ipairs(before.targets) do
        lineBefore[target.item] = lineBefore[target.item] or target
    end
    for _, target in ipairs(after.targets) do
        local earlier = lineBefore[target.item]
        if earlier and not reported[target.item] and (earlier.made == nil) == (target.made == nil) then
            reported[target.item] = true
            local by = (target.made or target.have) - (earlier.made or earlier.have)
            if by ~= 0 then
                targets[#targets + 1] = { item = target.item, by = by }
            end
        end
    end

    -- complete is true when the Plan became Complete. It is false when the Plan stopped being Complete.
    local complete
    if after.complete ~= before.complete then
        complete = after.complete
    end

    return {
        former = former,
        back = back,
        ready = ready,
        next = nextChange,
        covered = covered,
        targets = targets,
        complete = complete,
    }
end

return Diff
