-- Runs every tests/test_*.lua. Usage, from the repository root:  luajit tests/run.lua
local root = arg[0]:match("^(.*)/tests/run%.lua$") or "."
package.path = table.concat({
    root .. "/mascot.koplugin/?.lua",
    root .. "/tests/?.lua",
    package.path,
}, ";")

local T = require("lib")

local listing = io.popen('ls "' .. root .. '/tests"')
local files = {}
for name in listing:lines() do
    if name:match("^test_.*%.lua$") then files[#files + 1] = name end
end
listing:close()
table.sort(files)

for _, file in ipairs(files) do
    local ok, err = pcall(dofile, root .. "/tests/" .. file)
    if not ok then
        T.failed = T.failed + 1
        T.failures[#T.failures + 1] = file .. " (failed to load)\n    " .. tostring(err)
    end
end

for _, failure in ipairs(T.failures) do print("FAIL " .. failure) end
print(string.format("%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
