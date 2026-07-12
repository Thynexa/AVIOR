# avior init — scaffolding (FR-INIT-1/2). Idempotent: existing files are
# never overwritten. The generated avior.yml is a human-edited template
# (category (2) in the example's file taxonomy), so it carries comments;
# generated artifacts (category (3)) go through the canonical writers instead.

init_config_template <- function(project_name) {
  c(
    "avior: 1",
    "project:",
    paste0("  name: ", project_name),
    "  validation_dir: validation",
    "scope:",
    "  lockfile: renv.lock",
    "  intended_for_use: auto        # auto | explicit（仅用 include 清单）",
    "  include: []                   # 强制纳入；可把默认豁免的 base/recommended 包拉回评估范围",
    "  exclude: []                   # 强制排除（需在报告中说明）",
    "  custom_orgs: []               # 判定自研包的来源规则，如 [\"our-gh-org/*\"]",
    "policy:",
    "  engine: riskmetric",
    "  weights:                      # 默认仅 metadata/network 档指标（PRD §6.2 说明）",
    "    has_vignettes: 0.5",
    "    has_news: 0.5",
    "    has_bug_reports_url: 0.5",
    "    downloads_1yr: 1.0",
    "    remote_checks: 1.0          # 「测试」准则的 network 档承担者（CRAN 机器检查）",
    "    last_30_bugs_status: 1.0",
    "  risk_tiers: { low_max: 0.25, high_min: 0.55 }",
    "  na_action: reweight           # reweight | zero | fail",
    "  rationale: >                  # 必填；留 TODO 则 check 不通过",
    "    TODO — 记录阈值与权重的组织理由（引用评审会/SOP 依据）",
    "depth_by_risk:",
    "  low: metadata_only",
    "  medium: use_statement_required",
    "  high: targeted_tests_required",
    "report:",
    "  formats: [html, docx]",
    "  language: zh"
  )
}

avior_init <- function(root = ".", ci = NULL) {
  if (!is.null(ci)) {
    avior_abort("avior init --ci is planned for V1 (FR-INIT-3) and not implemented yet")
  }
  vdir <- file.path(root, "validation")
  created <- character(0)
  skipped <- character(0)

  for (d in c(vdir, file.path(vdir, "decisions"), file.path(vdir, "tests"),
              file.path(vdir, ".cache"))) {
    if (!dir.exists(d)) {
      dir.create(d, recursive = TRUE)
      created <- c(created, paste0(d, "/"))
    }
  }

  write_if_absent <- function(path, lines) {
    if (file.exists(path)) {
      skipped <<- c(skipped, path)
    } else {
      write_lines_lf(lines, path)
      created <<- c(created, path)
    }
  }

  project_name <- basename(normalizePath(root))
  write_if_absent(file.path(vdir, "avior.yml"), init_config_template(project_name))
  write_if_absent(file.path(vdir, ".gitignore"), c(".cache/", "evidence/*.zip"))

  invisible(list(created = created, skipped = skipped))
}
