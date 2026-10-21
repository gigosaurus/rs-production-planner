-- Keeps the saved data, as ADR 0008 and ADR 0011 describe.
-- It does not use the game API. Tests run it outside the game client.
-- The adapter gives it a store with Get and Set, for example PersistentDB.
local Saved = {}

-- The Bank snapshot is one string: a version line, then one line `<name>=<count>` for each item.
local bank = {}

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
    for name, count in text:gmatch("([^\n]*)=(%d+)\n") do
        if name ~= "v" then
            snapshot[name] = math.tointeger(tonumber(count))
        end
    end
    return snapshot
end

local CODECS = { bank = bank }

local function key(name, part)
    return "char:" .. name .. ":" .. part
end

function Saved.new(store)
    return { store = store, changed = {} }
end

-- Gives the saved parts of one character.
function Saved.loadCharacter(saved, name)
    local parts = {}
    for part, codec in pairs(CODECS) do
        local value = saved.store:Get(key(name, part))
        if value ~= nil then
            parts[part] = codec.decode(value)
        end
    end
    return parts
end

-- Marks a part as changed. Saved.write writes it.
function Saved.change(saved, name, part, value)
    saved.changed[key(name, part)] = CODECS[part].encode(value)
end

-- Call this one time in each Logic tick. It writes each changed part one time.
function Saved.write(saved)
    for changedKey, value in pairs(saved.changed) do
        saved.store:Set(changedKey, value)
    end
    saved.changed = {}
end

return Saved
