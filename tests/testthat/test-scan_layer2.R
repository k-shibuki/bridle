# Tests for scan_package() Layer 2 (Rd documentation analysis)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# mock_resolve, mock_version, make_rd_*, make_mock_rd provided by helper-mocks.R

# -- rd_text() ----------------------------------------------------------------

test_that("rd_text: handles plain character", {
  # Given: a simple character string
  # When:  converting to text
  # Then:  returns the string as-is
  expect_equal(bridle:::rd_text("hello"), "hello")
})

test_that("rd_text: handles nested list", {
  # Given: nested Rd structure
  # When:  converting to text
  # Then:  concatenates all text content
  nested <- list("hello ", list(" world"))
  expect_equal(bridle:::rd_text(nested), "hello  world")
})

test_that("rd_text: handles NULL", {
  # Given: NULL input
  # When:  converting to text
  # Then:  returns empty string
  expect_equal(bridle:::rd_text(NULL), "")
})

# -- get_rd_aliases() ----------------------------------------------------------

test_that("get_rd_aliases: extracts aliases", {
  # Given: an Rd object with alias tags
  # When:  getting aliases
  # Then:  returns all alias names
  rd <- list(
    make_rd_alias("myfunc"),
    make_rd_alias("my_func")
  )
  aliases <- bridle:::get_rd_aliases(rd)
  expect_equal(aliases, c("myfunc", "my_func"))
})

test_that("get_rd_aliases: returns empty for no aliases", {
  # Given: an Rd object with no alias tags
  # When:  getting aliases
  # Then:  returns empty character
  rd <- list(make_rd_arguments())
  aliases <- bridle:::get_rd_aliases(rd)
  expect_equal(aliases, character(0))
})

# -- find_function_rd() --------------------------------------------------------

test_that("find_function_rd: finds by exact Rd name", {
  # Given: an Rd database with a matching Rd name
  # When:  finding function Rd
  # Then:  returns the matching Rd object
  rd_obj <- make_mock_rd("myfunc", list(x = "A parameter"))
  rd_db <- list("myfunc.Rd" = rd_obj)
  result <- bridle:::find_function_rd(rd_db, "myfunc")
  expect_identical(result, rd_obj)
})

test_that("find_function_rd: finds by alias", {
  # Given: an Rd database where function is an alias but not the Rd name
  # When:  finding function Rd
  # Then:  returns the Rd object with matching alias
  rd_obj <- make_mock_rd("myfunc", list(x = "A parameter"))
  rd_db <- list("othername.Rd" = rd_obj)
  result <- bridle:::find_function_rd(rd_db, "myfunc")
  expect_identical(result, rd_obj)
})

test_that("find_function_rd: returns NULL when not found", {
  # Given: an Rd database without the target function
  # When:  finding function Rd
  # Then:  returns NULL
  rd_db <- list("other.Rd" = make_mock_rd("other"))
  result <- bridle:::find_function_rd(rd_db, "myfunc")
  expect_null(result)
})

# -- extract_rd_param_descriptions() -------------------------------------------

test_that("extract_rd_param_descriptions: extracts descriptions", {
  # Given: an Rd object with \\arguments section
  # When:  extracting parameter descriptions
  # Then:  returns named list of descriptions
  rd <- make_mock_rd("f", list(
    method = "The statistical method to use.",
    sm = "Summary measure. One of \"RR\", \"OR\", \"RD\"."
  ))
  descs <- bridle:::extract_rd_param_descriptions(rd)
  expect_equal(descs[["method"]], "The statistical method to use.")
  expect_true(grepl("Summary measure", descs[["sm"]]))
})

test_that("extract_rd_param_descriptions: returns empty for no arguments", {
  # Given: an Rd object without \\arguments section
  # When:  extracting descriptions
  # Then:  returns empty list
  rd <- list(make_rd_alias("f"))
  descs <- bridle:::extract_rd_param_descriptions(rd)
  expect_equal(descs, list())
})

# -- extract_values_from_text() ------------------------------------------------

test_that("extract_values_from_text: 'one of' with quoted values", {
  # Given: description with "one of" pattern
  # When:  extracting values
  # Then:  returns the enumerated values
  text <- 'One of "RR", "OR", "RD".'
  values <- bridle:::extract_values_from_text(text)
  expect_equal(values, c("RR", "OR", "RD"))
})

test_that("extract_values_from_text: 'must be' pattern", {
  # Given: description with "must be" pattern
  # When:  extracting values
  # Then:  returns the values
  text <- 'Must be "Inverse" or "MH".'
  values <- bridle:::extract_values_from_text(text)
  expect_true(length(values) >= 2L)
  expect_true("Inverse" %in% values)
  expect_true("MH" %in% values)
})

test_that("extract_values_from_text: 'possible values' pattern", {
  # Given: description with "possible values" pattern
  # When:  extracting values
  # Then:  returns the values
  text <- 'Possible values are "A", "B", "C".'
  values <- bridle:::extract_values_from_text(text)
  expect_equal(values, c("A", "B", "C"))
})

test_that("extract_values_from_text: unquoted comma-separated values", {
  # Given: description with unquoted values after "one of"
  # When:  extracting values
  # Then:  returns the bare values
  text <- "One of Inverse, MH, Peto."
  values <- bridle:::extract_values_from_text(text)
  expect_true(length(values) >= 2L)
})

test_that("extract_values_from_text: no enumeration pattern", {
  # Given: description without enumeration patterns
  # When:  extracting values
  # Then:  returns empty character
  text <- "The number of iterations for the algorithm."
  values <- bridle:::extract_values_from_text(text)
  expect_equal(values, character(0))
})

test_that("extract_values_from_text: empty string", {
  # Given: empty description
  # When:  extracting values
  # Then:  returns empty character
  values <- bridle:::extract_values_from_text("")
  expect_equal(values, character(0))
})

# -- extract_rd_valid_values() ----------------------------------

test_that("extract_rd_valid_values: multiple params", {
  # Given: descriptions with enumeration patterns for some params
  # When:  extracting valid values
  # Then:  returns values only for params with patterns
  descs <- list(
    method = 'One of "MH", "Inverse", "Peto".',
    sm = "Summary measure (numeric).",
    type = 'Must be "fixed" or "random".'
  )
  vals <- bridle:::extract_rd_valid_values(descs)
  expect_true("method" %in% names(vals))
  expect_true("type" %in% names(vals))
  expect_false("sm" %in% names(vals))
})

# -- extract_rd_references() ---------------------------------------------------

test_that("extract_rd_references: extracts references", {
  # Given: an Rd object with \\references section
  # When:  extracting references
  # Then:  returns character vector of references
  rd <- make_mock_rd("f", references = "Author A (2020). Title.\n\nAuthor B (2021). Title 2.")
  refs <- bridle:::extract_rd_references(rd)
  expect_length(refs, 2L)
  expect_true(grepl("Author A", refs[[1L]]))
  expect_true(grepl("Author B", refs[[2L]]))
})

test_that("extract_rd_references: returns empty for no references", {
  # Given: an Rd object without \\references
  # When:  extracting references
  # Then:  returns empty character vector
  rd <- list(make_rd_alias("f"))
  refs <- bridle:::extract_rd_references(rd)
  expect_equal(refs, character(0))
})

test_that("extract_rd_references: handles empty references section", {
  # Given: an Rd object with empty \\references
  # When:  extracting references
  # Then:  returns empty character vector
  rd <- make_mock_rd("f", references = "   ")
  refs <- bridle:::extract_rd_references(rd)
  expect_equal(refs, character(0))
})

# -- detect_rd_deprecated() ----------------------------------------------------

test_that("detect_rd_deprecated: detects deprecated keyword", {
  # Given: descriptions with "deprecated" keyword
  # When:  detecting deprecated params
  # Then:  returns the deprecated parameter names
  descs <- list(
    method = "The method to use.",
    old_param = "Deprecated. Use new_param instead.",
    new_param = "The new parameter."
  )
  deprecated <- bridle:::detect_rd_deprecated(descs)
  expect_equal(deprecated, "old_param")
})

test_that("detect_rd_deprecated: case insensitive", {
  # Given: descriptions with "DEPRECATED" in uppercase
  # When:  detecting deprecated params
  # Then:  still detects it
  descs <- list(old = "DEPRECATED since version 2.0.")
  deprecated <- bridle:::detect_rd_deprecated(descs)
  expect_equal(deprecated, "old")
})

test_that("detect_rd_deprecated: no deprecated params", {
  # Given: descriptions without deprecated keywords
  # When:  detecting deprecated params
  # Then:  returns empty character
  descs <- list(method = "A method.", sm = "Summary measure.")
  deprecated <- bridle:::detect_rd_deprecated(descs)
  expect_equal(deprecated, character(0))
})

# -- update_deprecated_params() ---------------------------------------

test_that("update_deprecated_params: updates classification", {
  # Given: parameters with non-deprecated classification and deprecated list
  # When:  updating classifications
  # Then:  deprecated params get "deprecated" classification
  params <- list(
    ParameterInfo(name = "x", has_default = TRUE, classification = "unknown"),
    ParameterInfo(name = "y", has_default = TRUE, classification = "statistical_decision")
  )
  result <- bridle:::update_deprecated_params(params, "x")
  expect_equal(result[[1L]]@classification, "deprecated")
  expect_equal(result[[2L]]@classification, "statistical_decision")
})

test_that("update_deprecated_params: no-op when empty", {
  # Given: empty deprecated list
  # When:  updating classifications
  # Then:  parameters unchanged
  params <- list(
    ParameterInfo(name = "x", has_default = TRUE, classification = "unknown")
  )
  result <- bridle:::update_deprecated_params(params, character(0))
  expect_equal(result[[1L]]@classification, "unknown")
})

test_that("update_deprecated_params: preserves already deprecated", {
  # Given: a parameter already classified as deprecated
  # When:  updating with same param in deprecated list
  # Then:  stays deprecated (no change)
  params <- list(
    ParameterInfo(name = "x", has_default = TRUE, classification = "deprecated")
  )
  result <- bridle:::update_deprecated_params(params, "x")
  expect_equal(result[[1L]]@classification, "deprecated")
})

# -- scan_layer2() integration tests -------------------------------------------

test_that("scan_layer2: enriches ScanResult with Rd data", {
  # Given: a function with Rd documentation
  # When:  running full scan (Layer 1 + Layer 2)
  # Then:  ScanResult contains Layer 2 data
  mock_fn <- function(method = "MH", sm = "OR") NULL
  mock_rd <- make_mock_rd("testfn", list(
    method = 'Statistical method. One of "MH", "Inverse", "Peto".',
    sm = "Summary measure."
  ), references = "Author (2020). Title of paper.")

  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = function(pkg) { # nolint: object_usage_linter. mock binding
    list("testfn.Rd" = mock_rd)
  })

  sr <- bridle:::scan_function("testpkg", "testfn")

  expect_true("layer2_rd" %in% sr@scan_metadata[["layers_completed"]])
  expect_true("method" %in% names(sr@descriptions))
  expect_true("method" %in% names(sr@valid_values))
  expect_true("MH" %in% sr@valid_values[["method"]])
  expect_true(length(sr@references) >= 1L)
})

test_that("scan_layer2: graceful when Rd unavailable", {
  # Given: a package without accessible Rd
  # When:  running scan
  # Then:  Layer 2 is skipped with warning, Layer 1 result preserved
  mock_fn <- function(x = 1) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = function(pkg) { # nolint: object_usage_linter. mock binding
    stop("No Rd available")
  })

  expect_warning(
    sr <- bridle:::scan_function("testpkg", "testfn"),
    "Cannot access Rd"
  )
  expect_equal(sr@scan_metadata[["layers_completed"]], "layer1_formals")
  expect_length(sr@parameters, 1L)
})

test_that("scan_layer2: graceful when function Rd not found", {
  # Given: Rd database exists but no entry for the function
  # When:  running scan
  # Then:  Layer 2 skipped with warning
  mock_fn <- function(x = 1) NULL
  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = function(pkg) { # nolint: object_usage_linter. mock binding
    list("other.Rd" = make_mock_rd("otherfunc"))
  })

  expect_warning(
    sr <- bridle:::scan_function("testpkg", "testfn"),
    "No Rd documentation"
  )
  expect_equal(sr@scan_metadata[["layers_completed"]], "layer1_formals")
})

test_that("scan_layer2: detects deprecated from Rd and updates classification", {
  # Given: Rd documentation marks a parameter as deprecated
  # When:  running full scan
  # Then:  parameter classification updated to "deprecated"
  mock_fn <- function(old_param = NULL, method = "MH") NULL
  mock_rd <- make_mock_rd("testfn", list(
    old_param = "Deprecated. Use method instead.",
    method = "The method."
  ))

  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = function(pkg) { # nolint: object_usage_linter. mock binding
    list("testfn.Rd" = mock_rd)
  })

  sr <- bridle:::scan_function("testpkg", "testfn")

  classes <- vapply(sr@parameters, function(p) p@classification, character(1))
  names(classes) <- vapply(sr@parameters, function(p) p@name, character(1))
  expect_equal(classes[["old_param"]], "deprecated")
})

test_that("scan_layer2: malformed Rd returns partial results", {
  # Given: Rd with valid alias but empty arguments section
  # When:  running scan
  # Then:  Layer 2 completes with empty descriptions/valid_values
  mock_fn <- function(x = 1) NULL
  mock_rd <- list(make_rd_alias("testfn"))

  local_mocked_bindings(resolve_function = mock_resolve(mock_fn))
  local_mocked_bindings(get_package_version = mock_version)
  local_mocked_bindings(get_rd_db = function(pkg) { # nolint: object_usage_linter. mock binding
    list("testfn.Rd" = mock_rd)
  })

  sr <- bridle:::scan_function("testpkg", "testfn")
  expect_true("layer2_rd" %in% sr@scan_metadata[["layers_completed"]])
  expect_equal(sr@descriptions, list())
  expect_equal(sr@valid_values, list())
})
