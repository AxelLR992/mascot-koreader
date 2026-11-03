-- Minimal test helpers: plain Lua, no dependencies.
local T = { passed = 0, failed = 0, failures = {} }

local function show(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. show(value[key]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not equal(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

--- Assert deep equality.
function T.eq(actual, expected, message)
    if not equal(actual, expected) then
        error(string.format("%sexpected %s, got %s", message and (message .. ": ") or "", show(expected), show(actual)), 2)
    end
end

--- Assert that `fn` raises an error whose message contains `fragment`.
function T.throws(fn, fragment)
    local ok, err = pcall(fn)
    if ok then error("expected an error, got none", 2) end
    if fragment and not tostring(err):find(fragment, 1, true) then
        error(string.format("expected error containing %q, got %q", fragment, tostring(err)), 2)
    end
end

--- Register and run one test.
function T.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = name .. "\n    " .. tostring(err)
    end
end

return T
