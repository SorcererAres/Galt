# Galt

Typeless 风格的 AI 语音听写工具（macOS 菜单栏 App）：按住 `fn` 说话，松开后自动转写、润色，并把成稿级文本插入任意 App 的光标处。

## 构建与运行

```bash
brew install opus  # 提供 libopus，供 make vendor 打包 Vendor/opus.xcframework
make vendor        # 按需下载 / 组装本地引擎二进制依赖（sherpa-onnx、onnxruntime、opus）
make build         # release 编译
make run           # 编译 → 打包 dist/Galt.app → 启动
make dmg           # 额外生成可分发的 dist/Galt-<版本>.dmg
```

要求：macOS 14+，Xcode 命令行工具，Homebrew（用于 `brew install opus`）。

> 首次构建务必先 `brew install opus` 再 `make vendor`，否则缺少 `Vendor/opus.xcframework` 会编译失败。

> `dist/`、`.build/`、`.dmg` 等生成产物不应提交到 git；重新发布时用脚本生成。

## 首次使用

1. **授权麦克风**：首次录音时系统会弹窗询问
2. **授权辅助功能**：系统设置 → 隐私与安全性 → 辅助功能，勾选 Galt（用于全局热键与文本注入）
3. **设置 API Key**：点击菜单栏麦克风图标 → 「设置 Groq API Key…」（可在 console.groq.com 免费获取），也支持环境变量 `GROQ_API_KEY`
4. 建议把 系统设置 → 键盘 → 「按下 🌐 键时」设为「无操作」，避免与听写热键冲突

## 使用

- **按住 `fn`** 说话，松开后文本经「转写 → LLM 润色」自动粘贴到光标处
- **点按 `fn`**（短按）进入锁定听写，适合长口述，再次点按结束
- **语音编辑**：先选中一段文字，再按 `fn` 说出指令（如"改短一点""换成正式语气""翻译成英文"），松开后选中内容被改写结果替换
- **翻译模式**：菜单栏 → 翻译模式，或设置面板中选择目标语言，开启后任何语言的口述都输出目标语言成稿
- 润色会按目标应用自动调整语气：邮件成文、聊天简短、技术场景保留英文术语
- 菜单栏 → 「设置…」：切换引擎（云端 / 本地离线 / 自动兜底）、API Key、个人词典、本地引擎语言
- 菜单栏展开即可查看统计：累计字数、平均 WPM、节省的打字时间
- **控制台**：菜单栏 → 「打开控制台」，包含概览仪表盘（统计卡片、近 7 天字数图表、最近听写）、可搜索的完整历史（复制/删除/查看原始转写）、个人词典管理与设置
- 历史记录仅存本地（`~/Library/Application Support/Galt/history.jsonl`）

## 转写引擎

| 模式 | 说明 |
|---|---|
| 自动（默认） | 有 Key 时走云端 Groq Whisper，失败或无 Key 自动回退本地 |
| 仅云端 | Groq Whisper，多语言自动检测，准确率最高 |
| 仅本地 | 完全离线，本地引擎二选一（见下） |

本地引擎（设置 → 本地离线引擎）：

| 引擎 | 说明 |
|---|---|
| Apple 设备端听写 | 零下载开箱即用，需指定语言，首次使用请求「语音识别」权限 |
| Whisper 离线模型 | whisper.cpp + Metal GPU 加速，自动检测语言、准确率更高；需在设置中下载模型（小型约 190MB / 高精度约 550MB） |

> API Key 加密存储在系统钥匙串（Keychain）中，不落明文。

## 路线图

见 [PLAN.md](PLAN.md)。M1–M4.5 已完成（核心闭环、智能润色、云端/Apple/Whisper 三引擎、设置面板、历史统计、语音编辑、翻译、Keychain、DMG 打包）；后续可选：Sparkle 自动更新、官网与 iOS。

## 仓库维护

- 贡献说明见 [CONTRIBUTING.md](CONTRIBUTING.md)
- 版本变更见 [CHANGELOG.md](CHANGELOG.md)
- 仓库健康度与后续优化建议见 [Docs/REPOSITORY_HEALTH.md](Docs/REPOSITORY_HEALTH.md)
