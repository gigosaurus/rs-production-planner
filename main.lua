-- Production Planner. The adapter between the game client and the plan/ modules.
-- This file and ui/ use the game API. It reads the game and gives plain tables to plan/adapter (issue 25).
-- It builds the Recipes from the game at runtime (ADR 0017). ui/planwindow.lua shows the Plan (issue 26).
local Account = require("plan/account")
local Adapter = require("plan/adapter")
local GameRecipe = require("plan/gamerecipe")
local News = require("plan/news")
local ObjParams = require("plan/objparams")
local PlanWindow = require("ui/planwindow")
local UnlockName = require("plan/unlockname")
local View = require("plan/view")
local unlockData = require("data/unlocks")

-- Decisions on issue 24, 2026-10-25.
local IDS_PER_TICK = 250
local GAP = 1000

-- Issue 5: a changed row shows its highlight for approximately 4 seconds. A server tick is 0.6 seconds.
local HIGHLIGHT_TICKS = 7

-- ObjStackType ALWAYS. SOMETIMES stacks only in the bank, so it is not stackable (issue 2, section 1).
local STACK_ALWAYS = 1

-- The skill names of the Recipes are the SkillType names (plan/gamerecipe.lua).
local SKILLS = {
    "ATTACK",
    "STRENGTH",
    "RANGED",
    "MAGIC",
    "DEFENCE",
    "HITPOINTS",
    "PRAYER",
    "AGILITY",
    "HERBLORE",
    "THIEVING",
    "CRAFTING",
    "RUNECRAFTING",
    "MINING",
    "SMITHING",
    "FISHING",
    "COOKING",
    "FIREMAKING",
    "WOODCUTTING",
    "FLETCHING",
    "SLAYER",
    "FARMING",
    "CONSTRUCTION",
    "HUNTER",
    "SUMMONING",
    "DUNGEONEERING",
    "DIVINATION",
    "INVENTION",
    "ARCHAEOLOGY",
    "NECROMANCY",
}

local EVENT_NAME = "productionPlanner"
local BANK_ID = config.Inv.BANK.id
local IRONMAN = var.VarPlayer.IRONMAN

local recipes = nil
-- Each Obj config name that stacks everywhere. The scan fills it. Plan.calculate gets the same table each time.
local stackable = {}
local loggedIn = false
local ironman = nil

local function say(text)
    log("[Production Planner] " .. text)
end

-- Logs each problem of a Saved load or write.
local function report(problems)
    for _, problem in ipairs(problems) do
        say("Saved data problem: " .. problem.kind .. " for key " .. problem.key .. ".")
    end
end

local adapter, loadProblems = Adapter.new(PersistentDB)
report(loadProblems)

-- Gives the config name and the recipe params of an Obj id, or nil when the id has no Obj.
local function readObj(id)
    local obj = config.Obj.FromID(id)
    if obj == nil or obj.isValid ~= true then
        return nil
    end
    if obj.stackType == STACK_ALWAYS then
        stackable[obj.configName] = true
    end
    return obj.configName, ObjParams.read(obj)
end

local scan = GameRecipe.newScan(readObj, GAP)

-- Inventory.Find gives one Inv, although the docs give a list (docs/client-behaviour.md).
local function findInv(invType)
    local found = Inventory.Find(invType)
    if found ~= nil and found.isValid == nil then
        found = found[1]
    end
    if found == nil or not found.isValid then
        return nil
    end
    return found
end

-- Gives the slots of an Inv as plain tables. An empty slot has the id -1. plan/adapter removes it.
local function slotsOf(inv)
    local slots = {}
    for index = 1, inv.slotCount do
        local slot = inv:GetSlot(index)
        if slot ~= nil and slot.obj ~= nil then
            slots[#slots + 1] = { id = slot.obj.id, configName = slot.obj.configName, count = slot.count }
        end
    end
    return slots
end

local function readBank()
    local bank = findInv(BANK_ID)
    if bank ~= nil then
        Adapter.bank(adapter, slotsOf(bank))
    end
end

local function readLevels()
    local levels = {}
    for _, name in ipairs(SKILLS) do
        levels[name] = Player.GetLevelCapped(SkillType[name])
    end
    return levels
end

-- Account mode is not saved (ADR 0014). Nothing in Have uses it. Make uses it for GE offers (issue 10).
local function readAccountMode()
    local now = Account.isIronman(IRONMAN.value)
    if now ~= ironman then
        ironman = now
        say(ironman and "Account mode: ironman." or "Account mode: not ironman.")
    end
end

-- The names of items. config.Obj gives nil for an unknown config name.
local names = {}
local function nameOf(item)
    if names[item] == nil then
        local obj = config.Obj[item]
        names[item] = obj ~= nil and obj.name or false
    end
    return names[item] or nil
end

local function unlockName(unlock)
    return UnlockName.of(unlockData, unlock)
end

local news = News.new()
-- The last result of Adapter.tick, or nil before the first Plan.
local last = nil
local highlightTicks = 0

local planWindow

-- Draws the Plan view again. The highlights show only while highlightTicks is more than 0.
local function render()
    local view = last
        and View.build({
            plan = last.plan,
            detected = last.detected,
            bankSeen = Adapter.bankSeen(adapter),
            assumed = last.assumed,
            nameOf = nameOf,
            unlockName = unlockName,
        })
    PlanWindow.show(planWindow, view, news.message, highlightTicks > 0 and news.highlights or nil)
end

local function startHighlights()
    highlightTicks = News.hasHighlights(news) and HIGHLIGHT_TICKS or 0
end

local function newsState()
    return { plan = last.plan, assumed = last.assumed }
end

local function windowParent()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
end

planWindow = PlanWindow.new(windowParent, {
    onOpen = function()
        if last then
            News.open(news, newsState(), nameOf)
            startHighlights()
        end
        render()
    end,
    onClose = function()
        News.close(news)
    end,
    onDismiss = function()
        News.dismiss(news)
        render()
    end,
    onProblem = function(text)
        say("Plan window problem: " .. text)
    end,
})

local function show(result)
    last = result
    News.see(news, newsState(), nameOf)
    startHighlights()
    render()
end

-- The first ServerLogic tick with the player available is the login (issue 25, 2026-10-25).
local function login()
    local name = Player.GetEntity().displayName
    report(Adapter.login(adapter, name))
    -- The last Plan is the Plan of the previous character. The next tick gives the Plan of this character.
    News.reset(news)
    last, highlightTicks = nil, 0
    loggedIn = true
    readAccountMode()
    readBank()
    say("Character " .. name .. " logged in.")
end

Event.Logic.Subscribe(EVENT_NAME, function()
    if recipes == nil and scan:step(IDS_PER_TICK) then
        recipes = scan:recipes()
        say("The Recipe scan is done.")
    end
    report(Adapter.save(adapter))
end)

Event.ServerLogic.Subscribe(EVENT_NAME, function()
    if recipes == nil then
        return
    end
    if not loggedIn then
        if not Player.IsAvailable() then
            return
        end
        login()
    end
    if highlightTicks > 0 then
        highlightTicks = highlightTicks - 1
        if highlightTicks == 0 then
            render()
        end
    end
    local inventory = findInv(config.Inv.INV)
    if inventory == nil then
        return
    end
    local result = Adapter.tick(
        adapter,
        { inventory = slotsOf(inventory), recipes = recipes, levels = readLevels(), stackable = stackable }
    )
    if result ~= nil then
        show(result)
    end
end)

-- The bank arrives whole in one InventoryAdded event. InventoryUpdated keeps it up to date (ADR 0007).
local function onInventory(e)
    if loggedIn and e.inv.id == BANK_ID then
        readBank()
    end
end

Event.InventoryAdded.Subscribe(EVENT_NAME, onInventory)
Event.InventoryUpdated.Subscribe(EVENT_NAME, onInventory)

-- The game client shows the layer when the player selects the Ribbon Icon of the plugin in the Plugins window.
-- The size of the layer is not known yet (issue 26), so the plugin logs it.
Event.ContentLayerReady.Subscribe(EVENT_NAME, function(e)
    say("Ribbon layer ready: " .. e.component.width .. "x" .. e.component.height .. ".")
    PlanWindow.mountLayer(planWindow, e.component)
end)

Event.VarTransmit.Subscribe(EVENT_NAME, function(e)
    if loggedIn and e.var.id == IRONMAN.id then
        readAccountMode()
    end
end)

-- Outside GAME, the plugin pauses. At the next login, it reads the name again.
-- A logout disables the plugin on the dev servers (docs/client-behaviour.md). So the plugin saves now.
Event.GameStateChanged.Subscribe(EVENT_NAME, function(e)
    if e.newState ~= GameState.GAME and loggedIn then
        Adapter.leave(adapter)
        loggedIn = false
        report(Adapter.save(adapter))
    end
end)

function PluginShutdown()
    report(Adapter.save(adapter))
    PlanWindow.destroy(planWindow)
    Event.ContentLayerReady.Unsubscribe(EVENT_NAME)
    Event.Logic.Unsubscribe(EVENT_NAME)
    Event.ServerLogic.Unsubscribe(EVENT_NAME)
    Event.InventoryAdded.Unsubscribe(EVENT_NAME)
    Event.InventoryUpdated.Unsubscribe(EVENT_NAME)
    Event.VarTransmit.Unsubscribe(EVENT_NAME)
    Event.GameStateChanged.Unsubscribe(EVENT_NAME)
end
