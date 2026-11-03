--[[--
What the character has absorbed from reading. One state per character.

The state is plain data (numbers, strings, tables; no functions, no cycles), so the caller can persist it
with any serializer (KOReader: LuaSettings). All functions here are pure: the caller passes the clock.

    state.pages_read        pages counted, ever
    state.themes[id]        decaying score per theme; the largest one is the "obsession"
    state.axes[id]          personality axes, -100..100, defined by the character
    state.obsession         current obsession theme id (or nil)
    state.books[book_id]    per-book totals (pages, words, theme density sums, tone, last seen)
    state.days[YYYY-MM-DD]  pages counted per day (the last DAYS_KEPT days)

A page is counted by `State.feed` only if it has text and its position in the book has not been counted
before. The caller decides *when* a page is worth feeding (for example, after the reader stayed on it for a
few seconds), and passes `progress`, the position in the book from 0 to 1. Positions are bucketed
(BUCKETS per book), so the rule survives font-size changes that renumber the pages of reflowable books.

Character configuration (from the pack), only the axes are used here:

    config = { axes = { courage = {
        step = 1,       -- how far one page can push the axis (default 1)
        decay = 0.998,  -- per counted page, the axis returns toward 0 (default 0.998)
        effects = {
            themes  = { sea = 0.5, fear = -0.5 },  -- weight x (density above the baseline)
            events  = { funeral = -0.3 },          -- same, for events
            tone    = 0.2,                         -- weight x (tone density - baseline); signed
            periods = { night = 0.1 },             -- added whenever the page is read in that period
        },
    } } }

Density is keyword hits per 100 words. Themes and events only push when above their baseline (default 0),
so what the reader does not read never pushes an axis the other way; it only decays toward neutral.

Pure Lua, no KOReader dependency.
]]

local State = {}

State.VERSION = 1
State.BUCKETS = 1000          -- positions per book used to decide "this page was already counted"
State.THEME_DECAY = 0.99      -- per counted page
State.OBSESSION_MIN = 10      -- score a theme needs to become the obsession
State.OBSESSION_MARGIN = 1.2  -- a new theme must beat the current obsession by this factor
State.MAX_BOOKS = 50          -- books remembered; the least recently read are dropped
State.DAYS_KEPT = 60
State.AXIS_LIMIT = 100
State.PERIODS = { { 5, "morning" }, { 12, "afternoon" }, { 18, "evening" }, { 22, "night" } }

local DEFAULT_STEP, DEFAULT_DECAY = 1, 0.998

--- A fresh state.
function State.new()
    return {
        version = State.VERSION,
        pages_read = 0,
        themes = {},
        axes = {},
        obsession = nil,
        books = {},
        days = {},
    }
end

--- Make `state` (possibly loaded from disk, possibly from an older version) usable with `config`.
-- Fills in whatever is missing; never removes data. Returns `state`.
function State.normalize(state, config)
    state.version = state.version or State.VERSION
    state.pages_read = state.pages_read or 0
    state.themes = state.themes or {}
    state.axes = state.axes or {}
    state.books = state.books or {}
    state.days = state.days or {}
    for id in pairs(config and config.axes or {}) do
        state.axes[id] = state.axes[id] or 0
    end
    return state
end

--- The part of the day for an hour (0-23): "morning", "afternoon", "evening" or "night".
function State.period(hour)
    local result = "night"  -- before the first boundary (00:00-04:59) is still night
    for _, boundary in ipairs(State.PERIODS) do
        if hour >= boundary[1] then result = boundary[2] end
    end
    return result
end

local function clamp(value, limit)
    return math.max(-limit, math.min(limit, value))
end

local function density(count, words)
    return (count or 0) / words * 100
end

local function newBook(title, now)
    return {
        title = title, first = now, last = now,
        pages = 0, words = 0, tone = 0,
        themes = {}, events = {},
        seen = string.rep("0", State.BUCKETS),
    }
end

local function dropOldestBooks(state)
    local ids = {}
    for id in pairs(state.books) do ids[#ids + 1] = id end
    if #ids <= State.MAX_BOOKS then return end
    table.sort(ids, function(a, b) return state.books[a].last > state.books[b].last end)
    for i = State.MAX_BOOKS + 1, #ids do state.books[ids[i]] = nil end
end

local function dropOldDays(state)
    local days = {}
    for day in pairs(state.days) do days[#days + 1] = day end
    if #days <= State.DAYS_KEPT then return end
    table.sort(days, function(a, b) return a > b end)
    for i = State.DAYS_KEPT + 1, #days do state.days[days[i]] = nil end
end

local function pushAxes(state, config, page, words)
    local signals, baseline = page.signals, page.baseline or {}
    local base_themes, base_events = (baseline.themes or {}), (baseline.events or {})
    local period = State.period(os.date("*t", page.now).hour)
    for id, axis in pairs(config and config.axes or {}) do
        local effects = axis.effects or {}
        local push = 0
        for theme, weight in pairs(effects.themes or {}) do
            local above = density(signals.counts.themes and signals.counts.themes[theme], words) - (base_themes[theme] or 0)
            push = push + weight * math.max(0, above)
        end
        for event, weight in pairs(effects.events or {}) do
            local above = density(signals.counts.events and signals.counts.events[event], words) - (base_events[event] or 0)
            push = push + weight * math.max(0, above)
        end
        if effects.tone then
            push = push + effects.tone * (density(signals.tone, words) - (baseline.tone or 0))
        end
        push = push + ((effects.periods or {})[period] or 0)
        local value = (state.axes[id] or 0) * (axis.decay or DEFAULT_DECAY) + (axis.step or DEFAULT_STEP) * push
        state.axes[id] = clamp(value, State.AXIS_LIMIT)
    end
end

--- The theme the character is obsessed with: `id, score`, or nil when no theme is strong enough.
function State.obsession(state)
    local best_id, best = nil, 0
    for id, score in pairs(state.themes) do
        if score > best or (score == best and best_id and id < best_id) then best_id, best = id, score end
    end
    if best_id and best >= State.OBSESSION_MIN then return best_id, best end
    return nil
end

local function updateObsession(state)
    local candidate, score = State.obsession(state)
    local current = state.obsession
    if not candidate or candidate == current then return nil end
    local current_score = current and state.themes[current] or 0
    if current and score < current_score * State.OBSESSION_MARGIN then return nil end
    state.obsession = candidate
    return { from = current, to = candidate }
end

--- Feed one page the reader has actually read.
--
-- `page` fields:
--   book       stable id of the book (string, required)
--   title      title of the book (optional, kept for the diary)
--   progress   position in the book, 0..1 (required)
--   signals    result of `Signals.extract` (required)
--   now        os.time() of the reading (required)
--   baseline   optional `{ themes = {id = density}, events = {id = density}, tone = density }`
--
-- @return table `{ counted = boolean, reason = string|nil, obsession_changed = {from, to}|nil }`
function State.feed(state, config, page)
    assert(type(page.book) == "string" and page.book ~= "", "page.book is required")
    assert(type(page.progress) == "number", "page.progress is required")
    assert(type(page.signals) == "table", "page.signals is required")
    assert(type(page.now) == "number", "page.now is required")

    local signals = page.signals
    local words = signals.words or 0
    if words == 0 then return { counted = false, reason = "no text" } end

    local bucket = math.floor(math.max(0, math.min(1, page.progress)) * State.BUCKETS) + 1
    bucket = math.min(bucket, State.BUCKETS)
    local book = state.books[page.book]
    if book and book.seen:sub(bucket, bucket) == "1" then
        book.last = math.max(book.last, page.now)
        return { counted = false, reason = "already read" }
    end
    if not book then
        book = newBook(page.title, page.now)
        state.books[page.book] = book
    end
    book.title = page.title or book.title
    book.seen = book.seen:sub(1, bucket - 1) .. "1" .. book.seen:sub(bucket + 1)
    book.last = math.max(book.last, page.now)
    book.pages = book.pages + 1
    book.words = book.words + words
    book.tone = book.tone + density(signals.tone, words)

    for id in pairs(state.themes) do state.themes[id] = state.themes[id] * State.THEME_DECAY end
    for id, hits in pairs(signals.counts.themes or {}) do
        local d = density(hits, words)
        state.themes[id] = (state.themes[id] or 0) + d
        book.themes[id] = (book.themes[id] or 0) + d
    end
    for id, hits in pairs(signals.counts.events or {}) do
        book.events[id] = (book.events[id] or 0) + density(hits, words)
    end

    pushAxes(state, config, page, words)

    state.pages_read = state.pages_read + 1
    local day = os.date("%Y-%m-%d", page.now)
    state.days[day] = (state.days[day] or 0) + 1
    dropOldDays(state)
    dropOldestBooks(state)

    return { counted = true, obsession_changed = updateObsession(state) }
end

--- Pages counted on the calendar day of `now`.
function State.pagesToday(state, now)
    return state.days[os.date("%Y-%m-%d", now)] or 0
end

--- Consecutive days with reading, ending today, or ending yesterday if nothing was read yet today.
function State.streak(state, now)
    local date = os.date("*t", now)
    local noon = os.time({ year = date.year, month = date.month, day = date.day, hour = 12 })
    if not state.days[os.date("%Y-%m-%d", noon)] then noon = noon - 86400 end
    local streak = 0
    while state.days[os.date("%Y-%m-%d", noon)] do
        streak = streak + 1
        noon = noon - 86400
    end
    return streak
end

return State
