# Tests for Prompt Assembler and LLM Utils (Issue #60)

# -- Helpers -------------------------------------------------------------------

make_test_node <- function(type = "decision", topic = "effect_measure",
                           parameter = "sm") {
  Node( # nolint: object_usage_linter. S7 class in R/decision_graph.R
    type = type, topic = topic, parameter = parameter,
    transitions = list(
      Transition(to = "end", always = TRUE) # nolint: object_usage_linter. S7 class
    )
  )
}

make_test_retrieval <- function(n_entries = 1L, n_constraints = 0L) {
  entries <- lapply(seq_len(n_entries), function(i) {
    KnowledgeEntry( # nolint: object_usage_linter. S7 class in R/knowledge.R
      id = paste0("entry_", i), when = paste("condition", i),
      properties = paste("fact", i)
    )
  })
  constraints <- if (n_constraints > 0L) {
    lapply(seq_len(n_constraints), function(i) {
      Constraint( # nolint: object_usage_linter. S7 class in R/constraints.R
        id = paste0("c_", i), source = "expert", type = "valid_values",
        param = "sm", values = c("OR", "RR"),
        message = paste("constraint message", i)
      )
    })
  } else {
    list()
  }
  RetrievalResult( # nolint: object_usage_linter. S7 class in R/knowledge_retriever.R
    entries = entries,
    entry_ids_presented = vapply(entries, function(e) e@id, character(1)),
    constraints = constraints
  )
}

make_test_trace <- function(needs_llm = TRUE) {
  cands <- if (needs_llm) {
    list(
      TransitionCandidate( # nolint: object_usage_linter. S7 class in R/graph_engine.R
        to = "opt_a", when = "few studies",
        computable_hint = character(0),
        eval_result = "not_evaluated", fallback_to_llm = TRUE
      ),
      TransitionCandidate( # nolint: object_usage_linter. S7 class in R/graph_engine.R
        to = "opt_b", when = "many studies",
        computable_hint = character(0),
        eval_result = "not_evaluated", fallback_to_llm = TRUE
      )
    )
  } else {
    list(
      TransitionCandidate( # nolint: object_usage_linter. S7 class in R/graph_engine.R
        to = "next_node", when = character(0),
        computable_hint = "k < 5",
        eval_result = "true", fallback_to_llm = FALSE
      )
    )
  }
  TransitionTrace( # nolint: object_usage_linter. S7 class in R/graph_engine.R
    candidates = cands,
    selected_transition = if (needs_llm) "" else "next_node",
    selection_basis = if (needs_llm) "llm" else "hint"
  )
}

# -- PromptResult S7 class -----------------------------------------------------

test_that("PromptResult constructs correctly", {
  pr <- PromptResult( # nolint: object_usage_linter. S7 class in R/prompt_assembler.R
    prompt_text = "test", node_type = "decision"
  )
  expect_equal(pr@prompt_text, "test")
  expect_equal(pr@node_type, "decision")
  expect_false(pr@includes_transition_query)
})

test_that("PromptResult validates node_type", {
  expect_error(
    PromptResult( # nolint: object_usage_linter. S7 class
      prompt_text = "x", node_type = "invalid"
    ),
    "node_type"
  )
})

test_that("PromptResult accepts all valid node types", {
  for (nt in c("decision", "diagnosis", "execution", "context_gathering")) {
    pr <- PromptResult( # nolint: object_usage_linter. S7 class
      prompt_text = "t", node_type = nt
    )
    expect_equal(pr@node_type, nt)
  }
})

# -- assemble_runtime_prompt: decision node ------------------------------------

test_that("decision node prompt has all sections", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 2L, n_constraints = 1L)
  ctx <- make_session_context(
    variables = list(k = 5L),
    parameters = list(method = "MH")
  )
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_true(grepl("effect_measure", result@prompt_text))
  expect_true(grepl("Knowledge", result@prompt_text))
  expect_true(grepl("Constraints", result@prompt_text))
  expect_true(grepl("Current Context", result@prompt_text))
  expect_true(grepl("Decide the value", result@prompt_text))
  expect_equal(result@node_type, "decision")
  expect_equal(length(result@entry_ids_presented), 2L)
})

# -- assemble_runtime_prompt: execution node -----------------------------------

test_that("execution node prompt includes execution task", {
  node <- make_test_node(type = "execution", topic = "run_analysis", parameter = "")
  rr <- make_test_retrieval(n_entries = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_true(grepl("Generate R code", result@prompt_text))
  expect_equal(result@node_type, "execution")
})

# -- assemble_runtime_prompt: diagnosis node -----------------------------------

test_that("diagnosis node prompt includes diagnosis task", {
  node <- make_test_node(type = "diagnosis", topic = "check_results", parameter = "")
  rr <- make_test_retrieval(n_entries = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_true(grepl("Diagnose", result@prompt_text))
  expect_equal(result@node_type, "diagnosis")
})

# -- assemble_runtime_prompt: context_gathering --------------------------------

test_that("context_gathering node prompt includes data task", {
  node <- make_test_node(
    type = "context_gathering", topic = "describe_data", parameter = ""
  )
  rr <- make_test_retrieval(n_entries = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_true(grepl("context", result@prompt_text, ignore.case = TRUE))
  expect_equal(result@node_type, "context_gathering")
})

# -- assemble_runtime_prompt: transition query ---------------------------------

test_that("transition query appended when needs_llm", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 1L)
  ctx <- make_session_context()
  trace <- make_test_trace(needs_llm = TRUE)
  result <- assemble_runtime_prompt(node, rr, ctx, transition_trace = trace)
  expect_true(result@includes_transition_query)
  expect_true(grepl("Transition Decision", result@prompt_text))
  expect_true(grepl("opt_a", result@prompt_text))
  expect_true(grepl("opt_b", result@prompt_text))
})

test_that("no transition query when all resolved by hints", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 1L)
  ctx <- make_session_context()
  trace <- make_test_trace(needs_llm = FALSE)
  result <- assemble_runtime_prompt(node, rr, ctx, transition_trace = trace)
  expect_false(result@includes_transition_query)
})

test_that("no transition query when trace is NULL", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 1L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx, transition_trace = NULL)
  expect_false(result@includes_transition_query)
})

# -- assemble_runtime_prompt: entry_ids ----------------------------------------

test_that("entry_ids_presented propagated correctly", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 3L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_equal(result@entry_ids_presented, c("entry_1", "entry_2", "entry_3"))
})

# -- assemble_runtime_prompt: boundary -----------------------------------------

test_that("0 knowledge entries produces valid prompt", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_false(grepl("Knowledge", result@prompt_text))
  expect_equal(length(result@entry_ids_presented), 0L)
})

test_that("0 constraints produces valid prompt", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 1L, n_constraints = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_false(grepl("Constraints", result@prompt_text))
})

test_that("empty context produces valid prompt", {
  node <- make_test_node()
  rr <- make_test_retrieval(n_entries = 0L)
  ctx <- make_session_context()
  result <- assemble_runtime_prompt(node, rr, ctx)
  expect_false(grepl("Current Context", result@prompt_text))
})

# -- bridle_runtime_chat -------------------------------------------------------

test_that("bridle_runtime_chat requires ellmer", {
  local_mocked_bindings(
    check_installed = function(pkg, ...) {
      if (pkg == "ellmer") {
        rlang::abort("Package 'ellmer' is required.")
      }
    },
    .package = "rlang"
  )
  expect_error(bridle_runtime_chat(), "ellmer")
})

test_that("bridle_runtime_chat rejects unknown provider", {
  local_mocked_bindings(
    check_installed = function(pkg, ...) invisible(NULL), # nolint: object_usage_linter. mock
    .package = "rlang"
  )
  expect_error(bridle_runtime_chat(provider = "nonexistent"), "Unknown")
})

test_that("bridle_runtime_chat resolves from env var", {
  captured_fn <- NULL
  local_mocked_bindings(
    check_installed = function(pkg, ...) invisible(NULL), # nolint: object_usage_linter. mock
    .package = "rlang"
  )
  local_mocked_bindings(
    getFromNamespace = function(name, ns) { # nolint: object_usage_linter. mock
      captured_fn <<- name
      function(...) "mock_chat"
    },
    .package = "utils"
  )
  withr::local_envvar(BRIDLE_LLM_PROVIDER = "anthropic")
  result <- bridle_runtime_chat()
  expect_equal(captured_fn, "chat_anthropic")
})

test_that("bridle_runtime_chat defaults to github", {
  captured_fn <- NULL
  local_mocked_bindings(
    check_installed = function(pkg, ...) invisible(NULL), # nolint: object_usage_linter. mock
    .package = "rlang"
  )
  local_mocked_bindings(
    getFromNamespace = function(name, ns) { # nolint: object_usage_linter. mock
      captured_fn <<- name
      function(...) "mock_chat"
    },
    .package = "utils"
  )
  withr::local_envvar(BRIDLE_LLM_PROVIDER = NA)
  result <- bridle_runtime_chat()
  expect_equal(captured_fn, "chat_openai_compatible")
})
