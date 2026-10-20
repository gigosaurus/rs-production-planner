-- Keeps the Made counts in Make, as ADR 0009 describes.
-- It does not use the game API. Tests run it outside the game client.
-- states maps each displayName to the state of that character (ADR 0008).
-- Each state is a plain table, so the plugin can save it with PersistentDB.
local Made = {}

-- Made count scope
Made.CHARACTER = "CHARACTER"
Made.ALL = "ALL"

-- GE offer type. The adapter maps GrandExchangeOfferType to these.
Made.BUY = "BUY"
Made.SELL = "SELL"

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
function Made.new()
    return { last = {}, counts = {}, slots = {}, ge = {} }
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
    if scope ~= Made.CHARACTER and scope ~= Made.ALL then
        error("unknown Made count scope: " .. tostring(scope), 3)
    end
end

local function checkOffer(offer)
    if offer.type ~= Made.BUY and offer.type ~= Made.SELL then
        error("unknown GE offer type: " .. tostring(offer.type), 4)
    end
    if not STAGES[offer.stage] then
        error("unknown GE offer stage: " .. tostring(offer.stage), 4)
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

-- Call this on Have → Make. detected is the Detected stock of the Targets now.
-- offers are all the GE offers of the character now.
-- Other characters start at their next observation. Their slot data stays.
function Made.start(states, name, detected, offers)
    for _, state in pairs(states) do
        state.counts = {}
        state.last = {}
        state.ge = {}
    end
    local state = character(states, name)
    for item, count in pairs(detected) do
        state.last[item] = count
    end
    readOffers(state, offers)
end

-- Call this when the plugin loads the state of a character in Make.
-- A rise between sessions is not made, so the next observation is the starting point.
-- offers are all the GE offers of the character now.
function Made.load(states, name, offers)
    local state = character(states, name)
    state.last = {}
    state.ge = {}
    readOffers(state, offers)
end

-- Items that the GE gives to the player add to the GE amount of the character.
local function observeOffer(state, offer, detected)
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
    -- The keys of detected are the Targets.
    if detected[offer.item] then
        state.ge[offer.item] = (state.ge[offer.item] or 0) + amount
    end
    saveSlot(state, offer)
end

-- tick has the facts of one server tick for one character.
function Made.observe(states, name, tick)
    local state = character(states, name)
    for _, offer in ipairs(tick.ge or {}) do
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

-- Gives the made field of the Basis of Plan.calculate. scope is Made.CHARACTER or Made.ALL.
-- All characters is the sum of the states that the plugin has now.
function Made.counts(states, name, scope)
    checkScope(scope)
    local counts = {}
    for stateName, state in pairs(states) do
        if scope == Made.ALL or stateName == name then
            for item, count in pairs(state.counts) do
                counts[item] = (counts[item] or 0) + count
            end
        end
    end
    return counts
end

-- Call this on Make → Have.
function Made.stop(states)
    for name in pairs(states) do
        states[name] = nil
    end
end

-- Call this when the player removes a Target. targets are the Targets that remain.
-- It deletes the data of each item that no Target is for. Two Targets for the same item share its count (issue 16).
-- If the player adds a Target for the item again, it starts at its next observation.
function Made.forgetUnused(states, targets)
    local used = {}
    for _, target in ipairs(targets) do
        used[target.item] = true
    end
    for _, state in pairs(states) do
        for _, data in ipairs({ state.counts, state.last, state.ge }) do
            for item in pairs(data) do
                if not used[item] then
                    data[item] = nil
                end
            end
        end
    end
end

-- Sets the count of the current character. A reset sets it to 0.
-- In All characters, the other characters go to 0, so the sum is the new count.
function Made.set(states, name, scope, item, count)
    checkScope(scope)
    if scope == Made.ALL then
        for _, state in pairs(states) do
            state.counts[item] = 0
        end
    end
    character(states, name).counts[item] = count
end

return Made
