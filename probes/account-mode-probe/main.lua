-- Throwaway probe for issue 52 (Account mode):
-- Is there a var that tells if the character is an ironman, hardcore ironman or group ironman?
-- 1. Scan: at start, look for var names that contain an ironman word, in var.* and id.* tables.
-- 2. Watch: log each var that changes. Then run these cheats, one at a time, and read the lines after each:
--    !setironman 1, !setironman 0, !sethardcore 1, !sethardcore 0, !setgroupironman 1, !setgroupironman 0
-- 3. Log out and in after a cheat, if no var changes. The server may send the var only at login.
-- Each log line starts with the server tick (ServerLogic count) and the client logic tick.

local serverTick = 0
local logicTick = 0

Event.ServerLogic.Subscribe("accountModeProbe", function() serverTick = serverTick + 1 end)
Event.Logic.Subscribe("accountModeProbe", function(e) logicTick = e.logicTick end)

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log("[s" .. serverTick .. " l" .. logicTick .. "] " .. table.concat(parts, " "))
end

local WORDS = { "IRON", "HARDCORE", "HCIM", "GIM", "GROUP", "ACCOUNT", "GAMEMODE", "GAME_MODE" }

-- Guessed names, for when a table cannot be iterated
local GUESSES = {
    "IRONMAN",
    "IRON_MAN",
    "IRONMAN_MODE",
    "IRONMAN_STATUS",
    "HARDCORE",
    "HARDCORE_IRONMAN",
    "GROUP_IRONMAN",
    "GIM",
    "ACCOUNT_TYPE",
    "ACCOUNT_MODE",
    "GAME_MODE",
}

local function matches(name)
    local upper = string.upper(tostring(name))
    for _, word in ipairs(WORDS) do
        if string.find(upper, word, 1, true) then return true end
    end
    return false
end

-- Value of a VarType, guarded because the read may fail
local function varValue(v)
    local ok, result = pcall(function() return v.value end)
    return ok and tostring(result) or ("read failed: " .. tostring(result))
end

local function describe(v)
    local ok, text = pcall(function()
        return v.typeName
            .. "."
            .. v.configName
            .. " id="
            .. v.id
            .. " isVarBit="
            .. tostring(v.isVarBit)
            .. " valueType="
            .. tostring(v.valueType)
    end)
    return ok and text or ("describe failed: " .. tostring(text))
end

-- Iterate one table and log the names that match, with the value for var.* tables
local function scan(label, tbl, isVarTable)
    if tbl == nil then
        say("SCAN", label, "table is nil")
        return
    end
    local count, found = 0, 0
    local ok, err = pcall(function()
        for name, entry in pairs(tbl) do
            count = count + 1
            if matches(name) then
                found = found + 1
                if isVarTable then
                    say("SCAN MATCH", label, describe(entry), "value=" .. varValue(entry))
                else
                    say("SCAN MATCH", label, tostring(name), "=", tostring(entry))
                end
            end
        end
    end)
    if ok then
        say("SCAN", label, "entries=" .. count, "matches=" .. found)
    else
        say("SCAN", label, "pairs failed:", err)
    end
end

local function tryGuesses(label, tbl)
    if tbl == nil then return end
    for _, name in ipairs(GUESSES) do
        local ok, v = pcall(function() return tbl[name] end)
        if not ok then
            say("GUESS", label, name, "lookup failed:", v)
        elseif v ~= nil then
            say("GUESS FOUND", label, describe(v), "value=" .. varValue(v))
        end
    end
end

local function scanAll()
    say("Scan start")
    scan("var.VarPlayer", var.VarPlayer, true)
    scan("var.VarClient", var.VarClient, true)
    scan("id.VarPlayer", id.VarPlayer, false)
    scan("id.VarClient", id.VarClient, false)
    tryGuesses("var.VarPlayer", var.VarPlayer)
    tryGuesses("var.VarClient", var.VarClient)
    say("Scan end")
end

Event.VarTransmit.Subscribe("accountModeProbe", function(e)
    if e.oldValue == e.newValue then return end
    say("VAR", describe(e.var), tostring(e.oldValue) .. " -> " .. tostring(e.newValue))
end)

-- Scan again in the game, because some vars arrive only after login
Event.GameStateChanged.Subscribe("accountModeProbe", function(e)
    say("GAME STATE", tostring(e.oldState), "->", tostring(e.newState))
    -- The docs example reads the state as an ID, so accept the ID (GAME = 30) too
    if e.newState == GameState.GAME or e.newState == 30 then scanAll() end
end)

say("Account mode probe running")
scanAll()
