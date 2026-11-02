# mascot-koreader

A companion character for [KOReader](https://github.com/koreader/koreader) that lives on your e-reader and reacts to what you read.

> **Status:** planning. Nothing is implemented yet. See [PLAN.md](PLAN.md).

## Idea

- **Extendable.** Every character is a self-contained directory (a *pack*): sprites, a personality definition, and per-language phrase banks. Drop a new pack in and it shows up. No code required.
- **One active character at a time.** Pick whoever you like.
- **Offline by default.** The character reads the pages you read, extracts simple signals (themes, tone, names, events, time of day) and speaks from hand-written phrases. No network, nothing leaves the device.
- **Optional online mode.** Bring your own API key for an OpenAI-compatible LLM endpoint (low-cost or free models work) and the character writes its lines live. If anything goes wrong, it falls back to offline.
- **Multilingual.** Each pack has a `locales/` directory; pack authors decide which languages to support.

## Targets

KOReader on a jailbroken Kindle and on Kobo. Compatible with the Simple UI plugin.

## Planned pack layout

```
characters/<name>/
  character.json     identity, personality axes, reaction rules, triggers
  sprites/           images for each mood
  locales/
    en.json          phrases, keywords, persona prompt for the online brain
    <code>.json
```

Packs are plain data. The engine never runs code from a pack.

## Roadmap

See [PLAN.md](PLAN.md).

## Contributing

Conventions (Keep a Changelog, Semantic Versioning, gitmoji) are described in [CLAUDE.md](CLAUDE.md).

## License

- Code: [MIT](LICENSE).
- Bundled example character (art and phrases): [CC BY 4.0](LICENSE-ART.md).

Characters distributed in other repositories carry their own licenses.
