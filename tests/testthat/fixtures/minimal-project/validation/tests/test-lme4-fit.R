# avior-package: lme4
# 针对声明用途（lmer 固定/随机效应估计）的定向测试。
# 金标准：对已知数据集，比对系数估计与预期值（此处用 lme4 自带 sleepstudy 示意）。
library(testthat)
library(lme4)

test_that("lmer 固定效应估计与金标准一致", {
  fit <- lmer(Reaction ~ Days + (Days | Subject), data = sleepstudy)
  fx  <- fixef(fit)
  # 预期值来自 lme4 文档/历史稳定结果（金标准比对）
  expect_equal(unname(fx["(Intercept)"]), 251.405, tolerance = 0.01)
  expect_equal(unname(fx["Days"]),         10.467, tolerance = 0.01)
})

test_that("随机效应结构符合模型设定", {
  fit <- lmer(Reaction ~ Days + (Days | Subject), data = sleepstudy)
  expect_true("Subject" %in% names(ranef(fit)))
  expect_equal(nrow(ranef(fit)$Subject), 18L)
})
