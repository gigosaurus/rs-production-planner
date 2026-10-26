-- Makes the "Just now" message and the row highlights from two Plans (issue 5, variant J4; issue 26).
-- It does not use the game API. Tests run it outside the game client.
-- A state is { plan, assumed }: a Plan and the result of Assumed.lines.
local Diff = require("plan/diff")
local View = require("plan/view")

local News = {}

local COMPLETE = "Plan complete. You have all the items that you wanted to make."
local SINCE = "Since you looked: "

-- Gives the first Step of plan for item. The Diff reports a Step by its item.
local function stepOf(plan, item)
    for _, step in ipairs(plan.steps) do
        if step.item == item then
            return step
        end
    end
end

local function stepNames(plan, items, nameOf)
    local names = {}
    for index, item in ipairs(items) do
        names[index] = View.stepName(nameOf, stepOf(plan, item))
    end
    return View.joined(names)
end

-- Gives "is" for one Step and "are" for more.
local function verbFor(items, one, more)
    return #items == 1 and one or more
end

local function remainingOf(assumed)
    local remaining = {}
    for _, line in ipairs(assumed) do
        remaining[line.item] = line.remaining
    end
    return remaining
end

-- Gives the sentences, true when one of them is a milestone, and the highlights of a change from before to after.
local function describe(before, after, nameOf)
    local diff = Diff.compare(before.plan, after.plan)
    local sentences, milestone = {}, false
    local highlights = { steps = {}, targets = {}, assumed = {} }
    local function say(text, isMilestone)
        sentences[#sentences + 1] = text
        milestone = milestone or isMilestone
    end

    local used, more = {}, {}
    for _, target in ipairs(diff.targets) do
        local name = nameOf(target.item) or target.item
        if target.by < 0 then
            used[#used + 1] = -target.by .. " " .. name
            highlights.targets[target.id] = "down"
        else
            more[#more + 1] = target.by .. " more " .. name
            highlights.targets[target.id] = "up"
        end
    end
    if #used > 0 then
        say("You used " .. View.joined(used) .. ".", false)
    end
    if #more > 0 then
        say("You have " .. View.joined(more) .. ".", false)
    end
    if #diff.former > 0 then
        say(stepNames(before.plan, diff.former, nameOf) .. verbFor(diff.former, " is", " are") .. " done.", true)
    end
    if #diff.back > 0 then
        say(stepNames(after.plan, diff.back, nameOf) .. " must be done again.", true)
    end
    if diff.complete == false then
        say("The plan is not complete now.", true)
    end
    for _, item in ipairs(diff.covered) do
        say("You have enough " .. (nameOf(item) or item) .. " now.", true)
    end

    local remainingAfter = remainingOf(after.assumed)
    for _, line in ipairs(before.assumed) do
        local now = remainingAfter[line.item]
        if now == nil then
            say("All your assumed " .. (nameOf(line.item) or line.item) .. " has arrived.", true)
        elseif now < line.remaining then
            highlights.assumed[line.item] = "arrived"
        end
    end

    if #diff.ready > 0 then
        say(stepNames(after.plan, diff.ready, nameOf) .. " can start now.", true)
    end
    for _, item in ipairs(diff.back) do
        highlights.steps[item] = "back"
    end
    for _, item in ipairs(diff.ready) do
        highlights.steps[item] = "ready now"
    end

    -- When no Step can be the Next step, the message says nothing about Next (issue 26). Do next shows the text.
    if diff.next and diff.next.to then
        local name = View.stepName(nameOf, after.plan.steps[after.plan.next])
        say(diff.next.backwards and "The next step moved back to " .. name .. "." or "Next: " .. name .. ".", true)
        highlights.next = "new"
    end

    -- The message of a Complete Plan replaces all other messages (issue 5).
    if diff.complete then
        sentences, milestone = { COMPLETE }, true
    end
    return sentences, milestone, highlights
end

-- Gives a News. message is the "Just now" message, or nil. milestone tells if the message has a milestone (issue 5).
-- highlights are the row highlights of the last change: next, steps (by item), targets (by id) and assumed (by item).
function News.new()
    return { open = false, highlights = { steps = {}, targets = {}, assumed = {} } }
end

-- Changes the message and the highlights for the change from the last state that the player saw to now.
-- A change with no sentence keeps the message (issue 26).
local function report(news, now, nameOf, prefix)
    if news.seen then
        local sentences, milestone, highlights = describe(news.seen, now, nameOf)
        if #sentences > 0 then
            news.message, news.milestone = prefix .. table.concat(sentences, " "), milestone
        end
        news.highlights = highlights
    end
    news.seen = now
end

-- Call this with each new Plan. While the window is closed, it changes nothing.
function News.see(news, now, nameOf)
    if news.open then
        report(news, now, nameOf, "")
    end
end

-- Call this when the window opens. It gives the changes since the window closed (issue 26).
function News.open(news, now, nameOf)
    news.open = true
    report(news, now, nameOf, SINCE)
end

-- Call this when the window closes. The News keeps the state that the player saw last.
function News.close(news)
    news.open = false
end

-- Call this at a login. A change from the Plan of another character is not correct.
function News.reset(news)
    news.seen, news.message, news.milestone = nil, nil, nil
    news.highlights = { steps = {}, targets = {}, assumed = {} }
end

return News
