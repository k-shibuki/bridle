# FSM SSOT regression (Refs: #282) — mirrors `make test-fsm-fixtures`.

# CI note: `system2(..., stdout = TRUE, stderr = TRUE)` can drop the `status`
# attribute on some Linux runners; `pipe()` + `close()` returns the exit status
# reliably after draining stdout (stderr merged via `2>&1`).
run_fsm_fixture_script <- function(script, env = character()) {
  script <- normalizePath(script, mustWork = TRUE)
  cmd <- paste("bash", shQuote(script), "2>&1")
  withr::with_envvar(env, {
    con <- pipe(cmd)
    out <- readLines(con, warn = FALSE)
    st <- close(con)
    list(out = out, status = as.integer(st))
  })
}

test_that("FSM jq fixture suite passes (pull-request-readiness, effective-state, augment-routing)", {
  skip_if_not(nzchar(Sys.which("bash")), "bash not on PATH")
  skip_if_not(nzchar(Sys.which("jq")), "jq not on PATH")

  # Given: Offline golden cases under tests/evidence/golden/fsm/cases/
  script <- testthat::test_path("../../tools/test-fsm-fixtures.sh")
  skip_if_not(file.exists(script), paste("missing", script))

  # When: The bash harness runs all JSON cases against docs/agent-control/fsm/*.jq
  res <- run_fsm_fixture_script(script)
  out <- res$out
  st <- res$status

  # Then: Exit status is zero and the last line reports success
  expect_identical(st, 0L, info = paste(out, collapse = "\n"))
  expect_true(any(grepl("OK: all FSM fixtures passed", out, fixed = TRUE)),
    info = paste(out, collapse = "\n")
  )
})

test_that("FSM jq harness exits non-zero when a case file is invalid JSON", {
  skip_if_not(nzchar(Sys.which("bash")), "bash not on PATH")
  skip_if_not(nzchar(Sys.which("jq")), "jq not on PATH")

  script <- testthat::test_path("../../tools/test-fsm-fixtures.sh")
  skip_if_not(file.exists(script), paste("missing", script))

  bad_dir <- tempfile("fsm_bad_case_")
  dir.create(bad_dir)
  writeLines("not valid json {", file.path(bad_dir, "broken.json"))

  res <- run_fsm_fixture_script(script, c(BRIDLE_TEST_FSM_CASE_DIR = bad_dir))
  st <- res$status

  expect_false(identical(st, 0L), info = paste(res$out, collapse = "\n"))
})
