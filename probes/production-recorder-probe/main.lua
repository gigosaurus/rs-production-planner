-- Throwaway probe for the recipe gaps in docs/recipe-params.md.
-- Make items in the developer environment while this probe runs. It logs:
-- 1. Each XP gain, with the server ticks since the last gain (Action time).
-- 2. Each item count change in every inventory (Inputs, Outputs, other Outputs, failures such as burnt food).
-- 3. Each inventory that the server adds or removes (for example forge storage or Invention materials).
-- After IDLE_TICKS server ticks with no XP gain, it logs a summary of the session:
-- the number of actions (Action limit), the ticks between actions, and the net change of each item.
-- Each log line starts with the server tick (ServerLogic count) and the client logic tick.

local IDLE_TICKS = 10

local serverTick = 0
local logicTick = 0

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do
        parts[i] = tostring(v)
    end
    log("[s" .. serverTick .. " l" .. logicTick .. "] " .. table.concat(parts, " "))
end

-- Config name of an inventory, guarded because the lookup may fail for unknown IDs
local function invName(id)
    local ok, result = pcall(function()
        return config.Inv.FromID(id).configName
    end)
    return ok and tostring(result) or ("lookup failed: " .. tostring(result))
end

-- SkillType is not always a table that pairs can walk, so the lookup is guarded
local function skillName(skill)
    local ok, name = pcall(function()
        for key, value in pairs(SkillType) do
            if value == skill then
                return key
            end
        end
    end)
    return ok and name or tostring(skill)
end

-- Item totals by item ID for one inventory
local function totalsOf(inv)
    local totals = {}
    if inv == nil or not inv.isValid then
        return totals
    end
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        if slot ~= nil and slot.obj ~= nil and slot.obj.id ~= -1 then
            local entry = totals[slot.obj.id] or { name = slot.obj.name, count = 0 }
            entry.count = entry.count + slot.count
            totals[slot.obj.id] = entry
        end
    end
    return totals
end

-- The last totals of each inventory, by inventory ID
local lastTotals = {}

-- The current session. It starts at the first XP gain and ends after IDLE_TICKS with no gain.
local session = nil

local function addToSession(invID, itemID, name, change)
    if session == nil then
        return
    end
    local key = invID .. ":" .. itemID
    local entry = session.items[key] or { inv = invName(invID), name = name, id = itemID, change = 0 }
    entry.change = entry.change + change
    session.items[key] = entry
end

local function logChanges(invID, now)
    local before = lastTotals[invID] or {}
    for id, entry in pairs(now) do
        local old = before[id] and before[id].count or 0
        if entry.count ~= old then
            say("ITEM", invName(invID), entry.name, "id=" .. id, old .. " -> " .. entry.count)
            addToSession(invID, id, entry.name, entry.count - old)
        end
    end
    for id, entry in pairs(before) do
        if now[id] == nil then
            say("ITEM", invName(invID), entry.name, "id=" .. id, entry.count .. " -> 0")
            addToSession(invID, id, entry.name, -entry.count)
        end
    end
    lastTotals[invID] = now
end

local function median(values)
    if #values == 0 then
        return "none"
    end
    local sorted = {}
    for i, v in ipairs(values) do
        sorted[i] = v
    end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

local function endSession()
    local s = session
    session = nil
    local gaps = {}
    for i = 2, #s.actionTicks do
        gaps[#gaps + 1] = s.actionTicks[i] - s.actionTicks[i - 1]
    end
    say(
        "SESSION END",
        "actions=" .. #s.actionTicks,
        "first tick=" .. s.actionTicks[1],
        "last tick=" .. s.actionTicks[#s.actionTicks],
        "median gap=" .. tostring(median(gaps)),
        "gaps=" .. table.concat(gaps, ",")
    )
    for skill, xp in pairs(s.xp) do
        say("SESSION XP", skill, "total=" .. xp, "per action=" .. (xp / #s.actionTicks))
    end
    for _, entry in pairs(s.items) do
        if entry.change ~= 0 then
            say("SESSION ITEM", entry.inv, entry.name, "id=" .. entry.id, "net=" .. entry.change)
        end
    end
end

Event.ServerLogic.Subscribe("productionRecorderProbe", function()
    serverTick = serverTick + 1
    if session ~= nil and serverTick - session.actionTicks[#session.actionTicks] >= IDLE_TICKS then
        endSession()
    end
end)

Event.Logic.Subscribe("productionRecorderProbe", function(e)
    logicTick = e.logicTick
end)

Event.SkillTransmit.Subscribe("productionRecorderProbe", function(e)
    local gain = e.newXP - e.oldXP
    if gain <= 0 then
        return
    end
    local name = skillName(e.skill)
    -- Two skills can gain XP from one action in the same tick. Count one action per tick.
    if session == nil then
        session = { actionTicks = { serverTick }, xp = {}, items = {} }
        say("SESSION START")
    elseif session.actionTicks[#session.actionTicks] ~= serverTick then
        local last = session.actionTicks[#session.actionTicks]
        session.actionTicks[#session.actionTicks + 1] = serverTick
        say("GAP", serverTick - last)
    end
    session.xp[name] = (session.xp[name] or 0) + gain
    say("XP", name, e.oldXP .. " -> " .. e.newXP, "gain=" .. gain, "action=" .. #session.actionTicks)
end)

Event.InventoryAdded.Subscribe("productionRecorderProbe", function(e)
    local inv = Inventory.Find(e.inv)[1]
    local slots = inv and inv.isValid and inv.slotCount or "?"
    say("INV ADDED", "id=" .. e.inv.id, invName(e.inv.id), "slots=" .. tostring(slots))
    lastTotals[e.inv.id] = totalsOf(inv)
end)

Event.InventoryRemoved.Subscribe("productionRecorderProbe", function(e)
    say("INV REMOVED", "id=" .. e.inv.id, invName(e.inv.id))
    lastTotals[e.inv.id] = nil
end)

Event.InventoryUpdated.Subscribe("productionRecorderProbe", function(e)
    logChanges(e.inv.id, totalsOf(Inventory.Find(e.inv)[1]))
end)

-- Read the backpack now, so the first update logs only the change.
lastTotals[config.Inv.INV.id] = totalsOf(Inventory.Find(config.Inv.INV)[1])

function PluginShutdown()
    Event.ServerLogic.Unsubscribe("productionRecorderProbe")
    Event.Logic.Unsubscribe("productionRecorderProbe")
    Event.SkillTransmit.Unsubscribe("productionRecorderProbe")
    Event.InventoryAdded.Unsubscribe("productionRecorderProbe")
    Event.InventoryRemoved.Unsubscribe("productionRecorderProbe")
    Event.InventoryUpdated.Unsubscribe("productionRecorderProbe")
end

say("Production recorder probe running")
