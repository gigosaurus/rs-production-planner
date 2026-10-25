-- Keeps the Made counts of the Make Targets, as ADR 0009 and ADR 0012 describe.
-- Its callers give it the Detected stock of all items. It counts only the items of the Make Targets.
-- It does not use the game API. Tests run it outside the game client.
-- states maps each displayName to the state of that character (ADR 0008).
-- It must have the state of each character that has saved data, also a character that is not logged in (ADR 0012).
-- startTarget and stopTarget change only the states in it.
-- Each state is a plain table, so the plugin can save it with PersistentDB.
local CountText = require("plan/counttext")
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

-- Gives true when scope is a Made count scope: Made.CHARACTER or Made.ALL.
function Made.isScope(scope)
    return Validate.isOneOf(scope, SCOPES)
end

local function checkScope(scope)
    if not Made.isScope(scope) then
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

-- Gives the items of the Make Targets. startTarget gives a count to each of them.
local function targetItems(states)
    local items = {}
    for _, state in pairs(states) do
        for item in pairs(state.counts) do
            items[item] = true
        end
    end
    return items
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
-- detected is the Detected stock now. offers are all the GE offers of the character now.
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

-- Changes the GE amount of an item. An amount of 0 is not kept, so the saved form changes only when an amount changes.
local function addGE(state, item, amount)
    local total = (state.ge[item] or 0) + amount
    state.ge[item] = total ~= 0 and total or nil
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
        addGE(state, offer.item, amount)
    end
    saveSlot(state, offer)
end

local function checkOffers(offers)
    for _, offer in ipairs(offers) do
        checkOffer(offer)
    end
end

-- Call this when the plugin loads the state of a character while a Make Target exists.
-- A rise between sessions is not made, so the next observation is the starting point.
-- offers are all the GE offers of the character now. A bad offer changes no state.
-- The GE amount stays, because the player can collect the items after the load (issue 53).
-- Items that the offers got between sessions add to it. With no saved slots, the offers are the starting point.
function Made.load(states, name, offers)
    checkOffers(offers)
    local state = character(states, name)
    state.last = {}
    local live, offered = {}, {}
    for _, offer in ipairs(offers) do
        live[offer.slot] = true
        if offer.stage ~= Made.EMPTY then
            offered[offer.item] = true
        end
    end
    if next(state.slots) == nil then
        readOffers(state, offers)
    else
        -- A saved slot with no offer is empty now.
        for slot in pairs(state.slots) do
            if not live[slot] then
                state.slots[slot] = nil
            end
        end
        local items = targetItems(states)
        for _, offer in ipairs(offers) do
            observeOffer(state, offer, items)
        end
    end
    -- Unverified (ADR 0009): with no offer for the item, the player collected the items while the plugin was off.
    for item in pairs(state.ge) do
        if not offered[item] then
            state.ge[item] = nil
        end
    end
end

-- tick has the facts of one server tick for one character. Assumed.observe takes the same record.
-- An item that is not in tick.detected has a Detected stock of 0.
-- With no Make Target, it makes no state, so startTarget reads the GE offers (issue 78).
function Made.observe(states, name, tick)
    checkOffers(tick.ge or {})
    if next(states) == nil then
        return
    end
    local state = character(states, name)
    local items = targetItems(states)
    for _, offer in ipairs(tick.ge or {}) do
        observeOffer(state, offer, items)
    end
    for item in pairs(items) do
        local now = tick.detected[item] or 0
        -- With no last count, a first Bank snapshot or an open shop, this observation is the starting point.
        local rise = (tick.firstBank or tick.shopOpen) and 0 or now - (state.last[item] or now)
        -- A rise in the same tick as a ground stack decrease is a pickup.
        rise = rise - ((tick.groundDecrease or {})[item] or 0)
        -- The rest of the rise uses up the GE amount first.
        local fromGE = math.max(0, math.min(rise, state.ge[item] or 0))
        addGE(state, item, -fromGE)
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

-- Gives the saved form of one state. Saved adds the version.
-- Made.load clears the last Detected counts, so the plugin does not save them.
function Made.encode(state)
    local slots = {}
    for slot, data in pairs(state.slots) do
        slots[slot] =
            { item = data.item, type = data.type, stage = data.stage, soldCount = CountText.text(data.soldCount) }
    end
    return {
        counts = CountText.texts(state.counts),
        starts = CountText.texts(state.starts),
        slots = slots,
        ge = CountText.texts(state.ge),
    }
end

-- Gives the start values by Target id, or nil when an id or a start value is bad.
local function startsOf(texts)
    if type(texts) ~= "table" then
        return nil
    end
    local starts = {}
    for id, text in pairs(texts) do
        local start = CountText.count(text)
        if not Validate.isPositiveInteger(id) or not start then
            return nil
        end
        starts[id] = start
    end
    return starts
end

-- Gives the state from its saved form, or nil when the data is bad.
-- The GE amounts stay between sessions (issue 53). Data with no GE amounts gives GE amounts of 0.
function Made.decode(value)
    local state = Made.new()
    state.counts = CountText.counts(value.counts)
    state.starts = startsOf(value.starts)
    state.ge = CountText.counts(value.ge or {})
    if not state.counts or not state.starts or not state.ge or type(value.slots) ~= "table" then
        return nil
    end
    for slot, data in pairs(value.slots) do
        local soldCount = type(data) == "table" and CountText.count(data.soldCount)
        if not soldCount then
            return nil
        end
        state.slots[slot] = { item = data.item, type = data.type, stage = data.stage, soldCount = soldCount }
    end
    return state
end

return Made
