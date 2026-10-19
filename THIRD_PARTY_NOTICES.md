# Third-party notices

## KOReader

- Project: https://github.com/koreader/koreader
- License: GNU Affero General Public License, version 3 (AGPL-3.0)
- Tested installation: v2026.07.1, Kindle Paperwhite 3
- Upstream license: https://github.com/koreader/koreader/blob/master/COPYING

`src/koreader/koreader.sh` is a modified copy of the launcher distributed with the tested KOReader installation. The original KOReader contributors retain their copyrights. Dashboard changes preserve native UI ownership during reader-to-dashboard handoffs, avoid unnecessary service restarts for managed readers, and retain dashboard-owned USB storage protection. These changes are identified by the `MYDASH_*` environment variables and handoff comments.

The plugins and patches use KOReader's interfaces, rendering, document handling, bundled Lua libraries and keyboard data. Those dependencies are supplied by an existing KOReader installation and are not vendored here.

## FBInk and system resources

- FBInk: https://github.com/NiLuJe/FBInk
- System Chinese font: supplied by the user's Kindle firmware.

The dashboard calls the FBInk binary already included with the tested reader installation and uses a font already present on the device. Neither is redistributed in this repository or release ZIP.

`gbk.map` is the GBK-to-UTF-8 encoding lookup table used by the market parser; it contains encoding data, not a font or a dictionary of book content.

## External content

Public websites and APIs provide weather, quotes, hotlists, book metadata and article content at runtime. The software license does not license those third-party materials. This repository and its release ZIP contain no electronic books or downloaded article bodies.
