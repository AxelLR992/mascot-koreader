local T = require("lib")
local State = require("mascot.state")

local function at(year, month, day, hour)
    return os.time({ year = year, month = month, day = day, hour = hour or 15 })
end

local NOW = at(2026, 11, 2)

--- Hand-made signals: `themes` are raw hit counts on a page of `words` words.
local function signals(themes, opts)
    opts = opts or {}
    return {
        words = opts.words or 100,
        counts = { themes = themes or {}, events = opts.events or {} },
        tone = opts.tone or 0,
    }
end

local function page(overrides)
    local p = { book = "book-a", progress = 0.1, signals = signals({ sea = 2 }), now = NOW }
    for key, value in pairs(overrides or {}) do p[key] = value end
    return p
end

local function plain(value, seen)
    seen = seen or {}
    local kind = type(value)
    if kind == "function" or kind == "userdata" or kind == "thread" then return false end
    if kind == "table" then
        if seen[value] then return false end
        seen[value] = true
        for k, v in pairs(value) do
            if not plain(k, seen) or not plain(v, seen) then return false end
        end
        seen[value] = nil
    end
    return true
end

-- Shape ---------------------------------------------------------------------------------------

T.test("state: a new state is empty and plain data", function()
    local state = State.new()
    T.eq(state.pages_read, 0)
    T.eq(State.obsession(state), nil)
    T.eq(plain(state), true)
end)

T.test("state: stays plain data after feeding pages", function()
    local state = State.new()
    local config = { axes = { courage = { effects = { themes = { sea = 1 } } } } }
    State.normalize(state, config)
    State.feed(state, config, page())
    T.eq(plain(state), true)
end)

T.test("state: normalize adds axes that a newer pack defines and keeps existing data", function()
    local state = State.new()
    state.axes.courage = 42
    State.normalize(state, { axes = { courage = {}, humour = {} } })
    T.eq(state.axes.courage, 42)
    T.eq(state.axes.humour, 0)
end)

T.test("state: normalize repairs a state with missing tables", function()
    local state = State.normalize({}, nil)
    T.eq(state.pages_read, 0)
    T.eq(state.books, {})
    T.eq(state.days, {})
end)

-- Counting pages ------------------------------------------------------------------------------

T.test("feed: counts a page and records book totals", function()
    local state = State.new()
    local result = State.feed(state, nil, page({ title = "Moby Dick" }))
    T.eq(result.counted, true)
    T.eq(state.pages_read, 1)
    local book = state.books["book-a"]
    T.eq(book.title, "Moby Dick")
    T.eq(book.pages, 1)
    T.eq(book.words, 100)
    T.eq(book.themes.sea, 2)  -- 2 hits in 100 words = density 2
end)

T.test("feed: a position already counted is not counted again", function()
    local state = State.new()
    State.feed(state, nil, page())
    local again = State.feed(state, nil, page({ now = NOW + 60 }))
    T.eq(again.counted, false)
    T.eq(again.reason, "already read")
    T.eq(state.pages_read, 1)
    T.eq(state.books["book-a"].pages, 1)
    T.eq(state.themes.sea, 2)
end)

T.test("feed: positions in the same bucket count once, different buckets count separately", function()
    local state = State.new()
    State.feed(state, nil, page({ progress = 0.1000 }))
    T.eq(State.feed(state, nil, page({ progress = 0.1004 })).counted, false)
    T.eq(State.feed(state, nil, page({ progress = 0.2 })).counted, true)
    T.eq(state.pages_read, 2)
end)

T.test("feed: the same position in another book counts", function()
    local state = State.new()
    State.feed(state, nil, page({ book = "a" }))
    T.eq(State.feed(state, nil, page({ book = "b" })).counted, true)
end)

T.test("feed: progress 1.0 lands in the last bucket", function()
    local state = State.new()
    T.eq(State.feed(state, nil, page({ progress = 1 })).counted, true)
    T.eq(State.feed(state, nil, page({ progress = 1 })).counted, false)
end)

T.test("feed: progress outside 0..1 is clamped", function()
    local state = State.new()
    T.eq(State.feed(state, nil, page({ progress = -3 })).counted, true)
    T.eq(State.feed(state, nil, page({ progress = 7 })).counted, true)
end)

T.test("feed: a page without text is not counted and does not mark the position", function()
    local state = State.new()
    local result = State.feed(state, nil, page({ signals = signals({}, { words = 0 }) }))
    T.eq(result.counted, false)
    T.eq(result.reason, "no text")
    T.eq(state.pages_read, 0)
    T.eq(State.feed(state, nil, page()).counted, true)
end)

T.test("feed: rejects missing required fields", function()
    local state = State.new()
    T.throws(function() State.feed(state, nil, page({ book = false })) end, "page.book")
    T.throws(function() State.feed(state, nil, page({ progress = "x" })) end, "page.progress")
    T.throws(function() State.feed(state, nil, page({ signals = false })) end, "page.signals")
    T.throws(function() State.feed(state, nil, page({ now = false })) end, "page.now")
end)

-- Themes and obsession ------------------------------------------------------------------------

T.test("themes: scores decay with every counted page", function()
    local state = State.new()
    State.feed(state, nil, page({ progress = 0.1, signals = signals({ sea = 10 }) }))
    State.feed(state, nil, page({ progress = 0.2, signals = signals({}) }))
    T.eq(math.abs(state.themes.sea - 10 * State.THEME_DECAY) < 1e-9, true)
end)

T.test("obsession: none until a theme reaches the minimum", function()
    local state = State.new()
    State.feed(state, nil, page({ signals = signals({ sea = 5 }) }))
    T.eq(State.obsession(state), nil)
    T.eq(state.obsession, nil)
end)

T.test("obsession: the strongest theme above the minimum wins and the change is reported", function()
    local state = State.new()
    local result = State.feed(state, nil, page({ signals = signals({ sea = 12, love = 3 }) }))
    T.eq(State.obsession(state), "sea")
    T.eq(state.obsession, "sea")
    T.eq(result.obsession_changed, { from = nil, to = "sea" })
end)

T.test("obsession: a rival must beat the current one by the margin", function()
    local state = State.new()
    State.feed(state, nil, page({ progress = 0.1, signals = signals({ sea = 20 }) }))
    -- love reaches 22 against sea ~19.8: stronger, but under the 1.2 margin
    local result = State.feed(state, nil, page({ progress = 0.2, signals = signals({ love = 22 }) }))
    T.eq(State.obsession(state), "love")
    T.eq(state.obsession, "sea")
    T.eq(result.obsession_changed, nil)
    -- more love eventually takes over
    local third = State.feed(state, nil, page({ progress = 0.3, signals = signals({ love = 20 }) }))
    T.eq(state.obsession, "love")
    T.eq(third.obsession_changed, { from = "sea", to = "love" })
end)

-- Personality axes ----------------------------------------------------------------------------

local function axisConfig(effects, extra)
    local axis = { effects = effects }
    for key, value in pairs(extra or {}) do axis[key] = value end
    return { axes = { courage = axis } }
end

T.test("axes: a theme above baseline pushes by weight x excess density", function()
    local config = axisConfig({ themes = { sea = 0.5 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({ sea = 4 }), baseline = { themes = { sea = 1 } } }))
    T.eq(state.axes.courage, 0.5 * (4 - 1))
end)

T.test("axes: a negative weight pushes the other way", function()
    local config = axisConfig({ themes = { fear = -1 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({ fear = 3 }) }))
    T.eq(state.axes.courage, -3)
end)

T.test("axes: a theme at or below baseline pushes nothing", function()
    local config = axisConfig({ themes = { sea = 1 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({ sea = 1 }), baseline = { themes = { sea = 2 } } }))
    T.eq(state.axes.courage, 0)
    State.feed(state, config, page({ progress = 0.5, signals = signals({}), baseline = { themes = { sea = 2 } } }))
    T.eq(state.axes.courage, 0)
end)

T.test("axes: events push like themes", function()
    local config = axisConfig({ events = { funeral = -2 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({}, { events = { funeral = 1 } }) }))
    T.eq(state.axes.courage, -2)
end)

T.test("axes: tone is signed and measured against its baseline", function()
    local config = axisConfig({ tone = 1 })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({}, { tone = -4 }) }))
    T.eq(state.axes.courage, -4)
    local other = State.normalize(State.new(), config)
    State.feed(other, config, page({ signals = signals({}, { tone = -4 }), baseline = { tone = -4 } }))
    T.eq(other.axes.courage, 0)
end)

T.test("axes: the period of the day adds its weight", function()
    local config = axisConfig({ periods = { night = 0.7 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ progress = 0.1, now = at(2026, 11, 2, 15), signals = signals({}) }))
    T.eq(state.axes.courage, 0)
    State.feed(state, config, page({ progress = 0.2, now = at(2026, 11, 2, 23), signals = signals({}) }))
    T.eq(math.abs(state.axes.courage - 0.7) < 1e-9, true)
    State.feed(state, config, page({ progress = 0.3, now = at(2026, 11, 3, 2), signals = signals({}) }))
    T.eq(state.axes.courage > 0.7, true)
end)

T.test("axes: decay pulls the axis back toward zero", function()
    local config = axisConfig({}, { decay = 0.5 })
    local state = State.normalize(State.new(), config)
    state.axes.courage = 40
    State.feed(state, config, page({ signals = signals({}) }))
    T.eq(state.axes.courage, 20)
end)

T.test("axes: step scales the push", function()
    local config = axisConfig({ themes = { sea = 1 } }, { step = 0.25 })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({ sea = 8 }) }))
    T.eq(state.axes.courage, 2)
end)

T.test("axes: values are clamped to the limit", function()
    local config = axisConfig({ themes = { sea = 1 } }, { step = 1000 })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ signals = signals({ sea = 9 }) }))
    T.eq(state.axes.courage, State.AXIS_LIMIT)
end)

T.test("axes: staying away from a theme never pushes the opposite way", function()
    local config = axisConfig({ themes = { sea = 1 } })
    local state = State.normalize(State.new(), config)
    State.feed(state, config, page({ progress = 0.1, signals = signals({ sea = 5 }) }))
    local before = state.axes.courage
    for i = 1, 20 do
        State.feed(state, config, page({ progress = 0.1 + i / 100, signals = signals({ love = 5 }) }))
    end
    T.eq(state.axes.courage > 0, true)
    T.eq(state.axes.courage < before, true)
end)

-- Days and streaks ----------------------------------------------------------------------------

T.test("days: pages are counted per calendar day", function()
    local state = State.new()
    State.feed(state, nil, page({ progress = 0.1, now = at(2026, 11, 2, 9) }))
    State.feed(state, nil, page({ progress = 0.2, now = at(2026, 11, 2, 21) }))
    State.feed(state, nil, page({ progress = 0.3, now = at(2026, 11, 3, 9) }))
    T.eq(State.pagesToday(state, at(2026, 11, 2, 23)), 2)
    T.eq(State.pagesToday(state, at(2026, 11, 3, 10)), 1)
    T.eq(State.pagesToday(state, at(2026, 11, 4, 10)), 0)
end)

T.test("streak: consecutive days ending today", function()
    local state = State.new()
    for day = 1, 3 do
        State.feed(state, nil, page({ progress = day / 10, now = at(2026, 11, day) }))
    end
    T.eq(State.streak(state, at(2026, 11, 3, 20)), 3)
end)

T.test("streak: still alive the day after, until a full day is missed", function()
    local state = State.new()
    for day = 1, 3 do
        State.feed(state, nil, page({ progress = day / 10, now = at(2026, 11, day) }))
    end
    T.eq(State.streak(state, at(2026, 11, 4, 8)), 3)
    T.eq(State.streak(state, at(2026, 11, 5, 8)), 0)
end)

T.test("streak: a gap restarts it", function()
    local state = State.new()
    for _, day in ipairs({ 1, 2, 4, 5 }) do
        State.feed(state, nil, page({ progress = day / 10, now = at(2026, 11, day) }))
    end
    T.eq(State.streak(state, at(2026, 11, 5, 20)), 2)
end)

T.test("streak: works across a month boundary", function()
    local state = State.new()
    State.feed(state, nil, page({ progress = 0.1, now = at(2026, 10, 31) }))
    State.feed(state, nil, page({ progress = 0.2, now = at(2026, 11, 1) }))
    T.eq(State.streak(state, at(2026, 11, 1, 20)), 2)
end)

T.test("days: only the most recent days are kept", function()
    local state = State.new()
    local start = at(2026, 1, 1)
    for i = 0, State.DAYS_KEPT + 9 do
        State.feed(state, nil, page({ progress = (i % 900) / 1000, book = "b" .. i, now = start + i * 86400 }))
    end
    local count = 0
    for _ in pairs(state.days) do count = count + 1 end
    T.eq(count, State.DAYS_KEPT)
end)

-- Books ---------------------------------------------------------------------------------------

T.test("books: only the most recently read are kept", function()
    local state = State.new()
    for i = 1, State.MAX_BOOKS + 5 do
        State.feed(state, nil, page({ book = "book-" .. i, now = NOW + i }))
    end
    local count = 0
    for _ in pairs(state.books) do count = count + 1 end
    T.eq(count, State.MAX_BOOKS)
    T.eq(state.books["book-1"], nil)
    T.eq(state.books["book-" .. (State.MAX_BOOKS + 5)] ~= nil, true)
end)

T.test("books: a re-read position refreshes the book's last-read time", function()
    local state = State.new()
    State.feed(state, nil, page({ now = NOW }))
    State.feed(state, nil, page({ now = NOW + 500 }))
    T.eq(state.books["book-a"].last, NOW + 500)
end)

-- Periods -------------------------------------------------------------------------------------

T.test("period: boundaries", function()
    T.eq(State.period(0), "night")
    T.eq(State.period(4), "night")
    T.eq(State.period(5), "morning")
    T.eq(State.period(11), "morning")
    T.eq(State.period(12), "afternoon")
    T.eq(State.period(17), "afternoon")
    T.eq(State.period(18), "evening")
    T.eq(State.period(21), "evening")
    T.eq(State.period(22), "night")
    T.eq(State.period(23), "night")
end)
