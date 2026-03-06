# Tests for KnowledgeRetriever (Issue #58)
# make_session_context() and S7 constructors live in helper-mocks.R.

# -- Helpers -------------------------------------------------------------------

make_entry <- function(id = "e1", when = "always", hint = character(0),
                       props = "some fact") {
  KnowledgeEntry( # nolint: object_usage_linter. S7 class in R/knowledge.R
    id = id, when = when, computable_hint = hint, properties = props
  )
}

make_store <- function(topic = "effect_measure",
                       entries = list(make_entry())) {
  KnowledgeStore( # nolint: object_usage_linter. S7 class in R/knowledge.R
    topic = topic,
    target_parameter = "sm",
    package = "meta",
    func = "metabin",
    entries = entries
  )
}

make_cst <- function(id = "c1", param = "sm", enabled_when = character(0)) {
  Constraint( # nolint: object_usage_linter. S7 class in R/constraints.R
    id = id, source = "expert", type = "valid_values",
    param = param, values = c("OR", "RR"),
    enabled_when = enabled_when
  )
}

make_cst_set <- function(constraints = list(make_cst())) {
  ConstraintSet( # nolint: object_usage_linter. S7 class in R/constraints.R
    package = "meta", func = "metabin", constraints = constraints
  )
}

# -- RetrievalResult S7 class --------------------------------------------------

test_that("RetrievalResult constructs with defaults", {
  rr <- RetrievalResult() # nolint: object_usage_linter.
  expect_equal(length(rr@entries), 0L)
  expect_equal(length(rr@entry_ids_presented), 0L)
  expect_equal(length(rr@constraints), 0L)
})

test_that("RetrievalResult validates entry types", {
  expect_error(
    RetrievalResult(entries = list("not_an_entry"), entry_ids_presented = "x"), # nolint: object_usage_linter.
    "KnowledgeEntry"
  )
})

test_that("RetrievalResult validates constraint types", {
  expect_error(
    RetrievalResult(constraints = list("not_a_constraint")), # nolint: object_usage_linter.
    "Constraint"
  )
})

test_that("RetrievalResult validates ids length matches entries", {
  e <- make_entry()
  expect_error(
    RetrievalResult(entries = list(e), entry_ids_presented = character(0)), # nolint: object_usage_linter.
    "length"
  )
})

# -- retrieve_knowledge: topic filter ------------------------------------------

test_that("retrieve_knowledge returns entries matching topic", {
  ctx <- make_session_context()
  store <- make_store(topic = "effect_measure")
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(length(result@entries), 1L)
  expect_equal(result@entry_ids_presented, "e1")
})

test_that("retrieve_knowledge returns empty for unknown topic", {
  ctx <- make_session_context()
  store <- make_store(topic = "effect_measure")
  result <- retrieve_knowledge(list(store), "unknown_topic", ctx)
  expect_equal(length(result@entries), 0L)
  expect_equal(length(result@entry_ids_presented), 0L)
})

# -- retrieve_knowledge: when conditions ---------------------------------------

test_that("entry with hint TRUE is included", {
  ctx <- make_session_context(variables = list(k = 3L))
  e <- make_entry(id = "e1", when = "few studies", hint = "k < 5")
  store <- make_store(entries = list(e))
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(length(result@entries), 1L)
})

test_that("entry with hint FALSE is excluded", {
  ctx <- make_session_context(variables = list(k = 10L))
  e <- make_entry(id = "e1", when = "few studies", hint = "k < 5")
  store <- make_store(entries = list(e))
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(length(result@entries), 0L)
})

test_that("entry with when but no hint is always included", {
  ctx <- make_session_context()
  e <- make_entry(id = "e1", when = "complex condition")
  store <- make_store(entries = list(e))
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(length(result@entries), 1L)
})

test_that("entry with unevaluable hint is included (NA fallback)", {
  ctx <- make_session_context()
  e <- make_entry(id = "e1", when = "needs data", hint = "k < 5")
  store <- make_store(entries = list(e))
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(length(result@entries), 1L)
})

# -- retrieve_knowledge: multi-store -------------------------------------------

test_that("entries from multiple stores with same topic are merged", {
  ctx <- make_session_context()
  e1 <- make_entry(id = "e1", when = "c1", props = "fact1")
  e2 <- make_entry(id = "e2", when = "c2", props = "fact2")
  s1 <- make_store(entries = list(e1))
  s2 <- make_store(entries = list(e2))
  result <- retrieve_knowledge(list(s1, s2), "effect_measure", ctx)
  expect_equal(length(result@entries), 2L)
  expect_equal(result@entry_ids_presented, c("e1", "e2"))
})

test_that("duplicate entry IDs across stores are deduplicated", {
  ctx <- make_session_context()
  e <- make_entry(id = "e1", when = "c1")
  s1 <- make_store(entries = list(e))
  s2 <- make_store(entries = list(e))
  result <- retrieve_knowledge(list(s1, s2), "effect_measure", ctx)
  expect_equal(length(result@entries), 1L)
})

# -- retrieve_knowledge: boundary ----------------------------------------------

test_that("empty stores list returns empty result", {
  ctx <- make_session_context()
  result <- retrieve_knowledge(list(), "effect_measure", ctx)
  expect_equal(length(result@entries), 0L)
})

test_that("entry_ids_presented has correct IDs", {
  ctx <- make_session_context()
  e1 <- make_entry(id = "alpha", when = "c1")
  e2 <- make_entry(id = "beta", when = "c2")
  store <- make_store(entries = list(e1, e2))
  result <- retrieve_knowledge(list(store), "effect_measure", ctx)
  expect_equal(result@entry_ids_presented, c("alpha", "beta"))
})

# -- retrieve_constraints: parameter filter ------------------------------------

test_that("retrieve_constraints returns matching constraints", {
  ctx <- make_session_context()
  cs <- make_cst_set()
  result <- retrieve_constraints(list(cs), "sm", ctx)
  expect_equal(length(result), 1L)
})

test_that("retrieve_constraints excludes non-matching param", {
  ctx <- make_session_context()
  c1 <- make_cst(id = "c1", param = "sm")
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "method", ctx)
  expect_equal(length(result), 0L)
})

# -- retrieve_constraints: enabled_when ----------------------------------------

test_that("constraint with enabled_when TRUE is included", {
  ctx <- make_session_context(variables = list(k = 3L))
  c1 <- make_cst(id = "c1", enabled_when = "k < 5")
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "sm", ctx)
  expect_equal(length(result), 1L)
})

test_that("constraint with enabled_when FALSE is excluded", {
  ctx <- make_session_context(variables = list(k = 10L))
  c1 <- make_cst(id = "c1", enabled_when = "k < 5")
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "sm", ctx)
  expect_equal(length(result), 0L)
})

test_that("constraint without enabled_when is always included", {
  ctx <- make_session_context()
  c1 <- make_cst(id = "c1")
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "sm", ctx)
  expect_equal(length(result), 1L)
})

test_that("constraint with unevaluable enabled_when is included", {
  ctx <- make_session_context()
  c1 <- make_cst(id = "c1", enabled_when = "missing_var > 0")
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "sm", ctx)
  expect_equal(length(result), 1L)
})

# -- retrieve_constraints: boundary --------------------------------------------

test_that("empty constraint_sets returns empty list", {
  ctx <- make_session_context()
  result <- retrieve_constraints(list(), "sm", ctx)
  expect_equal(length(result), 0L)
})

test_that("constraint with empty param matches any parameter", {
  ctx <- make_session_context()
  c1 <- make_cst(id = "c1", param = character(0))
  cs <- make_cst_set(constraints = list(c1))
  result <- retrieve_constraints(list(cs), "any_param", ctx)
  expect_equal(length(result), 1L)
})

# -- Input validation ----------------------------------------------------------

test_that("retrieve_knowledge validates stores argument", {
  ctx <- make_session_context()
  expect_error(retrieve_knowledge("not_a_list", "t", ctx), "list")
})

test_that("retrieve_knowledge validates topic argument", {
  ctx <- make_session_context()
  expect_error(retrieve_knowledge(list(), 42, ctx), "character")
})

test_that("retrieve_knowledge validates context argument", {
  expect_error(retrieve_knowledge(list(), "t", "not_ctx"), "SessionContext")
})

test_that("retrieve_constraints validates constraint_sets", {
  ctx <- make_session_context()
  expect_error(retrieve_constraints("x", "p", ctx), "list")
})

test_that("retrieve_constraints validates parameter", {
  ctx <- make_session_context()
  expect_error(retrieve_constraints(list(), 42, ctx), "character")
})

test_that("retrieve_constraints validates context", {
  expect_error(retrieve_constraints(list(), "p", "x"), "SessionContext")
})
