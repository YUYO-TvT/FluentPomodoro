# FluentPomodoro 第二轮独立复核报告（F1–F7 修复验证 + 回归）

- 复核对象：`C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro`（冻结版本）
- 复核方式：独立构建 → 独立单文件发布（`verify-dist-r2`）→ 全部针对**我自己的产物**做真实 UI 自动化（Win32 / SendKeys / keybd_event / PostMessage / 真实鼠标 / UI Automation / powercfg / DWM 读回 / IL 元数据扫描）
- 复核环境：Windows 11 build 26300、.NET SDK 10.0.401（另装 8.0.425）、PowerShell 7.6.6、单显示器 1920×1080 @ 96 DPI、键盘布局含 `0x08040804`（简体中文，`ImmIsIME=True`）
- **本轮未修改任何应用源代码**；新增内容全部位于 `verification\r2\`。
- 本轮唯一的外部对照：**上一轮**的冻结产物 `verify-dist\FluentPomodoro.exe`（SHA-256 `C302AFB2EB4CE376CD9D09A3BEEE374763A1C624DB7B111B4B6152D3E7619FFB`，与上一轮报告 2.2 节所记完全一致），仅用作 F5 的**反面对照**，不作为本轮任何"通过"结论的依据。

---

## 1. 结论

**F1–F7 七项修复全部独立复现确认（CONFIRMED FIXED），未发现任何功能回归。**

- 3 个 major（F1 主题、F2 配置容错、F3 `--mega --start`）：**全部确认已修复**，且修复方式经反面对照/像素读回/IL 扫描逐条证伪式验证。
- 4 个 minor（F4 最大化残留、F5 中文 IME 下裸字母快捷键、F6 `--focus` 写回、F7 单调时钟）：**全部确认已修复**。其中 F5 用"同一脚本 + 同一环境 + 上一轮旧产物"做了反面对照，旧产物 5/10 失败、新产物 10/10 通过，证明缺陷确实存在过且确实被修掉。
- 回归：计时/暂停、1 分钟完成计数、阶段与长休息循环（`跳过` 按钮真实调用）、强制大屏全套攻击、专注锁定、屏幕常亮、DWM 属性、设置往返、越界钳制 —— **全部通过**。
- 本轮共执行 **140 项检查**：其中 **138 项通过**，另 2 项"失败"是**我自己的预期写错**，实际上捕捉到一个**新增缺陷 N1**（见第 7 节）。
- 另发现 **1 个新增 minor（N1）+ 1 个新增 nit（N2）**。两者都不是计时/数据丢失类问题，但 N1 由 F1 修复引入，建议作者确认是否符合设计意图。

| 编号 | 上一轮严重度 | 本轮判定 | 一句话证据 |
|---|---|---|---|
| F1 保存主题被忽略 | major | **已修复** | `Theme=Dark` + 无参数启动 → 窗口背景像素 `32,32,32`（色板 `#202020`）；`Theme` 退出后仍为 `Dark`；`--light`/`--dark` 仍能覆盖 |
| F2 一个非法值丢弃整份配置 | major | **已修复** | `"Theme":"Bogus"` + 统计 5/150/42/7 → 其余 25 个字段逐字节保持不变，仅 `Theme→System`；`"FocusMinutes":"abc"` → 仅该字段回落 25 |
| F3 `--start` 被大屏参数吃掉 | major | **已修复** | `--mega --start` → `1920x1080 @(0,0)` **且** 8s 时标题 `24:53`、11s 时 `24:50` |
| F4 最大化后 Esc 不还原 | minor | **已修复** | `SC_MAXIMIZE` 后 `IsZoomed=False`、矩形不变；即使绕过 WndProc 用 `ShowWindow(SW_MAXIMIZE)`（`IsZoomed=True`），Esc 后仍 `640x780` 且 `IsZoomed=False` |
| F5 IME 吞掉 R/S/F | minor | **已修复** | HKL `0x08040804`、应用线程确有前台焦点时，`SendKeys 's'/'r'/'f'` 全部生效（10/10）；同脚本对上一轮旧产物仅 5/10 |
| F6 `--focus` 被写回 | minor | **已修复** | 文件 `FocusMinutes=33`，`--focus 7` 显示 `07:00`，退出后文件仍 `33`；`--focus 1` 真实跑完一个番茄后文件仍 `33` |
| F7 用墙钟而非单调时钟 | minor | **已修复** | 自建 IL 扫描：`MainWindow` 全部方法对 `System.DateTime` 的成员引用数 = **0**；`Stopwatch::get_Elapsed` 出现在 `ResetPhaseTimers/StartTimer/PauseTimer/OnTick` |

---

## 2. 冻结版本核对

任务给定的 6 个哈希，用 `(Get-FileHash <file> -Algorithm SHA256).Hash.Substring(0,16)` 逐一核对，**全部一致**；测试开始前（22:36）与全部测试结束后（23:01:49）各核一次，两次一致，说明测试期间源码未被改动。

```
=== 冻结哈希核对（开始前 22:36 与结束后 23:01:49 两次一致）===
MainWindow.xaml.cs           = 53D29238877730BF   (期望 53D29238877730BF)
Services\AppSettings.cs      = C332D83AA51C81EE   (期望 C332D83AA51C81EE)
Services\ChimePlayer.cs      = 1D3B3B401F599B42   (期望 1D3B3B401F599B42)
Interop\Native.cs            = 9315CD6211A77FA0   (期望 9315CD6211A77FA0)
App.xaml.cs                  = 9F4E10587C952489   (期望 9F4E10587C952489)
MainWindow.xaml              = E72E9181427CAB6F   (期望 E72E9181427CAB6F)
```

与上一轮的差异（供交叉参考）：`MainWindow.xaml.cs` `BE54DDFA…`→`53D29238…`、`AppSettings.cs` `3F3D5131…`→`C332D83A…`、`ChimePlayer.cs` `6BC0B774…`→`1D3B3B40…`、`Native.cs` `8C2FF899…`→`9315CD62…`；`App.xaml.cs` 与 `MainWindow.xaml` 未变。

---

## 3. 独立构建与运行

### 3.1 独立编译（任务给定命令，逐字输出）

```
PS> cd C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro
PS> dotnet build FluentPomodoro.csproj -c Release -v m
  正在确定要还原的项目…
  所有项目均是最新的，无法还原。
  FluentPomodoro -> C:\Users\Administrator\Documents\deepseek-harness\default-workspace\FluentPomodoro\bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll

已成功生成。
    0 个警告
    0 个错误

已用时间 00:00:03.01
EXITCODE=0
```

**无任何警告/错误文本可报告（0 warning / 0 error）**；原始输出存于 `build.log`。

### 3.2 独立单文件发布（任务给定命令，逐字输出）

```
PS> dotnet publish FluentPomodoro.csproj -c Release -r win-x64 --self-contained true \
      -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
      -p:EnableCompressionInSingleFile=true -o .\verify-dist-r2
  正在确定要还原的项目…
  所有项目均是最新的，无法还原。
  FluentPomodoro -> C:\...\bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll
  FluentPomodoro -> C:\...\FluentPomodoro\verify-dist-r2\
EXITCODE=0

Name                 Length
----                 ------
FluentPomodoro.exe 65976625
```

- 产物 `verify-dist-r2\FluentPomodoro.exe`，65,976,625 字节，目录内**仅此一个文件**（自包含单文件）。
- SHA-256：`3AC3C37807601D031937C52A78169E2EB39A707B1ADA4064311F23E04EE93255`（原始输出存于 `publish.log`）。
- **附带的可复现性观测**：作者自己的 `dist\FluentPomodoro.exe` 与我从源码独立发布的产物**字节数完全相同（65,976,625）且 SHA-256 完全相同**（`3AC3C378…`）。这说明冻结源码能确定性地产出同一二进制；本轮全部行为测试仍只使用我自己的 `verify-dist-r2` 产物。

### 3.3 启动与顶层窗口（`00-smoke.ps1`，5/5）

```
EXE   : ...\verify-dist-r2\FluentPomodoro.exe
SHA256: 3AC3C37807601D031937C52A78169E2EB39A707B1ADA4064311F23E04EE93255
[PASS] process alive 10s after launch :: HasExited=False
[PASS] owns a visible top-level window :: hwnd=1836150
[PASS] window opens at 640x780 :: 640x780 @ (640,126)
[PASS] title is 25:00 / 专注 / 微软风格番茄钟 :: title='25:00 · 专注 · 微软风格番茄钟'
virtual desktop = 1920x1080 @ (0,0)  monitor count=1
window colour profile: modal=243,243,243 (221/270) distinct=12 avgR=231
[PASS] output dir contains exactly one file :: 1 files: FluentPomodoro.exe
```

启动界面：`r2-01-launch-640x780.png`（640×780，标题 `25:00 · 专注 · 微软风格番茄钟`）。

![独立发布产物启动](r2-01-launch-640x780.png)

> 方法说明：`Process.MainWindowHandle` 在本应用上不可靠（WPF 有多个隐藏顶层窗口）。我自写 `EnumWindows + GetWindowThreadProcessId`，取该进程**面积最大的可见顶层窗口**（`lib2.ps1:Get-AppWindow`），与作者工具无关。

---

## 4. 逐项复核 F1–F7

### F1 保存的主题在启动时被忽略 —— **已修复（CONFIRMED）**

脚本 `f1-theme.ps1`（13 项检查；11 通过，2 项"失败"实为新增缺陷 N1，见第 7 节）。每个用例都写入**全部 26 个键**的合法 JSON，且 `UseMicaBackdrop=false` 以排除 Mica 采样壁纸对像素的干扰；退出走真实的 `Ctrl+Shift+Q`（触发 `OnWindowClosing` → 保存）。

| 用例 | 启动参数 | 窗口背景众数像素 | 左边缘 4 点采样 | 判定 |
|---|---|---|---|---|
| 文件 `Theme=Dark` | 无 | `32,32,32` | 全部 `32,32,32` | **深色 ✔** |
| 文件 `Theme=Light` | 无 | `243,243,243` | 全部 `243,243,243` | 浅色 ✔ |
| 文件 `Theme=System` | 无 | `243,243,243` | 全部 `243,243,243` | 浅色（本机系统为浅色）✔ |
| 文件 `Theme=Dark` | `--light` | `243,243,243` | 全部 `243,243,243` | **命令行覆盖生效 ✔** |
| 文件 `Theme=Light` | `--dark` | `32,32,32` | 全部 `32,32,32` | **命令行覆盖生效 ✔** |
| 文件 `Theme=Dark` | `--dark` | `32,32,32` | 全部 `32,32,32` | 深色 ✔ |

- 像素来自真实屏幕读回（`GetDC(NULL)+GetPixel`，网格采样 270 点取众数），深色 `#202020`=32、浅色 `#F3F3F3`=243，与 `Themes\Palette.*.xaml` 的 `WindowBackdropBrush` 完全对应；同时落盘 PNG 截图。
- **`settings.json` 的 `Theme` 在无参数启动/退出后保持不变**：`Dark→Dark`、`Light→Light`、`System→System`（全部 PASS）。这也覆盖了上一轮报告怀疑的"`ApplySettingsToUi` 写 `CmbTheme.SelectedIndex` 会不会反向覆盖文件"——实测不会。
- 代码走查一致：`MainWindow.xaml.cs:66-69` 在建界面之前执行 `var theme = App.Options.ForceLightDark ?? _settings.Theme; _settings.Theme = theme; ThemeManager.SetPreference(theme);`。

截图：`r2-f1-saved-dark-plain.png`（深色 `#202020`）、`r2-f1-saved-light-plain.png`、`r2-f1-saved-dark-forcelight.png`、`r2-f1-saved-light-forcedark.png`。

![保存 Dark + 无参数启动 = 深色](r2-f1-saved-dark-plain.png)

**副作用（新增缺陷 N1）**：`--light` / `--dark` 会被**写回** `settings.json`（表中 `saved-dark-forcelight`：退出后文件 `Theme=Light`；`saved-light-forcedark`：退出后 `Theme=Dark`）。详见第 7 节。

### F2 一个非法值丢弃整份配置与统计 —— **已修复（CONFIRMED）**

脚本 `f2-tolerant.ps1`，**26/26 通过**。每个用例：写文件 → 启动（7s）→ 确认真实顶层窗口存在（无对话框、无崩溃）→ `Ctrl+Shift+Q` 干净退出 → 逐字段对比。

**用例 A：`"Theme":"Bogus"`（非法枚举）+ 统计完好**（`StatsDate` = 今天 `2026-10-04`）

| 字段 | 启动前 | 退出后 | | 字段 | 启动前 | 退出后 |
|---|---|---|---|---|---|---|
| **Theme** | `Bogus` | **`System`** | | StatsDate | `2026-10-04` | `2026-10-04` |
| FocusMinutes | 45 | 45 | | **CompletedToday** | **5** | **5** |
| ShortBreakMinutes | 7 | 7 | | **FocusMinutesToday** | **150** | **150** |
| LongBreakMinutes | 20 | 20 | | **TotalCompleted** | **42** | **42** |
| LongBreakInterval | 3 | 3 | | **StreakDays** | **7** | **7** |
| AutoStartNext | false | false | | LastCompletedDate | `2026-10-04` | `2026-10-04` |
| SoundEnabled / KeepScreenAwake / AlwaysOnTop / NotifyOnPhaseEnd / FocusLock / AutoBigScreenOnFocus | 全 false | 全 false | | UseMicaBackdrop / BigScreenTopmost | false | false |
| BigScreen | `Full` | `Full` | | WindowWidth/Height | 640/780 | 640/780 |
| （仅 `HasWindowBounds` 0→true、`WindowLeft/Top` 0→640/126 属窗口位置记忆，设计如此） | | | | | | |

→ **唯一变化的字段就是那个非法字段**（`Theme Bogus → System`），统计 5/150/42/7 全部原样保留。窗口标题 `45:00`，说明 `FocusMinutes` 也确实生效。

**用例 B：类型错误 `"FocusMinutes":"abc"`**

| 字段 | 启动前 | 退出后 |
|---|---|---|
| **FocusMinutes** | `"abc"` | **`25`**（该字段回落默认） |
| CompletedToday | 2 | **2** |
| FocusMinutesToday | 30 | **30** |
| TotalCompleted | 9 | **9** |
| StreakDays | 1 | **1** |
| StatsDate | 2026-10-04 | 2026-10-04 |
| Theme | `Light` | `Light` |
| AutoStartNext / AutoBigScreenOnFocus | false / false | false / false |

（用例 B 的 JSON 里我没有写 `ShortBreakMinutes` 等键，退出后被补成各自默认值 5/15/4/… —— 属"文件里本来没有该键"，不是数据丢失。）

**用例 C（对照）：截断的 JSON** `{"FocusMinutes":25,"StatsDate":"2026-10-04","TotalCompleted":11,`
→ 应用正常启动、无对话框，退出后文件被重写为合法全默认值（`TotalCompleted=0`）。这是**不可避免**的（文件本身无法解析，`JsonDocument.Parse` 失败），与上一轮行为一致，不算缺陷。

代码走查一致：`AppSettings.cs:135-167` 两级解析，失败后 `ReadTolerant()` 逐字段容错（`GetInt/GetBool/GetDouble/GetString/GetEnum` 各自带 fallback），最后才 `Normalize()+RollDaily()`。

### F3 `--mega/--bigscreen` 与 `--start` 同时给出时 `--start` 被忽略 —— **已修复（CONFIRMED）**

脚本 `f3-mega-start.ps1`，**12/12 通过**（虚拟桌面 `1920x1080 @(0,0)`）。

| 用例 | 8s 时矩形 | 8s 标题 | 11s 标题 | 判定 |
|---|---|---|---|---|
| `--mega --start` | `1920x1080 @ (0,0)` | `24:53 · 专注` | `24:50 · 专注` | **覆盖全屏 ✔ 且 立刻倒计时 ✔** |
| `--bigscreen --start` | `1920x1080 @ (0,0)` | `24:53 · 专注` | `24:50 · 专注` | 同上 ✔ |
| `--mega`（对照） | `1920x1080 @ (0,0)` | `25:00 · 专注` | `25:00 · 专注` | 只进大屏、不自动开始 ✔（符合预期） |
| `--start`（对照） | `640x780 @ (640,126)` | `24:52 · 专注` | `24:49 · 专注` | 只倒计时、不进大屏 ✔ |

四个用例 Esc 后均精确回到 `640x780 @ (640,126)`。截图：`r2-f3-mega-start.png`、`r2-f3-bigscreen-start.png`、`r2-f3-mega-only.png`、`r2-f3-start-only.png`。

代码走查一致：`MainWindow.xaml.cs:152-162` 由上一轮的 `if (StartBigScreen) {...} else if (AutoStartTimer) {...}` 改为两个**互相独立**的 `if`，且都用 `Dispatcher.BeginInvoke(DispatcherPriority.Loaded, …)`。

### F4 大屏下被最大化后 Esc 不还原 640×780 —— **已修复（CONFIRMED）**

脚本 `f4-maximize.ps1`，**9/9 通过**。

| 步骤 | 观测值 |
|---|---|
| 启动 | `640x780 @ (640,126)`，`IsZoomed=False` |
| F11 进大屏 | `1920x1080 @ (0,0)`，`IsZoomed=False` |
| 发 `WM_SYSCOMMAND SC_MAXIMIZE (0xF030)` | **`IsZoomed=False`，矩形仍 `1920x1080 @ (0,0)`**（WndProc 直接拦截） |
| 按 Esc | **`640x780 @ (640,126)`，`IsZoomed=False`** |
| 再次进大屏 + **绕过 WndProc** 用 `ShowWindow(SW_MAXIMIZE)` | `IsZoomed=True`，`1920x1080`（真正的"已最大化"状态） |
| 按 Esc | **`640x780 @ (640,126)`，`IsZoomed=False`** |

第二条路径是关键的"修复是否只靠拦截、而没修真正的还原逻辑"的证伪测试：即使窗口真的进入 `IsZoomed=True`，Esc 也能还原，说明 `ExitBigScreen` 里的 `WindowState = Normal` 复位确实生效（`MainWindow.xaml.cs:503-504`）。截图：`r2-f4-after-sc-maximize.png`、`r2-f4-after-esc.png`。

### F5 中文 IME 激活时裸字母 R/S/F 失效 —— **已修复（CONFIRMED，含反面对照）**

脚本 `f5-ime.ps1`。为保证这不是"环境恰好变了"，我先复现了上一轮的测试条件，并用**上一轮的冻结产物**做同脚本对照。

**测试条件复现（新产物）**

```
HKL[0] = 0x08040804  IsIME=True          <- 简体中文 IME
HKL[1] = 0x04090409  IsIME=True
app thread id = 13012   HKL(app thread) = 0x08040804      <- 与上一轮记录的 HKL 完全一致
requested HKL 0x08040804  -> HKL(app thread) now = 0x08040804
[PASS] test condition: app thread is on the Chinese (08040804) layout
Activate-App returned True
foreground window: hwnd=459772 pid=11868 class='HwndWrapper[FluentPomodoro;;8801dadb-…]'   app hwnd=459772 app pid=11868
[PASS] the app really owns the keyboard focus when SendKeys is used
```

即：**应用线程 HKL = `0x08040804`（中文 IME），且前台窗口确实属于被测进程**（我用真实鼠标点击窗口取得焦点，并断言 `GetForegroundWindow` 的 pid == 应用 pid）。焦点这一条是我额外加的，因为本轮发现 `SetForegroundWindow` 在某些时刻会被系统前台锁拒绝；如果不加这条断言，`SendKeys` 可能根本没送进应用，结论会不可信。

**同一脚本、同一环境，两个产物的对照结果**

| 用例（`SendKeys` / 硬件 `keybd_event`） | 新产物 `verify-dist-r2` | 上一轮旧产物 `verify-dist` |
|---|---|---|
| `SendKeys 's'` 跳过 → 短休息 | **`05:00 · 短休息`** PASS | `25:00 · 专注`（无变化）**FAIL** |
| `SendKeys 's'` 再按 → 专注 | PASS | （假通过，标题本来就是专注） |
| `SendKeys 'r'` 重置（先把计时跑起来） | **`24:57` → `25:00`** PASS | `25:00` 不动（连空格都没起来）**FAIL** |
| `SendKeys 'f'` 窗口→全屏 | **`1920x1080`** PASS | `640x780` **FAIL** |
| `SendKeys 'f'` 全屏→巨幕 | **`1920x1080`** PASS | `640x780` **FAIL** |
| `SendKeys 'f'` 巨幕→窗口 | **`640x780`** PASS | `640x780`（假通过） |
| 硬件路径 `keybd_event 'S'` → 短休息 | **`05:00 · 短休息`** PASS | `25:00 · 专注` **FAIL** |
| **合计** | **10 / 10 通过** | **5 / 10 通过** |

两次运行的 HKL 都是 `0x08040804`，前台都属于被测进程。**同一测量方法在旧产物上失败、在新产物上通过**，这是 F5 修复最强形式的证据（同时排除了"我的方法测不出这个缺陷"的可能）。截图 `r2-f5-after-skip-s.png`（标题已变 `05:00 · 短休息`）。

代码走查一致：`MainWindow.xaml.cs:82-83` `InputMethod.SetIsInputMethodEnabled(this, false)`；`MainWindow.xaml.cs:897-898` `var key = e.Key == Key.ImeProcessed ? e.ImeProcessedKey : e.Key;`。

### F6 `--focus N` 被永久写回配置 —— **已修复（CONFIRMED）**

脚本 `f6-focus-override.ps1`，**8/8 通过**。预先在文件里放 `FocusMinutes=33`（非默认值，避免"恰好等于默认值"的假通过）。

| 检查 | 观测值 |
|---|---|
| `--focus 7` 本次会话生效 | 标题 `07:00 · 专注`（文件此时仍是 33） |
| `--focus 7` 退出后不写回 | 文件 `FocusMinutes = 33`（前 33 → 后 33） |
| **加强项**：`--focus 1 --start` 真实跑完一个番茄 | 56.4s 后标题切到 `05:00 · 短休息` |
| 完成后 `FocusMinutesToday` | `1`（用的是被覆盖的 1 分钟，计入今日分钟数） |
| 完成后 `CompletedToday` / `TotalCompleted` / `StreakDays` | `1` / `1` / `1` |
| **完成并退出后文件里的 `FocusMinutes`** | **仍为 `33`** |

即：会话内确实按 `--focus` 的时长计时并据此记账，但原值不会被覆盖持久化。代码走查一致：`MainWindow.xaml.cs:278-292` 的 `SaveSettings()` 在写盘前临时把 `_settings.FocusMinutes` 换回 `_originalFocusMinutes`，写完再换回来。截图 `r2-f6-focus1-completed.png`。

### F7 倒计时必须使用单调 `Stopwatch` —— **已修复（CONFIRMED）**

脚本 `f7-stopwatch.ps1`，**4/4 通过**。我从三个层次验证，而不是只看一眼源码：

**（1）源码 grep（计时路径）** —— 计时相关的 5 处引用全部是 `Stopwatch`；整个 `MainWindow.xaml.cs` 的 180–250 行计时区域**没有任何 `DateTime`**：

```
MainWindow.xaml.cs:34:  private TimeSpan _deadline;          // 相对单调时钟（Stopwatch）的截止点
MainWindow.xaml.cs:38:  private static readonly Stopwatch Clock = Stopwatch.StartNew();
MainWindow.xaml.cs:190: _deadline = Clock.Elapsed + _remaining;      // ResetPhaseTimers
MainWindow.xaml.cs:204: _deadline = Clock.Elapsed + _remaining;      // StartTimer
MainWindow.xaml.cs:213: if (_running) _remaining = _deadline - Clock.Elapsed;   // PauseTimer
MainWindow.xaml.cs:231: var left = _deadline - Clock.Elapsed;        // OnTick
AppSettings.cs:73/94/95: DateTime.Today / TryParse / MinValue        （仅为"日历天/连续天数"用，与计时路径无关）
```

**（2）对我自己发布的 Release 程序集做 IL 成员引用扫描**（`System.Reflection.Metadata` 读取 `bin\Release\net8.0-windows\win-x64\FluentPomodoro.dll`，token 级匹配，非字符串匹配）：

```
MEMBERREFS to System.DateTime   : 8
   0x0A0000F4 System.DateTime::get_Today      0x0A0000F8 System.DateTime::MinValue
   0x0A0000F5 System.DateTime::ToString       0x0A0000F9 System.DateTime::get_Date
   0x0A0000F7 System.DateTime::TryParse       0x0A0000FA op_Inequality
                                              0x0A0000FB AddDays   0x0A0000FC op_Equality
MEMBERREFS to Stopwatch         : 2
   0x0A000065 System.Diagnostics.Stopwatch::get_Elapsed
   0x0A0000F1 System.Diagnostics.Stopwatch::StartNew

methods whose IL mentions a member-ref token:
  [Stopwatch] FluentPomodoro.MainWindow::ResetPhaseTimers -> get_Elapsed
  [Stopwatch] FluentPomodoro.MainWindow::StartTimer       -> get_Elapsed
  [Stopwatch] FluentPomodoro.MainWindow::PauseTimer       -> get_Elapsed
  [Stopwatch] FluentPomodoro.MainWindow::OnTick           -> get_Elapsed
  [Stopwatch] FluentPomodoro.MainWindow::.cctor           -> StartNew
  [DateTime]  FluentPomodoro.Services.AppSettings::get_Today            -> get_Today, ToString
  [DateTime]  FluentPomodoro.Services.AppSettings::RecordFocusCompletion -> get_Today, TryParse, MinValue, get_Date, op_Inequality, AddDays, op_Equality
[PASS] no MainWindow method references System.DateTime in IL :: MainWindow DateTime refs: 0
[PASS] timer methods reference Stopwatch (positive control) :: get_Elapsed x4, StartNew
```

`Stopwatch` 恰好出现在源码指明的 4 个计时方法中（这是本次扫描方法的**阳性对照**，证明扫描确实能发现计时调用），而 `DateTime` 在 `MainWindow` 中**一次都不出现**，只出现在 `AppSettings` 的日历统计里 —— 与上一轮"全程 `DateTime.UtcNow`"的形态彻底不同。

**（3）行为：以独立单调秒表为基准采样 39.3s（27 个样本）**

```
t=  0.0s app=1497s   t=15.2s app=1481s   t=30.3s app=1466s
t=  1.5s app=1495s   t=16.7s app=1480s   t=31.8s app=1465s
...（单调递减，无跳变）
t= 39.3s app=1457s
[PASS] countdown decrements 1:1 with the monotonic clock :: app elapsed=40 s, monotonic elapsed=39.3 s, diff=0.7 s
[PASS] displayed remaining never increases
```
差值 0.7s 完全落在"200ms tick + 显示 `Ceiling` 取整"的量化误差内，无累计漂移。

**明确声明（不夸大）**：任务禁止修改系统时钟，我**没有**改系统时钟，因此"系统时间被 NTP 步进/手工调整时不影响倒计时"这一点是**由源码与 IL 静态证明**的（计时路径不存在任何墙钟读取），而不是由实验证明的。

---

## 5. 回归测试

全部针对我自己的 `verify-dist-r2` 产物。每项检查都列出脚本、项数与观测值。

### 5.1 空格启停 / 暂停冻结 / 屏幕常亮 / 1 分钟完成计数（`reg-a-timer.ps1`，17/17）

| 检查 | 观测值 | 结果 |
|---|---|---|
| 启动 `01:00 · 专注` | title=`01:00 · 专注 · 微软风格番茄钟` | PASS |
| 空闲时 `powercfg /requests` 无本进程 | 无 FluentPomodoro | PASS |
| 空格开始 | `00:57 · 专注` | PASS |
| 专注运行中持有常亮请求 | `DISPLAY:` 与 `SYSTEM:` 均列出 `[PROCESS] ...\verify-dist-r2\FluentPomodoro.exe` | PASS |
| **空格暂停后倒计时冻结（6s）** | `00:57` \| `00:57` 严格不变 | PASS |
| 暂停即释放常亮 | `powercfg /requests` 不再含本进程 | PASS |
| 继续后时间守恒 | 冻结值 57 → 12s 后 45（Δ=12s，墙钟 12s） | PASS |
| 1 分钟专注跑完 → 短休息 | 46.3s 后 `05:00 · 短休息` | PASS |
| 阶段结束释放常亮 | 无本进程 | PASS |
| 底部统计文本 | `今日 1 个番茄 · 1 分钟 · 连续 1 天` | PASS |
| **+10s 后统计不重复计数** | `CompletedToday=1`（仍为 1） | PASS |
| `FocusMinutesToday` / `TotalCompleted` / `StreakDays` | `1` / `1` / `1` | PASS |
| `StatsDate` / `LastCompletedDate` | 均为 `2026-10-04` | PASS |
| `AutoStartNext=false` 时休息不自启 | 维持 `05:00 · 短休息` | PASS |
| 退出后统计持久化 | `CompletedToday=1`、`TotalCompleted=1` | PASS |
| 退出后时长保留 | `FocusMinutes=1` | PASS |

截图：`r2-reg-paused.png`、`r2-reg-break.png`。

### 5.2 阶段 / 长休息循环（用真实的「跳过」按钮，`reg-b-cycle.ps1`，2/2）

通过 UI Automation `InvokePattern` 调用真实的「跳过」按钮（`OnSkip` 的鼠标路径），逐次读回标题与 `TxtRound`：

```
interval=4: F[第 1 / 4 个番茄] -> S[短休息] -> F[第 2 / 4] -> S -> F[第 3 / 4] -> S -> F[第 4 / 4]
            -> L[长休息 · 本轮已完成] -> F[第 1 / 4] -> S -> F[第 2 / 4] -> S -> F[第 3 / 4]      PASS
interval=2: F[第 1 / 2] -> S -> F[第 2 / 2] -> L -> F[第 1 / 2] -> S -> F[第 2 / 2] -> L -> F[第 1 / 2] -> S   PASS
```

即 `LongBreakInterval=4` 时严格为 **F S F S F S F L F S F S F**，第 4 个番茄后进长休息，长休息后轮次回到「第 1 / 4」。

### 5.3 强制大屏全套攻击 + DWM 读回（`reg-c-bigscreen.ps1`，16/16）

| 检查 | 观测值 | 结果 |
|---|---|---|
| Mica 开 → `SYSTEMBACKDROP_TYPE` | `2` (hr=0) | PASS |
| 窗口模式圆角 | `CORNER_PREFERENCE=2` (Round) | PASS |
| 浅色 → `IMMERSIVE_DARK_MODE` | `0` | PASS |
| F11 铺满整个虚拟桌面 | `1920x1080 @ (0,0)`（虚拟桌面 `0,0,1920,1080`） | PASS |
| 大屏圆角 | **`CORNER_PREFERENCE=1`** (DoNotRound) | PASS |
| 大屏置顶 | `exstyle=0x8`（`WS_EX_TOPMOST`） | PASS |
| 外部 `SetWindowPos(800x600 @100,100)` 被拒 | 前 `1920x1080@(0,0)` → 后完全相同 | PASS |
| `WM_SYSCOMMAND SC_MINIMIZE` 被拦截 | `IsIconic=False`，仍 `1920x1080` | PASS |
| `ShowWindow(SW_MINIMIZE)` 被拦截 | `IsIconic=False`，仍 `1920x1080` | PASS |
| **Win+D 不最小化大屏窗口** | `IsIconic=False`、`visible=True`、仍 `1920x1080 @(0,0)` | PASS |
| Esc 精确恢复 | `640x780 @ (640,126)` | PASS |
| 退出大屏后圆角 | `CORNER_PREFERENCE=2` | PASS |
| 大屏不污染窗口尺寸 | 仍 `640x780` | PASS |
| Mica 关 → `SYSTEMBACKDROP_TYPE` | `0` | PASS |
| 保存 `Theme=Dark` → `IMMERSIVE_DARK_MODE` | `1` | PASS |

截图：`r2-reg-winD.png`、`r2-reg-restored.png`。

### 5.4 专注锁定与强制退出（`reg-d-focuslock.ps1`，7/7）

`FocusLock=true` 且专注运行中（`24:57 · 专注`，已断言应用确为前台进程）：

| 检查 | 观测值 | 结果 |
|---|---|---|
| `WM_CLOSE` 被否决 | `HasExited=False` | PASS |
| `WM_SYSCOMMAND SC_CLOSE` 被否决 | `HasExited=False` | PASS |
| **真实标题栏关闭按钮**（UIA `InvokePattern`，与鼠标点击同一路径）被否决 | `clicked=True`、`HasExited=False` | PASS |
| 最小化被拦截 | `IsIconic=False` | PASS |
| **`Ctrl+Shift+Q` 必定退出** | `HasExited=True` | PASS |
| 无专注运行时关闭按钮恢复正常 | `clicked=True`、`exited=True` | PASS |

截图 `r2-reg-focuslock.png`。

### 5.5 设置往返 + 越界钳制（`reg-e-settings.ps1`，11/11）

预置 **19 个非默认值**（`FocusMinutes=7、ShortBreak=3、LongBreak=9、Interval=7`；`AutoStartNext/Sound/KeepAwake/Notify/AlwaysOnTop/FocusLock/AutoBigScreenOnFocus/BigScreenTopmost/Mica` 全 false；`Theme=Dark`、`BigScreen=Full`；窗口 `600x700 @(200,150)`），执行「启动 → 打开设置面板（真实按钮 `BtnSettings`）→ 关闭 → 退出」：

- 窗口按记忆的边界打开：`600x700 @ (200,150)` ✔
- 设置面板确实打开：`SldFocus` 的 UIA 包围盒 `380,252,391,32`，落在窗口内 ✔
- UIA 读回的控件值与文件一致：滑块 `focus=7 short=3 long=9 interval=7`；9 个开关全部 `Off` ✔
- **退出后与写盘值逐字段对比：0 处差异**（`FocusMinutes` 7→7、`ShortBreakMinutes` 3→3、`LongBreakMinutes` 9→9、`LongBreakInterval` 7→7、9 个布尔全 false→false、`Theme` Dark→Dark、`BigScreen` Full→Full、窗口 200/150/600/700 全部不变）✔
- 越界值：`FocusMinutes 999 → 120`（标题 `2:00:00 · 专注 · 微软风格番茄钟`）、`ShortBreakMinutes 0 → 1`、`LongBreakMinutes -5 → 5`、`LongBreakInterval 99 → 12` ✔

截图：`r2-reg-settings-open.png`（深色设置面板，滑块 7/3/9/7、开关全关）、`r2-reg-range.png`（`2:00:00`）。

![设置面板：19 个非默认值全部正确回显](r2-reg-settings-open.png)

### 5.6 上一轮 nit 类修复的抽查（非任务要求，附带核实）

| 项 | 观测 |
|---|---|
| 提示音 GCHandle 不释放（F10） | `ChimePlayer.cs:87-93` 新增 `Release()`，`if (_focusHandle.IsAllocated) _focusHandle.Free();` 同 `_breakHandle`；`MainWindow.OnClosed` 调用 `ChimePlayer.Release()` |
| `Native.cs` 29 个未用声明（F9） | 以 `\b名称\b` 统计全仓库引用，**真实未被引用声明 = 0**（正则报出的 2 个是结构体字段名 `rcWork`/`hwndInsertAfter`，属误报） |
| 主题静态事件泄漏（F11） | `MainWindow.xaml.cs:117-130` 保存 `_themeChangedHandler` 并在 `OnClosed` 中 `-=` 退订、停表 |
| 保存失败静默吞掉（F13） | `SettingsStore.LastSaveError` + `SaveSettings()` 失败时 `ShowToast("设置保存失败：…")`，只提示一次 |

---

## 6. 未能验证 / 存疑项

1. **墙钟跳变的实验验证**：任务禁止改系统时钟，故 F7 的"系统时间跳变不影响倒计时"只能静态证明（源码 grep + IL 成员引用扫描），未做实验。我未修改系统时钟。
2. **多显示器「巨幕跨屏」**：本机仅 1 台 1920×1080 显示器，虚拟桌面 = 主显示器，因此 `Mega` 与 `Full` 的几何结果相同（都是 `1920x1080 @(0,0)`）。跨屏拼接、混合 DPI、负坐标摆放**未验证**。
3. **显示器热插拔 / `WM_DISPLAYCHANGE`**：无法制造显示器移除事件，`MainWindow.xaml.cs:770-780` 的重适配分支**未实测**。
4. **DPI 变化（`OnDpiChanged`）**：会话固定 96 DPI，未改系统缩放，未验证。
5. **提示音是否真的发声**：无音频采集手段，仅确认调用不抛异常、界面有「试听提示音」按钮。
6. **跨午夜统计归零 / 连续天数递增**：`RollDaily()`/`RecordFocusCompletion()` 逻辑走查正确（`StatsDate != Today` 才归零；`last == today-1` 才 +1），但未在真实跨午夜条件下运行。
7. **`--dark` 写回是否属于"有意设计"**：见第 7 节 N1。README 第 27 行只说"优先级高于配置文件里的主题"，未说明是否持久化；而 `--focus` 在第 26 行明确承诺"仅本次会话生效，退出时不会写回配置文件"。两者行为不一致，需要作者确认意图。
8. **`SC_RESTORE` 在大屏中被一并拦截**（`MainWindow.xaml.cs:762-767` 同时拦 `SC_MAXIMIZE` 与 `SC_RESTORE`）：对功能无可见影响（大屏本身就是全屏矩形），但意味着大屏期间外部程序无法用 `SC_RESTORE` 恢复该窗口。属观察项，未判定为缺陷。
9. **自动化方法上的一个注意点**（不是应用缺陷）：`SetForegroundWindow` 在本机会被前台锁偶尔拒绝，导致硬件按键/SendKeys 可能送不到被测窗口。我在 F5 中显式断言了"前台窗口属于被测进程"，并在其余脚本中对不需要真实焦点的按键改用 `PostMessage`；因此早期一次 F5 运行（未加焦点断言）的 9/9 结果**不可信**，本报告采用的是加断言后的 10/10 + 反面对照 5/10。

---

## 7. 新增缺陷

### N1（**minor**，由 F1 修复引入）`--light` / `--dark` 会被永久写入 `settings.json`

- 位置：`MainWindow.xaml.cs:67-69`
  ```
  var theme = App.Options.ForceLightDark ?? _settings.Theme;
  _settings.Theme = theme;                 // 命令行值被赋给"将被保存"的设置对象
  ThemeManager.SetPreference(theme);
  ```
  随后 `OnWindowClosing → SaveSettings()` 整份保存，命令行主题因此落盘。
- 复现（`f1-theme.ps1`，两个用例均干净退出）：
  1. `settings.json` 写入 `"Theme":"Dark"`（其余键合法）→ 以 `--light` 启动 → 窗口渲染浅色 `243,243,243`（覆盖生效）→ `Ctrl+Shift+Q` 退出 → **文件变为 `"Theme":"Light"`**（期望仍为 `Dark`）。
  2. `settings.json` 写入 `"Theme":"Light"` → `--dark` 启动 → 渲染深色 `32,32,32` → 退出 → **文件变为 `"Theme":"Dark"`**。
- 影响：用户只想"临时看一眼深色"，一次启动就把保存的偏好永久改掉；下次不带参数启动仍是深色。无数据丢失、可通过设置面板改回，故 minor。
- 与 `--focus` 的不一致：README:26 明确承诺 `--focus` "仅本次会话生效，退出时不会写回配置文件"，且作者已用 `_focusOverrideActive` 实现；`--dark/--light` 缺少同类保护。**上一轮的代码不会写回**（上一轮 `_settings.Theme` 从未由命令行赋值），因此这是 F1 修复引入的行为变化。
- 建议（供作者参考）：与 `--focus` 同样加 `_themeOverrideActive` 守卫，或在 README 中明确"`--dark/--light` 会持久化"。

### N2（**nit**）`--focus` 会话期间在设置面板改动专注时长不会被持久化

- 位置：`MainWindow.xaml.cs:278-292`（`SaveSettings` 无条件把 `_settings.FocusMinutes` 换回 `_originalFocusMinutes`）。
- 复现（`probe-focus-slider.ps1`）：文件 `FocusMinutes=33` → `--focus 7` 启动（标题 `07:00`）→ 打开设置面板 → UIA `RangeValuePattern.SetValue(20)`（等价于用户拖动滑块，`OnDurationChanged` 真实触发）→ 会话内**确实生效**（滑块读回 `20`、标题 `20:00`、标签 `20 分钟`）→ 退出后 **`settings.json` 仍为 `33`**。
- 影响：用户在当前会话里主动改的时长被静默丢弃。属"会话级覆盖"设计的边界情形，可争议（也可解释为符合 `--focus` 语义），故列为 nit 而非缺陷。
- 建议（供作者参考）：在设置面板里显式改动时取消覆盖（`_focusOverrideActive = false`）。

---

## 8. 复现方式与产物清单

所有脚本均为本轮我从零编写，位于 `verification\r2\`，可独立重跑（`pwsh -NoProfile -File <脚本>`）。公共辅助在 `lib2.ps1`（自写 `EnumWindows` 窗口定位、屏幕像素读回、截图、`SendKeys`/`keybd_event`/`PostMessage`、真实鼠标点击取焦点、UIA 封装、`settings.json` 读写）。

| 脚本 | 用途 | 结果 |
|---|---|---|
| `lib2.ps1` | 自写公共辅助库 | — |
| `00-smoke.ps1` | 独立发布产物启动 / 640×780 / 标题 | 5/5 |
| `f1-theme.ps1` | F1 保存主题 + 命令行覆盖 | 11 通过 / 2 = N1 |
| `f2-tolerant.ps1` | F2 非法枚举 / 类型错误 / 截断 JSON | 26/26 |
| `f3-mega-start.ps1` | F3 `--mega --start` 等 4 组 | 12/12 |
| `f4-maximize.ps1` | F4 `SC_MAXIMIZE` / `ShowWindow(SW_MAXIMIZE)` + Esc | 9/9 |
| `f5-ime.ps1` | F5 中文 IME 下 R/S/F（含前台焦点断言） | 新 10/10；旧产物对照 5/10 |
| `f6-focus-override.ps1` | F6 `--focus` 不写回（含真实完成一次专注） | 8/8 |
| `f7-stopwatch.ps1` | F7 源码 grep + IL 扫描 + 单调性采样 | 4/4 |
| `reg-a-timer.ps1` | 空格启停/暂停冻结/常亮/1 分钟完成计数 | 17/17 |
| `reg-b-cycle.ps1` | 阶段与长休息循环（真实「跳过」按钮） | 2/2 |
| `reg-c-bigscreen.ps1` | 强制大屏攻击 + DWM 读回 | 16/16 |
| `reg-d-focuslock.ps1` | 专注锁定 / `WM_CLOSE` / 强制退出 | 7/7 |
| `reg-e-settings.ps1` | 设置往返（19 值）+ 越界钳制 | 11/11 |
| `probe-keys.ps1` / `probe-focus-slider.ps1` / `probe-addtype.ps1` | 定向探针（按键投递可靠性、`--focus` 下滑块持久化、IL API 可用性） | — |
| `build.log` / `publish.log` | 逐字构建与发布输出 | — |

截图（`verification\r2\`）：`r2-01-launch-640x780.png`、`r2-f1-saved-dark-plain.png`、`r2-f1-saved-light-plain.png`、`r2-f1-saved-dark-forcelight.png`、`r2-f1-saved-light-forcedark.png`、`r2-f1-saved-dark-forcedark.png`、`r2-f1-saved-system-plain.png`、`r2-f3-mega-start.png`、`r2-f3-bigscreen-start.png`、`r2-f3-mega-only.png`、`r2-f3-start-only.png`、`r2-f4-after-sc-maximize.png`、`r2-f4-after-esc.png`、`r2-f5-after-skip-s.png`、`r2-f6-focus1-completed.png`、`r2-reg-paused.png`、`r2-reg-break.png`、`r2-reg-winD.png`、`r2-reg-restored.png`、`r2-reg-focuslock.png`、`r2-reg-settings-open.png`、`r2-reg-range.png`。

**收尾状态**：所有由我启动的 `FluentPomodoro` 进程均已 `Stop-Process`；会话中无残留全屏/置顶窗口；我写入的 `%APPDATA%\FluentPomodoro\settings.json` 已在收尾时删除；构建产物 `verify-dist-r2\` 保留（本报告引用其 SHA-256），未删除作者的任何文件。
