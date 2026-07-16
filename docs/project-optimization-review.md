# 项目优化审查(2026-07-14)

> 范围:M1 合并后(PR #17–#19)的全量代码 + 基建 + 流程审查。
> 结论先行:**M1 代码质量高,无需返工的架构问题;当前最大风险不在代码,而在两个从未被验证的假设**(样例包能否进签署流程、riskmetric 适配器能否真实跑通)。代码级只发现少量鲁棒性缺口,可合并为一个小型 hardening PR。

## 总体评估

- 契约驱动 + fail-closed 的风格贯彻得很一致:自定义 canonical 序列化(字节级确定性、`SOURCE_DATE_EPOCH`)、静态指标注册表(离线校验策略)、每条 finding 带 package/type/fix(NFR-8)。
- ~490 个测试、三平台 + R 4.1 下限 CI、fixture 防漂移测试,回归防护到位。
- `docs/superpowers/plans/2026-07-12-m2-roadmap.md` 的方向判断仍然成立,本审查不推翻它,只补充代码级发现并确认优先级。

## 一、最高优先:两件先于写新代码的事(与 M2 纲要 §0 一致,至今未动)

| # | 事项 | 风险敞口 |
| --- | --- | --- |
| 0.1 | **样例证据包送 design partner QA 评审**(M0 出口标准) | 「此格式能进签署流程」是全项目最大假设;评审意见直接决定 M2 `bundle`/report 的形态,先送审避免返工 |
| 0.2 | **真实 riskmetric 冒烟 + 性能 spike** | `R/engine.R` 的 `mget(paste0("assess_", metric_ids))` 指标映射、`pkg_ref()` 对未安装包的行为、`remote_checks` 等网络指标的实际可用性,**从未被真实执行过**;§8 性能目标值也无实测数据。适配器若有出入,越晚发现修正成本越高 |

## 二、代码级发现

### P2 — 鲁棒性 / CLI 打磨(建议合并为一个小 PR,半天量级)

1. **过时的错误信息**:`R/cli.R:44` 无命令时报 `expected: init|scan`,实际已有 5 个命令(`R/cli.R:105` 处的列表是对的)。
2. **CLI 缺 `--version` / `--help`**:审计场景下报告需要引用工具版本,`avior --version` 是刚需;目前只能靠触发未知命令报错来看命令列表。
3. **评分缓存损坏 → assess 整体崩溃**:`R/assess.R:107` 直接 `read_yaml_file(cache_file)`,`.cache/scores/*.yml` 被中断写入损坏时抛未捕获错误(exit 2)。应 `tryCatch` 视为 cache miss 重新评分——缓存本就是可再生产物。
4. **test-results.yml 损坏 → check 崩溃**:`R/check.R:89` 无容错,而 `decisions/*.yml` 损坏会产出结构化的 `invalid_decision` finding(`R/review.R:63`)。两处 fail-closed 风格不一致;应产出 `invalid_test_results` finding(exit 1)而非 `unexpected error`(exit 2)。
5. **canonical 写出非原子**:`R/canonical.R` `write_lines_lf()` 原地写文件,进程中断会留下半截 `inventory.yml`/`scores.yml`。对审计工具建议 temp 文件 + `file.rename()` 原子替换。
6. 琐碎:`R/cli.R:1` 注释写 `inst/exec/avior`,实际文件在顶层 `exec/avior`。

### P3 — 流程与基建

7. **M2 纲要 §2 的 5 个递延项应落为 GitHub issue**(纲要自己也这么建议)——当前仓库 **0 个 open issue**,递延项只活在文档里,容易丢。
8. **CI 缺覆盖率与 lint**:加一个 covr 作业(+ badge)和 lintr,成本低;M2 的 `avior test` 本身要集成 covr,先在自家 CI 用起来。
9. **Dogfooding 缺位**(M3 NFR-5a/5b):仓库自身没有 renv.lock,无法用 avior 验证 avior;M3 前不阻塞,但建 renv.lock 可以提前做。

### 明确不建议现在做的

- 性能优化(`transitive_source` 的 O(n²)、`scan_file_calls` 的逐行 append):典型 lockfile(数百包)下无感,等 0.2 的性能 spike 给出实测再说。
- pkgdown 站点、roxygen 化文档:M2 交付前属于分心项。

## 三、下一步工作方向(建议顺序)

1. **并行启动 0.1(QA 送审)与 0.2(riskmetric 冒烟)** —— 两者都不写新功能代码,但都可能改变 M2 的实现细节。
2. **小型 hardening PR**:上面 P2 的 1–6 项,一次解决。
3. **M2 主线按既有纲要推进**:PR-A `avior test` → PR-B `avior verify` → PR-C `avior bundle`(HTML 报告先行,docx/Quarto 放 M3)。0.2 的冒烟结论若要求改适配器,在 PR-A 前落地。
4. **开 issue 跟踪递延项**(纲要 §2 的 5 项)+ CI 加 covr/lintr。
5. **M3 预备**:dogfooding renv.lock、NFR-9 方法论对照文档随命令落地持续积累。

## 四、过程建议

沿用 M1 的循环(writing-plans 逐任务计划 → TDD → PR 前对抗性评审):7 轮评审拦截 ~35 个缺陷且多为 fail-open 类,这个循环的投入产出比已被验证,M2 不要省。
