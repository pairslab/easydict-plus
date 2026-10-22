## 2026-10-21 | 任务：加快悬停翻译识别

**Links:** [执行计划](../../exec-plans/completed/2026-10/2026-10-21-hover-translation-responsiveness.md)

### 执行上下文

- **Agent Name:** `Codex`
- **Model:** `GPT-6`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

### 用户请求

Option 悬停取词需要等待很久或反复移动；希望直接开始识别，保留既有 DeepSeek 与自动复制配置。

### 变更

- 移除识别前 250 ms 固定等待，网络翻译前的防抖从 350 ms 缩短至 150 ms。
- 接受仍包含最新鼠标位置的异步识别结果，同段落几何短暂复用最多 350 ms；滚动及跟踪会话变化使旧结果失效。
- AX 父节点改为按需读取，当前节点可识别时不预先查询完整祖先链。
- 移除 HTTP 服务初始化时的 SwiftNIO 全局执行器接管，保持系统执行器。
- 备份并安装本机构建，保留本地化名称、已有签名权限及偏好设置，重新关联失效的辅助功能权限记录。

### 设计意图

识别立即开始，短防抖仅约束网络请求；保留现有状态机和其他快捷键取消逻辑。
有界复用减少同段落移动时的跨进程访问，同时允许流式聊天内容定期更新。
安装验证发现当前工具链下执行器接管导致译文停在首词，因此一并保留系统执行器以确保新版可用。

### 验证

- `xcodebuild build -workspace Easydict.xcworkspace -scheme Easydict -configuration Release -destination 'platform=macOS,arch=arm64'`：最终 Release 通用构建成功；使用独立 DerivedData、本地临时签名及发布打包配置。
- 三个变更 Swift 文件通过 SwiftLint strict；`git diff --check` 通过。
- 深度严格代码签名检查通过；安装时保留原应用包与偏好设置备份。
- 手动检查：同一句中文在保留系统执行器后完整译为 `Today's meeting has been moved to 3 PM.`，流式加载结束；实际 Command-V 粘贴得到完整英文，自动复制通过。
- 设置检查：触发键为 Hold Option，第一/第二语言为简体中文/英语，DeepSeek 与自动复制设置保持不变。
- 辅助功能检查：系统界面移除旧签名条目并重新加入当前应用；重启后开关保持开启，对应日志不再出现签名不匹配。
- Review：完整差异、异步状态边界及必要调用点审查完成，源文件快照复验一致，未发现新增阻断项。
- 未新增或扩写测试；当前没有覆盖悬停状态机的现有测试。界面工具无法单独按住修饰键，未实测 Option 悬停体感或端到端耗时。

### 受影响文件

- `Easydict/Swift/Feature/ReadingAssist/HoverTranslationManager.swift`
- `Easydict/Swift/Feature/ReadingAssist/ParagraphLocator.swift`
- `Easydict/Swift/Feature/HTTPServer/Vapor/VaporServer.swift`
- `docs/exec-plans/completed/2026-10/2026-10-21-hover-translation-responsiveness.md`
- `docs/histories/2026-10/2026-10-21-hover-translation-responsiveness.md`

### 后续事项

- 用户在 AgentsDock 英文段落上确认 Option 悬停手感；网络服务响应时间不属于本地识别延迟的保证范围。
