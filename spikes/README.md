# Spikes

Throwaway plugins used to check assumptions on real devices before building on them. They are not part of the product and are deleted once their findings are in `PLAN.md`.

## mascotspike.koplugin (Phase 0)

Adds **Tools > Mascot spike** with six checks:

| Item | What it verifies |
|---|---|
| 1. Report | Device, screen, RAM, TLS availability, other plugins installed, and all results so far |
| 2. Read current page text | Page text can be read (reflowable and PDF), and how long it takes. Also sampled on every page turn |
| 3. Settings persistence | A counter in `settings/mascot-spike.lua` grows by 1 on every KOReader restart |
| 4. HTTPS request | `https://example.com/` can be fetched from a subprocess, and the UI loop keeps running meanwhile |
| 5. Draw sprite | A 16x16 PNG is drawn at 8x. Crisp edges mean nearest-neighbour scaling |
| Reset counters | Clears the page-turn samples and resets the launch counter |

### Install on a device

Copy the folder `spikes/mascotspike.koplugin` to KOReader's `plugins/` directory (USB or the `filesync` plugin) and restart KOReader.

### Procedure

1. Open a **reflowable book** (EPUB), turn about 10 pages, then run item 2.
2. Run items 4 and 5.
3. Restart KOReader, run item 3, and check the counter went up by 1.
4. Put the device to sleep, wake it, and run item 1 (the events line shows `suspend` and `resume` counts).
5. Optionally open a PDF and run item 2 again.
6. Run item 1 and send the report.
