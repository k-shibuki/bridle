# Tests for DecisionGraph S7 classes
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

test_that("Transition: valid unconditional transition", {

  # Given: a target node ID with always = TRUE
  # When:  constructing a Transition
  # Then:  object is created with correct properties

  t <- Transition(to = "node_b", always = TRUE)
  expect_equal(t@to, "node_b")
  expect_true(t@always)
  expect_equal(t@when, character(0))
  expect_equal(t@computable_hint, character(0))
  expect_true(is.na(t@otherwise))
})

test_that("Transition: valid conditional transition with when + computable_hint", {

  # Given: when text and a computable_hint

  # When:  constructing a Transition
  # Then:  both fields are stored

  t <- Transition(to = "node_c", when = "k < 5", computable_hint = "k < 5")
  expect_equal(t@when, "k < 5")
  expect_equal(t@computable_hint, "k < 5")
})

test_that("Transition: valid otherwise fallback", {
  # Given: otherwise = TRUE
  # When:  constructing a Transition
  # Then:  object is valid
  t <- Transition(to = "fallback", otherwise = TRUE)
  expect_true(t@otherwise)
})

test_that("Transition: error when no condition is specified", {
  # Given: no condition fields set
  # When:  constructing a Transition
  # Then:  validation error about missing condition
  expect_error(
    Transition(to = "node_x"),
    "exactly one"
  )
})

test_that("Transition: error when multiple conditions specified", {
  # Given: both always and when set
  # When:  constructing a Transition
  # Then:  validation error about multiple conditions
  expect_error(
    Transition(to = "node_x", always = TRUE, when = "some condition"),
    "exactly one condition"
  )
})

test_that("Transition: error when computable_hint without when", {
  # Given: computable_hint set but when is NULL
  # When:  constructing a Transition with always = TRUE
  # Then:  validation error
  expect_error(
    Transition(to = "node_x", always = TRUE, computable_hint = "k < 5"),
    "computable_hint.*only valid when.*when"
  )
})

test_that("Transition: error when always and otherwise both set", {
  # Given: both always and otherwise are TRUE
  # When:  constructing a Transition
  # Then:  validation error
  expect_error(
    Transition(to = "node_x", always = TRUE, otherwise = TRUE),
    "exactly one condition"
  )
})

test_that("NodePolicy: valid policy with all fields", {
  # Given: skip_when, skip_hint, and max_iterations
  # When:  constructing a NodePolicy
  # Then:  all fields stored correctly
  p <- NodePolicy(
    skip_when = "large k", skip_hint = "k > 100", max_iterations = 2L
  )
  expect_equal(p@skip_when, "large k")
  expect_equal(p@skip_hint, "k > 100")
  expect_equal(p@max_iterations, 2L)
})

test_that("NodePolicy: valid with default optional fields", {
  # Given: no fields set
  # When:  constructing a NodePolicy
  # Then:  all fields have empty defaults
  p <- NodePolicy()
  expect_equal(p@skip_when, character(0))
  expect_equal(p@skip_hint, character(0))
  expect_true(is.na(p@max_iterations))
})

test_that("NodePolicy: error when skip_hint without skip_when", {
  # Given: skip_hint set but skip_when is NULL
  # When:  constructing a NodePolicy
  # Then:  validation error
  expect_error(
    NodePolicy(skip_hint = "k > 100"),
    "skip_hint.*only valid when.*skip_when"
  )
})

test_that("NodePolicy: error when max_iterations is zero", {
  # Given: max_iterations = 0
  # When:  constructing a NodePolicy
  # Then:  validation error
  expect_error(
    NodePolicy(max_iterations = 0L),
    "max_iterations.*positive"
  )
})

test_that("GlobalPolicy: valid with max_iterations", {
  # Given: a positive integer
  # When:  constructing a GlobalPolicy
  # Then:  field stored correctly
  gp <- GlobalPolicy(max_iterations = 3L)
  expect_equal(gp@max_iterations, 3L)
})

test_that("GlobalPolicy: error when max_iterations negative", {
  # Given: negative max_iterations
  # When:  constructing a GlobalPolicy
  # Then:  validation error
  expect_error(
    GlobalPolicy(max_iterations = -1L),
    "max_iterations.*positive"
  )
})

test_that("Node: valid decision node with single parameter", {
  # Given: type = decision, topic, single parameter, one transition
  # When:  constructing a Node
  # Then:  all fields stored correctly
  n <- Node(
    type = "decision",
    topic = "effect_measures",
    parameter = "sm",
    transitions = list(Transition(to = "next_node", always = TRUE))
  )
  expect_equal(n@type, "decision")
  expect_equal(n@topic, "effect_measures")
  expect_equal(n@parameter, "sm")
  expect_length(n@transitions, 1L)
})

test_that("Node: valid node with multiple parameters", {
  # Given: parameter as character vector
  # When:  constructing a Node
  # Then:  all parameters stored
  n <- Node(
    type = "decision",
    parameter = c("incr", "method.incr", "allstudies"),
    transitions = list(Transition(to = "next", always = TRUE))
  )
  expect_equal(n@parameter, c("incr", "method.incr", "allstudies"))
})

test_that("Node: valid terminal node with empty transitions", {
  # Given: a context_gathering node with no transitions
  # When:  constructing a Node
  # Then:  valid (terminal node)
  n <- Node(type = "context_gathering", transitions = list())
  expect_length(n@transitions, 0L)
})

test_that("Node: valid node with default optional fields", {
  # Given: only required fields
  # When:  constructing a Node
  # Then:  optional fields have empty defaults
  n <- Node(type = "execution", transitions = list())
  expect_equal(n@topic, character(0))
  expect_equal(n@parameter, character(0))
  expect_equal(n@description, character(0))
  expect_s3_class(n@policy, "bridle::NodePolicy")
})

test_that("Node: error with invalid type", {
  # Given: type = "unknown"
  # When:  constructing a Node
  # Then:  validation error listing valid types
  expect_error(
    Node(type = "unknown", transitions = list()),
    "must be one of"
  )
})

test_that("Node: error when type has multiple values", {
  # Given: type with length > 1
  # When:  constructing a Node
  # Then:  validation error
  expect_error(
    Node(type = c("decision", "execution"), transitions = list()),
    "single string"
  )
})

test_that("Node: error when transitions contains non-Transition", {
  # Given: a list with a plain list instead of Transition
  # When:  constructing a Node
  # Then:  validation error
  expect_error(
    Node(type = "decision", transitions = list(list(to = "x"))),
    "must be a Transition"
  )
})

test_that("DecisionGraph: valid minimal graph", {
  # Given: entry node and one node with empty transitions
  # When:  constructing a DecisionGraph
  # Then:  valid graph
  dg <- DecisionGraph(
    entry_node = "start",
    nodes = list(start = Node(type = "context_gathering", transitions = list()))
  )
  expect_equal(dg@entry_node, "start")
  expect_length(dg@nodes, 1L)
  expect_true(is.na(dg@global_policy@max_iterations))
  expect_equal(dg@template, character(0))
})

test_that("DecisionGraph: valid graph with global_policy", {
  # Given: a graph with global_policy
  # When:  constructing a DecisionGraph
  # Then:  global_policy is stored
  gp <- GlobalPolicy(max_iterations = 5L)
  dg <- DecisionGraph(
    entry_node = "a",
    global_policy = gp,
    nodes = list(a = Node(type = "execution", transitions = list()))
  )
  expect_equal(dg@global_policy@max_iterations, 5L)
})

test_that("DecisionGraph: error when entry_node not in nodes", {
  # Given: entry_node references a non-existent node
  # When:  constructing a DecisionGraph
  # Then:  validation error with helpful message
  expect_error(
    DecisionGraph(
      entry_node = "missing",
      nodes = list(a = Node(type = "execution", transitions = list()))
    ),
    "entry_node.*missing.*not found"
  )
})

test_that("DecisionGraph: error when entry_node is empty string", {
  # Given: entry_node = ""
  # When:  constructing a DecisionGraph
  # Then:  validation error
  expect_error(
    DecisionGraph(
      entry_node = "",
      nodes = list(a = Node(type = "execution", transitions = list()))
    ),
    "non-empty"
  )
})

test_that("DecisionGraph: error when nodes is empty", {
  # Given: no nodes in the map
  # When:  constructing a DecisionGraph
  # Then:  validation error
  expect_error(
    DecisionGraph(entry_node = "a", nodes = list()),
    "non-empty named list"
  )
})

test_that("DecisionGraph: error with dangling transition target", {
  # Given: a transition to a node that doesn't exist
  # When:  constructing a DecisionGraph
  # Then:  validation error identifying the missing target
  expect_error(
    DecisionGraph(
      entry_node = "a",
      nodes = list(
        a = Node(
          type = "decision",
          transitions = list(Transition(to = "nonexistent", always = TRUE))
        )
      )
    ),
    'targets.*"nonexistent".*does not exist'
  )
})

test_that("read_decision_graph: valid YAML round-trip", {
  # Given: the metabin example fixture
  # When:  reading the YAML file
  # Then:  DecisionGraph has correct structure
  path <- test_path("fixtures", "decision_graph_valid.yaml")
  dg <- read_decision_graph(path)

  expect_s3_class(dg, "bridle::DecisionGraph")
  expect_equal(dg@entry_node, "outcome_type")
  expect_equal(length(dg@nodes), 10L)
  expect_equal(dg@global_policy@max_iterations, 3L)

  # Check node types
  expect_equal(dg@nodes[["outcome_type"]]@type, "context_gathering")
  expect_equal(dg@nodes[["sm_selection"]]@type, "decision")
  expect_equal(dg@nodes[["execute_analysis"]]@type, "execution")
  expect_equal(dg@nodes[["heterogeneity_assessment"]]@type, "diagnosis")

  # Check multi-parameter node
  expect_equal(
    dg@nodes[["continuity_correction"]]@parameter,
    c("incr", "method.incr", "allstudies")
  )

  # Check node with policy
  tau2 <- dg@nodes[["tau2_estimation"]]
  expect_equal(tau2@policy@skip_when, "number of studies is very large")
  expect_equal(tau2@policy@skip_hint, "k > 100")
  expect_equal(tau2@policy@max_iterations, 1L)

  # Check conditional transition with computable_hint
  method_trans <- dg@nodes[["method_selection"]]@transitions
  expect_equal(method_trans[[1]]@when, "zero cells exist in the data")
  expect_equal(method_trans[[1]]@computable_hint, "any(event.e == 0)")
  expect_true(method_trans[[2]]@otherwise)

  # Check terminal node
  expect_length(dg@nodes[["complete"]]@transitions, 0L)
})

test_that("read_decision_graph: error on nonexistent file", {
  # Given: a path that does not exist
  # When:  reading the file
  # Then:  informative error
  expect_error(
    read_decision_graph("nonexistent_file.yaml"),
    "File not found"
  )
})

test_that("read_decision_graph: error on malformed YAML", {
  # Given: a file with invalid YAML content
  # When:  reading the file
  # Then:  YAML parse error
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("graph:\n  entry_node: [invalid\n  unclosed", tmp)
  expect_error(
    read_decision_graph(tmp),
    "Failed to parse YAML"
  )
})

test_that("read_decision_graph: error when graph key is missing", {
  # Given: valid YAML without top-level 'graph' key
  # When:  reading the file
  # Then:  error about missing graph key
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("entry_node: foo\nnodes: {}", tmp)
  expect_error(
    read_decision_graph(tmp),
    "graph"
  )
})

test_that("read_decision_graph: error when entry_node is missing", {
  # Given: YAML with graph key but no entry_node
  # When:  reading the file
  # Then:  error about missing entry_node
  tmp <- withr::local_tempfile(fileext = ".yaml")
  yaml::write_yaml(list(graph = list(nodes = list(a = list(
    type = "execution", transitions = list()
  )))), tmp)
  expect_error(
    read_decision_graph(tmp),
    "entry_node.*required"
  )
})
