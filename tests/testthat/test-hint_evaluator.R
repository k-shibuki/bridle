# Tests for evaluate_hint() — shared hint expression evaluator (ADR-0003)

test_that("hint eval returns TRUE when expression is true", {
  result <- evaluate_hint("k < 5", variables = list(k = 3))
  expect_true(result)
})

test_that("hint eval returns FALSE when expression is false", {
  result <- evaluate_hint("k < 5", variables = list(k = 10))
  expect_false(result)
})

test_that("hint eval returns NA when variable is unavailable", {
  expect_warning(
    result <- evaluate_hint("I2 > 50", variables = list(k = 3)),
    "eval error"
  )
  expect_true(is.na(result))
})

test_that("hint eval returns NA with warning on syntax error", {
  expect_warning(
    result <- evaluate_hint("k <", variables = list(k = 3)),
    "parse error"
  )
  expect_true(is.na(result))
})

test_that("hint eval returns NA with warning on runtime error", {
  expect_warning(
    result <- evaluate_hint("stop('bad')", variables = list()),
    "eval error"
  )
  expect_true(is.na(result))
})

test_that("hint eval returns NA on timeout (infinite loop)", {
  expect_warning(
    result <- evaluate_hint("while(TRUE) 1", variables = list(), timeout_s = 0.1)
  )
  expect_true(is.na(result))
})

test_that("hint eval blocks system() via baseenv sandbox", {
  expect_warning(
    result <- evaluate_hint("system('ls')", variables = list()),
    "eval error"
  )
  expect_true(is.na(result))
})

test_that("hint eval handles empty string expression", {
  result <- evaluate_hint("", variables = list())
  expect_true(is.na(result))
})

test_that("hint eval handles NULL expression", {
  result <- evaluate_hint(NULL, variables = list())
  expect_true(is.na(result))
})

test_that("hint eval handles non-character expression", {
  result <- evaluate_hint(42, variables = list())
  expect_true(is.na(result))
})

test_that("hint eval handles numeric result coercion", {
  result <- evaluate_hint("1", variables = list())
  expect_true(result)
})

test_that("hint eval handles complex logical expressions", {
  result <- evaluate_hint(
    "k >= 5 && I2 < 75",
    variables = list(k = 10, I2 = 50)
  )
  expect_true(result)
})

test_that("hint eval handles NaN producing expressions", {
  expect_warning(
    result <- evaluate_hint("log(-1) > 0", variables = list())
  )
  expect_true(is.na(result))
})

test_that("hint eval with empty variables list works for constant", {
  result <- evaluate_hint("TRUE", variables = list())
  expect_true(result)
})

test_that("hint eval with whitespace-only expression returns NA", {
  result <- evaluate_hint("   ", variables = list())
  expect_true(is.na(result))
})
