if not Plugin.HasPermission(PluginPermissions.httpAccess) then
    log("[Object export] HTTP permission is unavailable")
end

local jsonBox
local updateJSONBox
local KEY = "object-tree-inspector"
local MAX_CHILDREN = 300
local MAX_VISIBLE = 1200
local MAX_DEPTH = 12
local MAX_BULK_JSON_BYTES = 100000000
-- Groups that hold game data. Other groups are inspector metadata.
local DATA_GROUPS = { params = true, columns = true }
local window, list, status, detail, idField
local root, pending, search = nil, nil, ""
local dirty, rendering, started = false, false, false
local visible = {}

local function str(v)
    local ok, s = pcall(tostring, v)
    return ok and s or "<unprintable>"
end
local function get(v,k) return pcall(function() return v[k] end) end
local function meta(v)
    local ok,t=pcall(getmetatable,v)
    return ok and type(t)=="table" and t or nil
end
local function keys(t)
    local r={}
    for k in next,t do r[#r+1]=k end
    table.sort(r,function(a,b)
        if type(a)=="number" and type(b)=="number" then return a<b end
        return type(a)..str(a)<type(b)..str(b)
    end)
    return r
end
local function members(v)
    local found,seen={},{}
    local function visit(t)
        if type(t)~="table" or seen[t] then return end
        seen[t]=true
        for k in next,t do
            if type(k)=="string" and k:sub(1,2)~="__"
                and k~="new" and k~="class_check" and k~="class_cast" then found[k]=true end
        end
        visit(rawget(t,"__index"))
    end
    visit(meta(v))
    return keys(found)
end
local function identity(v)
    local a,t=get(v,"typeName")
    local b,id=get(v,"id")
    if a and b and type(t)=="string" and type(id)=="number" then return t..":"..str(id) end
    return v
end
local function node(name,v,parent)
    local n={name=str(name),value=v,parent=parent,open=false}
    local t=type(v)
    n.branch=t=="table" or t=="userdata"
    if n.branch then
        n.identity=t=="userdata" and identity(v) or v
        local p=parent
        while p do
            if p.identity==n.identity then n.cycle=true; n.branch=false; break end
            p=p.parent
        end
    end
    return n
end
local function group(name,parent)
    return {name=name,parent=parent,branch=true,children={},open=false,group=true}
end
local function add(parent,child) parent.children[#parent.children+1]=child end
local function warning(parent,message)
    local n=node("Warning",message,parent); n.warning=true; add(parent,n)
end
local function parameterName(p)
    local ok,n=get(p,"configName")
    return ok and type(n)=="string" and n or str(p)
end
local function populate(n,depth,limit)
    if n.children or not n.branch then return end
    limit=limit or MAX_CHILDREN
    n.children={}
    if depth>=MAX_DEPTH then warning(n,"Expansion depth limit reached"); return end
    local v=n.value
    if type(v)=="table" then
        local ks=keys(v)
        for i,k in ipairs(ks) do
            if i>limit then warning(n,"Remaining table entries omitted"); break end
            add(n,node(k,rawget(v,k),n))
        end
        return
    end
    local ns=members(v)
    local params,getter,paramCount,paramValues
    local advanced=group("Methods and metadata",n)
    if #ns==0 then warning(n,"No enumerable member names in accessible metatable") end
    for i,k in ipairs(ns) do
        if i>limit then warning(n,"Remaining members omitted"); break end
        local ok,value=get(v,k)
        if not ok then
            local x=node(k,str(value),n); x.warning=true; add(n,x)
        elseif k=="params" then params=value
        elseif k=="paramValues" and type(value)=="table" then paramValues=value
        elseif type(value)=="function" then
            if k=="GetParamValue" then getter=value end
            add(advanced,node(k,value,advanced))
        else
            if k=="paramCount" then paramCount=value end
            add(n,node(k,value,n))
        end
    end
    if type(params)=="table" then
        local pg=group("params",n)
        pg.open = true
        local definitions=group("Parameter definitions",advanced)
        local ks=keys(params)
        for i,k in ipairs(ks) do
            if i>limit then warning(pg,"Remaining parameters omitted"); break end
            local p=rawget(params,k)
            local name=parameterName(p)
            add(definitions,node(name,p,definitions))
            if type(getter)=="function" then
                local ok,value=pcall(function() return v:GetParamValue(p) end)
                local x=node(name,value,pg)
                if not ok then x.warning=true end
                add(pg,x)
            else warning(pg,"GetParamValue unavailable for "..name) end
        end
        if type(paramCount)=="number" and paramCount~=#ks then warning(pg,"Entry count differs from paramCount") end
        add(n,pg)
        if #definitions.children>0 then add(advanced,definitions) end
    elseif params~=nil then
        add(n,node("params",params,n)); warning(n,"params is not an enumerable table")
    elseif paramValues then
        -- Struct gives [ [ParamType, value], ... ] instead of params.
        local pg=group("params",n)
        pg.open = true
        for i,pair in ipairs(paramValues) do
            if i>limit then warning(pg,"Remaining parameters omitted"); break end
            local okType,p=get(pair,1)
            local okValue,value=get(pair,2)
            local x=node(okType and parameterName(p) or "Unreadable param "..i,value,pg)
            if not (okType and okValue) then x.warning=true end
            add(pg,x)
        end
        add(n,pg)
        paramValues=nil
    elseif type(paramCount)=="number" and paramCount>0 then warning(n,"No readable params member") end
    if paramValues then add(n,node("paramValues",paramValues,n)) end
    -- DBRow and DBTable give their data only through column methods (1-indexed).
    local okCount,columnCount=get(v,"columnCount")
    if okCount and type(columnCount)=="number" and columnCount>0 then
        local cg=group("columns",n)
        cg.open = true
        for c=1,math.min(columnCount,limit) do
            local column={}
            for key,method in pairs({types="GetColumnValueTypes",values="GetColumnValues",
                hasDefaults="GetColumnHasDefaultValues",defaults="GetColumnDefaultValues"}) do
                local okMethod,fn=get(v,method)
                if okMethod and fn~=nil then
                    local ok,result=pcall(function() return fn(v,c) end)
                    if ok then column[key]=result else column[key]="error: "..str(result) end
                end
            end
            add(cg,node(c,column,cg))
        end
        add(n,cg)
    end
    local mt=meta(v)
    if mt and rawget(mt,"__type")~=nil then add(advanced,node("__type",rawget(mt,"__type"),advanced)) end
    if #advanced.children>0 then add(n,advanced) end
end
local function valueText(n)
    if n.group then return "" end
    if n.cycle then return " : "..str(n.value).." [ancestor reference]" end
    local t=type(n.value)
    if t=="string" then return " : "..string.format("%q",n.value) end
    if t=="function" then return " : function (not called)" end
    if t=="table" then return "" end
    if t=="userdata" then return " : "..str(n.value) end
    return " : "..str(n.value)
end
local function render()
    if not list then return end
    local entries={}
    visible={}
    local terms={}
    for term in search:lower():gmatch("%S+") do terms[#terms+1]=term end
    local function matches(n,path)
        local hay=(path.." "..valueText(n).." "..type(n.value)):lower()
        for _,term in ipairs(terms) do if not hay:find(term,1,true) then return false end end
        return true
    end
    local function include(n,path)
        if #terms==0 or matches(n,path) then return true end
        for _,c in ipairs(n.children or {}) do
            if include(c,path.."."..c.name) then return true end
        end
        return false
    end
    local truncated=false
    local function walk(n,depth,path)
        if not include(n,path) then return end
        if #entries>=MAX_VISIBLE then truncated=true; return end
        local count=n.children and " {"..#n.children.."}" or " {...}"
        local marker=n.branch and (n.open and "v " or "> ") or "  "
        local label=string.rep("    ",depth)..marker..n.name..valueText(n)
        if n.branch then label=label..count end
        local index=#entries+1
        visible[index]={node=n,depth=depth,path=path}
        entries[index]={id=index,label=label:gsub("[\r\n]"," "),
            textColour=n.warning and 0xFF9988FF or n.branch and 0xAFCFEFFF
                or type(n.value)=="number" and 0x91D9FFFF
                or type(n.value)=="string" and 0xB8D899FF or 0xE5E5E5FF}
        if n.branch and (n.open or #terms>0) then
            for _,c in ipairs(n.children or {}) do walk(c,depth+1,path.."."..c.name) end
        end
    end
    if root then walk(root,0,root.name) end
    rendering=true
    list:SetEntries(entries)
    rendering=false
    status.content=str(#entries).." visible rows"
        ..(truncated and " | WARNING: visible-row limit reached" or "")
        ..(#terms>0 and " | Search covers loaded branches only" or " | Click a branch to expand or collapse")
end
-- Config kinds to export. A kind with no lastID is scanned until
-- MISS_LIMIT IDs in a row are missing. skip lists members to leave out.
local EXPORT_KINDS = {
    { name = "Obj", lastID = 64356, lookup = function() return config.Obj end },
    { name = "Param", lookup = function() return config.Param end },
    { name = "Struct", lookup = function() return config.Struct end },
    { name = "Quest", lookup = function() return config.Quest end },
    { name = "Enum", lookup = function() return config.Enum end },
    -- value is the character's live state, not config data.
    { name = "VarPlayer", lookup = function() return var.VarPlayer end, skip = { value = true } },
    -- Discovery only. ADR 0001 rejects DBRow data in the plugin.
    { name = "DBTable", lookup = function() return config.DBTable end },
    { name = "DBRow", lookup = function() return config.DBRow end },
}
local MISS_LIMIT = 10000
local MAX_SCAN_ID = 1000000

local function findKind(name)
    for _, kind in ipairs(EXPORT_KINDS) do
        if kind.name:lower() == name:lower() then
            return kind
        end
    end
end

local function lookupConfig(kind, idNumber)
    local okSource, source = pcall(kind.lookup)
    local okFind, fromID = get(source, "FromID")

    -- FromID is not always a plain Lua function, so only check that it exists.
    if not okSource or source == nil or not okFind or fromID == nil then
        error(
            kind.name .. ".FromID is unavailable (source: "
            .. type(source) .. ", FromID: " .. type(fromID) .. ")"
        )
    end

    local ok, cfg = pcall(function() return source.FromID(idNumber) end)

    if not ok then
        return nil
    end

    return cfg
end

local function load(value)
    local kindName, idText = tostring(value):match("^%s*(%a+)%s+(%-?%d+)%s*$")
    local kind = findKind(kindName or "Obj")
    local idNumber=tonumber(idText or value)
    if not kind then status.content="Unknown kind: "..str(kindName); return end
    if not idNumber or idNumber%1~=0 then status.content="Enter an ID, or a kind and an ID (Struct 43263)"; return end
    local ok,obj=pcall(lookupConfig,kind,idNumber)
    if not ok or obj==nil then status.content="Lookup failed: "..str(obj); return end
    root=node(kind.name.." "..str(idNumber),obj,nil)
    populate(root,0); root.open=true
    detail.content = "Click a value to see its full text. References expand in place."

    pending = nil
    dirty = false

    render()

    if jsonBox then
        updateJSONBox()
    end
end
local function jsonQuote(value)
    local escaped = tostring(value):gsub('[%z\1-\31\\"]', function(c)
        if c == '"' then
            return '\\"'
        elseif c == "\\" then
            return "\\\\"
        end

        return string.format("\\u%04x", string.byte(c))
    end)

    return '"' .. escaped .. '"'
end

local function jsonScalar(value)
    local kind = type(value)

    if kind == "nil" then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        if value ~= value
            or value == math.huge
            or value == -math.huge then
            return '{"$type":"number","$value":'
                .. jsonQuote(str(value)) .. '}'
        end

        return tostring(value)
    elseif kind == "string" then
        return jsonQuote(value)
    end

    -- JSON cannot directly represent functions or other Lua values.
    return '{"$type":' .. jsonQuote(kind)
        .. ',"$label":' .. jsonQuote(str(value)) .. '}'
end

local function exportVisibleJSON(
    suppliedRoot,
    suppliedRows,
    suppliedSearch,
    suppliedMode
)
    local currentSearch = search

    local root = suppliedRoot or root
    local visible = suppliedRows or visible
    local search = suppliedSearch

    if search == nil then
        search = currentSearch
    end
    if not root or #visible == 0 then
        return nil, "There is no displayed object to export."
    end

    local shown = {}
    local children = {}
    local warnings = {}
    local truncated = false

    local function addWarning(message)
        warnings[#warnings + 1] = message
    end

    local function objectJSON(fields)
        return "{" .. table.concat(fields, ",") .. "}"
    end

    local function field(name, encodedValue)
        return jsonQuote(name) .. ":" .. encodedValue
    end

    local function stringArrayJSON(values)
        local encoded = {}

        for _, value in ipairs(values) do
            encoded[#encoded + 1] = jsonQuote(value)
        end

        return "[" .. table.concat(encoded, ",") .. "]"
    end

    local function isLimitWarning(message)
        message = message:lower()

        return message:find("limit", 1, true) ~= nil
            or message:find("omitted", 1, true) ~= nil
    end

    -- Record exactly which rows the current render included.
    for _, row in ipairs(visible) do
        local n = row.node

        shown[n] = true
        children[n] = {}

        if n.warning then
            local message = row.path .. ": " .. str(n.value)

            addWarning(message)

            if isLimitWarning(str(n.value)) then
                truncated = true
            end
        end
    end

    for _, row in ipairs(visible) do
        local n = row.node

        if n.parent and shown[n.parent] then
            local siblings = children[n.parent]
            siblings[#siblings + 1] = n
        end
    end

    -- Check whether MAX_VISIBLE prevented otherwise eligible rows
    -- from appearing. This mirrors render()'s filtering behaviour.
    local terms = {}

    for term in search:lower():gmatch("%S+") do
        terms[#terms + 1] = term
    end

    local function matches(n, path)
        local haystack = (
            path .. " " .. valueText(n) .. " " .. type(n.value)
        ):lower()

        for _, term in ipairs(terms) do
            if not haystack:find(term, 1, true) then
                return false
            end
        end

        return true
    end

    local function included(n, path)
        if #terms == 0 or matches(n, path) then
            return true
        end

        for _, child in ipairs(n.children or {}) do
            if included(child, path .. "." .. child.name) then
                return true
            end
        end

        return false
    end

    local displayWasCutOff = false

    local function checkDisplayed(n, path)
        if not included(n, path) then
            return
        end

        if not shown[n] then
            displayWasCutOff = true
            return
        end

        if n.branch and (n.open or #terms > 0) then
            for _, child in ipairs(n.children or {}) do
                checkDisplayed(child, path .. "." .. child.name)
            end
        end
    end

    checkDisplayed(root, root.name)

    if displayWasCutOff then
        truncated = true
        addWarning(
            "The visible-row limit excluded part of the matching tree."
        )
    end

    -- Preserve config identity independently of visible properties.
    local function referenceIdentityJSON(value)
        local identityFields = {}
        local foundIdentity = false

        for _, key in ipairs({"typeName", "id", "configName"}) do
            local ok, result = get(value, key)

            if ok and (
                type(result) == "string"
                or type(result) == "number"
            ) then
                identityFields[#identityFields + 1] =
                    field(key, jsonScalar(result))

                if key == "id" then
                    foundIdentity = true
                end
            end
        end

        if not foundIdentity then
            return nil
        end

        return objectJSON(identityFields)
    end

    local function ancestorReferenceJSON(n)
        local identity = referenceIdentityJSON(n.value)
        local fields = {
            field("$state", jsonQuote("ancestor-reference"))
        }

        if identity then
            fields[#fields + 1] = field("$ref", identity)
        else
            fields[#fields + 1] =
                field("$type", jsonQuote(type(n.value)))
        end

        return objectJSON(fields)
    end

    local encodeNode
    local encodeChildren

    -- Inspector-generated groups are kept separate from Obj data.
    encodeChildren = function(n)
        local properties = {}
        local inspector = {}

        for _, child in ipairs(children[n] or {}) do
            local encoded = field(child.name, encodeNode(child))

            if child.warning then
                -- Already recorded in export.warnings.
                -- Do not pretend a diagnostic is a game property.
            elseif child.group and not DATA_GROUPS[child.name] then
                inspector[#inspector + 1] = encoded
            else
                properties[#properties + 1] = encoded
            end
        end

        return objectJSON(properties),
            #inspector > 0 and objectJSON(inspector) or nil
    end

    encodeNode = function(n)
        if n.cycle then
            return ancestorReferenceJSON(n)
        end

        local kind = type(n.value)

        if not n.branch then
            if kind == "function" then
                return '{"$type":"function","$state":"not-called"}'
            end

            -- Avoid addresses in unexpected opaque values.
            if kind == "userdata" or kind == "thread" then
                return objectJSON({
                    field("$type", jsonQuote(kind)),
                    field("$state", jsonQuote("opaque"))
                })
            end

            return jsonScalar(n.value)
        end

        local expanded = n.open or search ~= ""

        if not expanded or not n.children then
            local stateName = not expanded
                and "unexpanded"
                or "not-loaded"

            local fields = {
                field("$state", jsonQuote(stateName))
            }

            if not n.group then
                fields[#fields + 1] =
                    field("$type", jsonQuote(kind))

                if kind == "userdata" then
                    local identity = referenceIdentityJSON(n.value)

                    if identity then
                        fields[#fields + 1] = field("$ref", identity)
                    end
                end
            end

            return objectJSON(fields)
        end

        local properties, inspector = encodeChildren(n)

        if kind == "userdata" then
            local fields = {}
            local identity = referenceIdentityJSON(n.value)

            if identity then
                fields[#fields + 1] = field("$ref", identity)
            else
                fields[#fields + 1] =
                    field("$type", jsonQuote("userdata"))
            end

            fields[#fields + 1] =
                field("$state", jsonQuote("expanded"))

            fields[#fields + 1] =
                field("properties", properties)

            if inspector then
                fields[#fields + 1] =
                    field("$inspector", inspector)
            end

            return objectJSON(fields)
        end

        -- Ordinary tables and the params grouping stay simple.
        -- Lua indices are preserved as JSON object keys.
        if inspector then
            -- This is normally only relevant to synthetic groups.
            return objectJSON({
                field("$state", jsonQuote("expanded")),
                field("properties", properties),
                field("$inspector", inspector)
            })
        end

        return properties
    end

    local objectData
    local inspectorData

    if root.open or search ~= "" then
        objectData, inspectorData = encodeChildren(root)
    else
        objectData = encodeNode(root)
    end

    local exportFields = {
        field("schemaVersion", "1"),
        field("mode", jsonQuote(suppliedMode or "visible-tree")),
        field("search", jsonQuote(search)),
        field("filtered", search ~= "" and "true" or "false"),
        field("truncated", truncated and "true" or "false"),
        field("warnings", stringArrayJSON(warnings))
    }

    local output = {
        field("object", objectData),
        field("export", objectJSON(exportFields))
    }

    if inspectorData then
        output[#output + 1] =
            field("inspector", inspectorData)
    end

    return objectJSON(output)
end

updateJSONBox = function()
    -- Process any queued expansion before taking the snapshot.
    -- Otherwise the button could capture the previous tree state.
    if pending or dirty then
        status.content =
            "Tree update pending. Click Update JSON again after it refreshes."
        return
    end

    local ok, result, message = pcall(exportVisibleJSON)

    if not ok then
        status.content = "JSON export failed: " .. str(result)
        return
    end

    if not result then
        status.content = message
        return
    end

    -- Avoid silently putting a truncated, invalid document in the box.
    if #result > 1000000 then
        status.content =
            "JSON exceeds the export-box limit. Collapse some branches."
        return
    end

    jsonBox:SetText(result, false)

    status.content = "JSON snapshot ready: "
        .. tostring(#result)
        .. " bytes. Click the JSON box to select and copy its contents."
end
local BULK_EVENT_KEY = KEY .. "-bulk-export"
local BULK_IDS_PER_TICK = 5
local bulkJob = nil

local function stopBulkExport(message)
    Event.Logic.Unsubscribe(BULK_EVENT_KEY)
    bulkJob = nil

    if status then
        status.content = message
    end
end

-- Enum values and other plain tables can be far larger than the UI limits.
local EXPORT_CHILD_LIMIT = 100000
local EXPORT_ROW_LIMIT = 200000

local function collectExportRows(exportRoot)
    local rows = {}
    local reachedLimit = false

    local function walk(n, depth, path)
        if #rows >= EXPORT_ROW_LIMIT then
            reachedLimit = true
            return
        end

        rows[#rows + 1] = {
            node = n,
            depth = depth,
            path = path
        }

        if n.branch and n.open then
            for _, child in ipairs(n.children or {}) do
                walk(
                    child,
                    depth + 1,
                    path .. "." .. child.name
                )
            end
        end
    end

    walk(exportRoot, 0, exportRoot.name)

    return rows, reachedLimit
end

-- Open params and plain tables, for example Enum values and op names.
-- Referenced configs stay closed, so they export as a $ref only.
local function openForExport(n, depth)
    for _, child in ipairs(n.children or {}) do
        if child.group and not DATA_GROUPS[child.name] then
            child.open = false
        elseif child.branch
            and (child.group or type(child.value) == "table") then

            populate(child, depth + 1, EXPORT_CHILD_LIMIT)
            child.open = true
            openForExport(child, depth + 1)
        else
            child.open = false
        end
    end
end

local function exportOneConfig(kind, idNumber)
    local cfg = lookupConfig(kind, idNumber)

    if cfg == nil then
        return nil, "FromID gave nil"
    end

    local validityRead, valid = get(cfg, "isValid")

    if kind.name == "Obj" then
        if not validityRead then
            error("Could not read isValid")
        end

        -- Do not count an unverifiable proxy as an existing object.
        if valid ~= true then
            return nil, "invalid"
        end
    elseif validityRead and valid == false then
        return nil, "isValid is false"
    end

    local identityRead, returnedID = get(cfg, "id")

    if not identityRead or returnedID ~= idNumber then
        if kind.name == "Obj" then
            error("Lookup returned an unexpected object ID")
        end

        return nil, "id is " .. str(returnedID)
    end

    -- The docs do not say what FromID gives for an unused ID.
    -- Treat a config without a name as missing, except a DBRow with columns:
    -- a DBRow can perhaps have no name.
    local nameRead, configName = get(cfg, "configName")
    local countRead, columnCount = get(cfg, "columnCount")
    local hasColumns = countRead and type(columnCount) == "number" and columnCount > 0

    if kind.name ~= "Obj"
        and not (kind.name == "DBRow" and hasColumns)
        and (not nameRead or configName == nil or configName == "") then
        return nil, "configName is " .. str(configName)
    end

    local exportRoot = node(
        kind.name .. " " .. tostring(idNumber),
        cfg,
        nil
    )

    populate(exportRoot, 0, EXPORT_CHILD_LIMIT)
    exportRoot.open = true

    if kind.skip then
        local kept = {}

        for _, child in ipairs(exportRoot.children) do
            if not kind.skip[child.name] then
                kept[#kept + 1] = child
            end
        end

        exportRoot.children = kept
    end

    openForExport(exportRoot, 0)

    local exportRows, limited = collectExportRows(exportRoot)

    if limited then
        error(kind.name .. " exceeded the export row limit")
    end

    local result, err = exportVisibleJSON(
        exportRoot,
        exportRows,
        "",
        "bulk-top-level"
    )

    if not result then
        error(err or "JSON encoding failed")
    end

    -- The receiver stores each kind separately.
    return '{"kind":' .. jsonQuote(kind.name) .. "," .. result:sub(2)
end

local RECEIVER_TOKEN = "PASTE_TOKEN_FROM_PYTHON_HERE"

local HTTP_EXPORT_KEY = KEY .. "-http-export"
local HTTP_BATCH_SIZE = 500
-- Exported configs per tick, and lookups per tick (missing IDs are cheap).
local HTTP_SCAN_PER_TICK = 50
local HTTP_LOOKUPS_PER_TICK = 2000

-- Stay below the receiver's 4 MiB request limit.
local HTTP_MAX_BODY_BYTES = 3 * 1024 * 1024

local networkJob = nil

local function networkStatus(job, message)
    local kind = job.kinds[job.kindIndex]

    status.content =
        message
        .. " | Kind: " .. (kind and kind.name or "done")
        .. " (" .. tostring(job.kindIndex) .. "/" .. tostring(#job.kinds) .. ")"
        .. " | Next ID: " .. tostring(job.nextID)
        .. " | Scanned: " .. tostring(job.scanned)
        .. " | Acknowledged: " .. tostring(job.sent)
        .. " | Invalid/missing: " .. tostring(job.skipped)
        .. " | Errors: " .. tostring(job.errors)
end

local function stopNetworkExport(job, message)
    if networkJob ~= job then
        return
    end

    networkJob = nil
    Event.Logic.Unsubscribe(HTTP_EXPORT_KEY)

    local request = job.request
    job.request = nil

    if request then
        pcall(function()
            if not request.finished then
                request:Cancel()
            end
        end)
    end

    networkStatus(job, message)
end

local function sendNetworkBatch(job, finish)
    local body = finish
        and "{}"
        or "[" .. table.concat(job.parts, ",") .. "]"

    if #body > HTTP_MAX_BODY_BYTES then
        stopNetworkExport(
            job,
            "Stopped: batch exceeds HTTP body limit"
        )
        return
    end

    local count = #job.parts
    local path = finish and "/finish" or "/batch"

    job.waiting = true

    local ok, err = pcall(function()
        local request = HTTPRequest.new(
            Plugin.urls.exportReceiver,
            path
        )

        job.request = request

        request:AddHeader(
            "Authorization",
            "Bearer " .. RECEIVER_TOKEN
        )

        request:AddHeader(
            "Content-Type",
            "application/json"
        )

        request:Post(body, function(response)
            -- Ignore callbacks from cancelled or superseded jobs.
            if networkJob ~= job then
                return
            end

            job.request = nil

            local code = response.responseCode

            if not response.successful
                or code < 200
                or code >= 300 then

                local message =
                    "HTTP export stopped: response "
                    .. tostring(code)
                    .. " "
                    .. tostring(response.data)

                if response.timedOut then
                    message = "HTTP export stopped: timeout"
                elseif response.failed then
                    message =
                        "HTTP export stopped: "
                        .. tostring(response.errorInfo)
                end

                stopNetworkExport(job, message)
                return
            end

            if finish then
                stopNetworkExport(
                    job,
                    job.errors == 0
                        and "File export complete"
                        or "File written, but some IDs had export errors"
                )

                log(
                    "[Object HTTP export] Receiver response: "
                    .. tostring(response.data)
                )
                return
            end

            job.sent = job.sent + count
            job.parts = {}
            job.batchBytes = 2
            job.waiting = false

            networkStatus(job, "Batch acknowledged")
        end)
    end)

    if not ok then
        stopNetworkExport(
            job,
            "Could not send HTTP request: " .. str(err)
        )
    end
end

local function kindFinished(job, kind)
    if kind.lastID then
        return job.nextID > kind.lastID
    end

    return job.misses >= MISS_LIMIT or job.nextID > MAX_SCAN_ID
end

-- Adds one encoded config to the batch. Gives false if the batch is full.
local function addToBatch(job, encoded, label)
    local extra = #encoded + (#job.parts > 0 and 1 or 0)

    if job.batchBytes + extra > HTTP_MAX_BODY_BYTES then
        if #job.parts == 0 then
            error(label .. " is larger than the HTTP body limit")
        end

        return false
    end

    job.parts[#job.parts + 1] = encoded
    job.batchBytes = job.batchBytes + extra
    return true
end

local function startNetworkExport(kinds)
    if networkJob then
        status.content = "An HTTP export is already running."
        return
    end

    if RECEIVER_TOKEN == "PASTE_TOKEN_FROM_PYTHON_HERE" then
        status.content = "Set RECEIVER_TOKEN in the script first."
        return
    end

    if not Plugin.HasPermission(
        PluginPermissions.httpAccess
    ) then
        status.content = "HTTP permission is unavailable."
        return
    end

    local job = {
        kinds = kinds,
        kindIndex = 1,
        nextID = 0,
        misses = 0,
        scanned = 0,
        sent = 0,
        skipped = 0,
        errors = 0,
        parts = {},
        carry = nil,
        batchBytes = 2,
        waiting = false,
        request = nil
    }

    networkJob = job

    Event.Logic.Subscribe(HTTP_EXPORT_KEY, function()
        if networkJob ~= job or job.waiting then
            return
        end

        local ok, err = pcall(function()
            -- A config that did not fit the last batch goes first.
            if job.carry then
                addToBatch(job, job.carry, "A carried config")
                job.carry = nil
            end

            local exportsThisTick, lookupsThisTick = 0, 0
            local batchFull = false

            while not batchFull
                and exportsThisTick < HTTP_SCAN_PER_TICK
                and lookupsThisTick < HTTP_LOOKUPS_PER_TICK
                and #job.parts < HTTP_BATCH_SIZE do

                local kind = job.kinds[job.kindIndex]

                if kind == nil then
                    break
                end

                if kindFinished(job, kind) then
                    log(
                        "[Config HTTP export] "
                        .. kind.name
                        .. " done at ID "
                        .. tostring(job.nextID - 1)
                    )
                    job.kindIndex = job.kindIndex + 1
                    job.nextID = 0
                    job.misses = 0
                else
                    local configID = job.nextID
                    job.nextID = configID + 1
                    job.scanned = job.scanned + 1
                    lookupsThisTick = lookupsThisTick + 1

                    local exported, encoded, reason = pcall(
                        exportOneConfig,
                        kind,
                        configID
                    )
                    local label = kind.name .. " " .. tostring(configID)

                    if not exported then
                        job.errors = job.errors + 1
                        job.misses = 0

                        if job.errors <= 20 then
                            log("[Config HTTP export] " .. label .. ": " .. str(encoded))
                        end

                        if str(encoded):find("FromID is unavailable", 1, true) then
                            -- Skip the kind; every ID would fail the same way.
                            job.nextID = math.huge
                        end
                    elseif encoded == nil then
                        job.skipped = job.skipped + 1
                        job.misses = job.misses + 1

                        -- Show why the first IDs of each kind are skipped.
                        if configID < 5 or (kind.name == "DBRow" and configID == 487) then
                            log("[Config HTTP export] " .. label .. " skipped: " .. str(reason))
                        end
                    else
                        job.misses = 0
                        exportsThisTick = exportsThisTick + 1

                        if not addToBatch(job, encoded, label) then
                            job.carry = encoded
                            batchFull = true
                        end
                    end
                end
            end

            networkStatus(job, "Scanning")

            if batchFull or #job.parts >= HTTP_BATCH_SIZE then
                sendNetworkBatch(job, false)

            elseif job.kindIndex > #job.kinds then
                if #job.parts > 0 then
                    sendNetworkBatch(job, false)
                else
                    -- All data batches have been acknowledged.
                    sendNetworkBatch(job, true)
                end
            end
        end)

        if not ok then
            stopNetworkExport(
                job,
                "HTTP export stopped: " .. str(err)
            )
        end
    end)

    networkStatus(job, "HTTP export started")
end

local function cancelNetworkExport()
    if networkJob then
        stopNetworkExport(
            networkJob,
            "Export cancelled; acknowledged batches remain in SQLite"
        )
    end
end

local function mount(parent)
    window=prettyui.Window.new(parent,{title="Object tree inspector",x=-360,y=-310,xAnchor=0.5,yAnchor=0.5,
        width=720,height=700,resizable=true,minWidth=450,minHeight=400,scrollable=true})
    idField=window:AddTextField({text="3030",placeholder="Obj ID, or a kind and an ID (Struct 43263)",onSubmit=function(_,v) load(v) end})
    window:AddSimpleButton("Load",function() load(idField:GetText()) end)
    window:AddSimpleButton("Refresh",function() load(idField:GetText()) end,{inline=true})
    window:AddSimpleButton("Collapse branches",function()
        local function close(n)
            n.open=false
            for _,c in ipairs(n.children or {}) do close(c) end
        end
        if root then close(root); root.open=true; render() end
    end,{inline=true})
    window:AddTextField({placeholder="Search loaded properties and values",onChange=function(_,_,v)
        search=v or ""; dirty=true
    end})
    status=window:AddText("Loading...")
    list=window:AddList({height=370,maxSelected=1,entries={},onChange=function(_,index,selected)
        if rendering or not selected then return end
        local row=visible[index]
        if row then pending=row end
    end})
    detail = window:AddText("Select a row")

    window:AddSimpleButton("Update JSON", updateJSONBox)

    jsonBox = window:AddTextField({
        text = "",
        placeholder = "JSON export",
        maxLength = MAX_BULK_JSON_BYTES
    })

    window:AddSimpleButton(
        "Export all kinds to localhost",
        function() startNetworkExport(EXPORT_KINDS) end
    )

    window:AddSimpleButton(
        "Cancel HTTP export",
        cancelNetworkExport,
        {inline = true}
    )

    for i, kind in ipairs(EXPORT_KINDS) do
        window:AddSimpleButton(
            "Export " .. kind.name,
            function() startNetworkExport({ kind }) end,
            {inline = (i % 4) > 1}
        )
    end

    window:Show()
    load("3030")
end
Event.Logic.Subscribe(KEY,function()
    if not started then
        local ok,parent=pcall(function() return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) end)
        if ok and parent then
            started=true
            local success,err=pcall(function() mount(parent) end)
            if not success then log("[Object tree] UI startup failed: "..str(err)) end
        end
    end
    if pending then
        local row=pending; pending=nil
        local ok,err=pcall(function()
            local n=row.node
            detail.content=row.path.."\n"..(n.group and "Group" or type(n.value).." : "..str(n.value))
            if n.branch then populate(n,row.depth); n.open=not n.open end
            dirty=true
        end)
        if not ok then status.content="Expansion failed: "..str(err) end
    end
    if dirty then
        dirty=false
        local ok,err=pcall(render)
        if not ok then log("[Object tree] Render failed: "..str(err)) end
    end
end)
function PluginShutdown()
    cancelNetworkExport()
    Event.Logic.Unsubscribe(HTTP_EXPORT_KEY)
    Event.Logic.Unsubscribe(BULK_EVENT_KEY)
    bulkJob = nil
    Event.Logic.Unsubscribe(KEY)
    if window then window:Destroy(); window=nil end
    root,pending=nil,nil
    visible={}
end
