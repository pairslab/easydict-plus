## 2026-10-21 | 任务：轻按修饰键查词

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-21-option-tap-word-lookup.md)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

将双击单词显示词典卡片改为轻按一次 Option，保留已有段落翻译与翻译配置。

### 变更

- 由阅读辅助的同一事件入口协调短按查词与长按段落翻译；短按在松开按键时确认。
- 通过 web 文本标记或原生字符范围定位鼠标下的单词及语境，不再依赖已选文字，不修改选区或剪贴板。
- 组合键、点击、滚动和应用切换取消短按或未完成的单词查询，防止过期结果重新出现。
- 移除双击专用词典入口，保留普通选词查询流程；更新六种语言的设置文案和中文指南。
- 显式应用初始设置，避免未写入的默认偏好阻止组合监听产生初始值。

### 设计意图

轻按在释放时查词，持续按住仍走段落翻译。两者使用同一按键时，识别立即进行，
但段落请求等待最多 250 ms 的短按判定窗口结束，避免一次操作同时打开两个卡片。
查词开关与段落触发设置独立。只接受鼠标所在位置的单词边界，保留只读文本限制。

### 验证

- 首轮构建发现嵌套闭包显式引用问题，修复后 Release 通用构建通过。
- 六个变更 Swift 文件通过 SwiftLint strict；String Catalog JSON 与 `git diff --check` 通过。
- 首次安装检查发现默认设置初始事件缺失，修正为启动时显式应用设置；最终 Release 通用构建通过，重启日志确认监听已注册。
- 界面已确认新的查词说明、开启状态，以及原段落触发键和自动复制设置保留。
- 备份旧应用和配置后安装最终构建，安装前后严格签名校验通过。通过系统设置刷新本应用的辅助功能授权后，开关保持开启，重启未再出现旧签名不匹配日志。
- 最终任务 diff 已审查并复验内容摘要，未发现新的确定缺陷；复用原事件入口协调手势的实现范围适当。
- 本次没有新增或扩写测试；现有测试不覆盖阅读辅助状态机，工具无法单独模拟修饰键。已请求用户轻按验证，但尚未取得实测结果；不将构建通过视为完整交互验证。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLocator.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupCardView.swift`
- `Easydict/Swift/Feature/Configuration/Defaults.Keys+Extension.swift`
- `Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift`
- `Easydict/App/Localizable.xcstrings`
- `README.md`
- 本任务计划和历史记录。

### 后续事项

- 待用户在实际阅读内容中确认轻按查词、持续按住翻译，以及所用应用的单词边界兼容性。

Web 文本标记实现参考：[WebKit 单词范围处理](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm)。
