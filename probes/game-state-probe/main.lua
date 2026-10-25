-- Throwaway probe for #25: what does the plugin see when the player logs out and logs in again?
-- Question: does GameStateChanged come, and what values does it give?
-- Steps: pon in the game. Log out to the lobby. Log in again. Then log out to the login screen and log in again.
-- The probe logs each GameStateChanged event, and each change of Player.IsAvailable() or of the player name.
-- Do not put the character "<" in log text (docs/client-behaviour.md).
-- Second run: after the login, walk for 10 s, then prl. The load line gives the last tick that the old run saved.
-- If that tick is after the logout tick, the plugin ran after the login, but its log did not show.

local serverTick = 0

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do
        parts[i] = tostring(v)
    end
    log("[gamestate s" .. serverTick .. "] " .. table.concat(parts, " "))
end

local function nameNow()
    local ok, name = pcall(function()
        return Player.GetEntity().displayName
    end)
    return ok and tostring(name) or ("read failed: " .. tostring(name))
end

Event.GameStateChanged.Subscribe("gameStateProbe", function(e)
    PersistentDB:Set("stateTick", serverTick)
    say(
        "GameStateChanged old=",
        e.oldState,
        "(" .. type(e.oldState) .. ")",
        "new=",
        e.newState,
        "(" .. type(e.newState) .. ")",
        "new == GameState.GAME:",
        e.newState == GameState.GAME,
        "GameState.GAME=",
        GameState.GAME
    )
end)

local lastAvailable, lastName = nil, nil

local function watch(source)
    local available = Player.IsAvailable()
    local name = available and nameNow() or "-"
    if available ~= lastAvailable or name ~= lastName then
        say(source, "IsAvailable=", available, "name=", name)
        lastAvailable, lastName = available, name
    end
end

Event.ServerLogic.Subscribe("gameStateProbe", function()
    serverTick = serverTick + 1
    PersistentDB:Set("lastTick", serverTick)
    watch("ServerLogic")
end)

-- Logic runs also when no server tick comes, for example in the lobby.
Event.Logic.Subscribe("gameStateProbe", function()
    watch("Logic")
end)

say("Last run: last ServerLogic tick", PersistentDB:Get("lastTick"), "| tick of last GameStateChanged", PersistentDB:Get("stateTick"))
PersistentDB:Delete("lastTick")
PersistentDB:Delete("stateTick")
say("Game state probe running. GameState.GAME =", GameState.GAME, "LOBBY =", GameState.LOBBY)
watch("load")
