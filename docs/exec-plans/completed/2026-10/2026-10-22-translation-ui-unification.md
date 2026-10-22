# 翻译界面风格统一与服务品牌隐藏

- 状态：completed
- 创建日期：2026-10-22
- 负责人：Claude Code
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Claude Code`
- **Model:** `claude-opus-5-5`
- **Environment:** `macOS 15.5 / Xcode 16.4 (16F6)`

## 背景

用户要求把翻译相关界面统一为紧凑、一致的 macOS 原生风格，并在翻译界面中隐藏 DeepSeek 品牌。
现状：单词卡片与流式翻译卡片各自定义圆角（14）、内边距（16/14 与 14/12）、字号和加载占位；
输入窗口结果行标题使用 13 pt 常规字重的服务名与服务图标，模型按钮显示模型名；流式翻译卡片
标题同样显示服务图标与名称。DeepSeek 名称与图标因此出现在日常翻译界面。

## 目标与范围

- 目标结果：
  - 单词卡片与翻译卡片共用同一套卡片样式（圆角、内边距、间距、标题、正文、加载占位、边框与阴影）。
  - 输入窗口结果行标题与卡片标题使用相同字号与字重。
  - DeepSeek 在结果行与翻译卡片中显示中性标题和系统翻译图标；模型按钮显示中性标题，点击仍可切换模型。
- 允许修改路径：`Easydict/Swift/Feature/ReadingAssist/`、`Easydict/Swift/Feature/ActionManager/`、
  `Easydict/objc/ViewController/View/ResultView/`、`Easydict/App/Localizable.xcstrings`、
  `Easydict.xcodeproj/project.pbxproj`（新增文件引用）及本任务 plan/history。
- 同任务 history：`docs/histories/2026-10/2026-10-22-translation-ui-unification.md`
- 用户限制：后台进行，不接管窗口或输入；保留原应用图标、设置与签名；保留 DeepSeek 后端、凭据、
  路由与设置入口；保留轻按查词、按住翻译、PDF 句子范围、自动复制和重新打开时清空输入。
- 非目标：设置界面、其他功能窗口、全局 `EZCornerRadius_8` 与窗口背景色；不关闭或更换服务。
- 验收标准：构建与严格 lint 通过；String Catalog 合法且六种语言齐全；卡片离屏渲染在浅色与深色
  外观下样式一致；设置中的服务名称与图标不变。

## 工作计划

1. 新增共享样式文件：卡片样式常量、卡片外观修饰、加载占位，以及按服务给出结果界面标题与图标的 `ServiceDisplay`。
2. 单词卡片与翻译卡片改用共享样式；翻译卡片标题改用 `ServiceDisplay`。
3. 输入窗口结果行标题字号字重对齐，服务标题、图标与模型按钮标题改用 `ServiceDisplay`。
4. 新增两条本地化文本（六种语言）。
5. 构建、lint、离屏渲染两种外观的卡片截图；Review；更新 history。

## 风险与决策

- 不修改服务的 `name()`/`iconName()`，因为设置与服务列表共用它们；只在翻译界面替换显示。
- 全局 8 pt 圆角被窗口内多处共用，修改会波及设置等非目标界面，本轮保持不变；浮动卡片统一为 12 pt。
- 无屏幕录制权限且不新增权限；输入窗口为 Objective-C 视图，无测试 hook 无法离屏渲染，安装后由用户目视确认。
- 仓库规则未授权新增测试；离屏渲染使用仓库外的临时程序，不提交。

## 进度

- [x] 共享样式与 `ServiceDisplay`。
- [x] 两张卡片改用共享样式。
- [x] 输入窗口结果行对齐与中性品牌。
- [x] 本地化。
- [x] 验证、Review、history。

## 验证

- Release arm64 构建通过；首次构建发现 SFSafeSymbols 的 `translate` 仅适用于 macOS 14.4+，改为可用时使用
  `translate`、更早系统使用 `character.bubble`，部署目标保持 macOS 13。
- `ActionManager` 与 `ReadingAssist` 目录 SwiftLint strict、`git diff --check`、`Localizable.xcstrings` 的
  `jq -e .` 通过；String Catalog 原样往返无格式漂移，新增两条 key 的六种语言齐全。
- 离屏渲染：仓库外临时程序编译本次与 `HEAD` 的两张卡片源码，在浅色与深色外观下输出词卡（内容与加载）和
  翻译卡（阅读、加载、已复制、失败）图片，未显示任何窗口；确认圆角、内边距、标题与正文字号一致，翻译卡
  标题由 DeepSeek 名称改为中性标题与系统翻译图标，两种外观可读。临时程序未提交。
- Review：复核服务名称与图标在设置中的来源未变（`name()`/`iconName()` 未改）、结果行图标回退、模板图标着色
  只影响符号、模型按钮点击菜单不变、卡片尺寸常量的外部引用（面板布局）保持；未发现其他翻译界面显示服务品牌。
- 已备份并安装，签名指定要求、原图标、`Info.plist` 与配置（含重新打开时清空输入）保持；后台启动正常。
- 未验证：输入窗口结果行的实际外观（Objective-C 视图，无测试 hook 无法离屏渲染，且无屏幕录制权限），
  需用户打开窗口目视确认。

## 完成条件

- 进度全部完成，验证结果如实记录，history 链接归档后的计划。
