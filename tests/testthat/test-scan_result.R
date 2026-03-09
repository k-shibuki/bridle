# Tests for ScanResult S7 classes (ParameterInfo, ScanResult)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# -- ParameterInfo ------------------------------------------------------------

test_that("ParameterInfo: valid construction with defaults", {
  # Given: minimal required fields
  # When:  constructing a ParameterInfo
  # Then:  defaults applied correctly

  p <- ParameterInfo(name = "method", has_default = TRUE)
  expect_equal(p@name, "method")
  expect_true(p@has_default)
  expect_equal(p@default_expression, "")
  expect_equal(p@classification, "unknown")
})

test_that("ParameterInfo: all fields specified", {
  # Given: all fields provided
  # When:  constructing a ParameterInfo
  # Then:  all values stored correctly
  p <- ParameterInfo(
    name = "sm",
    has_default = TRUE,
    default_expression = "ifelse(method == 'Peto', 'OR', 'RR')",
    classification = "statistical_decision"
  )
  expect_equal(p@name, "sm")
  expect_equal(p@default_expression, "ifelse(method == 'Peto', 'OR', 'RR')")
  expect_equal(p@classification, "statistical_decision")
})

test_that("ParameterInfo: parameter without default", {
  # Given: a parameter with no default
  # When:  constructing a ParameterInfo
  # Then:  has_default is FALSE
  p <- ParameterInfo(name = "data", has_default = FALSE)
  expect_false(p@has_default)
  expect_equal(p@default_expression, "")
})

test_that("ParameterInfo: all classification values accepted", {
  # Given: each valid classification
  # When:  constructing a ParameterInfo
  # Then:  no validation error
  for (cls in c(
    "data_input", "statistical_decision", "presentation",
    "deprecated", "unknown"
  )) {
    p <- ParameterInfo(name = "x", has_default = FALSE, classification = cls)
    expect_equal(p@classification, cls)
  }
})

test_that("ParameterInfo: empty name rejected", {
  # Given: an empty name string
  # When:  constructing a ParameterInfo
  # Then:  validation error
  expect_error(
    ParameterInfo(name = "", has_default = TRUE),
    "non-empty single string"
  )
})

test_that("ParameterInfo: missing name rejected", {
  # Given: zero-length character for name
  # When:  constructing a ParameterInfo
  # Then:  validation error
  expect_error(
    ParameterInfo(name = character(0), has_default = TRUE),
    "non-empty single string"
  )
})

test_that("ParameterInfo: NA has_default rejected", {
  # Given: NA for has_default
  # When:  constructing a ParameterInfo
  # Then:  validation error
  expect_error(
    ParameterInfo(name = "x", has_default = NA),
    "TRUE or FALSE"
  )
})

test_that("ParameterInfo: invalid classification rejected", {
  # Given: an invalid classification string
  # When:  constructing a ParameterInfo
  # Then:  validation error
  expect_error(
    ParameterInfo(name = "x", has_default = TRUE, classification = "bogus"),
    "classification"
  )
})

# -- ScanResult ---------------------------------------------------------------

test_that("ScanResult: valid minimal construction", {
  # Given: required fields with one parameter
  # When:  constructing a ScanResult
  # Then:  object created with defaults for optional fields
  sr <- ScanResult(
    package = "stats",
    func = "lm",
    parameters = list(
      ParameterInfo(name = "formula", has_default = FALSE)
    ),
    scan_metadata = list(
      layers_completed = "layer1_formals",
      timestamp = "2026-01-01T00:00:00+0000"
    )
  )
  expect_equal(sr@package, "stats")
  expect_equal(sr@func, "lm")
  expect_length(sr@parameters, 1L)
  expect_equal(sr@dependency_graph, list())
  expect_equal(sr@constraints, list())
  expect_equal(sr@valid_values, list())
  expect_equal(sr@references, character(0))
})

test_that("ScanResult: full construction with all fields", {
  # Given: all fields provided including constraints and dep graph
  # When:  constructing a ScanResult
  # Then:  all fields stored correctly
  cst <- Constraint(
    id = "c1",
    source = "formals_default",
    type = "forces",
    forces = list(sm = "OR"),
    confidence = "medium",
    confirmed_by = "formals_default"
  )
  sr <- ScanResult(
    package = "meta",
    func = "metabin",
    parameters = list(
      ParameterInfo(name = "method", has_default = TRUE),
      ParameterInfo(name = "sm", has_default = TRUE)
    ),
    dependency_graph = list(sm = "method"),
    constraints = list(cst),
    valid_values = list(method = c("MH", "Peto")),
    references = "Cochrane Handbook 2023",
    scan_metadata = list(
      layers_completed = "layer1_formals",
      timestamp = "2026-01-01T00:00:00+0000",
      package_version = "7.0-0"
    )
  )
  expect_length(sr@constraints, 1L)
  expect_equal(sr@valid_values, list(method = c("MH", "Peto")))
  expect_equal(sr@references, "Cochrane Handbook 2023")
})

test_that("ScanResult: empty package rejected", {
  # Given: an empty package name
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "",
      func = "f",
      parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "non-empty single string"
  )
})

test_that("ScanResult: empty func rejected", {
  # Given: an empty func name
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "",
      parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "non-empty single string"
  )
})

test_that("ScanResult: empty parameters rejected", {
  # Given: no parameters
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list(),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "at least one ParameterInfo"
  )
})

test_that("ScanResult: non-ParameterInfo in parameters rejected", {
  # Given: a non-ParameterInfo object in parameters list
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list("not a ParameterInfo"),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "ParameterInfo"
  )
})

test_that("ScanResult: duplicate parameter names rejected", {
  # Given: two parameters with the same name
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list(
        ParameterInfo(name = "x", has_default = FALSE),
        ParameterInfo(name = "x", has_default = TRUE)
      ),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "Duplicate parameter name"
  )
})

test_that("ScanResult: non-Constraint in constraints rejected", {
  # Given: a non-Constraint in constraints
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
      constraints = list("not a constraint"),
      scan_metadata = list(layers_completed = "layer1_formals")
    ),
    "Constraint"
  )
})

test_that("ScanResult: missing layers_completed rejected", {
  # Given: scan_metadata without layers_completed
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
      scan_metadata = list(timestamp = "2026-01-01")
    ),
    "layers_completed"
  )
})

test_that("ScanResult: invalid layer name rejected", {
  # Given: an invalid layer name
  # When:  constructing a ScanResult
  # Then:  validation error
  expect_error(
    ScanResult(
      package = "pkg",
      func = "f",
      parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
      scan_metadata = list(layers_completed = "layer99_invalid")
    ),
    "Invalid layer"
  )
})

test_that("ScanResult: multiple valid layers accepted", {
  # Given: multiple valid layer names
  # When:  constructing a ScanResult
  # Then:  no validation error
  sr <- ScanResult(
    package = "pkg",
    func = "f",
    parameters = list(ParameterInfo(name = "x", has_default = FALSE)),
    scan_metadata = list(
      layers_completed = c("layer1_formals", "layer2_rd")
    )
  )
  expect_equal(
    sr@scan_metadata[["layers_completed"]],
    c("layer1_formals", "layer2_rd")
  )
})

# -- PackageScanResult --------------------------------------------------------

test_that("PackageScanResult: valid minimal construction", {
  # Given: required fields with empty functions list
  # When:  constructing a PackageScanResult
  # Then:  object created with defaults
  psr <- PackageScanResult(
    package = "metafor",
    scan_metadata = list(package_version = "4.6-0", timestamp = "2026-01-01")
  )
  expect_equal(psr@package, "metafor")
  expect_equal(psr@functions, list())
  expect_equal(psr@function_roles, character(0))
  expect_equal(psr@function_families, list())
  expect_equal(psr@cross_function_constraints, list())
})

test_that("PackageScanResult: full construction with functions", {
  # Given: package scan result with one analysis function
  # When:  constructing a PackageScanResult
  # Then:  all fields stored correctly
  sr <- ScanResult(
    package = "metafor", func = "rma.uni",
    parameters = list(ParameterInfo(name = "yi", has_default = FALSE)),
    scan_metadata = list(layers_completed = "layer1_formals")
  )
  psr <- PackageScanResult(
    package = "metafor",
    functions = list(rma.uni = sr), # nolint: object_name_linter. matches R package function naming
    function_roles = c(rma.uni = "analysis"), # nolint: object_name_linter. matches R package function naming
    function_families = list(rma = list(
      name = "rma", common_parameters = c("yi", "vi"),
      members = list(rma.uni = list(unique_parameters = c("sei"))) # nolint: object_name_linter. matches R package function naming
    )),
    cross_function_constraints = list(list(
      function_name = "rma.peto", constraint = "measure == \"OR\"",
      reason = "Peto requires OR"
    )),
    scan_metadata = list(package_version = "4.6-0", timestamp = "2026-01-01")
  )
  expect_length(psr@functions, 1L)
  expect_equal(names(psr@functions), "rma.uni")
  expect_equal(psr@function_roles[["rma.uni"]], "analysis")
  expect_length(psr@function_families, 1L)
  expect_length(psr@cross_function_constraints, 1L)
})

test_that("PackageScanResult: empty package rejected", {
  # Given: empty package name
  # When:  constructing
  # Then:  validation error
  expect_error(
    PackageScanResult(
      package = "",
      scan_metadata = list(timestamp = "2026-01-01")
    ),
    "non-empty single string"
  )
})

test_that("PackageScanResult: invalid function role rejected", {
  # Given: an invalid role string
  # When:  constructing
  # Then:  validation error
  expect_error(
    PackageScanResult(
      package = "metafor",
      function_roles = c(rma.uni = "invalid_role"), # nolint: object_name_linter. matches R package function naming
      scan_metadata = list(timestamp = "2026-01-01")
    ),
    "Invalid function role"
  )
})

test_that("PackageScanResult: non-ScanResult in functions rejected", {
  # Given: a non-ScanResult in functions list
  # When:  constructing
  # Then:  validation error
  expect_error(
    PackageScanResult(
      package = "metafor",
      functions = list(bad = "not a ScanResult"),
      scan_metadata = list(timestamp = "2026-01-01")
    ),
    "ScanResult"
  )
})

test_that("PackageScanResult: all valid roles accepted", {
  # Given: each valid function role
  # When:  constructing
  # Then:  no validation error
  for (role in c("analysis", "visualization", "diagnostic", "utility", "unclassified")) {
    psr <- PackageScanResult(
      package = "pkg",
      function_roles = stats::setNames(role, "fn"),
      scan_metadata = list(timestamp = "2026-01-01")
    )
    expect_equal(psr@function_roles[["fn"]], role)
  }
})
