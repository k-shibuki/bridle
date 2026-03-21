# FSM SSOT regression (Refs: #282) — mirrors `make test-fsm-fixtures`.

test_that("FSM jq fixture suite passes (pull-request-readiness, effective-state, augment-routing)", {
  skip_if_not(nzchar(Sys.which("bash")), "bash not on PATH")
  skip_if_not(nzchar(Sys.which("jq")), "jq not on PATH")

  # Given: Offline golden cases under tests/evidence/golden/fsm/cases/
  script <- testthat::test_path("../../tools/test-fsm-fixtures.sh")
  skip_if_not(file.exists(script), paste("missing", script))

  # When: The bash harness runs all JSON cases against docs/agent-control/fsm/*.jq
  out <- system2("bash", script, stdout = TRUE, stderr = TRUE)
  st <- attr(out, "status", exact = TRUE)
  st <- if (is.null(st)) NA_integer_ else as.integer(st)

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

  out <- withr::with_envvar(c(BRIDLE_TEST_FSM_CASE_DIR = bad_dir), {
    system2("bash", script, stdout = TRUE, stderr = TRUE)
  })
  st <- attr(out, "status", exact = TRUE)
  st <- if (is.null(st)) NA_integer_ else as.integer(st)

  expect_false(identical(st, 0L), info = paste(out, collapse = "\n"))
})
