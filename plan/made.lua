-- Keeps the Made counts in Make, as ADR 0009 describes.
-- It does not use the game API. Tests run it outside the game client.
-- The state is a plain table, so the plugin can save it with PersistentDB.
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

function Made.new()
    return { characters = {}, all = {} }
end

local function character(state, name)
    local data = state.characters[name]
    if not data then
        data = { last = {}, counts = {}, slots = {}, ge = {} }
        state.characters[name] = data
    end
    return data
end

-- Call this on Have → Make. detected is the Detected stock of the Targets now.
-- Other characters start at their next observation.
function Made.start(state, name, detected)
    Made.stop(state)
    local data = character(state, name)
    for item, count in pairs(detected) do
        data.last[item] = count
    end
end

-- Items that the GE gives to the player add to the GE amount of the character.
local function observeOffer(data, offer, detected)
    if offer.type ~= Made.BUY and offer.type ~= Made.SELL then
        error("unknown GE offer type: " .. tostring(offer.type), 3)
    end
    if not STAGES[offer.stage] then
        error("unknown GE offer stage: " .. tostring(offer.stage), 3)
    end
    local slot = data.slots[offer.slot]
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
        data.ge[offer.item] = (data.ge[offer.item] or 0) + amount
    end
    data.slots[offer.slot] = { item = offer.item, type = offer.type, stage = offer.stage, soldCount = offer.soldCount }
end

-- tick has the facts of one server tick for one character.
function Made.observe(state, name, tick)
    local data = character(state, name)
    for _, offer in ipairs(tick.ge or {}) do
        observeOffer(data, offer, tick.detected)
    end
    for item, now in pairs(tick.detected) do
        -- With no last count, a first Bank snapshot or an open shop, this observation is the starting point.
        local rise = (tick.firstBank or tick.shopOpen) and 0 or now - (data.last[item] or now)
        -- A rise in the same tick as a ground stack decrease is a pickup.
        rise = rise - ((tick.groundDecrease or {})[item] or 0)
        -- The rest of the rise uses up the GE amount first.
        local fromGE = math.max(0, math.min(rise, data.ge[item] or 0))
        data.ge[item] = (data.ge[item] or 0) - fromGE
        rise = rise - fromGE
        if rise > 0 then
            data.counts[item] = (data.counts[item] or 0) + rise
            state.all[item] = (state.all[item] or 0) + rise
        end
        data.last[item] = now
    end
end

-- Gives the made input of Plan.calculate. scope is Made.CHARACTER or Made.ALL.
function Made.counts(state, name, scope)
    if scope == Made.ALL then
        return state.all
    elseif scope == Made.CHARACTER then
        return character(state, name).counts
    end
    error("unknown Made count scope: " .. tostring(scope), 2)
end

-- Call this on Make → Have.
function Made.stop(state)
    state.characters = {}
    state.all = {}
end

-- If the player adds the Target again, it starts at its next observation.
function Made.removeTarget(state, item)
    for _, data in pairs(state.characters) do
        data.counts[item] = nil
        data.last[item] = nil
        data.ge[item] = nil
    end
    state.all[item] = nil
end

-- Sets the count of the selected scope only. A reset sets it to 0.
function Made.set(state, name, scope, item, count)
    Made.counts(state, name, scope)[item] = count
end

return Made
