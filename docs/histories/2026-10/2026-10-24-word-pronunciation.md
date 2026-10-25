## 2026-10-24 | 任务：单词卡片发音

**Links:** 基线 `1e2ef5e`

### 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

为单词卡片增加单词发音功能。

### 变更

- 音标（英/美）变为按钮，点击播放有道对应口音的录音，失败时由 `EZAudioPlayer` 退回系统朗读；没有音标时在单词旁显示发音按钮。
- “自动播放发音”设置开启时，词典结果到达后按设置中的口音偏好自动播放；卡片关闭时停止播放。
- 卡片面板只在指针位于卡片本体时接收鼠标，并接受首次点击，按钮无需激活 Easydict 即可使用；透明阴影边距仍让点击穿透。
- 新增本地化文本 `word_lookup.pronounce`（六种语言）。

### 设计意图

复用现有播放器与发音设置，不新增服务请求路径。面板按指针位置切换是否接收鼠标，避免透明边距遮挡单词附近的文字。

### 验证

- Release arm64 构建、`ReadingAssist` SwiftLint strict、`jq -e .` 通过。
- 未验证：实际点击与播放效果。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/WordLookupCardView.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupLoader.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/WordLookupPanel.swift`
- `Easydict/App/Localizable.xcstrings`
- 本任务历史记录。

### 后续事项

- None
