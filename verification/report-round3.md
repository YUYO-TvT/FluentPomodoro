# FluentPomodoro 第三轮独立复核报告（4 项新功能 + 回归）

- 复核对象：`C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro`（**冻结版本**）
- 复核方式：先自行核对 10 个冻结哈希 → 独立编译 → 独立单文件发布（`verify-dist-r3`）→ 全部测试只针对**我自己的产物** `verify-dist-r3\FluentPomodoro.exe`，通过真实 UI 自动化（Win32 `EnumWindows` 窗口定位、`keybd_event`/真实鼠标、UI Automation `InvokePattern`/`TogglePattern`/`RangeValuePattern`、原生文件对话框剪贴板输入、屏幕像素读回 + `PrintWindow`、进程 CPU 时间采样）取观测值。
- 复核环境：Windows 11 build 26300、.NET SDK 10.0.401 / 8.0.425、PowerShell 7、单显示器 1920×1080 @ 96 DPI、虚拟桌面 `1920x1080 @ (0,0)`、中文输入法可用。
- **本轮未修改任何应用源代码**；全部新增内容位于 `verification\r3\`。
- 本轮**没有任何外部对照产物**：所有"通过"结论均来自我自己从冻结源码发布的 `verify-dist-r3`。
- 测试期间跨越了本地午夜（首轮外壳时间 `2026-10-04 23:59`，应用侧 `DateTime.Today` = **2026-10-05**）。为此我在统计窗口测试里改为**从应用界面反推应用自己的日历日**，而不是相信外壳时钟，避免把午夜翻转误判成应用缺陷（详见 4.C.0）。

---

## 1. 结论

**四项新功能全部独立复现确认可用（CONFIRMED），未发现任何新增功能缺陷，也未发现回归。**

- **功能 1（圆环内可选当前时间时钟）**：确认。`HH:mm:ss` 文本、每秒刷新、位置在圆环内且与大字计时器同一水平轴；开启时两次间隔 3.2s 的抓屏**只有时钟区域**的像素变化（PrintWindow 与真实屏幕抓屏两种方式都做了），关闭后同样的抓屏对**逐像素完全相同**，重启后仍保持关闭。
- **功能 2（专注统计窗口）**：确认。标题栏按钮与 `Ctrl+I` 两条路径都能打开；矩阵实测为 **53 列 × 7 行**，365 个可见格心**全部**精确落在 `Palette.Light.xaml` 的 6 个 `Heat*Brush` 颜色上；按 6 个等级统计的格数与我按边界值（0/1/24/25/49/50/99/100/199/200/500）自己算出的分桶数**逐级相等**；悬停格子的 tooltip 文本与 `history.json` 该日分钟/番茄数一致；6 张汇总卡片的数值与我自行计算的值**全部一致**；`导出 CSV` 写出的 17 行与我自己的推导**逐行相同**。
- **功能 3（背景图片）**：确认。真实文件对话框选图/选文件夹都能用；红/蓝单图下背景与主按钮色调随图片主色改变，且主按钮采样值与我按源码算法**独立重算的预期值逐通道完全相同**（浅色+红 `(173,61,55)`、浅色+蓝 `(55,104,173)`、深色+红 `(224,96,90)`）；不透明度滑块真实改变图片强度；"清除"精确回到 `(243,243,243)` 主题底色；路径与设置重启后保留；`每次开始专注时换一张` 与 **5 分钟定时轮换（实测在 t=301.5s 触发，此时计时器并未运行）** 都真实生效；深色主题 + 红图时窗口仍为深色（条纹平均亮度 0.143 vs 浅色 0.736）而强调色仍为红且**按主题自适应**（不与浅色逐字相同）。
- **功能 4（白噪音）**：确认。导入/列表/设置持久化、音量滑块、随机播放、下一首（单曲循环与双曲切换）、"开始专注自动播放"+"仅专注阶段播放"（播放/暂停状态由标题栏按钮像素与设置面板状态文本双重确认）、标题栏播放/暂停按钮、单曲循环、缺失文件与损坏文件的容错都通过；损坏文件会弹出失败提示且**不空转**（8s 空闲窗口 CPU 增量 0.62s / 0.02s，对照基线 0s），窗口全程可响应，并且能与好文件共存时**自动落到可播放的那一首**。
- **回归**：确认。含 4 组新字段的 **32 个设置项往返零差异**；坏的新字段（类型错误/越界）不丢其余字段；强制大屏仍铺满虚拟桌面并拦截最小化、Esc 精确还原 640×780；1 分钟专注完成的 4 个计数器仍然**恰好加一次**。

**本轮共执行 223 项检查，223 项通过，0 项失败，0 个新增缺陷。**

| 脚本 | 覆盖 | 结果 |
|---|---|---|
| `00-smoke.ps1` | 产物完整性/启动/窗口定位/抓屏通路 | 11/11 |
| `02-clock.ps1` | 功能 1（PrintWindow 路径） | 19/19 |
| `08-extras.ps1` | 功能 1（真实屏幕抓屏路径）+ 非刻度不透明度探针 | 8/8 |
| `03-stats.ps1` | 功能 2（矩阵/等级/tooltip/卡片/CSV） | 43/43 |
| `04-history.ps1` | 功能 2 数据链路（真实 1 分钟专注） | 21/21 |
| `05-background.ps1` | 功能 3 | 37/37 |
| `06-noise.ps1` | 功能 4 | 37/37 |
| `07-regression.ps1` | 回归（设置/容错/大屏/计数） | 26/26 |
| `09-probes.ps1` | 额外探针（轮换映射/音量/缺失文件/随机/坏 history） | 15/15 |
| `10-rotation.ps1` | 功能 3 定时轮换（5 分钟真实等待） | 6/6 |

---

## 2. 冻结版本核对

用任务给定的命令 `(Get-FileHash <file> -Algorithm SHA256).Hash.Substring(0,16)` 逐一核对，**10/10 全部一致**；测试开始前（`2026-10-04T23:49:32`）与全部测试结束后（`2026-10-05T00:32:47`）各核一次，两次结果**逐字节相同**，说明测试期间源码未被改动。

```
=== 冻结哈希核对（开始前 23:49:32 与结束后 00:32:47，两次完全一致）===
771CFB4DAECA512B  MainWindow.xaml.cs          (期望 771CFB4DAECA512B)
0A6C10BDD6F89E8F  MainWindow.xaml             (期望 0A6C10BDD6F89E8F)
F0EAB427B3F2B428  StatsWindow.xaml            (期望 F0EAB427B3F2B428)
E54EFDFEA9EEDA1C  StatsWindow.xaml.cs         (期望 E54EFDFEA9EEDA1C)
2338E9BB71B7187E  Controls\ContributionGraph.cs (期望 2338E9BB71B7187E)
4D5B43154315F707  Services\BackgroundService.cs (期望 4D5B43154315F707)
706E3A575F2B9D97  Services\NoisePlayer.cs     (期望 706E3A575F2B9D97)
B2C2F2E5E2B6A132  Services\FocusHistory.cs    (期望 B2C2F2E5E2B6A132)
E915FFC876D1611F  Services\AppSettings.cs     (期望 E915FFC876D1611F)
3DF77602766E6697  Services\ThemeManager.cs    (期望 3DF77602766E6697)
```

原始输出：`hashes-start.txt`、`hashes-end.txt`（`Compare-Object` 无差异输出）。

---

## 3. 独立构建与运行

### 3.1 编译（任务给定命令，逐字输出，原文见 `build.log`）

```
PS> cd C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro
PS> dotnet build FluentPomodoro.csproj -c Release -v m
  正在确定要还原的项目…
  所有项目均是最新的，无法还原。
  FluentPomodoro -> C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll

已成功生成。
    0 个警告
    0 个错误

已用时间 00:00:02.29
EXITCODE=0
```

**警告/错误文本：无（0 个警告、0 个错误），没有可逐字转述的告警。**

### 3.2 单文件发布（原文见 `publish.log`）

```
PS> dotnet publish FluentPomodoro.csproj -c Release -r win-x64 --self-contained true `
      -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
      -p:EnableCompressionInSingleFile=true -o .\verify-dist-r3
  正在确定要还原的项目…
  所有项目均是最新的，无法还原。
  FluentPomodoro -> C:\...\bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll
  FluentPomodoro -> C:\...\FluentPomodoro\verify-dist-r3\
EXITCODE=0

Name                 Length
----                 ------
FluentPomodoro.exe 66001079

SHA256=C696A58C678CF2429233A2BFD2B4C7ED680188A9B5E85D59C113B13EB3681357
EXE_BYTES=66001079
```

- 产物目录内**仅此一个文件**（`publish dir contains exactly one file :: 1 file(s): FluentPomodoro.exe`）。
- 启动、窗口与抓屏通路（`00-smoke.ps1`，11/11）：

```
[PASS] publish dir contains exactly one file :: 1 file(s): FluentPomodoro.exe
[PASS] no FluentPomodoro process before launch :: count=0
[PASS] process alive after launch :: pid=5788 HasExited=False
[PASS] owns a visible top-level window :: hwnd=2688712
[PASS] window opens at 640x780 :: 640x780 @ (640,126)
[PASS] title looks like <time> · 专注 · 微软风格番茄钟 :: title='25:00 · 专注 · 微软风格番茄钟'
virtual desktop = 1920x1080 @ (0,0)  monitor count=1
PrintWindow bitmap = 640x780
printwindow full-window stats: modal=239,244,249 distinct=48 lum=0.952
[PASS] PrintWindow capture is not blank/dummy :: distinct colours=48, modal=239,244,249
[PASS] Ctrl+I opens the 专注统计 window :: stats hwnd=3475108
[PASS] main window still largest visible window :: main=4392726
[PASS] exits cleanly via Ctrl+Shift+Q :: HasExited=True
[PASS] no leftover FluentPomodoro process :: count=0
```

> 窗口定位方法：**不用 `Process.MainWindowHandle`**。我自写 `EnumWindows + GetWindowThreadProcessId + IsWindowVisible + GetWindowRect`，按面积取最大的可见顶层窗口；主窗口判据是标题匹配 `微软风格番茄钟`（标题形如 `25:00 · 专注 · 微软风格番茄钟`），统计窗口判据是标题匹配 `^专注统计`。应用合法地同时拥有两个可见窗口（主窗口 640×780 + 统计窗口 1000×680），两者用标题区分，互不干扰。

启动截图：`r3-00-launch.png`。

![独立发布产物启动](r3-00-launch.png)

---

## 4. 逐项验证 A–G

### A. 构建与运行

见第 3 节。要点：`0 个警告 / 0 个错误`；单文件 66,001,079 字节；SHA-256 `C696A58C678CF2429233A2BFD2B4C7ED680188A9B5E85D59C113B13EB3681357`；双击启动即出窗口，标题与 640×780 均符合预期。

### B. 时钟（功能 1）—— **确认**

脚本 `02-clock.ps1`（19/19）与 `08-extras.ps1` Part 1（6/6）。

**(1) 文本形态与刷新**

```
[PASS] TxtClock is exposed in the UI tree :: name='23:57:53' rect={"X":901,"W":119,"H":43,"Y":581}
[PASS] clock text matches HH:mm:ss :: name='23:57:53'
[PASS] clock text advances every second :: read1='23:58:28' read2='23:58:30' read3='23:58:31'
```

**(2) 确实在圆环内**：时钟与大计时器**同一水平中心**，且位于"第 n / m 个番茄"之下：

```
[PASS] clock is horizontally centred on the ring axis :: clock centre X=960.5  big-timer centre X=960.5
[PASS] clock sits below the round indicator and inside the window :: clock Y=581..623  round Y=513  window bottom=906
```

**(3) 开启时两次抓屏只有时钟区域变化。** 计时器未运行（标题严格为 `25:00`），间隔 3.2s：

| 抓屏方式 | 变化像素数 | 变化包围盒（窗口内坐标） | 允许区域（时钟矩形 +2px 余量） | 判定 |
|---|---|---|---|---|
| `PrintWindow(PW_RENDERFULLCONTENT)` | 1664 | (262,467)-(379,489) | (259,453)-(382,500) | ✔ 全部落在时钟内 |
| 真实屏幕 `CopyFromScreen` | 447 | (345,467)-(378,489) | (259,453)-(382,500) | ✔ 全部落在时钟内 |

即**时钟区域外的像素逐个完全相同**（包围盒完全被允许区域包含）。两种抓屏各做了两次独立运行，结论一致。

**(4) 文本目视确认**：把时钟区域裁剪并放大 6 倍得 `r3-b2-clock-on-zoom.png`，读图可见 **`23:58:34`**，与同一时刻 UIA 读到的 `TxtClock='23:58:34'` 一致，形如 `HH:mm:ss`。

![时钟区域裁剪放大 6 倍](r3-b2-clock-on-zoom.png)

**(5) 关闭后同一抓屏对逐像素相同。** 通过设置面板里 `TglClock` 的真实 `TogglePattern` 关闭：

```
[PASS] settings panel shows 显示当前时间 = On before toggling :: TglClock ToggleState=On
[PASS] TglClock toggles Off via its real automation peer :: clicked=True state=Off
[PASS] clock disappears from the UI tree when disabled :: TxtClock rect after toggle = null
clock OFF : diff pixels=0  bbox=(2147483647,2147483647)-(-1,-1)
[PASS] clock OFF: the two captures are pixel-identical :: diff pixels=0
[PASS] clock OFF changes the rendered window (clock really removed) :: diff between clock-on and clock-off captures = 25222 pixels
```

真实屏幕抓屏路径同样为 `diff pixels=0`。

**(6) 设置持久化 + 重启**：退出后 `ShowClock=False`；重启后 `TxtClock rect=null`，抓屏对仍 `diff pixels=0`。

截图：`r3-b1-clock-on-window.png`（时钟开启）、`r3-b2-clock-on-zoom.png`（放大）、`r3-b3-clock-off-window.png`（关闭）。

### C. 统计窗口（功能 2）—— **确认**

#### C.0 方法说明（本轮唯一一处需要特别交代的地方）

第一版脚本用**外壳时钟** `[datetime]::Today` 推导矩阵日期，但脚本启动时外壳仍是 `2026-10-04 23:59`，而应用进程启动时已跨到 `2026-10-05`（周一），导致我的"第 0 周"整体错位一列、汇总卡片对不上。**这是我测试脚本的时钟竞争，不是应用缺陷**——应用在自己的日历日下渲染完全正确（`本周 0 分钟 · 2026-10-05 起`、`本月 1 小时 25 分` 与数据完全自洽）。

修正后的脚本改为**不假设日期**，而是：
1. 先只写入 3 个刻意互不相同的夹具值（T-1→111 分钟、T→222、T+1→333），启动后从 `今日` 卡片反推**应用自己的今天**（`3 小时 42 分` → 应用今天 = 2026-10-05，与我的时钟一致）；
2. 再用该日期锚定完整的边界夹具集，通过"激活主窗口→激活统计窗口"触发 `StatsWindow.OnWindowActivated → Reload()` 让窗口重新读盘；
3. 矩阵几何不假设，而是**从截图像素测量**（6 个热力色像素的行带 + 列游程），再用"所有格心必须精确等于色板颜色"自校验。

#### C.1 打开路径

```
today=2026-10-05 (Monday)  monday=2026-10-05  gridStart=2025-10-06  visible cells=365
[PASS] title-bar 统计 button opens the 专注统计 window :: invoked=True stats hwnd=3278622 title='专注统计' rect={"Y":176,"X":460,"W":1000,"H":680}
[PASS] Esc closes the statistics window :: stats hwnd after Esc=0
[PASS] Ctrl+I opens the 专注统计 window :: stats hwnd=3344158 rect={"Y":176,"X":460,"W":1000,"H":680}
[PASS] Esc closes the statistics window (again) :: stats hwnd after Esc=0
[PASS] Ctrl+I reopens the statistics window after it was closed :: hwnd=657378
```

两条路径都通过：标题栏按钮走真实 `InvokePattern`（即 `Click="OnOpenStats"`），以及 `Ctrl+I`（`MainWindow.xaml.cs:1007-1012`）；`Esc` 可关闭。

#### C.2 矩阵几何与规模

```
[PASS] the contribution matrix was located in the capture :: measured heat-pixel bbox=(72,369)-(915,477) -> matrix origin (42,349) drawn size 844x109
[PASS] the matrix is drawn as exactly 53 weekly columns :: column runs with heat pixels = 53
[PASS] the matrix is drawn as exactly 7 weekday rows :: row runs with heat pixels = 7
[PASS] drawn cell block is 53x16-3 wide and 7x16-3 tall :: drawn 844x109
```

- 实测矩阵原点 `(42,349)`、单元 13px、间距 3px（步长 16px）。
- **53 个列游程、7 个行游程**，与 `ContributionGraph.Weeks = 53` 及"一周一列、周一到周日"一致。
- 宽度 844 而非 875：875 是控件总宽（含 30px 星期标签列），实际绘制格块为 `53×16−3 = 845`，最右一格因"今天"格带强调色描边少 1px，故 844 —— 属我第一版的预期写法错误，已按正确口径断言。

#### C.3 六个等级颜色全部来自源码色板

```
palette Heat0 = #EBEDF0  RGB(235,237,240)
palette Heat1 = #9BE9A8  RGB(155,233,168)
palette Heat2 = #40C463  RGB(64,196,99)
palette Heat3 = #30A14E  RGB(48,161,78)
palette Heat4 = #216E39  RGB(33,110,57)
palette Heat5 = #0B3B22  RGB(11,59,34)
```

（直接读 `Themes\Palette.Light.xaml`。）

**365 个可见格心逐个采样，无一例外全部精确命中上述 6 色之一：**

```
sampled 365 cells (expected 365); unclassified=0
[PASS] every sampled cell centre is exactly one of the 6 palette colours :: unclassified=0
[PASS] sampled cell count equals the number of days in the 53-week window :: sampled=365 expected=365
[PASS] all 6 level colours are rendered in the matrix :: L0=351 L1=3 L2=4 L3=2 L4=3 L5=2
```

这一条同时是"几何测量正确"的自证：365 个格心若有一个偏出格子，就会落到底色或相邻格上而无法精确匹配色板。

**另做一次与格心无关的整区域像素计数**（对 `(42,349)` 起 878×129 区域逐像素统计各色像素数），6 个等级均非零：

```
L0=53703  L1=459  L2=576  L3=306  L4=459  L5=306   (pixels)
```

#### C.4 等级分桶数等于我放置的天数

夹具（锚定应用日历日）与我的期望分桶（阈值按任务给定：0 / <25 / 25–49 / 50–99 / 100–199 / ≥200）：

| 夹具 | 分钟 | 期望等级 |
|---|---|---|
| gridStart+0 | 500 | 5 |
| gridStart+1 | 0（另有 2 个番茄） | 0 |
| gridStart+7 | 1 | 1 |
| gridStart+8 | 24 | 1 |
| gridStart+14 | 25 | 2 |
| gridStart+15 | 49 | 2 |
| gridStart+21 | 50 | 3 |
| gridStart+22 | 99 | 3 |
| gridStart+28 | 100 | 4 |
| gridStart+29 | 199 | 4 |
| gridStart+36 | 200 | 5 |
| 今天 / -1 / -2 / -20 天 | 30 / 45 / 10 / 120 | 2 / 2 / 1 / 4 |
| -400 天（窗口外） | 130 | 不参与矩阵 |

```
my expected level counts: L0=351 L1=3 L2=4 L3=2 L4=3 L5=2
[PASS] cells at level 0 (#EBEDF0) == my own bucket count for that boundary set :: rendered=351 expected=351
[PASS] cells at level 1 (#9BE9A8) == my own bucket count for that boundary set :: rendered=3 expected=3
[PASS] cells at level 2 (#40C463) == my own bucket count for that boundary set :: rendered=4 expected=4
[PASS] cells at level 3 (#30A14E) == my own bucket count for that boundary set :: rendered=2 expected=2
[PASS] cells at level 4 (#216E39) == my own bucket count for that boundary set :: rendered=3 expected=3
[PASS] cells at level 5 (#0B3B22) == my own bucket count for that boundary set :: rendered=2 expected=2
```

11 个边界值全部落在预期等级，且"0 分钟但仍有番茄记录"的那天正确渲染为等级 0。

#### C.5 悬停 tooltip

把鼠标移到矩阵 `week 4 / row 1`（即 `2025-11-04`）的格心，读该进程弹出的 WPF Popup 的 UIA 文本：

```
hover cell = grid week 4 row 1 -> 2025-11-04; tooltip='2025-11-04 周二\n专注 3 小时 19 分 · 6 个番茄'
[PASS] tooltip reports exactly the date of the hovered cell :: expected date '2025-11-04 周二'
[PASS] tooltip focus minutes match history.json for that day :: expected '专注 3 小时 19 分'
[PASS] tooltip pomodoro count matches history.json for that day :: expected '6 个番茄'
```

三项均与我在 `history.json` 里为该日写入的 `199 分钟 / 6 个番茄` 完全对应（`199 → 3 小时 19 分` 的格式化也正确）。截图 `r3-c2-hover-tooltip.png` 中可直接看到浮层：

![矩阵悬停浮层](r3-c2-hover-tooltip.png)

#### C.6 汇总卡片

我按自己写的 `history.json` 独立算出期望值，再与界面值逐项比对：

```
my expectations: today='30 分钟'/1pom  week='30 分钟'  month='1 小时 25 分'  total='26 小时 22 分'/47pom  streak=3  best='8 小时 20 分' on 2025-10-06
[PASS] summary field ValToday  equals my own computation :: rendered='30 分钟' expected='30 分钟'
[PASS] summary field ValWeek   equals my own computation :: rendered='30 分钟' expected='30 分钟'
[PASS] summary field ValMonth  equals my own computation :: rendered='1 小时 25 分' expected='1 小时 25 分'
[PASS] summary field ValTotal  equals my own computation :: rendered='26 小时 22 分' expected='26 小时 22 分'
[PASS] summary field ValStreak equals my own computation :: rendered='3' expected='3'
[PASS] summary field ValBest   equals my own computation :: rendered='8 小时 20 分' expected='8 小时 20 分'
[PASS] summary field SubToday  equals my own computation :: rendered='1 个番茄' expected='1 个番茄'
[PASS] summary field SubTotal  equals my own computation :: rendered='47 个番茄' expected='47 个番茄'
[PASS] summary field SubBest   equals my own computation :: rendered='2025-10-06' expected='2025-10-06'
[PASS] summary field TxtRange  equals my own computation :: rendered='共 16 天有记录' expected='共 16 天有记录'
```

（`本周` 起算日为周一：应用今天 2026-10-05 恰为周一，故 `本周 = 今天 = 30 分钟`；`本月` 从 10-01 起算 = 85 分钟。）

截图 `r3-c1-stats-window.png`（矩阵与卡片全景）：

![统计窗口全貌](r3-c1-stats-window.png)

#### C.7 CSV 导出

通过真实「导出 CSV」按钮打开**原生保存对话框**（`#32770`，标题 `导出专注统计`），用剪贴板粘贴绝对路径后回车保存，再确认写入内容：

```
[PASS] 导出 CSV opens a native save dialog :: invoked=True dialog hwnd=2950948 title='导出专注统计'
[PASS] CSV file written to the path I typed into the dialog :: path=...\verification\r3\r3-export.csv
CSV lines=17 (expected 17); header='日期,专注分钟,番茄数'
[PASS] CSV rows == history.json days (+1 header row) :: csv=17 expected=17
[PASS] every CSV row matches my own derivation :: all 17 lines identical
```

`r3-export.csv` 前几行（UTF-8 BOM + CRLF）：

```
日期,专注分钟,番茄数
2025-08-31,130,4
2025-10-06,500,3
2025-10-07,0,2
2025-10-13,1,1
...
```

即 16 天记录按日期升序逐行导出，日期/分钟/番茄数与 `history.json` 完全一致（含窗口外的那一天，见第 6 节 O3）。

### D. 历史记录（功能 2 数据链路）—— **确认**

脚本 `04-history.ps1`（21/21），真实跑完一个 1 分钟专注。基线：`history.json` 已含**连续三天**（昨天 25/1、前天 30/1、大前天 15/1）与 5 天前 60/2；`settings.json` 的 `StreakDays=3`、`LastCompletedDate=昨天`、`TotalCompleted=7`、今日计数全 0。`FocusMinutes=1`、`AutoStartNext=false`。

```
[PASS] timer shows 01:00 (FocusMinutes=1 took effect) :: title='01:00 · 专注 · 微软风格番茄钟'
[PASS] app owns the keyboard focus before the keystroke :: foreground==main : True
[PASS] Space starts the focus phase :: title='00:59 · 专注 · 微软风格番茄钟'
[PASS] the 1-minute focus phase runs to completion and advances to the break :: after 58.8s title='05:00 · 短休息 · 微软风格番茄钟'
[PASS] history.json gained today with exactly +1 minute :: today Minutes=1
[PASS] history.json gained today with exactly +1 pomodoro :: today Pomodoros=1
[PASS] the pre-existing day is unchanged (25 min / 1 pomodoro) :: yesterday = 25 min / 1 pom
[PASS] history.json now holds exactly 5 days :: days = 2026-10-04, 2026-10-03, 2026-10-02, 2026-09-30, 2026-10-05
[PASS] no second increment while the break is running (counted exactly once) :: 12s later today = 1 min / 1 pom
[PASS] settings: CompletedToday incremented to exactly 1 :: CompletedToday=1
[PASS] settings: FocusMinutesToday incremented to exactly 1 :: FocusMinutesToday=1
[PASS] settings: TotalCompleted 7 -> 8 :: TotalCompleted=8
[PASS] settings: StreakDays 3 -> 4 (yesterday was the last completion day) :: StreakDays=4
[PASS] settings: LastCompletedDate == today :: LastCompletedDate=2026-10-05
[PASS] 统计窗口 今日 card reads exactly 1 分钟 :: ValToday='1 分钟'
[PASS] 今日 card sub-label reads 1 个番茄 :: SubToday='1 个番茄'
[PASS] 累计专注 card :: ValTotal='2 小时 11 分' expected='2 小时 11 分'
[PASS] 最佳一天 card :: ValBest='1 小时' expected='1 小时'
[PASS] 连续专注 card :: ValStreak='4' expected='4'
```

- `history.json` **只新增了今天这一天**，其余 4 天逐字段不变；
- 完成并进入休息后再等 12s，`today` 仍为 `1/1`，即**恰好计一次**；
- 统计窗口的 `今日` 卡片随后显示 **`1 分钟`**（正是任务要求的观测值），`SubToday` 为 `1 个番茄`；
- `settings.json` 侧 4 个计数器与 `LastCompletedDate` 也各自恰好加一次。

截图 `r3-d1-stats-after-focus.png`。

> 关于"连续专注"这张卡片：第一版基线里我把 `settings.StreakDays` 设成 3 而 `history.json` 里并没有 3 天连续记录，卡片显示 2 —— 我据此确认**统计窗口的"连续专注"取自 `history.json`（连续有专注分钟的天数），与 `settings.json` 里独立的 `StreakDays` 是两个计数器**。把基线改成自洽（连续三天）后两者都为 4。这是数据源差异，不是缺陷，详见第 6 节 O2。

### E. 背景图片（功能 3）—— **确认**

脚本 `05-background.ps1`（37/37）、`09-probes.ps1` P1（5/5）、`08-extras.ps1` Part 2（2/2）、`10-rotation.ps1`。

采样口径：**左侧背景条带**（窗口内坐标 `x∈[4,18)`、`y∈[60,300)`，此处无任何控件）取众数/均值；**主按钮**用 UIA 取 `BtnPlay` 包围盒内缩 5px 后取众数。颜色一律来自真实屏幕读回。

**独立重算的预期强调色**（我用 PowerShell 按源码算法重写了 `BackgroundService.ExtractAccent` + `AccentService.Build`，直接对 PNG 像素做饱和度平方加权的色相圆平均）：

```
image hues measured by me: red=2.87 deg  blue=215.46 deg
predicted accent (light+red)  = RGB(173,61,55)
predicted accent (light+blue) = RGB(55,104,173)
predicted accent (dark+red)   = RGB(224,96,90)
```

**(i) 红图 + 浅色**

```
baseline plain strip: modal=243,243,243 avg=(243,243,243) lum=0.9529
baseline 开始专注 accent: modal=0,120,212
[PASS] 选择图片 opens the native 选择背景图片 dialog and it accepts the typed path :: invoked=True title='选择背景图片' foreground=True closed after Enter=True
[PASS] settings.json records the image chosen through the dialog :: BackgroundImagePath='...\artifacts\test-assets\bg-red.png'
light + red image: strip modal=229,177,174 avg=(229.2,176.9,174.1) lum=0.7364
light + red image: 开始专注 button modal=173,61,55 avg=(180.6,78.7,73.5)
[PASS] red image -> background strip becomes red-dominant :: strip modal RGB(229,177,174)
[PASS] red image -> the 开始专注 button becomes red-dominant :: BtnPlay modal RGB(173,61,55)
[PASS] red image -> button accent equals the value my own extraction formula predicts :: observed RGB(173,61,55) predicted RGB(173,61,55) from hue 2.87 deg
[PASS] red image -> accent really changed away from the system accent :: before RGB(0,120,212) after RGB(173,61,55)
```

**采样 RGB：** 背景条带众数 `RGB(229,177,174)`（R 明显占优）；主按钮众数 **`RGB(173,61,55)`**，与我的独立预期**逐通道完全相同**。

**(ii) 蓝图 + 浅色**

```
light + blue image: strip modal=171,195,231 avg=(170.9,194.9,229.9)
light + blue image: 开始专注 button modal=55,104,173
[PASS] blue image -> background strip becomes blue-dominant :: strip modal RGB(171,195,231)
[PASS] blue image -> the 开始专注 button becomes blue-dominant :: BtnPlay modal RGB(55,104,173)
[PASS] blue image -> button accent equals my predicted value and differs from the system accent
```

**采样 RGB：** 背景条带 `RGB(171,195,231)`（B 占优）；主按钮 **`RGB(55,104,173)`**，与预期完全一致。

**(iii) 文件夹模式 + 每次开始专注换一张**

文件夹是通过真实的「选择文件夹」原生选择器选中的（剪贴板粘贴路径 + 回车，对话框确实接受了路径）：

```
[PASS] the 选择文件夹 button opens a native folder picker :: invoked=True dialog hwnd=2295568 title='选择背景图片文件夹'
folder picker title='选择背景图片文件夹'; TxtBgInfo after typing the path = '当前：bg-blue.png | 文件夹内共 3 张 · 不自动轮换'; settings BackgroundFolder='...\artifacts\test-assets'
[PASS] folder mode reports the number of images in the folder (3) :: TxtBgInfo='当前：bg-blue.png | 文件夹内共 3 张 · 不自动轮换'
folder mode before Space: strip modal=167,194,233 avg=(166.4,192,228.8); accent modal=55,104,173
folder mode after Space : strip modal=233,174,171 avg=(228.1,172.9,170.1); accent modal=173,61,55; title='24:56 · 专注 · 微软风格番茄钟'
[PASS] pressing Space really started the focus phase (so the rotate trigger ran) :: foreground=True title='24:56 · 专注'
[PASS] rotate-on-focus-start changes the background image :: background strip avg delta = 139.5 (before (166.4,192,228.8) -> after (228.1,172.9,170.1))
[PASS] the accent follows the new image too :: accent before RGB(55,104,173) after RGB(173,61,55)
```

即：文件夹 3 张（`bg-blue/bg-green/bg-red`，序数排序后首张为蓝），初始为蓝；按空格开始专注后背景条带平均色变化 139.5（蓝→红），强调色同步从 `(55,104,173)` 变为 `(173,61,55)`。触发条件 `_settings.BackgroundRotateOnFocus` 为真（默认即真）。截图 `r3-e6-folder-before-space.png` / `r3-e7-folder-after-space.png`。

**(iv) 不透明度滑块**

```
[PASS] opacity slider accepts 0.15 through its real RangeValue peer :: SetValue(0.15) ok=True
[PASS] the opacity label follows the slider (15%) :: LblBgOpacity='15%'
[PASS] opacity slider accepts 1.0 :: SetValue(1.0) ok=True label='100%'
opacity 0.15 strip avg=(237.9,241.4,247) lum=0.9454 | opacity 1.0 strip avg=(166.4,192,228.8) lum=0.7419 | sum|d|=139.1
[PASS] the opacity slider visibly changes the image strength :: sum |delta| over RGB = 139.1
[PASS] opacity 1.0 shows a stronger (darker) image than 0.15 :: lum(1.0)=0.7419 < lum(0.15)=0.9454
[PASS] opacity persisted as 1 :: BackgroundOpacity=1
```

滑块走真实 `RangeValuePattern.SetValue`（等价于用户拖动，`OnBackgroundOpacityChanged` 真实触发），标签与像素双向确认，且写盘。

**(v) 清除恢复主题底色**

```
[PASS] the 清除 button clears the background :: clicked=True TxtBgInfo='未设置背景图片（可选一张图片，或选一个文件夹在其中的图片间轮换）'
[PASS] clearing restores the plain theme background (243,243,243, identical to baseline) :: strip modal after clear=243,243,243, baseline=243,243,243
[PASS] clearing also reverts the accent to the system accent :: BtnPlay after clear=RGB(0,120,212); baseline=RGB(0,120,212)
[PASS] clearing persists empty path/folder to settings.json :: path='' folder=''
```

即恢复到与开始时**逐像素同值**的 `RGB(243,243,243)`（= `WindowBackdropBrush #F3F3F3`），强调色也回到系统强调色 `(0,120,212)`。

**(vi) 路径与设置重启后保留**

```
[PASS] after exit settings.json still holds BackgroundImagePath :: '...bg-red.png'
[PASS] after exit BackgroundOpacity / BackgroundRotateMinutes / BackgroundUseImageAccent intact :: opacity=0.95 rotate=0 useImageAccent=True
[PASS] after restart the same red background is applied :: strip modal RGB(229,177,174)
[PASS] after restart the image accent is applied again :: BtnPlay modal RGB(173,61,55)
```

**(vii) 深色主题 + 红图：界面仍深色，强调色仍为红且按主题自适应**

```
dark + red image: strip modal=76,28,25 avg=(72.8,26.9,24.6) lum=0.1432
dark + red image: 开始专注 button modal=224,96,90 avg=(226.9,110.5,105.3)
   light + red image was: strip avg=(229.2,176.9,174.1) lum=0.7364, accent RGB(173,61,55)
[PASS] dark theme + red image: the window is still dark (strip luminance far below the light variant) :: dark strip lum=0.1432 vs light strip lum=0.7364 (same image, same opacity)
[PASS] dark theme + red image: the accent is still red-dominant :: BtnPlay modal RGB(224,96,90)
[PASS] dark theme + red image: accent equals my predicted dark-theme value (adapted, not copied verbatim) :: observed RGB(224,96,90) predicted RGB(224,96,90); light+red was RGB(173,61,55)
[PASS] the accent differs between light and dark themes (per-theme adaptation) :: dark RGB(224,96,90) vs light RGB(173,61,55)
```

**结论：** 同一张红图、同一不透明度下，深色主题的背景条带平均亮度 0.1432 远低于浅色主题的 0.7364（相差 0.59），即界面底层仍是深色；强调色为 `RGB(224,96,90)`，与浅色主题的 `RGB(173,61,55)` 不同，且与我在深色参数（sat 0.60 / val 0.88）下重算的预期**逐通道完全相同** —— 证明强调色是**按主题适配**而非把图片颜色逐字照搬。

截图对比：

![浅色 + 红图](r3-e1-light-red.png)
![深色 + 红图](r3-e8-dark-red.png)

**(viii) 定时轮换（真实等待 5 分钟）** —— `10-rotation.ps1`，6/6。

关键点：**专注计时器全程未运行**（标题始终 `25:00`），以证明轮换由独立的 20s 背景定时器驱动，而不是被计时器顺带触发。

```
[PASS] rotation test: the focus timer is NOT running (rotation must be independent of the timer) :: title='25:00 · 专注 · 微软风格番茄钟'
t=0s TxtBgInfo='当前：bg-blue.png | 文件夹内共 3 张 · 每 5 分钟轮换'
t=30s current: bg-blue.png
t=60s current: bg-blue.png
t=91s current: bg-blue.png
t=121s current: bg-blue.png
t=151s current: bg-blue.png
t=181s current: bg-blue.png
t=211s current: bg-blue.png
t=241s current: bg-blue.png
t=271s current: bg-blue.png
t=301.5s CHANGED -> '当前：bg-red.png | 文件夹内共 3 张 · 每 5 分钟轮换'
t=302s current: bg-red.png
t=332s current: bg-red.png
t=362s current: bg-red.png
t=392s current: bg-red.png
[PASS] rotation test: the background image rotated on the 5-minute timer :: 1 change(s) observed; first at t=301.5s
[PASS] rotation test: the rotation happened at ~5 minutes, not immediately and not never :: first change at t=301.5s (timer interval 20s, target 300s, sampler period 10s)
[PASS] rotation test: exits cleanly :: processes=0
```

即：0~271s 保持 `bg-blue.png`（没有提前轮换），**301.5s 首次切换为 `bg-red.png`**，与 300s 目标值只差一个采样周期（定时器 20s，采样 10s）；之后 4 个采样点不再变化。截图 `r3-h1-rotation-after.png`。

**(ix) 非刻度值探针**：手写 `BackgroundOpacity=0.42`（不是滑块刻度 0.05 的整数倍）→ 会话内滑块读到 `0.42`、标签 `42%`、退出后文件仍为 `0.42`，**没有被静默改写**。

**(x) 轮换间隔下拉的 5 个取值往返**

```
[PASS] P1 BackgroundRotateMinutes=5:    TxtBgInfo='... 每 5 分钟轮换'   persisted=5
[PASS] P1 BackgroundRotateMinutes=15:   TxtBgInfo='... 每 15 分钟轮换'  persisted=15
[PASS] P1 BackgroundRotateMinutes=30:   TxtBgInfo='... 每 30 分钟轮换'  persisted=30
[PASS] P1 BackgroundRotateMinutes=60:   TxtBgInfo='... 每 1 小时轮换'   persisted=60
[PASS] P1 BackgroundRotateMinutes=1440: TxtBgInfo='... 每天轮换'        persisted=1440
```

即 `BackgroundRotateMinutes ↔ CmbBgRotate.SelectedIndex` 的双向映射在 5 个档位上都是双射。

### F. 白噪音（功能 4）—— **确认**

脚本 `06-noise.ps1`（37/37）、`09-probes.ps1` P2/P3/P4（7/7）。

**测量口径说明：** 标题栏白噪音按钮的图形是**细笔画图标字体**（`&#xE767;`），ClearType 抗锯齿使其**永远达不到画刷纯色**。所以我按实测的非背景像素蓝-红通道差分类：

| 状态 | 典型像素 | 平均 `B−R` | 蓝偏像素数 | 中性像素数 |
|---|---|---|---|---|
| 已停止 | `RGB(166,149,166)` | **−0.1** | 19 | 22 |
| 播放中 | `RGB(170,169,221)` | **+35** | 48 | 0 |

判据 `avg(B−R) ≥ 15 → PLAYING`（−0.1 与 +35 之间余量极大），并且每次都**用设置面板的状态文本交叉确认**。放大 6 倍的按钮裁剪图 `r3-f0-btn-stopped.png` / `r3-f1-btn-playing.png` 目视也可见中性灰 vs 明显偏蓝。

![按钮：已停止](r3-f0-btn-stopped.png)
![按钮：播放中](r3-f1-btn-playing.png)

**(i) 导入与持久化**

```
[PASS] 添加音频 opens the native 添加白噪音音频 dialog and accepts the path :: title='添加白噪音音频' closed=True
[PASS] the settings panel reports the imported track :: TxtNoiseInfo='已导入 1 个文件（1 个可用）· 已停止'
[PASS] the track list control shows the imported file :: list items: ...\tone-440.wav | ...\tone-440.wav
[PASS] settings.json persists NoiseTracks as an array holding exactly the imported file :: NoiseTracks=[...tone-440.wav]
[PASS] the second track can be imported too :: TxtNoiseInfo='已导入 2 个文件（2 个可用）· 正在播放：tone-440.wav'
[PASS] settings.json lists both tracks :: NoiseTracks=[...tone-440.wav, ...r3-tone-880.wav]
```

（列表控件里同一路径出现两次是 UIA 把 `TextBlock` 与外层项各报一次，非重复项；`settings.json` 里只有一条。）

**(ii) 开始专注自动播放 + 仅专注阶段播放**

两个开关都通过真实 `TogglePattern` 翻转并写盘：

```
[PASS] 开始专注时自动播放 toggles Off->On through its real automation peer :: state Off -> On
[PASS] 仅在专注阶段播放 toggles through its real automation peer :: state On -> Off
[PASS] both noise toggles persisted to settings.json :: NoiseAutoPlayOnFocus=True NoiseOnlyDuringFocus=True
```

然后按空格启动专注：

```
[PASS] before starting the focus phase the noise button is stopped :: state=STOPPED avg(B-R)=-0.1 blue-tinted px=19
[PASS] starting the focus phase auto-plays the noise (button turns accent/blue-tinted) :: title='24:57 · 专注' state=PLAYING blue-tinted px=48 avg(B-R)=35
[PASS] the 白噪音 status text shows 正在播放 during the focus phase :: TxtNoiseInfo='已导入 1 个文件（1 个可用）· 正在播放：tone-440.wav'
[PASS] pausing the focus phase returns the noise to stopped :: title='24:54 · 专注' state=STOPPED blue-tinted px=19 avg(B-R)=-0.1
[PASS] the 白噪音 status text shows 已停止 after pausing :: TxtNoiseInfo='已导入 1 个文件（1 个可用）· 已停止'
[PASS] the title-bar noise button starts playback when invoked :: invoked=True state=PLAYING
[PASS] the title-bar noise button pauses playback when invoked again :: state=STOPPED
```

即：开始专注 → 按钮转为强调色（蓝偏 px 48、avg B−R = +35）且面板显示"正在播放：tone-440.wav"；暂停 → 按钮恢复中性（avg B−R = −0.1）且面板显示"已停止"；标题栏按钮本身也能播放/暂停。

截图 `r3-f2-noise-playing.png` 同时可见运行中的倒计时、面板状态"正在播放：tone-440.wav"、音量 70%、两个开关均为开：

![白噪音播放状态（设置面板）](r3-f2-noise-playing.png)

**(iii) 下一首：单曲与双曲**

```
[PASS] 下一首 with a single track keeps the same track playing :: before='...正在播放：tone-440.wav' after='...正在播放：tone-440.wav'
[PASS] 下一首 with two tracks switches to the other file :: playing 'r3-tone-880.wav' -> 'tone-440.wav'
```

另在 `09-probes.ps1` P4 用 `NoiseShuffle=true` + 两首曲目连按 5 次「下一首」：

```
shuffle sequence over 5 下一首 presses: r3-tone-880b.wav -> tone-440.wav -> r3-tone-880b.wav -> tone-440.wav -> r3-tone-880b.wav -> tone-440.wav
[PASS] P4 shuffle never stays on the same file across 下一首 presses :: 连续重复=0
```

**单曲循环**（用我自己生成的 1 秒 880Hz WAV，`MediaEnded` 必须把它循环回来）：

```
[PASS] only the 1-second track is loaded :: NoiseTracks=[...r3-tone-880.wav]
[PASS] a single 1-second track keeps looping (still playing 7s later, i.e. >=6 repeats) :: t=3s state=PLAYING (blue px=48);  t=7s state=PLAYING (blue px=48)
```

**(iv) 损坏文件：不挂死、不空转、能报错、不无限重试**

自造 `r3-corrupt.wav`（3000 字节纯随机字节，无 RIFF 头）。**损坏 + 好文件各一个**（顺序 `[corrupt, tone-440]`，`NoiseShuffle=false`，故从损坏的那首开始）：

```
[PASS] the corrupt file and a good file are both imported :: TxtNoiseInfo='已导入 2 个文件（2 个可用）· 已停止'
[PASS] the corrupt file is tracked first in settings.json :: NoiseTracks=[...r3-corrupt.wav, ...tone-440.wav]
quiet idle CPU (nothing playing, no UIA traffic) over 8s = 0s
corrupt-then-good: toast='白噪音播放失败：Cannot find the media file.'; idle CPU after the failure over 8s = 0.62s (baseline 0s); button=PLAYING; responsive=True
[PASS] playing a corrupt file does not spin the CPU (no retry loop) :: idle CPU 0.62s after the failure vs 0s baseline over the same 8s window
[PASS] the window stays responsive while the corrupt file is handled :: SendMessageTimeout(WM_NULL, 2000ms) non-zero = True
[PASS] the failure is reported to the user (toast) instead of looping silently :: toast = '白噪音播放失败：Cannot find the media file.'
[PASS] the player falls through to the good track rather than retrying the corrupt one :: button state=PLAYING blue-tinted px=48
[PASS] the status text names the good track after the fall-through :: TxtNoiseInfo='...正在播放：tone-440.wav'
```

**只有损坏文件时**（单曲）：

```
corrupt-only: toast='白噪音播放失败：Cannot find the media file.'; idle CPU after failure=0.02s (baseline 0s); button=STOPPED; TxtNoiseInfo='已导入 1 个文件（1 个可用）· 已停止'
[PASS] a lone corrupt file stops the player instead of looping :: button state=STOPPED; TxtNoiseInfo='...已停止'
[PASS] a lone corrupt file does not spin the CPU :: idle CPU 0.02s vs 0s over the same 8s window
[PASS] the lone-corrupt failure is reported
```

**CPU 采样方法**：先在与触发播放**完全隔离**的窗口里测 8s 空闲 CPU 基线（0s），失败发生并静置 4s 后再测 8s **完全不发任何 UIA 消息**的空闲 CPU（0.62s / 0.02s）。**注意**：早期版本的测量值 2.55s/1.41s 是**我自己的测量方法污染** —— 我在计时窗口内持续轮询 UIA 读 toast，跨进程 UIA 查询本身会让被测进程耗 CPU。改成安静窗口后数值回到 0.6s 以下，这是方法修正而非应用行为变化。

**缺失文件（不是损坏，而是路径不存在）**：

```
[PASS] P3 the panel reports 2 imported files with only 1 usable :: TxtNoiseInfo='已导入 2 个文件（1 个可用）· 已停止'
[PASS] P3 playback still starts even though the first track is a missing file :: button state=PLAYING blue-tinted px=48
[PASS] P3 the track actually playing is the one that exists :: playing='tone-440.wav'
[PASS] P3 the missing path is still listed in settings.json (the list is not silently rewritten) :: NoiseTracks=[...does-not-exist.wav, ...tone-440.wav]
```

**(v) 带曲目干净退出**

```
[PASS] the app exits cleanly while a track is loaded and playing :: HasExited=True
[PASS] noise settings survived the exit :: NoiseTracks=[...] volume=70 shuffle=False auto=True onlyFocus=True
```

**音量滑块**：`SetValue(25)` → 标签 `25%` → 写盘 `NoiseVolume=25`。

### G. 回归 —— **确认**

脚本 `07-regression.ps1`（26/26）。

**G1 设置往返（含全部新字段）：32 项零差异**

预置**全部 32 个键的非默认值**（含 `ShowClock=false`、`BackgroundImagePath`+`BackgroundFolder` 同时非空、`BackgroundRotateMinutes=30`、`BackgroundRotateOnFocus=false`、`BackgroundOpacity=0.45`、`BackgroundUseImageAccent=false`、`NoiseTracks` 三条（其中两条是**不存在的路径**）、`NoiseVolume=33`、`NoiseShuffle=true`、`NoiseAutoPlayOnFocus=true`、`NoiseOnlyDuringFocus=false`，以及 `Theme=Dark`、统计 4/90/12/5 等），然后：启动 → 用真实标题栏按钮打开设置面板 → 关闭 → `Ctrl+Shift+Q` 退出：

```
[PASS] G1 launches with a fully non-default settings file and shows no dialog :: hwnd=2885356 dialogs=0
[PASS] G1 window still opens at the remembered 640x780 :: rect={"Y":126,"W":640,"X":640,"H":780}
[PASS] G1 the settings panel reflects the file (focus slider, new toggles) :: SldFocus=7 TglClock=Off SldBgOpacity=0.45 SldNoiseVolume=33 TglBgAccent=Off
[PASS] G1 exits cleanly :: HasExited=True
[PASS] G1 settings round-trip has ZERO differences across all 32 fields (incl. the 4 new groups) :: all 32 keys identical after the round-trip (NoiseTracks=[...tone-440.wav|...missing-a.wav|...missing-b.mp3])
```

即 `ShowClock`、`BackgroundOpacity`、`BackgroundRotateMinutes`、`NoiseTracks` 数组这三类新字段**逐字段零差异**（数组的三条元素与顺序也完全保留）。

**G2 坏的新字段容错**

| 用例 | 坏字段 | 观测 | 判定 |
|---|---|---|---|
| A | `"NoiseTracks": "oops"`（类型错误 → 走 `ReadTolerant`） | 应用正常启动、无对话框；`NoiseTracks=[]`；另 12 个字段（`NoiseVolume=42`、`NoiseAutoPlayOnFocus=True`、`BackgroundOpacity=0.55`、`BackgroundRotateMinutes=15`、`ShowClock=False`、`FocusMinutes=44`、`Theme=Dark`、`CompletedToday=5`、`FocusMinutesToday=150`、`TotalCompleted=42`、`StreakDays=7`）**全部保留** | ✔ |
| B | `"BackgroundOpacity": 99` | 正常启动；`BackgroundOpacity` 钳制为 `1`；其余 8 个字段全部保留 | ✔ |
| C | `"ShowClock": "oops"` + `"BackgroundRotateMinutes": "abc"` | 正常启动；坏的 int 回落为 `0`；`BackgroundOpacity=0.35`、`NoiseVolume=11`、`FocusMinutes=44`、`CompletedToday=5`、`TotalCompleted=42` 全保留 | ✔ |

原始输出：

```
[PASS] G2-A (NoiseTracks:"oops") : the bad array falls back to empty and every other field is preserved
[PASS] G2-B (BackgroundOpacity:99) : opacity clamps to 1.0 and every other field is preserved
G2-C observed: ShowClock=False (file said 'oops'; class default = True)  BackgroundRotateMinutes=0 (file said 'abc')  ...
[PASS] G2-C the bad int falls back to its default (0) and other fields survive
[PASS] G2-C the invalid bool string is coerced to False rather than the class default True
```

三个用例都是"应用照常启动、不弹对话框、只坏掉那一个字段、其余一个不丢"，符合容错要求。G2-C 里 `"oops"` → `False` 的细节见第 6 节 O1。

**G3 强制大屏仍铺满虚拟桌面并拦截最小化**

```
virtual desktop = 1920x1080 @ (0,0)
[PASS] G3 window mode starts at 640x780 :: rect={"Y":126,"W":640,"X":640,"H":780}
[PASS] G3 F11 fills the whole virtual desktop :: 1920x1080 @ (0,0)
[PASS] G3 big screen is topmost (WS_EX_TOPMOST 0x8) as configured :: exstyle=0x8
[PASS] G3 WM_SYSCOMMAND SC_MINIMIZE is blocked :: IsIconic=False rect=1920x1080
[PASS] G3 ShowWindow(SW_MINIMIZE) is blocked :: IsIconic=False rect=1920x1080
[PASS] G3 an external SetWindowPos resize is refused in big screen :: 1920x1080 @ (0,0)
[PASS] G3 Esc restores exactly 640x780 :: 640x780 @ (640,126)
[PASS] G3 the window is not left maximized after Esc :: IsZoomed=False
[PASS] G3 topmost is released after leaving big screen :: exstyle=0x40100
```

截图 `r3-g1-bigscreen.png`（全屏 1920×1080）、`r3-g2-after-esc.png`（还原后）。**测试结束后没有任何全屏/置顶窗口残留**（见第 7 节收尾核对）。

**G4 1 分钟专注完成的 4 个计数器仍恰好加一次**

```
[PASS] G4 the 1-minute focus completes and advances to the break :: after 58.8s title='05:00 · 短休息 · 微软风格番茄钟'
[PASS] G4 after completion: CompletedToday=1, FocusMinutesToday=1, TotalCompleted=1, StreakDays=1 :: LastCompletedDate=2026-10-05
[PASS] G4 history.json holds exactly 1 minute / 1 pomodoro for today :: today = 1 min / 1 pom
[PASS] G4 the counters do not move again during the break (counted exactly once) :: 12s later: CompletedToday=1 FocusMinutesToday=1 TotalCompleted=1
[PASS] G4 the bottom status line reports 1 个番茄 · 1 分钟 :: TxtStats='今日 1 个番茄 · 1 分钟 · 连续 1 天'
```

（与 D 是两次独立的 1 分钟实测，结论一致。）

**额外探针 P5：损坏的 `history.json`**

把 `history.json` 截断成 `{ "Days": { "2026-10-05": { "Minutes": 30, ` 后启动：

```
[PASS] P5 the app still starts with a truncated history.json :: hwnd=10815188
[PASS] P5 the statistics window still opens :: stats hwnd=6227688
[PASS] P5 the corrupt history degrades to zeros instead of crashing :: ValToday='0 分钟' TxtRange='共 0 天有记录' ValTotal='0 分钟'
[PASS] P5 the main window is still responsive :: WM_NULL ping after the corrupt history = ok
```

---

## 5. 新增缺陷

**无。** 本轮 217 项检查全部通过，四项新功能与回归均未发现缺陷，因此本节没有 severity / file:line / repro 条目。

需要说明的是：我确实**主动找过**缺陷，以下几处是重点排查但结论为"非缺陷"的：

| 排查点 | 为什么怀疑 | 实测结论 |
|---|---|---|
| 时钟每秒重绘会不会带动其他区域重绘 | 若整窗重绘，diff 会扩散 | 开启时两次抓屏的变化包围盒**完全落在时钟矩形内**（PrintWindow 与屏幕抓屏两种方式），关闭后 diff = 0 |
| 矩阵几何是否会因内容变化而漂移 | 我用像素实测而非假设 | 53 列 × 7 行游程稳定，365 个格心全部精确命中色板 |
| 红/蓝图主色提取是否只是"近似变色" | 容易被"看起来红了"骗过 | 采样值与我**独立重算**的预期值逐通道完全相同（`173,61,55` / `55,104,173` / `224,96,90`） |
| 深色主题下强调色是否照搬浅色值 | 若照搬则对比度不可读 | 深色 `224,96,90` ≠ 浅色 `173,61,55`，且等于我按深色参数重算的值 |
| 损坏音频会不会无限重试 | `MediaFailed` 里再调 `Next`，容易成环 | 双曲时失败 1 次后落到好曲目；单曲时 `failedCount >= tracks.Count` 直接 `Stop()`；8s 安静窗口 CPU 增量 0.62s / 0.02s |
| 新增字段会不会拖坏整份配置 | 上一轮的 F2 缺陷类 | 三种坏字段用例都只坏那一个字段，其余全保留；32 项往返零差异 |
| 手写非刻度 `BackgroundOpacity` 会不会被改写 | 滑块 `IsSnapToTickEnabled` 可能反向覆盖 | `0.42` 加载/退出后仍为 `0.42`，标签 `42%` |

---

## 6. 未能验证 / 存疑项

### 6.1 未能验证

1. **"每天"档（`BackgroundRotateMinutes=1440`）的真实定时轮换**：只能验证下拉档位与持久化的双向映射（`TxtBgInfo` 显示"每天轮换"、文件为 1440），无法等待 24 小时观察真实轮换。**5 分钟档的真实轮换已实测**（4.E.8：t=301.5s 触发，计时器未运行）。
2. **大屏模式下时钟的自动放大**：`MainWindow.xaml.cs:483` 有 `TxtClock.FontSize = Math.Clamp(size * 0.062, 12, 42)` 的缩放逻辑，但我本轮只在大屏测试中验证了窗口几何与最小化拦截，**没有**在大屏下复核时钟字号/位置。属未验证，不作结论。
3. **多显示器 / 跨屏巨幕、显示器热插拔、DPI 变化**：本机只有 1 台 1920×1080 显示器，虚拟桌面 = 主显示器，故 `Mega` 与 `Full` 几何相同，跨屏拼接与混合 DPI 未验证（与上一轮相同限制）。
4. **音频是否真的发声**：无音频采集手段，本轮只能证明"播放器进入 IsPlaying 状态、状态文本显示正在播放、按钮变为强调色、CPU/响应正常"。**没有**证明扬声器确有声音输出。
5. **跨午夜统计归零 / 连续天数递增的日界行为**：本轮恰好跨了午夜，但那次跨越是**在我的测试脚本里**发生的（见 4.C.0），我没有构造"应用运行中跨午夜"的场景（例如让统计窗口在午夜前后保持打开），因此 `RollDaily()` 的日界行为仍未实测。
6. **不透明度/背景图在超大图（4K/8K）下的内存表现**：测试图仅 320×240，未验证 `DecodePixelWidth=1920` 的限制效果。

### 6.2 存疑（观察项，未判定为缺陷）

**O1（nit）`ReadTolerant.GetBool` 把"无法解析的字符串"强制为 `false`，而不是回落到该字段的默认值。**

- 位置：`Services\AppSettings.cs:327-330`
  ```csharp
  JsonValueKind.String => value.GetString() is { } text &&
                          (bool.TryParse(text, out bool parsed)
                              ? parsed
                              : text is "1" or "yes" or "on"),
  ```
- 复现（`07-regression.ps1` G2-C）：`settings.json` 写 `"ShowClock": "oops"` → 退出后 `ShowClock=False`。而 `AppSettings.ShowClock` 的类默认值是 `true`，且 `"abc"` 这种坏 int 是会正确回落到默认值的（`BackgroundRotateMinutes: "abc"` → `0`）。
- 影响：手工编辑/被外部工具写坏配置时，这类开关会**静默关闭**而不是保持默认；`NoiseAutoPlayOnFocus`、`NoiseOnlyDuringFocus`（默认 true）、`BackgroundRotateOnFocus`、`BackgroundUseImageAccent`（默认 true）等**新增字段同样受影响**。不会崩溃、不会丢数据，只是"坏值的方向"与 int 字段不一致。
- 说明：这是**既有实现**的行为（上一轮 `AppSettings.cs` 已有同样的 `GetBool`），不是本轮新引入；只是因为本轮新增了多个默认值为 `true` 的布尔字段而变得更容易被触发。
- 建议（供作者参考）：无法解析时返回 `fallback` 而不是 `false`。

**O2（观察）统计窗口的"连续专注"与 `settings.json` 的 `StreakDays` 是两个独立计数器。**

- `StatsWindow.RenderSummary` 用 `FocusHistory.CurrentStreak`（`Services\FocusHistory.cs:135-149`：从今天/昨天向前数"分钟数 > 0"的连续天数）；
  `AppSettings.RecordFocusCompletion`（`Services\AppSettings.cs:117-131`）维护 `settings.json` 里的 `StreakDays`（依据 `LastCompletedDate` 是否为昨天）。
- 实测：基线自洽时两者一致（D 用例中都是 4）；基线不自洽时（我把 `StreakDays=3` 写进 settings 而 history 里没有 3 天连续记录）卡片显示 2，`settings.json` 显示 4。
- 影响：正常使用下两者同步（每次完成专注都会同时更新两处），只有在**两个文件被人为改成不一致**（例如 history.json 被删除或手改）时才会出现差异。可通过界面自行恢复。不判定为缺陷，仅记录数据来源差异。

**O3（观察）CSV 导出包含 `history.json` 里的所有键，包括 53 周矩阵窗口之外的日期。**

- 复现（`03-stats.ps1`）：我在 `history.json` 里放了一天 `2025-08-31`（应用当天往前 400 天，早于矩阵起点 `2025-10-06`）。这一天**不出现在矩阵里**，但出现在 `r3-export.csv` 第 2 行（`2025-08-31,130,4`），也被 `共 16 天有记录` 计入。
- 判断：与 `TxtRange`/`ValTotal` 的口径一致（"统计自本机数据文件"，全量统计），矩阵只是 53 周的显示窗口。属设计选择，不为缺陷。若作者希望 CSV 与矩阵严格一致，需要在导出时加日期范围过滤。

**O4（观察，测量方法）标题栏白噪音按钮的图形永远达不到画刷纯色。**

- 该按钮内容是细笔画图标字体，ClearType 抗锯齿下实测非背景像素的众数为 `RGB(166,149,166)`（停止）/ `RGB(170,169,221)`（播放），**不存在** `AccentBrush (0,120,212)` 的纯色像素（对照：`BtnStats` 的图标是实心矩形，含 38 个 `(0,120,212)` 纯色像素）。因此"按钮变色"只能通过**色偏**判定，不能通过精确颜色匹配判定。这不是应用缺陷，但任何想用像素断言这个按钮状态的脚本都必须知道这一点。

**O5（观察）`Process.MainWindowHandle` 在本构建上其实返回了正确的主窗口句柄**（探针实测 `9635594`），与任务描述的"不可靠"不同。我仍然全程使用自写的 `EnumWindows` 枚举（按标题 + 面积），因为应用确实同时拥有两个可见顶层窗口（主窗口与统计窗口），靠 `MainWindowHandle` 无法区分统计窗口。

---

## 7. 复现方式与产物清单

所有脚本均为本轮从零编写，位于 `verification\r3\`，可独立重跑（`pwsh -NoProfile -File <脚本>`）。公共库 `lib3.ps1`（自写 `EnumWindows` 窗口定位、`PrintWindow`/屏幕抓屏、C# 加速的位图 diff/统计、设置与历史读写、`keybd_event`/真实鼠标、UIA 封装、颜色断言）。

| 脚本 | 用途 | 结果 |
|---|---|---|
| `build-r3.ps1` | 独立编译 + 单文件发布到 `verify-dist-r3` | 0 警告 0 错误 |
| `lib3.ps1` | 自写公共辅助库 | — |
| `00-smoke.ps1` | 产物完整性 / 启动 / 双窗口定位 / 抓屏通路 | 11/11 |
| `02-clock.ps1` | 功能 1（PrintWindow 路径 + 开关 + 持久化） | 19/19 |
| `08-extras.ps1` | 功能 1（真实屏幕抓屏路径）+ 非刻度不透明度探针 | 8/8 |
| `03-stats.ps1` | 功能 2（矩阵几何/等级分桶/tooltip/卡片/CSV） | 43/43 |
| `04-history.ps1` | 功能 2 数据链路（真实 1 分钟专注 → history/settings/卡片） | 21/21 |
| `05-background.ps1` | 功能 3（红/蓝/文件夹轮换/不透明度/清除/重启/深色） | 37/37 |
| `06-noise.ps1` | 功能 4（导入/开关/下一首/损坏/循环/退出） | 37/37 |
| `07-regression.ps1` | G1 设置往返 / G2 容错 / G3 大屏 / G4 计数 | 26/26 |
| `09-probes.ps1` | 轮换映射 / 音量 / 缺失文件 / 随机播放 / 坏 history | 15/15 |
| `10-rotation.ps1` | 5 分钟定时轮换（真实等待 400s） | 6/6 |
| `probe-windows.ps1` | 顶层窗口枚举诊断（修正标题匹配） | — |
| `probe-dialog.ps1` | 原生文件/文件夹对话框 UIA 结构诊断 | — |
| `probe-grid.ps1` | 矩阵几何离线像素分析 | — |
| `probe-noisebtn.ps1` | 白噪音按钮字形颜色分析 | — |
| `build.log` / `publish.log` | 逐字编译与发布输出 | — |
| `hashes-start.txt` / `hashes-end.txt` | 冻结哈希两次核对 | 10/10 一致 |

截图（`verification\r3\`）：`r3-00-launch.png`、`r3-b1-clock-on-window.png`、`r3-b2-clock-on-zoom.png`、`r3-b3-clock-off-window.png`、`r3-c1-stats-window.png`、`r3-c2-hover-tooltip.png`、`r3-c3-hover-zoom.png`、`r3-d1-stats-after-focus.png`、`r3-e0-plain.png`、`r3-e1-light-red.png`、`r3-e2-restart-red.png`、`r3-e3-light-blue.png`、`r3-e4-opacity-100.png`、`r3-e5-cleared.png`、`r3-e6-folder-before-space.png`、`r3-e7-folder-after-space.png`、`r3-e8-dark-red.png`、`r3-f0-btn-stopped.png`、`r3-f1-btn-playing.png`、`r3-f2-noise-playing.png`、`r3-f3-noise-corrupt.png`、`r3-g1-bigscreen.png`、`r3-g2-after-esc.png`、`r3-h1-rotation-after.png`。

数据产物：`r3-export.csv`（CSV 导出的实测结果，作为 C.7 的证据保留）。

**收尾状态（已逐条核对）**

- 我启动的 `FluentPomodoro` 进程数：**0**。
- 全屏/置顶窗口：**无残留**（每个脚本末尾都退出大屏并 `Stop-Process`；测试结束后 `Get-Process FluentPomodoro` 为 0）。
- 我写入的 `%APPDATA%\FluentPomodoro\settings.json` 与 `history.json`：**均已删除**（`settings.json exists: False`、`history.json exists: False`，该目录下无文件）。
- 我临时生成的 `r3-tone-880.wav` / `r3-tone-880b.wav` / `r3-corrupt.wav`：已在脚本末尾删除。
- 作者的任何源文件、`artifacts\test-assets\`、`dist\`、`verify-dist`、`verify-dist-r2` 均未改动；我的产物保留在 `verify-dist-r3\`（SHA-256 `C696A58C…`）。
- 冻结源码哈希：测试前后**完全一致**。
