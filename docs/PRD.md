# AVIOR — R 包验证证据编译器
## 产品需求文档（PRD · 开发指导版）

| 项目 | 内容 |
| --- | --- |
| 产品名 | **AVIOR** — Automated Validation and Inspection for Operational R-packages |
| 命名来源 | 船底座 ε（Avior），神话中阿尔戈号的龙骨 —— 验证体系的龙骨 |
| CLI / R 包名 | `avior` |
| 文档版本 | v1.6（开发基线；本文件取代《ValiR PRD》v0.1（`docs/ValiR-PRD.md`），后者保留作历史参考） |
| 文档状态 | 定稿。后续变更通过 PR 修订本文件，重大范围变更须先对照 §2 设计公理 |
| 编制日期 | 2026-07-08 |
| 依据 | 《R 包验证策略对比分析与实施方案》《评审意见与聚焦规划》 |
| 一句话定位 | **`renv.lock` 进，可签署的验证证据包出。** 跑在用户自己环境与 CI 里的 CLI 工具，把第三方 R 包验证的「依赖识别 → 风险评分 → 决策留痕 → 定向测试 → 环境指纹 → 审计就绪报告」编译成一条命令的产出 |

---

## 1. 背景与定位

### 1.1 问题（继承自参考文件，已验证）

受监管环境（FDA / EMA / NMPA 申报）使用 R 的团队，要建立合规的包验证体系，今天必须手工缝合 riskmetric、riskassessment、valtools、PPM、renv、diffify、oysteR 等至少 7 个工具，并人工编写与拼接风险评估、决策记录、追溯矩阵、验证报告。碎片化编排与文档黑洞是最大成本；证据链靠手工维系，审计时易断裂。

### 1.2 AVIOR 是什么、不是什么

**是**：一个 local-first 的证据编译器。像 pytest / terraform 一样活在用户的仓库和 CI 里；输入依赖清单与策略配置，输出结构化、防篡改、可直接送签的验证证据包。

**不是**：平台。不托管数据、不做签名、不提供 Web 服务、不替客户做合规判断。合规责任主体始终是申办方；AVIOR 只负责让「产出证据」这件事从数周人工变成一条命令。

### 1.3 方法论锚点（审计辩护的出处）

- R Validation Hub 白皮书《A Risk-based Approach for Assessing R Package Accuracy within a Validated Infrastructure》—— 风险评估四准则（用途/类型、维护、社区使用、测试）。
- **intended-for-use 聚焦原则**：深度验证只针对直接调用包；间接依赖只做版本管理。这是工作量收敛的关键，工具的一等公民。
- ISPE GAMP 5（第二版）最小交付物：规范、风险评估、测试、追溯矩阵。
- 包三分类：Base/Recommended（低风险，无需补验）、Contributed（按风险分级）、Custom（SDLC 式验证，本产品 V2 范围）。

### 1.4 验证对象与产物边界

一句话：**AVIOR 以 R 项目为验证上下文与证据边界，以该项目依赖的 R 包为验证对象；产物是一份项目级的包环境验证证据包。**

- **运行单元是 R 项目**：项目的 `renv.lock` 划定包集合、版本与环境，即证据边界。锚定项目是方法论要求而非实现选择——四准则第一条是「用途」，同一个包在不同项目中的用途不同，风险档与测试深度就不同。脱离使用上下文的「此包已验证」在风险评估式验证中不成立（这也是商业已验证包订阅只能作为证据之一、最终决策仍在申办方的原因）。
- **被评估的对象是包**：清单中处于验证范围的第三方包（intended-for-use 聚焦直接调用者）。评分、决策、定向测试都以「包 + 版本 + 本项目用途」为单位。
- **验证产物是证据包（bundle）**：证明「**本项目所用的 R 包环境**已按既定 SOP 完成与风险相称的评估、决策与测试，且环境可复现」。它是关于包环境的合格证据，不是对任何单个包的抽象认证，更不是对项目分析代码的验证。

| 对象 | AVIOR 范围 | 说明 |
| --- | --- | --- |
| 项目依赖的第三方包 | ✅ V1 核心 | 评分 → 决策 → 定向测试，逐包入追溯矩阵 |
| 项目的包环境整体 | ✅ V1 | bundle 的证明对象：环境指纹 + lockfile 哈希 + 可复现性 |
| 自研 R 包的 SDLC 验证 | ⏳ V2 | 编排 valtools；当下直接用 valtools 本身 |
| 项目自身的分析代码（脚本 / TLF 程序） | ❌ 永久不做 | 属程序验证领域（双编程、代码评审）；包环境证据是分析结果可信的前提之一，不是全部 |

**跨项目复用**：评分是「包 + 版本 + 引擎」级事实，可跨项目缓存复用（FR-X-5）；决策因含用途声明而默认项目级。组织级决策库（多项目共享已评审决策，仅复核 `use_statement` 是否一致）列为 V2 候选。

---

## 2. 设计公理（约束一切范围决策）

任何新需求进入 backlog 前，必须先通过这三条公理的检验。与公理冲突的需求默认拒绝，除非修订本节并说明理由。

| # | 公理 | 含义 | 直接后果 |
| --- | --- | --- | --- |
| A1 | **做管线，不做平台** | CLI 工具，跑在用户环境与 CI；无服务端、无数据库、无多租户、无账号体系 | 不做 SaaS/托管/Web 评审界面；看板只能是证据包内的静态 HTML 文件 |
| A2 | **证据即文件** | 策略、清单、评分、决策、报告全部是版本库中的纯文本/文档文件；git 历史即变更留痕，PR 即评审流 | 不自建审计追踪系统；一切格式必须 diff 友好（YAML/CSV 优先） |
| A3 | **签署留在客户 QMS** | 产出 signature-ready 证据包，完整性由 SHA-256 清单保证；签署与受控归档走客户现有体系（Veeva / MasterControl / 纸质流程） | 不做电子签名，不宣称 21 CFR Part 11 合规；AVIOR 自身不成为需被供应商审计的 GxP 关键系统 |

---

## 3. 目标用户与用户旅程

### 3.1 用户

| 画像 | 角色 | 关键动作 |
| --- | --- | --- |
| 验证负责人 / 统计编程负责人 | 主用户 | `init` 配置策略、审阅决策 PR、发起 `bundle`、把证据包送 QA |
| 统计程序员 / R 开发者 | 高频用户 | 填写决策记录、为中高风险包写定向测试、修 `check` 红灯 |
| QA / 合规 | 验收方（不直接操作工具） | 审查证据包、在自有 QMS 中签署归档 |
| 审计员 / 监管方 | 外部只读 | 阅读报告与追溯矩阵、用 `verify` 校验证据包完整性 |

第一个用户是我们自己团队的真实项目（design partner），一切验收以真实项目跑通为准。

### 3.2 旅程 J1：首次建立验证证据（V1 核心闭环）

1. `avior init` —— 生成策略文件骨架与目录结构，rationale 字段留 TODO。
2. 负责人补全策略（权重、阈值、理由），走 PR 评审合入 —— 策略即受控文档。
3. `avior scan` —— 从 `renv.lock` 生成包清单：三分类 + 直接/间接识别。
4. `avior assess` —— 批量评分，生成评分快照。
5. `avior review` —— 为在册包生成决策记录桩；团队分头填写决策（含理由与署名），走 PR 评审。
6. 对判定为中高风险的包补写定向 testthat 测试；`avior test` 运行。
7. `avior bundle` —— 编译证据包（报告 + 追溯矩阵 + 环境指纹 + 哈希清单）。
8. QA 审查证据包 → 在客户 QMS 中签署归档。AVIOR 的工作到 bundle 为止。

### 3.3 旅程 J2：CI 持续门禁（V1）

`avior check` 挂进 CI。任何人升级依赖 / 引入新包 / 改动策略，门禁即红：新包缺决策、版本变更导致评分过期、rationale 留空。红灯指引对应命令修复。**这一条命令以近零成本覆盖了「持续验证」的大部分需求**，无需监控平台。

### 3.4 旅程 J3：升级触发再验证（V2）

diffify 差异摘要 + oysteR CVE 命中 → 变更影响评估记录 → 定向重跑 assess/test → 新 bundle。V2 范围，本版不展开。

---

## 4. 版本范围总览

| 版本 | 范围 | 优先级标记 |
| --- | --- | --- |
| **V1（MVP）** | 第三方包评估管线全闭环：8 条 CLI 命令 + 证据包格式 + CI 门禁 | P0 |
| **V1.1** | `avior draft tests`（AI 起草定向测试，human-in-the-loop）；英文报告字符串完善 | P1 |
| **V2** | 自研包线（编排 valtools）、diffify/oysteR 监控与变更评估、NMPA 双语模板包、rmarkdown 降级渲染 | P2 |

### 明确不做

**永久不做（公理约束）**：电子签名 / Part 11 认证；SaaS / 托管服务 / Web 界面；自建用户体系与审计追踪系统；替客户做合规判断或代签。

**V1 阶段不做**：自研包 SDLC 验证（当下直接用 valtools 本身）；SOP 文档管理；监控/触发引擎；AI 起草；多项目治理；双语模板。

---

## 5. 功能需求（按 CLI 命令组织）

需求编号 `FR-<命令>-<序号>`。每条含验收标准（AC）。P0 = V1 必须。

### 5.0 全局约定

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-X-1 | 所有命令在项目根目录运行，读取 `validation/avior.yml`（目录可经 `project.validation_dir` 配置） | P0 |
| FR-X-2 | 所有命令支持 `--format json` 输出机器可读结果（供 CI 注解与二次加工） | P0 |
| FR-X-3 | 退出码约定：`0` 成功/通过；`1` 校验不通过（业务性失败）；`2` 执行错误（环境/配置问题） | P0 |
| FR-X-4 | 评估引擎经适配层接入（见 §7.2）；V1 实现 riskmetric 适配器；引擎 id 与版本记入一切评分产物 | P0 |
| FR-X-5 | 评分缓存：以「包名+版本+引擎 id+引擎版本+指标集」为键，缓存于项目 `validation/.cache/`（gitignore）；重跑只算变更项。缓存条目记录 `na_metrics` **及其成因（`network`/`execution`）**：命中项含 network 成因 NA 且当前网络可用时视为**可改进命中**，默认重评（可配置）；execution 成因 NA（指标未随 `--deep` 运行）**不触发**自动重评，仅由 `--deep` 解决——否则默认策略下每次联网命中都会被误判为可改进 | P0 |
| FR-X-6 | 配置与产物 schema 带版本号（`avior: 1`）；schema 演进保持向后可读——旧证据包永不失效 | P0 |
| FR-X-7 | **确定性排序**：一切生成物中的包序为**包名字母序**（C locale 字节序，大小写敏感——大写整体排在小写之前，如 `Matrix` 排在 `jsonlite` **之前**（`0x4D` < `0x6A`）；勿用大小写不敏感或 locale-aware 排序），覆盖 `inventory.yml`、`scores.yml`、`traceability.csv` 与报告逐包明细；`test-results.yml` 按测试文件路径排序；`MANIFEST.sha256` 按相对路径排序（§6.4）。这是「重复执行输出字节一致」（各命令 AC）的前提 | P0 |
| FR-X-8 | **规范化序列化**：一切生成物 UTF-8 无 BOM、LF 换行（全平台一致）；数值一律十进制小数（禁科学计数法），银行家舍入至最多 4 位小数、去尾零但 score/weight 至少保留 1 位小数（`1`→`1.0`、`0.6100000000000001`→`0.61`）；时间戳统一 UTC ISO-8601 秒级（`YYYY-MM-DDTHH:MM:SSZ`）；YAML 生成物默认 block 风格、2 空格缩进、键序按 schema 定义、仅必要时加引号，**行内紧凑映射（flow map）仅在 §6 各产物示例指明处使用**（如 `risk_tiers`、inventory 包行、scores 的 `engine`/`metrics` 行），逐产物固定不混用；JSON 生成物 2 空格缩进、键序按 schema 定义、最小转义、文件末尾换行；CSV 字段仅在含 ASCII 逗号、双引号、换行或非 ASCII 字符时加引号。FR-X-7 + FR-X-8 共同构成字节一致 AC（NFR-1）的前提 | P0 |

### 5.1 `avior init` —— 脚手架

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-INIT-1 | 生成 `validation/` 目录结构与 `avior.yml` 骨架：默认权重与阈值（默认权重仅含 metadata/network 档指标，见 §6.2 说明）+ `rationale` 字段置 `TODO`；`check` 在 TODO 存在时不通过（强制组织写下阈值理由） | P0 |
| FR-INIT-2 | 幂等：已存在的文件不覆盖，输出差异提示 | P0 |
| FR-INIT-3 | `--ci github\|gitlab` 生成对应 CI 工作流文件（在 PR 上跑 `avior check`） | P1 |

**AC**：空 R 项目执行 `init` 后，目录与配置文件与 §6.1 布局一致；重复执行无破坏。

### 5.2 `avior scan` —— 依赖识别与分类

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-SCAN-1 | 解析 `renv.lock`（首选）或 `DESCRIPTION`，产出包清单 `validation/inventory.yml`（生成物，纳入 git） | P0 |
| FR-SCAN-2 | 三分类：`base`/`recommended`（按 R 发行优先级字段）、`contributed`、`custom`（依 renv 来源为 GitHub/local/私有仓库，或 `scope.custom_orgs` 规则）；`base`/`recommended` **默认**不纳入评分与深验（随 R 发行分发，视为低风险） | P0 |
| FR-SCAN-3 | intended-for-use 识别：静态扫描项目 R 源码中的 `library()`/`require()`/`pkg::` 调用，区分 `direct`（直接调用）与 `transitive`（间接依赖）；每个判定附出处（文件:行 或 DESCRIPTION 字段）。**无法解析的源码文件不得被静默跳过**：其相对路径（C locale 排序）记入 inventory 的可选 `scan` 段（`scan: { complete: false, skipped_files: [...] }`；完整扫描时该段省略，故干净项目 inventory 字节不变），`avior scan` 据此返回非成功状态（退出码 1），`check` 亦据此报红（`scan_incomplete`）——瞬时告警不构成审计证据 | P0 |
| FR-SCAN-4 | 人工覆盖：`scope.include`/`scope.exclude` 强制调整清单，覆盖行为本身记录进 inventory（`overridden: true` + 来源）；`scope.include` 可将默认豁免的 `base`/`recommended` 包**拉回评估范围**，纳入后照常评分、决策与补测 | P0 |
| FR-SCAN-5 | inventory 记录 lockfile 的 SHA-256，作为后续漂移检测基准 | P0 |

**AC**：对 design partner 项目（约 50 包），直接调用识别与人工核对清单的差异 ≤ 10%，且全部差异可经 FR-SCAN-4 修正；重复执行输出字节一致。

> **范围规则（明确口径）**：「recommended = 豁免」是**默认值而非铁律**。四准则第一条是**用途**——当一个 `recommended` 包承担主分析统计量（如 `survival` 的 coxph）时，intended-use 重要性优先于发行优先级，应经 `scope.include` 强制纳入并走完整评分/决策/补测链路（§6.3 示例即此情形）。

### 5.3 `avior assess` —— 风险评分

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-ASSESS-1 | 对 inventory 中在验证范围内（`in_scope: true`）的包——默认为 `contributed`/`custom`，也含经 `scope.include` 强制纳入的 `base`/`recommended` 包——经适配层批量评分，按策略权重聚合为 0–1 风险分，写入 `validation/scores.yml`（纳入 git）；`scores.yml` 记录本次运行模式 `run: { deep, network }`，审计员据此判断 execution 档指标是否实际运行 | P0 |
| FR-ASSESS-2 | 按 `policy.risk_tiers` 阈值给出风险档（low/medium/high） | P0 |
| FR-ASSESS-3 | 指标缺失（如离线导致下载量不可得）记为 `NA` 并列入 `na_metrics`，聚合时按策略声明的处理方式（`na_action: reweight\|zero\|fail`）处理；NA 情况必须可见：`scores.yml` 逐包记录 `na_metrics`（为空省略）+ 顶层聚合，报告在生效权重与策略权重不一致时（即 `na_metrics` 非空经 reweight）逐包展示生效权重 | P0 |
| FR-ASSESS-4 | 支持离线评估：优先从本地已安装包/本地元数据评估；需要网络的指标在离线时走 FR-ASSESS-3 路径，不阻断整体评分 | P0 |
| FR-ASSESS-5 | `--only <pkg>` 增量重评单包 | P1 |

**AC**：50 包冷启动（含网络元数据，不含 execution 档指标）≤ 30 分钟，缓存命中重跑 ≤ 5 分钟（目标值，W3–6 以实测校准）；`scores.yml` 记录引擎 id/版本、评分时间、run 模式（deep / network 可用性）、逐指标原始值。

### 5.4 `avior review` —— 决策留痕

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-REVIEW-1 | 为每个「在范围内但缺决策记录」的包生成 `validation/decisions/<pkg>.yml` 桩（预填包名、版本、评分快照引用；决策字段留空） | P0 |
| FR-REVIEW-2 | 决策枚举：`include` / `include_with_tests` / `exclude`；`include_with_tests` 必须关联至少一个测试文件 | P0 |
| FR-REVIEW-3 | 完整性校验并报告：缺决策、决策未署名、rationale 为空、决策引用的评分快照与当前包版本不符（过期） | P0 |
| FR-REVIEW-4 | 决策记录含 `use_statement`（声明用途）字段；中高风险包必填——它是定向测试与 V1.1 AI 起草的输入 | P0 |
| FR-REVIEW-5 | AI 参与的决策必须 `ai_assisted: true` 且 `confirmed_by` 非空（为 V1.1 预留的双署名字段，schema 先行） | P0 |

**AC**：删除任一决策文件或篡改版本号后，`review` 与 `check` 均能准确报出对应包名与缺陷类型。

### 5.5 `avior test` —— 定向测试执行

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-TEST-1 | 运行 `validation/tests/` 下的 testthat 文件；测试与包的映射经文件头部注释声明（`# avior-package: <pkg>`） | P0 |
| FR-TEST-2 | 结果（通过/失败/跳过、耗时、testthat 版本）写入 `validation/test-results.yml`，供 bundle 采集；结果与运行环境绑定：记录被测包版本 + 运行时 `renv.lock` SHA-256 + R 版本/平台；被测包版本不符**或 lockfile 哈希与当前 inventory 基准不符**均视为过期 | P0 |
| FR-TEST-3 | 采集 covr 覆盖率作为参考指标（不作为门禁阈值——覆盖率高≠关键函数被测到，遵循参考文件的告诫） | P1 |

**AC**：`include_with_tests` 的包若测试失败或结果过期，`check` 必红。

### 5.6 `avior bundle` —— 证据包编译

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-BUNDLE-1 | 产出不可变证据包目录 `validation/evidence/bundle-<UTC 时间戳>/`；已存在的 bundle 永不覆盖。zip 为**传输件而非归档件**：仅 `--zip` 时生成且默认 gitignore（目录 + manifest 是归档形态，zip 可经 `SOURCE_DATE_EPOCH` 确定性重建）。留存口径：git 历史即归档，工作区可按需裁剪旧 bundle | P0 |
| FR-BUNDLE-2 | 内容物：验证报告（HTML + docx，PDF 可选）、`traceability.csv` 追溯矩阵、`environment.json` 环境指纹、`session-info.txt` 会话指纹、策略/清单/评分/决策/测试结果的快照副本、`BUNDLE.yml` 元数据、`MANIFEST.sha256` | P0 |
| FR-BUNDLE-3 | 报告结构对齐 GAMP 5 叙事：方法论引用（四准则）→ **范围与边界声明** → 范围与分类 → 评分与阈值 → 决策汇总 → 测试证据 → 环境与可复现性 → 附录（逐包明细）；模板字符串外置，V1 提供中文，V1.1 补英文。「范围与边界声明」为固定章节，明确本证据包**不覆盖**：计算环境 IQ/OQ/PQ（申办方 IT 在其 QMS 下的责任，GAMP 5 管辖）、项目分析代码的 QC/双重编程（§1.4 边界）、Part 11 控制（宿主系统责任）；`base`/`recommended` 默认豁免须分层署明依据——R-FDA.pdf 仅支持「属官方发行范围、经 R Core SDLC 维护」的**事实**（该文档不下「低风险」结论，且要求组织按 intended use 自定 SOP），「默认豁免（低风险起点）」为 **AVIOR 策略默认值**、其风险分级出处为白皮书四准则，且可经 `scope.include` 拉回 | P0 |
| FR-BUNDLE-4 | 追溯矩阵列定义见 §6.5；每行打通「包 → 分类 → 评分 → 决策 → 测试 → 结果」 | P0 |
| FR-BUNDLE-5 | 环境指纹：R 版本、OS/平台、仓库 URL（含 PPM 快照 ID 如有）、`renv.lock` SHA-256、avior 与引擎版本、locale（至少 `LC_COLLATE`）、BLAS/LAPACK 实现与版本（经 `sessionInfo()` 采集；不可得记 `"unknown"`，键不可省略）、容器镜像摘要（可检测时记录，否则 `null`）；完整 `sessionInfo()` 文本随 bundle 存为 `session-info.txt` | P0 |
| FR-BUNDLE-6 | bundle 前置校验：等价于 `check` 通过才允许编译（`--force` 可越过，但报告首页醒目标注「完整性校验未通过」） | P0 |
| FR-BUNDLE-7 | 证据包内含静态 HTML 风险总览页（纯文件，无服务） | P1 |
| FR-BUNDLE-8 | 支持 `SOURCE_DATE_EPOCH` 注入时间戳，便于确定性重建 | P1 |

**AC**：同一输入重跑 bundle，`traceability.csv`、`environment.json`、各快照副本字节一致（报告文件允许仅嵌入时间戳差异，FR-BUNDLE-8 启用时亦须一致）；启用 `--zip` 时，zip 解压后 `avior verify` 通过（zip 的确定性重建依赖 FR-BUNDLE-8）。

### 5.7 `avior check` —— CI 门禁

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-CHECK-1 | 漂移检测：当前 `renv.lock` 哈希 vs inventory 基准；新增/移除/版本变更逐包列出 | P0 |
| FR-CHECK-2 | 完整性检测：聚合 FR-REVIEW-3 全部校验 + 策略文件合法性（含 rationale TODO 检查、weights 引用已注册指标）+ 测试结果时效（含 FR-TEST-2 环境绑定校验）+ `excluded_but_present`：决策为 `exclude` 的包仍在 lockfile 中即红（修复建议：从项目移除该依赖，或修订决策并说明） | P0 |
| FR-CHECK-3 | 输出：人类可读摘要（按包分组、给出修复命令建议）+ `--format json`；退出码遵循 FR-X-3 | P0 |
| FR-CHECK-4 | 性能：50 包项目全量 check ≤ 30 秒（不触发重新评分，只做一致性校验） | P0 |

**AC**：在 design partner 项目 CI 中，对「升级一个包版本」「新增一个包」「清空一个 rationale」三种 PR 分别正确变红且指引修复。

### 5.8 `avior verify` —— 证据包完整性校验

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-VERIFY-1 | 对指定 bundle（目录或 zip）重算全部文件哈希并与 `MANIFEST.sha256` 比对，输出通过/篡改明细 | P0 |
| FR-VERIFY-2 | 面向审计员的独立可用性：不依赖项目上下文与配置文件，仅凭 bundle 本身即可运行 | P0 |
| FR-VERIFY-3 | 校验通过时同时输出 `MANIFEST.sha256` **自身**的 SHA-256（锚点值），供与 git 提交、QMS 归档记录或独立签名比对 | P1 |

**AC**：篡改 bundle 内任意一个字节，verify 必须报出具体文件。

> **信任边界（审计口径，ALCOA+ 评审必问）**：manifest 只保证 bundle 的**内部一致性**——防意外损坏与幼稚篡改有效。对脱离 git 的松散目录 / zip，能改文件者亦能重算并改写 `MANIFEST.sha256`，此时 verify 照常通过。**detached bundle 的防篡改锚点是外部的**：`evidence/` 所在的 git 提交哈希（本工具默认路径，公理 2「证据即文件 + git 留痕」的「留痕」半边即指此）、客户 QMS 归档记录、或独立签名——manifest 本身不是信任根。`BUNDLE.yml` 的 `integrity_check` 为**生成时点**执行的自证结果，同样不构成信任根。推荐做法：归档时把 manifest 自身的 SHA-256（FR-VERIFY-3 输出）记入 git 提交信息或 QMS 归档记录。

### 5.9 `avior draft tests <pkg>`（V1.1，P1）

| 编号 | 需求 | 优先级 |
| --- | --- | --- |
| FR-DRAFT-1 | 输入：决策记录的 `use_statement` + 包的导出函数签名与文档；输出：testthat 草稿文件，头部强制标注 `# AI-DRAFTED — 未经人工确认不得进入证据`，含边界/异常场景 | P1 |
| FR-DRAFT-2 | 采纳流程：人工编辑确认后，决策记录置 `ai_assisted: true` + `confirmed_by`；未确认的草稿被 `check` 视为不存在 | P1 |
| FR-DRAFT-3 | 数据边界：显式 opt-in；**默认使用第三方大模型**——被评估对象是开源 R 包，其元数据与函数签名无保密性；端点可配置，有源码保护需求（如涉及私有代码）时切换本地模型；客户私有代码默认不外发，除非显式配置 | P1 |
| FR-DRAFT-4 | AI 交互日志（prompt 摘要、模型 id、时间）留存于决策记录侧文件，可审计 | P1 |

---

## 6. 文件与数据契约（开发的核心规范）

### 6.1 项目内布局

```text
your-r-project/
├── renv.lock
└── validation/
    ├── avior.yml              # 策略即代码（受控文档，改动走 PR）
    ├── inventory.yml          # scan 生成（纳入 git）
    ├── scores.yml             # assess 生成（纳入 git）
    ├── test-results.yml       # test 生成（纳入 git）
    ├── decisions/             # 每包一条决策记录（人工编辑，纳入 git）
    │   └── <pkg>.yml
    ├── tests/                 # 定向 testthat 测试（人工编写）
    │   └── test-<pkg>-*.R
    ├── .cache/                # 评分缓存（gitignore）
    └── evidence/              # 不可变证据包（纳入 git，已决策）
        └── bundle-<timestamp>/
```

### 6.2 `avior.yml`（schema v1）

```yaml
avior: 1
project:
  name: my-trial-analysis
  validation_dir: validation          # 可选，默认 validation
scope:
  lockfile: renv.lock
  intended_for_use: auto              # auto | explicit（仅用 include 清单）
  include: []                         # 强制纳入；可把默认豁免的 base/recommended 包拉回评估范围（FR-SCAN-4）
  exclude: [datasets]                 # 强制排除（需在报告中说明）
  custom_orgs: ["our-gh-org/*"]       # 判定自研包的来源规则
policy:
  engine: riskmetric
  weights:                            # 指标 id 引用引擎适配层注册表
    has_vignettes: 0.5
    has_news: 0.5
    downloads_1yr: 1.0
    covr_coverage: 2.0                # execution 档指标：本项目显式选入，随 --deep 运行（§7.2）
  risk_tiers: { low_max: 0.25, high_min: 0.55 }
  na_action: reweight                 # reweight | zero | fail
  rationale: >                        # 必填；留 TODO 则 check 不通过
    阈值参考 riskassessment 默认配置，经统计编程组 2026-07 评审会确认；
    covr_coverage 加权 2.0 因本项目以统计计算为主（execution 档，
    组织显式选入并接受 --deep 深评成本）。
depth_by_risk:                        # 风险档 → 要求
  low: metadata_only
  medium: use_statement_required
  high: targeted_tests_required
report:
  formats: [html, docx]
  language: zh
```

> **init 默认模板与本例的区别**：上例为一个「显式选入 execution 档指标」的项目策略。`avior init` 生成的**默认权重仅含 metadata/network 档指标**（`has_vignettes: 0.5`、`has_news: 0.5`、`has_bug_reports_url: 0.5`、`downloads_1yr: 1.0`、`remote_checks: 1.0`、`last_30_bugs_status: 1.0`）——「测试」准则默认由 `remote_checks`（CRAN 机器检查结果，network 档）承担；`covr_coverage` 等 execution 档指标**不入默认权重**，须组织显式加入并接受 `--deep` 深评成本（如上例）。这保证默认策略下批量 assess 的性能 AC（§5.3）成立、且不产生恒非空的 `na_metrics`。

### 6.3 决策记录 `decisions/<pkg>.yml`

本例特意选用 `survival`：一个 **`recommended` 包被 `scope.include` 强制纳入**后的决策记录。`recommended` 默认豁免（§5.2 范围规则），但它承担主分析统计量时，intended-use 重要性把它拉回范围——纳入后照常评分、决策与补测，与 `contributed` 包无异。

```yaml
avior: 1
package: survival                     # recommended 包，经 scope.include 强制纳入（§5.2 范围规则）
version: "3.6-4"
score_snapshot:
  score: 0.61
  tier: high
  scored_at: "2026-07-10T08:12:00Z"
  engine: "riskmetric 0.2.x"
use_statement: >                      # 中高风险必填；定向测试与 AI 起草的依据
  用于 Cox 比例风险模型（coxph）与 KM 估计（survfit），
  主分析与敏感性分析均调用。
decision: include_with_tests          # include | include_with_tests | exclude
rationale: >
  高风险源于社区指标而非质量缺陷；针对声明用途补充金标准比对测试。
tests:
  - tests/test-survival-coxph.R
reviewed_by: "jin@example.com"
date: "2026-07-11"
ai_assisted: false                    # true 时 confirmed_by 必填
confirmed_by: null
assessment_type: initial              # initial | delta；V1 固定 initial，V2 变更影响评估（J3）用 delta
supersedes: null                      # V2：delta 评估所取代的先前决策引用；V1 恒为 null
```

### 6.4 证据包结构与 `MANIFEST.sha256`

```text
bundle-20260715T093000Z/
├── report.html / report.docx
├── traceability.csv
├── environment.json
├── session-info.txt           # sessionInfo() 全文（FR-BUNDLE-5）
├── snapshot/                  # 编译时点的输入快照
│   ├── avior.yml
│   ├── inventory.yml
│   ├── scores.yml
│   ├── test-results.yml
│   └── decisions/…
├── BUNDLE.yml                 # avior/引擎/R 版本、时间、策略与 lockfile 哈希
└── MANIFEST.sha256            # "<sha256>  <相对路径>" 按路径排序，覆盖除自身外全部文件
```

### 6.5 `traceability.csv` 列定义

`package, version, classification, role(direct|transitive), score, tier, decision, use_statement_ref, decision_file, reviewed_by, decision_date, test_files, test_status, notes`

——每行即一条完整证据链；QA 与审计员优先读这个文件。

两列引用的分工：`decision_file` 指向决策记录**文件**（`decisions/<pkg>.yml`）；`use_statement_ref` 指向其中的**字段锚点**（`decisions/<pkg>.yml#use_statement`），供审计员直接定位用途声明，无决策文件的行（如 transitive）两列均留空。行序为包名字母序（FR-X-7）。

`decision` 列的取值分两个命名空间：在范围内的行填 FR-REVIEW-2 决策枚举（`include`/`include_with_tests`/`exclude`）；`transitive` 行固定填行级状态值 **`version_managed`**（「仅版本管理，不深验」——intended-for-use 原则在追溯矩阵上的显式表达），它不属于决策枚举，不对应决策文件。

---

## 7. 架构与技术选型

### 7.1 架构（刻意薄）

```text
┌──────────────────────────────────────────────────┐
│ CLI 入口（avior / Rscript 包装，Windows 提供 .bat）│
├──────────────────────────────────────────────────┤
│ 核心 R 包：配置/Schema 校验 · 依赖分析与三分类 ·   │
│            策略引擎 · 决策校验 · 追溯链组装        │
├──────────────┬───────────────┬───────────────────┤
│ 评估适配层    │ 测试运行器     │ 报告编译器          │
│ riskmetric   │ testthat/covr │ Quarto → html/docx │
│ (V2:val.meter)│              │ (V2: rmarkdown 降级)│
├──────────────┴───────────────┴───────────────────┤
│ 状态 = 仓库里的文件。无服务端、无数据库、无守护进程 │
└──────────────────────────────────────────────────┘
```

### 7.2 评估引擎适配层（FR-X-4 的接口契约）

```r
# 引擎注册接口（概念签名，实现时细化）
avior_engine(
  id      = "riskmetric",
  version = utils::packageVersion("riskmetric"),
  metrics = function() { ... },          # 返回指标注册表：id、描述、是否需网络、成本档（cost）
  assess  = function(pkg, version, opts) # 返回 tibble(metric_id, value, status)
)
```

- 策略 `weights` 引用指标 id；引用未注册指标 → `check` 报错。指标注册表须可**静态获取**（不依赖引擎包已安装），`check` 据此离线校验 weights。
- 注册表每条指标含成本档 `cost: metadata | network | execution`；`execution` 档指标（如 `covr_coverage`，需装包并跑测试套件）**默认不进入批量 `assess`**，须经 `--deep` 或按包显式开启——这是 §5.3 性能 AC 成立的前提。
- 引擎 id + 版本写入 scores.yml 与每个 bundle。**切换引擎（riskmetric → val.meter）= 重新评分 + 决策刷新，走用户自己的变更控制** —— 工具保证新旧证据都可读、可对比，不承诺分数可比。

### 7.3 技术决策记录（ADR 摘要）

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 实现语言 | R 包为核心 | 用户是 R 团队；riskmetric/testthat/covr 都是 R；零额外运行时 |
| 最低 R 版本 | R ≥ 4.1 | 受监管环境普遍锁旧版本；不用高于 4.1 的语言特性 |
| 配置/产物格式 | YAML + CSV | diff 友好（公理 A2）；QA 无需工具即可阅读 |
| 报告引擎 | Quarto（系统前置依赖，文档明示）| 现代、支持 docx/html/pdf；锁死环境的降级方案（rmarkdown）列 V2 |
| 依赖策略 | 核心依赖最小化（cli、yaml、jsonlite 级别）；引擎与 covr 置 Suggests | AVIOR 自己也会被客户拿来评估——依赖树越小，自身风险画像越好 |
| 分发 | CRAN 优先 + GitHub Releases | CRAN 收录本身就是目标用户环境准入的信任信号 |
| 开源许可 | Apache-2.0（已确认） | 专利条款对企业采纳友好 |

---

## 8. 非功能需求

| 编号 | 类别 | 需求 |
| --- | --- | --- |
| NFR-1 | 可重现 | 同输入重跑：数据产物字节一致；报告在 `SOURCE_DATE_EPOCH` 下确定性重建（见 FR-BUNDLE-8 AC） |
| NFR-2 | 离线 | 除「显式声明需网络的指标」外，全流程可在 air-gapped 环境运行；离线降级路径明确（FR-ASSESS-3/4） |
| NFR-3 | 性能 | check ≤ 30s（50 包）；assess 冷 ≤ 30min / 热 ≤ 5min（50 包）；500 包批量给出并行选项，目标 ≤ 4h 冷启动 |
| NFR-4 | 安全与隐私 | 默认零外发（评估元数据抓取除外，且可关）；AI 功能 opt-in + 端点可配 + 数据边界文档化（FR-DRAFT-3） |
| NFR-5 | **自验证（dogfooding）** | 两个独立 CI 作业：**5a 管线自验**——AVIOR 仓库以 avior 跑自身开发依赖并产出证据包；**5b 自身画像**——以默认引擎与策略对 avior 包本身评分，必须落入低风险档（测试覆盖、文档、NEWS、bug 跟踪等指标齐备） |
| NFR-6 | 平台 | Linux / macOS / Windows；CI 三平台全绿 |
| NFR-7 | 兼容性 | schema 版本化；`avior` 遵循语义化版本；旧版本产出的证据包在新版本 `verify`/报告读取下永远可用 |
| NFR-8 | 可用性 | 从零到第一份评分 ≤ 3 条命令（init → scan → assess）；每个红灯信息附修复命令建议 |
| NFR-9 | 文档 | 用户手册 + 《方法论白皮书对照》文档（面向审计员：AVIOR 每个产物对应白皮书/GAMP 5 的哪个要求，引用出处） |

---

## 9. 里程碑与验收（12 周，1–2 人产能）

| 阶段 | 周 | 交付 | 出口标准（DoD） |
| --- | --- | --- | --- |
| M0 格式定稿 | W1–2 | 证据包结构 + 全部 schema（§6）冻结；手工组装一份样例证据包 | design partner 的 QA 同事审阅样例后确认「此格式可进入我们的签署流程」；schema 评审通过 |
| M1 核心管线 | W3–6 | `init`/`scan`/`assess`/`review` + 适配层 + 缓存 | 真实项目 50 包产出 inventory/scores/决策桩；FR-SCAN AC 达标；性能实测回填 §8 目标值 |
| M2 证据编译 | W7–9 | `test`/`bundle`/`check`/`verify` + 报告模板（中文） | J1 全旅程在真实项目跑通；`check` 三场景 AC 通过；`verify` 篡改检测 AC 通过 |
| M3 试点打磨 | W10–12 | 端到端试点、模板打磨、NFR-5 dogfooding 上线、NFR-9 两份文档 | **一份真实证据包通过内部 QA 审查**；CI 门禁稳定运行 ≥ 2 周；三平台 CI 全绿 |
| 决策点 | W12 | 依试点反馈决定 V1.1 优先级 | AI 起草（FR-DRAFT，隐私边界已定，见 §11） vs 自研包线提前 |

**V1 Definition of Done**：全部 P0 FR 的 AC 通过 + §10 成功标准 1–4 达成 + NFR-5/6/9 就绪。

---

## 10. 成功标准

1. **效率**：真实项目（约 50 个第三方包）从 `renv.lock` 到可签署证据包 ≤ 1 个工作日（对照人工路径：以周计）。
2. **合规有效性**：至少一份证据包通过一次真实的内部 QA 审查，审查意见回灌报告模板。
3. **可重现**：同输入重跑，**数据产物**（追溯矩阵、环境指纹、各快照副本）字节级一致且与 manifest 相符；报告文件内嵌时间戳，其确定性重建需启用 `SOURCE_DATE_EPOCH`（FR-BUNDLE-8；与 NFR-1 同口径）。
4. **持续性**：`avior check` 在 design partner CI 稳定运行 ≥ 4 周，依赖漂移零漏报。
5. **北极星指标**：通过完整性校验的证据包生成数（工具可观测；「经签署归档数」发生在客户 QMS，工具不可见，不作为指标）。度量口径：试点期在 design partner 项目内统计；开源后以 GitHub 采纳信号（真实使用报告）为代理。**不引入 telemetry**（NFR-4 零外发）。

---

## 11. 风险与开放问题

### 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| riskmetric 处于维护模式、val.meter 演进中 | 引擎失修/口径变化 | 适配层（§7.2）；引擎版本钉入证据；跟踪 val.meter 并预研适配器 |
| 「git 即审计追踪」被客户 QA 质疑 | 证据链认可度 | M0 用样例证据包先行验证；必要时 bundle 附「变更历史导出」章节（仍是文件，不是系统） |
| intended-for-use 静态识别不准（动态调用、Suggests 边界） | 清单可信度 | 人工覆盖机制（FR-SCAN-4）+ 判定出处可追溯；识别差异纳入 M1 AC 度量 |
| Quarto/pandoc 在锁死环境不可用 | 报告无法生成 | 前置依赖文档明示；HTML 优先（依赖最轻）；rmarkdown 降级列 V2 |
| 离线环境指标大面积 NA | 评分可信度 | `na_action` 策略显式化 + 报告披露 NA 面；提供联网机器上预热缓存后迁移的操作指引 |
| 评分/报告性能不达标 | 体验与里程碑 | 缓存（FR-X-5）+ 并行选项；M1 实测回填目标 |
| 单人/小团队产能 | 范围蔓延 | §2 公理作为需求准入检验；本 PRD 之外的需求默认进 V2 backlog |

### 已决事项（2026-07-08 评审确认）

| # | 问题 | 决策 |
| --- | --- | --- |
| Q1 | AI 起草的模型与隐私边界 | **默认第三方大模型**——被评估对象是开源 R 包，元数据与签名无保密性；端点可配置，有源码保护需求时切换本地模型（FR-DRAFT-3 已同步） |
| Q2 | 开源许可 | **Apache-2.0**（§7.3 已同步） |
| Q3 | `evidence/` 是否纳入 git | **纳入**——证据与代码同库，git 历史即归档链（§6.1 已同步） |
| Q4 | 英文报告字符串时点 | **不进 V1**；V1 仅中文模板，英文随 V1.1（与 §4 版本表一致） |

当前无未决问题；新问题按本节格式追加，决议后落档至对应章节。

---

## 12. 术语表

| 术语 | 含义 |
| --- | --- |
| GxP | 药品研发生产各环节质量规范的统称（GCP/GLP/GMP…），本产品语境指受监管申报环境 |
| GAMP 5 | ISPE 计算机化系统验证指南；本产品对齐其最小交付物：规范、风险评估、测试、追溯矩阵 |
| 21 CFR Part 11 | FDA 电子记录与电子签名法规；AVIOR 依公理 A3 不做签名，仅产出可送签证据 |
| 四准则 | R Validation Hub 白皮书的风险评估维度：用途/类型、维护、社区使用、测试 |
| intended-for-use | 只对用户直接调用的包做深度验证的聚焦原则 |
| riskmetric / val.meter | pharmaR 的包风险评估引擎（现役/下一代），经适配层接入 |
| valtools | PHUSE 的自研包验证框架（RPVF）；V2 编排对象，当前直接使用 |
| 证据包（bundle） | AVIOR 的核心产出：报告 + 追溯矩阵 + 环境指纹 + 输入快照 + 哈希清单的不可变集合 |
| QMS | 客户的质量管理体系/文档系统（Veeva、MasterControl 等），签署与受控归档发生地 |

---

## 13. 修订记录

| 版本 | 日期 | 变更 |
| --- | --- | --- |
| v1.0 | 2026-07-08 | 初版开发基线 |
| v1.1 | 2026-07-08 | 新增 §1.4 验证对象与产物边界；Q1–Q4 评审决策落档（AI 默认第三方模型、Apache-2.0、evidence 纳入 git、英文模板不进 V1） |
| v1.2 | 2026-07-10 | 落实 PR 评审意见 #1/#2：§5.2 明确「recommended 默认豁免、可经 `scope.include` 强制纳入」范围规则（FR-SCAN-2/4、FR-ASSESS-1、§6.2、§6.3 联动）；§5.8 明确 manifest 仅保证内部一致、防篡改锚点在外部（git 提交 / QMS / 签名），新增 FR-VERIFY-3 输出 manifest 自身哈希 |
| v1.3 | 2026-07-10 | 落实评审后续项（issues #7/#8）：§10-#3 显式限定字节级可复现仅覆盖数据产物、报告需 `SOURCE_DATE_EPOCH`（与 NFR-1 对齐）；§6.5 明确 `use_statement_ref` 为字段锚点（`decisions/<pkg>.yml#use_statement`），与 `decision_file` 分工 |
| v1.4 | 2026-07-10 | 落实 issue #11（NFR-6 可移植性）：根目录文档迁入 `docs/` 并 ASCII 化文件名（本文件原名 `AVIOR PRD.md`），内容无变更；索引见 `docs/README.md` |
| v1.5 | 2026-07-10 | 落实 issue #15：新增 FR-X-7 确定性排序——生成物包序为包名字母序（C locale），`test-results.yml` 按测试文件路径、manifest 按相对路径；示例文件同步整理 |
| v1.6 | 2026-07-12 | 落实《产品设计方向与路线评审》（`docs/product-design-review.md`）A/B/C 级处置：A1 新增 FR-X-8 规范化序列化；A2 §6.5 定义 transitive 行 `version_managed` 状态值；A3 FR-BUNDLE-2/5、§6.4 环境指纹扩展（locale/BLAS/容器摘要/`session-info.txt`）；A4 FR-TEST-2 测试结果环境绑定；A5 FR-BUNDLE-3 增「范围与边界声明」固定章节（含 R-FDA.pdf 豁免出处）；A6 FR-CHECK-2 增 `excluded_but_present` 红灯；B1 §7.2 指标成本档（`execution` 默认不批量、注册表可静态获取）；B2 FR-X-5/FR-ASSESS-3 缓存 NA 感知与生效权重披露；B3 FR-BUNDLE-1 zip 定义为传输件；B4 §6.3 预留 `assessment_type`/`supersedes`；B5 NFR-5 拆分 5a/5b；C1 §10-5 度量口径（无 telemetry）；文档版本号自 v1.1 起未随修订记录更新，本次一并对齐。评审子代理复核后修正：FR-X-5 区分 NA 成因（network/execution，防默认策略下重评循环）；§6.2 增 init 默认模板说明（默认权重仅 metadata/network 档，测试准则由 `remote_checks` 承担）；FR-ASSESS-1/AC 增 `run: { deep, network }` 运行模式披露；FR-X-8 细化 flow map 逐产物指明、JSON 风格、CSV 非 ASCII 加引号；§5.6 zip AC 条件化 |

---

*本 PRD 为 AVIOR 开发基线。修订走 PR；任何与 §2 设计公理冲突的变更须先修订公理并记录理由。*
