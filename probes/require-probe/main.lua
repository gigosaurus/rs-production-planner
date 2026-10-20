-- Throwaway probe: when does require() return nil?
-- The planner prototype's require("editing") returned nil even though editing.lua
-- was in the copied plugin folder. Each case below isolates one possible cause.

local function try(path)
    local ok, result = pcall(require, path)
    local shape
    if not ok then shape = "ERROR: " .. tostring(result)
    elseif result == nil then shape = "nil"
    elseif type(result) == "table" then shape = "table " .. tostring(result.name) .. (result.count and (" count=" .. result.count) or "")
    elseif type(result) == "function" then shape = "function"
    else shape = type(result) .. " " .. tostring(result) end
    log("[require-probe] require(\"" .. path .. "\") = " .. shape)
end

log("[require-probe] type(require) = " .. type(require) .. ", type(package) = " .. type(package))
try("root_table")      -- top-level module returning a table
try("root_function")   -- top-level module returning a function (like editing.lua)
try("sub/nested")      -- module in a subfolder (like PrettyUI's src/)
try("unicode")         -- non-ASCII characters in the file
try("large")           -- about 40KB
try("editing")         -- the prototype's editing module, rebuilt from main.lua
try("broken")          -- error while running
try("missing")         -- file that doesn't exist
try("late")            -- doesn't exist on first load; add late.lua, copy, prl, then pon again
