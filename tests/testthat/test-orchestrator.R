# Tests for turn_prepare(), turn_resolve(), aggregate_knowledge()

.orch_make_plugin_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  graph_yaml <- "
graph:
  entry_node: start
  nodes:
    start:
      type: decision
      topic: effect_measure
      parameter: sm
      transitions:
        - to: end
          always: true
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))

  ctx_yaml <- "
variables:
  - name: k
    description: number of studies
    available_from: data_loaded
    source_expression: nrow(data)
"
  writeLines(ctx_yaml, file.path(dir, "context_schema.yaml"))
  dir
}

# Entry decision with natural-language `when` (no computable_hint) -> needs_llm;
# engine stays on `dec` after advance().
.orch_stall_plugin <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  graph_yaml <- "
graph:
  entry_node: dec
  nodes:
    dec:
      type: decision
      topic: effect_measure
      parameter: sm
      transitions:
        - to: end
          when: LLM must choose the transition
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))
  know <- "
topic: effect_measure
target_parameter: sm
package: meta
function: rma
entries:
  - id: e1
    when: default
    properties:
      - Use an appropriate effect measure.
"
  writeLines(know, file.path(dir, "knowledge.yaml"))
  ctx_yaml <- "
variables:
  - name: k
    description: number of studies
    available_from: data_loaded
    source_expression: nrow(data)
"
  writeLines(ctx_yaml, file.path(dir, "context_schema.yaml"))
  dir
}

.orch_make_terminal_plugin <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  graph_yaml <- "
graph:
  entry_node: done
  nodes:
    done:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))
  dir
}

.orch_make_skip_plugin <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  graph_yaml <- "
graph:
  entry_node: start
  nodes:
    start:
      type: decision
      topic: effect_measure
      parameter: sm
      policy:
        skip_when: always skip
        skip_hint: \"TRUE\"
      transitions:
        - to: end
          always: true
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))
  know <- "
topic: effect_measure
target_parameter: sm
package: meta
function: rma
entries:
  - id: e1
    when: default
    properties:
      - Use an appropriate effect measure.
"
  writeLines(know, file.path(dir, "knowledge.yaml"))
  ctx_yaml <- "
variables:
  - name: k
    description: studies
    available_from: data_loaded
    source_expression: nrow(data)
"
  writeLines(ctx_yaml, file.path(dir, "context_schema.yaml"))
  dir
}

.orch_write_knowledge <- function(topic, id = "e1") {
  sprintf(
    "topic: %s
target_parameter: sm
package: meta
function: rma
entries:
  - id: %s
    when: default
    properties:
      - Notes for %s.
",
    topic, id, topic
  )
}

test_that("turn_prepare returns completed for terminal entry graph", {
  # Given: a plugin whose entry node is terminal
  dir <- .orch_make_terminal_plugin()
  agent <- bridle_agent(dir)
  # When: turn_prepare is executed
  p <- turn_prepare(agent)
  # Then: the turn is marked as completed
  expect_identical(p$status, "completed")
})

test_that("turn_prepare returns skipped when skip_hint is TRUE", {
  # Given: a plugin with skip_when/skip_hint policy
  dir <- .orch_make_skip_plugin()
  agent <- bridle_agent(dir)
  # When: turn_prepare is executed
  p <- turn_prepare(agent)
  # Then: the node is skipped at prepare time
  expect_identical(p$status, "skipped")
  expect_equal(p$node_id, "start")
})

test_that("turn_prepare continues with assembled prompt on decision node", {
  # Given: a plugin that reaches a decision node requiring LLM input
  dir <- .orch_stall_plugin()
  agent <- bridle_agent(dir)
  # When: turn_prepare is executed
  p <- turn_prepare(agent)
  # Then: execution continues with a non-empty prompt
  expect_identical(p$status, "continue")
  expect_equal(p$node_id, "dec")
  expect_true(nzchar(p$prompt_text))
  expect_equal(p$node_type, "decision")
})

test_that("turn_resolve applies accept and updates context", {
  # Given: a prepared decision turn with a suggested parameter value
  dir <- .orch_stall_plugin()
  agent <- bridle_agent(dir)
  prep <- turn_prepare(agent)
  parsed <- parse_response(
    paste0(
      "{\"recommendation_text\":\"Use RR.\",",
      "\"suggested_value\":\"RR\",",
      "\"transition_signal\":\"end\"}"
    ),
    prep$node,
    prep$transition_candidates
  )
  # When: turn_resolve is called with accept action
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "accept")
    )
  )
  # Then: the suggested value is written to context
  expect_equal(agent$engine@context@parameters_decided$sm, "RR")
})

test_that("turn_resolve applies reject override", {
  # Given: a prepared decision turn with a reject override value
  dir <- .orch_stall_plugin()
  agent <- bridle_agent(dir)
  prep <- turn_prepare(agent)
  parsed <- parse_response(
    paste0(
      "{\"recommendation_text\":\"Use RR.\",",
      "\"transition_signal\":\"end\"}"
    ),
    prep$node,
    prep$transition_candidates
  )
  # When: turn_resolve is called with reject + override
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "reject", override = "OR")
    )
  )
  # Then: the override value is written to context
  expect_equal(agent$engine@context@parameters_decided$sm, "OR")
})

test_that("turn_resolve uses transition_choice override when provided", {
  # Given: a decision node with multiple valid transition targets
  dir <- withr::local_tempdir()
  graph_yaml <- "
graph:
  entry_node: dec
  nodes:
    dec:
      type: decision
      topic: effect_measure
      parameter: sm
      transitions:
        - to: end
          when: choose terminal
        - to: alt
          when: choose alternate
    alt:
      type: execution
      transitions: []
    end:
      type: execution
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))
  writeLines(
    .orch_write_knowledge("effect_measure", "e1"),
    file.path(dir, "knowledge.yaml")
  )
  writeLines(
    "variables:
  - name: k
    description: studies
    available_from: data_loaded
    source_expression: nrow(data)
",
    file.path(dir, "context_schema.yaml")
  )
  agent <- bridle_agent(dir)
  prep <- turn_prepare(agent)
  parsed <- parse_response(
    paste0(
      "{\"recommendation_text\":\"Use RR.\",",
      "\"suggested_value\":\"RR\",",
      "\"transition_signal\":\"alt\"}"
    ),
    prep$node,
    prep$transition_candidates
  )
  # When: transition_choice is explicitly overridden to end
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "accept")
    ),
    transition_choice = "end"
  )
  # Then: the engine transitions using the override
  expect_equal(agent$engine@.state$current_node, "end")
})

test_that("aggregate_knowledge includes graph for empty knowledge list", {
  # Given: an agent with graph metadata and no loaded knowledge entries
  dir <- .orch_make_terminal_plugin()
  agent <- bridle_agent(dir)
  # When: aggregate_knowledge is executed
  txt <- aggregate_knowledge(agent)
  # Then: graph information is present and knowledge block is absent
  expect_match(txt, "Decision graph", fixed = TRUE)
  expect_match(txt, "Entry: done", fixed = TRUE)
  expect_false(grepl("# Knowledge", txt))
})

test_that("aggregate_knowledge includes multiple knowledge topics", {
  # Given: an agent with two topic knowledge stores
  dir <- withr::local_tempdir()
  graph_yaml <- "
graph:
  entry_node: a
  nodes:
    a:
      type: decision
      topic: topic_a
      parameter: sm
      transitions:
        - to: b
          always: true
    b:
      type: decision
      topic: topic_b
      parameter: sm
      transitions: []
"
  writeLines(graph_yaml, file.path(dir, "decision_graph.yaml"))
  kdir <- file.path(dir, "knowledge")
  dir.create(kdir)
  writeLines(.orch_write_knowledge("topic_a", "ea"), file.path(kdir, "a.yaml"))
  writeLines(.orch_write_knowledge("topic_b", "eb"), file.path(kdir, "b.yaml"))
  writeLines(
    "variables:
  - name: k
    description: \"study count\"
    available_from: data_loaded
    source_expression: nrow(data)
",
    file.path(dir, "context_schema.yaml")
  )
  agent <- bridle_agent(dir)
  # When: aggregate_knowledge is executed
  txt <- aggregate_knowledge(agent)
  # Then: both topic sections are present in the aggregate text
  expect_match(txt, "topic_a", fixed = TRUE)
  expect_match(txt, "topic_b", fixed = TRUE)
})

test_that("aggregate_knowledge includes constraints when present", {
  # Given: an agent with technical constraints defined
  dir <- .orch_make_plugin_dir()
  cons <- "
package: meta
function: rma
constraints:
  - id: c1
    source: expert
    type: valid_values
    param: sm
    values: [RR, OR]
    message: Pick RR or OR.
"
  writeLines(cons, file.path(dir, "constraints.yaml"))
  agent <- bridle_agent(dir)
  # When: aggregate_knowledge is executed
  txt <- aggregate_knowledge(agent)
  # Then: the constraints section and constraint ID are included
  expect_match(txt, "Technical constraints", fixed = TRUE)
  expect_match(txt, "c1", fixed = TRUE)
})

test_that("turn_resolve rejects parameter_value without prepare", {
  # Given: a valid agent and malformed parameter_value payload
  agent <- bridle_agent(.orch_stall_plugin())
  # When/Then: turn_resolve aborts with class + message checks
  expect_error(
    turn_resolve(agent, list(parsed = list(), user_action = list(action = "accept"))),
    "must be a list containing",
    class = "rlang_error"
  )
})

test_that("turn_resolve rejects parameter_value missing parsed/user_action", {
  # Given: a valid prepare object but missing parsed/user_action fields
  agent <- bridle_agent(.orch_stall_plugin())
  prep <- turn_prepare(agent)
  # When/Then: turn_resolve aborts with class + message checks
  expect_error(
    turn_resolve(agent, list(prepare = prep)),
    "must contain",
    class = "rlang_error"
  )
})

test_that("turn_resolve keeps current node for invalid transition_choice", {
  # Given: a decision node with LLM transition candidates
  dir <- .orch_stall_plugin()
  agent <- bridle_agent(dir)
  prep <- turn_prepare(agent)
  parsed <- parse_response(
    paste0(
      "{\"recommendation_text\":\"Use RR.\",",
      "\"suggested_value\":\"RR\",",
      "\"transition_signal\":\"end\"}"
    ),
    prep$node,
    prep$transition_candidates
  )
  before_node <- agent$engine@.state$current_node
  # When: transition_choice points to an invalid/non-candidate node
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "accept")
    ),
    transition_choice = "invalid_node"
  )
  # Then: no transition is applied and current node is unchanged
  expect_equal(agent$engine@.state$current_node, before_node)
})

test_that("turn_prepare and turn_resolve reject non-agent", {
  expect_error(
    turn_prepare(list()),
    "bridle_agent",
    class = "rlang_error"
  )
  expect_error(
    turn_resolve(list(), list(prepare = list())),
    "bridle_agent",
    class = "rlang_error"
  )
})
