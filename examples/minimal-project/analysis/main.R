# 最小示例分析脚本 —— avior scan 从这里识别"直接调用"包
library(lme4)       # 直接调用：混合效应模型
library(survival)   # 直接调用：生存分析（recommended 包）

fit_mixed <- function(data) {
  lmer(response ~ dose + (1 | subject), data = data)
}

fit_surv <- function(data) {
  coxph(Surv(time, status) ~ arm, data = data)
}

export_results <- function(obj, path) {
  jsonlite::write_json(obj, path)   # 直接调用（命名空间形式）
}
# 注意：minqa 未被直接 library()/:: 调用 —— 它是 lme4 拉入的间接依赖
