-- Keeps the saved data, as ADR 0008 and ADR 0011 describe.
-- It does not use the game API. Tests run it outside the game client.
-- The adapter gives it a store with Get and Set, for example PersistentDB.
local Saved = {}

-- Problem kinds
Saved.UNKNOWN_VERSION = "UNKNOWN_VERSION"

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
        lines[#lines + 1] = name .. "=" .. string.format("%d", snapshot[name]) .. "\n"
    end
    return table.concat(lines)
end

function bank.decode(text)
    local snapshot = {}
    for name, count in text:gsub("^[^\n]*\n", "", 1):gmatch("([^\n]*)=(%d+)\n") do
        snapshot[name] = math.tointeger(tonumber(count))
    end
    return snapshot
end

local CODECS = { bank = bank }

local function key(name, part)
    return "char:" .. name .. ":" .. part
end

function Saved.new(store)
    return { store = store, changed = {}, blocked = {} }
end

-- Gives the saved parts of one character, and a list of problems.
-- The plugin does not read or write a key with no version or a newer version (ADR 0011).
function Saved.loadCharacter(saved, name)
    local parts, problems = {}, {}
    for part, codec in pairs(CODECS) do
        local partKey = key(name, part)
        local value = saved.store:Get(partKey)
        if value ~= nil then
            local version = codec.versionOf(value)
            if version == codec.version then
                parts[part] = codec.decode(value)
            else
                saved.blocked[partKey] = true
                problems[#problems + 1] = { key = partKey, kind = Saved.UNKNOWN_VERSION }
            end
        end
    end
    return parts, problems
end

-- Marks a part as changed. Saved.write writes it.
function Saved.change(saved, name, part, value)
    saved.changed[key(name, part)] = CODECS[part].encode(value)
end

-- Call this one time in each Logic tick. It writes each changed part one time.
function Saved.write(saved)
    for changedKey, value in pairs(saved.changed) do
        if not saved.blocked[changedKey] then
            saved.store:Set(changedKey, value)
        end
    end
    saved.changed = {}
end

return Saved
