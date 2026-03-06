# Tests for DecisionLogger S7 class (ADR-0006)

# -- S7 Constructor -----------------------------------------------------------

test_that("DecisionLogger constructs with defaults", {
  logger <- DecisionLogger(session_id = "test-123", log_path = tempfile())
  expect_true(S7::S7_inherits(logger, DecisionLogger))
  expect_equal(logger@turn_counter, 0L)
  expect_true(logger@enabled)
})

test_that("DecisionLogger rejects empty session_id", {
  expect_error(
    DecisionLogger(session_id = "", log_path = tempfile()),
    "non-empty"
  )
})

test_that("DecisionLogger disabled does not write", {
  path <- tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path, enabled = FALSE)
  logger <- log_visit(logger, "n1", "decision",
    transition_trace = list(
      candidates = list(), selected_transition = "n2", selection_basis = "hint"
    )
  )
  expect_false(file.exists(path))
  expect_equal(logger@turn_counter, 0L)
})

# -- log_visit() --------------------------------------------------------------

test_that("log_visit writes one JSONL line", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  logger <- log_visit(logger, "node_a", "decision",
    transition_trace = list(
      candidates = list(),
      selected_transition = "node_b",
      selection_basis = "hint"
    )
  )
  lines <- readLines(path)
  expect_equal(length(lines), 1L)
  expect_equal(logger@turn_counter, 1L)
})

test_that("log_visit writes schema-conformant JSON", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  logger <- log_visit(logger, "node_a", "decision",
    transition_trace = list(
      candidates = list(),
      selected_transition = "node_b",
      selection_basis = "hint"
    ),
    plugin_name = "test.plugin",
    plugin_version = "0.1.0",
    graph_version = "sha256:abc"
  )
  entry <- jsonlite::fromJSON(readLines(path), simplifyVector = FALSE)
  expect_equal(entry$meta$session_id, "s1")
  expect_equal(entry$meta$turn_id, 1L)
  expect_equal(entry$meta$plugin_name, "test.plugin")
  expect_equal(entry$node_id, "node_a")
  expect_equal(entry$node_type, "decision")
  expect_true(grepl(
    "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$",
    entry$meta$timestamp_utc
  ))
})

test_that("log_visit includes all optional fields when provided", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  logger <- log_visit(logger, "node_a", "decision",
    transition_trace = list(
      candidates = list(), selected_transition = "n2", selection_basis = "hint"
    ),
    constraints_trace = list(list(id = "c1", fired = TRUE)),
    knowledge_context = list(entry_ids_presented = c("e1", "e2")),
    llm_output = list(recommendation_text = "Use RR", suggested_value = "RR"),
    user_response = list(outcome = "accepted"),
    decision_state = list(parameters_decided = list(sm = "RR")),
    policy_applied = list(skipped = FALSE, iteration_count = 1L)
  )
  entry <- jsonlite::fromJSON(readLines(path), simplifyVector = FALSE)
  expect_equal(entry$llm_output$suggested_value, "RR")
  expect_equal(entry$user_response$outcome, "accepted")
  expect_false(entry$policy_applied$skipped)
})

test_that("turn_id increments across multiple visits", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision", transition_trace = trace)
  logger <- log_visit(logger, "n2", "execution", transition_trace = trace)
  logger <- log_visit(logger, "n3", "diagnosis", transition_trace = trace)

  lines <- readLines(path)
  expect_equal(length(lines), 3L)
  expect_equal(logger@turn_counter, 3L)

  entries <- lapply(lines, function(l) jsonlite::fromJSON(l, simplifyVector = FALSE))
  expect_equal(entries[[1]]$meta$turn_id, 1L)
  expect_equal(entries[[2]]$meta$turn_id, 2L)
  expect_equal(entries[[3]]$meta$turn_id, 3L)
})

test_that("JSONL format readable by stream_in", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision", transition_trace = trace)
  logger <- log_visit(logger, "n2", "execution", transition_trace = trace)
  logger <- log_visit(logger, "n3", "decision", transition_trace = trace)

  con <- file(path, "r")
  on.exit(close(con))
  df <- jsonlite::stream_in(con, verbose = FALSE)
  expect_equal(nrow(df), 3L)
})

test_that("timestamp uses UTC format", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision", transition_trace = trace)

  entry <- jsonlite::fromJSON(readLines(path), simplifyVector = FALSE)
  ts <- entry$meta$timestamp_utc
  expect_true(endsWith(ts, "Z"))
  parsed <- as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  expect_false(is.na(parsed))
})

# -- analyze_log() ------------------------------------------------------------

test_that("analyze_log handles empty file", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  file.create(path)
  result <- analyze_log(path)
  expect_equal(result$n_visits, 0L)
  expect_equal(length(result$override_rate_by_node), 0L)
  expect_equal(result$fallback_rate, 0)
})

test_that("analyze_log computes override rate", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision",
    transition_trace = trace,
    user_response = list(outcome = "accepted")
  )
  logger <- log_visit(logger, "n1", "decision",
    transition_trace = trace,
    user_response = list(outcome = "rejected", override_value = "OR")
  )
  logger <- log_visit(logger, "n1", "decision",
    transition_trace = trace,
    user_response = list(outcome = "accepted")
  )

  result <- analyze_log(path)
  expect_equal(result$n_visits, 3L)
  expect_equal(result$override_rate_by_node$n1, 1 / 3)
})

test_that("analyze_log handles single line", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision", transition_trace = trace)
  result <- analyze_log(path)
  expect_equal(result$n_visits, 1L)
})

test_that("analyze_log reports missing file", {
  expect_error(analyze_log("/nonexistent/path.jsonl"), "not found")
})

# -- Crash resistance ---------------------------------------------------------

test_that("partial writes leave existing lines readable", {
  path <- withr::local_tempfile(fileext = ".jsonl")
  logger <- DecisionLogger(session_id = "s1", log_path = path)
  trace <- list(
    candidates = list(), selected_transition = "n2", selection_basis = "hint"
  )
  logger <- log_visit(logger, "n1", "decision", transition_trace = trace)
  logger <- log_visit(logger, "n2", "execution", transition_trace = trace)

  write("{ broken json", file = path, append = TRUE)

  result <- analyze_log(path)
  expect_equal(result$n_visits, 2L)
})

test_that("log_visit rejects non-DecisionLogger", {
  expect_error(
    log_visit(list(), "n1", "decision", transition_trace = list()),
    "DecisionLogger"
  )
})
