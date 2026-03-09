# Tests for scan_package() Layer 3a (source code static analysis)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# setup_all_mocks, mock_resolve, mock_version, mock_rd_for
# provided by helper-mocks.R

# -- collect_calls() ----------------------------------------------------------

test_that("collect_calls: finds match.arg calls", {
  # Given: a function body with match.arg
  # When:  collecting match.arg calls
  # Then:  returns the call
  fn <- function(method = c("MH", "Inverse")) {
    method <- match.arg(method)
    method
  }
  calls <- bridle:::collect_calls(body(fn), "match.arg")
  expect_length(calls, 1L)
})

test_that("collect_calls: finds nested match.arg", {
  # Given: match.arg inside an if block
  # When:  collecting calls
  # Then:  still found
  fn <- function(method = c("A", "B")) {
    if (TRUE) {
      method <- match.arg(method)
    }
    method
  }
  calls <- bridle:::collect_calls(body(fn), "match.arg")
  expect_length(calls, 1L)
})

test_that("collect_calls: returns empty for no match", {
  # Given: function body without match.arg
  # When:  collecting calls
  # Then:  empty list
  fn <- function(x = 1) x + 1
  calls <- bridle:::collect_calls(body(fn), "match.arg")
  expect_length(calls, 0L)
})

# -- parse_match_arg() --------------------------------------------------------

test_that("parse_match_arg: extracts explicit choices", {
  # Given: match.arg(method, c("A", "B", "C"))
  # When:  parsing
  # Then:  returns param and values
  fmls <- formals(function(method = "A") NULL)
  call_expr <- quote(match.arg(method, c("A", "B", "C")))
  info <- bridle:::parse_match_arg(call_expr, fmls, "method")
  expect_equal(info$param, "method")
  expect_equal(info$values, c("A", "B", "C"))
})

test_that("parse_match_arg: extracts values from formal default", {
  # Given: match.arg(method) where method has default c("A", "B")
  # When:  parsing
  # Then:  returns values from formal
  fmls <- formals(function(method = c("A", "B")) NULL)
  call_expr <- quote(match.arg(method))
  info <- bridle:::parse_match_arg(call_expr, fmls, "method")
  expect_equal(info$param, "method")
  expect_equal(info$values, c("A", "B"))
})

test_that("parse_match_arg: returns NULL for non-param symbol", {
  # Given: match.arg on a non-parameter variable
  # When:  parsing
  # Then:  returns NULL
  fmls <- formals(function(x = 1) NULL)
  call_expr <- quote(match.arg(y))
  info <- bridle:::parse_match_arg(call_expr, fmls, "x")
  expect_null(info)
})

test_that("parse_match_arg: returns NULL for empty call", {
  # Given: match.arg()
  # When:  parsing
  # Then:  returns NULL
  fmls <- formals(function(x = 1) NULL)
  call_expr <- quote(match.arg())
  info <- bridle:::parse_match_arg(call_expr, fmls, "x")
  expect_null(info)
})

# -- extract_char_vector() ----------------------------------------------------

test_that("extract_char_vector: from c() expression", {
  # Given: c("A", "B", "C")
  # When:  extracting
  # Then:  returns character vector
  expr <- quote(c("A", "B", "C"))
  values <- bridle:::extract_char_vector(expr)
  expect_equal(values, c("A", "B", "C"))
})

test_that("extract_char_vector: from plain character", {
  # Given: a character string
  # When:  extracting
  # Then:  returns it
  values <- bridle:::extract_char_vector("hello")
  expect_equal(values, "hello")
})

test_that("extract_char_vector: non-c() call returns empty", {
  # Given: a non-c() call expression
  # When:  extracting
  # Then:  returns empty
  expr <- quote(paste("A", "B"))
  values <- bridle:::extract_char_vector(expr)
  expect_equal(values, character(0))
})

# -- collect_conditional_stops() -----------------------------------------------

test_that("collect_conditional_stops: finds stop in if-block", {
  # Given: function with if(param check) stop(...)
  # When:  collecting conditional stops
  # Then:  returns the stop with param reference
  fn <- function(method = "A") {
    if (method == "invalid") stop("invalid method")
    method
  }
  results <- bridle:::collect_conditional_stops(body(fn), "method")
  expect_true(length(results) >= 1L)
  expect_equal(results[[1L]]$param, "method")
})

test_that("collect_conditional_stops: ignores stop without param", {
  # Given: function with if(TRUE) stop(...)
  # When:  collecting conditional stops
  # Then:  returns empty (no param reference in condition)
  fn <- function(x = 1) {
    if (TRUE) stop("always stops")
    x
  }
  results <- bridle:::collect_conditional_stops(body(fn), "x")
  expect_length(results, 0L)
})

test_that("collect_conditional_stops: extracts message", {
  # Given: stop with a message string
  # When:  collecting
  # Then:  message is extracted
  fn <- function(sm = "OR") {
    if (sm == "bad") stop("sm must be valid")
    sm
  }
  results <- bridle:::collect_conditional_stops(body(fn), "sm")
  expect_true(length(results) >= 1L)
  expect_equal(results[[1L]]$message, "sm must be valid")
})

# -- extract_stop_message() ----------------------------------------------------

test_that("extract_stop_message: extracts string argument", {
  # Given: stop("message here")
  # When:  extracting message
  # Then:  returns the string
  call_expr <- quote(stop("error occurred"))
  msg <- bridle:::extract_stop_message(call_expr)
  expect_equal(msg, "error occurred")
})

test_that("extract_stop_message: falls back to deparsed call", {
  # Given: stop(paste("a", "b"))
  # When:  extracting message
  # Then:  returns deparsed call expression
  call_expr <- quote(stop(paste("a", "b")))
  msg <- bridle:::extract_stop_message(call_expr)
  expect_true(grepl("paste", msg))
})

# -- upgrade_confidence() -----------------------------------------------------

test_that("upgrade_confidence: high when 2+ layers confirm", {
  # Given: a constraint confirmed by formals, with match.arg also found
  # When:  upgrading confidence
  # Then:  confidence becomes high
  cst <- Constraint(
    id = "c1", source = "formals_default", type = "forces",
    param = "method", condition = "method == 'A'",
    forces = list(sm = "OR"),
    confirmed_by = "formals_default", confidence = "medium"
  )
  result <- bridle:::upgrade_confidence(
    list(cst),
    ma_values = list(method = c("A", "B")),
    rd_valid_values = list(),
    stop_constraints = list()
  )
  expect_equal(result[[1L]]@confidence, "high")
  expect_true("source_code" %in% result[[1L]]@confirmed_by)
})

test_that("upgrade_confidence: stays medium with single layer", {
  # Given: a constraint with only one confirmation source
  # When:  upgrading (no match.arg or Rd)
  # Then:  confidence stays medium
  cst <- Constraint(
    id = "c1", source = "formals_default", type = "forces",
    param = "method", condition = "cond",
    forces = list(sm = "OR"),
    confirmed_by = "formals_default", confidence = "medium"
  )
  result <- bridle:::upgrade_confidence(
    list(cst),
    ma_values = list(),
    rd_valid_values = list(),
    stop_constraints = list()
  )
  expect_equal(result[[1L]]@confidence, "medium")
})

test_that("upgrade_confidence: adds rd_description confirmation", {
  # Given: constraint + Rd valid values for same param
  # When:  upgrading
  # Then:  rd_description added to confirmed_by, confidence high
  cst <- Constraint(
    id = "c1", source = "formals_default", type = "forces",
    param = "sm", condition = "cond",
    forces = list(method = "A"),
    confirmed_by = "formals_default", confidence = "medium"
  )
  result <- bridle:::upgrade_confidence(
    list(cst),
    ma_values = list(),
    rd_valid_values = list(sm = c("RR", "OR")),
    stop_constraints = list()
  )
  expect_true("rd_description" %in% result[[1L]]@confirmed_by)
  expect_equal(result[[1L]]@confidence, "high")
})

# -- merge_valid_values() -----------------------------------------------------

test_that("merge_valid_values: combines new with existing", {
  # Given: existing values for param A, new values for A and B
  # When:  merging
  # Then:  A gets union, B is added
  existing <- list(method = c("A", "B"))
  new_vals <- list(method = c("B", "C"), sm = c("RR", "OR"))
  result <- bridle:::merge_valid_values(existing, new_vals)
  expect_equal(sort(result$method), c("A", "B", "C"))
  expect_equal(result$sm, c("RR", "OR"))
})

test_that("merge_valid_values: handles empty inputs", {
  # Given: empty existing and new
  # When:  merging
  # Then:  returns empty list
  result <- bridle:::merge_valid_values(list(), list())
  expect_equal(result, list())
})

# -- scan_layer3a() integration tests -----------------------------------------

test_that("scan_layer3a: detects match.arg valid values", {
  # Given: function with match.arg
  # When:  running full scan
  # Then:  valid_values populated from match.arg
  mock_fn <- function(method = c("MH", "Inverse", "Peto")) {
    method <- match.arg(method)
    method
  }
  m <- setup_all_mocks(mock_fn)
  local_mocked_bindings(resolve_function = m$resolve) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_package_version = m$version) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_rd_db = m$rd) # nolint: object_usage_linter. mock binding

  sr <- bridle:::scan_function("testpkg", "testfn")

  expect_true("layer3a_source" %in% sr@scan_metadata[["layers_completed"]])
  expect_true("method" %in% names(sr@valid_values))
  expect_true("MH" %in% sr@valid_values[["method"]])
  expect_true("Inverse" %in% sr@valid_values[["method"]])
})

test_that("scan_layer3a: extracts stop constraint", {
  # Given: function with if(param) stop(...)
  # When:  running full scan
  # Then:  constraint extracted from stop
  mock_fn <- function(sm = "OR") {
    if (sm == "invalid") stop("sm must be a valid measure")
    sm
  }
  m <- setup_all_mocks(mock_fn)
  local_mocked_bindings(resolve_function = m$resolve) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_package_version = m$version) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_rd_db = m$rd) # nolint: object_usage_linter. mock binding

  sr <- bridle:::scan_function("testpkg", "testfn")

  stop_csts <- Filter(
    function(c) c@source == "source_code",
    sr@constraints
  )
  expect_true(length(stop_csts) >= 1L)
  expect_equal(stop_csts[[1L]]@param, "sm")
  expect_equal(stop_csts[[1L]]@message, "sm must be a valid measure")
})

test_that("scan_layer3a: confidence upgraded to high with cross-layer", {
  # Given: function where method has Rd valid values (L2) + match.arg (L3a)
  #        and sm has a conditional default depending on method (L1)
  # When:  running full scan
  # Then:  the formals constraint on sm gets rd_description confirmation
  #        because sm depends on method which has Rd values
  mock_fn <- function(
    method = c("MH", "Inverse"),
    sm = ifelse(method == "Peto", "OR", "RR")
  ) {
    method <- match.arg(method)
    sm
  }
  rd_db <- mock_rd_for("testfn", list(
    method = 'One of "MH", "Inverse".',
    sm = 'One of "RR", "OR", "RD".'
  ))
  m <- setup_all_mocks(mock_fn, rd_db)
  local_mocked_bindings(resolve_function = m$resolve) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_package_version = m$version) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_rd_db = m$rd) # nolint: object_usage_linter. mock binding

  sr <- bridle:::scan_function("testpkg", "testfn")

  formals_csts <- Filter(
    function(c) c@source == "formals_default",
    sr@constraints
  )
  expect_true(length(formals_csts) >= 1L)
  sm_cst <- Filter(function(c) c@param == "sm", formals_csts)
  expect_true(length(sm_cst) >= 1L)
  expect_true("rd_description" %in% sm_cst[[1L]]@confirmed_by)
  expect_equal(sm_cst[[1L]]@confidence, "high")
})

test_that("scan_layer3a: no source access returns gracefully", {
  # Given: a primitive function (no body)
  # When:  running scan
  # Then:  Layer 3a skipped, previous layers preserved
  mock_fn <- sum
  m <- setup_all_mocks(mock_fn)
  local_mocked_bindings(resolve_function = m$resolve) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_package_version = m$version) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_rd_db = m$rd) # nolint: object_usage_linter. mock binding

  expect_warning(
    sr <- bridle:::scan_function("testpkg", "testfn"),
    "Cannot access source"
  )
  expect_true("layer1_formals" %in% sr@scan_metadata[["layers_completed"]])
})

test_that("scan_layer3a: gap marking for unparseable source", {
  # Given: function with only literal body
  # When:  running full scan
  # Then:  Layer 3a completes with no additional constraints
  mock_fn <- function(x = 1, y = 2) x + y
  m <- setup_all_mocks(mock_fn)
  local_mocked_bindings(resolve_function = m$resolve) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_package_version = m$version) # nolint: object_usage_linter. mock binding
  local_mocked_bindings(get_rd_db = m$rd) # nolint: object_usage_linter. mock binding

  sr <- bridle:::scan_function("testpkg", "testfn")

  expect_true("layer3a_source" %in% sr@scan_metadata[["layers_completed"]])
  stop_csts <- Filter(
    function(c) c@source == "source_code",
    sr@constraints
  )
  expect_length(stop_csts, 0L)
})
