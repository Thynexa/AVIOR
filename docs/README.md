# 文档索引

文件名已 ASCII 化（issue #11，NFR-6 跨平台 CI 可移植性）；正文仍以《标题》互引，重命名不影响引用。

| 文件 | 标题 | 状态 |
| --- | --- | --- |
| [`PRD.md`](PRD.md) | 《AVIOR — R 包验证证据编译器 PRD》 | **开发基线**（受控，修订走 PR） |
| [`r-package-validation-strategy.md`](r-package-validation-strategy.md) | 《R 包验证策略分析与实施方案》 | 参考文件 |
| [`r-regulatory-submission-research.md`](r-regulatory-submission-research.md) | 《R 语言合规递交调研与实施方案》 | 调研资料 |
| [`riskmetric-spike-results.md`](riskmetric-spike-results.md) | riskmetric 引擎 spike 结果 | 工程记录（配套脚本见 `../tools/riskmetric-spike.R`） |

示例项目见 [`../examples/minimal-project/`](../examples/minimal-project/)。

根目录 [`../renv.lock`](../renv.lock) 锁定 `DESCRIPTION` 依赖及其传递依赖；`covr`、`lintr`、`renv` 是为覆盖率、静态检查和锁文件维护而刻意记录的 tooling-only 包。
