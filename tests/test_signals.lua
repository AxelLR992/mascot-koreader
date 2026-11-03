local T = require("lib")
local Signals = require("mascot.signals")
local locales = require("fixtures.locales")

local en, es = locales.en, locales.es

T.test("signals: exact keywords are counted per theme", function()
    local s = Signals.extract("The sea was calm. The sea was wide.", en)
    T.eq(s.counts.themes.sea, 2)
    T.eq(s.counts.themes.death, nil)
end)

T.test("signals: prefix keywords match inflections", function()
    local s = Signals.extract("He dies. They died. Everyone dies.", en)
    T.eq(s.counts.themes.death, 3)
end)

T.test("signals: a prefix keyword also matches the bare stem", function()
    T.eq(Signals.extract("The die is cast.", en).counts.themes.death, 1)
end)

T.test("signals: irregular forms need their own keyword", function()
    T.eq(Signals.extract("Dying is hard.", en).counts.themes.death, nil)
end)

T.test("signals: prefix keyword does not match unrelated words", function()
    T.eq(Signals.extract("A dim light and a dime.", en).counts.themes.death, nil)
end)

T.test("signals: a word counts once per theme even if two keywords match", function()
    -- "ships" matches the prefix "ship*" only once; "funeral" is both a theme word and an event word
    local s = Signals.extract("The ships left before the funeral.", en)
    T.eq(s.counts.themes.sea, 1)
    T.eq(s.counts.themes.death, 1)
    T.eq(s.counts.events.funeral, 1)
end)

T.test("signals: one word can feed several themes", function()
    local s = Signals.extract("Everyone died.", en)
    T.eq(s.counts.themes.death, 1)
    T.eq(s.counts.themes.night, 1)
end)

T.test("signals: tone is positive minus negative hits", function()
    T.eq(Signals.extract("Joy and love, but also grief.", en).tone, 1)
    T.eq(Signals.extract("Grief, sad, grief.", en).tone, -3)
end)

T.test("signals: tone is zero for a locale without a tone group", function()
    T.eq(Signals.extract("El mar y la muerte.", es).tone, 0)
end)

T.test("signals: Spanish keywords with accents and prefixes", function()
    local s = Signals.extract("El barco murió en el mar. Las olas.", es)
    T.eq(s.counts.themes.sea, 3)
    T.eq(s.counts.themes.death, 1)
    local t = Signals.extract("Morir es otra cosa. Muere el rey, mora la reina.", es)
    T.eq(t.counts.themes.death, 2)  -- "morir" and "mora" match mor*; "muere" does not
end)

T.test("signals: counts every group of the locale, even when empty", function()
    local s = Signals.extract("Nothing here.", en)
    T.eq(s.counts, { themes = {}, events = {}, tone = {} })
end)

T.test("signals: sizes and rhythm", function()
    local s = Signals.extract("One two three. Four five! Six seven eight nine?", en)
    T.eq(s.words, 9)
    T.eq(s.sentences, 3)
    T.eq(s.avg_sentence, 3)
end)

T.test("signals: an ellipsis run is one sentence end", function()
    T.eq(Signals.extract("Well... maybe.", en).sentences, 2)
end)

T.test("signals: text without terminators is one sentence", function()
    T.eq(Signals.extract("no punctuation at all", en).sentences, 1)
end)

T.test("signals: counts quoted dialogue turns", function()
    T.eq(Signals.extract('"Hello," she said. "Goodbye," he said.', en).dialogue, 2)
    T.eq(Signals.extract("“Hello,” she said.", en).dialogue, 1)
    T.eq(Signals.extract("«Hola», dijo.", es).dialogue, 1)
end)

T.test("signals: counts dash-led dialogue lines", function()
    local text = "—Hola —dijo ella.\n—Adiós.\nUna línea normal."
    T.eq(Signals.extract(text, es).dialogue, 2)
end)

T.test("signals: empty text gives zeros without error", function()
    local s = Signals.extract("", en)
    T.eq(s.words, 0)
    T.eq(s.sentences, 0)
    T.eq(s.avg_sentence, 0)
    T.eq(s.dialogue, 0)
    T.eq(s.tone, 0)
end)

T.test("signals: a locale without keywords still works", function()
    local s = Signals.extract("Plain text.", {})
    T.eq(s.words, 2)
    T.eq(s.counts, {})
end)

T.test("signals: rejects prefix keywords that are too short", function()
    local bad = { keywords = { themes = { x = { "ab*" } } } }
    T.throws(function() Signals.compile(bad) end, "prefix too short")
end)
