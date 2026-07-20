# Shared hand-built report model (all-ASCII by construction): unit-level
# rendering tests prove that any non-ASCII byte in the English output would
# be template-owned, so the data must be ASCII. Used by test-report.R and
# test-docx.R.

mini_model <- function(forced = FALSE) {
  trace <- data.frame(
    package = c("alpha", "trans"),
    version = c("1.0.0", "0.5.0"),
    classification = c("contributed", "contributed"),
    role = c("direct", "transitive"),
    score = c(0.2, NA_real_),
    tier = c("low", NA_character_),
    decision = c("include", "version_managed"),
    use_statement_ref = c("decisions/alpha.yml#use_statement", NA),
    decision_file = c("decisions/alpha.yml", NA),
    reviewed_by = c("a@example.com", NA),
    decision_date = c("2026-01-01", NA),
    test_files = c("tests/test-alpha.R", NA),
    test_status = c("pass", NA),
    notes = c(NA, NA),
    stringsAsFactors = FALSE)
  list(
    meta = list(
      bundle_id = "bundle-20260101T000000Z",
      generated_at = "2026-01-01T00:00:00Z",
      avior_version = "0.0.0.9000",
      engine_label = "mock 1.0",
      r_version = "4.3.2", platform = "x86_64-pc-linux-gnu",
      project_name = "demo-project",
      lockfile_sha256 = strrep("a", 64),
      policy_sha256 = strrep("b", 64)),
    integrity = list(
      check = if (forced) "failed" else "passed", forced = forced,
      finding_count = 2L, finding_types = c("failing_tests", "stale_tests")),
    policy = list(policy = list(
      risk_tiers = list(low_max = 0.25, high_min = 0.55))),
    inventory = list(
      lockfile = list(path = "renv.lock", sha256 = strrep("a", 64)),
      packages = list(
        list(name = "alpha", version = "1.0.0",
             classification = "contributed", role = "direct",
             in_scope = TRUE, source = "analysis/main.R:1"),
        list(name = "trans", version = "0.5.0",
             classification = "contributed", role = "transitive",
             in_scope = FALSE, source = "alpha Requirements")),
      summary = list(total = 2L, direct = 1L, transitive = 1L,
                     in_scope_assessed = 1L, recommended_exempt = 0L,
                     force_included = 0L)),
    scores = list(
      engine = list(id = "mock", version = "1.0"),
      run = list(deep = TRUE, network = FALSE),
      packages = list(alpha = list(version = "1.0.0", score = 0.2,
                                   tier = "low")),
      na_metrics = list()),
    decisions = list(alpha = list(
      package = "alpha", decision = "include",
      use_statement = "serializes results to JSON",
      rationale = "low risk, simple use", reviewed_by = "a@example.com",
      date = "2026-01-01")),
    tests = list(results = list(list(
      file = "tests/test-alpha.R", package = "alpha",
      package_version = "1.0.0", tests = 2L, passed = 2L, failed = 0L,
      skipped = 0L, duration_s = 0.5))),
    trace = trace,
    environment = list(
      r_version = "4.3.2", platform = "x86_64-pc-linux-gnu",
      repositories = list(list(name = "CRAN", url = "https://example.com",
                               snapshot = "2024-01-15")),
      lockfile = list(path = "renv.lock", sha256 = strrep("a", 64)),
      engine = list(id = "mock", version = "1.0"),
      locale = list(LC_COLLATE = "C"),
      blas = "reference BLAS", lapack = "LAPACK 3.11.0",
      container = NULL, session_info = "session-info.txt",
      package_count = list(total = 2L, in_scope_assessed = 1L,
                           recommended_exempt = 0L, force_included = 0L,
                           transitive = 1L)),
    counts = list(packages_total = 2L, assessed = 1L, decisions_signed = 1L,
                  tests_run = 1L))
}
