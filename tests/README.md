# Tests

## Host regression checks

Linux with Python 3, Pillow, `liblua5.3` and the Noto Sans CJK Bold font installed. Point `MYDASH_KOREADER_COMMON` to an existing KOReader checkout's `common/` directory (for `dkjson.lua`):

```sh
MYDASH_KOREADER_COMMON=/path/to/koreader/common python3 tests/test_fullscreen.py
```

The script compiles Lua/shell sources, runs native-ownership and launcher lifecycle checks with mocked services, verifies USB ownership during reader handoffs, and checks populated/empty layouts and touch targets. Generated images and logs go into the ignored `artifacts/` directory. It does not connect to a Kindle.

## Native Lua checks

`test_reading.lua` uses a mocked book history. `test_news.lua` uses synthetic publisher payloads and needs KOReader's HTML parser and JSON library on `LUA_PATH`. Neither test needs live book downloads.

After copying tests to a device, from its KOReader directory:

```sh
MYDASH_ROOT=/mnt/us/mydash_v2 \
LUA_PATH='/mnt/us/mydash_v2/?.lua;/mnt/us/koreader/common/?.lua;;' \
./luajit /path/to/tests/test_reading.lua

MYDASH_ROOT=/mnt/us/mydash_v2 \
LUA_PATH='/mnt/us/mydash_v2/?.lua;/mnt/us/koreader/common/?.lua;;' \
./luajit /path/to/tests/test_news.lua

./luajit /path/to/tests/device_input_wait.lua
./luajit /path/to/tests/device_keep_awake.lua /mnt/us/koreader/patches/2-mydash-keep-awake.lua
```

The input check tests the actual kernel wait with a pipe, without injecting touchscreen events. The keep-awake check substitutes power operations and uses the installed AutoSuspend implementation.

Real-device verification is still needed for screen quality, touch routing, reader progress saving, USB replugging and model/firmware compatibility. Short CPU samples are not battery-life benchmarks.

## Frontlight controls

Render all pages with native device fonts and exercise the real settings callbacks using isolated brightness controls:

```sh
MYDASH_ROOT=/mnt/us/mydash_v2 \
LUA_PATH='/mnt/us/mydash_v2/?.lua;/mnt/us/koreader/common/?.lua;;' \
MYDASH_RENDER_OFFSCREEN=1 \
./luajit /path/to/tests/device_frontlight.lua
```

This checks the stock minimum versus off, repeated off, increase/decrease, bounds and control/readback failures without changing live brightness or touching the screen. To additionally execute the real turn-off callback on a Paperwhite 3, set `MYDASH_TEST_LIGHT_OFF=1`; this deliberately leaves its frontlight off and writes an offscreen preview to `/var/tmp/mydash-frontlight-off.png`.

## Persistent power queries

Run `device_power_reads.lua` with the same `MYDASH_ROOT`, `LUA_PATH` and `MYDASH_RENDER_OFFSCREEN=1` settings as the frontlight check. It exercises typed reads, zero values, one reused connection, command fallback and clean close with isolated LIPC calls. It does not alter live power state.

## Batched refresh

With the dashboard on `LUA_PATH`, run `test_refresh.lua` for semantic comparisons, shared timing, due-only requests, persisted failure backoff, manual retries and recovery. It replaces data/network operations and does not download content.

Run `device_refresh_ui.lua` on a configured device with `MYDASH_RENDER_OFFSCREEN=1` and `MYDASH_HOME_FILE=/mnt/us/mydash_v2/home.lua`. It uses copies of existing weather, market and hotspot caches, mocks writes/network calls, and checks actual cache-to-render decisions. Populated caches are required; it does not touch live input, network state or saved settings.

## Partial homepage refresh

The host renderer checks cover no timer-only flashes, manual/page-change ghost clearing, hotspot-only damage bounds and current-article clicks. `device_partial_hotspots.lua` runs the same path offscreen with native device fonts and synthetic headlines, preserving live screen/input/settings. Use `MYDASH_RENDER_OFFSCREEN=1` and the normal dashboard `LUA_PATH`. It writes before/after PNGs to `/var/tmp/mydash-partial-{before,after}.png` for pixel comparisons outside the hotspot rectangle.

## Landscape dashboard pages

From the device's KOReader directory, run:

```sh
MYDASH_ROOT=/mnt/us/mydash_v2 \
LUA_PATH='/mnt/us/mydash_v2/?.lua;/mnt/us/koreader/common/?.lua;;' \
MYDASH_RENDER_OFFSCREEN=1 \
MYDASH_HOME_FILE=/mnt/us/mydash_v2/home.lua \
./luajit /path/to/tests/device_landscape.lua
```

This uses synthetic headlines/quotes and isolated settings, write and command callbacks. It checks populated and empty layouts in both orientations with native fonts, all text/touch bounds, raw physical touch mapping, six market rows, padded-stride rotated blits, immediate saved orientation toggles, page returns, six-row calendars, list pagination, watchlist reordering, partial keyboard typing/case changes, complete-line text clipping, pending-input draining with a real nonblocking pipe, current-article selection and physical hotspot refresh bounds. PNGs are written to `/var/tmp/mydash-landscape-{before,after,stride,empty}.png`; the before and stride images must be pixel-identical, and before/after differences must stay inside the logical hotspot rectangle `(976, 372, 424, 512)`. Per-page landscape previews are written to `/var/tmp/mydash-wide-*.png`. Live library/dashboard handoff and display quality need a separate device check. The standalone frontlight/calendar/hotspot checks explicitly use isolated portrait settings so they remain independent of the device’s saved direction.

## Unified native reader direction

Run `test_reader_direction.lua /path/to/2-mydash-direction.lua` with Lua/LuaJIT and `dkjson` on `LUA_PATH`. It checks managed portrait/landscape selection, native sticky-rotation queries, landscape keyboard compactness, saved preference preservation, malformed/missing config and standalone-reader isolation.

On a device, set `MYDASH_TEST_NATIVE_ROTATION=1` and run from KOReader's directory (with its `common/` directory on `LUA_PATH`) to additionally check the actual framebuffer rotation against the dashboard's physical top-left. This uses an isolated buffer and does not rotate the live display. Library, keyboard, reading gestures and progress preservation need a live check.
