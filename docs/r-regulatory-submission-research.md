# 合规的 R 语言监管递交：软硬件要求、监管指导思想、R 包验证流程比对与实施方案

> 版本：v1.0　编制日期：2026-07-06
> 范围：面向以 FDA 为主、兼顾 EMA/PMDA/NMPA 的药品/生物制品监管递交场景，讨论使用 R 语言进行统计分析与递交时的软件、硬件、计算环境与 R 包验证要求，比对现有市面上的 R 包验证流程，并给出"自建 vs 复用开源"的决策与落地实施方案。
>
> 说明：本报告基于公开监管文件、R Consortium/R Validation Hub/pharmaverse/Posit 等一手资料整合而成。文中对"强制要求"与"行业最佳实践"做了明确区分；对无法从一手来源确证的说法，以 ⚠️ 标注不确定性，供进一步核实。

---

## 目录

1. [执行摘要](#1-执行摘要)
2. [监管指导思想与法规背景](#2-监管指导思想与法规背景)
3. [软件要求](#3-软件要求)
4. [硬件与计算环境要求](#4-硬件与计算环境要求)
5. [R 包验证的四个层次](#5-r-包验证的四个层次)
6. [现有 R 包验证流程/工具比对](#6-现有-r-包验证流程工具比对)
7. [自建 vs 复用开源：决策分析](#7-自建-vs-复用开源决策分析)
8. [实施方案（落地路线图）](#8-实施方案落地路线图)
9. [风险登记与缓解](#9-风险登记与缓解)
10. [附录](#10-附录)

---

## 1. 执行摘要

**核心结论一句话：FDA 从不强制使用任何特定统计软件，R 语言完全可用于监管递交；合规责任由申办方承担，重点不在"证明 R 合法"，而在于"证明你的 R 环境与 R 包在你的场景下可靠、可复现、可追溯"。**

关键要点：

- **监管态度**：FDA 早在 2015 年 5 月 6 日发布《Statistical Software Clarifying Statement》，明确"不要求使用任何特定软件"，只要求软件在递交中被完整记录（含版本与 build）、且软件"可靠、有可用的软件测试程序文档"（该可靠性要求源自 ICH E9）。这是软件中立原则的成文依据。
- **R 已被 eCTD 正式接纳**：FDA《Study Data Technical Conformance Guide》（2025 年 8 月版）新增了 `.r`、`.rds` 等 R 相关文件扩展名到允许清单，扫清了 eCTD 文件格式白名单这一历史障碍。
- **已有大量成功先例**：R Consortium R Submissions Working Group 通过真实 eCTD 通道向 FDA 提交的 Pilot 1–4（静态 TLF、Shiny、ADaM 全流程、容器/WebAssembly）均获 FDA 接收/审阅并成功复现结果；Pilot 5（Dataset-JSON）在进行中。Novo Nordisk、J&J 等已有真实的 R/混合递交实践。
- **软件重点**：环境可复现（锁定 R 版本、`renv` 锁文件、Posit P3M 日期快照）、包版本可追溯（`sessionInfo()`）、数值可复现（RNG、locale、BLAS/LAPACK 层需固定）。
- **硬件重点**：无公开的 FDA/行业硬件规格；RAM 是主导因素；真正与合规相关的是**数值可复现性依赖 BLAS/LAPACK 实现与线程**，需在容器内固定并记录。计算环境须做 IQ/OQ/PQ 资质确认，遵循 GAMP 5 / 21 CFR Part 11 / EU Annex 11。
- **验证分层**：Base R（R Foundation 已提供合规文档，视为最低风险）→ 第三方 CRAN/Bioconductor 包（风险分级评估）→ 内部自研包/分析代码（完整 SDLC）→ 分析结果（双重编程/独立 QC）。四层各有不同要求，缺一不可。
- **自建 vs 复用**：**行业已明确收敛为"复用而非自建"**。建议复用开源风险评估工具链（`riskmetric`/`riskassessment` + `valtools`/`thevalidatoR`）+ 受控包仓库（Posit Package Manager 或商业化 Atorus OpenVal），把有限的"自建"投入集中在**你自己的 SOP、环境资质确认、和自研包/分析代码验证**上。从零自建一套 bespoke 验证框架无必要、增加审计面、且无同行在做。

---

## 2. 监管指导思想与法规背景

### 2.1 FDA《Statistical Software Clarifying Statement》（2015-05-06）——软件中立原则的基石

FDA 官方声明（fda.gov/media/161196）全文仅两段，核心原文：

> "FDA does not require use of any specific software for statistical analyses, and statistical software is not explicitly discussed in Title 21 of the Code of Federal Regulations [e.g., in 21 CFR part 11]. However, the software package(s) used for statistical analyses should be fully documented in the submission, including version and build identification.
>
> As noted in the FDA guidance, E9 Statistical Principles for Clinical Trials […], 'The computer software used for data management and statistical analysis should be reliable, and documentation of appropriate software testing procedures should be available.' Sponsors are encouraged to consult with FDA review teams… at an early stage…"

由此得出申办方的**三项确定性义务**：

1. **软件中立**：可用 SAS、R 或任何软件——不存在"必须用 SAS"的规定。
2. **完整记录**：递交中须完整记录所用软件包及**版本与 build 标识**。
3. **可靠 + 有测试文档**：软件须可靠，且**软件测试程序的文档须可提供**（此项来自 ICH E9，而非 FDA 自创）。

FDA 同时鼓励在开发早期就软件选择与 FDA 统计审评员沟通。

### 2.2 ICH E9——"可靠性 + 测试文档"要求的来源

ICH E9《临床试验统计学原则》原文："The computer software used for data management and statistical analysis should be reliable, and documentation of appropriate software testing procedures should be available." E9 本身软件中立、以结果为导向；E9(R1) 增补 estimand 框架，与软件无关。E9 已被 FDA、EMA、PMDA、Health Canada、NMPA 等 ICH 成员采用（NMPA 于 2020-05-12 实施）。

### 2.3 21 CFR Part 11（电子记录/电子签名）与 predicate rule 判定

**关键判定逻辑（predicate rule 测试）**：Part 11 的控制只有在满足两个条件时才附着——(a) 某底层 GxP 法规（predicate rule，如 Part 58 GLP、Part 211 cGMP、Part 312 IND、Part 314 NDA、Part 601 BLA、Part 820 器械 QSR）要求保存某记录或应用某签名，且 (b) 该记录/签名以电子方式处理。

FDA《Part 11 — Scope and Application》指出：

> "…a record that is not itself submitted, but is used in generating a submission, is not a part 11 record unless it is otherwise required to be maintained under a predicate rule and it is maintained in electronic format."

**对 R 的定位**（R Foundation 官方合规文档 R-FDA.pdf 的立场）：

> "R is not intended to create, maintain, modify or delete Part 11 relevant records but to perform calculations and draw graphics."

即：R 是"更大受控数据管理框架中的一个计算组件"。Part 11 的功能控制（审计追踪、访问控制、电子签名、记录留存）应由**宿主系统/操作系统/数据库**提供，而非由 R 本身提供。即使 Part 11 不直接适用，系统仍可能因 GxP 相关（如 211.68(b)、820.70(i)）而需要验证以保障数据完整性。Part 11 适用性的最终判定与文档化是**组织自身的责任**。

### 2.4 GAMP 5 与 CSV → CSA 的验证哲学演进

- **FDA 对"验证"的定义**（《General Principles of Software Validation》，2002）："Establishing documented evidence which provides a high degree of assurance that a specific process will consistently produce a product meeting its predetermined specifications and quality attributes."
- **GAMP 5**（ISPE）：业界事实上的计算机系统验证（CSV）框架，基于风险与软件类别（基础设施/配置/定制）。**GAMP 5 第二版于 2022 年 7 月发布**，纳入敏捷、云并向 CSA 方向对齐。
- **CSA（Computer Software Assurance）**：FDA 2022 年 9 月发布草案，2025 年 9 月 24 日在《联邦公报》**定稿**。其核心是把验证从"重文档的 CSV"转向"基于风险、最小负担、批判性思维"的四步法：(i) 定义预期用途；(ii) 评估失效风险（对患者/产品）；(iii) 确定相应保证活动；(iv) 建立并记录适当的记录。定稿取代了 2002 年《General Principles of Software Validation》第 6 节，并纳入 IaaS/PaaS/SaaS 与 AI 工具的表述。
  - **重要范围提示**：CSA 的正式范围是**医疗器械生产与质量体系软件（Part 820）**，并非直接管辖药品递交的统计分析软件。它对"R 用于递交"的意义在于**体现 FDA 的整体风险化验证哲学**——这与 R Validation Hub 的风险化方法同源——而非直接的管辖规则。
  - ⚠️ 某二手检索称"2026-02-03 有更新文件取代 2025-09 CSA 定稿"，**未能从 FDA 一手来源确证**，疑为检索摘要错误；以 **2025-09-24 联邦公报定稿**为当前权威状态，如需引用请再向 FDA 核实。

### 2.5 eCTD、ADRG 与《Study Data Technical Conformance Guide》——审评员如何复现结果

- FDA 要求标准化研究数据（列表用 CDISC **SDTM**、分析用 **ADaM**）+ 机器可读元数据（**define.xml**）+ **分析程序**，以便审评员独立复现结果。
- 分析程序按指南以 **ASCII 文本（.txt）或 PDF** 提交——正是因为**FDA 审评员不一定运行 SAS**（且整体软件中立）。R 脚本以 `.r`/`.txt` 提交；Pilot 已确认 eCTD 门户接受 `.r`。
- **2025 年 8 月的里程碑**：《Study Data Technical Conformance Guide》将 `.r`、`.rds` 等纳入允许扩展名清单——这是 2015 声明中"版本与 build 记录"要求在操作层面的落地前提。
- **ADRG（Analysis Data Reviewer's Guide）**：标准合规分析递交的推荐组成，为审评员提供分析数据集/术语的上下文，是分析数据集的"单点导航"。提交 ADRG **不免除**完整 define.xml 的要求。PHUSE 维护 ADRG 模板。
- **对 R 的额外负担（相对 SAS）**：**记录计算环境与包依赖**（R 版本、包版本/锁文件如 `renv`），使审评员能重建环境。一句业界流传的话："用 SAS 你在 ADRG 里写 'SAS 9.4' 即可；用 R 你可能打开了潘多拉魔盒。"

### 2.6 R Consortium R Submissions Working Group 系列 Pilot——FDA 接收 R 的最强实证

通过**真实 eCTD 通道**、用模拟 CDISC 数据（无真实药物）向 FDA CDER 递交的公开测试，材料均在 GitHub `RConsortium/` 开源：

| Pilot | 内容 | FDA 结果/时间 | 关键经验 |
|---|---|---|---|
| **1** | R 生成静态 TLF | 2021-11 递交，2022 年正面反馈 | 确认 R 可产出监管级 TLF |
| **2** | R Shiny 交互应用 | 2022-12 接收，2023-10 正式审阅 | 首个含 Shiny 组件的公开递交；用 `renv` 锁文件；FDA 提出交互过滤可能诱发 p-hacking → 从可过滤表中移除 p 值 |
| **3** | R 从 SDTM 生成 ADaM + define.xml + ADRG + TLF | 2023-08 首交，2024-04-19 重交，**2024-08-08 FDA 回函，成功接收并复现** | 验证 R 全数据流水线；也测试了以压缩方式提交专有 R 包；FDA 强调清晰记录计算环境/依赖/统计方法 |
| **4** | Shiny 的两种打包：Docker 容器 与 WebAssembly/webR | **2024-09-20 递交（首个含 WASM 组件的公开递交）** | **FDA 审评员更青睐 WebAssembly（浏览器即可运行，无需容器运行时/WSL）**；容器组件 2025 年夏递交，防火墙内运行可行性仍在讨论；Pilot 4 容器选用 **Podman（rootless，非 root）** 以满足审评员要求 |
| **5** | 用 CDISC **Dataset-JSON** 取代传统 XPT | 2025 秋递交，2026-01 初按 FDA 要求返工重交，预计 2026 春完成 | ⚠️ 尚未确认正式接收 |
| **6/2026** | 更多 ADaM/显示程序、AI 自动化、真实模拟 CDISC 数据 | 计划中（不向 FDA 递交） | 前瞻性，细节待定 |

此外，R Consortium 于 2024 年已向 **Swissmedic** 做过介绍，方法正在 FDA 之外被推广。

### 2.7 R Foundation 官方合规文档（R-FDA.pdf）

R Foundation 的《R: Regulatory Compliance and Validation Issues》（当前版本 2026-03-12）系统论证了 Base R 的合规性：

- 明确其**仅覆盖"Base R + Recommended Packages"**（R Foundation 官方发行、GPL 许可），**不覆盖第三方/CRAN 贡献包**（含 tidyverse、pharmaverse 等）——后者的验证是申办方责任，正是 R Validation Hub 要填补的空白。
- 论证 R Core 的 SDLC：Subversion 源码管理、发布分支、随发行附带的验证测试套件（`tests/` 目录，含源码与预期结果，可在安装时运行以获客观证据）、CRAN 历史版本存档、NEWS/变更日志、合格人员等。
- 开源的合规优势原文："as R is open source, the availability of R's source code provides for superior and thorough documentation of R's functionality and designed behavior and is open to inspection by all users."

### 2.8 其他监管机构（EMA / PMDA / NMPA）

- 总体：**无主要监管机构强制特定统计软件**，均遵循 ICH E9"可靠 + 测试文档"原则。R Foundation 指出 EMA、PMDA"深受 FDA 与 ICH 标准影响"。
- EMA/PMDA：与 FDA 一样接受 CDISC 标准数据、软件中立；PMDA 对 CDISC 数据标准要求尤严。
- NMPA：承诺采纳 ICH（含 E6 GCP、E9），原则上软件中立。
- ⚠️ **不确定性**：未找到 EMA/PMDA/NMPA 像 FDA 2015 声明那样**点名 R** 的正式文件；对 R 的接受是从"软件中立 + ICH E9"**推断**而来。若报告需要各机构对 R 的明确表态，应逐一向各机构指南核实。

---

## 3. 软件要求

> 监管只规定**结果**（数据完整性、可复现、可追溯，遵循 21 CFR Part 11 与 GxP predicate rule）。以下"如何做"绝大多数是**行业最佳实践**对这些结果要求的落地。

### 3.1 环境可复现性（锁定 R 与包版本）

- **锁定 R 版本本身**：记录并固定确切 R 版本（如 R 4.4.x）。这是基础，因为 RNG 与默认行为会跨版本变化（见 §3.3）。
- **`renv`**：项目级依赖隔离与锁定的事实标准，生成 `renv.lock`（记录每个包的版本与来源）。`renv::snapshot()`/`renv::restore()` 复现库；`renv::checkout(date=...)` 按日期重装。
- **Posit Public Package Manager（P3M，原 RSPM）日期快照**：免费公共镜像，提供**按日期冻结**的 CRAN/Bioconductor/PyPI 仓库 URL，可获取"某日期当时"的二进制包。当前推荐的日期冻结机制。
- **⚠️ MRAN 已停用**：Microsoft R Application Network 于 **2023 年 6 月底退役**。任何仍引用 MRAN 快照 URL 的 SOP/验证文档均已过期，必须迁移到 P3M（Posit 已协助保留历史快照）。
- **`checkpoint` 包**：遗留方案（原指向 MRAN），可重指向 P3M，但新项目应优先 `renv` + P3M。
- **可追溯性工具**：在递交产物与 ADRG 中捕获 `sessionInfo()` / `devtools::session_info()`，用以核验实际加载的包与已批准清单一致。

### 3.2 包管理与验证分层

见 §5（四层验证）与 §6（工具比对）。软件层面须建立**受控包仓库**：仅收录通过评估/验证的包版本，通过 Posit Package Manager 绑定到 Workbench/Connect，使用户只能安装已批准版本。

### 3.3 数值可复现性（R 特有的技术清单）

合规文档中应记录的最佳实践控制：

- **`set.seed()` + `RNGkind()`**：始终同时设定种子与 RNG 类型；用 **`RNGversion("x.y.z")`** 复现旧版 R 的 RNG 结果。
- **⚠️ R 3.6.0 抽样变更（需重点标注）**：`sample()` 默认算法在 **R 3.6.0** 改变（旧法在大总体上非均匀）。3.6.0 之前代码在 ≥3.6.0 下**不可复现**，除非调用 `RNGversion("3.5.0")`。这是具体的跨版本复现陷阱。
- **`stringsAsFactors` 默认在 R 4.0.0 改为 `FALSE`**：依赖旧默认（字符自动转因子）的旧代码在 ≥4.0 下行为不同——又一个必须锁定版本的理由。
- **locale 相关排序**：因子层级/排序依赖系统 locale；在环境中固定 locale（如 `LC_COLLATE=C`）以获确定性排序。
- **浮点/BLAS**：见 §4.4——数值可复现性依赖 BLAS/LAPACK 实现与线程，须固定。
- **`sessionInfo()`**：作为环境指纹捕获并归档（R 版本、OS、locale、加载包及版本，部分构建含 BLAS）。

---

## 4. 硬件与计算环境要求

> **总体判断**：无公开的 FDA/行业硬件规格；应按工作负载定容量。真正与合规相关的硬件问题是**数值可复现性依赖 BLAS/LAPACK 层**，以及计算环境的 **IQ/OQ/PQ 资质确认**。

### 4.1 硬件容量（按负载定容）

- **RAM 是主导因素**：R 内存密集、数据驻留 RAM，ADaM/TLF 工作通常受内存约束而非 CPU 约束——尽量给足 RAM。
- **CPU**：Base R 单线程，多核仅对显式并行的包或多并发会话有益；TLF 生成一般非计算密集。
- **存储**：数据集需求适中；需为包库、容器镜像、审计追踪/日志留存规划空间。
- **可参照的公开基准（Posit Workbench 定容）**：最低 2 核 / 4 GB / 100 GB 盘；推荐 4+ 核；主要按"并发会话数 × 平均会话内存"定容，可下沉到 Kubernetes/Slurm。

### 4.2 操作系统

- **Linux 是可复现/受控环境的实际标准**（Rocker `r-ver` 基于 Ubuntu LTS）。跨平台（Windows/macOS↔Linux）复现是已知弱点。
- **⚠️ FDA 审评员的 R 运行环境未公开规定**：FDA 历史上以 SAS/Windows 为主；无权威公开声明称审评员以标准化 OS 原生运行 R。**这正是 Pilot 4 探索 webR（浏览器、与 OS 无关）与容器的原因**——消除对审评员 OS 的依赖。
- **跨平台复现问题**：locale 排序、路径/换行差异、平台特定二进制构建，意味着一个 OS 上生成的锁文件未必能在另一 OS 上完全一致还原。实务建议（依 ADRG 附录模式）：让审评员在其本机安装后**本地生成 `renv.lock`**，而非跨 OS 搬运不可移植的锁文件。

### 4.3 容器化

- **Docker + Rocker 项目**是主流。用 **`rocker/r-ver`**（而非 `r-base`）：为复现而建，从源码装固定 R 版本于 Ubuntu LTS 基础上。
- **⚠️ 验证文档必须注意的关键点**：版本 *tag*（如 `rocker/r-ver:4.4.0`）只固定 R。Rocker 镜像会**定期重建**，非 R 系统库会随安全更新漂移，且 tag 的 CRAN 镜像**不会**自动按日期锁定。真正冻结环境需**三层同时锁定**：按 **SHA256 镜像摘要**锁定（`rocker/r-ver@sha256:...`）+ 锁定 CRAN 快照日期（P3M）+ 使用 `renv`。
- **R Consortium Pilot 4（FDA 的参考实现）**：
  - **WebAssembly/webR**：Shiny 编译为完全在审评员浏览器内运行——无需安装。2024-09-20 经 eCTD 门户递交（首个含 WASM 组件）。约束：仅限 CRAN 包（舍弃了 `cowplot`、`teal` 等，用替代品垫片）；~100MB+ 浏览器加载是痛点。
  - **容器组件**：2025 夏经 eCTD 递交；**防火墙内运行**可行性仍在讨论。**选用 Podman 而非 Docker**，因其 rootless（非 root）运行——FDA 审评员的明确要求。
- **Apptainer/Singularity（受控 HPC 场景）**：在多用户 HPC/受控集群中更受青睐，因 rootless、无常驻守护进程、无提权（容器内保留用户身份），审计/安全姿态优于基于守护进程的 Docker；支持镜像加密签名（软件供应链信任）；可运行 OCI/Docker 镜像。适合 IT 安全禁用 Docker 守护进程之处。
- **必需 vs 最佳实践**：无 FDA 规则要求容器。容器是复现/可移植的最佳实践，Pilot 表明 FDA 在**测试而非强制**。若审评员或你的受控基础设施禁用 root，则 rootless（Podman/Apptainer）重要。

### 4.4 数值可复现性依赖硬件——经 BLAS/LAPACK 层（合规报告的关键技术点）

- 浮点加法**非结合**，运算顺序改变会改变低位结果。不同 **BLAS/LAPACK** 实现（参考/内部 BLAS vs **OpenBLAS** vs Intel MKL vs Apple Accelerate）、不同 BLAS *版本*、以及多线程执行，都可能对同一代码产生数值不同的结果。
- **R 自带内部参考 BLAS** 正是为稳定/复现；换用优化多线程 BLAS 是以复现换速度。已有真实案例：切换 OpenBLAS 版本导致模型预测改变。
- **受控环境的缓解**：(a) 将 BLAS/LAPACK 实现**及版本**作为环境规格的一部分固定——容器有助于此；(b) 考虑单线程 BLAS 以求确定性；(c) Intel MKL 提供 **CNR（Conditional Numerical Reproducibility）** 以牺牲部分性能换取确定顺序。
- **实务结论**：对典型 ADaM/TLF（描述统计、计数、标准模型），差异通常小于报告精度；但**数值可复现性不跨硬件/BLAS 自动保证**——应在容器内固定 BLAS 层并记录之。此为最佳实践，非 FDA 明文要求。

### 4.5 计算环境的 IQ/OQ/PQ 资质确认

- **IQ（安装确认）**：环境按规格安装的书面证据——正确的 R 版本、OS、系统库、BLAS、包仓库、容器摘要。
- **OQ（运行确认）**：在预期范围内正确运行的证据——如产出已知输出的测试脚本、包精度检查。
- **PQ（性能确认）**：在真实生产负载/数据下可靠运行的证据。
- **重要范围提示**：**R Validation Hub 白皮书明确将"基础设施验证"列为范围之外**——它覆盖*包*精度/软件验证，并*假定*已有一个受控基础设施。因此计算环境的 IQ/OQ/PQ 是申办方/IT 在其 QMS 下的责任，受 GAMP 5 / 21 CFR Part 11 / Annex 11 管辖，而非由 R Validation Hub 管辖。**不要把白皮书当作基础设施资质确认的依据来引用。**

### 4.6 基础设施资质（GxP 云、IaC、审计追踪、访问/变更控制）

- **责任共担模型**：AWS/Azure/GCP/Oracle 发布 GxP 资质指南并持有 ISO 27001 / SOC 2 / HITRUST 认证，但**云认证不自动满足 GxP**——客户必须在其上实施 IQ/OQ/PQ 与控制。
- **基础设施即代码（IaC）**（Terraform/CloudFormation）：实现自动化、可重复、可审计的置备与**自动化 IQ**；据报可为受控云负载减少约 30–40% 资质确认时间。
- **预资质 GxP 云供应商**（Validated Cloud、ByteGrid、GxP-Cloud 等）：自带 QMS 并提供审计就绪的 IQ/OQ 文档，适合想缩短基础设施资质的团队。
- **21 CFR Part 11 / EU Annex 11 的真实必需要素**：审计追踪（谁/做了什么/何时，不可篡改）、访问控制（认证、最小权限、基于角色）、变更控制（有记录、经批准，触发再资质）、数据完整性（ALCOA+）。这些是真正的监管要求，具体工具由你选择。

---

## 5. R 包验证的四个层次

不同层次要求不同，缺一不可。前三层验证"工具/包"，第四层验证"结果"。

| 层次 | 对象 | 验证要求 | 谁负责 | 可否外包/复用 |
|---|---|---|---|---|
| **(a) Base R + Recommended 包** | R 解释器与核心包 | **最低风险**。R Foundation R-FDA.pdf 已提供合规论证；仍需在*你的*环境做 IQ/OQ/PQ，但无需重验解释器内部 | R Foundation（论证）+ 你（环境资质） | 直接复用 R Foundation 文档 |
| **(b) 第三方 CRAN/Bioconductor 包** | 社区贡献包 | **风险分级评估**。CRAN check 通过只是地板不是验证；需按包做风险评估（`riskmetric`/`riskassessment`）+ 对高风险/高频包补充测试 | 你（可借助共享仓库） | 高度可复用（OpenVal/pharmaverse/共享仓库） |
| **(c) 内部自研包/分析代码** | 你写的包与脚本 | **最严——完整 SDLC**：需求、单元测试、覆盖率、CI/CD、同行评审、版本化规格与可追溯性 | 你（不可外包） | 复用*工具*（valtools/thevalidatoR），但工作必须自做 |
| **(d) 分析结果（TLF/数据集）** | 具体研究产出 | **独立 QC / 双重编程**：由第二名程序员独立复算并电子比对；验证的是"结果"而非"工具" | 你/CRO | 复用流程范式，工作自做 |

**四层的哲学区分**：(a)(b)(c) 验证的是"用来算的工具是否可信"，(d) 验证的是"这次算出来的结果对不对"。二者正交，成熟受控递交**四层叠加**。双重编程据单一综述报告有 ~92–98% 错误检出率、成本约为主编程的 1.6–2.0×（⚠️ 单来源，指示性数字）；现代实践趋向"双重编程 + 自动化验证（单元测试/CI/风险评估）"的混合 QC 以降本。

---

## 6. 现有 R 包验证流程/工具比对

市面工具分为**四种哲学上不同、但互补而非竞争**的路线：风险化包评估、验证即包、环境/基础设施验证、独立 QC。

### 6.1 R Validation Hub 白皮书——风险化方法（框架）

跨行业倡议（2018 年源自 PSI 的 AIMS SIG，现隶属 PHUSE、与 R Consortium ISC 关联，~60–100 家机构）。白皮书《A Risk-based Approach for Assessing R Package Accuracy within a Validated Infrastructure》（2020 初）是验证**CRAN 贡献包**的参考框架。

- **包分级**：Base/Recommended（最低风险）；Contributed/CRAN（社区构建，CRAN check 不保证精度）；部署内功能分类——"Intended for Use"（用户直接加载/调用）vs "Imports"（传递依赖，按支撑基础设施对待，评估精力集中在前者）。
- **四个风险维度**：①**用途**（统计/ML 算法类风险更高，数据整理/IO/可视化类更低）；②**维护良好实践**（vignette、网站、NEWS、bug 跟踪、公开源码、发布节奏、代码规模、作者声誉、许可）；③**社区使用**（成熟度、反向依赖、下载量——更多社区曝光≈更多真实世界的临时测试）；④**测试**（有无单元测试及覆盖率）。
- **评分哲学**：**刻意不用单一不透明数字**。每条准则由合格评审者（统计包由统计学家，其余由资深 R 程序员）评估、同行复核、逐包成文；度量*辅助*主观专业判断。
- **明确仍需**（白皮书自述）：逐包风险报告；**无论风险高低都要做系统资质测试（IQ/OQ/PQ）**；高风险包额外测试（`testthat`）；遵循组织内部 QA SOP；环境可复现与可追溯。
- **关键局限**：白皮书**不覆盖基础设施验证、版本锁定、Docker、RSPM、IQ/OQ**——它假定受控基础设施已存在。

### 6.2 `riskmetric`——度量引擎

pharmaR 组织维护。**状态：仅维护（maintenance-only）**，活跃开发已转向 `val.meter`。

- **工作流**：`pkg_ref()`（定位包）→ `pkg_assess()`（跑评估）→ `pkg_score()`（转分）→ `summarize()`（加权汇总）。
- **度量**（`assess_*`）：维护/良好实践（has_maintainer、has_source_control、has_website、has_news、news_current、has_bug_reports_url、last_30_bugs_status、license、size_codebase）；文档（has_vignettes、has_examples、export_help）；测试/检查（covr_coverage、r_cmd_check、remote_checks、exported_namespace）；社区使用（downloads_1yr、reverse_dependencies、dependencies）。
- **评分**：每项归一化到 **0–1**（1 好 0 差），**风险是度量分的反面**；`summarize()` 按可配置权重合成。
- **⚠️ 关键局限**：`riskmetric` 衡量包的**成熟度/维护/测试覆盖**，**不衡量计算或统计正确性**。高分不代表数学正确。

### 6.3 `riskassessment`——组织级签核 Shiny 应用

pharmaR 项目，ShinyConf 2023"最佳应用"。把 `riskmetric` 包装成组织规模可用的评估与签核：定义待评包清单→跑 `riskmetric`→存本地数据库；追踪风险分随时间变化；组织级度量权重 + 自动决策规则（背书/禁用）；包级评论/对话记录（支撑人工判断层）；评审/决策工作流（指派评审、记录决策）→ 形成可审计的签核记录，适合建"已验证包清单"。

### 6.4 `valtools`——验证即包

PHUSE R Package Validation Framework 工作组（Ellis Hughes 维护，MIT）。**哲学**：验证产物**内建于包中**，随包安装后仍存于 `inst/validation/`。

- **工作流**：`vt_use_validation()`/`vt_use_change_log()` 建基础设施；`vt_use_req()`/`vt_use_test_case()`/`vt_use_test_code()`/`vt_use_report()` 建立"需求→测试用例→测试代码"的**可追溯链**；配置文件记录用户与角色（`vt_scrape_sig_table()`）支持多方签名/批准；`vt_scrape_coverage_matrix()` 生成"测试用例↔需求"**追溯矩阵**；`vt_validate_source/build/install/installed_package()` 渲染签名的**验证报告**（规格、风险评估、测试、追溯矩阵，按 CSV/计算机化系统生命周期阶段组织）。

### 6.5 `thevalidatoR`——自动化验证报告 GitHub Action

**⚠️ 归属更正**：由 **Roche 的 `insightsengineering` 组织**维护，**非** Jumping Rivers（Jumping Rivers 另有其"Litmusverse"工具集）。MIT，活跃。

- 复合 GitHub Action，跑在 Docker `rocker/verse` 镜像里：对包仓库依次运行 `R CMD check` → `covr::package_coverage()` 覆盖率 → `covtracer` 文档↔测试追溯 → 汇编 **PDF 验证报告**（元数据、依赖、测试结果、覆盖率、检查发现、测试到文档追溯），通常附到 GitHub release。
- **与风险评估的区别**：它验证包*自身*的技术健康（覆盖率、安装成功、检查、追溯），而非给第三方包的可信度打分。是"验证即包"的 CI 自动化。

### 6.6 pharmaverse / `admiral`——已高度工程化的开源临床包

Roche/Genentech、GSK、J&J/Janssen、Atorus 共建的开源生态（SDTM→ADaM→TLG→递交），旗舰 `admiral`（用 R 生成 ADaM）。测试/验证实践：`testthat` 第 3 版（严格）；每个新函数须有典型/边界/错误测试，数据集比对用 `expect_dfs_equal()`；测试标题嵌函数名+测试 ID 以追溯，测试描述编入包验证报告；**CI 门禁：任一测试失败则拒绝 PR**；开发标准形式化于 `admiraldev`。**注意**：pharmaverse 包因设计而 `riskmetric` 分高，但 pharmaverse **本身不认证监管验证**——申办方仍需在其环境验证。

### 6.7 Posit Package Manager / P3M——环境/快照验证

面向**环境**而非单包。PPM（商业：受控 CRAN/Bioc/PyPI 仓库、漏洞扫描与阻断、气隙运行、防火墙内私有/自定义仓库、日期快照）；P3M（免费公共快照服务）。**日期快照** = 某日期 CRAN 的精确副本；组织维护单独的"已验证"仓库（仅通过评估的包），绑定 Workbench/Connect，使用户只能装批准版本。**哲学**：这是基础设施验证 / IQ-OQ-PQ 使能——它不判断包*正确*与否，只保证你跑的是*受控、可复现*的版本集合，与风险评估**互补**。

### 6.8 `covr` / `testthat` / CI——测试基座

`testthat`（事实标准单测框架）、`covr`（覆盖率，含编译 C/C++/Fortran；`covr_coverage` 是 `riskmetric` 的直接度量、`thevalidatoR` 的一节）、GitHub Actions（`r-lib/actions`；受控用途下 CI 强制"测试通过才合并"、发布时生成验证产物）。它们是**证据供给方**（覆盖率、通过/失败），非验证框架本身。

### 6.9 商业化：Atorus OpenVal（"验证即产品"）

订阅式**已验证 R 包仓库** + 可复现环境 + 验证证据，客户可对照 FDA 电子记录指南、GAMP 5、21 CFR Part 11 / EU Annex 11 审计。也上架 AWS Marketplace。⚠️ 各页包数不一致（~200 / ~400 / 580），"<$500/包"是营销对比而非订阅报价，视为约数。

### 6.10 双重编程（源自 SAS 的独立 QC）

独立重实现分析数据集/TLF 并电子比对，长期是 SAS 生物统计的"金标准"；碳移植到 R 后，图形可视觉比对 SAS 对应图；现代趋向与自动化验证混合。**概念区分**：双重编程验证**分析输出/研究结果**；`riskmetric`/`valtools`/pharmaverse 验证**工具/包**。二者在受控递交中并存。

### 6.11 并列比较表

| 工具 | 路线 | 验证什么 | 维护方 | 许可 | 成熟度 | 产出 |
|---|---|---|---|---|---|---|
| R Validation Hub 白皮书 | 风险化（框架） | 第三方包可信度 | R Validation Hub | 文档 CC | 成熟、广引 | 方法论 |
| `riskmetric` | 风险化（引擎） | 包良好实践/社区/测试度量 | pharmaR | MIT | 成熟、**仅维护**（→val.meter） | 0–1 分、加权合成 |
| `riskassessment` | 风险化（组织流程） | 组织级包清单与签核 | pharmaR | MIT | 成熟 | 分数库、决策、备注 |
| `val.meter` | 风险化（下一代） | 受控用途的包启发式 | pharmaR | 开源 | **新兴/开发中** | 包启发式 |
| `valtools` | 验证即包 | 需求↔测试追溯 + 签名报告 | PHUSE WG | MIT | 成熟 | 验证报告、追溯矩阵 |
| `thevalidatoR` | 验证即包（CI） | 包 check/覆盖率/追溯 | Roche insightsengineering | MIT | 活跃 | PDF 验证报告 |
| pharmaverse / admiral | 软件化开发+测试 | 包正确性（严格 SDLC/测试） | pharmaverse 社区 | Apache/MIT | 成熟、已用于递交 | 已测试包、开发标准 |
| Posit PPM / P3M | 环境验证 | 可复现、受控版本 | Posit | 商业/免费 | 成熟 | 快照、受控已验证仓库 |
| `covr`/`testthat`/CI | 测试基座 | 覆盖率与通过/失败证据 | r-lib/Posit | MIT | 成熟 | 覆盖率、测试结果 |
| Atorus OpenVal | 环境+包（商业） | 已验证包仓库+证据 | Atorus | 商业订阅 | 成熟 | 已验证包+文档 |
| 双重编程 | 独立 QC（SAS 传承） | 分析结果 | 申办方/CRO 实践 | — | 成熟 | 比对/调和的结果 |

---

## 7. 自建 vs 复用开源：决策分析

### 7.1 结论

**复用为主、混合分层——不要从零自建。**行业已明确收敛为"复用"：无一家大药企今天从零构建 bespoke R 验证框架；均采用共享开源工具链（`riskmetric`/`riskassessment` + `valtools`/`thevalidatoR`）并在其上叠加自己的 SOP、受控环境与测试。剩下不可避免的"自建"仅限窄范围：**你的 SOP、你的环境资质确认（IQ/OQ/PQ）、以及你自研包/分析代码的验证。**

### 7.2 理由

- **一手佐证**：R Validation Hub、pharmaverse 皆为大药企（Roche/GSK/J&J/Atorus 等）协作产物，正是为了消除全行业重复劳动。咨询界（Appsilon、Atorus）共识为**混合**——你有控制权处（内部包）用软件化验证，第三方包用风险化复用。
- **自建的代价**：重复已有共享工具链、增大审计面、无同行参照、维护负担高（每次版本升级都要重跑）。
- **风险评估分数不足以单独交差**：白皮书自述风险分不够，仍需逐包报告 + 无论风险的 IQ/OQ/PQ + 高风险包补测 + 内部 SOP + 环境可复现追溯。`riskmetric` 也不衡量正确性。
- **买 vs 自建包仓库**：内部验证数百个 CRAN 包是庞大且反复的工作；商业订阅（OpenVal）在客户间摊薄成本。

### 7.3 分层推荐策略

| 层 | 推荐做法 | 复用的开源/商业 |
|---|---|---|
| Base R | 直接引用 R Foundation R-FDA.pdf 作为低风险论证，纳入你的验证包 | R-FDA.pdf |
| 第三方 CRAN 包 | 建受控仓库；用 `riskassessment`（内含 `riskmetric`）做逐包风险评估与签核；高风险包补 `testthat` 测试；或订阅 OpenVal / 直接采用 pharmaverse 已工程化包 | riskassessment/riskmetric、Posit PPM、OpenVal、pharmaverse |
| 内部自研包/代码 | 用 `valtools` 搭建"验证即包"骨架 + `thevalidatoR` 在 CI 自动出验证报告；完整 SDLC | valtools、thevalidatoR、covr、testthat、GitHub Actions |
| 分析结果 | 保留双重编程/独立 QC（对关键/推断性分析），与自动化测试混合 | 内部 SOP + CI |
| 环境 | 容器（Rocker/Podman，按摘要锁定）+ P3M 日期快照 + `renv`；IQ/OQ/PQ 资质确认 | Rocker、Posit PPM/P3M、renv、IaC |

---

## 8. 实施方案（落地路线图）

分四阶段，约 6–9 个月达到"可支撑一次真实 R 递交"的成熟度。

### 阶段 0：治理与范围（第 1 月）

- 成立跨职能小组：生物统计、统计编程、IT/基础设施、QA/合规、（可选）监管事务。
- 确定 Part 11 适用性判定（predicate rule 测试）并成文；界定哪些系统 GxP 相关。
- 起草**验证主计划（VMP）**与总体 SOP 框架。
- 决策：包仓库自建 vs 订阅（OpenVal）；平台自管（开源 Rocker+P3M）vs Posit Team 商业平台。

### 阶段 1：受控计算环境（第 2–3 月）

- **环境构建**：以 `rocker/r-ver`（按 SHA256 摘要锁定）为基，固定 R 版本、OS、系统库、**BLAS/LAPACK 实现与版本**（建议单线程或记录 CNR 设置）、locale（`LC_COLLATE=C`）。
- **依赖管理**：`renv` + Posit P3M 日期快照三层锁定；建立受控包仓库（PPM 或等价），用户仅能装批准版本。
- **基础设施资质**：编写并执行 **IQ/OQ/PQ** 协议（含 RTM 追溯矩阵、Part 11 审计追踪与访问控制测试用例、变更控制流程）；若上云，用 IaC 实现自动化 IQ，并保留责任共担文档。
- **产出**：环境规格文档、IQ/OQ/PQ 已签执行记录、偏差日志、资质报告、容器镜像与摘要清单。

### 阶段 2：R 包验证流程（第 3–5 月，可与阶段 1 并行）

- 部署 **`riskassessment`**（内含 `riskmetric`）作为组织级评估与签核工具，建立"已验证包清单"数据库；配置组织级度量权重与自动决策规则。
- 制定**风险分级 SOP**：按四维度（用途/维护/社区/测试）评估 Intended-for-Use 包；高风险包用 `testthat` 补充测试并做追溯。
- 内部自研包：用 `valtools` 建"验证即包"骨架（需求→用例→代码→报告 + 签名表），`thevalidatoR` 在 CI 自动出 PDF 验证报告；强制"测试通过才合并"。
- 直接采用 pharmaverse（`admiral` 等）以减少自研 ADaM 代码量。
- **产出**：逐包风险报告、已验证包清单、内部包验证报告、覆盖率报告、SOP 集。

### 阶段 3：递交流水线与预演（第 5–7 月）

- 搭建 SDTM→ADaM→define.xml→TLF 的 R 流水线（pharmaverse + xportr 产出 XPT，关注 Pilot 5 的 Dataset-JSON 进展）。
- 编写 **ADRG**，重点记录**计算环境与包依赖**（R 版本、`renv.lock`、`sessionInfo()`、容器摘要、BLAS 设置）；分析程序以 `.r`/`.txt` 提交。
- 对关键/推断性分析实施**双重编程/独立 QC**。
- **递交格式预演**：参照 RConsortium Pilot 1–4 的公开范例组织 eCTD 包；如做交互组件，优先 webR/WASM（FDA 审评员偏好），去除可过滤表的 p 值以避 p-hacking 质疑。
- （强烈建议）就软件选择与 FDA 统计审评团队**早期沟通**（2015 声明鼓励）。

### 阶段 4：持续运行与再验证（第 7 月起）

- 变更控制：R/包/环境任何变更触发影响评估与必要的再资质/再验证（`vt_validate_installed_package()` 可在环境变更后重验）。
- 定期重跑风险评估（版本升级时）；维护审计追踪与文档的"实时（而非事后补）"生成——事后补文档是 FDA 483 最严重的发现之一。
- 迁移检查：清除任何遗留 **MRAN** 引用，改用 P3M。
- 关注 `riskmetric`→`val.meter` 迁移与 R Consortium Pilot 5/6、CSA 定稿等动态。

### 8.1 建议的 SOP 清单（最小集）

1. 计算环境资质确认（IQ/OQ/PQ）SOP
2. R 包风险评估与签核 SOP（含四维度评分与阈值）
3. 内部 R 包/分析代码 SDLC 与验证 SOP
4. 依赖与版本管理 SOP（renv + P3M 快照 + 容器摘要）
5. 变更控制与再验证 SOP
6. 分析结果独立 QC/双重编程 SOP
7. 递交文档（ADRG/程序/环境说明）SOP
8. Part 11 适用性判定与审计追踪/访问控制 SOP

### 8.2 工具选型汇总（推荐默认）

- 环境：Rocker `r-ver`（摘要锁定）/ 或 Posit Workbench；Podman（rootless）；`renv` + Posit P3M
- 包评估：`riskassessment` + `riskmetric`（或 `val.meter` 就绪后迁移）
- 包仓库：Posit Package Manager（自管）或 Atorus OpenVal（订阅）
- 内部包验证：`valtools` + `thevalidatoR` + `covr` + `testthat` + GitHub Actions
- 临床流水线：pharmaverse（`admiral`、`metacore`、`xportr` 等）
- 递交参考：RConsortium `submissions-pilot1..4` 公开仓库 + PHUSE ADRG 模板

---

## 9. 风险登记与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 环境不可复现（跨 OS/BLAS 漂移） | 审评员无法复现结果 | 三层锁定（容器摘要 + P3M 日期 + renv）；固定并记录 BLAS/locale；必要时让审评员本地生成锁文件 |
| 事后补验证/资质文档 | FDA 483 最严重发现、数据完整性问题 | 文档"实时"生成；先定验收标准后执行测试；保留签名执行记录 |
| 仅靠 `riskmetric` 分数交差 | 不满足监管期望（分数≠正确性） | 叠加逐包报告 + IQ/OQ/PQ + 高风险补测 + SOP + 双重编程 |
| 引用过期机制（MRAN） | SOP 失效、不可复现 | 迁移 P3M；审查现有 SOP |
| 交互组件诱发 p-hacking 质疑 | 审评顾虑 | 从可过滤表移除推断统计；仅对非推断可视化保留过滤 |
| 依赖包被弃维 | 长期监管参照风险 | 优先 CRAN/pharmaverse 高维护包；受控仓库锁版本；记录 last_30_bugs 等维护度量 |
| 容器在 FDA 防火墙内运行受限 | 交互递交受阻 | 优先 webR/WASM 路线（Pilot 4 显示审评员偏好）；容器选 rootless（Podman/Apptainer） |
| ⚠️ 各法规状态时效 | 引用过时 | 关键结论（CSA 定稿状态、Pilot 5、EMA/PMDA/NMPA 对 R 的表态）在正式引用前向一手来源复核 |

---

## 10. 附录

### 10.1 强制要求 vs 最佳实践 速查

| 事项 | 状态 |
|---|---|
| 可复现、可追溯的分析；数据完整性；审计追踪；访问与变更控制（Part 11/Annex 11/GxP） | **强制（结果层）** |
| R 已被 eCTD 允许（2025-08 Conformance Guide） | 监管事实 |
| 软件版本/build 完整记录、软件可靠 + 测试文档可提供 | **强制**（2015 声明 + ICH E9） |
| 计算环境 IQ/OQ/PQ | **由申办方 QMS 强制**（GAMP 5）；FDA 不规定如何做 |
| `renv` + P3M 日期快照 + 锁定 R 版本 | 最佳实践（主流标准） |
| Docker/Rocker 或 Podman/Apptainer 容器、按摘要锁定 | 最佳实践；FDA 在试点非强制 |
| 固定 BLAS/LAPACK 以求数值确定性 | 最佳实践（技术上重要） |
| `set.seed`/`RNGkind`/`RNGversion`、固定 locale、`sessionInfo()` 捕获 | 最佳实践（强烈推荐） |
| 特定硬件（CPU/RAM/存储）规格 | **无公开 FDA/行业规格**——按负载定容 |

### 10.2 已标注的不确定性（正式引用前请核实）

1. FDA 审评员实际的 R 运行环境/OS 未公开规定；webR/容器试点正是为绕开此依赖；容器在防火墙内运行可行性截至 2025 夏仍在讨论。
2. 无 R ADaM/TLF 流水线的权威硬件要求；Posit Workbench 定容是最佳可得替代参照。
3. R Validation Hub 白皮书**不覆盖**基础设施验证/版本锁定/Docker/RSPM/IQ-OQ——不要据此引用基础设施资质。
4. ⚠️ 传闻的"2026-02-03 取代 CSA 定稿的文件"未从 FDA 一手确证；以 2025-09-24 联邦公报定稿为准。
5. 未发现 EMA/PMDA/NMPA **点名 R** 的正式文件；对 R 的接受由"软件中立 + ICH E9"推断。
6. 未确证存在 FDA 自有的"R 包仓库"；`pharmaR`/R Validation Hub 是行业/R Consortium 努力（有监管方参与），非 FDA 所有。
7. `riskmetric` 已仅维护，`val.meter` 为继任但尚早期，正式采用前请核实其成熟度/CRAN 发布状态。
8. OpenVal 包数/价格各页不一致；双重编程效果数字为单来源指示性数据。

### 10.3 关键一手来源

**FDA / 法规**
- Statistical Software Clarifying Statement (2015): https://www.fda.gov/media/161196/download
- Study Data Technical Conformance Guide: https://www.fda.gov/media/88173/download
- Part 11 — Scope and Application: https://www.fda.gov/media/75414/download
- 21 CFR Part 11 (eCFR): https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11
- CSA 定稿 (2025-09-24 联邦公报): https://www.federalregister.gov/documents/2025/09/24/2025-18468/computer-software-assurance-for-production-and-quality-system-software-guidance-for-industry-and
- CSA 指南 PDF: https://www.fda.gov/media/188844/download

**R Foundation / ICH / 其他机构**
- R: Regulatory Compliance and Validation Issues (R-FDA.pdf): https://www.r-project.org/doc/R-FDA.pdf
- EMA ICH E9: https://www.ema.europa.eu/en/ich-e9-statistical-principles-clinical-trials-scientific-guideline
- ICH efficacy guidelines: https://www.ich.org/page/efficacy-guidelines

**R Consortium Pilots / pharmaverse**
- R Submissions WG 2026 计划: https://r-consortium.org/posts/submissions-wg-2026/
- Pilot 3 FDA 接收: https://r-consortium.org/posts/news-from-r-submissions-working-group-pilot-3/
- Pilot 4 递交: https://r-consortium.org/posts/using-r-to-submit-research-to-the-fda-pilot-4-successfully-submitted/
- 容器/WebAssembly 说明: https://pharmaverse.github.io/blog/posts/2024-02-01_containers_webassembly_submission/containers_and_webassembly_submissions.html
- pharmaverse: https://pharmaverse.org/ · admiral: https://github.com/pharmaverse/admiral
- eCTD 对 R 文件扩展支持: https://r-consortium.org/posts/expanded-fda-ectd-file-format-support-for-r-packages/

**验证工具**
- R Validation Hub: https://pharmar.org/ · 白皮书: https://pharmar.org/white-paper/ · 风险: https://pharmar.org/risk/
- riskmetric: https://github.com/pharmaR/riskmetric · https://pharmar.github.io/riskmetric/
- riskassessment: https://github.com/pharmaR/riskassessment
- val.meter: https://github.com/pharmaR/val.meter
- valtools: https://github.com/phuse-org/valtools · https://phuse-org.github.io/valtools/
- thevalidatoR: https://github.com/insightsengineering/thevalidatoR
- covr: https://covr.r-lib.org/ · r-lib actions: https://github.com/r-lib/actions

**环境 / 平台 / 商业**
- renv: https://rstudio.github.io/renv/ · MRAN→P3M 迁移: https://posit.co/blog/migrating-from-mran-to-posit-package-manager
- Posit Package Manager: https://posit.co/products/enterprise/package-manager · P3M: https://posit.co/products/enterprise/public-package-manager
- Rocker r-ver: https://rocker-project.org/images/versioned/r-ver.html · 复现性: https://rocker-project.org/use/reproducibility.html
- Apptainer: https://apptainer.org/
- Posit pharma 方案: https://posit.co/solutions/pharma · 验证环境: https://solutions.posit.co/envs-pkgs/environments/validated/
- Atorus OpenVal: https://www.atorusresearch.com/openval/
- Appsilon R 包验证指南: https://www.appsilon.com/post/r-package-validation-in-pharma

**云 / GxP / 资质**
- AWS GxP: https://aws.amazon.com/blogs/industries/automating-gxp-compliance-in-the-cloud-best-practices-and-architecture-guidelines/
- Azure GxP: https://azure.microsoft.com/en-us/blog/new-azure-gxp-guidelines-help-pharmaceutical-and-biotech-customers-build-gxp-solutions/
- IQ/OQ/PQ 指南: https://govalidation.com/blog/iq-oq-pq-validation-guide/

---

*本报告为调研与规划文档，非法律或监管意见。正式监管递交前，建议就具体产品与软件选择与 FDA（及相关机构）审评团队早期沟通，并由 QA/监管事务对本方案做机构内部复核。*
