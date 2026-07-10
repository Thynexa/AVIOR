# AVIOR

> **Automated Validation and Inspection for Operational R-packages**
> `renv.lock` 进，可签署的验证证据包出。

AVIOR 是一个面向受监管环境（FDA / EMA / NMPA 申报）的 **local-first R 包验证证据编译器**。它像 `pytest` / `terraform` 一样活在你的仓库和 CI 里：输入项目的依赖清单与策略配置，输出结构化、防篡改、可直接送签的验证证据包。

命名取自船底座 ε（Avior）——神话中阿尔戈号的龙骨，寓意验证体系的龙骨。

---

## 📌 当前状态：设计定稿，尚未开始编码

本仓库目前处于 **规格与设计阶段**。它包含产品需求文档、方法论调研、评审记录，以及一份手工组装的最小样例证据包（对应 PRD 的 M0 里程碑）。**核心 R 包 `avior` 的实现代码尚未开始。**

开发基线是 [`AVIOR PRD.md`](./AVIOR%20PRD.md)（v1.2）——所有后续开发以此为准，修订走 PR。

---

## 它解决什么问题

受监管环境用 R 的团队要建立合规的包验证体系，今天必须手工缝合 riskmetric、riskassessment、valtools、PPM、renv、diffify、oysteR 等至少 7 个工具，并人工编写与拼接风险评估、决策记录、追溯矩阵、验证报告。碎片化编排与文档黑洞是最大成本；证据链靠手工维系，审计时易断裂。

AVIOR 把「依赖识别 → 风险评分 → 决策留痕 → 定向测试 → 环境指纹 → 审计就绪报告」编译成一条命令的产出。

**是**：一个证据编译器，跑在用户环境与 CI，输出可送签的验证证据包。
**不是**：平台。不托管数据、不做电子签名、不提供 Web 服务、不替客户做合规判断——合规责任主体始终是申办方。

## 三条设计公理（约束一切范围决策）

| # | 公理 | 直接后果 |
| --- | --- | --- |
| A1 | **做管线，不做平台** | 无服务端 / 数据库 / 多租户 / 账号体系 |
| A2 | **证据即文件** | 策略、清单、评分、决策、报告全是版本库中的纯文本；git 历史即变更留痕，PR 即评审流 |
| A3 | **签署留在客户 QMS** | 产出 signature-ready 证据包（SHA-256 清单保证完整性）；签署与受控归档走客户现有体系 |

## 计划中的 CLI（V1 核心闭环）

```bash
avior init      # 生成策略骨架与目录结构
avior scan      # 从 renv.lock 识别依赖：三分类 + direct/transitive
avior assess    # 经适配层（riskmetric）批量风险评分
avior review    # 生成决策记录桩，团队填写用途/理由/署名（走 PR）
avior test      # 运行中高风险包的定向 testthat 测试
avior bundle    # 编译不可变证据包（报告 + 追溯矩阵 + 环境指纹 + 哈希清单）
avior check     # CI 门禁：依赖漂移 + 完整性校验
avior verify    # 独立校验证据包完整性（审计员只读，无需项目上下文）
```

---

## 仓库结构

```text
AVIOR/
├── AVIOR PRD.md                    # ⭐ 开发基线：产品需求文档 v1.2
├── ValiR PRD.md                    # 历史参考：被 AVIOR PRD 取代的平台版 PRD v0.1
├── 评审意见与聚焦规划.md            # 从「平台」收敛到「CLI 工具」的评审决策
├── R语言合规递交调研与实施方案.md   # 方法论调研：监管要求与工具链对比
├── R包验证策略分析与实施方案.docx   # 同上（docx 版本）
├── examples/
│   └── minimal-project/            # M0 手工样例证据包（4 包，覆盖所有关键情形）
├── .claude/skills/  ·  .agents/skills/   # 供 AI 辅助开发的 superpowers 技能集
└── skills-lock.json
```

## 从哪里开始读

| 你是… | 先读 |
| --- | --- |
| 想了解产品全貌 | [`AVIOR PRD.md`](./AVIOR%20PRD.md) —— 定位、公理、CLI、文件契约、里程碑一应俱全 |
| 想看证据包长什么样 | [`examples/minimal-project/`](./examples/minimal-project/) —— 一份可读的手工样例，附 QA/审计员阅读指引 |
| 想理解方法论出处 | [`R语言合规递交调研与实施方案.md`](./R语言合规递交调研与实施方案.md) —— 监管背景与工具链对比 |
| 想知道范围为何这样定 | [`评审意见与聚焦规划.md`](./评审意见与聚焦规划.md) —— 平台版到 CLI 版的收敛逻辑 |

## 方法论锚点

- **R Validation Hub 白皮书**——风险评估四准则（用途/类型、维护、社区使用、测试）。
- **intended-for-use 聚焦原则**——深度验证只针对直接调用包；间接依赖只做版本管理。这是工作量收敛的关键。
- **ISPE GAMP 5（第二版）**——最小交付物：规范、风险评估、测试、追溯矩阵。

---

## 技术选型（摘自 PRD §7.3）

| 决策 | 选择 |
| --- | --- |
| 实现语言 | R 包为核心（用户是 R 团队，riskmetric/testthat/covr 都是 R） |
| 最低 R 版本 | R ≥ 4.1 |
| 配置 / 产物格式 | YAML + CSV（diff 友好，QA 无需工具即可阅读） |
| 报告引擎 | Quarto → html / docx |
| 分发 | CRAN 优先 + GitHub Releases |
| 开源许可 | Apache-2.0 |

## 贡献

本 PRD 为开发基线。修订走 PR；任何与 §2 设计公理冲突的变更须先修订公理并记录理由。

## 许可

Apache-2.0（见 PRD §7.3 已决事项 Q2）。
