-- Keeps the Made counts of the Make Targets, as ADR 0009 and ADR 0012 describe.
-- Its callers give it only the Make Targets.
-- It does not use the game API. Tests run it outside the game client.
-- states maps each displayName to the state of that character (ADR 0008).
-- It must have the state of each character that has saved data, also a character that is not logged in (ADR 0012).
-- startTarget and stopTarget change only the states in it.
-- Each state is a plain table, so the plugin can save it with PersistentDB.
local Validate = require("plan/validate")

local Made = {}

-- Made count scope
Made.CHARACTER = "CHARACTER"
Made.ALL = "ALL"
local SCOPES = { [Made.CHARACTER] = true, [Made.ALL] = true }

-- GE offer type. The adapter maps GrandExchangeOfferType to these.
Made.BUY = "BUY"
Made.SELL = "SELL"
local OFFER_TYPES = { [Made.BUY] = true, [Made.SELL] = true }

-- GE offer stage. The adapter maps GrandExchangeOfferStage to these.
Made.EMPTY = "EMPTY"
Made.ADDING = "ADDING"
Made.ADDED = "ADDED"
Made.VERIFYING = "VERIFYING"
Made.ABORTING = "ABORTING"
Made.FINISHED = "FINISHED"

local STAGES = {
    [Made.EMPTY] = true,
    [Made.ADDING] = true,
    [Made.ADDED] = true,
    [Made.VERIFYING] = true,
    [Made.ABORTING] = true,
    [Made.FINISHED] = true,
}

-- Gives the state of one character.
-- counts has one item count for each item: the number that the plugin saw the character make. starts has one start value for each Make Target id (ADR 0012).
function Made.new()
    return { last = {}, counts = {}, starts = {}, slots = {}, ge = {} }
end

local function character(states, name)
    local state = states[name]
    if not state then
        state = Made.new()
        states[name] = state
    end
    return state
end

local function checkScope(scope)
    if not Validate.isOneOf(scope, SCOPES) then
        error("The Made count scope " .. tostring(scope) .. " is unknown.", 3)
    end
end

local function checkOffer(offer)
    if not Validate.isOneOf(offer.type, OFFER_TYPES) then
        error("The GE offer type " .. tostring(offer.type) .. " is unknown.", 4)
    end
    if not Validate.isOneOf(offer.stage, STAGES) then
        error("The GE offer stage " .. tostring(offer.stage) .. " is unknown.", 4)
    end
end

local function saveSlot(state, offer)
    state.slots[offer.slot] = { item = offer.item, type = offer.type, stage = offer.stage, soldCount = offer.soldCount }
end

-- The offers that the GE has now become the slot data. They add no GE amount.
-- Items that the offers bought but the player did not collect then count as made.
local function readOffers(state, offers)
    state.slots = {}
    for _, offer in ipairs(offers) do
        checkOffer(offer)
        saveSlot(state, offer)
    end
end

local function hasCounts(states, item)
    for _, state in pairs(states) do
        if state.counts[item] ~= nil then
            return true
        end
    end
    return false
end

-- Call this when a Target changes to Make, or when the player adds a Make Target.
-- detected is the Detected stock of the Make Targets now. offers are all the GE offers of the character now.
-- The start value on each character is its item count now. The counts of other Make Targets do not change.
-- A Target that has start values does not start again, because that sets its Made count to 0. A reset uses Made.set.
function Made.startTarget(states, name, target, detected, offers)
    local item = target.item
    for _, state in pairs(states) do
        if state.starts[target.id] ~= nil then
            error("The Make Target " .. tostring(target.id) .. " of " .. tostring(item) .. " has start values.", 2)
        end
    end
    if not hasCounts(states, item) then
        -- With no Make Target, stopTarget deleted all states. The first Make Target then reads the GE offers.
        if next(states) == nil then
            readOffers(character(states, name), offers)
        end
        -- The count of the item starts now on this character, and at the next observation on each other character.
        local state = character(states, name)
        state.counts[item] = 0
        state.last[item] = detected[item]
    end
    for _, state in pairs(states) do
        state.starts[target.id] = state.counts[item] or 0
    end
end

-- Items that the GE gives to the player add to the GE amount of the character.
-- items has a key for the item of each Make Target.
local function observeOffer(state, offer, items)
    checkOffer(offer)
    local slot = state.slots[offer.slot]
    -- A slot has a new offer when it has no saved data, a different item or type, or a lower soldCount.
    if not slot or slot.item ~= offer.item or slot.type ~= offer.type or offer.soldCount < slot.soldCount then
        slot = { soldCount = 0 }
    end
    local bought = offer.soldCount - slot.soldCount
    local amount = 0
    if offer.type == Made.BUY and bought > 0 then
        amount = bought
    elseif offer.type == Made.SELL and offer.stage == Made.ABORTING and slot.stage ~= Made.ABORTING then
        -- Unverified (ADR 0009): the items that the offer did not sell come back.
        amount = offer.itemCount - offer.soldCount
    end
    if items[offer.item] then
        state.ge[offer.item] = (state.ge[offer.item] or 0) + amount
    end
    saveSlot(state, offer)
end

-- Call this when the plugin loads the state of a character while a Make Target exists.
-- A rise between sessions is not made, so the next observation is the starting point.
-- offers are all the GE offers of the character now. targets are the Make Targets.
-- The GE amount stays, because the player can collect the items after the load (issue 53).
-- Items that the offers got between sessions add to it. With no saved state, the offers are the starting point.
function Made.load(states, name, offers, targets)
    if not states[name] then
        readOffers(character(states, name), offers)
        return
    end
    local state = states[name]
    state.last = {}
    local items = {}
    for _, target in ipairs(targets) do
        items[target.item] = true
    end
    for _, offer in ipairs(offers) do
        observeOffer(state, offer, items)
    end
end

-- tick has the facts of one server tick for one character.
function Made.observe(states, name, tick)
    local state = character(states, name)
    for _, offer in ipairs(tick.ge or {}) do
        -- The keys of detected are the items of the Make Targets.
        observeOffer(state, offer, tick.detected)
    end
    for item, now in pairs(tick.detected) do
        -- With no last count, a first Bank snapshot or an open shop, this observation is the starting point.
        local rise = (tick.firstBank or tick.shopOpen) and 0 or now - (state.last[item] or now)
        -- A rise in the same tick as a ground stack decrease is a pickup.
        rise = rise - ((tick.groundDecrease or {})[item] or 0)
        -- The rest of the rise uses up the GE amount first.
        local fromGE = math.max(0, math.min(rise, state.ge[item] or 0))
        state.ge[item] = (state.ge[item] or 0) - fromGE
        rise = rise - fromGE
        if rise > 0 then
            state.counts[item] = (state.counts[item] or 0) + rise
        end
        state.last[item] = now
    end
end

-- Gives the Made count of each Make Target in targets, by Target id. scope is Made.CHARACTER or Made.ALL.
-- On each character, the Made count is the item count minus the start value (ADR 0012).
-- All characters is the sum of the states that the plugin has now.
function Made.counts(states, name, scope, targets)
    checkScope(scope)
    local counts = {}
    for _, target in ipairs(targets) do
        counts[target.id] = 0
        for stateName, state in pairs(states) do
            if scope == Made.ALL or stateName == name then
                local made = (state.counts[target.item] or 0) - (state.starts[target.id] or 0)
                counts[target.id] = counts[target.id] + made
            end
        end
    end
    return counts
end

-- Call this when a Target changes to Have, or when the player removes a Make Target.
-- targets are the Make Targets that remain. It deletes the start values of the Target.
-- When no Make Target remains for the item, it deletes the data of the item. When no Make Target remains, it deletes all states.
function Made.stopTarget(states, target, targets)
    if #targets == 0 then
        for name in pairs(states) do
            states[name] = nil
        end
        return
    end
    local used = false
    for _, other in ipairs(targets) do
        used = used or other.item == target.item
    end
    for _, state in pairs(states) do
        state.starts[target.id] = nil
        if not used then
            state.counts[target.item], state.last[target.item], state.ge[target.item] = nil, nil, nil
        end
    end
end

-- Sets the Made count of a Make Target. A reset sets it to 0. It changes only the start values of the Target.
-- In All characters, the other characters add 0, so the sum is the new count.
function Made.set(states, name, scope, target, count)
    checkScope(scope)
    if not Validate.isNonNegativeInteger(count) then
        error("The Made count of " .. tostring(target.item) .. " must be a whole number of 0 or more.", 2)
    end
    if scope == Made.ALL then
        for _, state in pairs(states) do
            state.starts[target.id] = state.counts[target.item] or 0
        end
    end
    local state = character(states, name)
    state.starts[target.id] = (state.counts[target.item] or 0) - count
end

return Made
