<div align="center">

# AVIOR

**Automated Validation and Inspection for Operational R-packages**

`renv.lock` in → a signature-ready validation evidence bundle out.

[![Status](https://img.shields.io/badge/status-M1%20%2B%20M2%20implemented-green)](./docs/PRD.md)
[![CI](https://github.com/Thynexa/AVIOR/actions/workflows/ci.yml/badge.svg)](https://github.com/Thynexa/AVIOR/actions/workflows/ci.yml)
[![Coverage](https://github.com/Thynexa/AVIOR/actions/workflows/coverage.yml/badge.svg)](https://github.com/Thynexa/AVIOR/actions/workflows/coverage.yml)
[![Lint](https://github.com/Thynexa/AVIOR/actions/workflows/lint.yml/badge.svg)](https://github.com/Thynexa/AVIOR/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](#license--许可)
[![Language](https://img.shields.io/badge/implementation-R%20%E2%89%A5%204.1-276DC3)](./docs/PRD.md)
[![PRD](https://img.shields.io/badge/PRD-development%20baseline-informational)](./docs/PRD.md)

**English** ｜ [中文](#中文)

</div>

---

## English

### What is AVIOR

AVIOR is a **local-first evidence compiler for R package validation** in regulated environments (FDA / EMA / NMPA submissions). Like `pytest` or `terraform`, it lives in your repository and your CI: it takes your dependency manifest and validation policy as input, and produces a structured, tamper-evident, signature-ready evidence bundle.

The name comes from **Avior (ε Carinae)**, a star in the keel of the mythical ship Argo — the keel of a validation program.

> ### 📌 Current status: M1 core pipeline and M2 evidence compilation implemented
>
> The `avior` R package now implements the **M1 milestone** of the PRD: `init` / `scan` / `assess` / `review` plus the `check` CI gate (pulled forward from M2), built test-driven against the frozen v1.6 file contracts with a comprehensive regression suite, byte-identical artifacts, and CI definitions for Linux/macOS/Windows plus the R 4.1 floor (PRs #17–#19).
>
> The **M2 milestone** now ships too (issues #30–#33): `avior test` (targeted testthat execution with environment-bound results), `avior bundle` (immutable, byte-reproducible evidence bundles), `avior verify` (auditor-standalone integrity verification), and the **English validation report** (HTML + DOCX, rendered by a built-in dependency-free renderer). English is the V1 report language; the Chinese template is an explicit fail-closed placeholder locale until a complete translation lands (PRD v1.8). The engine default is riskmetric; assessments need it installed at runtime (`check` validates policies offline via the static metric registry).
>
> The development baseline is [`PRD.md`](./docs/PRD.md) — all work is scoped against it, and revisions go through pull requests.

### The problem

Teams using R in regulated environments must, today, manually stitch together at least seven separate tools — riskmetric, riskassessment, valtools, PPM, renv, diffify, oysteR — and hand-write and glue together risk assessments, decision records, traceability matrices, and validation reports. Fragmented orchestration and documentation gaps are the biggest cost; the evidence chain is held together by hand and breaks easily under audit.

AVIOR compiles **dependency identification → risk scoring → decision trail → targeted testing → environment fingerprinting → audit-ready reporting** into a single command's output.

**AVIOR is**: an evidence compiler that runs in your environment and CI, producing a bundle ready to be signed.
**AVIOR is not**: a platform. It does not host data, does not perform electronic signatures, does not provide a web service, and does not make compliance judgments on the sponsor's behalf — compliance responsibility always remains with the sponsor.

### Three design axioms

Every scope decision is checked against these three axioms before it can enter the backlog.

| # | Axiom | Direct consequence |
| --- | --- | --- |
| A1 | **Ship a pipeline, not a platform** | No server, no database, no multi-tenancy, no account system |
| A2 | **Evidence is files** | Policy, inventory, scores, decisions, and reports are all plain text/documents in the repo; git history *is* the change trail, PRs *are* the review flow |
| A3 | **Signing stays in the customer's QMS** | Produces a signature-ready bundle (SHA-256 manifest guarantees integrity); signing and controlled archival happen in the customer's existing system (Veeva, MasterControl, paper process) |

### CLI (V1 core loop)

```bash
avior init      # ✅ scaffold policy file skeleton and directory structure (idempotent; --ci github|gitlab)
avior scan      # ✅ identify dependencies from renv.lock (DESCRIPTION fallback): classification + direct/transitive
avior assess    # ✅ batch risk scoring via the engine adapter layer (riskmetric; --deep, --offline, --only, --refresh-na true|false)
avior review    # ✅ generate decision-record stubs; validate completeness/sign-off
avior test      # ✅ run targeted testthat tests, write environment-bound test evidence (--coverage)
avior bundle    # ✅ compile an immutable evidence bundle (report + traceability + fingerprint + manifest; --force, --zip)
avior check     # ✅ CI gate: drift + completeness + fail-closed integrity rules (exit 0/1/2)
avior verify    # ✅ independently verify bundle integrity (read-only, no project context needed)
```

Every command supports `--format json` for machine consumption (FR-X-2); exit codes are 0 = pass, 1 = validation failure, 2 = execution error (FR-X-3).

**Generated artifacts vs human input.** `inventory.yml` and `scores.yml` are generated artifacts owned by their commands: a rescan rewrites them wholesale, deterministically. The one supported human annotation in the inventory is the per-package `note:` field (it appears in the frozen example) — rescans carry it over by package name, and it leaves with its package row. Any other hand-added field is discarded on rescan, never silently: `scan` warns and points at the durable home for substantive human input, the decision records (`validation/decisions/<pkg>.yml`: `rationale`, `use_statement`).

### Try it (development version)

```r
# not yet on CRAN — install from GitHub:
# install.packages("pak"); pak::pak("Thynexa/AVIOR")
library(avior)

avior_init()     # scaffold validation/ in your project (rationale left as TODO on purpose)
avior_scan()     # writes validation/inventory.yml from renv.lock + source scan
avior_assess()   # writes validation/scores.yml (requires the riskmetric package)
avior_review()   # decision stubs + completeness findings
# Complete validation/decisions/*.yml and add validation/tests/test-*.R.
avior_test()     # writes environment-bound validation/test-results.yml
gate <- avior_check()
stopifnot(gate$status == "pass")

bundle <- avior_bundle(zip = TRUE) # English report.html + report.docx
directory_check <- avior_verify(bundle$path)
zip_check <- avior_verify(bundle$zip)
stopifnot(directory_check$status == "pass", zip_check$status == "pass")
directory_check$anchor             # archive this SHA-256 outside the bundle
```

Every targeted test file must contain exactly one
`# avior-package: <package>` header. English is the implemented report locale;
selecting the Chinese placeholder (`report.language: zh`) fails closed before
writing a partial or mixed-language bundle.

### Repository layout

```text
AVIOR/
├── DESCRIPTION · NAMESPACE          # R package metadata (R ≥ 4.1; Imports: cli, digest, jsonlite, yaml)
├── R/                               # Implementation: config/scan/assess/review/test/check,
│                                    #   bundle/verify, report renderers, canonical serialization, CLI
├── tests/testthat/                  # Regression suite + vendored fixture copy of the example project
├── man/                             # Function reference
├── exec/avior                       # CLI shim (Rscript)
├── inst/templates/ · inst/report/   # Config/CI templates + versioned report locales
├── .github/workflows/ci.yml         # Linux / macOS / Windows + R 4.1 matrix
├── docs/                            # Project documentation
│   ├── README.md                    # Documentation index
│   ├── PRD.md                       # ⭐ Development baseline (controlled; see its revision log)
│   ├── r-regulatory-submission-research.md  # Methodology research
│   ├── r-package-validation-strategy.md     # Validation strategy analysis
│   └── riskmetric-spike-results.md          # riskmetric engine spike results
└── examples/
    └── minimal-project/             # M0 hand-assembled example bundle (5 packages, all key scenarios)
```

### Where to start reading

| If you are… | Start with |
| --- | --- |
| Looking for the full product picture | [`PRD.md`](./docs/PRD.md) — positioning, axioms, CLI, file contracts, milestones |
| Wondering what a bundle looks like | [`examples/minimal-project/`](./examples/minimal-project/) — a readable hand-built sample with a QA/auditor reading guide |
| Interested in the methodology | [`r-regulatory-submission-research.md`](./docs/r-regulatory-submission-research.md) — regulatory background and tool-chain comparison |

### Methodology anchors

- **R Validation Hub white paper** — the four risk-assessment criteria (intended use/type, maintenance, community usage, testing).
- **Intended-for-use focus** — deep validation targets only directly-called packages; transitive dependencies get version management only. This is the key lever that keeps effort bounded.
- **ISPE GAMP 5 (2nd edition)** — minimum deliverables: specification, risk assessment, testing, traceability matrix.

### Technical choices (from PRD §7.3)

| Decision | Choice |
| --- | --- |
| Implementation language | An R package at the core (users are R teams; riskmetric/testthat/covr are all R) |
| Minimum R version | R ≥ 4.1 |
| Config / artifact format | YAML + CSV (diff-friendly; QA can read without tooling) |
| Report engine | Built-in dependency-free renderer → self-contained HTML + DOCX |
| Distribution | CRAN first, GitHub Releases |
| Open-source license | Apache-2.0 |

### Contributing

The PRD is the development baseline. Revisions go through pull requests; any change that conflicts with the design axioms in §2 must first amend the axioms themselves, with rationale recorded.

### License / 许可

Apache-2.0 — full text in [`LICENSE.md`](./LICENSE.md) (see PRD §7.3, decided item Q2).

---

## 中文

### AVIOR 是什么

AVIOR 是一个面向受监管环境（FDA / EMA / NMPA 申报）的 **local-first R 包验证证据编译器**。它像 `pytest` / `terraform` 一样活在你的仓库和 CI 里：输入项目的依赖清单与策略配置，输出结构化、防篡改、可直接送签的验证证据包。

命名取自船底座 ε（Avior）——神话中阿尔戈号的龙骨，寓意验证体系的龙骨。

> ### 📌 当前状态：M1 核心管线与 M2 证据编译均已实现
>
> `avior` R 包已实现 PRD 的 **M1 里程碑**：`init` / `scan` / `assess` / `review` 以及提前落地的 `check` CI 门禁——全程 TDD、对齐冻结的 v1.6 文件契约，具备完整回归测试、字节级确定性产物，以及覆盖 Linux / macOS / Windows 与 R 4.1 下限的 CI 定义（PR #17–#19）。
>
> **M2 里程碑现已落地**（issues #30–#33）：`avior test`（定向 testthat 执行 + 环境绑定的测试证据）、`avior bundle`（不可变、字节可复现的证据包）、`avior verify`（审计员独立完整性校验）、以及**英文验证报告**（HTML + DOCX，内建零依赖渲染器）。V1 报告语言为英文；中文模板为显式 fail-closed 占位 locale，完整翻译落地前选择 `zh` 会明确报错（PRD v1.8）。默认引擎为 riskmetric，评分需运行时安装该包（`check` 经静态指标注册表可离线校验策略）。
>
> 开发基线是 [`PRD.md`](./docs/PRD.md)——所有工作以此为准，修订走 PR。

### 它解决什么问题

受监管环境用 R 的团队要建立合规的包验证体系，今天必须手工缝合 riskmetric、riskassessment、valtools、PPM、renv、diffify、oysteR 等至少 7 个工具，并人工编写与拼接风险评估、决策记录、追溯矩阵、验证报告。碎片化编排与文档黑洞是最大成本；证据链靠手工维系，审计时易断裂。

AVIOR 把「依赖识别 → 风险评分 → 决策留痕 → 定向测试 → 环境指纹 → 审计就绪报告」编译成一条命令的产出。

**是**：一个证据编译器，跑在用户环境与 CI，输出可送签的验证证据包。
**不是**：平台。不托管数据、不做电子签名、不提供 Web 服务、不替客户做合规判断——合规责任主体始终是申办方。

### 三条设计公理（约束一切范围决策）

任何新需求进入 backlog 前，必须先通过这三条公理的检验。

| # | 公理 | 直接后果 |
| --- | --- | --- |
| A1 | **做管线，不做平台** | 无服务端 / 数据库 / 多租户 / 账号体系 |
| A2 | **证据即文件** | 策略、清单、评分、决策、报告全是版本库中的纯文本；git 历史即变更留痕，PR 即评审流 |
| A3 | **签署留在客户 QMS** | 产出 signature-ready 证据包（SHA-256 清单保证完整性）；签署与受控归档走客户现有体系（Veeva / MasterControl / 纸质流程） |

### CLI（V1 核心闭环）

```bash
avior init      # ✅ 生成策略骨架与目录结构（幂等；--ci github|gitlab 生成 CI 工作流）
avior scan      # ✅ 从 renv.lock（缺失时回退 DESCRIPTION）识别依赖：三分类 + direct/transitive
avior assess    # ✅ 经适配层（riskmetric）批量风险评分（--deep / --offline / --only / --refresh-na true|false）
avior review    # ✅ 生成决策记录桩 + 完整性/署名校验
avior test      # ✅ 运行定向 testthat 测试，写出环境绑定的测试证据（--coverage）
avior bundle    # ✅ 编译不可变证据包（报告 + 追溯矩阵 + 环境指纹 + 哈希清单；--force / --zip）
avior check     # ✅ CI 门禁：漂移 + 完整性 + fail-closed 规则（退出码 0/1/2）
avior verify    # ✅ 独立校验证据包完整性（审计员只读，无需项目上下文）
```

所有命令支持 `--format json` 机器可读输出（FR-X-2）；退出码 0 = 通过、1 = 校验不通过、2 = 执行错误（FR-X-3）。

**生成物与人工输入的所有权。** `inventory.yml` 与 `scores.yml` 是命令所有的生成物：rescan 会确定性地整体重写。inventory 中唯一受支持的人工注释是逐包的 `note:` 字段（冻结样例中即存在）——rescan 按包名保留它，包行消失时随行移除。其余任何手工添加的字段会在 rescan 时被丢弃，但绝不静默：`scan` 会发出警告，并指向实质性人工输入的长期归属——决策记录（`validation/decisions/<包名>.yml` 的 `rationale`、`use_statement`）。

### 试用（开发版）

```r
# 尚未上 CRAN，从 GitHub 安装：
# install.packages("pak"); pak::pak("Thynexa/AVIOR")
library(avior)

avior_init()     # 在项目中生成 validation/ 骨架（rationale 刻意留 TODO）
avior_scan()     # 从 renv.lock + 源码扫描写出 validation/inventory.yml
avior_assess()   # 写出 validation/scores.yml（需要安装 riskmetric）
avior_review()   # 决策桩 + 完整性 findings
# 完成 validation/decisions/*.yml，并添加 validation/tests/test-*.R。
avior_test()     # 写出与运行环境绑定的 validation/test-results.yml
gate <- avior_check()
stopifnot(gate$status == "pass")

bundle <- avior_bundle(zip = TRUE) # 生成英文 report.html + report.docx
directory_check <- avior_verify(bundle$path)
zip_check <- avior_verify(bundle$zip)
stopifnot(directory_check$status == "pass", zip_check$status == "pass")
directory_check$anchor             # 将此 SHA-256 归档到证据包外部
```

每个定向测试文件必须且只能包含一个 `# avior-package: <包名>` 头。英文是当前
已实现的报告 locale；选择中文占位 locale（`report.language: zh`）会在写入任何
部分或混合语言证据包之前 fail closed。

### 仓库结构

```text
AVIOR/
├── DESCRIPTION · NAMESPACE          # R 包元数据（R ≥ 4.1；Imports：cli、digest、jsonlite、yaml）
├── R/                               # 实现：配置、scan/assess/review/test/check、
│                                    #   bundle/verify、报告渲染、规范化序列化与 CLI
├── tests/testthat/                  # 回归测试套件；内置样例项目的 fixture 副本
├── man/                             # 函数文档
├── exec/avior                       # CLI 入口（Rscript）
├── inst/templates/ · inst/report/   # 配置/CI 模板与版本化报告 locale
├── .github/workflows/ci.yml         # Linux / macOS / Windows + R 4.1 矩阵
├── docs/                            # 项目文档
│   ├── README.md                    # 文档索引
│   ├── PRD.md                       # ⭐ 开发基线（受控文档，版本见其修订记录）
│   ├── r-regulatory-submission-research.md  # 方法论调研
│   ├── r-package-validation-strategy.md     # R 包验证策略分析
│   └── riskmetric-spike-results.md          # riskmetric 引擎 spike 结果
└── examples/
    └── minimal-project/             # M0 手工样例证据包（5 包，覆盖所有关键情形）
```

### 从哪里开始读

| 你是… | 先读 |
| --- | --- |
| 想了解产品全貌 | [`PRD.md`](./docs/PRD.md) —— 定位、公理、CLI、文件契约、里程碑一应俱全 |
| 想看证据包长什么样 | [`examples/minimal-project/`](./examples/minimal-project/) —— 一份可读的手工样例，附 QA/审计员阅读指引 |
| 想理解方法论出处 | [`r-regulatory-submission-research.md`](./docs/r-regulatory-submission-research.md) —— 监管背景与工具链对比 |

### 方法论锚点

- **R Validation Hub 白皮书**——风险评估四准则（用途/类型、维护、社区使用、测试）。
- **intended-for-use 聚焦原则**——深度验证只针对直接调用包；间接依赖只做版本管理。这是工作量收敛的关键。
- **ISPE GAMP 5（第二版）**——最小交付物：规范、风险评估、测试、追溯矩阵。

### 技术选型（摘自 PRD §7.3）

| 决策 | 选择 |
| --- | --- |
| 实现语言 | R 包为核心（用户是 R 团队，riskmetric/testthat/covr 都是 R） |
| 最低 R 版本 | R ≥ 4.1 |
| 配置 / 产物格式 | YAML + CSV（diff 友好，QA 无需工具即可阅读） |
| 报告引擎 | 内建零依赖渲染器 → 自包含 HTML + DOCX |
| 分发 | CRAN 优先 + GitHub Releases |
| 开源许可 | Apache-2.0 |

### 贡献

本 PRD 为开发基线。修订走 PR；任何与 §2 设计公理冲突的变更须先修订公理并记录理由。

### 许可

Apache-2.0——完整文本见 [`LICENSE.md`](./LICENSE.md)（见 PRD §7.3 已决事项 Q2）。
