# Tests for ConstraintSet S7 classes
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# -- Constraint ---------------------------------------------------------------

test_that("Constraint: valid forces type", {
  # Given: a forces-type constraint with required fields
  # When:  constructing a Constraint
  # Then:  all fields stored correctly
  c <- Constraint(
    id = "peto_forces_or",
    source = "formals_default",
    type = "forces",
    condition = "method == 'Peto'",
    forces = list(sm = "OR"),
    message = "Peto method forces OR"
  )
  expect_equal(c@id, "peto_forces_or")
  expect_equal(c@source, "formals_default")
  expect_equal(c@type, "forces")
  expect_equal(c@forces, list(sm = "OR"))
})

test_that("Constraint: valid valid_values type", {
  # Given: a valid_values-type constraint with values
  # When:  constructing a Constraint
  # Then:  values stored correctly
  c <- Constraint(
    id = "valid_sm",
    source = "rd_description",
    type = "valid_values",
    param = "sm",
    values = c("RR", "OR", "RD"),
    confirmed_by = c("source_code"),
    confidence = "high"
  )
  expect_equal(c@values, c("RR", "OR", "RD"))
  expect_equal(c@confirmed_by, "source_code")
  expect_equal(c@confidence, "high")
})

test_that("Constraint: valid requires type", {
  # Given: a requires-type constraint
  # When:  constructing a Constraint
  # Then:  requires field stored
  c <- Constraint(
    id = "req1",
    source = "expert",
    type = "requires",
    condition = "method == 'Peto'",
    requires = list(sm = "OR")
  )
  expect_equal(c@requires, list(sm = "OR"))
})

test_that("Constraint: valid incompatible type", {
  # Given: an incompatible-type constraint
  # When:  constructing a Constraint
  # Then:  incompatible field stored
  c <- Constraint(
    id = "incompat1",
    source = "expert",
    type = "incompatible",
    incompatible = list(method = "Peto"),
    confidence = "low"
  )
  expect_equal(c@incompatible, list(method = "Peto"))
})

test_that("Constraint: valid conditional type", {
  # Given: a conditional-type constraint
  # When:  constructing a Constraint
  # Then:  enabled_when field stored
  c <- Constraint(
    id = "cond1",
    source = "rd_description",
    type = "conditional",
    param = "model.glmm",
    enabled_when = "method == 'GLMM'"
  )
  expect_equal(c@enabled_when, "method == 'GLMM'")
})

test_that("Constraint: valid with default optional fields", {
  # Given: only required fields for valid_values
  # When:  constructing a Constraint
  # Then:  optional fields have empty defaults
  c <- Constraint(
    id = "c1",
    source = "formals_default",
    type = "valid_values",
    values = "x"
  )
  expect_equal(c@param, character(0))
  expect_equal(c@condition, character(0))
  expect_equal(c@message, character(0))
  expect_equal(c@confidence, character(0))
  expect_equal(c@confirmed_by, character(0))
})

test_that("Constraint: error with invalid source enum", {
  # Given: source = "unknown"
  # When:  constructing a Constraint
  # Then:  validation error listing valid sources
  expect_error(
    Constraint(id = "c1", source = "unknown", type = "forces", forces = list(a = "b")),
    "source.*must be one of"
  )
})

test_that("Constraint: error with invalid type enum", {
  # Given: type = "invalid"
  # When:  constructing a Constraint
  # Then:  validation error listing valid types
  expect_error(
    Constraint(id = "c1", source = "expert", type = "invalid"),
    "type.*must be one of"
  )
})

test_that("Constraint: error with invalid confidence enum", {
  # Given: confidence = "very_high"
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(
      id = "c1", source = "expert", type = "valid_values",
      values = "x", confidence = "very_high"
    ),
    "confidence.*must be one of"
  )
})

test_that("Constraint: error when forces type missing forces field", {
  # Given: type = "forces" but no forces field
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "c1", source = "expert", type = "forces"),
    'type.*"forces".*forces.*field'
  )
})

test_that("Constraint: error when valid_values type missing values field", {
  # Given: type = "valid_values" but no values
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "c1", source = "expert", type = "valid_values"),
    'type.*"valid_values".*values.*field'
  )
})

test_that("Constraint: error when requires type missing requires field", {
  # Given: type = "requires" but no requires
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "c1", source = "expert", type = "requires"),
    'type.*"requires".*requires.*field'
  )
})

test_that("Constraint: error when incompatible type missing incompatible field", {
  # Given: type = "incompatible" but no incompatible
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "c1", source = "expert", type = "incompatible"),
    'type.*"incompatible".*incompatible.*field'
  )
})

test_that("Constraint: error when conditional type missing enabled_when", {
  # Given: type = "conditional" but no enabled_when
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "c1", source = "expert", type = "conditional"),
    'type.*"conditional".*enabled_when.*field'
  )
})

test_that("Constraint: error with missing id", {
  # Given: empty id
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(id = "", source = "expert", type = "valid_values", values = "x"),
    "id.*non-empty"
  )
})

test_that("Constraint: error with invalid confirmed_by value", {
  # Given: confirmed_by with invalid source type
  # When:  constructing a Constraint
  # Then:  validation error
  expect_error(
    Constraint(
      id = "c1", source = "expert", type = "valid_values",
      values = "x", confirmed_by = "invalid_source"
    ),
    "confirmed_by.*valid source"
  )
})

test_that("Constraint: valid confirmed_by with multiple sources", {
  # Given: confirmed_by with valid source types
  # When:  constructing a Constraint
  # Then:  accepted
  c <- Constraint(
    id = "c1", source = "rd_description", type = "valid_values",
    values = "x", confirmed_by = c("source_code", "formals_default")
  )
  expect_equal(c@confirmed_by, c("source_code", "formals_default"))
})

# -- ConstraintSet ------------------------------------------------------------

test_that("ConstraintSet: valid construction", {
  # Given: package, func, and valid constraints
  # When:  constructing a ConstraintSet
  # Then:  all fields stored correctly
  cs <- ConstraintSet(
    package = "meta",
    func = "metabin",
    constraints = list(
      Constraint(
        id = "c1", source = "expert", type = "valid_values", values = "x"
      ),
      Constraint(
        id = "c2", source = "expert", type = "forces",
        forces = list(a = "b")
      )
    )
  )
  expect_equal(cs@package, "meta")
  expect_equal(cs@func, "metabin")
  expect_length(cs@constraints, 2L)
})

test_that("ConstraintSet: error with empty constraints list", {
  # Given: empty constraints
  # When:  constructing a ConstraintSet
  # Then:  validation error
  expect_error(
    ConstraintSet(package = "meta", func = "metabin", constraints = list()),
    "constraints.*at least one"
  )
})

test_that("ConstraintSet: error with duplicate constraint IDs", {
  # Given: two constraints with the same id
  # When:  constructing a ConstraintSet
  # Then:  validation error
  expect_error(
    ConstraintSet(
      package = "meta",
      func = "metabin",
      constraints = list(
        Constraint(
          id = "dup", source = "expert", type = "valid_values", values = "x"
        ),
        Constraint(
          id = "dup", source = "expert", type = "forces",
          forces = list(a = "b")
        )
      )
    ),
    "Duplicate constraint id.*dup"
  )
})

test_that("ConstraintSet: error with non-Constraint in list", {
  # Given: a plain list instead of Constraint
  # When:  constructing a ConstraintSet
  # Then:  validation error
  expect_error(
    ConstraintSet(
      package = "meta",
      func = "metabin",
      constraints = list(list(id = "x"))
    ),
    "must be a Constraint"
  )
})

test_that("ConstraintSet: error when package is empty", {
  # Given: empty package
  # When:  constructing a ConstraintSet
  # Then:  validation error
  expect_error(
    ConstraintSet(
      package = "",
      func = "metabin",
      constraints = list(
        Constraint(
          id = "c1", source = "expert", type = "valid_values", values = "x"
        )
      )
    ),
    "package.*non-empty"
  )
})

test_that("ConstraintSet: error when func is empty", {
  # Given: empty func
  # When:  constructing a ConstraintSet
  # Then:  validation error
  expect_error(
    ConstraintSet(
      package = "meta",
      func = "",
      constraints = list(
        Constraint(
          id = "c1", source = "expert", type = "valid_values", values = "x"
        )
      )
    ),
    "func.*non-empty"
  )
})

# -- YAML Reader --------------------------------------------------------------

test_that("read_constraints: valid YAML round-trip", {
  # Given: the metabin example fixture (7 constraints)
  # When:  reading the YAML file
  # Then:  ConstraintSet has correct structure
  path <- test_path("fixtures", "constraints_valid.yaml")
  cs <- read_constraints(path)

  expect_s3_class(cs, "bridle::ConstraintSet")
  expect_equal(cs@package, "meta")
  expect_equal(cs@func, "metabin")
  expect_length(cs@constraints, 7L)

  c1 <- cs@constraints[[1L]]
  expect_equal(c1@id, "peto_forces_or")
  expect_equal(c1@type, "forces")
  expect_equal(c1@forces, list(sm = "OR"))

  c3 <- cs@constraints[[3L]]
  expect_equal(c3@id, "valid_sm")
  expect_equal(c3@type, "valid_values")
  expect_equal(c3@values, c("RR", "OR", "RD", "ASD", "DOR", "VE"))
  expect_equal(c3@confirmed_by, "source_code")
  expect_equal(c3@confidence, "high")

  c7 <- cs@constraints[[7L]]
  expect_equal(c7@id, "peto_not_for_imbalanced")
  expect_equal(c7@type, "incompatible")
  expect_equal(c7@confidence, "low")
})

test_that("read_constraints: error on nonexistent file", {
  # Given: a path that does not exist
  # When:  reading the file
  # Then:  informative error
  expect_error(
    read_constraints("nonexistent_file.yaml"),
    "File not found"
  )
})

test_that("read_constraints: error on malformed YAML", {
  # Given: invalid YAML content
  # When:  reading the file
  # Then:  YAML parse error
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("constraints: [invalid\n  unclosed", tmp)
  expect_error(
    read_constraints(tmp),
    "Failed to parse YAML"
  )
})

test_that("read_constraints: error when package is missing", {
  # Given: YAML without package field
  # When:  reading the file
  # Then:  error about missing package
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(
    `function` = "metabin",
    constraints = list(list(
      id = "c1", source = "expert", type = "valid_values", values = list("x")
    ))
  ), tmp)
  expect_error(read_constraints(tmp), "package.*required")
})

test_that("read_constraints: error when constraints is missing", {
  # Given: YAML without constraints
  # When:  reading the file
  # Then:  error about missing constraints
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(package = "meta", `function` = "metabin"), tmp)
  expect_error(read_constraints(tmp), "constraints.*non-empty")
})
