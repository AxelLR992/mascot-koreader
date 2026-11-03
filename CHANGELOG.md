# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project scaffolding: `README.md`, `PLAN.md`, `CLAUDE.md` and this changelog.
- MIT license for the code and CC BY 4.0 for the bundled example character.
- Minimal `mascot.koplugin` skeleton with a "Mascot" entry in the tools menu.
- Phase 0 spike plugin (`spikes/mascotspike.koplugin`) that checks page text, settings, HTTPS, sprites and events on a device.
- Engine: UTF-8 tokenizer and locale-driven signal extraction (`mascot.tokenizer`, `mascot.signals`), with a dependency-free test runner (`luajit tests/run.lua`).
- Engine: persistent character state (`mascot.state`): once-per-position page counting, decaying theme scores with an obsession, personality axes driven by pack-defined effects, per-book totals, daily counts and streaks.
- Draft of the character pack format (`docs/PACK_FORMAT.md`).
- Desktop emulator workflow: `scripts/dev-link.sh`, `scripts/dev-run.sh` and `docs/DEVELOPMENT.md`.
