-- Keeps the saved data, as ADR 0008 and ADR 0011 describe.
-- It does not use the game API. Tests run it outside the game client.
-- The adapter gives it a store with Get and Set, for example PersistentDB.
local Assumed = require("plan/assumed")

local Saved = {}

-- Problem kinds
Saved.UNKNOWN_VERSION = "UNKNOWN_VERSION"
Saved.NOT_SAVED = "NOT_SAVED"

-- PersistentDB keeps numbers as 32-bit floats, so each count is saved as a decimal string (ADR 0011).
local function countText(count)
    return string.format("%d", count)
end

local function countOf(text)
    return math.tointeger(tonumber(text))
end

local function tableVersionOf(value)
    return type(value) == "table" and math.tointeger(value.v) or nil
end

-- The Bank snapshot is one string: a version line, then one line `<name>=<count>` for each item.
local bank = { version = 1 }

function bank.versionOf(text)
    return math.tointeger(tonumber(text:match("^v=(%d+)\n")))
end

function bank.encode(snapshot)
    local names = {}
    for name in pairs(snapshot) do
        names[#names + 1] = name
    end
    table.sort(names)
    local lines = { "v=1\n" }
    for _, name in ipairs(names) do
        lines[#lines + 1] = name .. "=" .. countText(snapshot[name]) .. "\n"
    end
    return table.concat(lines)
end

function bank.decode(text)
    local snapshot = {}
    for name, count in text:gsub("^[^\n]*\n", "", 1):gmatch("([^\n]*)=(%d+)\n") do
        snapshot[name] = countOf(count)
    end
    return snapshot
end

-- A character that the plugin has not seen has no Bank snapshot.
function bank.start()
    return nil
end

local assumed = { version = 1, versionOf = tableVersionOf, start = Assumed.new }

function assumed.encode(state)
    local entries = {}
    for index, entry in ipairs(state.entries) do
        entries[index] = {
            item = entry.item,
            entered = countText(entry.entered),
            remaining = countText(entry.remaining),
            baseline = countText(entry.baseline),
        }
    end
    return { v = assumed.version, entries = entries }
end

function assumed.decode(value)
    local state = Assumed.new()
    for index, entry in ipairs(value.entries) do
        state.entries[index] = {
            item = entry.item,
            entered = countOf(entry.entered),
            remaining = countOf(entry.remaining),
            baseline = countOf(entry.baseline),
        }
    end
    return state
end

local function empty()
    return {}
end

local reserves = { version = 1, versionOf = tableVersionOf, start = empty }

function reserves.encode(counts)
    local texts = {}
    for item, count in pairs(counts) do
        texts[item] = countText(count)
    end
    return { v = reserves.version, reserves = texts }
end

function reserves.decode(value)
    local counts = {}
    for item, text in pairs(value.reserves) do
        counts[item] = countOf(text)
    end
    return counts
end

local unlocks = { version = 1, versionOf = tableVersionOf, start = empty }

function unlocks.encode(set)
    local copy = {}
    for unlock in pairs(set) do
        copy[unlock] = true
    end
    return { v = unlocks.version, unlocks = copy }
end

function unlocks.decode(value)
    local set = {}
    for unlock in pairs(value.unlocks) do
        set[unlock] = true
    end
    return set
end

local CODECS = { bank = bank, assumed = assumed, reserves = reserves, unlocks = unlocks }

-- The display names of all characters that have saved data, in the order that the plugin added them.
local CHARACTERS_KEY = "global:characters"
local characters = { version = 1, versionOf = tableVersionOf, start = empty }

function characters.encode(names)
    return { v = characters.version, characters = table.move(names, 1, #names, 1, {}) }
end

function characters.decode(value)
    return table.move(value.characters, 1, #value.characters, 1, {})
end

local function key(name, part)
    return "char:" .. name .. ":" .. part
end

function Saved.new(store)
    return { store = store, changed = {}, blocked = {}, characters = nil }
end

-- Gives the value of one key, decoded, or the start value. A key with an unknown version is blocked.
local function load(saved, codec, loadKey, problems)
    local value = saved.store:Get(loadKey)
    if value == nil then
        return codec.start()
    end
    if codec.versionOf(value) == codec.version then
        return codec.decode(value)
    end
    saved.blocked[loadKey] = true
    problems[#problems + 1] = { key = loadKey, kind = Saved.UNKNOWN_VERSION }
    return codec.start()
end

-- Gives the global data, and a list of problems. Call this one time at start, before a change.
function Saved.loadGlobal(saved)
    local problems = {}
    saved.characters = load(saved, characters, CHARACTERS_KEY, problems)
    return { characters = table.move(saved.characters, 1, #saved.characters, 1, {}) }, problems
end

-- Gives the saved parts of one character, and a list of problems.
-- The plugin does not read or write a key with no version or a newer version (ADR 0011).
-- Such a part gets its start value.
function Saved.loadCharacter(saved, name)
    local parts, problems = {}, {}
    for part, codec in pairs(CODECS) do
        parts[part] = load(saved, codec, key(name, part), problems)
    end
    return parts, problems
end

-- Marks a part as changed. Saved.write writes it.
-- The first change for a character adds its name to the saved characters.
function Saved.change(saved, name, part, value)
    if not saved.characters then
        error("Load the global data before a change.", 2)
    end
    saved.changed[key(name, part)] = CODECS[part].encode(value)
    for _, known in ipairs(saved.characters) do
        if known == name then
            return
        end
    end
    saved.characters[#saved.characters + 1] = name
    saved.changed[CHARACTERS_KEY] = characters.encode(saved.characters)
end

-- Call this one time in each Logic tick. It writes each changed part one time, and gives a list of problems.
-- A part that the store does not save is not marked again. Its next change tries again (ADR 0011).
function Saved.write(saved)
    local problems = {}
    for changedKey, value in pairs(saved.changed) do
        if not saved.blocked[changedKey] and not saved.store:Set(changedKey, value) then
            problems[#problems + 1] = { key = changedKey, kind = Saved.NOT_SAVED }
        end
    end
    saved.changed = {}
    return problems
end

return Saved
