--[[--
Phase 0 spike for Mascot. Throwaway: checks, on a real device, the assumptions the plan relies on.

  1. environment        device, screen, memory, TLS, other plugins
  2. page text          can we read the text of the current page, and how long does it take
  3. settings           does state survive a restart
  4. HTTPS              can we make a request without blocking the UI
  5. sprite             can we draw a small PNG, scaled by an integer factor
  6. events             do page / suspend / resume events reach the plugin

Everything is under Tools > Mascot spike. "Report" shows the results of all checks.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Version = require("version")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local lfs = require("libs/libkoreader-lfs")
local socketutil = require("socketutil")
local time = require("ui/time")
local _ = require("gettext")

local Screen = Device.screen
local HTTPS_URL = "https://example.com/"
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local Spike = WidgetContainer:extend{
    name = "mascotspike",
    is_doc_only = false,
}

function Spike:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/mascot-spike.lua")
    self.settings:saveSetting("launches", self.settings:readSetting("launches", 0) + 1)
    self.settings:flush()
    self.results = {}
    self.events = { page = 0, suspend = 0, resume = 0, ready = 0, close = 0 }
    self.samples = {}  -- per-page text extraction: { ms, chars }
    self.ui.menu:registerToMainMenu(self)
end

-- Menu ----------------------------------------------------------------------------------------

function Spike:addToMainMenu(menu_items)
    menu_items.mascotspike = {
        text = _("Mascot spike"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text = _("1. Report (all results)"), keep_menu_open = true, callback = function() self:showReport() end },
            { text = _("2. Read current page text"), keep_menu_open = true, callback = function() self:checkPageText() end },
            { text = _("3. Settings persistence"), keep_menu_open = true, callback = function() self:checkSettings() end },
            { text = _("4. HTTPS request (non-blocking)"), keep_menu_open = true, callback = function() self:checkHttps() end },
            { text = _("5. Draw sprite"), callback = function() self:checkSprite() end },
            { text = _("Reset counters"), keep_menu_open = true, callback = function() self:reset() end },
        },
    }
end

function Spike:show(text)
    UIManager:show(TextViewer:new{ title = _("Mascot spike"), text = text, width = Screen:getWidth() * 0.9,
                                   height = Screen:getHeight() * 0.8 })
end

-- 1. Environment ------------------------------------------------------------------------------

local function memAvailableKb()
    local f = io.open("/proc/meminfo", "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return tonumber(text:match("MemAvailable:%s*(%d+)")), tonumber(text:match("MemTotal:%s*(%d+)"))
end

function Spike:environment()
    local avail, total = memAvailableKb()
    local plugins_dir = PLUGIN_DIR:match("^(.*)/[^/]*$") or "."
    local function has(name) return lfs.attributes(plugins_dir .. "/" .. name .. ".koplugin", "mode") == "directory" end
    local has_ssl = pcall(require, "ssl.https")
    return {
        string.format("KOReader: %s", Version:getShortVersion()),
        string.format("Device: %s (kindle=%s kobo=%s emulator=%s)", tostring(Device.model),
            tostring(Device:isKindle()), tostring(Device:isKobo()), tostring(Device:isEmulator())),
        string.format("Screen: %dx%d, %d dpi", Screen:getWidth(), Screen:getHeight(), Screen:getDPI()),
        string.format("LuaJIT: %s %s", jit.version, jit.arch),
        string.format("RAM available: %s of %s MB", avail and math.floor(avail / 1024) or "?",
            total and math.floor(total / 1024) or "?"),
        string.format("Lua heap: %d KB", math.floor(collectgarbage("count"))),
        string.format("TLS (ssl.https) loadable: %s", tostring(has_ssl)),
        string.format("Plugin dir: %s", PLUGIN_DIR),
        string.format("Settings dir: %s", DataStorage:getSettingsDir()),
        string.format("Simple UI installed: %s", tostring(has("simpleui"))),
        string.format("Bookshelf installed: %s", tostring(has("bookshelf"))),
    }
end

-- 2. Page text --------------------------------------------------------------------------------

--- Text of the page on screen, or nil plus the reason.
function Spike:pageText()
    local doc = self.ui and self.ui.document
    if not doc then return nil, "no book open" end
    if self.ui.rolling then
        local res = doc:getTextFromPositions({ x = 0, y = 0 }, { x = Screen:getWidth(), y = Screen:getHeight() }, true)
        return res and res.text or "", nil
    end
    local words = {}
    for _, line in ipairs(doc:getTextBoxes(self.ui:getCurrentPage()) or {}) do
        for _, box in ipairs(line) do
            if box.word then words[#words + 1] = box.word end
        end
    end
    return table.concat(words, " "), nil
end

function Spike:checkPageText()
    local t0 = time.now()
    local ok, text, err = pcall(self.pageText, self)
    local ms = time.to_ms(time.since(t0))
    local result
    if not ok then
        result = "ERROR: " .. tostring(text)
    elseif not text then
        result = "n/a: " .. tostring(err)
    else
        local kind = self.ui.rolling and "reflowable (crengine)" or "paged (PDF/DjVu)"
        result = string.format("%s, %d chars in %.1f ms\n\"%s\"", kind, #text, ms, text:sub(1, 160):gsub("%s+", " "))
    end
    self.results.page_text = result
    self:show(result)
end

--- Average cost of text extraction over the last page turns.
function Spike:sampleSummary()
    if #self.samples == 0 then return "no page turns sampled yet" end
    local sum_ms, sum_chars = 0, 0
    for _, s in ipairs(self.samples) do sum_ms = sum_ms + s[1]; sum_chars = sum_chars + s[2] end
    return string.format("%d page turns sampled: %.1f ms and %d chars on average", #self.samples,
        sum_ms / #self.samples, sum_chars / #self.samples)
end

-- 3. Settings ---------------------------------------------------------------------------------

function Spike:checkSettings()
    local launches = self.settings:readSetting("launches", 0)
    local result = string.format("launches recorded: %d (should grow by 1 after every KOReader restart)\nfile: %s",
        launches, DataStorage:getSettingsDir() .. "/mascot-spike.lua")
    self.results.settings = result
    self:show(result)
end

function Spike:reset()
    self.settings:saveSetting("launches", 1)
    self.settings:flush()
    self.samples, self.results = {}, {}
    UIManager:show(InfoMessage:new{ text = _("Counters reset."), timeout = 2 })
end

-- 4. HTTPS ------------------------------------------------------------------------------------

function Spike:checkHttps()
    NetworkMgr:runWhenOnline(function()
        local ticks, running = 0, true
        local function tick()
            if running then
                ticks = ticks + 1
                UIManager:scheduleIn(0.2, tick)
            end
        end
        tick()
        UIManager:show(InfoMessage:new{ text = _("Requesting ") .. HTTPS_URL, timeout = 2 })
        Trapper:wrap(function()
            local t0 = time.now()
            local completed, answer = Trapper:dismissableRunInSubprocess(function()
                local https = require("ssl.https")
                local sink = {}
                socketutil:set_timeout(8, 15)
                local body, code = https.request{ url = HTTPS_URL, method = "GET", sink = socketutil.table_sink(sink) }
                socketutil:reset_timeout()
                return string.format("%s|%s|%d", tostring(body ~= nil), tostring(code), #table.concat(sink))
            end, nil, true)
            running = false
            local ms = time.to_ms(time.since(t0))
            local result
            if not completed then
                result = "dismissed before finishing"
            else
                local ok, code, len = tostring(answer):match("^(.-)|(.-)|(.-)$")
                result = string.format("ok=%s code=%s bytes=%s in %.0f ms\nUI loop ran %d ticks of 200 ms while waiting "
                    .. "(about %.0f expected if it never blocked)", tostring(ok), tostring(code), tostring(len), ms,
                    ticks, ms / 200)
            end
            self.results.https = result
            self:show(result)
        end)
    end)
end

-- 5. Sprite -----------------------------------------------------------------------------------

local SpriteView = InputContainer:extend{ file = nil, factor = 8 }

function SpriteView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self[1] = CenterContainer:new{
        dimen = self.dimen,
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE, bordersize = 0,
            ImageWidget:new{ file = self.file, scale_factor = self.factor, alpha = true, file_do_cache = false },
        },
    }
end

function SpriteView:onTap()
    UIManager:close(self)
    UIManager:setDirty("all", "full")
    return true
end

function Spike:checkSprite()
    local path = PLUGIN_DIR .. "/test_sprite.png"
    local ok, err = pcall(function() UIManager:show(SpriteView:new{ file = path }) end)
    self.results.sprite = ok and "shown: 16x16 PNG scaled x8 (tap to close); judge edges: crisp = nearest-neighbour"
        or ("ERROR: " .. tostring(err))
    if not ok then self:show(self.results.sprite) end
end

-- 6. Events -----------------------------------------------------------------------------------

function Spike:onPageUpdate()
    self.events.page = self.events.page + 1
    local t0 = time.now()
    local ok, text = pcall(self.pageText, self)
    if ok and text then
        self.samples[#self.samples + 1] = { time.to_ms(time.since(t0)), #text }
        if #self.samples > 30 then table.remove(self.samples, 1) end
    end
end
function Spike:onReaderReady() self.events.ready = self.events.ready + 1 end
function Spike:onCloseDocument() self.events.close = self.events.close + 1 end
function Spike:onSuspend() self.events.suspend = self.events.suspend + 1 end
function Spike:onResume() self.events.resume = self.events.resume + 1 end

-- Report --------------------------------------------------------------------------------------

function Spike:showReport()
    local lines = self:environment()
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Page text:  " .. (self.results.page_text or "(not run)"):gsub("\n.*", "")
    lines[#lines + 1] = "Per page turn: " .. self:sampleSummary()
    lines[#lines + 1] = "Settings:   launches=" .. self.settings:readSetting("launches", 0)
    lines[#lines + 1] = "HTTPS:      " .. (self.results.https or "(not run)")
    lines[#lines + 1] = "Sprite:     " .. (self.results.sprite or "(not run)")
    lines[#lines + 1] = string.format("Events:     pages=%d ready=%d close=%d suspend=%d resume=%d", self.events.page,
        self.events.ready, self.events.close, self.events.suspend, self.events.resume)
    self:show(table.concat(lines, "\n"))
end

return Spike
