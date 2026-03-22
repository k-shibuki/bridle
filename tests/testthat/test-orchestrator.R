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
  dir <- .orch_make_terminal_plugin()
  agent <- bridle_agent(dir)
  p <- turn_prepare(agent)
  expect_identical(p$status, "completed")
})

test_that("turn_prepare returns skipped when skip_hint is TRUE", {
  dir <- .orch_make_skip_plugin()
  agent <- bridle_agent(dir)
  p <- turn_prepare(agent)
  expect_identical(p$status, "skipped")
  expect_equal(p$node_id, "start")
})

test_that("turn_prepare continues with assembled prompt on decision node", {
  dir <- .orch_stall_plugin()
  agent <- bridle_agent(dir)
  p <- turn_prepare(agent)
  expect_identical(p$status, "continue")
  expect_equal(p$node_id, "dec")
  expect_true(nzchar(p$prompt_text))
  expect_equal(p$node_type, "decision")
})

test_that("turn_resolve applies accept and updates context", {
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
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "accept")
    )
  )
  expect_equal(agent$engine@context@parameters_decided$sm, "RR")
})

test_that("turn_resolve applies reject override", {
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
  turn_resolve(
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = list(action = "reject", override = "OR")
    )
  )
  expect_equal(agent$engine@context@parameters_decided$sm, "OR")
})

test_that("aggregate_knowledge includes graph for empty knowledge list", {
  dir <- .orch_make_terminal_plugin()
  agent <- bridle_agent(dir)
  txt <- aggregate_knowledge(agent)
  expect_match(txt, "Decision graph", fixed = TRUE)
  expect_match(txt, "Entry: done", fixed = TRUE)
  expect_false(grepl("# Knowledge", txt))
})

test_that("aggregate_knowledge includes multiple knowledge topics", {
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
  txt <- aggregate_knowledge(agent)
  expect_match(txt, "topic_a", fixed = TRUE)
  expect_match(txt, "topic_b", fixed = TRUE)
})

test_that("aggregate_knowledge includes constraints when present", {
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
  txt <- aggregate_knowledge(agent)
  expect_match(txt, "Technical constraints", fixed = TRUE)
  expect_match(txt, "c1", fixed = TRUE)
})

test_that("turn_prepare and turn_resolve reject non-agent", {
  expect_error(turn_prepare(list()), "bridle_agent")
  expect_error(
    turn_resolve(list(), list(prepare = list())),
    "bridle_agent"
  )
})
