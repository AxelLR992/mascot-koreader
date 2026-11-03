# Plan

An extendable KOReader companion plugin. Characters are data-only packs; dialogue comes from an offline template brain or an optional online LLM brain.

## Goals

- Generic engine plus drop-in character packs (sprites, personality, per-language phrases).
- One active character at a time.
- Offline mode as the default; online mode (user API key, OpenAI-compatible) as an opt-in upgrade with silent fallback.
- Kindle (jailbroken) and Kobo support. Simple UI compatibility.
- Fully original, fully English codebase.

## Non-goals

- Growth, evolution or life stages. A character has a fixed identity; it may have moods and slowly drifting personality axes.
- Multiple simultaneous characters.
- On-device LLM inference (too heavy for these devices; see the online brain instead).
- Reusing any code, art or phrase banks from other projects.

## Architecture

```
mascot.koplugin/
  _meta.lua
  main.lua                 KOReader glue: menus, events, sleep screen, Simple UI card
  engine/
    reader.lua             page text -> signals (themes, tone, names, events, time)
    state.lua              persistent per-character state
    brain_offline.lua      trigger evaluation + weighted template selection + slot filling
    brain_online.lua       LLM client, prompt builder, scheduling, cache
    pack_loader.lua        loads and validates packs
  characters/
    <character>/
      character.json
      sprites/
      locales/<code>.json
docs/                      pack authoring guide, schema reference
tests/                     desktop-runnable tests for the pure logic
```

Pure logic (everything under `engine/` except adapters) must not require KOReader modules so it can be tested on a desktop.

## Character pack format

**Packs are data, never code.** The engine only reads them. A pack from a stranger cannot read files or the API key.

`character.json`:
- `schema_version`
- identity: id, display name, author, version, default locale, supported locales
- sprites: mapping from mood to file
- personality axes: id, two poles, step size, decay
- influences: recipes of weighted signals (e.g. `horror = { fear = 0.4, night = 0.25, _dark = 0.1 }`)
- axis effects: how signals push each axis
- triggers: conditions (time window, streak, chapter end, book finished, influence above N, ...) mapped to phrase groups

`locales/<code>.json`:
- phrase banks grouped by trigger/influence, with slots (`{book}`, `{name}`, `{theme}`, `{word}`)
- keyword lists per theme for that language
- inline personality branches
- persona prompt for the online brain

The engine falls back to the pack's default locale when a phrase or keyword list is missing. Phrases with unfillable slots are skipped.

## Offline brain

Signals (keyword counts per theme, sentiment, events, style, names, time of day) -> slow-moving state (axes, influences, obsession) -> trigger evaluation -> weighted phrase choice -> slot filling. Only pages actually read, once each, feed the state.

## Online brain

- OpenAI-compatible chat-completions client (covers OpenAI, OpenRouter, Groq, Together, local Ollama, many free tiers). Other providers via adapters behind one interface.
- Prompt = pack persona prompt (per locale) + compact state summary (axes, strongest influences, current book/chapter, a few recent quotes). Ask for one short line in the user's language.
- Called only at event points (chapter end, book finished, new day, at most every N pages). Result is cached and shown at the next utterance.
- Asynchronous with a short timeout. Never blocks reading. Never turns wifi on by itself.
- Any failure (no network, bad key, timeout, rate limit) falls back silently to the offline brain.
- Output is capped in length and treated as plain text.

## Risks

- **Privacy.** Online mode sends reading data to a third party. Requires an explicit opt-in screen listing what is sent. Default payload is a summary (themes, book title, chapter), not page text.
- **API key storage.** Plaintext in KOReader settings. Warn the user; recommend a scoped, low-limit key.
- **Networking.** HTTPS depends on the TLS libraries KOReader ships per platform. Verify on Kindle and Kobo in Phase 0.
- **Memory.** Load only the active pack. Keep state compact.
- **Pack quality.** Version the schema; ship a validator with clear error messages.
- **Platform differences.** Kindle and Kobo differ in paths, wifi handling and sleep-screen behaviour.

## Phases

### Phase 0: Spike
Confirm on a real Kindle (and a Kobo if available) that a plugin can: be loaded from a custom directory, read the current page text, persist settings, make an async HTTPS request, draw an image widget, and integrate with Simple UI. Hello-world LLM call.

### Phase 1: Engine core
Signals extraction, state, offline brain, with desktop tests. English first, but locale-driven from day one.

### Phase 2: Pack format
Schema, loader and validator. A reference character built only from the pack format: a public-domain-inspired "Frankenstein's monster" style character (original sprites, original phrases).

### Phase 3: KOReader integration
Main screen, menu, tap/long-press interactions, mood sprites, sleep screen, Simple UI card, settings (language, active character).

### Phase 4: Second character
A deliberately different character, written using only the pack format. Fix whatever the schema cannot express.

### Phase 5: Online brain
Provider client, prompt builder, scheduling, cache, fallback, settings UI and privacy opt-in.

### Phase 6: Tooling and docs
Pack validator CLI, pack template, authoring guide, release packaging (zip with the plugin folder).

## Phase 0 findings (partial)

Measured with `spikes/mascotspike.koplugin`.

| Check | Emulator (KOReader 2026.07.2) | Kindle Basic 4 (KOReader 2026.03) |
|---|---|---|
| Plugin loads, menu entry (Tools > More tools) | yes | yes |
| Device facts | 1072x1364, 300 dpi | 1072x1448, 300 dpi, LuaJIT arm, 218 of 474 MB RAM available |
| Settings persist across restarts | yes | yes |
| Suspend and resume events reach the plugin | not tested | yes (1 and 1) |
| Page text (reflowable) | yes: ~750 chars/page, 2.3 ms average over 27 page turns | **not tested yet** |
| HTTPS from a subprocess, UI not blocked | yes: 200 OK in 333 ms, UI loop kept ticking | **not tested yet** |
| Sprite at integer scale | yes: crisp nearest-neighbour edges, alpha works | **not tested yet** |
| Simple UI detected | no (not installed) | yes |

Observations:
- The Kindle runs KOReader **2026.03**, older than the emulator build. Target the older API and verify on the device.
- The Kindle has about 218 MB of free RAM, and its Lua heap read **164 MB** versus 17 MB in the emulator. The cause is unknown (possibly caches in other plugins). Budget a few MB for Mascot and measure before and after.
- The "launches" counter increments on every plugin instantiation (file manager and each opened book), not once per KOReader start.

Still to do on the Kindle: page text and per-page cost (open an EPUB, turn pages), HTTPS (needs Wi-Fi), sprite drawing, and page events.

## Decisions

Settled:
- Start from scratch; only ideas are borrowed. No Silverfish code, art or names.
- English-only codebase.
- No growth or evolution.
- One active character at a time.
- Targets: Kindle (maintainer owns a jailbroken one, using Simple UI) and Kobo.
- Conventions: Keep a Changelog, Semantic Versioning, gitmoji.
- Name: `mascot`.
- Packs are installed by copying files. In-app installation is deferred until there is something to install.
- Development and testing happen on the maintainer's Kindle first; Kobo testing comes later (a Kobo is available through a third party).
- Desktop tests are plain `luajit` scripts, no test framework dependency.
- Scope of this repository: the engine plus one example character, a generic Frankenstein's-monster-style character. Other characters live in their own repositories with their own licenses.

- Licenses: MIT for code, CC BY 4.0 for the bundled example character's art and phrases.
