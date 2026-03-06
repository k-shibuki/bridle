# Tests for internal (non-exported) functions
# Uses ::: to access package internals — standard R package testing practice

# -- matches_any_pattern (scan_package.R) ------------------------------------

test_that("matches_any_pattern: single pattern match", {
  # Given: a name matching one regex pattern
  # When:  checking against pattern list
  # Then:  returns TRUE
  expect_true(bridle:::matches_any_pattern("method.tau", c("^method\\.")))
})

test_that("matches_any_pattern: no match", {
  # Given: a name not matching any pattern
  # When:  checking against pattern list
  # Then:  returns FALSE
  expect_false(bridle:::matches_any_pattern("data", c("^method\\.", "^tau")))
})

test_that("matches_any_pattern: empty patterns list", {
  # Given: empty pattern vector
  # When:  checking any name
  # Then:  returns FALSE
  expect_false(bridle:::matches_any_pattern("anything", character(0)))
})

test_that("matches_any_pattern: multiple patterns, second matches", {
  # Given: name matches second pattern but not first
  # When:  checking against pattern list
  # Then:  returns TRUE
  expect_true(bridle:::matches_any_pattern(
    "tau_method",
    c("^method\\.", "^tau")
  ))
})

test_that("matches_any_pattern: exact match with anchored pattern", {
  # Given: exact name with ^$ anchored pattern
  # When:  checking
  # Then:  matches correctly
  expect_true(bridle:::matches_any_pattern("sm", c("^sm$")))
  expect_false(bridle:::matches_any_pattern("smx", c("^sm$")))
})

# -- safe_formals (scan_package.R) -------------------------------------------

test_that("safe_formals: NULL input returns empty list", {
  # Given: NULL formals (e.g., from a primitive)
  # When:  converting with safe_formals
  # Then:  returns empty list
  result <- bridle:::safe_formals(NULL)
  expect_equal(result, list())
})

test_that("safe_formals: default values preserved", {
  # Given: a function with default values
  # When:  converting formals
  # Then:  defaults are preserved
  fn <- function(x = 1, y = "a") NULL
  result <- bridle:::safe_formals(formals(fn))
  expect_equal(result$x, 1)
  expect_equal(result$y, "a")
})

test_that("safe_formals: missing args get sentinel", {
  # Given: a function with no-default argument
  # When:  converting formals
  # Then:  missing arg gets .missing_sentinel class
  fn <- function(x, y = 1) NULL
  result <- bridle:::safe_formals(formals(fn))
  expect_true(inherits(result$x, "bridle_missing_formal"))
  expect_equal(result$y, 1)
})

test_that("safe_formals: preserves all names", {
  # Given: a function with several arguments
  # When:  converting formals
  # Then:  all names are present in result
  fn <- function(a, b = 2, c = "x") NULL
  result <- bridle:::safe_formals(formals(fn))
  expect_equal(names(result), c("a", "b", "c"))
})

# -- is_formal_missing (scan_package.R) --------------------------------------

test_that("is_formal_missing: detects missing formal", {
  # Given: safe_formals result with missing arg
  # When:  checking with is_formal_missing
  # Then:  returns TRUE for missing, FALSE for present
  fn <- function(x, y = 1) NULL
  fmls <- bridle:::safe_formals(formals(fn))
  expect_true(bridle:::is_formal_missing(fmls, "x"))
  expect_false(bridle:::is_formal_missing(fmls, "y"))
})

# -- collect_constraint_params (validate_plugin.R) ---------------------------

test_that("collect_constraint_params: param only", {
  # Given: a constraint with only param set
  # When:  collecting params
  # Then:  returns the param name
  cst <- Constraint( # nolint: object_usage_linter.
    id = "c1", source = "formals_default", type = "valid_values", param = "sm",
    values = c("RR", "OR")
  )
  result <- bridle:::collect_constraint_params(cst)
  expect_equal(result, "sm")
})

test_that("collect_constraint_params: param + forces", {
  # Given: a constraint with param and forces
  # When:  collecting params
  # Then:  returns unique union
  cst <- Constraint( # nolint: object_usage_linter.
    id = "c1", source = "formals_default", type = "forces", param = "method",
    forces = list(sm = "OR")
  )
  result <- bridle:::collect_constraint_params(cst)
  expect_true("method" %in% result)
  expect_true("sm" %in% result)
})

test_that("collect_constraint_params: deduplication", {
  # Given: a constraint where param appears in forces too
  # When:  collecting params
  # Then:  no duplicates
  cst <- Constraint( # nolint: object_usage_linter.
    id = "c1", source = "formals_default", type = "forces", param = "sm",
    forces = list(sm = "OR")
  )
  result <- bridle:::collect_constraint_params(cst)
  expect_equal(length(result), length(unique(result)))
})

# -- compute_node_order (validate_plugin.R) ----------------------------------

test_that("compute_node_order: linear graph", {
  # Given: a -> b -> c linear graph
  # When:  computing node order
  # Then:  returns sequential order 1, 2, 3
  graph <- make_graph(
    nodes = list(
      a = Node( # nolint: object_usage_linter.
        type = "decision",
        transitions = list(Transition(to = "b", always = TRUE)) # nolint: object_usage_linter.
      ),
      b = Node( # nolint: object_usage_linter.
        type = "decision",
        transitions = list(Transition(to = "c", always = TRUE)) # nolint: object_usage_linter.
      ),
      c = Node(type = "execution", transitions = list()) # nolint: object_usage_linter.
    ),
    entry = "a"
  )
  order <- bridle:::compute_node_order(graph)
  expect_equal(order[["a"]], 1L)
  expect_equal(order[["b"]], 2L)
  expect_equal(order[["c"]], 3L)
})

test_that("compute_node_order: branching graph", {
  # Given: a -> b, a -> c branching graph
  # When:  computing node order (BFS)
  # Then:  a first, b and c in order 2 and 3
  graph <- make_graph(
    nodes = list(
      a = Node( # nolint: object_usage_linter.
        type = "decision",
        transitions = list(
          Transition(to = "b", when = "cond1"), # nolint: object_usage_linter.
          Transition(to = "c", otherwise = TRUE) # nolint: object_usage_linter.
        )
      ),
      b = Node(type = "execution", transitions = list()), # nolint: object_usage_linter.
      c = Node(type = "execution", transitions = list()) # nolint: object_usage_linter.
    ),
    entry = "a"
  )
  order <- bridle:::compute_node_order(graph)
  expect_equal(order[["a"]], 1L)
  expect_true(order[["b"]] %in% c(2L, 3L))
  expect_true(order[["c"]] %in% c(2L, 3L))
})

test_that("compute_node_order: single node", {
  # Given: a graph with one node
  # When:  computing node order
  # Then:  returns that node as order 1
  graph <- make_graph(
    nodes = list(
      only = Node(type = "execution", transitions = list()) # nolint: object_usage_linter.
    ),
    entry = "only"
  )
  order <- bridle:::compute_node_order(graph)
  expect_equal(order[["only"]], 1L)
  expect_length(order, 1L)
})
