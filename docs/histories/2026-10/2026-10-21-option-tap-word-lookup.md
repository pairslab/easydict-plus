## 2026-10-21 | 任务：轻按修饰键查词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-21-option-tap-word-lookup.md) · [PR #1](https://github.com/pairslab/easydict-plus/pull/1)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

将双击单词显示词典卡片改为轻按一次 Option，保留已有段落翻译与翻译配置；修复误触段落、取词无反应并改善响应。

### 变更

- 同一事件入口协调短按查词与长按段落翻译。共用按键时，松开优先查词；持续按住约 500 ms 且物理按键仍按下才开始段落识别，轻按期间不高亮整段。
- 增加静态文本范围边界定位，适配 Electron 内容；通过范围矩形缩小候选，最多查询 64 次，避免逐词查询整段。
- 保留 web 文本标记与原生字符范围回退，web 范围扩展到单词两端，不依赖旧选区，不修改选区或剪贴板。
- 组合键、点击、滚动和应用切换取消短按或未完成查询；日志只记录手势、角色和查询次数，不记录读取内容。
- 显式应用初始设置，避免未写入的默认偏好阻止监听注册；移除双击专用词典入口，更新六种语言的设置文案和中文指南。

### 设计意图

短按和长按共用监听入口，避免段落流程抢占单词查询；其他段落触发键仍立即识别。
查词开关与段落触发设置独立，保留只读文本和既有翻译配置边界。
Chromium 的范围边界实现用于选择 Electron 取词路径，WebKit 实现用于核对文本标记范围；均不代表所有应用兼容性保证。

### 验证

- 初版及手势修复版 Release 通用构建通过；最终取词兼容修复版 Release arm64 构建通过。
- 初版六个、最终修复三个变更 Swift 文件通过 SwiftLint strict；String Catalog JSON 与差异格式检查通过。
- 已备份旧应用和配置并安装最终构建；严格签名校验、原配置保留、辅助功能刷新和启动检查通过。
- 最终源码与构建、审查快照一致；审查覆盖短按优先、范围矩形剪枝、完整单词边界及取消分支，未发现未解决的确定缺陷。
- 用户在 AgentsDock 中实测后确认可用；日志确认轻按展示单词卡片并取得语境，持续按住进入段落模式，静态文本取词示例使用 4–7 次边界查询。
- 未新增或扩写测试，现有测试不覆盖阅读辅助状态机；未进行跨应用完整回归或网络翻译耗时测量。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/AXElementReader.swift`
- `Easydict/objc/Libraries/DictionaryKit/TTTDictionary.m`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupCardView.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift`
- `Easydict/App/Localizable.xcstrings`
- `README.md`
- 本任务计划和历史记录。

### 后续事项

无阻断项；其他应用的兼容性仍以各自的实际辅助功能支持为准。

参考：[WebKit 单词范围处理](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm)、[Chromium 辅助功能范围实现](https://github.com/chromium/chromium/blob/main/ui/accessibility/platform/browser_accessibility_cocoa.mm)。

### 网页取词兼容性修复

- 用户反馈 Edge 网页中轻按完全无反应；日志确认按键到达，但失败时的祖先链被 8 层限制截断，另有成功取词后未显示卡片的记录。
- 将取词祖先遍历扩展至最多 32 层，并在网页根节点停止；单词卡片先显示，完整语境在独立队列补充，防止语境读取拖住单词查询。
- 取词期间的鼠标移动改为结果返回时核对真实单词范围；事件与应用切换回调绑定查询代次，取消旧回调、排队语境任务及过期显示。诊断区分词语过滤、几何查询和取消事件，不记录原文。
- Release arm64、两个 Swift 文件 SwiftLint strict、差异格式及源码摘要复核通过。Review 未发现新增确定缺陷；没有新增测试或进行完整跨应用回归。
- 用户明确要求按共性问题修复并重启。实现没有站点域名、URL 或浏览器名称特判。
- 已备份应用与配置，安装并后台启动保留原内嵌图标的构建；严格签名校验、运行程序摘要与相关配置保留检查通过。
- 启动日志确认旧辅助功能授权与更新后的签名不匹配。用户允许短暂切换设置并完成 Touch ID 后，移除旧授权记录并添加当前应用，恢复原有权限；再次后台重启，系统日志确认辅助功能与按键监听均获准，设置开关保持开启。
- 实际跨网页交互尚待验收；构建、静态检查与启动成功不能证明所有网页均可取词。

### Chromium 文字几何与词典崩溃修复

- 执行者：Claude Code（Claude Opus 5.5）。
- 可编辑判断只认文本输入角色或 `AXEditable`，不再把 `AXValue` 可设置的列表等祖先当成输入框。
- Chromium 与 Electron 对只读取的辅助工具只开启基础模式，`AXBoundsForRange` 返回空矩形。网页内静态文本出现该情况时，向对应进程请求完整文字几何（`AXManualAccessibility`，失败时 `AXEnhancedUserInterface`），每进程 10 秒至多一次，原生应用不请求；定位按 0.25 秒重试最长 3.5 秒，查询代次变化或指针移开即停止。
- 命中容器时有界向下搜索，塌缩的包装节点只向下穿过。
- 修复 `TTTDictionary.m` 对 Get 规则结果使用 `__bridge_transfer` 造成的多释放；它使系统词典回退中的 `DCSCopyTextDefinition` 段错误，导致应用退出。
- 本机安装改用自签名身份，指定要求在重建后保持不变；仅重置本应用失效的辅助功能记录后由用户重新授权。
- 验证：Release arm64、SwiftLint strict、差异格式检查通过；临时应用内诊断（已删除）确认 AgentsDock 授权前后范围矩形由空变为有效，真实命中测试多轮 5/5 定位正确且释义非空；Edge 5/5 遍历定位正确（从父容器开始，非真实命中）；系统词典回退不再崩溃。详见[执行计划](../../exec-plans/completed/2026-10/2026-10-21-option-tap-word-lookup.md)。
- 待用户实测：alphaXiv 页面、Edge 前台真实命中、物理 Option 轻按及可见卡片。

### 实测反馈与按键、取词鲁棒性

- 执行者：Claude Code（`claude-opus-5-5`）；用户要求后台进行，不接管窗口或输入。
- Edge 中 alphaXiv 实测（上一版构建）：6 次网页轻按中 5 次在松开后 5–36 ms 显示单词卡片并取得语境，按住约 500 ms 进入段落模式；
  第一次轻按没有任何阅读辅助日志，原因未能确定。
- 同一日志暴露的共性问题与修复：
  - ⌥A 等被全局快捷键消费的组合会被记为 Option 轻按并发起查词。松开时用 HID 层 `keyDown` 空闲时间判断按住期间是否按过其他键，有则不查词；触发键本身留 20 ms 余量。
  - 开始手势依赖缓存的已按修饰键，发往 Easydict 自身窗口的松开事件会让缓存过期。改为由事件键码判断单独新按下。
  - 指针在词间空白或标点上时两侧单词都被剪掉。同一行 5 pt 内吸附最近单词，剪枝同步放宽，仍受 64 次查询上限约束。
  - Electron 基础树中命中整窗容器且无文字。网页区域内本次未遇到静态文本时，只请求 `AXManualAccessibility`，不回退
    `AXEnhancedUserInterface`；每进程成功一次后不再等待，浏览器拒绝时立即结束并清除记录。
- 验证：Release arm64 构建、`ReadingAssist` SwiftLint strict、`git diff --check` 通过；未新增测试。
- 安装：备份旧应用与偏好后，用同一本机身份只签名外层应用，沿用原 `Info.plist`、`Assets.car`（保留 Easydict-27 图标；
  已核对原资源包含新构建全部 86 个命名资源）与签名权限声明；指定要求不变，后台启动，无需重新授权。
- 新版实测（应用日志）：
  - AgentsDock：命中整窗容器后向下搜索 45 个节点定位单词，松开后 60 ms 显示卡片；另一次 9 ms；按住进入段落模式。
  - ⌥A：未弹出单词卡片（由输入窗口激活 Easydict 时的重置取消，HID 组合检查本轮未被触发）；随后在 AgentsDock 的轻按正常，
    该场景旧逻辑会因缓存的修饰键过期而忽略。
  - Claude（Electron，冷启动）：文字树请求被接受，260 ms 后出现静态文本，但单词范围矩形约 7 秒后才可用；
    其间重试在指针移开后停止。之后一次词间轻按吸附 2 pt 定位成功，但结果返回时指针已离开单词，未显示卡片。
- 未验证：本版在 Edge/alphaXiv 中的轻按、HID 组合检查在不激活 Easydict 的快捷键（如 ⌥R）下的效果、吸附后的可见卡片。
