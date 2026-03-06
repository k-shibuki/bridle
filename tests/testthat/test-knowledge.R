# Tests for KnowledgeStore S7 classes
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# -- CompetingView ------------------------------------------------------------

test_that("CompetingView: valid construction", {
  # Given: valid view and source strings
  # When:  constructing a CompetingView
  # Then:  both fields are stored correctly
  cv <- CompetingView(view = "use DL", source = "Cochrane Handbook")
  expect_equal(cv@view, "use DL")
  expect_equal(cv@source, "Cochrane Handbook")
})

test_that("CompetingView: error when view is empty", {
  # Given: empty view string
  # When:  constructing a CompetingView
  # Then:  validation error
  expect_error(
    CompetingView(view = "", source = "some source"),
    "view.*non-empty"
  )
})

test_that("CompetingView: error when source is empty", {
  # Given: empty source string
  # When:  constructing a CompetingView
  # Then:  validation error
  expect_error(
    CompetingView(view = "some view", source = ""),
    "source.*non-empty"
  )
})

# -- KnowledgeEntry -----------------------------------------------------------

test_that("KnowledgeEntry: valid construction with all fields", {
  # Given: all fields including optional ones
  # When:  constructing a KnowledgeEntry
  # Then:  all fields stored correctly
  entry <- KnowledgeEntry(
    id = "tau2_small_k",
    when = "number of studies is small",
    computable_hint = "k < 5",
    properties = c("PM is robust", "DL underestimates"),
    related = "consider HK adjustment",
    competing_views = list(
      CompetingView(view = "use DL", source = "Cochrane")
    ),
    references = "Veroniki (2016)"
  )
  expect_equal(entry@id, "tau2_small_k")
  expect_equal(entry@when, "number of studies is small")
  expect_equal(entry@computable_hint, "k < 5")
  expect_length(entry@properties, 2L)
  expect_length(entry@competing_views, 1L)
})

test_that("KnowledgeEntry: valid with default optional fields", {
  # Given: only required fields
  # When:  constructing a KnowledgeEntry
  # Then:  optional fields have empty defaults
  entry <- KnowledgeEntry(
    id = "test",
    when = "always",
    properties = "some fact"
  )
  expect_equal(entry@computable_hint, character(0))
  expect_equal(entry@related, character(0))
  expect_equal(entry@competing_views, list())
  expect_equal(entry@references, character(0))
})

test_that("KnowledgeEntry: error when id is missing", {
  # Given: empty id
  # When:  constructing a KnowledgeEntry
  # Then:  validation error
  expect_error(
    KnowledgeEntry(id = "", when = "always", properties = "fact"),
    "id.*non-empty"
  )
})

test_that("KnowledgeEntry: error when when is missing", {
  # Given: empty when
  # When:  constructing a KnowledgeEntry
  # Then:  validation error
  expect_error(
    KnowledgeEntry(id = "test", when = "", properties = "fact"),
    "when.*non-empty"
  )
})

test_that("KnowledgeEntry: error when properties is empty", {
  # Given: empty properties vector
  # When:  constructing a KnowledgeEntry
  # Then:  validation error
  expect_error(
    KnowledgeEntry(id = "test", when = "always", properties = character(0)),
    "properties.*at least one"
  )
})

test_that("KnowledgeEntry: error with non-CompetingView in competing_views", {
  # Given: a plain list instead of CompetingView
  # When:  constructing a KnowledgeEntry
  # Then:  validation error
  expect_error(
    KnowledgeEntry(
      id = "test",
      when = "always",
      properties = "fact",
      competing_views = list(list(view = "x", source = "y"))
    ),
    "must be a CompetingView"
  )
})

# -- KnowledgeStore -----------------------------------------------------------

test_that("KnowledgeStore: valid construction", {
  # Given: topic, target_parameter, package, func, and valid entries
  # When:  constructing a KnowledgeStore
  # Then:  all fields stored correctly
  ks <- KnowledgeStore(
    topic = "tau2_estimators",
    target_parameter = "method.tau",
    package = "meta",
    func = "metabin",
    entries = list(
      KnowledgeEntry(id = "e1", when = "cond1", properties = "fact1"),
      KnowledgeEntry(id = "e2", when = "cond2", properties = "fact2")
    )
  )
  expect_equal(ks@topic, "tau2_estimators")
  expect_equal(ks@target_parameter, "method.tau")
  expect_length(ks@entries, 2L)
})

test_that("KnowledgeStore: valid with multiple target_parameters", {
  # Given: target_parameter as character vector
  # When:  constructing a KnowledgeStore
  # Then:  all parameters stored
  ks <- KnowledgeStore(
    topic = "test",
    target_parameter = c("sm", "method"),
    package = "meta",
    func = "metabin",
    entries = list(
      KnowledgeEntry(id = "e1", when = "cond", properties = "fact")
    )
  )
  expect_equal(ks@target_parameter, c("sm", "method"))
})

test_that("KnowledgeStore: error when topic is missing", {
  # Given: empty topic
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "",
      target_parameter = "p",
      package = "meta",
      func = "metabin",
      entries = list(
        KnowledgeEntry(id = "e1", when = "c", properties = "f")
      )
    ),
    "topic.*non-empty"
  )
})

test_that("KnowledgeStore: error when entries is empty", {
  # Given: empty entries list
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "t",
      target_parameter = "p",
      package = "meta",
      func = "metabin",
      entries = list()
    ),
    "entries.*at least one"
  )
})

test_that("KnowledgeStore: error with duplicate entry IDs", {
  # Given: two entries with the same id
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "t",
      target_parameter = "p",
      package = "meta",
      func = "metabin",
      entries = list(
        KnowledgeEntry(id = "dup", when = "c1", properties = "f1"),
        KnowledgeEntry(id = "dup", when = "c2", properties = "f2")
      )
    ),
    "Duplicate entry id.*dup"
  )
})

test_that("KnowledgeStore: error with non-KnowledgeEntry in entries", {
  # Given: a plain list instead of KnowledgeEntry
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "t",
      target_parameter = "p",
      package = "meta",
      func = "metabin",
      entries = list(list(id = "x", when = "y"))
    ),
    "must be a KnowledgeEntry"
  )
})

test_that("KnowledgeStore: error when package is empty", {
  # Given: empty package name
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "t",
      target_parameter = "p",
      package = "",
      func = "metabin",
      entries = list(
        KnowledgeEntry(id = "e1", when = "c", properties = "f")
      )
    ),
    "package.*non-empty"
  )
})

test_that("KnowledgeStore: error when func is empty", {
  # Given: empty function name
  # When:  constructing a KnowledgeStore
  # Then:  validation error
  expect_error(
    KnowledgeStore(
      topic = "t",
      target_parameter = "p",
      package = "meta",
      func = "",
      entries = list(
        KnowledgeEntry(id = "e1", when = "c", properties = "f")
      )
    ),
    "func.*non-empty"
  )
})

# -- YAML Reader --------------------------------------------------------------

test_that("read_knowledge: valid YAML round-trip", {
  # Given: the tau2_estimators example fixture
  # When:  reading the YAML file
  # Then:  KnowledgeStore has correct structure
  path <- test_path("fixtures", "knowledge_valid.yaml")
  ks <- read_knowledge(path)

  expect_s3_class(ks, "bridle::KnowledgeStore")
  expect_equal(ks@topic, "tau2_estimators")
  expect_equal(ks@target_parameter, "method.tau")
  expect_equal(ks@package, "meta")
  expect_equal(ks@func, "metabin")
  expect_length(ks@entries, 4L)

  e1 <- ks@entries[[1L]]
  expect_equal(e1@id, "tau2_small_k")
  expect_equal(e1@computable_hint, "k < 5")
  expect_length(e1@properties, 3L)
  expect_length(e1@related, 1L)
  expect_length(e1@references, 2L)

  e4 <- ks@entries[[4L]]
  expect_equal(e4@id, "tau2_cochrane_default")
  expect_length(e4@competing_views, 2L)
  expect_equal(e4@competing_views[[1L]]@view, "use DL (Cochrane standard)")
  expect_equal(e4@computable_hint, character(0))
})

test_that("read_knowledge: error on nonexistent file", {
  # Given: a path that does not exist
  # When:  reading the file
  # Then:  informative error
  expect_error(
    read_knowledge("nonexistent_file.yaml"),
    "File not found"
  )
})

test_that("read_knowledge: error on malformed YAML", {
  # Given: invalid YAML content
  # When:  reading the file
  # Then:  YAML parse error
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("topic: [invalid\n  unclosed", tmp)
  expect_error(
    read_knowledge(tmp),
    "Failed to parse YAML"
  )
})

test_that("read_knowledge: error when topic is missing", {
  # Given: YAML without topic field
  # When:  reading the file
  # Then:  error about missing topic
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(
    target_parameter = "p",
    package = "meta",
    `function` = "metabin",
    entries = list(list(id = "e1", when = "c", properties = list("f")))
  ), tmp)
  expect_error(read_knowledge(tmp), "topic.*required")
})

test_that("read_knowledge: error when entries is missing", {
  # Given: YAML without entries
  # When:  reading the file
  # Then:  error about missing entries
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(
    topic = "t",
    target_parameter = "p",
    package = "meta",
    `function` = "metabin"
  ), tmp)
  expect_error(read_knowledge(tmp), "entries.*non-empty")
})
