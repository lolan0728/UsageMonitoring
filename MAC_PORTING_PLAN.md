# Mac 迁移实施文档

## Summary
- 当前仓库里的 Windows 版本已经完成一个可用的额度悬浮面板，技术栈是 `WPF + C# + H.NotifyIcon`，只保留了 `5h / 1w` 两个额度胶囊，不再包含历史曲线。
- 在 Mac 上不要继续改现有 `UsageMonitoring.App` 项目；应当在同一仓库下新增一个独立的原生 macOS 项目，例如 `UsageMonitoring.Mac`。
- mac 版目标形态已经确定为：`SwiftUI 悬浮小窗`，不是 WidgetKit，不是跨平台 .NET UI。
- 数据源已经确定为：`本机 Mac 上的 Codex app-server`，刷新频率维持 `1 分钟`，并保留“缓存快照 + 黯淡态/活跃态切换”。

## Current Windows Baseline
- 现有 Windows 项目路径：
  - `UsageMonitoring.App/UsageMonitoring.App.csproj`
  - `UsageMonitoring.App/MainWindow.xaml`
  - `UsageMonitoring.App/ViewModels/MainViewModel.cs`
  - `UsageMonitoring.App/Services/CodexAppServerClient.cs`
- 当前已实现行为：
  - 双胶囊 UI，`5h` 和 `1w` 上下排列
  - 启动时先显示缓存额度，默认黯淡态
  - 只有本次启动期间真正拿到新额度后才切换到活跃态
  - 离线启动时如果存在本地快照，会显示上次额度，但保持黯淡态
  - 托盘菜单支持 `Show/Hide Window`、`Locate Codex`、`Quit`
  - 已去掉历史曲线和本地 usage 日志导入
- Windows 特有实现，不应直接移植：
  - `WPF/XAML`
  - `H.NotifyIcon.Wpf`
  - 注册表开机自启
  - DWM 材质与 Windows 窗口 API
  - `codex.exe` 路径探测逻辑

## Target Mac App Spec
- 技术栈：
  - `SwiftUI` 作为主 UI
  - 必要时用 `AppKit` 处理悬浮窗、拖拽、菜单栏和窗口行为
- 产品形态：
  - 桌面悬浮小窗
  - 默认右上角停靠
  - 可拖动、记忆位置、隐藏/显示
  - 菜单栏常驻
- 视觉要求：
  - 延续当前 Windows 版双胶囊风格
  - `5h` 与 `1w` 上下排列
  - 左侧圆环，右侧百分比与 `Until`
  - 支持两种视觉状态：
    - `活跃态`：文字和圆环正常亮度
    - `黯淡态`：文字和圆环整体降亮度
- 刷新策略：
  - 正常情况下 `1 分钟` 兜底刷新
  - 如果 app-server 有推送更新，优先即时更新
- 数据范围：
  - 只看 `本机 Mac` 上的 Codex
  - 不做跨设备汇总
  - 不做历史曲线
  - 不做云端同步

## Mac Data Layer Requirements
- mac 版需要重建一个 `CodexAppServerClientMac`
- 行为与 Windows 版保持一致：
  - 启动本机 `codex app-server --analytics-default-enabled`
  - 通过 `JSON-RPC over stdio` 通信
  - 先发 `initialize`
  - 读取 `account/rateLimits/read`
  - 监听 `account/rateLimits/updated`
- Mac 路径探测规则：
  - 优先查找 `~/.codex/.sandbox-bin/codex`
  - 再查找 PATH 中的 `codex`
  - 如果都找不到，则进入 `MissingExecutable`
  - 菜单栏里始终显示 `Locate Codex`
- 状态模型保持一致：
  - `Disconnected`
  - `Connecting`
  - `MissingExecutable`
  - `Connected`
  - `Degraded`
- 活跃态规则必须保持：
  - 仅当本次运行真正收到最新 `rateLimits` 数据时，才置为活跃态
  - 不能因为“连接已建立”或“加载了缓存快照”就提前点亮

## Local Persistence Requirements
- mac 版继续保留本地额度快照
- 建议保存为简单 JSON 文件，路径放在 mac 用户目录下的 app data 区域
- 快照内容最少应包含：
  - `5h` bucket
  - `1w` bucket
  - `SyncedAtUtc`
  - `ResetsAtUtc`
  - `RemainingPercent`
  - `UsedPercent`
- 启动时行为：
  - 先加载本地快照并显示
  - 但默认保持黯淡态
  - 等收到本次真实新数据后再切成活跃态

## Mac UI Structure
- 建议拆成以下组件：
  - `App entry`
  - `Menu bar controller`
  - `Floating panel/window controller`
  - `Main quota view`
  - `Quota pill view`
  - `Quota ring view`
  - `View model / state store`
- 每个胶囊展示：
  - 左：圆环
  - 右上：`5h` 或 `1w`
  - 右中：剩余百分比
  - 右下：`Until xx:xx` 或周额度时间
- 黯淡态实现：
  - 降低圆环亮度
  - 降低底环亮度
  - 主数字、标签、副文字统一降亮度
- 不要加入：
  - 历史图表
  - 复杂设置页
  - 多 tab 结构
  - WidgetKit 组件

## Menu Bar / Window Behavior
- 菜单栏图标：
  - 使用当前 Windows 版“双环监控”图标语义
  - 转成 mac 可用资源
- 菜单项：
  - `Show Window` 或 `Hide Window`，根据当前状态二选一显示
  - `Locate Codex`
  - `Quit`
- 悬浮窗行为：
  - 可拖拽
  - 可记忆上次位置
  - 默认贴近右上角
  - 关闭按钮默认不退出，隐藏到菜单栏
- 开机自启：
  - 使用 mac 登录项方案
  - 不沿用 Windows 注册表逻辑

## Recommended Build Sequence On Mac
1. 把当前仓库完整复制到 Mac。
2. 新建 `UsageMonitoring.Mac` 原生 macOS SwiftUI 项目。
3. 先实现静态双胶囊悬浮窗，不接任何真实数据。
4. 再实现菜单栏图标和菜单。
5. 再实现本地 `codex` 可执行文件探测。
6. 再接 `app-server` JSON-RPC。
7. 再接本地快照加载和保存。
8. 最后补齐黯淡态/活跃态切换、窗口位置记忆、登录项。

## Acceptance Criteria
- 在 Mac 上启动时：
  - 如果有缓存快照，立刻显示两个额度胶囊，但为黯淡态
  - 如果没有缓存且找不到 Codex，显示空状态且不崩溃
- 成功拿到最新额度后：
  - 两个胶囊切为活跃态
  - `5h / 1w` 数值和重置时间正确
- 断网或 Codex 不可用时：
  - 保留上次快照显示
  - 界面自动回到黯淡态
- 菜单栏可正常：
  - 打开窗口
  - 隐藏窗口
  - 手动定位 Codex
  - 退出应用

## Assumptions
- Mac 上已安装 Xcode，并可以开发原生 macOS 应用。
- Mac 上存在本机 Codex 环境，或者允许用户手动定位 `codex` 可执行文件。
- v1 只做悬浮小窗，不做 WidgetKit。
- v1 不做跨设备额度同步，不读取其他电脑的数据。
