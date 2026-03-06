# Tests for validate_plugin()
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases

# -- Helpers: minimal valid plugin objects ------------------------------------

# nolint start: object_usage_linter. S7 constructors from same package.
make_graph <- function(nodes = NULL, entry = "start") {
  if (is.null(nodes)) {
    nodes <- list(
      start = Node(
        type = "decision",
        topic = "effect_measure",
        parameter = "sm",
        transitions = list(
          Transition(to = "end", always = TRUE)
        )
      ),
      end = Node(
        type = "execution",
        transitions = list()
      )
    )
  }
  DecisionGraph(entry_node = entry, nodes = nodes)
}

make_knowledge <- function(topic = "effect_measure",
                           param = "sm",
                           pkg = "meta",
                           func = "metabin") {
  KnowledgeStore(
    topic = topic,
    target_parameter = param,
    package = pkg,
    func = func,
    entries = list(KnowledgeEntry(
      id = "e1",
      when = "always",
      properties = "Use RR for binary outcomes"
    ))
  )
}

make_constraint <- function(param = "sm", pkg = "meta", func = "metabin") {
  ConstraintSet(
    package = pkg,
    func = func,
    constraints = list(Constraint(
      id = "c1",
      source = "formals_default",
      type = "valid_values",
      param = param,
      values = c("RR", "OR", "RD")
    ))
  )
}

make_context <- function(vars = NULL) {
  if (is.null(vars)) {
    vars <- list(ContextVariable(
      name = "k",
      description = "number of studies",
      available_from = "data_loaded",
      source_expression = "nrow(data)"
    ))
  }
  ContextSchema(variables = vars)
}
# nolint end

# -- ValidationResult --------------------------------------------------------

test_that("ValidationResult: empty result is valid", {
  # Given: no errors or warnings
  # When:  constructing and checking
  # Then:  is_valid returns TRUE
  vr <- ValidationResult()
  expect_true(is_valid(vr))
})

test_that("ValidationResult: errors make it invalid", {
  # Given: an error present
  # When:  checking validity
  # Then:  is_valid returns FALSE
  vr <- ValidationResult(errors = "something broke")
  expect_false(is_valid(vr))
})

test_that("ValidationResult: warnings make it invalid", {
  # Given: a warning present
  # When:  checking validity
  # Then:  is_valid returns FALSE
  vr <- ValidationResult(warnings = "minor issue")
  expect_false(is_valid(vr))
})

test_that("is_valid: rejects non-ValidationResult", {
  # Given: a non-ValidationResult object
  # When:  calling is_valid
  # Then:  error
  expect_error(is_valid("not a result"), "ValidationResult")
})

# -- validate_plugin(): valid plugin -----------------------------------------

test_that("validate_plugin: valid complete plugin passes", {
  # Given: a consistent plugin (graph + knowledge + constraints match)
  # When:  validating
  # Then:  no errors or warnings
  graph <- make_graph()
  ks <- make_knowledge()
  cs <- make_constraint()

  result <- validate_plugin(graph, list(ks), list(cs))
  expect_equal(length(result@errors), 0L)
  expect_equal(length(result@warnings), 0L)
})

test_that("validate_plugin: graph-only validation passes", {
  # Given: just a graph with no knowledge or constraints
  # When:  validating
  # Then:  no errors (warnings possible for missing knowledge)
  graph <- make_graph()
  result <- validate_plugin(graph)
  expect_equal(length(result@errors), 0L)
})

# -- validate_plugin(): input validation -------------------------------------

test_that("validate_plugin: rejects non-DecisionGraph", {
  # Given: a non-DecisionGraph object
  # When:  calling validate_plugin
  # Then:  error
  expect_error(
    validate_plugin("not a graph"),
    "DecisionGraph"
  )
})

# -- Check 1: Reachability ---------------------------------------------------

test_that("validate_plugin: detects unreachable nodes", {
  # Given: a graph where node "orphan" has no incoming transitions
  # When:  validating
  # Then:  error about unreachable node
  nodes <- list(
    start = Node(
      type = "decision",
      parameter = "sm",
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list()),
    orphan = Node(type = "decision", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "start", nodes = nodes)

  result <- validate_plugin(graph)
  expect_true(any(grepl("Unreachable node.*orphan", result@errors)))
})

test_that("validate_plugin: all reachable nodes pass", {
  # Given: a fully connected graph
  # When:  validating reachability
  # Then:  no unreachable errors
  nodes <- list(
    a = Node(
      type = "decision",
      transitions = list(Transition(to = "b", always = TRUE))
    ),
    b = Node(
      type = "decision",
      transitions = list(Transition(to = "c", always = TRUE))
    ),
    c = Node(type = "execution", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "a", nodes = nodes)
  result <- validate_plugin(graph)
  reachability_errors <- grep("Unreachable", result@errors, value = TRUE)
  expect_length(reachability_errors, 0L)
})

# -- Check 2: Coverage -------------------------------------------------------

test_that("validate_plugin: warns on uncovered parameter", {
  # Given: knowledge references param "method" not in any graph node
  # When:  validating
  # Then:  warning about uncovered parameter
  graph <- make_graph()
  ks <- make_knowledge(param = "method")

  result <- validate_plugin(graph, list(ks))
  expect_true(any(grepl("Coverage.*method", result@warnings)))
})

test_that("validate_plugin: covered parameters produce no warning", {
  # Given: knowledge param matches a graph node parameter
  # When:  validating
  # Then:  no coverage warnings
  graph <- make_graph()
  ks <- make_knowledge(param = "sm")

  result <- validate_plugin(graph, list(ks))
  coverage_warns <- grep("Coverage", result@warnings, value = TRUE)
  expect_length(coverage_warns, 0L)
})

test_that("validate_plugin: constraint param triggers coverage warning", {
  # Given: constraint references param "tau" not in graph
  # When:  validating
  # Then:  warning about uncovered parameter
  graph <- make_graph()
  cs <- make_constraint(param = "tau")

  result <- validate_plugin(graph, constraints = list(cs))
  expect_true(any(grepl("Coverage.*tau", result@warnings)))
})

# -- Check 3: Consistency (topics) -------------------------------------------

test_that("validate_plugin: errors on orphan knowledge topic", {
  # Given: knowledge topic "orphan_topic" not in any graph node
  # When:  validating
  # Then:  error about orphan topic
  graph <- make_graph()
  ks <- make_knowledge(topic = "orphan_topic", param = "sm")

  result <- validate_plugin(graph, list(ks))
  expect_true(any(grepl("Consistency.*orphan_topic", result@errors)))
})

test_that("validate_plugin: warns on graph topic missing knowledge", {
  # Given: graph has topic "effect_measure" but no knowledge provided
  # When:  validating
  # Then:  warning about missing knowledge
  graph <- make_graph()
  result <- validate_plugin(graph)
  expect_true(any(grepl("Consistency.*effect_measure.*no corresponding", result@warnings)))
})

test_that("validate_plugin: matching topics produce no consistency error", {
  # Given: knowledge topic matches graph node topic
  # When:  validating
  # Then:  no consistency errors
  graph <- make_graph()
  ks <- make_knowledge(topic = "effect_measure")
  result <- validate_plugin(graph, list(ks))
  consistency_errors <- grep("Consistency", result@errors, value = TRUE)
  expect_length(consistency_errors, 0L)
})

# -- Check 4: Constraint integrity -------------------------------------------

test_that("validate_plugin: errors on unknown param in constraint", {
  # Given: constraint references parameter not in graph
  # When:  validating
  # Then:  error about unknown parameter in constraint
  graph <- make_graph()
  cs <- ConstraintSet(
    package = "meta",
    func = "metabin",
    constraints = list(Constraint(
      id = "c1",
      source = "formals_default",
      type = "forces",
      param = "unknown_param",
      forces = list(also_unknown = "value")
    ))
  )

  result <- validate_plugin(graph, constraints = list(cs))
  expect_true(any(grepl("Constraint integrity.*unknown_param", result@errors)))
  expect_true(any(grepl("Constraint integrity.*also_unknown", result@errors)))
})

test_that("validate_plugin: constraint referencing known param passes", {
  # Given: constraint param matches graph node parameter
  # When:  validating
  # Then:  no constraint integrity errors
  graph <- make_graph()
  cs <- make_constraint(param = "sm")
  result <- validate_plugin(graph, constraints = list(cs))
  integrity_errors <- grep("Constraint integrity", result@errors, value = TRUE)
  expect_length(integrity_errors, 0L)
})

# -- Check 5: Variable scope -------------------------------------------------

test_that("validate_plugin: errors on early variable usage", {
  # Given: computable_hint uses variable "I2" available only after
  #        "execute" node, but hint is at "decide" node (before execute)
  # When:  validating
  # Then:  error about variable scope
  nodes <- list(
    decide = Node(
      type = "decision",
      parameter = "sm",
      transitions = list(
        Transition(
          to = "execute",
          when = "I2 is high",
          computable_hint = "I2 > 50"
        )
      )
    ),
    execute = Node(
      type = "execution",
      transitions = list()
    )
  )
  graph <- DecisionGraph(entry_node = "decide", nodes = nodes)

  ctx <- ContextSchema(variables = list(
    ContextVariable(
      name = "I2",
      description = "I-squared",
      available_from = "post_fit",
      depends_on_node = "execute",
      source_expression = "result$I2"
    )
  ))

  result <- validate_plugin(graph, context_schema = ctx)
  expect_true(any(grepl("Variable scope.*I2", result@errors)))
})

test_that("validate_plugin: available variable passes scope check", {
  # Given: variable "k" available from data_loaded (no depends_on_node)
  # When:  validating hint at any node
  # Then:  no scope errors
  nodes <- list(
    start = Node(
      type = "decision",
      transitions = list(
        Transition(
          to = "end",
          when = "few studies",
          computable_hint = "k < 5"
        )
      )
    ),
    end = Node(type = "execution", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "start", nodes = nodes)
  ctx <- make_context()

  result <- validate_plugin(graph, context_schema = ctx)
  scope_errors <- grep("Variable scope", result@errors, value = TRUE)
  expect_length(scope_errors, 0L)
})

test_that("validate_plugin: dynamic variable (not declared) no error", {
  # Given: computable_hint references variable not in context_schema
  # When:  validating
  # Then:  no error (assumed dynamic data column)
  nodes <- list(
    start = Node(
      type = "decision",
      transitions = list(
        Transition(
          to = "end",
          when = "outcome type",
          computable_hint = "event.e > 0"
        )
      )
    ),
    end = Node(type = "execution", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "start", nodes = nodes)
  ctx <- make_context()

  result <- validate_plugin(graph, context_schema = ctx)
  scope_errors <- grep("Variable scope", result@errors, value = TRUE)
  expect_length(scope_errors, 0L)
})

test_that("validate_plugin: skip_hint scope checked", {
  # Given: skip_hint references variable only available after later node
  # When:  validating
  # Then:  error about variable scope
  nodes <- list(
    start = Node(
      type = "decision",
      policy = NodePolicy(
        skip_when = "tau2 is zero",
        skip_hint = "tau2 == 0"
      ),
      transitions = list(Transition(to = "fit", always = TRUE))
    ),
    fit = Node(type = "execution", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "start", nodes = nodes)
  ctx <- ContextSchema(variables = list(
    ContextVariable(
      name = "tau2",
      description = "between-study variance",
      available_from = "post_fit",
      depends_on_node = "fit",
      source_expression = "result$tau2"
    )
  ))

  result <- validate_plugin(graph, context_schema = ctx)
  expect_true(any(grepl("Variable scope.*tau2", result@errors)))
})

# -- Multiple violations ------------------------------------------------------

test_that("validate_plugin: reports all violations at once", {
  # Given: a plugin with multiple issues
  # When:  validating
  # Then:  all errors/warnings collected (not just first)
  nodes <- list(
    start = Node(
      type = "decision",
      parameter = "sm",
      topic = "effect_measure",
      transitions = list(
        Transition(to = "end", always = TRUE)
      )
    ),
    end = Node(type = "execution", transitions = list()),
    orphan = Node(type = "diagnosis", transitions = list())
  )
  graph <- DecisionGraph(entry_node = "start", nodes = nodes)
  ks <- make_knowledge(topic = "nonexistent_topic", param = "unknown_p")
  cs <- ConstraintSet(
    package = "meta",
    func = "metabin",
    constraints = list(Constraint(
      id = "bad",
      source = "expert",
      type = "forces",
      param = "bad_param",
      forces = list(worse = "val")
    ))
  )

  result <- validate_plugin(graph, list(ks), list(cs))
  total_issues <- length(result@errors) + length(result@warnings)
  expect_true(total_issues >= 3L)
})

# -- Helper functions ---------------------------------------------------------

test_that("extract_hint_variables: parses valid expression", {
  # Given: a valid R expression string
  # When:  extracting variables
  # Then:  variable names returned
  vars <- bridle:::extract_hint_variables("I2 > 50 && k < 5")
  expect_true("I2" %in% vars)
  expect_true("k" %in% vars)
})

test_that("extract_hint_variables: returns empty for invalid expression", {
  # Given: an invalid expression
  # When:  extracting variables
  # Then:  empty character vector
  vars <- bridle:::extract_hint_variables("{{not valid R}}")
  expect_length(vars, 0L)
})

test_that("collect_graph_parameters: extracts all params", {
  # Given: a graph with params on multiple nodes
  # When:  collecting parameters
  # Then:  all unique params returned
  graph <- make_graph()
  params <- bridle:::collect_graph_parameters(graph)
  expect_true("sm" %in% params)
})
