# FluentPomodoro
一个开箱即用的桌面端开源番茄钟：不想折腾环境？直接下载仓库里的  FluentPomodoro.exe 双击就能跑，无需安装运行时、无广告、不联网。  同时也完整开放源码，想改配色、调时长逻辑、自己打包都可以， clone  下来按文档一键构建。  给想安静干活的人，也给想自己动手改一改的人。

Windows 11 上运行的 C# / WPF 番茄钟桌面程序，采用微软 Fluent Design 视觉语言（Mica 云母材质、Segoe UI Variable、
系统强调色、WinUI 风格开关与分段控件），并支持**强制大屏**（全屏 / 跨屏巨幕），可发布为**单文件自包含 EXE**，
目标机器无需安装 .NET 运行时。

---

## 1. 快速开始

```powershell
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
└─ tools/                     # 构建与验收脚本（图标/素材）
