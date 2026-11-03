--[[--
Turns the text of a page into numbers ("signals") that the rest of the engine can accumulate.

The engine knows no words. Everything language-specific comes from a locale table:

    locale = {
        keywords = {
            themes = { death = { "death", "die*", ... }, ... },   -- any group names are allowed
            events = { funeral = { "funeral", "burial" }, ... },
            tone   = { positive = { ... }, negative = { ... } },
        },
    }

A keyword matches a whole word. A trailing `*` makes it a prefix ("die*" matches "dies", "died",
"dying"); a prefix needs at least `Signals.MIN_PREFIX` letters. Keywords must be lowercase.

Signals for one page:

    words, sentences, avg_sentence   size and rhythm
    dialogue                         estimated number of spoken turns (quote pairs + dash-led lines)
    counts[group][id]                keyword hits per group and id, for every group of the locale
    tone                             positive hits minus negative hits (0 without a `tone` group)

Pure Lua, no KOReader dependency.
]]

local Tokenizer = require("mascot.tokenizer")

local Signals = {}

Signals.MIN_PREFIX = 3

local compiled_cache = setmetatable({}, { __mode = "k" })

--- Build (once per locale table) the lookup tables used by `extract`.
-- @return table `{ groups = { name = true }, exact = { word = { {group, id}, ... } }, prefix = { ... } }`
function Signals.compile(locale)
    local compiled = compiled_cache[locale]
    if compiled then return compiled end
    compiled = { groups = {}, exact = {}, prefix = {} }
    for group, ids in pairs(locale.keywords or {}) do
        compiled.groups[group] = true
        for id, words in pairs(ids) do
            for _, keyword in ipairs(words) do
                local target, key = compiled.exact, keyword
                if keyword:sub(-1) == "*" then
                    key = keyword:sub(1, -2)
                    if #key < Signals.MIN_PREFIX then
                        error(string.format("keyword prefix too short: %s.%s %q", group, id, keyword))
                    end
                    target = compiled.prefix
                end
                local list = target[key]
                if not list then
                    list = {}
                    target[key] = list
                end
                list[#list + 1] = { group, id }
            end
        end
    end
    compiled_cache[locale] = compiled
    return compiled
end

local function count(text, pattern)
    local _, n = text:gsub(pattern, "")
    return n
end

local QUOTE_MARKS = { '"', "\226\128\156", "\226\128\157", "\194\171", "\194\187" }  -- " “ ” « »
local DASH_LEAD = "^%s*\226\128[\148\149]"  -- a line that starts with — or ―

local function dialogueTurns(text)
    local marks = 0
    for _, mark in ipairs(QUOTE_MARKS) do marks = marks + count(text, mark) end
    local dashes = 0
    for line in text:gmatch("[^\n]+") do
        if line:find(DASH_LEAD) then dashes = dashes + 1 end
    end
    return math.floor(marks / 2) + dashes
end

local function sentenceCount(text, words)
    if words == 0 then return 0 end
    local runs = count(text, "[%.!%?]+") + count(text, "\226\128\166")
    return math.max(1, runs)
end

--- Extract the signals of `text` (a string; may be empty) using `locale`.
function Signals.extract(text, locale)
    local compiled = Signals.compile(locale)
    local counts = {}
    for group in pairs(compiled.groups) do counts[group] = {} end

    local words = Tokenizer.words(text)
    local seen = {}
    local function hit(entries)
        for _, entry in ipairs(entries) do
            local group, id = entry[1], entry[2]
            local key = group .. "\0" .. id
            if not seen[key] then
                seen[key] = true
                counts[group][id] = (counts[group][id] or 0) + 1
            end
        end
    end
    for _, word in ipairs(words) do
        seen = {}  -- a word counts once per (group, id), even if two keywords match it
        local entries = compiled.exact[word]
        if entries then hit(entries) end
        for length = Signals.MIN_PREFIX, #word do
            entries = compiled.prefix[word:sub(1, length)]
            if entries then hit(entries) end
        end
    end

    local sentences = sentenceCount(text, #words)
    local tone = counts.tone or {}
    return {
        words = #words,
        sentences = sentences,
        avg_sentence = sentences > 0 and #words / sentences or 0,
        dialogue = dialogueTurns(text),
        counts = counts,
        tone = (tone.positive or 0) - (tone.negative or 0),
    }
end

return Signals
