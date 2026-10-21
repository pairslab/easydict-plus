## 2026-10-21 | 任务：双击查词词典卡片

**Links:** 个人分支 `personal/main`；关联 `2026-10-21-hover-translation.md`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 27.2 / Xcode 27.0 (27A5252f)`

### 用户请求

在"按住 ⌃ 悬停翻译整段"之外，提供查单个单词的方式，并与整段翻译明确区分；交互和界面要优雅，且不
额外付费。

### 变更

- 在只读文字中双击外文单词（拉丁字母单词，不含空格），以带箭头的毛玻璃气泡代替原来的划词查询图标：
  衬线字体词头、英美音标（放不下时换行）、词性胶囊与释义，以及 AI 给出的"此处"语境义。输入框等可编辑
  文字中的双击保持原有行为。
- 释义来自 Easydict 内置的有道免费网页词典（无需 API Key），查不到时回退系统词典
  `DCSCopyTextDefinition`（离线）；语境义使用替换翻译所选的 AI 服务，非 AI 服务时回退内置 AI。
- `StreamService` 新增 `customChatMessages`，在 `chatMessageDicts` 最前生效，用于一次性的自定义提问，
  对所有基于该方法的模型服务通用。
- 段落定位与单词定位共享新的 `AXElementReader`、`AXCoordinateSpace`；三个浮层面板共享
  `NSPanel.floatingOverlay(level:contentView:)`。
- 功能目录 `HoverTranslation` 更名为 `ReadingAssist`；高级设置中的分组更名为"阅读辅助"，新增"双击查词"
  开关（默认开启），并补充 6 种语言文案。

### 设计意图

参考 Google Dictionary、沙拉查词、系统"查询"与 Language Reactor：单词使用更轻的双击手势，整段使用
按住修饰键，两者在手势、高亮与卡片形态上都不同。接入点放在 `EventMonitor.handleSelectedText`，复用
它已有的双击判断与可编辑性检测，避免与查询图标同时出现。

### 验证

- `xcodebuild build`（Debug）：BUILD SUCCEEDED，新增与修改文件无编译或 SwiftLint 警告。
- `jq -e . Easydict/App/Localizable.xcstrings`、`plutil -lint project.pbxproj`、`git diff --check`：通过。
- 离线渲染词典气泡的加载中、已出释义、完整三种状态（浅色/深色，箭头朝上/朝下），确认长单词不缩小、
  音标与词头基线对齐。
- 回归：TextEdit 中 `⌥R` 记录发送 15 个字符并完成翻译；写回前用户切换了前台，按设计改为复制。
- 未验证：真实双击查词端到端效果（用户正在使用电脑，未接管屏幕）、Chrome/PDF 中的选区边界读取。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/`（目录更名，新增 `AXElementReader`、`WordLocator`、
  `WordLookupLoader`、`WordLookupCardView`、`WordLookupPanel`、`WordLookupManager`）
- `Easydict/Swift/Utility/Extensions/NSWindow/NSPanel+FloatingOverlay.swift`
- `Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift`
- `Easydict/Swift/Service/OpenAI/StreamService.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewPanel.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AdvancedTab.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/TextAssistSettingsSections.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`

### 后续事项

- 实测网页、PDF、Electron 应用中的双击查词；如某应用的选区边界读取失败，气泡会退回指向鼠标位置。
