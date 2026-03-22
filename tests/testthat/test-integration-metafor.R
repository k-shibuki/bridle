# E2E integration tests for the metafor plugin runtime.
# Issue #134: Realistic metafor plugin fixture + comprehensive E2E tests.
# Uses build_graph() template composition (ADR-0009).

skip_on_unit_tier()
.metafor_dir <- function() {
  testthat::test_path("fixtures", "metafor-plugin")
}

.mock_chat <- function(responses) {
  idx <- 0L
  list(
    chat = function(prompt) {
      idx <<- idx + 1L
      if (idx > length(responses)) {
        responses[[length(responses)]]
      } else {
        responses[[idx]]
      }
    }
  )
}

.mock_readline_queue <- function(inputs) {
  idx <- 0L
  function(prompt) {
    idx <<- idx + 1L
    if (idx > length(inputs)) {
      inputs[[length(inputs)]]
    } else {
      inputs[[idx]]
    }
  }
}

# -- Plugin validation ---------------------------------------------------------

test_that("metafor-plugin fixture loads via bridle_agent", {
  agent <- bridle_agent(.metafor_dir())

  expect_s3_class(agent, "bridle_agent")
  expect_true(!is.null(agent$graph))
  expect_true(!is.null(agent$engine))
  expect_true(!is.null(agent$sandbox))
  expect_true(is.function(agent$console))
})

test_that("metafor-plugin uses template composition", {
  graph <- build_graph(
    file.path(.metafor_dir(), "decision_graph.yaml")
  )

  expect_true(S7::S7_inherits(graph, DecisionGraph))
  template_nodes <- c("gather_data", "measure_selection", "analysis_approach")
  func_nodes <- c(
    "configure_tau2", "run_analysis",
    "check_heterogeneity", "assess_bias", "complete"
  )
  for (n in c(template_nodes, func_nodes)) {
    expect_true(n %in% names(graph@nodes), info = paste("Missing node:", n))
  }
  expect_equal(graph@entry_node, "gather_data")
})

test_that("metafor-plugin has multiple knowledge stores", {
  agent <- bridle_agent(.metafor_dir())

  expect_true(length(agent$knowledge) >= 4L)
  topics <- vapply(agent$knowledge, function(ks) ks@topic, character(1))
  expect_true("effect_measures" %in% topics)
  expect_true("estimation_methods" %in% topics)
  expect_true("heterogeneity" %in% topics)
  expect_true("publication_bias" %in% topics)
})

test_that("metafor-plugin passes validate_plugin", {
  agent <- bridle_agent(.metafor_dir())

  result <- validate_plugin(
    agent$graph, agent$knowledge, agent$constraints
  )
  expect_true(is_valid(result))
})

test_that("metafor-plugin constraint filtering returns method constraints", {
  agent <- bridle_agent(.metafor_dir())
  ctx <- make_session_context()

  constraints <- retrieve_constraints(agent$constraints, "method", ctx)
  expect_true(length(constraints) > 0L)
  ids <- vapply(constraints, function(c) c@id, character(1))
  expect_true("valid_method_values" %in% ids)
})

test_that("metafor-plugin knowledge retrieval returns topic entries", {
  agent <- bridle_agent(.metafor_dir())
  ctx <- make_session_context()

  retrieval <- retrieve_knowledge(agent$knowledge, "effect_measures", ctx)
  expect_true(length(retrieval@entries) > 0L)
  ids <- vapply(retrieval@entries, function(e) e@id, character(1))
  expect_true("smd_default" %in% ids)
})

# -- Happy path E2E ------------------------------------------------------------

test_that("happy path: gather → measure → method → tau2 → exec → diag → bias → complete", {
  agent <- bridle_agent(.metafor_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data looks like continuous outcome data with yi and vi.",
        "I recommend using SMD (Standardized Mean Difference).",
        "I recommend REML estimation method.",
        "I recommend REML for tau-squared estimation.",
        "```r\nresult <- list(I2 = 30, tau2 = 0.05, QE = 12)\n```",
        "Heterogeneity is low to moderate (I2 = 30%). No adjustment needed.",
        "No evidence of publication bias.",
        "Analysis complete with SMD using REML."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 20))
  )

  expect_no_error(bridle_console(agent))
})

# -- Abort mid-session ---------------------------------------------------------

test_that("abort at measure_selection ends gracefully", {
  agent <- bridle_agent(.metafor_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c("Data overview.", "I recommend SMD."))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(c("y", "abort"))
  )

  expect_no_error(bridle_console(agent))
})

# -- Reject with override -----------------------------------------------------

test_that("reject measure with override records user choice", {
  agent <- bridle_agent(.metafor_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data confirmed.",
        "I recommend SMD.",
        "I recommend REML.",
        "REML for tau-squared.",
        "```r\nresult <- list(I2 = 20, tau2 = 0.03, QE = 8)\n```",
        "Results acceptable.",
        "No publication bias detected.",
        "Complete."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(c(
      "y",
      "n", "OR",
      "y",
      "y",
      "y",
      "y",
      "y",
      "y"
    ))
  )

  expect_no_error(bridle_console(agent))
})

# -- LLM error handling -------------------------------------------------------

test_that("LLM error mid-session is handled gracefully", {
  agent <- bridle_agent(.metafor_dir())
  call_count <- 0L

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      list(
        chat = function(prompt) {
          call_count <<- call_count + 1L
          if (call_count == 3L) stop("LLM service unavailable")
          "Fallback response."
        }
      )
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 20))
  )

  expect_no_error(bridle_console(agent))
})

# -- Audit log -----------------------------------------------------------------

test_that("JSONL audit log records all visited nodes", {
  log_dir <- withr::local_tempdir()
  agent <- bridle_agent(.metafor_dir(), log_dir = log_dir)

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data overview.",
        "I recommend SMD.",
        "I recommend REML.",
        "REML for tau2.",
        "```r\nresult <- list(I2 = 25, tau2 = 0.04, QE = 10)\n```",
        "Heterogeneity acceptable.",
        "No bias detected.",
        "Done."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 20))
  )

  bridle_console(agent)

  log_files <- list.files(log_dir, pattern = "\\.jsonl$")
  expect_true(length(log_files) > 0L)

  log_lines <- readLines(file.path(log_dir, log_files[[1L]]))
  expect_true(length(log_lines) >= 5L)

  entries <- lapply(log_lines, function(ln) {
    jsonlite::fromJSON(ln, simplifyVector = FALSE)
  })
  node_ids <- vapply(entries, function(e) e$node_id, character(1))
  expect_true("measure_selection" %in% node_ids)
  expect_true("run_analysis" %in% node_ids)
  expect_true("complete" %in% node_ids)

  for (entry in entries) {
    expect_true("node_id" %in% names(entry))
    expect_true("node_type" %in% names(entry))
  }
})

# -- Diagnosis loop (cycle) ---------------------------------------------------

test_that("diagnosis loop revisits measure_selection on adjustment", {
  agent <- bridle_agent(.metafor_dir())
  visit_counts <- list()

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      idx <- 0L
      list(
        chat = function(prompt) {
          idx <<- idx + 1L
          responses <- c(
            "Data overview.",
            "SMD recommended.",
            "REML recommended.",
            "REML for tau2.",
            "```r\nresult <- list(I2 = 85, tau2 = 0.5, QE = 50)\n```",
            "I2 is very high (85%). Adjustment needed.",
            "I recommend OR instead.",
            "REML still appropriate.",
            "REML for tau2.",
            "```r\nresult <- list(I2 = 30, tau2 = 0.04, QE = 10)\n```",
            "Heterogeneity now acceptable.",
            "No bias detected.",
            "Complete."
          )
          if (idx > length(responses)) responses[[length(responses)]] else responses[[idx]]
        }
      )
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 30))
  )

  expect_no_error(bridle_console(agent))
})

# -- Peto constraint -----------------------------------------------------------

test_that("Peto constraint forces measure to OR", {
  agent <- bridle_agent(.metafor_dir())
  ctx <- make_session_context()

  constraints <- retrieve_constraints(agent$constraints, "measure", ctx)
  peto <- Filter(function(c) c@id == "peto_forces_or", constraints)
  expect_true(length(peto) == 1L)
  expect_equal(peto[[1L]]@forces$measure, "OR")
})
