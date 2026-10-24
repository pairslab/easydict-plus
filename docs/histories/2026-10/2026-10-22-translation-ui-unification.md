## 2026-10-22 | 任务：统一翻译界面风格并隐藏服务品牌

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-22-translation-ui-unification.md)

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

把翻译界面统一为紧凑、一致的 macOS 原生风格；在翻译界面中隐藏 DeepSeek 品牌，保留其后端与设置入口；
保留原应用图标和现有功能，后台进行。

### 变更

- 新增 `TranslationCardStyle`：浮动卡片共用 12 pt 圆角、14/12 内边距、8 pt 间距、12 pt 半粗标题、14 pt 正文、
  说明与占位字体，以及材质、细边框、阴影和统一的加载占位条。
- 单词卡片与翻译卡片改用共享样式；单词卡片标题字号由 22 降为 20，整体更紧凑。
- 新增 `ServiceDisplay`：结果与卡片界面中，DeepSeek 显示中性标题“翻译”和系统翻译图标，模型按钮显示“模型”，
  点击仍弹出原模型菜单；其他服务保持自身名称与图标。翻译卡片与输入窗口结果行改用它。
- 输入窗口结果行服务标题改为 12 pt 半粗，与卡片标题一致；模型按钮字号 10 → 11；符号图标随文字颜色着色。
- `Localizable.xcstrings` 新增 `query_result.service.neutral_title` 与 `query_result.service.model`，六种语言齐全。

### 设计意图

服务的 `name()`/`iconName()` 同时用于设置与服务列表，不做修改；品牌隐藏只发生在翻译结果与卡片的展示层，
请求、凭据、路由和模型选择都不变。全局 8 pt 圆角被窗口内多处共用，保持不变以免波及设置等非目标界面；
统一集中在浮动卡片的样式常量和结果行标题。

### 验证

- Release arm64 构建、SwiftLint strict、`git diff --check`、`jq -e .` 通过。
- 离屏渲染新旧两张卡片在浅色与深色外观下的各状态，确认样式一致与中性标题；仓库外临时程序，未提交。
- 已安装，签名指定要求、原图标、`Info.plist` 与配置保持。

### 受影响文件

- `Easydict/Swift/Feature/ActionManager/TranslationCardStyle.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewView.swift`
- `Easydict/Swift/Feature/ActionManager/TranslationPreviewPanel.swift`
- `Easydict/Swift/Feature/ActionManager/ActionManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupCardView.swift`
- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/objc/ViewController/View/ResultView/EZResultView.m`
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`
- 本任务计划和历史记录。

### 后续事项

- 输入窗口结果行的实际外观需用户目视确认。模型按钮悬停提示仍显示具体模型名，属主动查看时的信息。
