-- Gives the name of an Unlock from the hand-written names in data/unlocks.lua.
-- plan/gamerecipe.lua makes the key UNLOCK<type>:<value>. The game names a quest or a blueprint, so they have no entry.
-- It does not use the game API. Tests run it outside the game client.
local UnlockName = {}

-- data is the table of data/unlocks.lua. Gives nil when the data has no name.
function UnlockName.of(data, unlock)
    local requirementType, value = unlock:match("^UNLOCK(%d+):(%d+)$")
    local entries = requirementType and data[tonumber(requirementType)]
    local entry = entries and entries[tonumber(value)]
    return entry and entry.name
end

return UnlockName
