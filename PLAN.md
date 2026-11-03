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
  mascot/                  engine modules, namespaced (require("mascot.signals")) so they cannot
                           collide with modules of other plugins on KOReader's package.path
    tokenizer.lua          page text -> lowercase words
    signals.lua            words -> signals (keyword counts, tone, rhythm, dialogue)
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
tests/                     desktop-runnable tests for the pure logic (luajit tests/run.lua)
```

Pure logic (everything under `mascot/` except adapters) must not require KOReader modules so it can be tested on a desktop.

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

### Phase 0: Spike (done for Kindle; see findings)
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

## Phase 0 findings

Measured with `spikes/mascotspike.koplugin`. Phase 0 is complete for the Kindle; Kobo and PDF are deferred.

| Check | Emulator (KOReader 2026.07.2) | Kindle Basic 4 (KOReader 2026.03) |
|---|---|---|
| Plugin loads, menu entry (Tools > More tools) | yes | yes |
| Device facts | 1072x1364, 300 dpi | 1072x1448, 300 dpi, LuaJIT arm, ~210 of 474 MB RAM available |
| Settings persist across restarts | yes | yes |
| Suspend and resume events reach the plugin | not tested | yes |
| Page and reader-ready events reach the plugin | yes | yes (13 page turns, 1 ready) |
| Page text, reflowable | ~750 chars/page, 2.3 ms average per page turn | ~700 chars/page, **29 ms average per page turn** (1 ms for a single call) |
| HTTPS from a subprocess, UI not blocked | 200 OK in 333 ms | 200 OK in 516 ms, UI loop kept ticking (3 ticks, 2.6 expected) |
| Sprite at integer scale | crisp nearest-neighbour edges, alpha works | identical to the emulator: crisp edges, alpha works |
| Simple UI detected | no (not installed) | yes |

Consequences for the design:
- **Page text is cheap but not free.** About 29 ms per page turn on the Kindle. Do not extract text synchronously in the page-turn handler: schedule it shortly after the turn, and only for pages the user dwells on (the plan already counts a page only after a few seconds).
- **HTTPS works** with `ssl.https` in a subprocess through `Trapper`, so the online brain is feasible. Latency is around half a second for a tiny request, so LLM calls must be asynchronous and cached.
- **Memory.** About 210 MB of RAM is free on the Kindle. The Lua heap read 164 MB in the file manager (with Simple UI's home screen) and 17 MB inside a book, so the large figure is a file-manager effect, not a baseline. Keep Mascot to a few MB.
- **Target KOReader 2026.03** as the minimum. The Kindle runs it, and it is older than the emulator build.
- The "launches" counter increments on every plugin instantiation (file manager and each opened book), not once per KOReader start. Do not use plugin `init` as a "session started" signal.

Deferred:
- PDF/DjVu page text (code path exists in the spike, untested on either platform).
- Kobo (waiting for a device).
- The Simple UI card integration (Phase 3).

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
