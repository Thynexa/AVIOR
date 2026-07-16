# 文档索引

文件名已 ASCII 化（issue #11，NFR-6 跨平台 CI 可移植性）；正文仍以《标题》互引，重命名不影响引用。

| 文件 | 标题 | 状态 |
| --- | --- | --- |
| [`PRD.md`](PRD.md) | 《AVIOR — R 包验证证据编译器 PRD》 | **开发基线**（受控，修订走 PR） |
| [`design-review.md`](design-review.md) | 《评审意见与聚焦规划》 | 历史讨论记录（示意值以 PRD §6.4 冻结契约为准） |
| [`product-design-review.md`](product-design-review.md) | 《产品设计方向与路线评审（对照 PRD v1.5 基线）》 | 评审记录（处置已落实：PRD v1.6 + M1 实现，见文末补记） |
| [`ValiR-PRD.md`](ValiR-PRD.md) | 《ValiR PRD》v0.1 | 历史参考（已被 `PRD.md` 取代） |
| [`r-package-validation-strategy.md`](r-package-validation-strategy.md) | 《R 包验证策略分析与实施方案》 | 参考文件 |
| [`r-regulatory-submission-research.md`](r-regulatory-submission-research.md) | 《R 语言合规递交调研与实施方案》 | 调研资料 |
| [`qa/design-partner-review-request.md`](qa/design-partner-review-request.md) | Design Partner Evidence-Bundle QA Request | Ready to send; recipient/channel not supplied |
| [`superpowers/plans/`](superpowers/plans/) | 实施计划（M0 契约修订、M1 核心管线——均已完成；M2 路线纲要） | 工作文档 |

示例项目见 [`../examples/minimal-project/`](../examples/minimal-project/)。

根目录 [`../renv.lock`](../renv.lock) 锁定 `DESCRIPTION` 依赖及其传递依赖；`covr`、`lintr`、`renv` 是为覆盖率、静态检查和锁文件维护而刻意记录的 tooling-only 包。
