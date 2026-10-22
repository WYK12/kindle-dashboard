# Changelog

## 2.53-list-spacing

- Increase spacing between homepage quote rows and separate the two timestamp lines in both orientations.
- Give quote details and watchlist rows more room, with pagination controls below the list. Six items remain visible per page.

## 2.52-unified-direction — 2026-10-22

- Follow dashboard direction in the managed KOReader library, search dialogs, books and articles, using native sticky-rotation queries without writing rotation-lock or per-book rotation preferences.
- Map dashboard BlitBuffer rotation1 to KOReader counter-clockwise mode3, keeping their physical top-left corners aligned.
- Use a wide pinyin search dialog and compact native keyboard in landscape so candidate/action rows remain visible; saved keyboard preferences remain unchanged.
- Leave standalone KOReader sessions unchanged. Verify native framebuffer mapping, portrait/landscape selection, unmanaged isolation and saved preference preservation.

## 2.51-landscape-pages — 2026-10-22

- Apply the saved dashboard direction to every custom page: forecasts, quotes/watchlist, hotlists/details, calendar, tasks, settings, city/search results, feed management and keyboard.
- Reflow wide pages with readable fonts, wider tables, two-column hotlists/settings and three-column preset grids. Preserve list page sizes, item order and return paths.
- Position back buttons, notices, loading feedback and partial keyboard redraws using the active canvas geometry; direction switches take effect immediately in settings.
- Stop text at complete lines when a box is full, avoiding clipped half-lines in long summaries.
- Discard input queued before the first dashboard frame on startup/wake, preventing the outgoing library gesture from also activating a landscape footer action.
- Keep KOReader library/reading direction independent; returning restores the dashboard direction.
- Verify populated/empty pages in both orientations with native fonts, touch bounds, pagination, item reordering, calendar six-row months, keyboard typing/case changes and partial hotspot damage.

## 2.50-landscape-dashboard — 2026-10-22

- Add a persisted homepage orientation setting; landscape lays out clock/weather above market quotes and publisher hotlists in two columns, with five bottom actions.
- Rotate the dashboard canvas and raw touch mapping together without changing framebuffer/kernel or KOReader orientation; custom details remain portrait and home restores the selected orientation.
- Map partial refresh rectangles to physical screen coordinates, retaining headline-only updates and the existing refresh schedule.
- Pause the independent PW3 Juno status bar while the dashboard owns the screen, retain ownership through reader handoffs, and resume it on normal native exit.
- Verify populated/empty native layouts, six quote rows, padded framebuffer stride, touch mapping, settings persistence, portrait details and live library/home returns.

## 2.49-partial-hotspots — 2026-10-22

- Remove the fixed ten-minute full-screen ghost-clearing flash while staying on a page; retain startup, manual and accumulated page-change clearing.
- Redraw only the homepage hotspot area on headline rotation, preserving clock, quotes, separators and footer.
- Keep existing touch regions and resolve article clicks against the currently displayed headline.

## 2.48-batched-refresh — 2026-10-20

- Coordinate weather, market and hotspot refreshes through one locked worker on shared five-minute slots, fetching only due categories.
- Preserve normal category intervals; progressively delay failed categories up to an hour (or their longer configured interval), retaining cached data and retry state across homepage restarts.
- Keep manual refresh immediate and reset backoff after recovery.
- Ignore fetch-only timestamp changes when deciding to repaint. Publish batch results together, update only affected pages, and avoid repeating identical error repaints.
- Use independent temporary download files for city searches and the batch worker.
- No Wi-Fi toggling or additional sleep behavior is introduced. Battery runtime has not been measured.

## 2.47-power-queries — 2026-10-20

- Reuse one native LIPC connection for homepage power-state, battery and frontlight reads, avoiding recurring query subprocesses.
- Retain command fallback when the library or a property is unavailable, and close the handle on exit.
- Keep clock, network update intervals, touch waits and keep-awake behavior unchanged. This reduces query overhead; no battery runtime improvement has been measured.

## 2.46-frontlight-off — 2026-10-20

- Add a separate turn-off button beside the settings brightness controls.
- On Paperwhite 3, write hardware brightness to zero after setting the stock level to zero, matching KOReader’s frontlight handling.
- Distinguish the stock minimum level from fully off; verify the zero readback and report control failures.
- Decreasing brightness to zero also turns the LEDs off; increasing brightness turns them back on.
- Check native settings callbacks, repeat off, brightness bounds, command/readback failures and actual hardware zero without interrupting the reader.

## 2.45-reader-home — 2026-10-19

Initial public source release, based on the version tested on Kindle Paperwhite 3.

- Custom home with clock, weather, sortable market watchlist, rotating publisher hotlists and five bottom actions.
- Calendar, forecasts, to-dos, library and continue-reading integration.
- Native house icon on reflowable book and generated-article reading headers, returning directly to the dashboard through KOReader's normal save/exit path.
- Existing left-header library/hotlist return controls retained.
- USB storage inhibition retained across dashboard/reader handoffs, with restoration on normal exit.
- Event-driven idle input wait, bold UI, minute clock refresh and owned keep-awake handling.
- Public package contains example settings and source only; no device logs, connection credentials, books or reading history.
