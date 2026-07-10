# AVIOR 最小示例：从项目输入到可签署证据包

这是一份**手工组装的最小样例证据包**（对应 PRD 的 M0 里程碑）。目的：在写任何代码之前，先确认「证据即文件 + git 留痕 + 哈希清单」这套证据形态**能否进入真实的 QA 签署流程**。

一个 4 包的假想 R 项目，覆盖了所有关键情形：三分类、直接/间接调用、低/高风险、两种决策、定向测试、recommended 包被 `scope.include` 强制纳入。

> ⚠️ **示意值声明**：本示例在无 R 环境下手工组装，`scores.yml` 中的风险分为**示意值**，真实运行时由 riskmetric 引擎产出。其余结构（清单、决策、追溯矩阵、环境指纹、哈希清单）均为最终格式。

---

## 三类文件：谁提供什么

| 类别 | 文件 | 谁产生 |
| --- | --- | --- |
| **① 输入**（你的真实项目提供） | `renv.lock`、`analysis/*.R` | 项目本来就有 |
| **② 人工填**（流程中人脑输入） | `validation/avior.yml` 的策略与理由、`validation/decisions/*.yml` 的用途声明与决策、`validation/tests/*.R` | 验证负责人 / 程序员 |
| **③ 自动产出**（avior 生成） | `inventory.yml`、`scores.yml`、`test-results.yml`、`evidence/bundle-*/` | avior 命令 |

**关键结论：你要准备的只有 ① 的两样。** 其中 `analysis/*.R` 只要能让 avior 看到 `library()`/`::` 调用即可；连这个都没有时，手工给一份直接调用清单也行。

---

## 目录导览

```text
minimal-project/
├── renv.lock                          # ① 输入：依赖锁（4 包，划定证据边界）
├── analysis/main.R                    # ① 输入：源码（scan 从这里识别直接调用）
└── validation/
    ├── avior.yml                      # ② 人工：策略即代码（权重/阈值/理由）
    ├── inventory.yml                  # ③ scan 产出：三分类 + direct/transitive
    ├── scores.yml                     # ③ assess 产出：风险分（本例为示意值）
    ├── test-results.yml               # ③ test 产出
    ├── decisions/
    │   ├── jsonlite.yml               # ② 人工：低风险 → include
    │   ├── lme4.yml                   # ② 人工：高风险 → include_with_tests
    │   └── survival.yml               # ② 人工：recommended 强制纳入 → include_with_tests
    ├── tests/
    │   ├── test-lme4-fit.R            # ② 人工：针对用途的定向测试
    │   └── test-survival-coxph.R      # ② 人工：强制纳入包同样要补定向测试
    └── evidence/bundle-20260708T120000Z/   # ③ bundle 产出（不可变证据包）
        ├── report.html               # 验证报告（GAMP 5 叙事结构）
        ├── traceability.csv          # 追溯矩阵：每行一条完整证据链
        ├── environment.json          # 环境指纹（R 版本/快照/lockfile 哈希）
        ├── BUNDLE.yml                # 元数据 + 完整性状态
        ├── snapshot/                 # 编译时点的输入快照副本
        └── MANIFEST.sha256           # 全文件哈希 → 内部一致性校验（防篡改锚点在外部，见下）
```

## 这 4 个包演示了什么

| 包 | 分类 | 角色 | 风险 | 决策 | 演示点 |
| --- | --- | --- | --- | --- | --- |
| `jsonlite` | contributed | direct | low (0.12) | include | 低风险仅元数据评估 |
| `lme4` | contributed | direct | high (0.58) | include_with_tests | 高风险必须配定向测试 |
| `survival` | **recommended**（强制纳入） | direct | high (0.61) | include_with_tests | recommended 默认豁免**不是铁律**：因承担主分析（coxph）经 `scope.include` 拉回范围，照常评分/决策/补测 |
| `minqa` | contributed | **transitive** | — | version_managed | intended-for-use 聚焦：间接依赖不深验 |

> recommended 包的**默认豁免路径**（不评分、不深验）本例未单独演示——规则见 PRD §5.2「范围规则」：豁免是默认值，intended-use 重要性可经 `scope.include` 覆盖，覆盖行为记录进 `inventory.yml`（`overridden: true`）。

---

## 怎么读这份证据包（QA / 审计员视角）

1. **先看 `evidence/.../report.html`** —— 完整的验证叙事。
2. **再看 `traceability.csv`** —— 每行打通「包 → 分类 → 评分 → 决策 → 测试 → 结果」，是审计的主入口。
3. **校验完整性**（无需任何工具，标准命令即可）：
   ```bash
   cd validation/evidence/bundle-20260708T120000Z && sha256sum -c MANIFEST.sha256
   ```
   任何一个字节被意外改动都会导致对应文件校验失败 —— 这就是 `avior verify` 的内核。

   **信任边界**：manifest 只保证 bundle 的**内部一致性**。对脱离 git 的松散目录 / zip，能改文件者亦能重算改写 `MANIFEST.sha256`，校验照常通过——所以 detached bundle 的**防篡改锚点是外部的**：本示例的锚点是 `evidence/` 所在的 **git 提交哈希**（公理 2「git 留痕」的意义所在）；交付客户后则是 **QMS 归档记录**或**独立签名**。归档时建议把 manifest 自身的 SHA-256 一并记入提交信息 / 归档记录（PRD FR-VERIFY-3）。

---

## 从这个例子到你的真实项目

替换 ① 的两样，重跑管线即可：

```bash
# 把你项目的 renv.lock 和源码放好，然后：
avior init          # 生成 avior.yml 骨架（填阈值理由）
avior scan          # 产出 inventory.yml
avior assess        # 产出 scores.yml（真实由 riskmetric 打分）
avior review        # 生成决策桩 → 团队填 use_statement/rationale/署名
avior test          # 跑中高风险包的定向测试
avior bundle        # 编译证据包
avior check         # CI 门禁：漂移 + 完整性
```

**给我你真实项目的 `renv.lock`（哪怕脱敏到只剩包名和版本），我就能把这份示意 bundle 换成你项目的真实骨架** —— 评分留待有 R 环境时由 riskmetric 填入，其余结构立即成形，可直接拿去给你的 QA 看格式。
