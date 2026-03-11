# Pipeline integration tests: scan_package → fetch_references → draft_knowledge → validate_plugin
# Issue #133: Full pipeline validation with metafor
# scan_package runs against real metafor; HTTP and LLM are mocked.

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

mock_llm_pipeline_response <- function() {
  paste(
    "graph:",
    "  entry_node: choose_method",
    "  nodes:",
    "    choose_method:",
    "      type: decision",
    "      topic: estimation_method",
    "      parameter: method",
    "      transitions:",
    "        - to: configure_model",
    "          always: true",
    "    configure_model:",
    "      type: execution",
    "      transitions: []",
    "---",
    "topic: estimation_method",
    "target_parameter: method",
    "package: metafor",
    "function: rma.uni",
    "entries:",
    "  - id: e1",
    "    when: always",
    "    properties: Use REML for random-effects meta-analysis models",
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
    "      - ML",
    "      - DL",
    sep = "\n"
  )
}

# -- T01: Scan produces PackageScanResult --------------------------------------

test_that("T01: scan_package(metafor) returns PackageScanResult", {
  pkg <- scan_package("metafor")

  expect_true(S7::S7_inherits(pkg, PackageScanResult))
  expect_equal(pkg@package, "metafor")
  expect_true(length(pkg@functions) > 0L)
  expect_true(length(pkg@function_roles) > 0L)
})

test_that("T02: PackageScanResult classifies rma variants as analysis", {
  pkg <- scan_package("metafor")
  roles <- pkg@function_roles

  rma_fns <- grep("^rma", names(roles), value = TRUE)
  expect_true(length(rma_fns) > 0L)
  rma_roles <- roles[rma_fns]
  expect_true(all(rma_roles == "analysis"))
})

test_that("T03: PackageScanResult contains function families", {
  pkg <- scan_package("metafor")

  expect_true(length(pkg@function_families) > 0L)
  family_names <- vapply(
    pkg@function_families, function(f) f$name, character(1)
  )
  expect_true("rma" %in% family_names)
})

# -- T04: Module boundary integrity -------------------------------------------

test_that("T04: scanned functions have non-empty parameters and metadata", {
  pkg <- scan_package("metafor")

  for (fn_name in names(pkg@functions)) {
    sr <- pkg@functions[[fn_name]]
    expect_true(
      length(sr@parameters) > 0L,
      info = paste("No parameters for", fn_name)
    )
    expect_true(
      length(sr@scan_metadata[["layers_completed"]]) > 0L,
      info = paste("No layers_completed for", fn_name)
    )
  }
})

# -- T05: References extracted per function -----------------------------------

test_that("T05: analysis functions have references from Rd", {
  pkg <- scan_package("metafor")

  has_refs <- vapply(pkg@functions, function(sr) {
    length(sr@references) > 0L
  }, logical(1))
  expect_true(any(has_refs))
})

# -- T06: fetch_references on PackageScanResult --------------------------------

test_that("T06: fetch_references aggregates and deduplicates DOIs", {
  pkg <- scan_package("metafor")
  init_anonymous_pipeline()

  all_dois <- bridle:::collect_package_dois(pkg)
  call_count <- 0L

  local_mocked_bindings(
    openalex_get = function(doi, timeout = 10) {
      call_count <<- call_count + 1L
      mock_openalex_for_doi(doi)
    },
    rate_limit_sleep = function(seconds) invisible(NULL)
  )

  refs <- fetch_references(pkg)

  expect_true(is.list(refs))
  expect_true(length(refs) > 0L)
  for (r in refs) {
    expect_true(!is.null(r$doi))
    expect_true(!is.null(r$title))
    expect_true(!is.null(r$authors))
    expect_true(!is.null(r$abstract))
  }
  expect_equal(call_count, length(all_dois))
})

# -- T07-T09: draft_knowledge with mocked LLM ---------------------------------

test_that("T07: draft_knowledge writes 3 YAML files", {
  pkg <- scan_package("metafor")
  refs <- list(list(
    doi = "10.18637/jss.v036.i03",
    title = "metafor package",
    authors = c("Viechtbauer"),
    abstract = "R package for meta-analysis",
    journal = "JSS",
    year = 2010L
  ))

  tmp <- withr::local_tempdir()
  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      mock_llm_pipeline_response()
    }
  )

  drafts <- draft_knowledge(pkg, references = refs, output_dir = tmp)

  expect_true(file.exists(file.path(tmp, "decision_graph.yaml")))
  expect_true(file.exists(
    file.path(tmp, "knowledge", "estimation_method.yaml")
  ))
  expect_true(file.exists(
    file.path(tmp, "constraints", "technical.yaml")
  ))
  expect_true(is.list(drafts$decision_graph))
  expect_true(is.list(drafts$knowledge))
  expect_true(is.list(drafts$constraints))
})

test_that("T08: draft output loads with S7 readers", {
  pkg <- scan_package("metafor")
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      mock_llm_pipeline_response()
    }
  )
  draft_knowledge(pkg, output_dir = tmp)

  graph <- read_decision_graph(file.path(tmp, "decision_graph.yaml"))
  expect_true(S7::S7_inherits(graph, DecisionGraph))
  expect_equal(graph@entry_node, "choose_method")
  expect_true("choose_method" %in% names(graph@nodes))

  ks <- read_knowledge(file.path(tmp, "knowledge", "estimation_method.yaml"))
  expect_true(S7::S7_inherits(ks, KnowledgeStore))
  expect_equal(ks@topic, "estimation_method")
  expect_equal(ks@target_parameter, "method")

  cs <- read_constraints(file.path(tmp, "constraints", "technical.yaml"))
  expect_true(S7::S7_inherits(cs, ConstraintSet))
  expect_equal(cs@package, "metafor")
})

test_that("T09: validate_plugin passes on draft output", {
  pkg <- scan_package("metafor")
  tmp <- withr::local_tempdir()

  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      mock_llm_pipeline_response()
    }
  )
  draft_knowledge(pkg, output_dir = tmp)

  graph <- read_decision_graph(file.path(tmp, "decision_graph.yaml"))
  ks <- read_knowledge(file.path(tmp, "knowledge", "estimation_method.yaml"))
  cs <- read_constraints(file.path(tmp, "constraints", "technical.yaml"))

  result <- validate_plugin(graph, list(ks), list(cs))
  expect_true(is_valid(result))
})

# -- T10: Full pipeline end-to-end --------------------------------------------

test_that("T10: full pipeline scan -> fetch -> draft -> validate", {
  pkg <- scan_package("metafor")
  init_anonymous_pipeline()

  local_mocked_bindings(
    openalex_get = function(doi, timeout = 10) {
      mock_openalex_for_doi(doi)
    },
    rate_limit_sleep = function(seconds) invisible(NULL)
  )
  refs <- fetch_references(pkg)
  expect_true(length(refs) > 0L)

  tmp <- withr::local_tempdir()
  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      expect_true(grepl("metafor", prompt))
      mock_llm_pipeline_response()
    }
  )
  drafts <- draft_knowledge(pkg, references = refs, output_dir = tmp)

  graph <- read_decision_graph(file.path(tmp, "decision_graph.yaml"))
  ks <- read_knowledge(file.path(tmp, "knowledge", "estimation_method.yaml"))
  cs <- read_constraints(file.path(tmp, "constraints", "technical.yaml"))

  result <- validate_plugin(graph, list(ks), list(cs))
  expect_true(is_valid(result))

  expect_true(S7::S7_inherits(graph, DecisionGraph))
  expect_true(S7::S7_inherits(ks, KnowledgeStore))
  expect_true(S7::S7_inherits(cs, ConstraintSet))
  expect_equal(length(result@errors), 0L)
  expect_equal(length(result@warnings), 0L)
})

# -- T11: scan → draft data handoff -------------------------------------------

test_that("T11: PackageScanResult passes through to assemble_package_prompt", {
  pkg <- scan_package("metafor")
  captured_prompt <- NULL

  tmp <- withr::local_tempdir()
  local_mocked_bindings(
    bridle_chat = function(prompt, provider, model) {
      captured_prompt <<- prompt
      mock_llm_pipeline_response()
    }
  )
  draft_knowledge(pkg, output_dir = tmp)

  expect_true(grepl("Package: metafor", captured_prompt))
  expect_true(grepl("Function:", captured_prompt))
  expect_true(grepl("rma", captured_prompt))
})
