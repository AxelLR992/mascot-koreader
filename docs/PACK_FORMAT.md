# Character pack format

**Status: draft, schema version 1.** Nothing implements this yet. Comments and objections are welcome before the loader and the offline brain are written.

A *character pack* is a directory. The engine reads it; it never runs anything from it. Packs contain only JSON and images.

```text
characters/<id>/
  character.json        identity, sprites, personality axes, moods, triggers
  sprites/              images (PNG or SVG)
  locales/
    <code>.json         phrases, labels and the persona prompt for one language
```

`<id>` is lowercase letters, digits, `_` and `-`, and equals `id` in `character.json`.

## The split of responsibilities

| Who | Defines |
|---|---|
| **Engine** | The *vocabulary* of signals (theme ids, event ids), how they are detected per language (the **lexicon**), how state evolves, and when events happen. |
| **Pack** | The *reactions*: which axes the character has and what moves them, which sprite shows when, which triggers fire on which events, and what the character says. |

A pack author writes phrases and rules. They do not write word lists, unless they want to extend the engine's lexicon for their character.

### Engine vocabulary (initial)

- **Themes:** `mortality`, `romance`, `conflict`, `journey`, `sea`, `faith`, `wealth`, `power`, `science`, `knowledge`, `art`, `nature`, `animals`, `family`, `youth`, `city`, `loneliness`, `fear`, `madness`, `crime`, `freedom`, `memory`, `darkness`, `humour`
- **Events** (things that happen in a page or chapter): `funeral`, `wedding`, `departure`, `letter`, `storm`, `illness`, `party`, `fight`, `escape`
- **Periods:** `morning`, `afternoon`, `evening`, `night`

The lexicon (which words in which language feed which id) lives in `mascot.koplugin/lexicon/<code>.json`, is part of the engine, and is a separate piece of work. A pack's locale file may add keywords (see below).

## `character.json`

```json
{
  "schema_version": 1,
  "id": "creature",
  "name": "The Creature",
  "author": "Example Author",
  "version": "1.0.0",
  "license": "CC-BY-4.0",
  "default_locale": "en",

  "sprites": {
    "neutral": "sprites/neutral.png",
    "happy": "sprites/happy.png",
    "gloomy": "sprites/gloomy.png",
    "sleepy": "sprites/sleepy.png"
  },

  "axes": {
    "cheer": {
      "poles": ["gloomy", "cheerful"],
      "step": 1,
      "decay": 0.998,
      "effects": {
        "themes": { "romance": 0.4, "humour": 0.5, "mortality": -0.4, "loneliness": -0.3 },
        "events": { "funeral": -0.5, "wedding": 0.4 },
        "tone": 0.2,
        "periods": {}
      }
    },
    "boldness": {
      "poles": ["timid", "bold"],
      "effects": {
        "themes": { "journey": 0.4, "conflict": 0.3, "fear": -0.5 },
        "periods": { "night": -0.05 }
      }
    }
  },

  "moods": [
    { "sprite": "sleepy", "if": { "period": ["night"] } },
    { "sprite": "gloomy", "if": { "axes": { "cheer": { "max": -30 } } } },
    { "sprite": "happy", "if": { "axes": { "cheer": { "min": 30 } } } },
    { "sprite": "neutral" }
  ],

  "triggers": {
    "greet_night": {
      "on": "session_start",
      "if": { "period": ["night"] },
      "phrases": "greeting_night",
      "priority": 10
    },
    "streak": {
      "on": "session_start",
      "if": { "streak": { "min": 3 } },
      "phrases": "streak",
      "priority": 20,
      "cooldown": { "hours": 20 }
    },
    "new_obsession": {
      "on": "obsession_changed",
      "phrases": "obsession",
      "priority": 30
    },
    "chapter": {
      "on": "chapter_end",
      "phrases": "chapter",
      "chance": 0.4,
      "cooldown": { "pages": 10 }
    },
    "tap": { "on": "tap", "phrases": "idle" }
  }
}
```

### Fields

| Field | Required | Notes |
|---|---|---|
| `schema_version` | yes | Integer. The engine lists the versions it supports. |
| `id`, `name`, `author`, `version`, `license` | yes | `version` is semantic versioning. `license` is an SPDX identifier. |
| `default_locale` | yes | Must have a file in `locales/`. Every phrase group used by a trigger must exist in it. |
| `sprites` | yes | Mood name to file. `neutral` is required. Paths are relative and may not contain `..`. See [Sprites](#sprites). |
| `axes` | no | Personality axes. Each value is -100 to 100. Same shape that `mascot.state` consumes (`step`, `decay`, `effects`). `poles` are `[negative, positive]` ids used for labels. |
| `moods` | no | Ordered rules choosing the resting sprite. The first rule whose `if` matches wins. The last rule should have no `if`. |
| `triggers` | yes | See below. At least one trigger must be on `tap`. |

### Axis effects

For every counted page, an axis moves by `step × push` and then decays toward 0.

- `themes` / `events`: `weight × max(0, density − baseline)`. Density is keyword hits per 100 words. Only *above-baseline* amounts push, so not reading something never pushes the opposite way.
- `tone`: `weight × (tone density − baseline)`. Signed: sad pages are negative.
- `periods`: added whenever a page is read in that period.

Theme and event ids must exist in the engine vocabulary.

## Conditions (`if`)

One small declarative language, used in `moods`, `triggers` and phrases. Every key present must match (logical AND). An absent `if` always matches. There are no expressions and no code.

| Key | Meaning |
|---|---|
| `period` | Array of periods. Matches if the current one is listed. |
| `hours` | `{ "from": 22, "to": 5 }`, local hours; wraps past midnight. |
| `axes` | `{ "cheer": { "min": 30, "max": 80 } }`. Either bound may be omitted. |
| `obsession` | Theme id, or `true` for "any". |
| `streak` | `{ "min": 3 }` consecutive reading days. |
| `pages_today` | `{ "min": 50 }`. |
| `days_away` | `{ "min": 3 }` days since the last counted page (useful on `session_start`). |
| `book_theme` | `{ "sea": { "min": 1.5 } }` density in the current book. |
| `book_progress` | `{ "min": 0.9 }` position in the current book, 0 to 1. |
| `weekday` | Array of 1 (Monday) to 7 (Sunday). |

## Triggers

A trigger fires when the engine raises its event `on` and its `if` matches.

**Engine events:** `session_start` (KOReader opened or device woke), `page` (a counted page, rate-limited), `chapter_end`, `book_start`, `book_end`, `obsession_changed`, `tap`, `long_press`, `sleep` (device is about to sleep; used by the sleep screen).

| Field | Notes |
|---|---|
| `on` | One engine event. |
| `if` | Conditions (optional). |
| `phrases` | Name of a phrase group in the locale. |
| `priority` | Default 0. When several triggers match, only the highest priority ones remain. |
| `weight` | Default 1. Among equal priorities, chosen at random by weight. |
| `chance` | 0 to 1, default 1. Probability that the trigger fires at all when it matches. |
| `cooldown` | `{ "hours": n }` and/or `{ "pages": n }`. Not eligible again until both have passed. |
| `mood` | Sprite mood to show while speaking. Default: the resting mood. |

**Selection, in order:** collect triggers for the event, drop those whose `if` fails or that are cooling down, roll `chance`, keep the highest `priority`, pick by `weight`. Then pick a phrase from the group (below). If no trigger remains, the character stays quiet.

## `locales/<code>.json`

```json
{
  "locale": "en",
  "persona": "You are the creature from Mary Shelley's Frankenstein, in a gentle, melancholy mood. You live on an e-reader and comment on what the reader reads, in one or two short sentences.",

  "labels": {
    "themes": {
      "sea": { "name": "the sea", "about": "the sea" },
      "mortality": { "name": "death", "about": "death" },
      "loneliness": { "name": "loneliness", "about": "loneliness" }
    },
    "axes": { "cheer": ["gloomy", "cheerful"], "boldness": ["timid", "bold"] }
  },

  "keywords": {
    "themes": { "loneliness": ["hovel", "abandoned"] }
  },

  "phrases": {
    "greeting_night": [
      "Night again. I was made in a storm; the dark does not trouble me.",
      "Awake at {time}. We are alike in that."
    ],
    "streak": [
      "{streak} days running. Nobody has been this loyal to me before.",
      { "text": "{streak} days. I try not to hope, and fail.", "if": { "axes": { "cheer": { "max": -20 } } } }
    ],
    "obsession": [
      "You keep reading about {theme:about}. I know something of it.",
      { "text": "{theme} again. I have learned to recognise your moods.", "weight": 2 }
    ],
    "chapter": [
      "A chapter ends. I listened to all of it, through the wall.",
      "I learned language by listening at a wall. You make it look easy."
    ],
    "idle": [
      "I am here.",
      { "text": "I read, too, once. Paradise Lost. It did not help.", "short": "I read Paradise Lost once." },
      { "text": "Tonight {pages_today} pages. That is a quiet kind of company.", "if": { "pages_today": { "min": 10 } } }
    ]
  }
}
```

### Phrases

A group is a list. Each entry is a string or an object:

| Field | Notes |
|---|---|
| `text` | Required. May contain slots. |
| `short` | Optional shorter version, used in narrow places (a small card or the Simple UI widget). |
| `if` | Conditions (see above). Entries whose `if` fails are not candidates. |
| `weight` | Default 1. |

The engine skips an entry whose slots cannot be filled, avoids repeating the last few phrases it showed, and falls back to the default locale for a group the current locale lacks. There is no inline branching syntax inside `text`: personality is expressed by writing entries with an `if`.

### Slots

`{name}` is replaced with a value. `{name:form}` selects a grammatical form from a label (see `labels`).

| Slot | Value |
|---|---|
| `{book}`, `{author}`, `{chapter}` | From the book's metadata. |
| `{theme}`, `{theme:<form>}` | The obsession, from `labels.themes.<id>`. `name` is the default form; a language may define more (`about`, `in`, ...). |
| `{time}` | Local time, `HH:MM`. |
| `{streak}`, `{pages_today}`, `{days_away}` | Numbers. |
| `{progress}` | Percentage through the book. |

Planned, requiring name and quote detection: `{character}`, `{word}`, `{quote}`.

### `labels`

Human-readable names. Themes are listed with the forms the language needs; a language with grammatical gender or contractions puts them in the forms (`"sea": { "name": "el mar", "in": "en el mar" }`). Anything missing falls back to the engine's generic label for that language.

### `keywords`

Optional. Extends the engine lexicon for this character only. Same syntax as the lexicon: whole words, or a prefix with a trailing `*` of at least 3 letters. Lowercase.

### `persona`

Used only by the online brain: the system prompt describing the character in this language. The engine adds a compact summary of the state (axes, obsession, current book, a few recent quotes, and what the user's settings allow) and asks for one short line in the locale's language. A pack cannot widen what is sent; the engine decides that.

## Sprites

- One image per mood, all with the **same canvas size**. `neutral` is required.
- Pixel art: a PNG whose longest side is 64 px or less is shown with nearest-neighbour scaling by an integer factor. Transparent backgrounds work.
- Larger PNGs and SVGs are scaled smoothly.
- Optional moods the engine knows: `sleep` (used by the sleep screen). Any other mood name is allowed and used through `moods` and `triggers`.

## Validation

The loader rejects a pack, with a message naming the file and key, when:

- `schema_version` is not supported, or `id` does not match the directory;
- a required field is missing, or a field has the wrong type;
- `neutral` is missing, a sprite path is absolute or contains `..`, or a sprite file is missing;
- `default_locale` has no file, or a trigger names a phrase group that the default locale lacks;
- a theme, event, axis or mood id is unknown where it must exist;
- an `if` uses an unknown key;
- a keyword prefix is shorter than 3 letters;
- a limit is exceeded: locale file 512 KB, phrase text 240 characters, sprite file 256 KB, 64 sprites.

Unknown keys are **warnings**, not errors, so newer packs still load on older engines.

A command-line validator for authors is planned (`scripts/validate-pack.lua`).

## Versioning

`schema_version` is an integer. Adding optional keys does not change it. Removing or changing the meaning of a key does, and is a MAJOR release of the plugin. The engine lists the schema versions it supports and refuses others with a clear message.

## Open questions

1. **Shared lexicon vs. per-pack keywords.** This draft makes the lexicon part of the engine, so authors write phrases, not dictionaries. The cost: the vocabulary is fixed by the engine, and extending it needs `keywords` in each pack or a new engine release.
2. **Conditions instead of inline branches.** Personality is expressed with `if` on phrase entries, which validates and is easy to tool, but makes some variations more verbose than an inline `<a|b>` syntax would.
3. **Grammar forms.** `{theme:about}` handles prepositions and contractions without code, but every pack has to provide them. A language-level default in the engine can cover most cases.
4. **Events.** The list of detectable events (`funeral`, `storm`, ...) is small and keyword-based. Chapter-level reactions will be shallow until detection improves.
5. **Engine event `page`.** Needs a rate limit so a character does not speak every page. Suggested default: at most once per 10 counted pages, and never while the user keeps turning pages quickly.
