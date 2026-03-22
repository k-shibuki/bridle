## Shared helpers for evidence-workflow-position procedure_context tests (Issue #269)

wfp_run <- function(root, script) {
  withr::local_envvar(PATH = paste(root, Sys.getenv("PATH"), sep = .Platform$path.sep))
  out <- withr::with_dir(root, system2("bash", args = c(script), stdout = TRUE, stderr = TRUE))
  text <- paste(out, collapse = "\n")
  testthat::expect_true(nzchar(text), paste("empty output; stderr may hold:", text))
  jsonlite::fromJSON(text, simplifyVector = TRUE)
}

wfp_setup_repo <- function(root, workflow_json) {
  run_git <- function(...) {
    status <- system2("git", c("-C", root, ...), stdout = FALSE, stderr = FALSE)
    testthat::expect_equal(status, 0L, info = paste("git", paste(c(...), collapse = " ")))
  }

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

  run_git("init")
  run_git("config", "user.email", "test@example.com")
  run_git("config", "user.name", "test")
  writeLines("x", file.path(root, "README.md"))
  run_git("add", ".")
  run_git("commit", "-m", "init")
  run_git("checkout", "-b", "ctx-branch")
}
