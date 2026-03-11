# Tests for draft_knowledge() (ellmer-based AI drafting)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases
# All LLM calls mocked via local_mocked_bindings on bridle_chat

# -- Helpers -------------------------------------------------------------------

make_test_scan_result <- function() {
  ScanResult( # nolint: object_usage_linter. S7 class in R/scan_result.R
    package = "meta",
    func = "metabin",
    parameters = list(
      ParameterInfo( # nolint: object_usage_linter. S7 class in R/scan_result.R
        name = "method", has_default = TRUE,
        default_expression = '"MH"', classification = "statistical_decision"
      ),
      ParameterInfo( # nolint: object_usage_linter. S7 class in R/scan_result.R
        name = "sm", has_default = TRUE,
        default_expression = '"OR"', classification = "statistical_decision"
      ),
      ParameterInfo( # nolint: object_usage_linter. S7 class in R/scan_result.R
        name = "data", has_default = FALSE,
        classification = "data_input"
      )
    ),
    dependency_graph = list(sm = "method"),
    valid_values = list(method = c("MH", "Inverse", "Peto")),
    constraints = list(
      Constraint( # nolint: object_usage_linter. S7 class in R/constraints.R
        id = "c1", source = "formals_default", type = "forces",
        param = "sm", condition = "method == 'Peto'",
        forces = list(sm = "OR"),
        message = "Default of sm depends on method",
        confirmed_by = "formals_default", confidence = "medium"
      )
    ),
    scan_metadata = list(
      layers_completed = c("layer1_formals", "layer2_rd"),
      timestamp = "2026-01-01T00:00:00+0000",
      package_version = "7.0-0"
    )
  )
}

make_mock_references <- function() {
  list(list(
    doi = "10.1234/test",
    title = "Test Paper on Meta-Analysis Methods",
    authors = c("Author A", "Author B"),
    abstract = "This paper reviews meta-analysis methods.",
    journal = "Statistical Methods Journal",
    year = 2020L
  ))
}

mock_llm_yaml_response <- function() {
  paste(
    "nodes:",
    "  - id: choose_method",
    "    question: Which method to use?",
    "---",
    "topic: method_selection",
    "entries:",
    "  - when: method is MH",
    "    recommendation: Use Mantel-Haenszel for sparse data",
    "---",
    "constraints:",
    "  - id: c1",
    "    type: forces",
    "    param: sm",
    sep = "\n"
  )
}

# -- assemble_draft_prompt() ---------------------------------------------------

test_that("assemble_draft_prompt: includes package info", {
  # Given: a ScanResult
  # When:  assembling prompt
  # Then:  prompt contains package and function names
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr)
  expect_true(grepl("meta", prompt))
  expect_true(grepl("metabin", prompt))
})

test_that("assemble_draft_prompt: includes parameters", {
  # Given: a ScanResult with parameters
  # When:  assembling prompt
  # Then:  prompt lists parameter names and classifications
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr)
  expect_true(grepl("method", prompt))
  expect_true(grepl("statistical_decision", prompt))
  expect_true(grepl("data_input", prompt))
})

test_that("assemble_draft_prompt: includes dependencies", {
  # Given: a ScanResult with dependency graph
  # When:  assembling prompt
  # Then:  prompt shows dependencies
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr)
  expect_true(grepl("sm depends on.*method", prompt))
})

test_that("assemble_draft_prompt: includes valid values", {
  # Given: a ScanResult with valid values
  # When:  assembling prompt
  # Then:  prompt lists valid values
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr)
  expect_true(grepl("MH.*Inverse.*Peto", prompt))
})

test_that("assemble_draft_prompt: includes constraints", {
  # Given: a ScanResult with constraints
  # When:  assembling prompt
  # Then:  prompt shows constraint info
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr)
  expect_true(grepl("forces", prompt))
  expect_true(grepl("medium", prompt))
})

test_that("assemble_draft_prompt: includes references", {
  # Given: a ScanResult and references
  # When:  assembling prompt with references
  # Then:  prompt includes reference information
  sr <- make_test_scan_result()
  refs <- make_mock_references()
  prompt <- bridle:::assemble_draft_prompt(sr, refs)
  expect_true(grepl("Author A", prompt))
  expect_true(grepl("meta-analysis methods", prompt, ignore.case = TRUE))
})

test_that("assemble_draft_prompt: handles no references", {
  # Given: a ScanResult without references
  # When:  assembling prompt
  # Then:  prompt is valid without references section
  sr <- make_test_scan_result()
  prompt <- bridle:::assemble_draft_prompt(sr, NULL)
  expect_false(grepl("## References", prompt))
  expect_true(grepl("## Task", prompt))
})

# -- parse_draft_response() ----------------------------------------------------

test_that("parse_draft_response: parses three YAML sections", {
  # Given: a YAML response with three sections separated by ---
  # When:  parsing
  # Then:  returns list with decision_graph, knowledge, constraints
  response <- mock_llm_yaml_response()
  result <- bridle:::parse_draft_response(response)

  expect_true(is.list(result$decision_graph))
  expect_true(is.list(result$knowledge))
  expect_true(is.list(result$constraints))
})

test_that("parse_draft_response: handles single section", {
  # Given: a response with only one YAML section
  # When:  parsing
  # Then:  returns first section, others empty
  response <- "nodes:\n  - id: node1"
  result <- bridle:::parse_draft_response(response)
  expect_true(!is.null(result$decision_graph$nodes))
  expect_equal(result$knowledge, list())
  expect_equal(result$constraints, list())
})

test_that("parse_draft_response: handles malformed YAML", {
  # Given: invalid YAML content
  # When:  parsing
  # Then:  returns empty lists (graceful degradation)
  response <- ":::invalid:::yaml:::"
  result <- bridle:::parse_draft_response(response)
  expect_true(is.list(result$decision_graph))
})

test_that("parse_draft_response: handles empty response", {
  # Given: empty string response
  # When:  parsing
  # Then:  returns empty lists
  result <- bridle:::parse_draft_response("")
  expect_equal(result$decision_graph, list())
  expect_equal(result$knowledge, list())
  expect_equal(result$constraints, list())
})

# -- write_draft_files() -------------------------------------------------------

test_that("write_draft_files: creates YAML files", {
  # Given: parsed draft content
  # When:  writing files
  # Then:  creates decision_graph.yaml, knowledge/, constraints/
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "test"),
    constraints = list(constraints = list(list(id = "c1")))
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  expect_true(file.exists(file.path(tmp, "decision_graph.yaml")))
  expect_true(file.exists(file.path(tmp, "knowledge", "fn.yaml")))
  expect_true(file.exists(file.path(tmp, "constraints", "technical.yaml")))
})

test_that("write_draft_files: YAML content is valid", {
  # Given: draft content written to files
  # When:  reading back
  # Then:  YAML is valid and matches input
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "test"),
    constraints = list(constraints = list(list(id = "c1")))
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  graph <- yaml::yaml.load_file(file.path(tmp, "decision_graph.yaml"))
  expect_equal(graph$nodes[[1L]]$id, "n1")
})

# -- draft_knowledge() integration tests ---------------------------------------

test_that("draft_knowledge: produces drafts with mocked LLM", {
  # Given: a ScanResult and mocked LLM response
  # When:  calling draft_knowledge
  # Then:  returns parsed drafts and writes files
  sr <- make_test_scan_result()
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      mock_llm_yaml_response()
    }
  )

  result <- draft_knowledge(sr, output_dir = tmp)

  expect_true(is.list(result$decision_graph))
  expect_true(is.list(result$knowledge))
  expect_true(file.exists(file.path(tmp, "decision_graph.yaml")))
})

test_that("draft_knowledge: LLM error produces abort", {
  # Given: LLM that returns an error
  # When:  calling draft_knowledge
  # Then:  error with informative message
  sr <- make_test_scan_result()
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      stop("API key invalid")
    }
  )

  expect_error(
    draft_knowledge(sr, output_dir = tmp),
    "LLM drafting failed"
  )
})

test_that("draft_knowledge: includes references in prompt", {
  # Given: ScanResult + references
  # When:  drafting with mocked LLM
  # Then:  LLM receives prompt with references
  sr <- make_test_scan_result()
  refs <- make_mock_references()
  tmp <- withr::local_tempdir()
  captured_prompt <- NULL

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      captured_prompt <<- prompt
      mock_llm_yaml_response()
    }
  )

  draft_knowledge(sr, references = refs, output_dir = tmp)
  expect_true(grepl("Author A", captured_prompt))
})

# -- sanitize_topic_name() ----------------------------------------------------

test_that("sanitize_topic_name: normal topic passes through", {
  expect_equal(bridle:::sanitize_topic_name("effect_measures"), "effect_measures")
})

test_that("sanitize_topic_name: path traversal is stripped", {
  expect_equal(
    bridle:::sanitize_topic_name("../constraints/technical"),
    "technical"
  )
})

test_that("sanitize_topic_name: NULL falls back to default", {
  expect_equal(bridle:::sanitize_topic_name(NULL), "default")
})

test_that("sanitize_topic_name: empty string falls back to default", {
  expect_equal(bridle:::sanitize_topic_name(""), "default")
  expect_equal(bridle:::sanitize_topic_name("  "), "default")
})

test_that("sanitize_topic_name: leading dots removed", {
  expect_equal(bridle:::sanitize_topic_name(".hidden"), "hidden")
  expect_equal(bridle:::sanitize_topic_name("..foo"), "foo")
})

test_that("sanitize_topic_name: special chars replaced with underscore", {
  expect_equal(
    bridle:::sanitize_topic_name("effect/measures"),
    "measures"
  )
})

# -- extract_graph_topics() ---------------------------------------------------

test_that("extract_graph_topics: extracts topics with parameters", {
  # Given: graph with multiple topics and parameters
  # When:  extracting topics
  # Then:  returns named list mapping topics to parameter vectors
  graph_raw <- list(graph = list(nodes = list(
    n1 = list(type = "decision", topic = "effect_measures", parameter = "measure"),
    n2 = list(type = "decision", topic = "estimation", parameter = "method"),
    n3 = list(type = "diagnosis", topic = "estimation"),
    n4 = list(type = "execution")
  )))

  result <- bridle:::extract_graph_topics(graph_raw)

  expect_equal(length(result), 2L)
  expect_true("effect_measures" %in% names(result))
  expect_true("estimation" %in% names(result))
  expect_equal(result$effect_measures, "measure")
  expect_equal(result$estimation, "method")
})

test_that("extract_graph_topics: returns empty for unnamed node list", {
  # Given: graph with unnamed node list
  # When:  extracting topics
  # Then:  returns empty list
  graph_raw <- list(nodes = list(list(type = "decision", topic = "t1")))
  expect_equal(bridle:::extract_graph_topics(graph_raw), list())
})

test_that("extract_graph_topics: returns empty for NULL nodes", {
  # Given: empty graph
  # When:  extracting topics
  # Then:  returns empty list
  expect_equal(bridle:::extract_graph_topics(list()), list())
})

test_that("extract_graph_topics: skips nodes without topic", {
  # Given: graph where some nodes lack a topic
  # When:  extracting topics
  # Then:  only nodes with topic are included
  graph_raw <- list(graph = list(nodes = list(
    gather = list(type = "context_gathering"),
    decide = list(type = "decision", topic = "t1", parameter = "p1")
  )))

  result <- bridle:::extract_graph_topics(graph_raw)
  expect_equal(length(result), 1L)
  expect_equal(names(result), "t1")
})

# -- assemble_topic_prompt() ----------------------------------------

test_that("assemble_topic_prompt: includes topic and params", {
  # Given: topic name, parameters, package, function
  # When:  assembling topic prompt
  # Then:  prompt contains all required fields
  prompt <- bridle:::assemble_topic_prompt(
    "heterogeneity", c("tau2_estimator"), "metafor", "rma.uni"
  )

  expect_true(grepl("heterogeneity", prompt))
  expect_true(grepl("tau2_estimator", prompt))
  expect_true(grepl("metafor", prompt))
  expect_true(grepl("rma.uni", prompt))
  expect_true(grepl("SINGLE YAML", prompt))
})

test_that("assemble_topic_prompt: handles empty params", {
  # Given: topic with no parameters
  # When:  assembling topic prompt
  # Then:  uses 'general' as parameter description
  prompt <- bridle:::assemble_topic_prompt(
    "bias", character(0), "metafor", "rma.uni"
  )
  expect_true(grepl("general", prompt))
})

# -- generate_multi_topic_knowledge() -----------------------------------------

test_that("generate_multi_topic_knowledge: single topic returns one entry", {
  # Given: graph with one topic, knowledge matching that topic
  # When:  generating multi-topic knowledge
  # Then:  returns single-entry named list
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", topic = "t1", parameter = "p1")
    ))),
    knowledge = list(topic = "t1", entries = list(list(id = "e1")))
  )

  result <- bridle:::generate_multi_topic_knowledge(
    drafts, "pkg", "fn", NULL, NULL
  )

  expect_equal(length(result), 1L)
  expect_equal(names(result), "t1")
  expect_equal(result$t1$topic, "t1")
})

test_that("generate_multi_topic_knowledge: blank topic falls back to graph topic", {
  # Given: graph with one topic, knowledge has empty topic string
  # When:  generating multi-topic knowledge
  # Then:  uses the graph's topic name as the key
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", topic = "t1", parameter = "p1")
    ))),
    knowledge = list(topic = "", entries = list(list(id = "e1")))
  )

  result <- bridle:::generate_multi_topic_knowledge(
    drafts, "pkg", "fn", NULL, NULL
  )

  expect_true("t1" %in% names(result))
  expect_equal(result$t1$topic, "")
})

test_that("generate_multi_topic_knowledge: zero-topic graph preserves knowledge", {
  # Given: decision graph without topic fields
  # When:  generating multi-topic knowledge
  # Then:  no supplementary LLM call; existing knowledge returned with default key
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", parameter = "p1")
    ))),
    knowledge = list(topic = "existing", entries = list(list(id = "e1")))
  )

  local_mocked_bindings(
    bridle_chat = function(...) stop("should not be called")
  )

  result <- bridle:::generate_multi_topic_knowledge(
    drafts, "pkg", "fn", NULL, NULL
  )

  expect_equal(length(result), 1L)
  expect_equal(names(result), "existing")
  expect_equal(result$existing$topic, "existing")
})

test_that("generate_multi_topic_knowledge: multi-topic triggers extra calls", {
  # Given: graph with 2 topics, first knowledge covers one
  # When:  generating multi-topic knowledge with mocked bridle_chat
  # Then:  supplementary call made for second topic
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", topic = "t1", parameter = "p1"),
      n2 = list(type = "decision", topic = "t2", parameter = "p2")
    ))),
    knowledge = list(topic = "t1", entries = list(list(id = "e1")))
  )

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      paste(
        "topic: t2",
        "target_parameter: p2",
        "package: pkg",
        "function: fn",
        "entries:",
        "  - id: e2",
        "    when: always",
        "    properties:",
        "      - some fact",
        sep = "\n"
      )
    }
  )

  result <- bridle:::generate_multi_topic_knowledge(
    drafts, "pkg", "fn", NULL, NULL
  )

  expect_equal(length(result), 2L)
  expect_true("t1" %in% names(result))
  expect_true("t2" %in% names(result))
  expect_equal(result$t2$topic, "t2")
})

test_that("generate_multi_topic_knowledge: supplementary LLM error is warning", {
  # Given: graph with 2 topics, supplementary LLM call fails
  # When:  generating multi-topic knowledge
  # Then:  first topic present, second skipped with warning
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", topic = "t1", parameter = "p1"),
      n2 = list(type = "decision", topic = "t2", parameter = "p2")
    ))),
    knowledge = list(topic = "t1", entries = list(list(id = "e1")))
  )

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      stop("API unavailable")
    }
  )

  expect_warning(
    result <- bridle:::generate_multi_topic_knowledge(
      drafts, "pkg", "fn", NULL, NULL
    ),
    "Failed to generate knowledge"
  )

  expect_equal(length(result), 1L)
  expect_equal(names(result), "t1")
})

test_that("generate_multi_topic_knowledge: malformed YAML is warning", {
  # Given: graph with 2 topics, supplementary LLM returns invalid YAML
  # When:  generating multi-topic knowledge
  # Then:  first topic present, second skipped with warning
  drafts <- list(
    decision_graph = list(graph = list(nodes = list(
      n1 = list(type = "decision", topic = "t1", parameter = "p1"),
      n2 = list(type = "decision", topic = "t2", parameter = "p2")
    ))),
    knowledge = list(topic = "t1", entries = list(list(id = "e1")))
  )

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter. mock binding
      "key: [unclosed bracket"
    }
  )

  expect_warning(
    result <- bridle:::generate_multi_topic_knowledge(
      drafts, "pkg", "fn", NULL, NULL
    ),
    "Failed to parse knowledge YAML"
  )

  expect_equal(length(result), 1L)
})

# -- write_draft_files with multi-topic knowledge_list ------------------------

test_that("write_draft_files: writes multiple knowledge files from knowledge_list", {
  # Given: drafts with knowledge_list containing 2 topics
  # When:  writing files
  # Then:  knowledge/<topic>.yaml exists for each topic
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "t1"),
    constraints = list(constraints = list(list(id = "c1"))),
    knowledge_list = list(
      t1 = list(topic = "t1", entries = list(list(id = "e1"))),
      t2 = list(topic = "t2", entries = list(list(id = "e2")))
    )
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  expect_true(file.exists(file.path(tmp, "knowledge", "t1.yaml")))
  expect_true(file.exists(file.path(tmp, "knowledge", "t2.yaml")))
  expect_false(file.exists(file.path(tmp, "knowledge", "fn.yaml")))

  k1 <- yaml::yaml.load_file(file.path(tmp, "knowledge", "t1.yaml"))
  expect_equal(k1$topic, "t1")
})

test_that("write_draft_files: falls back to func name when no knowledge_list", {
  # Given: drafts without knowledge_list
  # When:  writing files
  # Then:  single knowledge/<func>.yaml written
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "test"),
    constraints = list(constraints = list(list(id = "c1")))
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  expect_true(file.exists(file.path(tmp, "knowledge", "fn.yaml")))
})

test_that("write_draft_files: sanitizes unsafe topic names", {
  # Given: knowledge_list with path-traversal and dotfile topic names
  # When:  writing files
  # Then:  filenames are sanitized, no files escape knowledge/
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "ignored"),
    constraints = list(constraints = list(list(id = "c1"))),
    knowledge_list = list(
      "..\\constraints\\technical" = list(
        topic = "..\\constraints\\technical",
        entries = list(list(id = "e1"))
      ),
      ".hidden" = list(
        topic = ".hidden",
        entries = list(list(id = "e2"))
      )
    )
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  expect_true(file.exists(file.path(tmp, "knowledge", "technical.yaml")))
  expect_true(file.exists(file.path(tmp, "knowledge", "hidden.yaml")))
  expect_false(file.exists(file.path(tmp, "..", "constraints", "technical.yaml")))
})

test_that("write_draft_files: detects filename collisions", {
  # Given: two topics that sanitize to the same filename
  # When:  writing files
  # Then:  second file gets a suffix and a warning is raised
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "ignored"),
    constraints = list(constraints = list(list(id = "c1"))),
    knowledge_list = list(
      "foo/bar" = list(topic = "bar", entries = list(list(id = "e1"))),
      "baz/bar" = list(topic = "bar", entries = list(list(id = "e2")))
    )
  )
  tmp <- withr::local_tempdir()

  expect_warning(
    bridle:::write_draft_files(drafts, tmp, "pkg", "fn"),
    "collides with existing filename"
  )

  expect_true(file.exists(file.path(tmp, "knowledge", "bar.yaml")))
  expect_true(file.exists(file.path(tmp, "knowledge", "bar_2.yaml")))
})

# -- generate_draft_context_schema() ------------------------------------------

test_that("generate_draft_context_schema: decision + execution nodes", {
  # Given: graph with decision (parameter) and execution nodes
  # When:  generating context schema
  # Then:  variables include k, decision params, and fit_result
  drafts <- list(decision_graph = list(graph = list(nodes = list(
    gather_data = list(type = "context_gathering"),
    choose_method = list(type = "decision", parameter = "method"),
    run_analysis = list(type = "execution")
  ))))

  result <- bridle:::generate_draft_context_schema(drafts)

  expect_true(is.list(result))
  names_out <- vapply(result$variables, `[[`, character(1), "name")
  expect_true("k" %in% names_out)
  expect_true("method" %in% names_out)
  expect_true("fit_result" %in% names_out)

  method_var <- result$variables[[which(names_out == "method")]]
  expect_equal(method_var$available_from, "parameter_decided")
  expect_equal(method_var$depends_on_node, "choose_method")
  expect_equal(method_var$source_expression, "decisions$method")
})

test_that("generate_draft_context_schema: only context_gathering nodes", {
  # Given: graph with only context_gathering nodes (no decision/execution)
  # When:  generating context schema
  # Then:  variables contain only k
  drafts <- list(decision_graph = list(graph = list(nodes = list(
    gather = list(type = "context_gathering"),
    done = list(type = "context_gathering")
  ))))

  result <- bridle:::generate_draft_context_schema(drafts)

  names_out <- vapply(result$variables, `[[`, character(1), "name")
  expect_equal(names_out, "k")
})

test_that("generate_draft_context_schema: empty graph returns NULL", {
  # Given: drafts with empty decision_graph
  # When:  generating context schema
  # Then:  returns NULL
  drafts <- list(decision_graph = list())
  expect_null(bridle:::generate_draft_context_schema(drafts))
})

test_that("generate_draft_context_schema: unnamed node list uses id fallback", {
  # Given: graph with unnamed (sequence-form) node list
  # When:  generating context schema
  # Then:  falls back to node id for depends_on_node
  drafts <- list(decision_graph = list(
    nodes = list(
      list(id = "n1", type = "decision", parameter = "method"),
      list(id = "n2", type = "execution")
    )
  ))

  result <- bridle:::generate_draft_context_schema(drafts)
  names_out <- vapply(result$variables, `[[`, character(1), "name")
  expect_true("method" %in% names_out)
  expect_true("fit_result" %in% names_out)

  method_var <- result$variables[[which(names_out == "method")]]
  expect_equal(method_var$depends_on_node, "n1")
})

test_that("generate_draft_context_schema: multiple execution nodes no duplicate", {
  # Given: graph with two execution nodes
  # When:  generating context schema
  # Then:  only one fit_result variable (from first execution node)
  drafts <- list(decision_graph = list(graph = list(nodes = list(
    run1 = list(type = "execution"),
    run2 = list(type = "execution")
  ))))

  result <- bridle:::generate_draft_context_schema(drafts)
  names_out <- vapply(result$variables, `[[`, character(1), "name")
  expect_equal(sum(names_out == "fit_result"), 1L)

  fit_var <- result$variables[[which(names_out == "fit_result")]]
  expect_equal(fit_var$depends_on_node, "run1")
})

test_that("generate_draft_context_schema: multi-param decision node", {
  # Given: decision node with multiple parameters
  # When:  generating context schema
  # Then:  one variable per parameter
  drafts <- list(decision_graph = list(graph = list(nodes = list(
    multi = list(type = "decision", parameter = list("method", "measure"))
  ))))

  result <- bridle:::generate_draft_context_schema(drafts)
  names_out <- vapply(result$variables, `[[`, character(1), "name")
  expect_true("method" %in% names_out)
  expect_true("measure" %in% names_out)
})

# -- generate_draft_manifest() ------------------------------------------------

test_that("generate_draft_manifest: extracts max_iterations from graph", {
  # Given: graph with global_policy.max_iterations = 5
  # When:  generating manifest
  # Then:  manifest has policy_defaults.max_iterations = 5
  drafts <- list(decision_graph = list(
    graph = list(global_policy = list(max_iterations = 5L))
  ))

  result <- bridle:::generate_draft_manifest(drafts)

  expect_equal(result$policy_defaults$max_iterations, 5L)
})

test_that("generate_draft_manifest: defaults to 10 when no global_policy", {
  # Given: graph without global_policy
  # When:  generating manifest
  # Then:  manifest defaults to 10 (matching runtime .default_max_iterations)
  drafts <- list(decision_graph = list(graph = list(nodes = list())))

  result <- bridle:::generate_draft_manifest(drafts)

  expect_equal(result$policy_defaults$max_iterations, 10L)
})

test_that("generate_draft_manifest: empty graph defaults to 10", {
  # Given: completely empty decision_graph
  # When:  generating manifest
  # Then:  manifest defaults to 10 (matching runtime .default_max_iterations)
  drafts <- list(decision_graph = list())

  result <- bridle:::generate_draft_manifest(drafts)

  expect_equal(result$policy_defaults$max_iterations, 10L)
})

test_that("generate_draft_manifest: non-numeric max_iterations falls back", {
  # Given: graph with non-numeric max_iterations
  # When:  generating manifest
  # Then:  falls back to default 10
  drafts <- list(decision_graph = list(
    graph = list(global_policy = list(max_iterations = "abc"))
  ))

  result <- bridle:::generate_draft_manifest(drafts)
  expect_equal(result$policy_defaults$max_iterations, 10L)
})

test_that("generate_draft_manifest: fractional max_iterations falls back", {
  # Given: graph with fractional max_iterations
  # When:  generating manifest
  # Then:  falls back to default 10
  drafts <- list(decision_graph = list(
    graph = list(global_policy = list(max_iterations = 5.5))
  ))

  result <- bridle:::generate_draft_manifest(drafts)
  expect_equal(result$policy_defaults$max_iterations, 10L)
})

test_that("generate_draft_manifest: whole double accepted as integer", {
  # Given: graph with max_iterations as double 8.0 (YAML often parses as double)
  # When:  generating manifest
  # Then:  coerced to integer 8L
  drafts <- list(decision_graph = list(
    graph = list(global_policy = list(max_iterations = 8.0))
  ))

  result <- bridle:::generate_draft_manifest(drafts)
  expect_equal(result$policy_defaults$max_iterations, 8L)
})

# -- write_draft_files with context_schema + manifest -------------------------

test_that("write_draft_files: writes context_schema.yaml and manifest.yaml", {
  # Given: drafts with context_schema and manifest
  # When:  writing files
  # Then:  both new files exist and are valid YAML
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "test"),
    constraints = list(constraints = list(list(id = "c1"))),
    context_schema = list(variables = list(list(
      name = "k", description = "number of studies",
      available_from = "data_loaded", source_expression = "nrow(data)"
    ))),
    manifest = list(policy_defaults = list(max_iterations = 10L))
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  cs_path <- file.path(tmp, "context_schema.yaml")
  mf_path <- file.path(tmp, "manifest.yaml")
  expect_true(file.exists(cs_path))
  expect_true(file.exists(mf_path))

  cs <- yaml::yaml.load_file(cs_path)
  expect_equal(cs$variables[[1L]]$name, "k")

  mf <- yaml::yaml.load_file(mf_path)
  expect_equal(mf$policy_defaults$max_iterations, 10L)
})

test_that("write_draft_files: skips context_schema when NULL", {
  # Given: drafts without context_schema
  # When:  writing files
  # Then:  no context_schema.yaml file
  drafts <- list(
    decision_graph = list(nodes = list(list(id = "n1"))),
    knowledge = list(topic = "test"),
    constraints = list(constraints = list(list(id = "c1"))),
    context_schema = NULL,
    manifest = NULL
  )
  tmp <- withr::local_tempdir()

  bridle:::write_draft_files(drafts, tmp, "pkg", "fn")

  expect_false(file.exists(file.path(tmp, "context_schema.yaml")))
  expect_false(file.exists(file.path(tmp, "manifest.yaml")))
})
