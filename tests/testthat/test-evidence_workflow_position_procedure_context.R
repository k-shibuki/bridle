## Issue #269: procedure_context + stale detection (evidence-workflow-position.sh)

test_that("procedure_context emits all fields when workflow-phase.json exists", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  # Given: a git repo on ctx-branch with workflow-phase.json matching current branch
  root <- withr::local_tempdir("bridle-wfp-")
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "ctx-branch",
  "updated_at": "2026-03-22T12:00:00Z"
}'
  )

  # When: evidence-workflow-position.sh is executed
  ev <- wfp_run(root, script)
  pc <- ev$procedure_context

  # Then: all procedure_context fields are populated and stale is false
  testthat::expect_equal(pc$workflow_phase, "implement")
  testthat::expect_equal(pc$issue_number, 269L)
  testthat::expect_equal(pc$branch, "ctx-branch")
  testthat::expect_equal(pc$updated_at, "2026-03-22T12:00:00Z")
  testthat::expect_false(pc$stale)
})

test_that("procedure_context stale when state branch differs from current branch", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  # Given: workflow-phase.json names a branch that is not the checked-out branch
  root <- withr::local_tempdir("bridle-wfp-")
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "other-branch",
  "updated_at": "2026-03-22T12:00:00Z"
}'
  )

  # When: evidence-workflow-position.sh runs in the repo
  ev <- wfp_run(root, script)

  # Then: branch mismatch marks procedure_context stale
  testthat::expect_true(ev$procedure_context$stale)
})

test_that("procedure_context stale when updated_at is older than 24 hours", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  # Given: workflow-phase.json timestamp is well beyond the 24h threshold
  root <- withr::local_tempdir("bridle-wfp-")
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "ctx-branch",
  "updated_at": "1999-01-01T00:00:00Z"
}'
  )

  # When: evidence-workflow-position.sh runs in the repo
  ev <- wfp_run(root, script)

  # Then: timestamps older than 24h mark procedure_context stale
  testthat::expect_true(ev$procedure_context$stale)
})

test_that("procedure_context stale when updated_at is exactly 24 hours old", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  # Given: updated_at is ~24h before current wall clock (integer age_hours >= 24 in shell)
  root <- withr::local_tempdir("bridle-wfp-")
  boundary <- Sys.time() - 86400
  updated_at <- strftime(boundary, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  wfp_setup_repo(
    root,
    sprintf(
      '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "ctx-branch",
  "updated_at": "%s"
}',
      updated_at
    )
  )

  # When: evidence-workflow-position.sh runs in the repo
  ev <- wfp_run(root, script)

  # Then: integer age_hours at the 24h boundary still triggers stale (>= 24)
  testthat::expect_true(ev$procedure_context$stale)
})
