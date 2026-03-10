# E2E pipeline bridge: scan_package → draft_knowledge → bridle_agent → bridle_console
# Issue #167: Validates that draft_knowledge output is directly consumable
# by bridle_agent without manual intervention.
#
# Design note — discovered gaps:
# 1. draft_knowledge() writes a single knowledge file (knowledge/<pkg>.yaml).
#    Realistic plugins need multiple knowledge files (one per topic). All
#    decision/diagnosis nodes share a single topic in this test to stay
#    consistent with what draft_knowledge actually produces.
# 2. No context_schema.yaml or manifest.yaml generation from draft pipeline.
#    Variable scope validation (ADR-0007) is skipped. Acceptable per Issue spec.
# 3. The draft graph is flat (no template composition). build_graph() handles
#    this correctly (ADR-0009 § flat graph path).

skip_if_not_installed("metafor")

# -- Helpers -------------------------------------------------------------------

init_anonymous_pipeline <- function() {
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = NA,
    BRIDLE_S2_API_KEY = NA,
    .local_envir = parent.frame()
  )
  suppressWarnings(bridle:::detect_profiles())
}

mock_full_draft_response <- function() {
  paste(
    # Section 1: decision_graph (8-node flat graph, no template)
    "graph:",
    "  entry_node: gather_data",
    "  global_policy:",
    "    max_iterations: 3",
    "  nodes:",
    "    gather_data:",
    "      type: context_gathering",
    "      description: Inspect data structure and determine analysis type",
    "      transitions:",
    "        - to: measure_selection",
    "          always: true",
    "    measure_selection:",
    "      type: decision",
    "      topic: estimation_method",
    "      parameter: measure",
    "      description: Select effect size measure",
    "      transitions:",
    "        - to: analysis_approach",
    "          always: true",
    "    analysis_approach:",
    "      type: decision",
    "      topic: estimation_method",
    "      parameter: method",
    "      description: Choose estimation method and approach",
    "      transitions:",
    "        - to: configure_tau2",
    "          always: true",
    "    configure_tau2:",
    "      type: decision",
    "      topic: estimation_method",
    "      parameter: tau2_estimator",
    "      description: Select tau-squared estimator",
    "      transitions:",
    "        - to: run_analysis",
    "          always: true",
    "    run_analysis:",
    "      type: execution",
    "      description: Execute meta-analysis with selected parameters",
    "      transitions:",
    "        - to: check_heterogeneity",
    "          always: true",
    "    check_heterogeneity:",
    "      type: diagnosis",
    "      topic: estimation_method",
    "      description: Assess heterogeneity and consider adjustments",
    "      transitions:",
    "        - to: measure_selection",
    "          when: adjustment needed",
    "        - to: assess_bias",
    "          always: true",
    "    assess_bias:",
    "      type: diagnosis",
    "      description: Assess publication bias",
    "      transitions:",
    "        - to: complete",
    "          always: true",
    "    complete:",
    "      type: context_gathering",
    "      description: Summarize analysis results",
    "      transitions: []",
    "---",
    # Section 2: knowledge (single topic covering all decision nodes)
    "topic: estimation_method",
    "target_parameter: method",
    "package: metafor",
    "function: rma.uni",
    "entries:",
    "  - id: reml_default",
    "    when: random-effects model is appropriate",
    "    properties:",
    "      - REML is the recommended estimator for tau-squared",
    "  - id: smd_continuous",
    "    when: continuous outcome data is available",
    "    properties:",
    "      - SMD is the standard effect measure for continuous outcomes",
    "  - id: i2_threshold",
    "    when: heterogeneity assessment is needed",
    "    properties:",
    "      - I-squared above 75 percent indicates substantial heterogeneity",
    "---",
    # Section 3: constraints (all 3 parameters covered)
    "package: metafor",
    "function: rma.uni",
    "constraints:",
    "  - id: valid_method_values",
    "    source: formals_default",
    "    type: valid_values",
    "    param: method",
    "    values:",
    "      - REML",
    "      - ML",
    "      - DL",
    "    confidence: high",
    "  - id: valid_measure_values",
    "    source: formals_default",
    "    type: valid_values",
    "    param: measure",
    "    values:",
    "      - SMD",
    "      - OR",
    "      - RR",
    "    confidence: high",
    "  - id: valid_tau2_values",
    "    source: formals_default",
    "    type: valid_values",
    "    param: tau2_estimator",
    "    values:",
    "      - REML",
    "      - ML",
    "      - DL",
    "    confidence: high",
    sep = "\n"
  )
}

.e2e_mock_chat <- function(responses) {
  idx <- 0L
  list(
    chat = function(prompt) {
      idx <<- idx + 1L
      if (idx > length(responses)) {
        responses[[length(responses)]]
      } else {
        responses[[idx]]
      }
    }
  )
}

.e2e_mock_readline <- function(inputs) {
  idx <- 0L
  function(prompt) {
    idx <<- idx + 1L
    if (idx > length(inputs)) {
      inputs[[length(inputs)]]
    } else {
      inputs[[idx]]
    }
  }
}

draft_to_dir <- function(tmp) {
  pkg <- scan_package("metafor")
  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      mock_full_draft_response()
    }
  )
  draft_knowledge(pkg, output_dir = tmp)
  tmp
}

# -- T-E2E-01: Draft output loadable by agent ----------------------------------

test_that("T-E2E-01: draft_knowledge output is directly loadable by bridle_agent", {
  # Given: scan_package(metafor) + mocked draft_knowledge producing 8-node graph
  # When:  bridle_agent(draft_output_dir) is called
  # Then:  returns valid bridle_agent with graph, knowledge, constraints, engine

  tmp <- withr::local_tempdir()
  draft_to_dir(tmp)

  agent <- bridle_agent(tmp)

  expect_s3_class(agent, "bridle_agent")
  expect_true(!is.null(agent$graph))
  expect_true(!is.null(agent$engine))
  expect_true(!is.null(agent$sandbox))
  expect_true(is.function(agent$console))

  expect_equal(length(names(agent$graph@nodes)), 8L)
  expect_equal(agent$graph@entry_node, "gather_data")
  expected_nodes <- c(
    "gather_data", "measure_selection", "analysis_approach",
    "configure_tau2", "run_analysis", "check_heterogeneity",
    "assess_bias", "complete"
  )
  for (n in expected_nodes) {
    expect_true(n %in% names(agent$graph@nodes), info = paste("Missing:", n))
  }

  expect_true(length(agent$knowledge) == 1L)
  expect_equal(agent$knowledge[[1L]]@topic, "estimation_method")

  expect_true(length(agent$constraints) == 1L)
  expect_true(length(agent$constraints[[1L]]@constraints) == 3L)
})

# -- T-E2E-02: Validation passes on draft output ------------------------------

test_that("T-E2E-02: validate_plugin passes on draft output with 0 errors 0 warnings", {
  # Given: draft output directory loaded by bridle_agent
  # When:  validate_plugin is called on the loaded artifacts
  # Then:  is_valid(result) is TRUE, 0 errors, 0 warnings

  tmp <- withr::local_tempdir()
  draft_to_dir(tmp)

  agent <- bridle_agent(tmp)

  result <- validate_plugin(
    agent$graph, agent$knowledge, agent$constraints
  )
  expect_true(is_valid(result))
  expect_equal(length(result@errors), 0L)
  expect_equal(length(result@warnings), 0L)
})

# -- T-E2E-03: Console completes full analysis ---------------------------------

test_that("T-E2E-03: bridle_console traverses all graph nodes to completion", {
  # Given: agent from draft output + mocked runtime LLM (7 responses) + readline
  # When:  bridle_console(agent) is called
  # Then:  completes without error

  tmp <- withr::local_tempdir()
  draft_to_dir(tmp)

  agent <- bridle_agent(tmp)

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .e2e_mock_chat(c(
        "Data looks like continuous outcome with yi and vi.",
        "I recommend SMD (Standardized Mean Difference).",
        "I recommend REML estimation method.",
        "I recommend REML for tau-squared estimation.",
        "```r\nresult <- list(I2 = 30, tau2 = 0.05, QE = 12)\n```",
        "Heterogeneity is low to moderate (I2 = 30%). No adjustment needed.",
        "No evidence of publication bias.",
        "Analysis complete with SMD using REML."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .e2e_mock_readline(rep("y", 20))
  )

  expect_no_error(bridle_console(agent))
})

# -- T-E2E-04: Audit log records all nodes ------------------------------------

test_that("T-E2E-04: audit log records visits to key nodes", {
  # Given: agent with log_dir + mocked LLM + mocked readline
  # When:  bridle_console runs to completion
  # Then:  JSONL log contains entries for key nodes with node_id and node_type

  tmp <- withr::local_tempdir()
  draft_to_dir(tmp)

  log_dir <- withr::local_tempdir()
  agent <- bridle_agent(tmp, log_dir = log_dir)

  local_mocked_bindings(
    bridle_runtime_chat = function(...) {
      .e2e_mock_chat(c(
        "Data overview for continuous outcomes.",
        "SMD recommended.",
        "REML recommended.",
        "REML for tau-squared.",
        "```r\nresult <- list(I2 = 25, tau2 = 0.04, QE = 10)\n```",
        "Heterogeneity acceptable.",
        "No bias detected.",
        "Done."
      ))
    }
  )
  local_mocked_bindings(
    bridle_readline = .e2e_mock_readline(rep("y", 20))
  )

  bridle_console(agent)

  log_files <- list.files(log_dir, pattern = "\\.jsonl$")
  expect_true(length(log_files) > 0L)

  log_lines <- readLines(file.path(log_dir, log_files[[1L]]))
  expect_true(length(log_lines) >= 5L)

  entries <- lapply(log_lines, function(ln) {
    jsonlite::fromJSON(ln, simplifyVector = FALSE)
  })
  node_ids <- vapply(entries, function(e) e$node_id, character(1))
  expect_true("measure_selection" %in% node_ids)
  expect_true("run_analysis" %in% node_ids)
  expect_true("complete" %in% node_ids)

  for (entry in entries) {
    expect_true("node_id" %in% names(entry))
    expect_true("node_type" %in% names(entry))
  }
})

# -- T-E2E-05: Malformed draft rejected ---------------------------------------

test_that("T-E2E-05: malformed draft without graph key is rejected", {
  # Given: mock LLM returns YAML without graph: key
  # When:  draft output is written and bridle_agent loads it
  # Then:  bridle_agent aborts with error about missing graph key

  pkg <- scan_package("metafor")
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      paste(
        "entry_node: start",
        "nodes:",
        "  start:",
        "    type: decision",
        "    transitions: []",
        "---",
        "topic: t1",
        "target_parameter: p1",
        "package: metafor",
        "function: rma.uni",
        "entries:",
        "  - id: e1",
        "    when: always",
        "    properties:",
        "      - some property",
        "---",
        "package: metafor",
        "function: rma.uni",
        "constraints:",
        "  - id: c1",
        "    source: formals_default",
        "    type: valid_values",
        "    param: p1",
        "    values:",
        "      - a",
        sep = "\n"
      )
    }
  )

  draft_knowledge(pkg, output_dir = tmp)
  expect_error(
    bridle_agent(tmp),
    "must contain a top-level.*graph.*key"
  )
})

# -- T-E2E-06: Topic mismatch detected ----------------------------------------

test_that("T-E2E-06: topic mismatch between knowledge and graph is detected", {
  # Given: mock LLM returns knowledge with topic that doesn't match any graph node
  # When:  validate_plugin is called on the loaded artifacts
  # Then:  validation reports error about orphan topic

  pkg <- scan_package("metafor")
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      paste(
        "graph:",
        "  entry_node: start",
        "  nodes:",
        "    start:",
        "      type: decision",
        "      topic: real_topic",
        "      parameter: method",
        "      transitions:",
        "        - to: finish",
        "          always: true",
        "    finish:",
        "      type: execution",
        "      transitions: []",
        "---",
        "topic: nonexistent_topic",
        "target_parameter: method",
        "package: metafor",
        "function: rma.uni",
        "entries:",
        "  - id: e1",
        "    when: always",
        "    properties:",
        "      - some property",
        "---",
        "package: metafor",
        "function: rma.uni",
        "constraints:",
        "  - id: c1",
        "    source: formals_default",
        "    type: valid_values",
        "    param: method",
        "    values:",
        "      - REML",
        sep = "\n"
      )
    }
  )

  draft_knowledge(pkg, output_dir = tmp)

  graph <- read_decision_graph(file.path(tmp, "decision_graph.yaml"))
  ks <- read_knowledge(file.path(tmp, "knowledge", "metafor.yaml"))
  cs <- read_constraints(file.path(tmp, "constraints", "technical.yaml"))

  result <- validate_plugin(graph, list(ks), list(cs))
  expect_true(length(result@errors) > 0L)
  expect_true(any(grepl("nonexistent_topic", result@errors)))
})

# -- T-E2E-07: Empty knowledge section ----------------------------------------

test_that("T-E2E-07: empty knowledge section causes reader error", {
  # Given: mock LLM returns empty second section
  # When:  read_knowledge is called on the written file
  # Then:  reader aborts because required fields are missing
  #
  # Discovery: draft_knowledge writes yaml::write_yaml(list()) which produces
  # an empty YAML document. read_knowledge then fails on missing `topic` field.

  pkg <- scan_package("metafor")
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      paste(
        "graph:",
        "  entry_node: start",
        "  nodes:",
        "    start:",
        "      type: decision",
        "      parameter: method",
        "      transitions:",
        "        - to: finish",
        "          always: true",
        "    finish:",
        "      type: execution",
        "      transitions: []",
        "---",
        "",
        "---",
        "package: metafor",
        "function: rma.uni",
        "constraints:",
        "  - id: c1",
        "    source: formals_default",
        "    type: valid_values",
        "    param: method",
        "    values:",
        "      - REML",
        sep = "\n"
      )
    }
  )

  draft_knowledge(pkg, output_dir = tmp)

  knowledge_path <- file.path(tmp, "knowledge", "metafor.yaml")
  expect_true(file.exists(knowledge_path))
  expect_error(read_knowledge(knowledge_path), "topic")
})
