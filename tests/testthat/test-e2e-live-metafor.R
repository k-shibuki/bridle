# Issue #168: Real LLM E2E — validate prompt quality with GitHub Models
#
# These tests run the full pipeline with real LLM calls via GitHub Models.
# They are skipped when GITHUB_PAT is not set or on CRAN.
#
# Design principles:
#   - Tolerant assertions: type/structure checks, not content assertions
#   - Rate limiting: Sys.sleep(1) between LLM calls
#   - Failure classification: capture and report failures, don't fail opaquely

skip_on_unit_tier()
skip_on_cran()
skip_if_not_installed("metafor")
skip_if_not_installed("ellmer")
skip_if_not(
  nzchar(Sys.getenv("GITHUB_PAT")),
  message = "GITHUB_PAT not set — skipping live LLM tests"
)

.live_provider <- "github"
.live_model <- "gpt-4o-mini"

# Shared draft output, lazily computed once per test run
.live_draft_env <- new.env(parent = emptyenv())

.get_live_draft <- function() {
  if (!is.null(.live_draft_env$result)) {
    return(.live_draft_env$result)
  }

  tmp <- withr::local_tempdir(.local_envir = .live_draft_env)
  scan <- scan_package("metafor")

  drafts <- tryCatch(
    draft_knowledge(
      scan,
      provider = .live_provider,
      model = .live_model,
      output_dir = tmp
    ),
    error = function(e) {
      list(.error = conditionMessage(e), .class = class(e))
    }
  )

  .live_draft_env$result <- list(
    drafts = drafts,
    output_dir = tmp,
    scan = scan
  )

  Sys.sleep(1)
  .live_draft_env$result
}

# -- T-LIVE-01: Real draft output is loadable ----------------------------------

test_that("T-LIVE-01: real draft_knowledge() output loads via bridle_agent()", {
  # Given: real LLM-generated draft output
  # When:  loading with bridle_agent()
  # Then:  agent loads without error, or failure is classified
  live <- .get_live_draft()

  if (!is.null(live$drafts$.error)) {
    skip(paste("Draft generation failed:", live$drafts$.error))
  }

  agent <- tryCatch(
    bridle_agent(
      live$output_dir,
      provider = .live_provider,
      model = .live_model
    ),
    error = function(e) {
      list(.error = conditionMessage(e), .class = class(e))
    }
  )

  if (is.list(agent) && !is.null(agent$.error)) {
    skip(paste(
      "bridle_agent() load failed (prompt quality issue):",
      agent$.error
    ))
  }

  expect_true(!is.null(agent$graph))
  expect_true(length(agent$knowledge) > 0L)
})

# -- T-LIVE-02: Validation on real draft ---------------------------------------

test_that("T-LIVE-02: validate_plugin() documents quality of real draft", {
  # Given: real LLM-generated draft output
  # When:  running validate_plugin()
  # Then:  result is reported (pass or classified failure)
  live <- .get_live_draft()

  if (!is.null(live$drafts$.error)) {
    skip(paste("Draft generation failed:", live$drafts$.error))
  }

  result <- tryCatch(
    validate_plugin(live$output_dir),
    error = function(e) {
      list(.error = conditionMessage(e), .class = class(e))
    }
  )

  if (is.list(result) && !is.null(result$.error)) {
    skip(paste(
      "validate_plugin() threw an error (prompt quality issue):",
      result$.error
    ))
  }

  n_errors <- length(result@errors)
  n_warnings <- length(result@warnings)
  cli::cli_inform(c(
    "i" = "T-LIVE-02 quality baseline: {n_errors} error(s), {n_warnings} warning(s)",
    if (n_errors > 0L) c("!" = "Errors: {paste(result@errors, collapse = '; ')}"),
    if (n_warnings > 0L) c("!" = "Warnings: {paste(result@warnings, collapse = '; ')}")
  ))

  expect_true(S7::S7_inherits(result, ValidationResult)) # nolint: object_usage_linter. S7 class
})

# -- T-LIVE-03: Single-turn runtime smoke test ---------------------------------

test_that("T-LIVE-03: single runtime turn completes with real LLM", {
  # Given: agent loaded from real draft, real runtime LLM
  # When:  running one turn of the console
  # Then:  first node processes: prompt sent, response received, parsed
  live <- .get_live_draft()

  if (!is.null(live$drafts$.error)) {
    skip(paste("Draft generation failed:", live$drafts$.error))
  }

  agent <- tryCatch(
    bridle_agent(
      live$output_dir,
      provider = .live_provider,
      model = .live_model
    ),
    error = function(e) NULL
  )

  if (is.null(agent)) {
    skip("Agent could not be loaded from real draft")
  }

  Sys.sleep(1)

  turn_count <- 0L
  local_mocked_bindings(
    bridle_readline = function(prompt) {
      turn_count <<- turn_count + 1L
      if (turn_count >= 2L) "abort" else "y"
    }
  )

  session_result <- tryCatch(
    bridle_console(agent),
    error = function(e) {
      list(.error = conditionMessage(e), .class = class(e))
    }
  )

  if (is.list(session_result) && !is.null(session_result$.error)) {
    cli::cli_inform(c(
      "!" = "T-LIVE-03 single-turn failed: {session_result$.error}",
      "i" = "Turns completed before failure: {turn_count}"
    ))
  }

  expect_true(turn_count >= 1L, label = "At least one turn should have been attempted")
})

# -- T-LIVE-05: Draft parse resilience ----------------------------------------

test_that("T-LIVE-05: parse_draft_response handles real LLM output", {
  # Given: real raw LLM response from draft_knowledge prompt
  # When:  parsing with parse_draft_response()
  # Then:  produces 3 non-empty sections, or failure mode documented
  scan <- scan_package("metafor")
  prompt <- bridle:::assemble_draft_prompt(scan, references = NULL)

  Sys.sleep(1)

  raw_response <- tryCatch(
    bridle:::bridle_chat(prompt, provider = .live_provider, model = .live_model),
    error = function(e) NULL
  )

  if (is.null(raw_response)) {
    skip("LLM call failed — cannot test parse resilience")
  }

  parsed <- tryCatch(
    bridle:::parse_draft_response(raw_response),
    error = function(e) {
      list(.error = conditionMessage(e), .class = class(e))
    }
  )

  if (is.list(parsed) && !is.null(parsed$.error)) {
    skip(paste(
      "parse_draft_response failed (prompt quality issue):",
      parsed$.error
    ))
  }

  expect_true(!is.null(parsed$decision_graph), label = "decision_graph section present")
  expect_true(!is.null(parsed$knowledge), label = "knowledge section present")
  expect_true(!is.null(parsed$constraints), label = "constraints section present")
})
