# Tests for build_graph() — template composition (ADR-0009)
# Issue #148: 9 scenarios (T01-T09)

fixture_dir <- testthat::test_path("fixtures", "template-test")

test_that("T01: simple merge produces flat graph with all nodes", {
  # Given: template with 3 nodes (mid_start→mid_step→mid_end),
  #        function graph with 2 nodes (start→mid_start, finish)
  # When:  build_graph(decision_graph.yaml)
  # Then:  flat graph with 5 nodes; start→mid_start→mid_step→mid_end→finish
  path <- file.path(fixture_dir, "decision_graph.yaml")
  graph <- build_graph(path)

  expect_s3_class(graph, "bridle::DecisionGraph")
  expect_equal(graph@entry_node, "start")
  expect_length(graph@nodes, 5L)
  expect_true(all(
    c("start", "mid_start", "mid_step", "mid_end", "finish") %in%
      names(graph@nodes)
  ))

  mid_end <- graph@nodes[["mid_end"]]
  expect_length(mid_end@transitions, 1L)
  expect_equal(mid_end@transitions[[1L]]@to, "finish")
})

test_that("T02: no template key falls through to read_decision_graph", {
  # Given: YAML without graph.template
  # When:  build_graph(no_template.yaml)
  # Then:  returns valid DecisionGraph
  path <- file.path(fixture_dir, "no_template.yaml")
  graph <- build_graph(path)

  expect_s3_class(graph, "bridle::DecisionGraph")
  expect_equal(graph@entry_node, "only")
  expect_length(graph@nodes, 1L)
})

test_that("T03: namespace collision produces error", {
  # Given: template has node "dup", function graph also has node "dup"
  # When:  build_graph(...)
  # Then:  error about collision
  dir <- withr::local_tempdir()
  writeLines(c(
    "template:",
    "  id: conflict",
    "  entry_point: dup",
    "  exit_point: dup",
    "  nodes:",
    "    dup:",
    "      type: execution",
    "      transitions: []"
  ), file.path(dir, "conflict.template.yaml"))

  func <- file.path(dir, "graph.yaml")
  writeLines(c(
    "graph:",
    "  entry_node: dup",
    "  template: conflict",
    "  nodes:",
    "    dup:",
    "      type: execution",
    "      transitions: []"
  ), func)

  expect_error(
    build_graph(func),
    "collision"
  )
})

test_that("T04: dangling transition target produces error", {
  # Given: function graph transitions to nonexistent_node
  # When:  build_graph(...)
  # Then:  DecisionGraph validator catches dangling reference
  dir <- withr::local_tempdir()
  writeLines(c(
    "template:",
    "  id: dangling",
    "  entry_point: t1",
    "  exit_point: t1",
    "  nodes:",
    "    t1:",
    "      type: execution",
    "      transitions: []"
  ), file.path(dir, "dangling.template.yaml"))

  func <- file.path(dir, "graph.yaml")
  writeLines(c(
    "graph:",
    "  entry_node: start",
    "  template: dangling",
    "  nodes:",
    "    start:",
    "      type: execution",
    "      transitions:",
    "        - to: nonexistent",
    "          always: true"
  ), func)

  expect_error(
    build_graph(func),
    "nonexistent"
  )
})

test_that("T05: template file not found produces error", {
  func <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c(
    "graph:",
    "  entry_node: s",
    "  template: missing_template",
    "  nodes:",
    "    s:",
    "      type: execution",
    "      transitions: []"
  ), func)

  expect_error(
    build_graph(func),
    "not found"
  )
})

test_that("T06: missing exit_point in template produces error", {
  dir <- withr::local_tempdir()
  writeLines(c(
    "template:",
    "  id: noxit",
    "  entry_point: t1",
    "  exit_point: missing",
    "  nodes:",
    "    t1:",
    "      type: execution",
    "      transitions: []"
  ), file.path(dir, "noxit.template.yaml"))

  func <- file.path(dir, "graph.yaml")
  writeLines(c(
    "graph:",
    "  entry_node: s",
    "  template: noxit",
    "  nodes:",
    "    s:",
    "      type: execution",
    "      transitions:",
    "        - to: t1",
    "          always: true"
  ), func)

  expect_error(
    build_graph(func),
    "exit_point.*missing.*not found"
  )
})

test_that("T07: exit_point with existing transitions warns", {
  dir <- withr::local_tempdir()
  writeLines(c(
    "template:",
    "  id: nonempty",
    "  entry_point: t1",
    "  exit_point: t1",
    "  nodes:",
    "    t1:",
    "      type: execution",
    "      transitions:",
    "        - to: t1",
    "          always: true"
  ), file.path(dir, "nonempty.template.yaml"))

  func <- file.path(dir, "graph.yaml")
  writeLines(c(
    "graph:",
    "  entry_node: s",
    "  template: nonempty",
    "  nodes:",
    "    s:",
    "      type: execution",
    "      transitions:",
    "        - to: t1",
    "          always: true",
    "    post:",
    "      type: execution",
    "      transitions: []"
  ), func)

  expect_warning(
    build_graph(func),
    "non-empty transitions"
  )
})

test_that("T08: single-node template (entry == exit) merges correctly", {
  dir <- withr::local_tempdir()
  writeLines(c(
    "template:",
    "  id: single",
    "  entry_point: only_tmpl",
    "  exit_point: only_tmpl",
    "  nodes:",
    "    only_tmpl:",
    "      type: execution",
    "      transitions: []"
  ), file.path(dir, "single.template.yaml"))

  func <- file.path(dir, "graph.yaml")
  writeLines(c(
    "graph:",
    "  entry_node: start",
    "  template: single",
    "  nodes:",
    "    start:",
    "      type: context_gathering",
    "      transitions:",
    "        - to: only_tmpl",
    "          always: true",
    "    finish:",
    "      type: context_gathering",
    "      transitions: []"
  ), func)

  graph <- build_graph(func)

  expect_length(graph@nodes, 3L)
  only_tmpl <- graph@nodes[["only_tmpl"]]
  expect_length(only_tmpl@transitions, 1L)
  expect_equal(only_tmpl@transitions[[1L]]@to, "finish")
})

test_that("T09: func_graph_path not found produces error", {
  expect_error(
    build_graph("/nonexistent/path.yaml"),
    "not found"
  )
})
