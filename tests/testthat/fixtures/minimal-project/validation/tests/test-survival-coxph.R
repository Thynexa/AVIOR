# avior-package: survival
# 针对声明用途（coxph 系数估计，主分析）的定向测试。
# 背景：survival 为 recommended 包，默认豁免；因承担主分析经 scope.include
# 强制纳入后，与 contributed 高风险包同等对待 —— 本文件即其定向测试。
# 金标准：对已知数据集（survival 自带 lung），比对系数估计与文献稳定值。
library(testthat)
library(survival)

test_that("coxph 系数估计与金标准一致", {
  fit <- coxph(Surv(time, status) ~ sex, data = lung)
  # 预期值来自 survival 文档/历史稳定结果（金标准比对）
  expect_equal(unname(coef(fit)["sex"]), -0.5310, tolerance = 0.001)
  expect_equal(fit$n, 228L)
})

test_that("survfit 分层生存曲线结构符合用途设定", {
  sf <- survfit(Surv(time, status) ~ sex, data = lung)
  expect_equal(length(sf$strata), 2L)                 # 两组（对应主分析的组间比较）
  expect_equal(sum(sf$n), 228L)
})
