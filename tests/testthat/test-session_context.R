# Tests for SessionContext S7 class (ADR-0007)

# -- Constructor & S7 validation ----------------------------------------------

test_that("SessionContext constructs with valid schema", {
  ctx <- make_session_context()
  expect_true(S7::S7_inherits(ctx, SessionContext))
  expect_equal(length(ctx@variables), 0L)
  expect_null(ctx@data)
  expect_equal(length(ctx@parameters_decided), 0L)
})

test_that("SessionContext rejects unnamed variables list", {
  schema <- make_context()
  expect_error(
    SessionContext(schema = schema, variables = list(1, 2)),
    "named list"
  )
})

# -- is_available() -----------------------------------------------------------

test_that("is_available returns FALSE when variable not set", {
  ctx <- make_session_context()
  expect_false(is_available(ctx, "k"))
})

test_that("is_available returns TRUE after variable is set", {
  ctx <- make_session_context(variables = list(k = 10))
  expect_true(is_available(ctx, "k"))
})

test_that("is_available rejects non-SessionContext", {
  expect_error(is_available(list(), "k"), "SessionContext")
})

test_that("is_available rejects non-character variable_name", {
  ctx <- make_session_context()
  expect_error(is_available(ctx, 42), "character string")
})

# -- update_context() ---------------------------------------------------------

test_that("update_context loads data and extracts data_loaded variables", {
  ctx <- make_session_context()
  df <- data.frame(x = 1:5, y = 6:10)
  ctx2 <- update_context(ctx, data = df)
  expect_true(is.data.frame(ctx2@data))
  expect_true(is_available(ctx2, "k"))
  expect_equal(ctx2@variables$k, 5L)
})

test_that("update_context merges parameters", {
  ctx <- make_session_context()
  ctx2 <- update_context(ctx, parameters = list(sm = "RR"))
  expect_equal(ctx2@parameters_decided$sm, "RR")
})

test_that("update_context preserves existing parameters", {
  ctx <- make_session_context()
  ctx2 <- update_context(ctx, parameters = list(sm = "RR"))
  ctx3 <- update_context(ctx2, parameters = list(method = "Inverse"))
  expect_equal(ctx3@parameters_decided$sm, "RR")
  expect_equal(ctx3@parameters_decided$method, "Inverse")
})

test_that("update_context rejects non-SessionContext", {
  expect_error(update_context(list()), "SessionContext")
})

test_that("update_context rejects non-data.frame data", {
  ctx <- make_session_context()
  expect_error(update_context(ctx, data = "not a df"), "data.frame")
})

test_that("update_context rejects unnamed parameters", {
  ctx <- make_session_context()
  expect_error(update_context(ctx, parameters = list(1, 2)), "named list")
})

test_that("update_context extracts post_fit variables with fit_result", {
  schema <- ContextSchema(variables = list(
    ContextVariable(
      name = "I2",
      description = "I-squared",
      available_from = "post_fit",
      source_expression = "result$I2"
    )
  ))
  ctx <- SessionContext(schema = schema)
  fit <- list(I2 = 75.3)
  ctx2 <- update_context(ctx, fit_result = fit)
  expect_true(is_available(ctx2, "I2"))
  expect_equal(ctx2@variables$I2, 75.3)
})

# -- get_hint_variables() -----------------------------------------------------

test_that("get_hint_variables returns variables list", {
  ctx <- make_session_context(variables = list(k = 5, I2 = 30))
  vars <- get_hint_variables(ctx)
  expect_equal(vars$k, 5)
  expect_equal(vars$I2, 30)
})

test_that("get_hint_variables returns empty list for new context", {
  ctx <- make_session_context()
  vars <- get_hint_variables(ctx)
  expect_equal(length(vars), 0L)
})

test_that("get_hint_variables rejects non-SessionContext", {
  expect_error(get_hint_variables(list()), "SessionContext")
})

# -- Boundary cases -----------------------------------------------------------

test_that("SessionContext with empty schema works", {
  schema <- ContextSchema(variables = list(
    ContextVariable(
      name = "k",
      description = "number of studies",
      available_from = "data_loaded",
      source_expression = "nrow(data)"
    )
  ))
  ctx <- SessionContext(schema = schema)
  expect_equal(length(ctx@variables), 0L)
})

test_that("update_context with NULL data preserves existing data", {
  ctx <- make_session_context()
  df <- data.frame(x = 1:3)
  ctx2 <- update_context(ctx, data = df)
  ctx3 <- update_context(ctx2, parameters = list(sm = "RR"))
  expect_true(is.data.frame(ctx3@data))
  expect_equal(nrow(ctx3@data), 3L)
})
