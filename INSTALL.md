# 安装与恢复

本版只在 README 列出的 Paperwhite 3 环境验证。它修改的是自定义首页与 KOReader 集成，不是 Kindle 固件升级包。

## 1. 检查环境

需要已越狱的 Paperwhite 3、KOReader v2026.07.1，以及 KMC 的 KOReader 启动入口。下列设备路径应存在：

```text
/mnt/us/koreader/luajit
/mnt/us/koreader/fbink
/mnt/us/koreader/frontend/ui/data/keyboardlayouts/zh_pinyin_data.lua
/mnt/us/kmc/kpm/packages/koreader/launch.sh
/usr/java/lib/fonts/STHeitiBold.ttf
```

当前启动脚本直接调用 KMC 的路径。若你的 KOReader 安装方式不同，需要先适配 `mydash_v2/run.sh` 中的启动入口。本版不提供越狱工具，也不自动安装 KOReader 或 KMC。

## 2. 退出阅读器并备份

先正常退出 KOReader，让阅读进度保存，再连接电脑进行文件传输。把以下现有文件保存到电脑：

- `koreader/koreader.sh`
- `koreader/settings.reader.lua`、`koreader/history.lua`
- `koreader/plugins/mydashbooks.koplugin/`、`mydashrss.koplugin/`（若存在）
- `koreader/patches/2-mydash-bold-ui.lua`、`2-mydash-keep-awake.lua`、`2-mydash-direction.lua`（若存在）
- `mydash_v2/` 和 `emergency.sh`（若已使用旧版看板）

## 3. 合并安装文件

Release 安装 ZIP 根目录包含 `mydash_v2/` 和 `koreader/`。将它们合并复制到 Kindle 根目录，保留原有 KOReader 的其他文件。

如果使用 GitHub 的源码 ZIP，这两个目录位于 `src/` 下。首次安装时还需要：

1. 将 `config.example.json` 复制为 `mydash_v2/config.json`。
2. 将 `markets_config.example.json` 复制为 `mydash_v2/markets_config.json`。

安装 ZIP 已生成这两个默认配置。升级已有安装时，保留自己的 `config.json`、`markets_config.json`、`todos.json` 与缓存，避免被示例配置覆盖。

`koreader/koreader.sh` 是针对已验证版本的修改版，不适合直接覆盖未知版本。若你已有其他启动脚本改动，请先比较差异。字体、常显和方向补丁也只应与已验证版本配合使用。

## 4. 首次启动

安全弹出 Kindle 磁盘并拔掉数据线。退出到原生首页，确保 KOReader 未在运行；在设备终端或已经配置好的 SSH 中执行：

```sh
nohup sh /mnt/us/mydash_v2/run.sh >/mnt/us/mydash_v2/launch.log 2>&1 </dev/null &
```

首次启动没有联网缓存时，会先显示空数据并在后台获取。进入设置可修改城市、前光、首页常显和看板方向（横屏 / 竖屏）；行情看板中可调整自选品种与顺序。天气、行情、热点、日历、待办、设置和输入键盘均跟随看板方向，切换立即生效；从看板进入的 KOReader 书库、搜书、书籍和文章阅读也跟随同一方向；独立启动 KOReader 保留原有方向设置。旋转后页码和总页数会重新计算，正文位置由阅读器保存。将自己的书放入 `/mnt/us/Books/`，即可使用书库和继续阅读。

## 5. 开机自启

首发包默认禁用自启。确认手动启动、阅读和返回都正常后，再从设置开启。

自启依赖系统现有的 KMC `emergency.sh` 钩子，并在开机后等待 45 秒。程序会检查已有钩子归属；遇到不属于本项目的 `emergency.sh` 时会保留它，不自动覆盖。

在 Kindle 根目录放置一个名为 `MYDASH_SAFE_MODE` 的空文件，可阻止本项目的开机自启。

## USB 连接

看板运行时及受管阅读器会暂停 USB 存储模式，防止程序所在分区被电脑接管。此时连接电脑用于充电，电脑可能看到无可用介质的 Kindle 设备。

需要传文件时，先从看板设置进入“原生首页”，再连接电脑；如数据线已连接，可拔下后重插。传输完成后从电脑安全弹出，再启动看板。

## 退出、恢复与卸载

- 正常退出：看板设置 → 原生首页。
- 停止首页：若已配置 SSH，执行 `sh /mnt/us/mydash_v2/stop.sh`。该命令只负责首页，不应拿它强制终止正在保存的阅读器。
- 关闭自启：在 `mydash_v2/` 内创建 `DISABLE_AUTOSTART`，或在根目录创建 `MYDASH_SAFE_MODE`。
- 恢复上游启动方式：退出看板和阅读器后，还原备份的 `koreader.sh`，移除本项目的两个插件和三个补丁。
- 移除看板：关闭自启并恢复 KOReader 后，删除 `mydash_v2/`。书籍目录 `Books/` 和文章目录 `RSS/` 是单独的数据目录，可按自己的需要保留。

若画面停住，先确认后台是否仍有首页或阅读器进程。USB 存储模式中留下的墨水屏画面，并不代表界面进程还在运行。
