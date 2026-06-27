# 仓库完整性评估（Repository Health）

> 基于当前 `main` 梳理。规模：Swift ~14,800 行 / 40 个文件（`Sources/Galt`）+ `COpusShim` C 桥；`swift build` 通过。

## 总体判断

Galt 在**功能与产品完成度**上已相当成熟：可构建的 macOS 应用、完整的听写闭环、云/本地多引擎、控制台与设置、引导与诊断、打包与公证脚本、产品与设计文档齐备。

但在**工程成熟度**（团队/开源协作所需）上仍有缺口：没有自动化测试、没有许可证、二进制依赖缺溯源、部分超大文件、以及若干早期文档已落后于现状。

## 优势

- SwiftPM 包构建通过；CI（GitHub Actions）在 push/PR 跑 `swift build`。
- 职责拆分清晰：音频、热键、引擎/厂商、注入、HUD、设置、历史、词典各司其职；手感常量集中于 `Tuning`。
- 引擎与厂商抽象良好（`STTProvider` + 5 云端 / 3 本地 / 6 LLM），`auto` 兜底。
- 文档体系完整：README、产品文档（`Docs/PRODUCT.md`）、设计规范（`Design.md`）、打包脚本与润色回归用例（`Docs/POLISH_REGRESSION.md`）。
- 离屏快照工装（`GALT_SNAPSHOT`）+ 程序化校验（VoiceOver/键码映射），无需录屏权限即可做 UI 验收。
- 隐私工程到位：历史本地、密钥 Keychain、`.gitignore` 已挡住 ~600MB 参考资源与二进制框架。

## 缺口

| 缺口 | 说明 | 严重度 |
|---|---|---|
| 无测试目标 | `Package.swift` 无 test target，零自动化测试；核心逻辑（引擎路由、Polisher、EditLearner、Opus 封装、热键真值对账）均无回归保护 | 高 |
| 无许可证 | 仓库根无 `LICENSE`，公开分发前需明确 | 高 |
| 二进制依赖溯源 | whisper / sherpa-onnx / onnxruntime / opus 的 xcframework 缺来源 URL、版本、许可证、校验和记录 | 中 |
| 文档落后 | `PRD.md` / `APP_SPEC.md` 为早期里程碑版（仅 Groq + Apple/whisper），未覆盖现有 5 云端 / sherpa-onnx / 6 LLM / 流式 / 诊断 / 纠错自学习 / 随便问卡片等。现以 `Docs/PRODUCT.md` 为现状基准 | 中 |
| 超大文件 | `ConsoleWindow.swift`(2487)、`SherpaOnnx.swift`(2275)、`SettingsWindow.swift`(1753) 偏大，评审与维护成本高 | 中 |
| CI 覆盖薄 | 仅 `swift build`，未跑测试、未打包、未做 lint | 中 |

## 建议下一步（按优先级）

1. **加许可证**：公开分发前选定并加入 `LICENSE`。
2. **建测试目标**：把可测逻辑从可执行目标抽出（引擎路由、`Polisher` 提示词契约、`EditLearner` 编辑距离、`OpusEncoder` 封装、`HotkeyManager` 真值对账），加 test target，CI 跑测试。
3. **二进制依赖溯源**：在 `Vendor/` 或文档记录各 xcframework 的来源/版本/许可证/校验和（配合 `scripts/fetch-vendor.sh`）。
4. **收敛早期文档**：将 `PRD.md` / `APP_SPEC.md` 标注为历史里程碑或更新至现状，统一指向 `Docs/PRODUCT.md`。
5. **拆分超大 UI 文件**：把 `ConsoleWindow` / `SettingsWindow` 按页面/分区拆成更小视图。
6. **扩展 CI**：增加打包冒烟与（引入 SwiftLint 后的）lint 步骤。
