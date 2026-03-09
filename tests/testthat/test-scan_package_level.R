# Tests for package-level scan_package() (ADR-0004 Addendum)
# Tests function enumeration, classification, family detection,
# and cross-function constraints.

# -- scan_package() input validation ------------------------------------------

test_that("scan_package: NULL package rejected", {
  expect_error(scan_package(NULL), "non-empty string")
})

test_that("scan_package: empty package rejected", {
  expect_error(scan_package(""), "non-empty string")
})

test_that("scan_package: non-existent package rejected", {
  expect_error(
    scan_package("nonexistent_pkg_xyz_999"),
    "not available"
  )
})

# -- classify_single_function() -----------------------------------------------

test_that("classify_single_function: analysis from formals + name", {
  # Given: a function named rma.uni with analysis formals
  # When:  classifying
  # Then:  returns "analysis"
  result <- bridle:::classify_single_function(
    "rma.uni", c("yi", "vi", "data", "method"), "Model Fitting"
  )
  expect_equal(result, "analysis")
})

test_that("classify_single_function: visualization from name prefix", {
  # Given: a function named forest.rma with plot formals
  # When:  classifying
  # Then:  returns "visualization"
  result <- bridle:::classify_single_function(
    "forest.rma", c("x", "xlim", "ylim"), "Forest Plot"
  )
  expect_equal(result, "visualization")
})

test_that("classify_single_function: diagnostic from name prefix", {
  # Given: a function named influence.rma.uni
  # When:  classifying
  # Then:  returns "diagnostic"
  result <- bridle:::classify_single_function(
    "influence.rma.uni", c("x"), "Influence Diagnostics"
  )
  expect_equal(result, "diagnostic")
})

test_that("classify_single_function: utility when no signals", {
  # Given: a function with no matching signals
  # When:  classifying
  # Then:  returns "utility"
  result <- bridle:::classify_single_function(
    "to.long", c("x", "transf"), "Convert Data"
  )
  expect_equal(result, "utility")
})

test_that("classify_single_function: escalc detected as analysis", {
  # Given: escalc with measure formals and calculation title
  # When:  classifying
  # Then:  returns "analysis"
  result <- bridle:::classify_single_function(
    "escalc", c("measure", "ai", "bi", "ci", "di"), "Calculate Effect Sizes"
  )
  expect_equal(result, "analysis")
})

# -- detect_families() --------------------------------------------------------

test_that("detect_families: detects shared prefix family", {
  # Given: two ScanResults with rma.* prefix
  # When:  detecting families
  # Then:  rma family found with correct common/unique params
  sr1 <- ScanResult(
    package = "metafor", func = "rma.uni",
    parameters = list(
      ParameterInfo(name = "yi", has_default = FALSE),
      ParameterInfo(name = "vi", has_default = FALSE),
      ParameterInfo(name = "method", has_default = TRUE),
      ParameterInfo(name = "sei", has_default = FALSE)
    ),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  sr2 <- ScanResult(
    package = "metafor", func = "rma.mh",
    parameters = list(
      ParameterInfo(name = "yi", has_default = FALSE),
      ParameterInfo(name = "vi", has_default = FALSE),
      ParameterInfo(name = "measure", has_default = TRUE)
    ),
    scan_metadata = list(layers_completed = "layer1_formals")
  )

  results <- list(rma.uni = sr1, rma.mh = sr2) # nolint: object_name_linter. matches R package function naming
  families <- bridle:::detect_families(results)

  expect_true("rma" %in% names(families))
  fam <- families[["rma"]]
  expect_true(all(c("yi", "vi") %in% fam$common_parameters))
  expect_true("method" %in% fam$members[["rma.uni"]]$unique_parameters)
  expect_true("measure" %in% fam$members[["rma.mh"]]$unique_parameters)
})

test_that("detect_families: single function returns empty", {
  # Given: only one function
  # When:  detecting families
  # Then:  no families
  sr <- ScanResult(
    package = "metafor", func = "escalc",
    parameters = list(ParameterInfo(name = "measure", has_default = TRUE)),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  families <- bridle:::detect_families(list(escalc = sr))
  expect_length(families, 0L)
})

test_that("detect_families: no prefix match returns empty", {
  # Given: two functions with different prefixes
  # When:  detecting families
  # Then:  no families
  sr1 <- ScanResult(
    package = "pkg", func = "alpha",
    parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  sr2 <- ScanResult(
    package = "pkg", func = "beta",
    parameters = list(ParameterInfo(name = "y", has_default = FALSE)),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  families <- bridle:::detect_families(list(alpha = sr1, beta = sr2))
  expect_length(families, 0L)
})

# -- extract_cross_function_constraints() -------------------------------------

test_that("cross_function_constraints: detects measure restriction", {
  # Given: a ScanResult with restricted valid_values for measure
  # When:  extracting cross-function constraints
  # Then:  constraint captured
  sr <- ScanResult(
    package = "metafor", func = "rma.peto",
    parameters = list(ParameterInfo(name = "measure", has_default = TRUE)),
    valid_values = list(measure = "OR"),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  constraints <- bridle:::extract_cross_constraints(
    list(rma.peto = sr), # nolint: object_name_linter. matches R package function naming
    c(rma.peto = "analysis") # nolint: object_name_linter. matches R package function naming
  )
  expect_true(length(constraints) >= 1L)
  expect_equal(constraints[[1L]]$function_name, "rma.peto")
  expect_true(grepl("OR", constraints[[1L]]$constraint))
})

test_that("cross_function_constraints: empty when no restrictions", {
  # Given: a ScanResult with no valid_values or forces constraints
  # When:  extracting cross-function constraints
  # Then:  empty list
  sr <- ScanResult(
    package = "metafor", func = "rma.uni",
    parameters = list(ParameterInfo(name = "yi", has_default = FALSE)),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  constraints <- bridle:::extract_cross_constraints(
    list(rma.uni = sr), # nolint: object_name_linter. matches R package function naming
    c(rma.uni = "analysis") # nolint: object_name_linter. matches R package function naming
  )
  expect_length(constraints, 0L)
})

# -- scan_package() integration with mocks ------------------------------------

test_that("scan_package: returns PackageScanResult with mocked package", {
  # Given: a mock package with 3 exported functions
  # When:  scanning at package level
  # Then:  returns PackageScanResult with classified functions
  mock_ns <- new.env(parent = emptyenv())
  local_mocked_bindings(
    get_package_namespace = function(pkg) mock_ns,
    get_namespace_exports = function(pkg) c("rma.uni", "forest.rma", "helper_fn"),
    exclude_s3_methods = function(exports, pkg) exports,
    classify_functions = function(func_names, ns, pkg) {
      c(rma.uni = "analysis", forest.rma = "visualization", helper_fn = "utility") # nolint: object_name_linter. matches R package function naming
    },
    scan_function = function(pkg, func) {
      ScanResult(
        package = pkg, func = func,
        parameters = list(
          ParameterInfo(name = "yi", has_default = FALSE),
          ParameterInfo(name = "vi", has_default = FALSE)
        ),
        scan_metadata = list(
          layers_completed = "layer1_formals",
          timestamp = "2026-01-01", package_version = "0.0.1"
        )
      )
    },
    get_package_version = mock_version
  )

  psr <- scan_package("testpkg")

  expect_s3_class(psr, "bridle::PackageScanResult")
  expect_equal(psr@package, "testpkg")
  expect_true("rma.uni" %in% names(psr@functions))
  expect_false("forest.rma" %in% names(psr@functions))
  expect_false("helper_fn" %in% names(psr@functions))
  expect_equal(psr@function_roles[["rma.uni"]], "analysis")
  expect_equal(psr@function_roles[["forest.rma"]], "visualization")
  expect_equal(psr@function_roles[["helper_fn"]], "utility")
})

test_that("scan_package: gracefully skips failing functions", {
  # Given: a mock where scan_function errors on one function
  # When:  scanning
  # Then:  the failing function is skipped with a warning
  mock_ns <- new.env(parent = emptyenv())
  local_mocked_bindings(
    get_package_namespace = function(pkg) mock_ns,
    get_namespace_exports = function(pkg) c("good_fn", "bad_fn"),
    exclude_s3_methods = function(exports, pkg) exports,
    classify_functions = function(func_names, ns, pkg) {
      c(good_fn = "analysis", bad_fn = "analysis")
    },
    scan_function = function(pkg, func) {
      if (func == "bad_fn") stop("intentional error")
      ScanResult(
        package = pkg, func = func,
        parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
        scan_metadata = list(
          layers_completed = "layer1_formals",
          timestamp = "2026-01-01", package_version = "0.0.1"
        )
      )
    },
    get_package_version = mock_version
  )

  expect_message(
    psr <- scan_package("testpkg"),
    "Scanning"
  )
  expect_length(psr@functions, 1L)
  expect_true("good_fn" %in% names(psr@functions))
})

# -- exclude_s3_methods() ----------------------------------------------------

test_that("exclude_s3_methods: filters registered S3 methods", {
  # Given: exports containing both regular functions and S3 methods
  # When:  excluding S3 methods with stats (where lm, print.lm are real)
  # Then:  only non-S3 functions remain
  local_mocked_bindings(
    get_s3_method_table = function(pkg) {
      data.frame(method = c("print.default", "summary.lm"), stringsAsFactors = FALSE)
    }
  )
  exports <- c("lm", "print.default", "summary.lm", "var")
  result <- bridle:::exclude_s3_methods(exports, "stats")
  expect_true("lm" %in% result)
  expect_true("var" %in% result)
  expect_false("print.default" %in% result)
  expect_false("summary.lm" %in% result)
})
