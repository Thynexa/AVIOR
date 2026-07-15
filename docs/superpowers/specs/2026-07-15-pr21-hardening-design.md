# PR #21 项目优化与加固设计

**日期：** 2026-07-15

**状态：** 已批准，进入实施

**目标 PR：** [Thynexa/AVIOR#21](https://github.com/Thynexa/AVIOR/pull/21)

## 1. 背景与目标

PR #21 对 M1 合并后的代码、基建和流程做了全量健康检查。复核确认其中六项 P2 代码问题均真实存在：CLI 命令提示过时、缺少 `--help`/`--version`、损坏评分缓存导致 `assess` 崩溃、损坏 `test-results.yml` 导致 `check` 崩溃、canonical writer 非原子写，以及 CLI 入口注释路径错误。

进一步核对 riskmetric 0.2.7 官方源码时还发现两个适配器契约缺陷：

1. `assess_last_30_bugs_status` 的输出列别名是 `bugs_status`，当前代码按 `last_30_bugs_status` 取值，会静默得到 `NA`；
2. 当前适配器接收 lockfile 版本却没有校验 `pkg_ref()` 实际解析的版本，可能对已安装或远端的不同版本评分。

本轮目标是在不改动 M1 架构、不提前实现 M2 主线命令的前提下，关闭上述鲁棒性和适配器风险，增加可执行的质量门禁，建立递延工作项，并准备 design partner QA 所需材料。

## 2. 范围

### 2.1 本轮实施

- CLI：完整命令提示、全局 `--help`、全局 `--version`、正确入口注释；
- 缓存：损坏或结构无效的评分缓存一律视为 cache miss 并重新评分；
- check：损坏或结构无效的 `test-results.yml` 转为 `invalid_test_results` finding，保持业务失败 exit 1；
- canonical writer：在目标文件同目录写临时文件，关闭连接后以 rename 替换，失败时清理临时文件并保留明确错误；
- riskmetric：显式维护策略指标 ID 到 riskmetric 输出列名的映射，校验被评分包版本与 inventory 版本一致，运行真实冒烟和计时实验；
- CI：新增独立 covr coverage 与 lintr 门禁，并在 README 展示工作流状态；
- dogfooding：生成根目录 `renv.lock`，记录 R 包开发与验证依赖；
- 流程：为 M2 路线 §2 的五个递延项创建 GitHub issue；
- QA：新增可直接交给 design partner 的评审请求、检查清单和反馈记录模板；
- 审阅：完成实现后进行独立对抗性代码审阅，修复 Critical/Important 问题，再重跑全量验证。

### 2.2 明确不做

- 不实现 `avior test`、`avior verify`、`avior bundle`；
- 不做未经实测驱动的性能重构；
- 不增加 pkgdown、roxygen 或报告模板功能；
- 不伪造 design partner 的实际签署或反馈；本轮只把送审材料准备到可直接发送的状态。

## 3. 设计

### 3.1 CLI 元数据命令

`--help` 和 `--version` 作为顶层只读命令进入现有 `parse_argv()` → `run_command()` → `main()` 流程，因此继续遵守统一的 text/JSON 输出和 exit code 规则。

- `avior --help`：exit 0，列出 usage、五个业务命令和两个全局输出选项；
- `avior --version`：exit 0，输出 DESCRIPTION 中的包版本；
- 两者都支持 `--format json`，集合字段保持 JSON array；
- `avior <business-command> --help` 不在本轮扩展为子命令帮助，仍按未知参数拒绝；
- 无命令错误与未知命令错误使用同一个权威命令清单，避免再次漂移。

### 3.2 可再生缓存容错

评分缓存是可再生产物，不是审计输入。读取缓存时，任何解析异常或最小结构校验失败都返回 `NULL`，随后走现有 fresh assessment 路径并原子重写缓存。

最小有效结构要求：顶层为 list，`metrics` 为带名 list 且恰好覆盖当前策略指标，`na_causes` 若存在则为 list。缓存损坏不得降级评分规则、吞掉引擎错误或复用部分值。

### 3.3 `test-results.yml` fail-closed

`test-results.yml` 是审计输入，不能像缓存一样静默忽略。读取和结构校验失败时，`check_test_results()` 返回一个结构化 finding：

- `package: "-"`；
- `type: invalid_test_results`；
- message 说明文件无法解析或不符合预期结构；
- fix 指向重新运行 `avior test` 生成该文件。

该 finding 进入现有 `avior_check()` 聚合，因此 text/JSON 均返回 `status: fail`、CLI exit 1，而不是 unexpected error/exit 2。对完全缺失文件的既有 `missing_test_results` 语义保持不变。

### 3.4 原子 canonical writer

所有 YAML/JSON/CSV 最终仍经 `write_lines_lf()`，所以只在这一层实现原子写即可覆盖全部 artifact writer：

1. 在 `dirname(path)` 创建唯一临时文件，保证 rename 不跨文件系统；
2. 以 binary connection 写 UTF-8、LF-only、末尾换行；
3. 在 rename 前显式关闭 connection；
4. rename 成功后取消临时文件清理；
5. 写入或 rename 失败时清理临时文件并抛 `avior_error`。

目标文件已存在时必须替换成功；三平台 CI 是 Windows/macOS/POSIX 行为的最终验收依据。测试同时验证字节契约未改变、替换现有文件成功、无遗留临时文件。

### 3.5 riskmetric 适配器

适配器继续输出 AVIOR 定义的 goodness `[0,1]`，上层仍以 `1 - weighted.mean()` 聚合为 risk，不改变历史分数方向。

改动集中在 `engine_riskmetric()`：

- 从静态注册表构造明确的 assessment 函数名；
- 根据 assessment 函数的 `column_name` 属性解析 riskmetric 输出列，特别处理 `last_30_bugs_status → bugs_status`；
- 使用 `score_error_NA`，使单指标上游错误显式成为 NA 并进入既有 `na_action` 策略；
- `pkg_ref()` 后比较实际 `ref$version` 与 inventory 版本；不一致时抛 `avior_error`，要求恢复对应 renv 环境或显式安装正确版本，禁止对错误版本评分；
- 缺失 assessment 函数时转换成包含指标 ID 的 `avior_error`，而不是泄漏裸 `mget` 错误。

真实冒烟至少覆盖：本地已安装包的 metadata 指标、`last_30_bugs_status` 别名、CRAN remote `remote_checks`、错误版本拒绝，以及同一输入冷/热两次的 wall-clock 记录。若本机系统依赖无法满足，使用 GitHub Actions Ubuntu 作业完成，不以 mock 测试替代真实冒烟结论。

### 3.6 CI 与质量门禁

采用 r-lib/actions 当前官方模板的结构：

- `coverage.yaml`：Ubuntu + R release，安装 coverage 依赖，运行 `covr::package_coverage()` 并生成 Cobertura；不把第三方上传凭据作为合并前提，覆盖率计算本身必须成功；
- `lint.yaml`：Ubuntu + R release，安装本地包与 lintr，运行 `lintr::lint_package()`，`LINTR_ERROR_ON_LINT=true`；
- README 增加两个 GitHub Actions workflow status badge；
- 不设置未经项目批准的覆盖率阈值，本轮先建立可观察基线；后续阈值单独决策。

新增 workflow 使用当前官方 action major 版本；现有 CI 若需统一 checkout major，作为同一机械更新处理并由 GitHub checks 验证。

### 3.7 renv 与 dogfooding

根 `renv.lock` 记录 DESCRIPTION 的 Depends/Imports/Suggests 以及测试、coverage、lint 所需开发工具。只提交 lockfile，不自动注入会改变所有开发者启动行为的 `.Rprofile`。锁文件必须能被 `renv::status()` 解析；无法在本机安装的 riskmetric 仍应有可解析的 CRAN 记录。

完整的 AVIOR 自验证管线仍依赖 M2 命令，不在本轮伪装为已完成；QA 材料会明确这一区别。

### 3.8 递延 issue 与 QA 材料

创建五个独立 issue，分别跟踪：

1. FR-SCAN-1 DESCRIPTION fallback；
2. `refresh_na` CLI 开关；
3. scope 未知引用从 warning 升为 check finding；
4. FR-INIT-3 `--ci github|gitlab`；
5. inventory `note:` 所有权与 rescan 覆盖策略。

每个 issue 引用 M2 roadmap，写清问题、验收标准和非目标，避免把路线文档重复粘贴成无边界任务。

QA 文档引用现有样例 evidence bundle，要求 design partner 检查签署流可接受性、报告信息层级、追溯矩阵、环境指纹、manifest 验证和强制越过门禁的披露位置，并提供结构化反馈表。没有真实接收方与渠道时，不声称“已送审”。

## 4. 测试策略

所有行为变化遵循 red-green-refactor：先添加只覆盖一个行为的失败测试，确认失败原因正确，再写最小实现。

- CLI：text/JSON help、version、完整无命令提示、未知额外参数保持拒绝；
- assess：语法损坏缓存、结构损坏缓存均触发重新评分且重写有效缓存；
- check：语法损坏、scalar、无效 results row 均成为 `invalid_test_results`，CLI JSON exit 1；
- canonical：替换现有文件、字节契约、临时文件清理、rename 失败错误；
- engine：通过可注入的 riskmetric API seam 测列别名、版本一致/不一致、缺失 assessment 和 NA；另跑真实 riskmetric 冒烟；
- CI/renv/docs：YAML 解析、lintr、coverage、`renv::status()`、R CMD build/check。

最终验证包括：完整 testthat、R CMD check、lintr、covr、CLI 端到端、真实 riskmetric 冒烟、git diff 审计、PR GitHub checks。任何新增 Critical/Important 审阅发现都必须修复并重新执行相关验证。

## 5. 完成标准

只有以下证据同时成立才视为本轮完成：

- PR #21 的六项 P2 建议均有代码或文档变更及回归测试；
- 两项新增 riskmetric 契约缺陷已修复，并有真实运行证据或明确的 CI 运行证据；
- coverage、lint 与原有四个 R CMD check 均为绿色；
- 五个递延 issue 已创建并可追踪；
- 根 `renv.lock` 可解析且状态检查通过；
- design partner QA 材料完整，外部发送状态表述真实；
- 独立复审无未处理 Critical/Important 项；
- 工作树干净，提交已推送到 PR #21 当前 head 分支。
