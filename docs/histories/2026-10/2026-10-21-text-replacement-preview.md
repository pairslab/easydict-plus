## 2026-10-21 | 任务：替换翻译悬浮预览与查询窗口翻译上屏

**Links:** 个人分支 `personal/main`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

把系统切到英文学英语时，希望输入中文后尽量无感地得到英文：在任意输入框原地替换，或在查询窗口输入后
直接把译文送回原来的光标位置；同时能用自己配置的翻译服务（如 DeepSeek），而不是固定的内置 AI。

### 变更

- 「翻译并替换」可以在高级设置中选择任意已添加的翻译服务；未选择或服务不存在时回退到内置 AI。
  流式服务按纯翻译请求，避免短词被扩展成词典释义；非流式服务（DeepL、Google 等）也可使用。
- 新增光标旁的悬浮预览：非激活面板实时显示服务、流式译文和完成/失败状态，不抢目标应用焦点；
  可在高级设置中关闭。
- 替换改为结果完整后一次性写回：失败或取消时保留原文；焦点已切到其他应用时改为复制到剪贴板。
- Accessibility 无法写入且未开启兼容模式时，回退到粘贴写入并恢复剪贴板，不再静默无反应。
- 新增应用内快捷键「翻译并上屏」（默认 ⌘↩）：关闭查询窗口、回到原应用并在光标处插入译文；
  第一个服务已完成时直接复用其结果。「在 Google 中打开」默认快捷键改为 ⌥⌘↩。
- `EZBaseQueryViewController` 新增 `firstFinishedTranslatedText`，并复用到语言切换逻辑。
- 新增 6 种语言的本地化文案。

### 设计意图

在现有 `ActionManager`、`SystemUtility` 插入策略与查询窗口边界内扩展，不改动服务实现和窗口查询
流程。一次性写回把"预览"和"写入"分离，使预览可以安全流式显示，同时保证原文不会被半截结果覆盖。

### 验证

- `xcodebuild build -workspace Easydict.xcworkspace -scheme Easydict`（Debug，本地自签名证书）：
  BUILD SUCCEEDED，新增与修改文件无编译警告。
- `git diff --check`、`jq -e . Easydict/App/Localizable.xcstrings`、`plutil -lint project.pbxproj`：通过。
- 手动检查：Debug App 启动正常；通过 `easydictd://query?text=…` 拉起查询窗口，中文自动译为英文。
- 手动检查：将预览视图离线渲染为浅色/深色两种外观，确认处理中、流式、已替换、已复制、失败五种状态
  排版正常（离线渲染无法呈现毛玻璃与系统进度动画）。
- 端到端（TextEdit，DeepSeek `deepseek-v4-flash`，按键由已授权辅助功能的终端模拟）：
  - `⌥R` 翻译并替换：自动全选后中译英、英译中均约 1 秒完成，经 Accessibility 一次性写回；
    悬浮预览依次显示处理中、已替换并淡出。首轮测试发现预览不显示：`NSHostingView` 关闭
    sizing options 后 `fittingSize` 为零，改用 `NSHostingController.sizeThatFits(in:)` 后修复。
  - `⌘↩` 翻译并上屏：关闭查询窗口约 0.1 秒后，在原光标处插入 DeepSeek 已完成的译文。
- 用户反馈：在 Claude 桌面版（Electron）输入框中预览显示「已替换」但原文未变。日志显示该应用对
  Accessibility 全选与写入均返回成功却不生效。修复为写入后回读焦点元素值确认变化；未变化时
  （替换场景先补 ⌘A）改用粘贴并再次确认，仍失败则复制到剪贴板并提示。
  - Claude 输入框复测：日志记录写入被忽略后改用粘贴，输入框内容被替换为英文译文。
  - TextEdit 回归：Accessibility 写入一次确认成功，没有重复粘贴。
  - 紧凑输入框（如聊天框）的预览改为贴着整个输入框外侧显示，避免覆盖边框。
- 未验证：网络失败时的预览提示（仅离线渲染检查）。

### 受影响文件

- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Feature/ActionManager/TextReplacementPreviewView.swift`
- `Easydict/Swift/Feature/ActionManager/TextReplacementPreviewPanel.swift`
- `Easydict/Swift/Feature/ActionManager/TextReplacementServiceOption.swift`
- `Easydict/Swift/Utility/SystemUtility/SystemUtility+Caret.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/Swift/Feature/Shortcut/Model/ShortcutAction.swift`
- `Easydict/Swift/Feature/Shortcut/Model/ShortcutManager+Default.swift`
- `Easydict/Swift/Feature/Shortcut/View/KeyHolderWrapper.swift`
- `Easydict/Swift/View/MenuView/MainMenuShortcutCommand.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AdvancedTab.swift`
- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.h`
- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`

### 后续事项

- 默认快捷键只在首次启动时写入；已有配置的用户需在设置中手动绑定「翻译并上屏」。
- 替换翻译暂不写入生词本。
