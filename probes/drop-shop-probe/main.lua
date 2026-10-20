-- Throwaway probe for issue 06 (Make):
-- 1. Drop: does a backpack fall and a new owned obj stack of the same item and count occur in the same server tick?
--    Also: what fires when the player drops onto a tile that already has a stack, and when they pick up?
-- 2. Shops: which inventories does the server add and remove when a shop opens and closes, and what are their config names?
-- Each log line starts with the server tick (ServerLogic count) and the client logic tick.

local BACKPACK_ID = config.Inv.INV.id
local serverTick = 0
local logicTick = 0

Event.ServerLogic.Subscribe("dropShopProbe", function() serverTick = serverTick + 1 end)
Event.Logic.Subscribe("dropShopProbe", function(e) logicTick = e.logicTick end)

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log("[s" .. serverTick .. " l" .. logicTick .. "] " .. table.concat(parts, " "))
end

-- Config name of an inventory, guarded because the lookup may fail for unknown IDs
local function invName(id)
    local ok, result = pcall(function() return config.Inv.FromID(id).configName end)
    return ok and tostring(result) or ("lookup failed: " .. tostring(result))
end

-- Backpack totals by item ID, so each update can log what rose and what fell
local function backpackTotals()
    local totals = {}
    local inv = Inventory.Find(config.Inv.INV)
    if inv == nil or not inv.isValid then return totals end
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        if slot ~= nil and slot.obj ~= nil and slot.obj.id ~= -1 then
            totals[slot.obj.id] = { name = slot.obj.name, count = (totals[slot.obj.id] and totals[slot.obj.id].count or 0) + slot.count }
        end
    end
    return totals
end

local lastTotals = backpackTotals()

local function logBackpackChanges()
    local now = backpackTotals()
    for id, entry in pairs(now) do
        local before = lastTotals[id] and lastTotals[id].count or 0
        if entry.count ~= before then say("BACKPACK", entry.name, "id=" .. id, before .. " -> " .. entry.count) end
    end
    for id, entry in pairs(lastTotals) do
        if now[id] == nil then say("BACKPACK", entry.name, "id=" .. id, entry.count .. " -> 0") end
    end
    lastTotals = now
end

Event.InventoryAdded.Subscribe("dropShopProbe", function(e)
    say("INV ADDED", "id=" .. e.inv.id, invName(e.inv.id))
    if e.inv.id == BACKPACK_ID then lastTotals = backpackTotals() end
end)

Event.InventoryRemoved.Subscribe("dropShopProbe", function(e)
    say("INV REMOVED", "id=" .. e.inv.id, invName(e.inv.id))
end)

Event.InventoryUpdated.Subscribe("dropShopProbe", function(e)
    if e.inv.id == BACKPACK_ID then
        logBackpackChanges()
    else
        say("INV UPDATED", "id=" .. e.inv.id, invName(e.inv.id))
    end
end)

Event.ObjStackEntityAdded.Subscribe("dropShopProbe", function(e)
    say("STACK ADDED", e.objType.name, "id=" .. e.objType.id, "x" .. e.count, "isOwner=" .. tostring(e.isOwner))
end)

Event.ObjStackEntityChanged.Subscribe("dropShopProbe", function(e)
    say("STACK CHANGED", e.objType.name, "id=" .. e.objType.id, e.oldCount .. " -> " .. e.newCount, "isOwner=" .. tostring(e.isOwner))
end)

Event.ObjStackEntityRemoved.Subscribe("dropShopProbe", function(e)
    say("STACK REMOVED", e.objType.name, "id=" .. e.objType.id, "x" .. e.count, "isOwner=" .. tostring(e.isOwner))
end)

say("Drop shop probe running")
