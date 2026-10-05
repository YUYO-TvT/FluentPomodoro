# 微软风格番茄钟 · Fluent Pomodoro

Windows 11 上运行的 C# / WPF 番茄钟桌面程序，采用微软 Fluent Design 视觉语言（Mica 云母材质、Segoe UI Variable、
系统强调色、WinUI 风格开关与分段控件），并支持**强制大屏**（全屏 / 跨屏巨幕），可发布为**单文件自包含 EXE**，
目标机器无需安装 .NET 运行时。

---

## 1. 快速开始

```powershell
# 直接运行已发布产物
.\dist\FluentPomodoro.exe

# 从源码构建单文件 EXE（生成图标 → 还原 → 发布到 .\dist）
pwsh -NoProfile -File .\build.ps1
```

命令行参数：

| 参数 | 说明 |
| --- | --- |
| `--bigscreen` / `-b` / `--fullscreen` | 启动后直接进入上次记忆的大屏方式（默认巨幕跨屏） |
| `--mega` / `--span` | 启动后直接进入**巨幕跨屏** |
| `--start` / `-s` | 启动后立即开始计时（可与上面的大屏参数同时使用） |
| `--focus <分钟>` | 覆盖本次专注时长（1–120），**仅本次会话生效，退出时不会写回配置文件** |
| `--light` / `--dark` | 强制浅色 / 深色主题启动（优先级高于配置文件里的主题；**仅本次会话**，退出时不会写回配置） |

例：`FluentPomodoro.exe --mega --start --focus 10` —— 巨幕大屏、立刻开始、专注 10 分钟。

---

## 2. 功能

**计时**
- 专注 / 短休息 / 长休息三阶段循环，每 N 个番茄进入一次长休息（N 可调 2–12）。
- `Stopwatch + Deadline` 绝对时间算法，不受 UI 卡顿影响，长时间运行不漂移；暂停/继续不丢时间。
- 圆环进度（`Controls/ProgressRing.cs`，纯 `OnRender` 绘制，任意分辨率不失真），大屏下自动放大到 900px 级别的巨型表盘。
- 阶段结束：合成提示音 + 浮层提醒 + 任务栏闪烁提醒。

**强制大屏**（本项目的重点能力）
| 方式 | 行为 |
| --- | --- |
| 窗口 | 普通可拖动/可缩放窗口，记忆位置与大小 |
| 全屏 | 无边框铺满主显示器，覆盖任务栏 |
| 巨幕跨屏 | 用 `GetSystemMetrics(SM_*VIRTUALSCREEN)` 把所有显示器拼成一块大屏，横跨整个虚拟桌面 |

“强制”体现在：
- 进入大屏时 `WM_WINDOWPOSCHANGING` 内强制回写窗口矩形 —— 其他程序 / 用户拖拽都无法改变大屏尺寸与位置；
- `WM_SYSCOMMAND` 拦截 `SC_MINIMIZE`，`OnStateChanged` 兜底阻止 `Win+D` 之类导致的最小化；大屏期间同时拦截 `SC_MAXIMIZE` / `SC_RESTORE`，退出大屏时先还原窗口状态再恢复原尺寸；
- 大屏下窗口默认置顶（可关闭），从而盖住任务栏；`ShowInTaskbar=false`，隐藏标题栏拖拽，`Esc` / `F11` 退出；
- 专注阶段可开启「专注锁定」：拦截最小化与关闭，`Ctrl + Shift + Q` 始终可强制退出，不会真的锁死用户。

**其它**
- 设置面板：时长、显示、背景、白噪音、行为、大屏、外观、数据、快捷键，随时修改即时生效并落盘。
- 今日统计：完成番茄数 / 专注分钟数 / 累计完成 / 连续专注天数；可一键重置。
- **专注时限制系统休眠**：专注计时进行中通过 `SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)`
  阻止系统进入睡眠 / 休眠；设置里可再叠加 `ES_DISPLAY_REQUIRED`「同时保持屏幕常亮」。
  两个开关独立生效（只阻止休眠时显示器仍可按系统设置熄灭）。暂停、跳过、进入休息或关闭开关都会立即
  释放请求，恢复系统正常休眠策略。此外监听 `WM_POWERBROADCAST`：若系统仍进入睡眠，会主动暂停本次专注
  （避免把睡眠时间算成专注时间）并在恢复后提示，恢复时重新申请上述状态。
- 主题：跟随系统 / 浅色 / 深色；强调色读取 Windows 个性化设置（`HKCU\...\DWM\AccentColor`）。
- 快捷键不惧输入法：程序没有任何文本输入，窗口关闭输入法（IME），中文输入法激活时 `空格` / `R` / `S` / `F` / `F11` 依然可用。

**当前时间（可选显示）**
- 设置 → 显示 → 「显示当前时间（时钟）」，在圆环中央显示 `HH:mm:ss`，每秒刷新；
- 还有「仅在专注阶段显示」：开启后只在专注阶段出现，休息时隐藏（更贴合“专注时看时间”的用法）；
- 大屏模式下钟面自动放大（随圆环尺寸缩放），适合投到大屏上看时间与剩余时间。

**统计二级窗口（GitHub 式绿点矩阵）**
- 标题栏统计按钮或 `Ctrl + I` 打开独立统计窗口；
- 绿点矩阵：53 周 × 7 天，一格一天，**当天专注越久颜色越深**，六档色阶
  `0 / <25分 / 25–49分 / 50–99分 / 100–199分 / ≥200分`，鼠标悬停显示当天明细；
- 汇总卡片：今日、本周、本月、累计专注、连续专注天数、最佳一天；
- 支持「导出 CSV」，数据来自 `%APPDATA%\FluentPomodoro\history.json`（每完成一个番茄自动累加）。

**背景图片（可周期更换，主题色随图）**
- 支持选择**单张图片**或**整个文件夹**（文件夹内随机轮换）；
- 轮换方式：不轮换 / 每 5、15、30、60 分钟 / 每天，另有「每次开始专注时换一张」；
- 图片不透明度可调；图片模式下自动加一层遮罩保证文字可读；
- 「用图片主色调作为主题色」：从图片中提取主色（饱和度加权色相平均，忽略近灰度像素），
  再按浅色/深色主题调整明度与饱和度，作为整个界面的强调色（圆环、按钮、开关、时钟高亮等）。

**白噪音（导入本地音频）**
- 设置 → 白噪音 → 「添加音频」导入自己的音频文件（mp3 / wav / wma / m4a / aac / flac / ogg，取决于系统解码器）；
- 支持列表管理（添加 / 单个移除 / 清空）、音量调节、随机播放、下一首、播放/暂停；
- 「开始专注时自动播放」+「仅在专注阶段播放」：专注开始自动播放，暂停或进入休息自动停；
- 标题栏音量图标按钮可随时播放/暂停，播放中图标变为强调色。
- 配置文件：`%APPDATA%\FluentPomodoro\settings.json`；唯一外部依赖是 .NET 自身，无第三方库。
- 配置容错：配置文件中出现非法枚举、类型不符、越界数值时，逐字段容错读取 —— 坏字段退回默认值，
  其余字段（尤其是统计数据）原样保留，不会因为一个坏值丢掉整份配置。

---

## 3. 快捷键

| 按键 | 功能 |
| --- | --- |
| `空格` | 开始 / 暂停（设置面板打开时不响应） |
| `R` | 重置当前阶段 |
| `S` | 跳过当前阶段（不计入统计） |
| `F11` | 大屏 / 窗口 切换 |
| `F` | 依次循环 窗口 → 全屏 → 巨幕跨屏 |
| `Esc` | 关闭设置面板 / 退出大屏 |
| `Ctrl` + `I` | 打开专注统计窗口 |
| `Ctrl` + `,` | 打开 / 关闭设置 |
| `Ctrl` + `1` / `2` / `3` | 窗口 / 全屏 / 巨幕跨屏 |
| `Ctrl` + `Shift` + `Q` | 强制退出（专注锁定下也可用） |

---

## 4. 环境要求

- 运行：Windows 10 1809 及以上 / Windows 11（Mica 材质与圆角需要 Windows 11 22H2+，即内部版本 ≥ 22621；
  更早的系统自动退回 Fluent 纯色背景，功能不受影响）。x64。
- 发布的 EXE 为 **自包含单文件**，目标机无需安装 .NET。
- 构建：.NET SDK 8.0 或更高（已用 8.0.425 / 10.0.401 验证）。

---

## 5. 从源码构建

```powershell
pwsh -NoProfile -File .\build.ps1                     # 默认 Release / win-x64 / 单文件 -> .\dist
pwsh -NoProfile -File .\build.ps1 -Output D:\out      # 自定义输出目录
pwsh -NoProfile -File .\build.ps1 -SkipIcon           # 跳过重新生成图标

dotnet build .\FluentPomodoro.csproj -c Release       # 仅编译（RID 已在 csproj 指定为 win-x64）
dotnet run   --project .\FluentPomodoro.csproj        # 直接调试运行
```

发布参数位于 `FluentPomodoro.csproj`：`SelfContained` / `PublishSingleFile` /
`IncludeNativeLibrariesForSelfExtract` / `EnableCompressionInSingleFile`。

---

## 6. 项目结构

```
FluentPomodoro/
├─ FluentPomodoro.csproj      # net8.0-windows / WPF / 单文件自包含发布配置
├─ app.manifest               # PerMonitorV2 DPI 感知、asInvoker、UTF-8
├─ App.xaml(.cs)              # 应用入口：单实例互斥、命令行参数、主题初始化、创建主窗口
├─ MainWindow.xaml(.cs)       # 主界面 + 计时状态机 + 强制大屏 + 设置面板 + 背景/白噪音/时钟
├─ StatsWindow.xaml(.cs)      # 统计二级窗口：绿点矩阵 + 汇总卡片 + 导出 CSV
├─ Controls/
│   ├─ ProgressRing.cs        # 圆环进度自绘控件（含柔光、圆头线帽）
│   └─ ContributionGraph.cs   # GitHub 贡献图式绿点矩阵控件（自绘 + 悬停命中）
├─ Interop/
│   └─ Native.cs              # user32 / dwmapi / kernel32 / winmm 互操作声明
├─ Services/
│   ├─ Models.cs              # 阶段 / 大屏方式 / 主题枚举
│   ├─ AppSettings.cs         # 设置持久化（含逐字段容错读取）
│   ├─ FocusHistory.cs        # 每日专注历史（history.json），供绿点矩阵使用
│   ├─ ThemeManager.cs        # 浅色深色调色板 + 系统强调色 + 图片主色覆盖
│   ├─ BackgroundService.cs   # 背景图片列表 / 随机轮换 / 主色调提取
│   ├─ NoisePlayer.cs         # 白噪音播放（MediaPlayer，循环/随机/音量）
│   ├─ ScreenInfo.cs          # 主显示器 / 虚拟桌面几何
│   └─ ChimePlayer.cs         # 运行时合成提示音 WAV + winmm 异步播放
├─ Themes/
│   ├─ Palette.Light.xaml     # 浅色主题令牌（含绿点矩阵六档配色）
│   ├─ Palette.Dark.xaml      # 深色主题令牌
│   └─ Controls.xaml          # Fluent 控件样式（按钮/开关/滑块/下拉/滚动条/分段控件）
├─ Assets/app.ico             # 由 tools\make-icon.ps1 生成的多尺寸图标
└─ tools/                     # 构建与验收脚本（图标/素材、截图、6 套端到端测试）
```

---

## 7. 技术实现要点

- **Mica 云母材质**：`DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_MAINWINDOW)` +
  `DwmExtendFrameIntoClientArea(-1)` + `HwndSource.CompositionTarget.BackgroundColor = Transparent`，
  使整块客户区参与材质合成；随后用 `DWMWA_CAPTION_COLOR` 覆盖被扩展出来的标题栏玻璃带，
  避免该区域透出桌面壁纸配色。系统不支持时自动回退为不透明 Fluent 背景。
- **无边框可缩放窗口**：`WindowStyle=None` + `WindowChrome`（`CaptionHeight=40`、`ResizeBorderThickness=6`、
  `CornerRadius=8`），标题栏按钮通过 `WindowChrome.IsHitTestVisibleInChrome` 保持可点击，
  原生拖动 / 吸附 / 双击最大化 / 边缘缩放全部保留。
- **DPI**：manifest 声明 PerMonitorV2；大屏矩形按物理像素计算后除以当前 `DpiScale` 换算为 WPF 设备无关单位，
  并在 `OnDpiChanged`、跨屏移动后二次校正。
- **提示音**：运行时用正弦基频 + 2/3 次谐波与指数包络合成 44.1kHz/16bit 单声道 WAV，
  字节数组用 `GCHandle.Alloc(..., Pinned)` 固定后交给 `winmm!PlaySound(SND_MEMORY | SND_ASYNC)`，
  不需要任何音频库与外部音频文件。
- **图标**：`tools/make-icon.ps1` 使用 `System.Drawing` 绘制 256×256 母图，
  缩放为 16/24/32/48/64/128/256 七种尺寸并以 PNG 帧打包成标准 `.ico`。

---

## 8. 常见问题

- **看不到云母（Mica）效果**：Windows 11 22H2 以下、或系统「透明效果」关闭、或使用了「最佳性能」模式时，
  DWM 会忽略材质请求，程序自动退回纯色背景。可在设置里关闭「Mica 云母材质背景」以固定使用纯色。
- **大屏后找不到窗口 / 无法退出**：按 `Esc`（退出大屏）或 `Ctrl + Shift + Q`（强制退出）。
- **多显示器 + 巨幕跨屏出现缩放不一致**：不同显示器 DPI 不同是 Windows 的既有行为（WPF 窗口按所在显示器 DPI 统一缩放）。
  需要严格一致时请对各显示器使用相同缩放比例，或改用「全屏」模式。
- **找不到提示音**：设置面板 → 「试听提示音」，若提示播放失败，请检查系统音量与声音方案是否被静音。
- **端口/网络**：程序完全离线，不访问网络、不写注册表（只读取系统主题与强调色）。

---

## 9. 验收脚本

| 脚本 | 用途 |
| --- | --- |
| `tools/make-icon.ps1` | 生成 `Assets/app.ico` |
| `tools/screenshot.ps1` | 截取虚拟桌面 |
| `tools/capture-window.ps1` | 按窗口句柄截图（`PrintWindow` 全内容） |
| `tools/ui-test.ps1` | 端到端 UI 验收：启动/拖动/设置面板/巨幕大屏/最小化拦截/位置锁定/Esc 还原/计时/退出落盘（12 项） |
| `tools/phase-test.ps1` | 阶段完成验收：1 分钟专注跑完整流程，校验阶段切换与统计落盘（9 项） |
| `tools/fix-test.ps1` | 缺陷回归：主题持久化 / 配置容错 / `--mega --start` / 大屏最大化拦截 / `--focus`、`--light`、`--dark` 不落盘 / 计时精度（17 项） |
| `tools/theme-ui-test.ps1` | 真实鼠标路径：设置面板 → 外观下拉 → 选「深色」→ 重启仍为深色（4 项） |
| `tools/ime-test.ps1` | 中文输入法下的裸字母快捷键 R / S / F / Esc（8 项） |
| `tools/make-test-assets.ps1` | 生成功能测试素材（三张纯色相背景图 + 一段 440Hz 测试音频） |
| `tools/feature-test.ps1` | 新功能验收：时钟开关与仅专注显示 / 背景图渲染与主题色随图 / 轮换 / 绿点矩阵色阶 / 白噪音自动播放（15 项） |
| `tools/sleep-test.ps1` | 专项：专注时限制系统休眠（用 `powercfg /requests` 观察 SYSTEM / DISPLAY 请求，含睡眠/恢复广播处理，14 项） |

一键跑完全部验收：

```powershell
foreach ($t in 'ui-test','phase-test','fix-test','theme-ui-test','ime-test','feature-test') {
    Get-Process FluentPomodoro -ErrorAction SilentlyContinue | Stop-Process -Force
    pwsh -NoProfile -File ".\tools\$t.ps1"
}
```

（`feature-test` 需要先跑一次 `tools/make-test-assets.ps1` 生成素材。）

---

## 10. 独立验收与缺陷修复记录

本项目经过一轮**独立验收**（另一名评审者从源码独立构建、独立编写 12 个测试脚本 + 探针，覆盖 34 张截图），
结论为「有条件通过：无 blocker，3 个 major / 4 个 minor / 6 个 nit」，随后全部修复并复测。

| 编号 | 严重度 | 问题 | 修复 |
| --- | --- | --- | --- |
| F1 | major | 配置文件里的 `Theme=Dark` 被忽略，同一 EXE 只有 `--dark` 才生效 | `MainWindow` 构造顺序改为「命令行 > 配置文件 > 跟随系统」，在建界面之前就应用主题；设置面板的下拉选择仍然实时生效 |
| F2 | major | 配置里出现一个非法枚举/类型错误，整份配置连统计一起被重置为默认 | `SettingsStore.Load` 改为两级解析：先常规反序列化，失败后退化为逐字段容错读取，坏字段回默认、其余字段（含统计）全部保留 |
| F3 | major | `--mega --start` 同时使用时 `--start` 被 `else if` 吞掉 | 两个启动动作改为独立的 `BeginInvoke`，可同时生效 |
| F4 | minor | 大屏中 `Win+↑` 之后按 Esc 仍停留在最大化状态 | 大屏期间拦截 `SC_MAXIMIZE`/`SC_RESTORE`；退出大屏时先把 `WindowState` 复位为 `Normal` 再恢复尺寸 |
| F5 | minor | 中文输入法激活时裸字母 `R`/`S`/`F` 失效（按键以 `ImeProcessed` 到达） | 窗口整体关闭输入法（`InputMethod.SetIsInputMethodEnabled(this,false)`），并在按键处理中把 `Key.ImeProcessed` 还原为 `ImeProcessedKey` |
| F6 | minor | `--focus <分钟>` 被当成永久设置写回配置 | 会话级覆盖：保存时临时换回原值，`--focus` 只影响本次运行 |
| F7 | minor | 文档声称 `Stopwatch + Deadline`，代码实际用 `DateTime.UtcNow` | 计时改为静态 `Stopwatch` 单调时钟 + 截止点，系统时间被校时也不会跳变 |
| nit | minor | `BigScreen` 死代码、`Native.cs` 29 个未用声明、提示音内存句柄不释放、主题静态事件泄漏、默认尺寸三处不一致、写盘异常静默吞掉 | 逐一清理：消除死分支、精简互操作声明、退出时释放句柄并退订事件、统一 640×780/480×560 尺寸约束、保存失败时提示一次 |

第二轮独立复核（同一评审者，冻结版本哈希核对两次、自带构建产物、140 项检查）确认 F1–F7 全部修复，
并指出修复过程中新引入的两个小问题，均已一并修掉：

| 编号 | 严重度 | 问题 | 修复 |
| --- | --- | --- | --- |
| N1 | minor | 修复 F1 时让 `--light`/`--dark` 被写回配置文件，与 `--focus` 的「仅本次会话」语义不一致 | 命令行主题同样按会话级覆盖处理（保存时临时换回原值）；用户在设置面板里自己选主题时解除该覆盖并正常持久化 |
| N2 | nit | `--focus` 生效期间，用户在设置面板里主动改的时长只在本会话生效、不写盘 | 检测到滑块值偏离命令行覆盖值即视为用户显式修改，结束覆盖并按用户设置持久化 |

复测结果（均为真实运行观测值）：

| 脚本 | 结果 |
| --- | --- |
| `tools/ui-test.ps1` | 12 / 12 通过 |
| `tools/phase-test.ps1` | 9 / 9 通过 |
| `tools/fix-test.ps1` | 17 / 17 通过（含 F1、F2、F3、F4、F6、N1、N2 与 21 秒计时精度） |
| `tools/theme-ui-test.ps1` | 4 / 4 通过（真实鼠标点开下拉并选择「深色」，重启后仍为深色） |
| `tools/ime-test.ps1` | 8 / 8 通过 |

最终产物：`dist\FluentPomodoro.exe`（62.9 MB，自包含单文件，SHA256 `1A1F75E05B2971401AD9A7E18BC25EA1E667ED8CA821A17AD3C761B6F4C116ED`）。

已知限制（不影响使用，但未做机器验证）：多显示器巨幕（本机仅单屏，`巨幕` 与 `全屏` 几何一致）、显示器热插拔、
非 96 DPI 缩放、提示音/白噪音是否真的出声（只能验证播放接口调用与状态机）、任务栏闪烁的可见性、
跨午夜统计翻转（应用运行中跨天）、背景轮换「每天」档的真实 24 小时触发、大屏下时钟字号缩放、
4K/8K 大图的内存表现、数小时长稳。

---

## 11. 第二轮功能（时钟 / 统计绿点矩阵 / 背景图 / 白噪音）

在原有番茄钟与大屏能力之上新增四项功能，均配有独立的端到端验收脚本：

| 功能 | 关键实现 | 验收脚本 |
| --- | --- | --- |
| 专注时显示当前时间 | `TxtClock` + 1 秒 `DispatcherTimer`，随圆环尺寸缩放 | `tools/feature-test.ps1` |
| 统计二级窗口（绿点矩阵） | `StatsWindow` + `Controls/ContributionGraph.cs`（自绘 53×7、六档绿色、悬停提示），数据来自 `Services/FocusHistory.cs` | 同上 |
| 背景图片（周期更换 + 主题色随图） | `Services/BackgroundService.cs`（列表/随机轮换/主色提取）+ `ThemeManager.SetAccentOverride` | 同上 |
| 白噪音（用户导入） | `Services/NoisePlayer.cs`（MediaPlayer，循环/随机/音量/仅专注时播放） | 同上 |

每完成一个专注番茄会向 `history.json` 累加当天分钟数与番茄数，绿点矩阵与汇总卡片据此渲染；
色阶为 `0 / <25分 / 25–49分 / 50–99分 / 100–199分 / ≥200分`，颜色越深表示当天专注越久。

第三轮独立复核（同一评审者，冻结版本 10/10 哈希前后一致、自带构建产物）结论：
**223 项检查全部通过，0 个新增缺陷**，四项功能逐项确认，包括：

- 时钟：开启后两次抓屏的像素变化严格落在时钟矩形内（1664 / 447 px，bbox 均在时钟区域内），关闭后 diff=0，重启保持；
- 绿点矩阵：像素实测出 53 列 × 7 行、365 个可用格心**全部精确命中**六个色阶画刷，
  按边界值 `0/1/24/25/49/50/99/100/199/200/500` 放置后各档格数与独立分桶逐级相等，悬停提示与 `history.json` 一致，导出 CSV 逐行正确；
- 背景图：红/蓝图实测强调色 `(173,61,55)` / `(55,104,173)`、深色+红 `(224,96,90)`，
  与评审者按源码算法独立重算的预期值**逐通道完全相同**；5 分钟档实测 `t=301.5s` 触发轮换（此时计时器未运行）；
- 白噪音：自动播放/仅专注播放/循环（1 秒音频 7 秒后仍在播）、随机不重复、损坏文件只提示失败且 CPU 不空转（8 秒内 0.02–0.62s）。

复核后按建议补做了两处改进（第三轮报告 §6.2 的观察项 O1 与措辞对齐）：
`AppSettings` 的容错读取在布尔字符串无法解析时回落到字段默认值（原实现一律视为 false），
并新增「仅在专注阶段显示时钟」开关；两项均已加入 `tools/feature-test.ps1` 并复测通过。

