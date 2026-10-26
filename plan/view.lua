-- Makes the text of each section of the Plan view from a Plan (issue 26, layout F of issue 1).
-- It does not use the game API. Tests run it outside the game client. ui/planwindow.lua draws the result.
local Diff = require("plan/diff")

local View = {}

local NOT_READY = "No step is ready yet."
local GET_SHORTAGES = "Get the items under Buy or gather first."

-- Gives "A", "A and B" or "A, B and C".
local function joined(parts)
    if #parts < 2 then
        return parts[1] or ""
    end
    return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

-- "HERBLORE" becomes "Herblore".
local function skillName(skill)
    return skill:sub(1, 1) .. skill:sub(2):lower()
end

-- The view of one build. name gives the name of an item, or its config name when the game gives no name.
local function newContext(input)
    local context = { input = input }
    function context.name(item)
        return input.nameOf(item) or item
    end
    function context.have(item)
        return input.detected[item] or 0
    end
    return context
end

-- Gives the requirement of one Flag. current adds the level of the player.
local function flagText(context, flag, current)
    if flag.skill then
        local text = skillName(flag.skill) .. " " .. flag.level
        return current and text .. " (you have " .. flag.current .. ")" or text
    end
    return context.input.unlockName(flag.unlock) or flag.unlock
end

local function allFlags(context, step, current)
    local parts = {}
    for _, flag in ipairs(step.flags) do
        parts[#parts + 1] = flagText(context, flag, current)
    end
    return joined(parts)
end

-- "Decant 64 Super restore (3) into 48 Super restore (4)".
local function decantText(context, step)
    local parts = {}
    for _, input in ipairs(step.inputs) do
        parts[#parts + 1] = input.count .. " " .. context.name(input.item)
    end
    return "Decant " .. joined(parts) .. " into " .. step.actions .. " " .. context.name(step.item)
end

-- "Clean 54x Ranarr weed".
local function stepText(context, step)
    if step.decant then
        return decantText(context, step)
    end
    return step.verb .. " " .. step.actions .. "x " .. context.name(step.item)
end

-- "Decant Super restore into (4)". A name with no Dose size stays whole.
local function decantCaption(context, step)
    local name = context.name(step.item)
    local base, size = name:match("^(.-)%s*(%(%d+%))$")
    if base then
        return "Decant " .. base .. " into " .. size
    end
    return "Decant into " .. name
end

-- "Mix Super restore (3)": the caption of a Step with no number and no action count.
local function shortText(context, step)
    return step.decant and decantCaption(context, step) or step.verb .. " " .. context.name(step.item)
end

local function inventories(step)
    local count = math.ceil(step.actions / step.batchHint)
    return count == 1 and "1 inventory" or count .. " inventories"
end

local function detailText(context, step)
    local text = stepText(context, step)
    if step.batchHint and not step.decant then
        text = text .. " (" .. inventories(step) .. ")"
    end
    return text
end

local function doNextOf(context, plan)
    local step = plan.next and plan.steps[plan.next]
    if not step then
        local noneReady = #plan.steps > 0
        for _, other in ipairs(plan.steps) do
            if #other.flags == 0 and not other.waitsOn then
                noneReady = false
            end
        end
        return { text = noneReady and NOT_READY or GET_SHORTAGES, inputs = {} }
    end
    local doNext = { text = stepText(context, step), inputs = {} }
    if step.decant then
        return doNext
    end
    for index, input in ipairs(step.inputs) do
        local text = context.name(input.item)
        if input.perInventory then
            text = input.perInventory .. " " .. text
        end
        if index == #step.inputs then
            text = text .. " per inventory"
        end
        doNext.inputs[index] = { item = input.item, have = input.detected, text = text }
    end
    return doNext
end

-- A line has a Made count only in Make. It shows up to the count (ADR 0012). Have shows Counted stock.
local function progressOf(plan, line)
    if plan.complete then
        return line.count
    end
    return line.made and math.min(line.made, line.count) or line.have
end

local function targetsOf(context, plan)
    local targets = {}
    for index, line in ipairs(plan.targets) do
        local have = progressOf(plan, line)
        targets[index] = {
            id = line.id,
            item = line.item,
            have = context.have(line.item),
            text = context.name(line.item) .. "   " .. have .. " of " .. line.count,
        }
    end
    return targets
end

local function shortagesOf(context, plan)
    local shortages = {}
    for index, shortage in ipairs(plan.shortages) do
        shortages[index] = {
            item = shortage.item,
            text = shortage.count .. " " .. context.name(shortage.item),
            tooltip = "You have " .. context.have(shortage.item) .. ".",
        }
    end
    return shortages
end

local function assumedOf(context)
    local assumed = {}
    for index, line in ipairs(context.input.assumed) do
        local text = line.remaining .. " " .. context.name(line.item)
        if line.arrived > 0 then
            text = text .. "   (" .. line.arrived .. " of " .. line.entered .. " arrived)"
        end
        assumed[index] = { item = line.item, text = text }
    end
    return assumed
end

-- Gives the row of one Step. kind is next, flagged, waiting or nil. A Flagged or Waiting row has a reason.
local function stepRow(context, plan, position)
    local step = plan.steps[position]
    local caption = position .. ". " .. shortText(context, step)
    local row = { key = Diff.keyOf(step), item = step.item, have = context.have(step.item), caption = caption }
    if position == plan.next then
        row.kind, row.caption = "next", "NEXT  " .. caption
        row.tooltip = detailText(context, step)
    elseif #step.flags > 0 then
        local more = #step.flags - 1
        row.kind = "flagged"
        row.reason = "needs " .. flagText(context, step.flags[1]) .. (more > 0 and " and " .. more .. " more" or "")
        row.tooltip = "Needs " .. allFlags(context, step, true) .. "."
    elseif step.waitsOn then
        local flagged = plan.steps[step.waitsOn]
        row.kind = "waiting"
        row.reason = "waits on " .. context.name(flagged.item)
        row.tooltip = shortText(context, flagged) .. " needs " .. allFlags(context, flagged) .. "."
    else
        row.tooltip = detailText(context, step)
    end
    return row
end

local function leftoverLines(context, plan)
    local lines = {}
    for index, leftover in ipairs(plan.leftovers) do
        lines[index] = leftover.count .. " " .. context.name(leftover.item)
    end
    return lines
end

-- input has the Plan, detected (Detected stock), bankSeen, assumed (the result of Assumed.lines),
-- nameOf (gives the name of an item, or nil) and unlockName (gives the name of an Unlock, or nil).
function View.build(input)
    local context, plan = newContext(input), input.plan
    local view = {
        state = #plan.targets == 0 and "noTargets" or plan.complete and "complete" or "plan",
        bankWarning = not input.bankSeen,
        doNext = doNextOf(context, plan),
        targets = targetsOf(context, plan),
        shortages = shortagesOf(context, plan),
        assumed = assumedOf(context),
        steps = {},
        leftovers = leftoverLines(context, plan),
        assumptions = plan.assumptions,
    }
    for position in ipairs(plan.steps) do
        view.steps[position] = stepRow(context, plan, position)
    end
    if #view.leftovers > 0 then
        view.leftOver = "Left over: " .. table.concat(view.leftovers, ", ")
    end
    -- The one-line status of the ribbon layer (issue 26).
    if view.state == "noTargets" then
        view.status = "No targets yet."
    elseif view.state == "complete" then
        view.status = "Plan complete."
    else
        view.status = (plan.next and "Next: " or "") .. view.doNext.text
    end
    return view
end

-- Gives the caption of a Step with no number and no action count, for example "Mix Super restore (3)".
function View.stepName(nameOf, step)
    return shortText(newContext({ nameOf = nameOf }), step)
end

View.joined = joined

return View
