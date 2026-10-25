-- Gives the recipe params of an Obj or Struct config as plain values, for GameRecipe.fromParams (ADR 0017).
-- The adapter gives the config. Tests run this module outside the game client with fake configs.
-- It reads only the params that GameRecipe uses: GetParamValue on some other params logs a client error
-- that pcall does not catch (docs/recipe-params.md).

local ObjParams = {}

-- The kind of value of each param that GameRecipe uses, found from the param name.
local KINDS = {
    { pattern = "^RECIPE_INGREDIENT_TYPE_%d+$", kind = "obj" },
    { pattern = "^RECIPE_NON_DUMMY_OBJ$", kind = "obj" },
    { pattern = "^RECIPE_MULTI_OBJECT_OVERRIDE$", kind = "obj" },
    { pattern = "^RECIPE_INGREDIENT_%d+_MULTIPLE$", kind = "struct" },
    { pattern = "^RECIPE_INGREDIENT_NUMBER_%d+$", kind = "plain" },
    { pattern = "^RECIPE_INGREDIENT_%d+_SCALE_STACK$", kind = "plain" },
    { pattern = "^RECIPE_REQUIREMENT_TYPE_%d+$", kind = "plain" },
    { pattern = "^RECIPE_REQUIREMENT_VALUE_%d+$", kind = "plain" },
    { pattern = "^RECIPE_XP_TYPE_%d+$", kind = "plain" },
    { pattern = "^RECIPE_XP_VALUE_%d+$", kind = "plain" },
    { pattern = "^RECIPE_XP_SCALE_STACK_%d+$", kind = "plain" },
    { pattern = "^RECIPE_MAKE_STACK_SIZE$", kind = "plain" },
    { pattern = "^RECIPE_CYCLES$", kind = "plain" },
}

local function kindOf(name)
    for _, entry in ipairs(KINDS) do
        if name:find(entry.pattern) then
            return entry.kind
        end
    end
    return nil
end

-- Gives { PARAM_NAME = value }. An Obj value becomes its config name. A Struct value becomes a table of its params.
-- An Obj or Struct param with no value is a missing param (PR 92, 2026-10-25).
function ObjParams.read(config)
    local values = {}
    for _, param in ipairs(config.params or {}) do
        local kind = kindOf(param.configName)
        if kind then
            local value = config:GetParamValue(param)
            if value ~= nil and kind == "obj" then
                value = value.configName
            elseif value ~= nil and kind == "struct" then
                value = ObjParams.read(value)
            end
            values[param.configName] = value
        end
    end
    return values
end

return ObjParams
