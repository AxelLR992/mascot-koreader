# CLAUDE.md

Guidance for working on this repository.

## Project

`mascot-koreader` is a KOReader plugin (Lua) that shows a companion character reacting to what the user reads.
Characters are **data-only packs** (JSON + sprites + locales) loaded by a generic engine. Two brains produce dialogue:
an **offline** brain (keyword signals + templates, no network) and an optional **online** brain (user-provided LLM API key).
See `PLAN.md` for the roadmap and `README.md` for the overview.

## Hard constraints

- **Original work.** The codebase is written from scratch. Ideas may be borrowed from other projects, but no code, assets,
  phrase banks or names from them are copied. Do not reference or reuse the Silverfish plugin.
- **English only** in code, identifiers, comments, docs, commit messages and file names.
- **One active character at a time.** No multi-character simulation.
- **No growth or evolution.** Characters have a fixed identity. They may have moods and drifting personality axes, but no life stages.
- **Packs are data, never code.** The engine must not execute anything from a character pack.
- **Offline is the default and must always work.** The online brain is an opt-in upgrade and must fall back silently to offline on any failure.
- **Never block reading.** No synchronous network calls, no heavy work on the UI path.
- **Privacy.** Nothing leaves the device unless the user has explicitly enabled online mode, and the opt-in screen must list what is sent.
- **Targets:** KOReader on Kindle (jailbroken) and Kobo. Also keep Simple UI compatibility in mind (the maintainer's Kindle uses it).

## Conventions

### Changelog
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- Keep an `## [Unreleased]` section at the top and add entries there as part of the change that causes them.
- Use the standard groups: Added, Changed, Deprecated, Removed, Fixed, Security.

### Versioning
- [Semantic Versioning](https://semver.org/). The version lives in one place (the plugin's `_meta.lua`) and is mirrored in `CHANGELOG.md` headings.
- Pack format changes: bump a separate `schema_version` in `character.json`, and treat breaking schema changes as a MAJOR bump of the plugin.

### Commits
- [Gitmoji](https://gitmoji.dev/) commit messages: an emoji (the character, not the `:code:`) followed by an imperative summary,
  e.g. `✨ Add pack loader`, `🐛 Fix slot filling for empty locales`, `📝 Update README`, `🎉 Initial commit`.
- Keep the subject under about 72 characters. Add a body when the *why* is not obvious.
- Do not commit unless asked.

### Code
- Lua, targeting the LuaJIT bundled with KOReader. No external native dependencies in the offline path.
- Keep pure logic (signals, state, brains, pack validation) free of KOReader requires so it can be tested on a desktop with plain `lua`/`luajit`.
- KOReader-specific glue stays in `main.lua` and a small number of adapter modules.
- Match the surrounding code's style, naming and comment density.

## Layout (planned)

```
mascot.koplugin/
  _meta.lua
  main.lua
  engine/        signals, state, brains, pack loader
  characters/    one directory per character: character.json, sprites/, locales/
docs/            pack authoring guide, schema reference
tests/           desktop-runnable tests for the pure logic
```

## Open questions
Track unresolved decisions in `PLAN.md` under "Decisions", not here.
