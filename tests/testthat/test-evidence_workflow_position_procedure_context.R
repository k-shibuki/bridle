## Issue #269: procedure_context + stale detection (evidence-workflow-position.sh)

wfp_run <- function(root, script) {
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)
  Sys.setenv(PATH = paste(root, old, sep = .Platform$path.sep))
  out <- withr::with_dir(root, system2("bash", args = c(script), stdout = TRUE, stderr = TRUE))
  text <- paste(out, collapse = "\n")
  testthat::expect_true(nzchar(text), paste("empty output; stderr may hold:", text))
  jsonlite::fromJSON(text, simplifyVector = TRUE)
}

wfp_setup_repo <- function(root, workflow_json) {
  dir.create(file.path(root, ".cursor", "state"), recursive = TRUE)
  writeLines(
    c(
      "#!/usr/bin/env sh",
      "if [ \"$1\" = \"issue\" ]; then echo '[]'; exit 0; fi",
      "if [ \"$1\" = \"pr\" ]; then echo '[]'; exit 0; fi",
      "if [ \"$1\" = \"api\" ]; then echo '{\"data\":{}}'; exit 0; fi",
      "exit 0"
    ),
    file.path(root, "gh")
  )
  Sys.chmod(file.path(root, "gh"), "0700", use_umask = FALSE)
  writeLines(workflow_json, file.path(root, ".cursor", "state", "workflow-phase.json"))

  system2("git", c("-C", root, "init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", root, "config", "user.email", "test@example.com"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", root, "config", "user.name", "test"), stdout = FALSE, stderr = FALSE)
  writeLines("x", file.path(root, "README.md"))
  system2("git", c("-C", root, "add", "."), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", root, "commit", "-m", "init"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", root, "checkout", "-b", "ctx-branch"), stdout = FALSE, stderr = FALSE)
}

test_that("procedure_context emits all fields when workflow-phase.json exists", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  root <- tempfile("bridle-wfp-")
  dir.create(root)
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "ctx-branch",
  "updated_at": "2026-03-22T12:00:00Z"
}'
  )

  ev <- wfp_run(root, script)
  pc <- ev$procedure_context
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

  root <- tempfile("bridle-wfp-")
  dir.create(root)
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "other-branch",
  "updated_at": "2026-03-22T12:00:00Z"
}'
  )

  ev <- wfp_run(root, script)
  testthat::expect_true(ev$procedure_context$stale)
})

test_that("procedure_context stale when updated_at is older than 24 hours", {
  skip_on_cran()
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  pkg_root <- normalizePath(test_path("../.."), mustWork = TRUE)
  script <- file.path(pkg_root, "tools", "evidence-workflow-position.sh")
  skip_if_not(file.exists(script), "evidence-workflow-position.sh missing")

  root <- tempfile("bridle-wfp-")
  dir.create(root)
  wfp_setup_repo(
    root,
    '{
  "workflow_phase": "implement",
  "issue_number": 269,
  "branch": "ctx-branch",
  "updated_at": "1999-01-01T00:00:00Z"
}'
  )

  ev <- wfp_run(root, script)
  testthat::expect_true(ev$procedure_context$stale)
})
