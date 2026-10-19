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
