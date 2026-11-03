# Development

## Desktop emulator

KOReader ships a desktop emulator (SDL). We build it once outside this repository and symlink the plugin into it.

### Prerequisites (Debian/Ubuntu/Mint)

```
sudo apt install autoconf automake build-essential ca-certificates cmake gcc-multilib gettext git \
    libtool libtool-bin meson nasm ninja-build patch pkg-config unzip wget luajit

# SDL3 is built by KOReader and needs window-system headers:
sudo apt install libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev \
    libxtst-dev libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev libdrm-dev libgbm-dev \
    libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev libdbus-1-dev libudev-dev libasound2-dev libpulse-dev
```

### Build KOReader

```
git clone https://github.com/koreader/koreader.git ~/Projects/koreader
cd ~/Projects/koreader
./kodev fetch-thirdparty
make TARGET= KODEBUG=1 PARALLEL_JOBS=1 NINJAFLAGS=-j"$(nproc)"
```

Do not use plain `./kodev build` on a system with GNU make older than 4.4 or ninja older than 1.13
(for example Ubuntu 24.04 and Mint 22). It fails in the first autotools dependency with
`make: *** read jobs pipe: Bad file descriptor`, because the nested `make` inherits a jobserver that ninja
did not pass on. Running `make` directly with `PARALLEL_JOBS=1` (no make jobserver) and the ninja job count
set through `NINJAFLAGS` avoids it. `kodev build` does not accept these variables, which is why we call `make`.

The result is `~/Projects/koreader/koreader-emulator-<arch>-debug/`.

### Run the plugin

```
scripts/dev-run.sh
```

This symlinks `mascot.koplugin` into the emulator's `koreader/plugins/` and starts it with the
Kindle Paperwhite screen size. Pass other `kodev run` options after it, e.g. `-s kobo-clara`.
Restart the emulator to pick up Lua changes. Set `KOREADER_DIR` if KOReader lives elsewhere.

In the emulator, open the top menu, then the tools (gear) menu, then **Mascot**.

## Tests

Pure logic is tested on the desktop with plain `luajit`, with no KOReader and no framework:

```
luajit tests/run.lua
```

It runs every `tests/test_*.lua` and exits non-zero if any test fails. Helpers are in `tests/lib.lua`
(`T.test`, `T.eq`, `T.throws`). Test locales live in `tests/fixtures/`.

## Real device

Copy `mascot.koplugin` to `koreader/plugins/` on the device (USB, or the `filesync` plugin) and restart KOReader.
The log is `koreader/crash.log`.
