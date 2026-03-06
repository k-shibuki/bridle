# Tests for scan_package() Layer 1 (formals analysis)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases
# Uses local_mocked_bindings to avoid dependency on external packages

# mock_resolve, mock_version provided by helper-mocks.R

mock_empty_rd_db <- function(package) {
  rd <- list(structure(
    list(structure("testfn", Rd_tag = "TEXT")),
    Rd_tag = "\\alias"
  ))
  list("testfn.Rd" = rd)
}

with_scan_mocks <- function(fn, code) {
  local_mocked_bindings(resolve_function = mock_resolve(fn)) # nolint: object_usage_linter.
  local_mocked_bindings(get_package_version = mock_version) # nolint: object_usage_linter.
  local_mocked_bindings(get_rd_db = mock_empty_rd_db) # nolint: object_usage_linter.
  code
}

# -- scan_package() input validation ------------------------------------------

test_that("scan_package: NULL package rejected", {
  # Given: NULL as package argument
  # When:  calling scan_package
  # Then:  error about non-empty string
  expect_error(scan_package(NULL, "f"), "non-empty string")
})

test_that("scan_package: empty package rejected", {
  # Given: empty string as package
  # When:  calling scan_package
  # Then:  error about non-empty string
  expect_error(scan_package("", "f"), "non-empty string")
})

test_that("scan_package: numeric package rejected", {
  # Given: numeric as package
  # When:  calling scan_package
  # Then:  error about non-empty string
  expect_error(scan_package(42, "f"), "non-empty string")
})

test_that("scan_package: NULL func rejected", {
  # Given: NULL as func argument
  # When:  calling scan_package
  # Then:  error about non-empty string
  expect_error(scan_package("pkg", NULL), "non-empty string")
})

test_that("scan_package: empty func rejected", {
  # Given: empty string as func
  # When:  calling scan_package
  # Then:  error about non-empty string
  expect_error(scan_package("pkg", ""), "non-empty string")
})

test_that("scan_package: non-existent package rejected", {
  # Given: a package name that is not installed
  # When:  calling scan_package
  # Then:  error about package not available
  expect_error(
    scan_package("nonexistent_pkg_xyz_999", "f"),
    "not available"
  )
})

test_that("scan_package: non-existent function rejected", {
  # Given: a valid package but non-existent function
  # When:  calling scan_package with mocked resolve
  # Then:  error about function not found
  local_mocked_bindings(
    resolve_function = function(package, func) {
      cli::cli_abort(
        "Function {.fn {func}} not found in package {.pkg {package}}."
      )
    }
  )
  expect_error(
    scan_package("stats", "nonexistent_fn_xyz"),
    "not found"
  )
})

# -- scan_package() Layer 1: basic extraction ---------------------------------

test_that("scan_package: extracts parameters from simple function", {
  # Given: a function with two params (one with default, one without)
  # When:  scanning with Layer 1
  # Then:  parameters extracted correctly
  mock_fn <- function(x, y = 10) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")

  expect_s3_class(sr, "bridle::ScanResult")
  expect_equal(sr@package, "testpkg")
  expect_equal(sr@func, "testfn")
  expect_length(sr@parameters, 2L)

  p1 <- sr@parameters[[1L]]
  expect_equal(p1@name, "x")
  expect_false(p1@has_default)

  p2 <- sr@parameters[[2L]]
  expect_equal(p2@name, "y")
  expect_true(p2@has_default)
  expect_equal(p2@default_expression, "10")
})

test_that("scan_package: metadata includes layer1 and timestamp", {
  # Given: any function
  # When:  scanning
  # Then:  scan_metadata has correct layer and timestamp
  mock_fn <- function(x) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true("layer1_formals" %in% sr@scan_metadata[["layers_completed"]])
  expect_true(nchar(sr@scan_metadata[["timestamp"]]) > 0L)
})

# -- scan_package() Layer 1: dependency graph ---------------------------------

test_that("scan_package: dependency graph from ifelse default", {
  # Given: a function where `sm` default depends on `method`
  # When:  scanning with Layer 1
  # Then:  dependency graph shows method -> sm
  mock_fn <- function(method = "MH", sm = ifelse(method == "Peto", "OR", "RR")) {
    NULL
  }
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true("sm" %in% names(sr@dependency_graph))
  expect_true("method" %in% sr@dependency_graph[["sm"]])
})

test_that("scan_package: no dependency for independent params", {
  # Given: two independent parameters with literal defaults
  # When:  scanning
  # Then:  empty dependency graph
  mock_fn <- function(a = 1, b = "hello") NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_length(sr@dependency_graph, 0L)
})

test_that("scan_package: multi-param dependency detected", {
  # Given: a param that depends on two other params
  # When:  scanning
  # Then:  both dependencies captured
  mock_fn <- function(a = 1, b = 2, c = a + b) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true("c" %in% names(sr@dependency_graph))
  deps <- sr@dependency_graph[["c"]]
  expect_true("a" %in% deps)
  expect_true("b" %in% deps)
})

test_that("scan_package: self-reference excluded from dep graph", {
  # Given: a default expression that references the param's own name
  #        (not meaningful but should not create self-loop)
  # When:  scanning
  # Then:  self-reference not in dependencies
  mock_fn <- function(x = x + 1) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_false("x" %in% names(sr@dependency_graph))
})

# -- scan_package() Layer 1: parameter classification -------------------------

test_that("scan_package: data_input classification for data params", {
  # Given: parameters matching data_input patterns
  # When:  scanning
  # Then:  classified as data_input
  # nolint start: object_name_linter. Mimics real R package parameter names.
  mock_fn <- function(event.e = NULL, n.e = NULL, data = NULL) NULL
  # nolint end
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  classes <- vapply(sr@parameters, function(p) p@classification, character(1))
  names(classes) <- vapply(sr@parameters, function(p) p@name, character(1))
  expect_equal(classes[["event.e"]], "data_input")
  expect_equal(classes[["n.e"]], "data_input")
  expect_equal(classes[["data"]], "data_input")
})

test_that("scan_package: statistical_decision classification", {
  # Given: parameters matching statistical patterns
  # When:  scanning
  # Then:  classified as statistical_decision
  mock_fn <- function(method = "MH", sm = "OR", random = FALSE) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  classes <- vapply(sr@parameters, function(p) p@classification, character(1))
  names(classes) <- vapply(sr@parameters, function(p) p@name, character(1))
  expect_equal(classes[["method"]], "statistical_decision")
  expect_equal(classes[["sm"]], "statistical_decision")
  expect_equal(classes[["random"]], "statistical_decision")
})

test_that("scan_package: presentation classification", {
  # Given: parameters matching presentation patterns
  # When:  scanning
  # Then:  classified as presentation
  mock_fn <- function(digits = 2, label.e = "exp", title = "My plot") NULL # nolint: object_name_linter.
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  classes <- vapply(sr@parameters, function(p) p@classification, character(1))
  names(classes) <- vapply(sr@parameters, function(p) p@name, character(1))
  expect_equal(classes[["digits"]], "presentation")
  expect_equal(classes[["label.e"]], "presentation")
  expect_equal(classes[["title"]], "presentation")
})

test_that("scan_package: dots classified as unknown", {
  # Given: a function with ... parameter
  # When:  scanning
  # Then:  ... classified as unknown
  mock_fn <- function(x, ...) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  dots_param <- Filter(
    function(p) p@name == "...",
    sr@parameters
  )
  expect_length(dots_param, 1L)
  expect_equal(dots_param[[1L]]@classification, "unknown")
})

# -- scan_package() Layer 1: constraint extraction ----------------------------

test_that("scan_package: constraint extracted from ifelse default", {
  # Given: a conditional default via ifelse
  # When:  scanning
  # Then:  a forces constraint is created
  mock_fn <- function(method = "MH", sm = ifelse(method == "Peto", "OR", "RR")) {
    NULL
  }
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true(length(sr@constraints) >= 1L)
  cst <- sr@constraints[[1L]]
  expect_equal(cst@type, "forces")
  expect_equal(cst@source, "formals_default")
  expect_equal(cst@param, "sm")
  expect_equal(cst@confidence, "medium")
})

test_that("scan_package: no constraints for literal defaults", {
  # Given: a function with only literal defaults (no conditionals)
  # When:  scanning
  # Then:  no constraints extracted
  mock_fn <- function(a = 1, b = "hello") NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_length(sr@constraints, 0L)
})

test_that("scan_package: constraint from switch default", {
  # Given: a default using switch()
  # When:  scanning
  # Then:  a forces constraint is created
  switch_default <- quote(switch(type,
    a = 1,
    b = 2
  ))
  mock_fn <- function(type = "a", val = NULL) NULL
  formals(mock_fn)$val <- switch_default
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true(length(sr@constraints) >= 1L)
  cst <- sr@constraints[[1L]]
  expect_equal(cst@type, "forces")
  expect_equal(cst@param, "val")
})

# -- scan_package() Layer 1: edge cases ---------------------------------------

test_that("scan_package: function with no formals", {
  # Given: a function with no parameters
  # When:  scanning
  # Then:  returns ScanResult with placeholder parameter, no error
  mock_fn <- function() NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_s3_class(sr, "bridle::ScanResult")
  expect_length(sr@parameters, 1L)
  expect_equal(sr@parameters[[1L]]@name, "..none..")
})

test_that("scan_package: deeply nested conditional default", {
  # Given: a parameter with deeply nested ifelse
  # When:  scanning
  # Then:  dependency detected (may not capture all details)
  mock_fn <- function(
    a = "x",
    b = ifelse(a == "x", ifelse(a == "y", 1, 2), 3)
  ) {
    NULL
  }
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = mock_empty_rd_db)

  sr <- scan_package("testpkg", "testfn")
  expect_true("b" %in% names(sr@dependency_graph))
  expect_true("a" %in% sr@dependency_graph[["b"]])
  expect_true(length(sr@constraints) >= 1L)
})

# -- walk_ast_symbols() -------------------------------------------------------

test_that("walk_ast_symbols: extracts symbol from simple expression", {
  # Given: a simple expression referencing a variable
  # When:  walking the AST
  # Then:  the variable name is returned
  expr <- quote(x + 1)
  syms <- bridle:::walk_ast_symbols(expr)
  expect_true("x" %in% syms)
})

test_that("walk_ast_symbols: handles NULL", {
  # Given: NULL expression
  # When:  walking the AST
  # Then:  empty character vector
  expect_equal(bridle:::walk_ast_symbols(NULL), character(0))
})

test_that("walk_ast_symbols: handles numeric literal", {
  # Given: a plain numeric value
  # When:  walking the AST
  # Then:  empty character vector
  expect_equal(bridle:::walk_ast_symbols(42), character(0))
})

test_that("walk_ast_symbols: extracts multiple symbols", {
  # Given: an expression referencing multiple variables
  # When:  walking the AST
  # Then:  all variables returned
  expr <- quote(a + b * c)
  syms <- bridle:::walk_ast_symbols(expr)
  expect_true(all(c("a", "b", "c") %in% syms))
})

test_that("walk_ast_symbols: handles nested calls", {
  # Given: nested function calls
  # When:  walking the AST
  # Then:  variables from all levels extracted
  expr <- quote(ifelse(x == "a", y, z))
  syms <- bridle:::walk_ast_symbols(expr)
  expect_true(all(c("x", "y", "z") %in% syms))
})

# -- classify_parameter() -----------------------------------------------------

test_that("classify_parameter: unknown for unrecognized name", {
  # Given: a parameter name matching no pattern
  # When:  classifying
  # Then:  returns "unknown"
  result <- bridle:::classify_parameter("foobar", quote(1), TRUE)
  expect_equal(result, "unknown")
})

test_that("classify_parameter: dots always unknown", {
  # Given: the ... parameter
  # When:  classifying
  # Then:  returns "unknown"
  result <- bridle:::classify_parameter("...", NULL, FALSE)
  expect_equal(result, "unknown")
})

# -- safe_deparse() -----------------------------------------------------------

test_that("safe_deparse: handles long expressions", {
  # Given: a very long expression
  # When:  deparsing
  # Then:  single string returned
  long_expr <- parse(text = paste0("x + ", paste(rep("y", 100), collapse = " + ")))[[1L]]
  result <- bridle:::safe_deparse(long_expr)
  expect_true(is.character(result))
  expect_length(result, 1L)
})

test_that("safe_deparse: handles simple values", {
  # Given: a simple numeric
  # When:  deparsing
  # Then:  string "42"
  result <- bridle:::safe_deparse(42)
  expect_equal(result, "42")
})
