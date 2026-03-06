# Tests for draft_knowledge() (ellmer-based AI drafting)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases
# All LLM calls mocked via local_mocked_bindings on bridle_chat

# -- Helpers -------------------------------------------------------------------

make_test_scan_result <- function() {
  ScanResult( # nolint: object_usage_linter. S7 class in R/scan_result.R
    package = "meta",
    func = "metabin",
    parameters = list(
      ParameterInfo( # nolint: object_usage_linter.
        name = "method", has_default = TRUE,
        default_expression = '"MH"', classification = "statistical_decision"
      ),
      ParameterInfo( # nolint: object_usage_linter.
        name = "sm", has_default = TRUE,
        default_expression = '"OR"', classification = "statistical_decision"
      ),
      ParameterInfo( # nolint: object_usage_linter.
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
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter.
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
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter.
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
    bridle_chat = function(prompt, provider, model) { # nolint: object_usage_linter.
      captured_prompt <<- prompt
      mock_llm_yaml_response()
    }
  )

  draft_knowledge(sr, references = refs, output_dir = tmp)
  expect_true(grepl("Author A", captured_prompt))
})
