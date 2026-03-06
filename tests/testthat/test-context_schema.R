# Tests for ContextSchema S7 classes
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# -- DataExpectation ----------------------------------------------------------

test_that("DataExpectation: valid construction", {
  # Given: valid column, role, and required
  # When:  constructing a DataExpectation
  # Then:  all fields stored correctly
  de <- DataExpectation(column = "event.e", role = "outcome", required = TRUE)
  expect_equal(de@column, "event.e")
  expect_equal(de@role, "outcome")
  expect_true(de@required)
})

test_that("DataExpectation: valid with required = FALSE", {
  # Given: required = FALSE
  # When:  constructing a DataExpectation
  # Then:  accepted
  de <- DataExpectation(column = "studlab", role = "study_id", required = FALSE)
  expect_false(de@required)
})

test_that("DataExpectation: error with invalid role", {
  # Given: role = "unknown"
  # When:  constructing a DataExpectation
  # Then:  validation error listing valid roles
  expect_error(
    DataExpectation(column = "x", role = "unknown", required = TRUE),
    "role.*must be one of"
  )
})

test_that("DataExpectation: error when column is empty", {
  # Given: empty column
  # When:  constructing a DataExpectation
  # Then:  validation error
  expect_error(
    DataExpectation(column = "", role = "outcome", required = TRUE),
    "column.*non-empty"
  )
})

test_that("DataExpectation: error when required is NA", {
  # Given: required = NA
  # When:  constructing a DataExpectation
  # Then:  validation error
  expect_error(
    DataExpectation(column = "x", role = "outcome", required = NA),
    "required.*TRUE or FALSE"
  )
})

# -- ContextVariable ----------------------------------------------------------

test_that("ContextVariable: valid construction with all fields", {
  # Given: all fields including depends_on_node
  # When:  constructing a ContextVariable
  # Then:  all fields stored correctly
  cv <- ContextVariable(
    name = "I2",
    description = "I-squared heterogeneity statistic",
    available_from = "post_fit",
    depends_on_node = "execute_analysis",
    source_expression = "result$I2"
  )
  expect_equal(cv@name, "I2")
  expect_equal(cv@available_from, "post_fit")
  expect_equal(cv@depends_on_node, "execute_analysis")
  expect_equal(cv@source_expression, "result$I2")
})

test_that("ContextVariable: valid with NULL depends_on_node", {
  # Given: no depends_on_node
  # When:  constructing a ContextVariable
  # Then:  depends_on_node is empty
  cv <- ContextVariable(
    name = "k",
    description = "number of studies",
    available_from = "data_loaded",
    source_expression = "nrow(data)"
  )
  expect_equal(cv@depends_on_node, character(0))
})

test_that("ContextVariable: valid with all available_from values", {
  # Given: each available_from enum value
  # When:  constructing ContextVariables
  # Then:  all accepted
  for (phase in c("data_loaded", "parameter_decided", "post_fit")) {
    cv <- ContextVariable(
      name = "x",
      description = "test",
      available_from = phase,
      source_expression = "x"
    )
    expect_equal(cv@available_from, phase)
  }
})

test_that("ContextVariable: error with invalid available_from", {
  # Given: available_from = "never"
  # When:  constructing a ContextVariable
  # Then:  validation error
  expect_error(
    ContextVariable(
      name = "x",
      description = "test",
      available_from = "never",
      source_expression = "x"
    ),
    "available_from.*must be one of"
  )
})

test_that("ContextVariable: error when name is empty", {
  # Given: empty name
  # When:  constructing a ContextVariable
  # Then:  validation error
  expect_error(
    ContextVariable(
      name = "",
      description = "test",
      available_from = "data_loaded",
      source_expression = "x"
    ),
    "name.*non-empty"
  )
})

test_that("ContextVariable: error when source_expression is empty", {
  # Given: empty source_expression
  # When:  constructing a ContextVariable
  # Then:  validation error
  expect_error(
    ContextVariable(
      name = "x",
      description = "test",
      available_from = "data_loaded",
      source_expression = ""
    ),
    "source_expression.*non-empty"
  )
})

test_that("ContextVariable: error when description is empty", {
  # Given: empty description
  # When:  constructing a ContextVariable
  # Then:  validation error
  expect_error(
    ContextVariable(
      name = "x",
      description = "",
      available_from = "data_loaded",
      source_expression = "x"
    ),
    "description.*non-empty"
  )
})

# -- ContextSchema ------------------------------------------------------------

test_that("ContextSchema: valid construction", {
  # Given: variables and data_expectations
  # When:  constructing a ContextSchema
  # Then:  all fields stored correctly
  cs <- ContextSchema(
    variables = list(
      ContextVariable(
        name = "k",
        description = "number of studies",
        available_from = "data_loaded",
        source_expression = "nrow(data)"
      )
    ),
    data_expectations = list(
      DataExpectation(column = "event.e", role = "outcome", required = TRUE)
    )
  )
  expect_length(cs@variables, 1L)
  expect_length(cs@data_expectations, 1L)
})

test_that("ContextSchema: valid without data_expectations", {
  # Given: only variables, no data_expectations
  # When:  constructing a ContextSchema
  # Then:  data_expectations defaults to empty list
  cs <- ContextSchema(
    variables = list(
      ContextVariable(
        name = "k",
        description = "test",
        available_from = "data_loaded",
        source_expression = "nrow(data)"
      )
    )
  )
  expect_equal(cs@data_expectations, list())
})

test_that("ContextSchema: error when variables is empty", {
  # Given: empty variables list
  # When:  constructing a ContextSchema
  # Then:  validation error
  expect_error(
    ContextSchema(variables = list()),
    "variables.*at least one"
  )
})

test_that("ContextSchema: error with non-ContextVariable in variables", {
  # Given: a plain list instead of ContextVariable
  # When:  constructing a ContextSchema
  # Then:  validation error
  expect_error(
    ContextSchema(variables = list(list(name = "x"))),
    "must be a ContextVariable"
  )
})

test_that("ContextSchema: error with non-DataExpectation in data_expectations", {
  # Given: a plain list instead of DataExpectation
  # When:  constructing a ContextSchema
  # Then:  validation error
  expect_error(
    ContextSchema(
      variables = list(
        ContextVariable(
          name = "k",
          description = "test",
          available_from = "data_loaded",
          source_expression = "nrow(data)"
        )
      ),
      data_expectations = list(list(column = "x"))
    ),
    "must be a DataExpectation"
  )
})

# -- Boundary cases -----------------------------------------------------------

test_that("ContextVariable: NULL name rejected", {
  # Given: NULL as name
  # When:  constructing a ContextVariable
  # Then:  type error
  expect_error(
    ContextVariable(
      name = NULL,
      description = "test",
      available_from = "data_loaded",
      source_expression = "x"
    )
  )
})

test_that("ContextVariable: whitespace-only description accepted", {
  # Given: whitespace-only description (non-empty string)
  # When:  constructing a ContextVariable
  # Then:  accepted (validator checks length, not content)
  cv <- ContextVariable(
    name = "x",
    description = "   ",
    available_from = "data_loaded",
    source_expression = "x"
  )
  expect_equal(cv@description, "   ")
})

test_that("DataExpectation: defaults for required", {
  # Given: required = TRUE (default boundary)
  # When:  constructing a DataExpectation
  # Then:  required is TRUE
  de <- DataExpectation(column = "x", role = "outcome", required = TRUE)
  expect_true(de@required)
})

test_that("ContextSchema: single variable accepted", {
  # Given: exactly one variable (minimum valid)
  # When:  constructing a ContextSchema
  # Then:  valid schema
  cs <- ContextSchema(
    variables = list(
      ContextVariable(
        name = "k",
        description = "count",
        available_from = "data_loaded",
        source_expression = "nrow(d)"
      )
    )
  )
  expect_length(cs@variables, 1L)
})

test_that("ContextSchema: multiple data expectations accepted", {
  # Given: several data expectations
  # When:  constructing a ContextSchema
  # Then:  all stored
  cs <- ContextSchema(
    variables = list(
      ContextVariable(
        name = "k",
        description = "count",
        available_from = "data_loaded",
        source_expression = "nrow(d)"
      )
    ),
    data_expectations = list(
      DataExpectation(column = "a", role = "outcome", required = TRUE),
      DataExpectation(column = "b", role = "group", required = FALSE),
      DataExpectation(column = "c", role = "study_id", required = TRUE)
    )
  )
  expect_length(cs@data_expectations, 3L)
})

# -- YAML Reader --------------------------------------------------------------

test_that("read_context_schema: valid YAML round-trip", {
  # Given: the metabin example fixture (5 variables + 5 expectations)
  # When:  reading the YAML file
  # Then:  ContextSchema has correct structure
  path <- test_path("fixtures", "context_schema_valid.yaml")
  cs <- read_context_schema(path)

  expect_s3_class(cs, "bridle::ContextSchema")
  expect_length(cs@variables, 5L)
  expect_length(cs@data_expectations, 5L)

  v1 <- cs@variables[[1L]]
  expect_equal(v1@name, "k")
  expect_equal(v1@available_from, "data_loaded")
  expect_equal(v1@source_expression, "nrow(data)")
  expect_equal(v1@depends_on_node, character(0))

  v2 <- cs@variables[[2L]]
  expect_equal(v2@name, "I2")
  expect_equal(v2@available_from, "post_fit")
  expect_equal(v2@depends_on_node, "execute_analysis")

  de1 <- cs@data_expectations[[1L]]
  expect_equal(de1@column, "event.e")
  expect_equal(de1@role, "outcome")
  expect_true(de1@required)

  de5 <- cs@data_expectations[[5L]]
  expect_equal(de5@column, "studlab")
  expect_false(de5@required)
})

test_that("read_context_schema: error on nonexistent file", {
  # Given: a path that does not exist
  # When:  reading the file
  # Then:  informative error
  expect_error(
    read_context_schema("nonexistent_file.yaml"),
    "File not found"
  )
})

test_that("read_context_schema: error on malformed YAML", {
  # Given: invalid YAML content
  # When:  reading the file
  # Then:  YAML parse error
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("variables: [invalid\n  unclosed", tmp)
  expect_error(
    read_context_schema(tmp),
    "Failed to parse YAML"
  )
})

test_that("read_context_schema: error when variables is missing", {
  # Given: YAML without variables
  # When:  reading the file
  # Then:  error about missing variables
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(data_expectations = list()), tmp)
  expect_error(read_context_schema(tmp), "variables.*non-empty")
})
