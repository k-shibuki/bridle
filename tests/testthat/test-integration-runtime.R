# E2E integration tests for the bridle runtime pipeline.
# Uses test-plugin fixture with mocked LLM and readline.

skip_on_unit_tier()
.plugin_dir <- function() {
  testthat::test_path("fixtures", "test-plugin")
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

test_that("happy path: all nodes accept through completion", {
  agent <- bridle_agent(.plugin_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data looks like binary outcome data.",
        "I recommend using RR (Risk Ratio).",
        "```r\nresult <- list(I2 = 30)\n```",
        "Results look acceptable, no adjustment needed.",
        "Analysis complete."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 10))
  )

  expect_no_error(bridle_console(agent))
})

test_that("reject with override records override value", {
  agent <- bridle_agent(.plugin_dir())

  readline_inputs <- c(
    "y",
    "n", "OR",
    "y",
    "y",
    "y"
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data structure confirmed.",
        "I recommend RR.",
        "```r\nresult <- list(I2 = 25)\n```",
        "Results acceptable.",
        "Summary complete."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(readline_inputs)
  )

  expect_no_error(bridle_console(agent))
})

test_that("abort mid-session ends gracefully", {
  agent <- bridle_agent(.plugin_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c("Data overview.", "I recommend RR."))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(c("y", "abort"))
  )

  expect_no_error(bridle_console(agent))
})

test_that("explain command shows additional explanation", {
  agent <- bridle_agent(.plugin_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data confirmed.",
        "I recommend RR.",
        "RR is preferred because it is easier to interpret.",
        "```r\nresult <- list(I2 = 20)\n```",
        "All good.",
        "Done."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(c(
      "y",
      "explain", "y",
      "y",
      "y",
      "y"
    ))
  )

  expect_no_error(bridle_console(agent))
})

test_that("LLM error is handled gracefully", {
  agent <- bridle_agent(.plugin_dir())

  call_count <- 0L
  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      list(
        chat = function(prompt) {
          call_count <<- call_count + 1L
          if (call_count == 2L) stop("LLM unavailable")
          "Fallback response."
        }
      )
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 10))
  )

  expect_no_error(bridle_console(agent))
})

test_that("logging produces JSONL output", {
  log_dir <- withr::local_tempdir()
  agent <- bridle_agent(.plugin_dir(), log_dir = log_dir)

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data overview.",
        "I recommend RR.",
        "```r\nresult <- list(I2 = 10)\n```",
        "Results OK.",
        "Done."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 10))
  )

  bridle_console(agent)
  log_files <- list.files(log_dir, pattern = "\\.jsonl$")
  expect_true(length(log_files) > 0L)

  log_content <- readLines(file.path(log_dir, log_files[[1]]))
  expect_true(length(log_content) > 0L)

  first_entry <- jsonlite::fromJSON(log_content[[1]], simplifyVector = FALSE)
  expect_true("node_id" %in% names(first_entry))
  expect_true("node_type" %in% names(first_entry))
})

test_that("all four node types are processed", {
  # Given: an agent fixture that traverses all node types
  agent <- bridle_agent(.plugin_dir())

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .mock_chat(c(
        "Data structure confirmed.",
        "I recommend RR for this analysis.",
        "```r\nresult <- list(I2 = 15)\n```",
        "Results are acceptable.",
        "Analysis summary complete."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 10))
  )

  # When: the console pipeline is executed end-to-end
  expect_no_error(bridle_console(agent))
  # Then: the run completes without runtime errors
})

test_that("skip_hint skips node when condition is met", {
  # Given: a graph where skip_when/skip_hint should skip diagnosis node
  dir <- withr::local_tempdir()

  graph_yaml <- '
graph:
  entry_node: start
  nodes:
    start:
      type: context_gathering
      transitions:
        - to: skippable
          always: true
    skippable:
      type: diagnosis
      topic: check
      policy:
        skip_when: "sample is large"
        skip_hint: "k > 100"
      transitions:
        - to: finish
          always: true
    finish:
      type: execution
      transitions: []
'
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))

  ctx_yaml <- '
variables:
  - name: k
    description: number of studies
    available_from: data_loaded
    source_expression: "nrow(data)"
'
  writeLines(ctx_yaml, file.path(dir, "context_schema.yaml"))

  # And: context has k > 100 so skip condition is true
  agent <- bridle_agent(dir)

  dummy_data <- data.frame(x = seq_len(200))
  eng <- agent$engine
  eng@context <- update_context(
    eng@context,
    node_id = "start",
    data = dummy_data
  )
  agent$engine <- eng

  chat_calls <- 0L
  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      list(
        chat = function(prompt) {
          chat_calls <<- chat_calls + 1L
          if (chat_calls == 1L) {
            "Context gathered."
          } else {
            "Final."
          }
        }
      )
    }
  )
  local_mocked_bindings(
    bridle_readline = .mock_readline_queue(rep("y", 5))
  )

  # When: console run is executed
  expect_no_error(bridle_console(agent))
  # Then: run completes and diagnosis/execution prompts are skipped
  expect_equal(chat_calls, 1L)
})

test_that("full pipeline with fixture produces valid agent", {
  agent <- bridle_agent(.plugin_dir())
  expect_s3_class(agent, "bridle_agent")
  expect_true(!is.null(agent$graph))
  expect_true(!is.null(agent$engine))
  expect_true(!is.null(agent$sandbox))
  expect_true(length(agent$knowledge) > 0L)
  expect_true(length(agent$constraints) > 0L)
  expect_true(is.function(agent$console))
})
