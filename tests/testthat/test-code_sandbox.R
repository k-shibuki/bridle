# Tests for CodeSandbox (Issue #64)

# -- CodeSandbox S7 class ------------------------------------------------------

test_that("CodeSandbox constructs with defaults", {
  sb <- CodeSandbox() # nolint: object_usage_linter. S7 class in R/code_sandbox.R
  expect_true(length(sb@allowed_packages) > 0L)
  expect_equal(sb@timeout_s, 10.0)
  expect_null(sb@max_memory_mb)
})

test_that("CodeSandbox validates timeout_s", {
  expect_error(
    CodeSandbox(timeout_s = -1), # nolint: object_usage_linter. S7 class
    "positive"
  )
})

test_that("CodeSandbox validates allowed_packages", {
  expect_error(
    CodeSandbox(allowed_packages = character(0)), # nolint: object_usage_linter.
    "at least one"
  )
})

test_that("CodeSandbox validates max_memory_mb", {
  expect_error(
    CodeSandbox(max_memory_mb = -1), # nolint: object_usage_linter.
    "positive"
  )
})

# -- CodeResult S7 class -------------------------------------------------------

test_that("CodeResult constructs correctly", {
  cr <- CodeResult(success = TRUE, value = 42, elapsed_s = 0.1) # nolint: object_usage_linter.
  expect_true(cr@success)
  expect_equal(cr@value, 42)
  expect_equal(cr@elapsed_s, 0.1)
})

test_that("CodeResult validates success", {
  expect_error(
    CodeResult(success = c(TRUE, FALSE), value = NULL, elapsed_s = 0), # nolint: object_usage_linter.
    "single logical"
  )
})

# -- bridle_eval_code: basic expressions ---------------------------------------

test_that("simple expression evaluates correctly", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("1 + 1", sb)
  expect_true(result@success)
  expect_equal(result@value, 2)
})

test_that("multi-line code returns last value", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("x <- 10\ny <- 20\nx + y", sb)
  expect_true(result@success)
  expect_equal(result@value, 30)
})

test_that("data manipulation with nrow()", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  df <- data.frame(a = 1:5, b = 6:10)
  result <- bridle_eval_code("nrow(data)", sb, data = df)
  expect_true(result@success)
  expect_equal(result@value, 5L)
})

test_that("parameters are accessible inside sandbox", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code(
    "parameters$sm", sb,
    parameters = list(sm = "OR")
  )
  expect_true(result@success)
  expect_equal(result@value, "OR")
})

# -- bridle_eval_code: output capture ------------------------------------------

test_that("cat() output is captured", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('cat("hello"); 42', sb)
  expect_true(result@success)
  expect_equal(result@value, 42)
  expect_true(grepl("hello", result@output))
})

# -- bridle_eval_code: warnings ------------------------------------------------

test_that("warnings are captured", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("log(-1)", sb)
  expect_true(result@success)
  expect_true(is.nan(result@value))
  expect_true(length(result@warnings) > 0L)
})

# -- bridle_eval_code: blocked functions ---------------------------------------

test_that("system() is blocked", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('system("ls")', sb)
  expect_false(result@success)
  expect_true(grepl("blocked", result@error))
})

test_that("file.remove() is blocked", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('file.remove("x")', sb)
  expect_false(result@success)
  expect_true(grepl("blocked", result@error))
})

test_that("download.file() is blocked", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('download.file("http://x", "y")', sb)
  expect_false(result@success)
  expect_true(grepl("blocked", result@error))
})

test_that("writeLines() is blocked", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('writeLines("x", "hack.txt")', sb)
  expect_false(result@success)
  expect_true(grepl("blocked", result@error))
})

test_that("Sys.setenv() is blocked", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('Sys.setenv(PATH = "/tmp")', sb)
  expect_false(result@success)
  expect_true(grepl("blocked", result@error))
})

# -- bridle_eval_code: error handling ------------------------------------------

test_that("syntax error is caught", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("if (", sb)
  expect_false(result@success)
  expect_true(grepl("parse error", result@error))
})

test_that("runtime error is caught", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code('stop("bad input")', sb)
  expect_false(result@success)
  expect_true(grepl("bad input", result@error))
})

test_that("timeout is enforced", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 0.5) # nolint: object_usage_linter.
  result <- bridle_eval_code("while(TRUE) 1", sb)
  expect_false(result@success)
  expect_true(grepl("timeout", result@error))
})

# -- bridle_eval_code: boundary ------------------------------------------------

test_that("empty code returns NULL success", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("", sb)
  expect_true(result@success)
  expect_null(result@value)
})

test_that("whitespace-only code returns NULL success", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("   \n  ", sb)
  expect_true(result@success)
  expect_null(result@value)
})

# -- bridle_eval_code: custom packages -----------------------------------------

test_that("stats functions available when allowed", {
  sb <- CodeSandbox(allowed_packages = c("base", "stats"), timeout_s = 2) # nolint: object_usage_linter.
  result <- bridle_eval_code("median(c(1, 2, 3, 4, 5))", sb)
  expect_true(result@success)
  expect_equal(result@value, 3)
})

# -- Input validation ----------------------------------------------------------

test_that("bridle_eval_code rejects non-character code", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  expect_error(bridle_eval_code(42, sb), "character")
})

test_that("bridle_eval_code rejects non-CodeSandbox", {
  expect_error(bridle_eval_code("1", "not_sandbox"), "CodeSandbox")
})

test_that("bridle_eval_code rejects NULL code", {
  sb <- CodeSandbox(allowed_packages = "base", timeout_s = 2) # nolint: object_usage_linter.
  expect_error(bridle_eval_code(NULL, sb), "character")
})
