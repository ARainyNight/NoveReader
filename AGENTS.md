# NovelReader 项目规范

## 范围

原生离线 macOS TXT 阅读器 MVP，最低 macOS 14，Apple Silicon。使用 Swift、SwiftUI、AppKit 和 TextKit。仅实现本地打开、中文编码、滚动阅读、自由缩放与可切换无边框窗口、字号、双主题、自定义字体及背景颜色（含系统吸管取色）、本地章节识别与选择跳转、阅读位置保存与重启恢复。配色与边框偏好在本机保存。

章节在后台按独立标题行及编号规则识别，目录仅用于选择章节跳转，位置使用原文 UTF-16 偏移量。不得修改小说原文件。

禁止网络能力、第三方依赖、WebView、数据库，以及书架、搜索、书签、同步等扩展功能。

## 结构

- `NovelReader/App`：应用入口及菜单。
- `NovelReader/Views`：SwiftUI 页面及轻量控制区。
- `NovelReader/Reader`：AppKit 阅读视图及位置协调。
- `NovelReader/Services`：文件解码与本地保存。
- `NovelReader/Models`：阅读状态。
- `NovelReader/Utilities`：窗口配置。
- `NovelReaderTests`：编码、持久化、阅读与大文件验证。
- `scripts`：仅使用本机系统工具的构建与验证脚本。

## 实现与验证

按目标文件的十阶段顺序实施，每阶段先编译并验证，再进入下一阶段。文件读取和解码在后台执行，UI 仅主线程更新。正文不得使用整本 SwiftUI Text 或逐段 SwiftUI View。

优先 TextKit 2；不得调用旧版 `layoutManager` 触发隐式回退。位置采用 UTF-16 文本偏移量，不仅保存像素。文件访问只读，沙箱持久访问使用安全作用域书签。

完成有实质变化的工作后更新 `ROADMAP.md`。未验证事项不能标记已完成。`README.md` 记录使用和构建方式。测试产物位于被忽略的 `build` 目录。

遵守用户全局规范，删除、覆盖回滚、密钥、系统配置、全局依赖与公开发布等红线操作须先确认。
