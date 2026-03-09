# Tests for bridle_agent() and bridle_console()

.make_plugin_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  graph_yaml <- "
graph:
  entry_node: start
  nodes:
    start:
      type: decision
      topic: effect_measure
      parameter: sm
      transitions:
        - to: end
          always: true
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))

  ctx_yaml <- "
variables:
  - name: k
    description: number of studies
    available_from: data_loaded
    source_expression: nrow(data)
"
  writeLines(ctx_yaml, file.path(dir, "context_schema.yaml"))
  dir
}

test_that("bridle_agent rejects missing plugin directory", {
  expect_error(
    bridle_agent("/nonexistent/path"),
    "does not exist"
  )
})

test_that("bridle_agent rejects directory without decision_graph.yaml", {
  dir <- withr::local_tempdir()
  expect_error(
    bridle_agent(dir),
    "decision_graph.yaml"
  )
})

test_that("bridle_agent loads plugin from directory", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)
  expect_s3_class(agent, "bridle_agent")
  expect_true(!is.null(agent$engine))
  expect_true(!is.null(agent$sandbox))
  expect_null(agent$logger)
})

test_that("bridle_agent creates logger when log_dir provided", {
  dir <- .make_plugin_dir()
  log_dir <- withr::local_tempdir()
  agent <- bridle_agent(dir, log_dir = log_dir)
  expect_true(!is.null(agent$logger))
})

test_that("bridle_console rejects non-agent input", {
  expect_error(
    bridle_console(list()),
    "bridle_agent"
  )
})

test_that("bridle_readline returns user input", {
  local_mocked_bindings(bridle_readline = function(prompt) "test_input")
  expect_equal(bridle_readline("> "), "test_input")
})

test_that("console processes accept flow with mocked LLM", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)

  input_queue <- c("y", "y")
  input_idx <- 0L

  mock_chat <- list(
    chat = function(prompt) {
      "I recommend using RR (Risk Ratio) for this analysis."
    }
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) {
      input_idx <<- input_idx + 1L
      input_queue[[min(input_idx, length(input_queue))]]
    }
  )

  expect_no_error(bridle_console(agent))
})

test_that("console handles abort command", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)

  mock_chat <- list(
    chat = function(prompt) "recommendation text"
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) "abort"
  )

  expect_no_error(bridle_console(agent))
})

test_that("console handles reject with override", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)

  input_queue <- c("n", "OR", "y")
  input_idx <- 0L

  mock_chat <- list(
    chat = function(prompt) "I recommend using RR."
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) {
      input_idx <<- input_idx + 1L
      input_queue[[min(input_idx, length(input_queue))]]
    }
  )

  expect_no_error(bridle_console(agent))
})

test_that("console handles LLM error gracefully", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)

  call_count <- 0L
  mock_chat <- list(
    chat = function(prompt) {
      call_count <<- call_count + 1L
      if (call_count == 1L) stop("LLM unavailable")
      "recommendation"
    }
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) "y"
  )

  expect_no_error(bridle_console(agent))
})

test_that("console handles explain command", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)

  input_queue <- c("explain", "y", "y")
  input_idx <- 0L

  mock_chat <- list(
    chat = function(prompt) "Here is my recommendation and explanation."
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) {
      input_idx <<- input_idx + 1L
      input_queue[[min(input_idx, length(input_queue))]]
    }
  )

  expect_no_error(bridle_console(agent))
})

test_that("console with logging writes JSONL", {
  dir <- .make_plugin_dir()
  log_dir <- withr::local_tempdir()
  agent <- bridle_agent(dir, log_dir = log_dir)

  mock_chat <- list(
    chat = function(prompt) "recommendation text"
  )

  local_mocked_bindings(
    bridle_runtime_chat = function(...) mock_chat
  )
  local_mocked_bindings(
    bridle_readline = function(prompt) "y"
  )

  bridle_console(agent)
  log_files <- list.files(log_dir, pattern = "\\.jsonl$")
  expect_true(length(log_files) > 0L)
})

# -- manifest.yaml policy_defaults (Issue #149) --------------------------------

test_that("manifest policy_defaults merges into global_policy", {
  dir <- .make_plugin_dir()
  writeLines(c(
    "policy_defaults:",
    "  max_iterations: 5"
  ), file.path(dir, "manifest.yaml"))

  agent <- bridle_agent(dir)
  policy <- resolve_policy(agent$engine, "start")
  expect_equal(policy$max_iterations, 5L)
})

test_that("graph global_policy overrides manifest policy_defaults", {
  dir <- .make_plugin_dir()
  writeLines(c(
    "policy_defaults:",
    "  max_iterations: 5"
  ), file.path(dir, "manifest.yaml"))

  graph_yaml <- "
graph:
  entry_node: start
  global_policy:
    max_iterations: 3
  nodes:
    start:
      type: decision
      topic: effect_measure
      parameter: sm
      transitions:
        - to: end
          always: true
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))

  agent <- bridle_agent(dir)
  policy <- resolve_policy(agent$engine, "start")
  expect_equal(policy$max_iterations, 3L)
})

test_that("missing manifest.yaml uses built-in defaults", {
  dir <- .make_plugin_dir()
  agent <- bridle_agent(dir)
  policy <- resolve_policy(agent$engine, "start")
  expect_equal(policy$max_iterations, 10L)
})

test_that("empty policy_defaults in manifest uses built-in defaults", {
  dir <- .make_plugin_dir()
  writeLines(c(
    "policy_defaults: {}"
  ), file.path(dir, "manifest.yaml"))

  agent <- bridle_agent(dir)
  policy <- resolve_policy(agent$engine, "start")
  expect_equal(policy$max_iterations, 10L)
})

test_that("manifest with unknown fields is silently ignored", {
  dir <- .make_plugin_dir()
  writeLines(c(
    "policy_defaults:",
    "  max_iterations: 5",
    "  unknown_field: true"
  ), file.path(dir, "manifest.yaml"))

  agent <- bridle_agent(dir)
  policy <- resolve_policy(agent$engine, "start")
  expect_equal(policy$max_iterations, 5L)
})
