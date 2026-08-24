# AITokenUsageWidget

**macOS 通知中心 AI 用量监控小组件 · AI Token Usage Monitor Widget for macOS Notification Center**

在 macOS 侧边栏（通知中心）实时显示 DeepSeek、Kimi（Moonshot）、GLM（智谱）的账户余额与 API 额度用量，支持深色/浅色主题、用量超阈值系统通知。
Monitor DeepSeek / Kimi / GLM (Zhipu) API balance & quota usage right from your macOS Notification Center, with dark/light themes and threshold alerts.

[English README](README_EN.md)

## 截图 · Screenshots

| 主界面（浅色） | 主界面（深色） |
|---|---|
| ![主界面浅色](docs/screenshots/main-window-light.png) | ![主界面深色](docs/screenshots/main-window-dark.png) |

| 小组件 · 中尺寸（3 供应商紧凑三列） | 小组件 · 深色 |
|---|---|
| ![小组件中尺寸](docs/screenshots/widget-medium-light.png) | ![小组件深色](docs/screenshots/widget-medium-dark.png) |

| 小组件 · 大尺寸（纵向列表 + 进度条 + 重置倒计时） |
|---|
| ![小组件大尺寸](docs/screenshots/widget-large-light.png) |

## 功能特性 · Features

- **多供应商用量监控 / Multi-provider monitoring**

  | 供应商 Provider | 显示内容 | 数据来源 |
  |---|---|---|
  | **DeepSeek** | 账户余额（总余额 / 赠送 / 充值 + 可用状态） | `GET api.deepseek.com/user/balance` |
  | **Kimi Code** | 5 小时 / 7 天 / 月度用量（含重置倒计时） | `GET api.kimi.com/coding/v1/usages`（月度需可选 Cookie） |
  | **GLM Coding（智谱）** | 5 小时 / 7 天 / 30 天累计 / 月度工具额度 | `open.bigmodel.cn` quota/limit + model-usage（免 Cookie） |

- **自适应布局**：仅显示已启用的供应商；中尺寸 3 个供应商自动切换紧凑三列；支持中 / 大两种小组件尺寸
- **主题切换**：跟随系统 / 浅色 / 深色，主界面与小组件联动
- **用量告警**：任一额度窗口达到阈值（50%–95% 可选，默认 80%）时发送系统通知，回落后自动重置
- **小组件实时预览**：主界面内嵌预览，未配置显示模拟数据（带标记），配置后自动显示实际用量
- **配置自动保存**：App Group 共享给小组件；查询接口不消耗模型 token
- **每 15 分钟自动刷新**（系统调度），失败时保留缓存

## 技术栈 · Tech Stack

- **Swift 5.9 + SwiftUI**：声明式 UI，App 与 Widget 共享视图组件
- **WidgetKit**：`TimelineProvider` + `StaticConfiguration`（systemMedium / systemLarge）
- **App Group / 共享 JSON**：主 App 与 Widget 扩展间配置共享（无描述文件时自动降级为扩展容器共享文件）
- **UserNotifications**：Widget 扩展直接发送用量告警，App 无需常驻
- **XcodeGen**：`project.yml` 声明式工程定义
- 零第三方依赖 · Zero third-party dependencies

## 系统要求 · Requirements

- macOS 12.7+（macOS 14+ 支持小组件背景主题化）
- Intel / Apple Silicon 双架构（universal binary）
- 源码构建需要 Xcode 15+ 与 [XcodeGen](https://github.com/yonsm/XcodeGen)（`brew install xcodegen`）

## 安装 · Installation

### 方式一：下载预编译包 / Prebuilt

1. 从 [Releases](../../releases) 下载 `AITokenUsageWidget-v1.0-universal.zip`，解压后将 `AITokenUsageWidget.app` 拖入 `/Applications`
2. 首次打开如被 Gatekeeper 拦截，终端执行一次（或在 系统设置 → 隐私与安全性 点「仍要打开」）：

   ```bash
   xattr -dr com.apple.quarantine /Applications/AITokenUsageWidget.app
   ```

### 方式二：源码构建 / Build from Source

```bash
git clone https://github.com/<your-name>/AITokenUsageWidget.git
cd AITokenUsageWidget
./setup.sh        # 自动安装 xcodegen、生成并打开 Xcode 工程
```

在 Xcode 中为两个 target 选择你的 Team（Signing & Capabilities，个人免费证书即可），确认 App Groups 勾选 `group.com.chenxing.tokenusage`，然后运行 `AITokenUsageWidget`。

> 提示：`*.xcodeproj` 由 XcodeGen 生成、已被 `.gitignore` 忽略，clone 后必须运行一次 `./setup.sh`。

## 使用方法 · Usage

1. **获取 API Key**
   - DeepSeek：[platform.deepseek.com](https://platform.deepseek.com) → API Keys（`sk-xxx`）
   - Kimi Code：[kimi.com/code/console](https://www.kimi.com/code/console)（`sk-kimi-xxx`，注意与开放平台按量 Key 不通用）
   - GLM：[open.bigmodel.cn](https://open.bigmodel.cn) 的 API Key
2. **配置**：打开 App → 左侧选供应商 → 打开「启用」→ 填入 API Key（自动保存）→ 可点「测试连接」验证
3. **添加小组件**：打开通知中心 → 编辑小组件 → 添加「AI 模型用量」（macOS 不允许应用自动添加，需手动一次）
4. **可选设置**：侧边栏「外观」切换主题；「通知」开关与阈值（Kimi 月度总额需在供应商配置中额外填 `kimi-auth` Cookie，非官方接口）

## 数据与隐私 · Data & Privacy

- API Key 仅保存在本机（App Group UserDefaults；无描述文件时降级为 Widget 容器内 `shared.json`），只发往对应供应商官方域名
- 存储可靠性：逐字段容错解码 + 写入前 `.bak` 备份 + 解码失败保留 `shared.corrupt-*.json`，配置不会因版本升级丢失
- 无任何遥测 / 第三方统计 · No telemetry

## 新增供应商 · Adding a Provider

1. `Shared/Models/ProviderKind.swift` 添加 case（名称、接口地址、图标、Key 说明）
2. `Shared/Networking/UsageServices.swift` 的 `fetch(config:)` 添加抓取与解析分支
3. 配置界面 / 存储 / 小组件卡片自动适配，无需改动

## 贡献指南 · Contributing

欢迎 Issue 与 PR！Contributions are welcome:

1. Fork 本仓库并创建特性分支（`git checkout -b feature/xxx`）
2. 遵循现有代码风格（SwiftUI、中文注释、最小化改动）
3. 提交前确认 `xcodegen generate` 后双 target 编译通过（Debug + Release）
4. 新增供应商请附上接口文档链接与测试账号外的验证方式
5. 提交 PR 并描述改动动机与效果（界面改动请附截图）

**不要提交**：真实 API Key / Cookie、`build/`、`dist/`、`*.xcodeproj`（均已由 `.gitignore` 兜底）。

## License

[MIT](LICENSE)（如仓库尚未包含 LICENSE 文件，请先添加）

## 关键词 · Keywords

`macOS widget` `Notification Center` `WidgetKit` `SwiftUI` `DeepSeek` `Kimi` `Moonshot AI` `GLM` `智谱` `ChatGLM` `Zhipu AI` `token usage` `API quota` `balance monitor` `AI 用量监控` `额度提醒` `通知中心小组件`

---

## English

**AITokenUsageWidget** is a macOS Notification Center widget that monitors AI API usage across providers:

- **DeepSeek**: account balance (total / granted / topped-up + availability indicator)
- **Kimi Code**: 5-hour / 7-day / monthly quota with reset countdowns
- **GLM Coding (Zhipu)**: 5-hour / 7-day / 30-day cumulative / monthly tool quota

**Highlights**: adaptive compact 3-column layout · dark/light theme shared between app & widget · system notifications when any quota window crosses a configurable threshold (default 80%) · in-app live widget preview (mock data badge when unconfigured) · auto-saved config shared via App Group · usage queries consume no model tokens · 15-minute auto refresh with cache fallback · zero third-party dependencies.

**Requirements**: macOS 12.7+, universal binary (Intel & Apple Silicon). Build from source with `./setup.sh` (requires XcodeGen), select your signing Team for both targets, run the app, then add "AI 模型用量" from Notification Center → Edit Widgets.

**Privacy**: API keys stay on device (App Group / container file with backup & corruption-safe decoding) and are only sent to the respective provider's official endpoints. No telemetry.

Contributions welcome — see the Contributing section above. Licensed under MIT.
