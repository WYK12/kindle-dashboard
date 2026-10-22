# 更新日志

## 2.53-list-spacing — 2026-10-22

- **首页行情**：拉开行情行距，调整品种、报价、涨跌与数据时间的对齐；日期和时间两行之间增加留白。
- **行情详情**：增加报价、数据来源说明和分隔线之间的间距，避免文字贴线；翻页及更新按钮下移。
- **自选管理**：增加列表行距与操作区域的留白，保留上移、下移和移除操作。
- **横竖屏一致**：两种方向分别适配间距，保留原有字号与粗体，每页最多显示 6 个行情品种。
- **验证**：通过本地语法、启动恢复和排版检查，以及 Kindle 原生字体下的横竖屏、有数据和空列表检查；实机确认行情详情、自选管理和返回首页可正常点按。

## 2.52-unified-direction — 2026-10-22

- **书库与阅读统一方向**：从看板进入的 KOReader 书库、搜书、书籍和文章阅读跟随“设置 → 看板方向”。
- **修复横屏朝向相反**：书库和阅读器与看板使用相同的实际朝向，切换页面后无需再转动设备。
- **横屏搜书适配**：加宽拼音输入框，使用紧凑键盘，让候选词、取消、首页和搜索按钮完整显示。
- **保留阅读设置**：方向锁定及紧凑键盘仅用于本次从看板启动的阅读器进程，不覆盖已保存的方向锁定、键盘或单本书方向偏好；独立启动 KOReader 保留原有行为。
- **验证**：实机检查书库、搜书、EPUB 翻页、快捷返回与竖屏切换，恢复测试前的正文阅读位置；文章返回按钮通过原生字体离屏检查，未进行本轮文章或 PDF 的完整实机阅读测试。

## 2.51-landscape-pages — 2026-10-22

- **看板各页横屏**：天气、7 天预报、逐小时天气、行情、自选管理、热点、日历、待办、设置、城市搜索及输入键盘统一跟随方向设置，切换立即生效。
- **按横屏重新排版**：加宽行情和天气表格，热点与设置采用双栏，常用选项采用多列；列表页容量及原有返回路径保持一致。
- **文字与操作区域适配**：返回按钮、提示、加载反馈和键盘局部刷新区域跟随屏幕尺寸；长文字只绘制完整行，避免露出半行字。
- **减少切换误触**：首次画面绘制后丢弃切换期间排队的旧触摸事件，避免从书库返回后又误触底部入口。
- **验证**：检查横竖屏有数据和空页面、触摸范围、翻页、自选排序、六行月份日历、键盘与局部刷新，并完成实机页面切换检查。

## 2.50-landscape-dashboard — 2026-10-22

- **新增首页横屏**：时钟和天气位于上方，行情与热点左右排列，底部保留五个快捷按钮；方向选择可保存。
- **旋转与点按同步**：看板画布、触摸坐标及局部刷新区域一同适配横屏，保留原有数据更新周期。
- **原生状态栏处理**：看板运行时暂停独立的原生状态栏绘制，正常退出时恢复，避免时钟等原生元素覆盖看板。
- **验证**：检查横竖屏有数据和空首页、6 行行情、触摸坐标、局部刷新及书库返回；后续版本继续扩展了详情页与阅读器横屏范围。

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
