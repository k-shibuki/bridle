# Tests for GraphEngine S7 classes (ADR-0002, ADR-0003, ADR-0005)
# make_test_engine() lives in helper-mocks.R (co-location pattern).

# -- S7 class construction ----------------------------------------------------

test_that("TransitionCandidate constructs with valid args", {
  tc <- TransitionCandidate(
    to = "n2", eval_result = "true", fallback_to_llm = FALSE
  )
  expect_true(S7::S7_inherits(tc, TransitionCandidate))
})

test_that("TransitionTrace constructs with candidates", {
  tc <- TransitionCandidate(
    to = "n2", eval_result = "true", fallback_to_llm = FALSE
  )
  tt <- TransitionTrace(
    candidates = list(tc), selected_transition = "n2", selection_basis = "hint"
  )
  expect_true(S7::S7_inherits(tt, TransitionTrace))
})

test_that("AdvanceResult constructs with status", {
  ar <- AdvanceResult(status = "continue", node_id = "n1")
  expect_true(S7::S7_inherits(ar, AdvanceResult))
})

test_that("GraphEngine constructs at entry node", {
  engine <- make_test_engine()
  expect_equal(engine_current_node(engine), "start")
  expect_equal(length(engine_visit_counts(engine)), 0L)
})

# -- transition evaluation ----------------------------------------------------

test_that("transition with always=TRUE evaluates to true", {
  engine <- make_test_engine()
  candidates <- evaluate_transitions(engine, "start")
  expect_equal(length(candidates), 1L)
  expect_equal(candidates[[1]]@eval_result, "true")
  expect_false(candidates[[1]]@fallback_to_llm)
})

test_that("transition with computable_hint TRUE selects correctly", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      transitions = list(
        Transition(to = "small", when = "few studies", computable_hint = "k < 5"),
        Transition(to = "large", otherwise = TRUE)
      )
    ),
    small = Node(type = "execution", transitions = list()),
    large = Node(type = "execution", transitions = list())
  )
  ctx <- make_session_context(variables = list(k = 3))
  engine <- make_test_engine(nodes = nodes, context = ctx)
  candidates <- evaluate_transitions(engine, "start")
  expect_equal(candidates[[1]]@eval_result, "true")
})

test_that("transition with computable_hint FALSE falls through", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      transitions = list(
        Transition(to = "small", when = "few studies", computable_hint = "k < 5"),
        Transition(to = "large", otherwise = TRUE)
      )
    ),
    small = Node(type = "execution", transitions = list()),
    large = Node(type = "execution", transitions = list())
  )
  ctx <- make_session_context(variables = list(k = 10))
  engine <- make_test_engine(nodes = nodes, context = ctx)
  candidates <- evaluate_transitions(engine, "start")
  expect_equal(candidates[[1]]@eval_result, "false")
})

test_that("transition with unavailable variable falls back to LLM", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      transitions = list(
        Transition(to = "high", when = "high I2", computable_hint = "I2 > 50"),
        Transition(to = "low", otherwise = TRUE)
      )
    ),
    high = Node(type = "execution", transitions = list()),
    low = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  candidates <- evaluate_transitions(engine, "start")
  expect_equal(candidates[[1]]@eval_result, "error")
  expect_true(candidates[[1]]@fallback_to_llm)
})

test_that("transition with when but no hint falls back to LLM", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      transitions = list(
        Transition(to = "a", when = "data has many studies"),
        Transition(to = "b", otherwise = TRUE)
      )
    ),
    a = Node(type = "execution", transitions = list()),
    b = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  candidates <- evaluate_transitions(engine, "start")
  expect_equal(candidates[[1]]@eval_result, "not_evaluated")
  expect_true(candidates[[1]]@fallback_to_llm)
})

# -- select_transition ---------------------------------------------------------

test_that("select_transition picks first true candidate", {
  engine <- make_test_engine()
  candidates <- list(
    TransitionCandidate(to = "a", eval_result = "false", fallback_to_llm = FALSE),
    TransitionCandidate(to = "b", eval_result = "true", fallback_to_llm = FALSE)
  )
  result <- select_transition(engine, candidates)
  expect_equal(result@status, "continue")
  expect_equal(result@node_id, "b")
  expect_equal(result@transition_trace@selection_basis, "hint")
})

test_that("select_transition returns needs_llm when fallback needed", {
  engine <- make_test_engine()
  candidates <- list(
    TransitionCandidate(to = "a", eval_result = "error", fallback_to_llm = TRUE)
  )
  result <- select_transition(engine, candidates)
  expect_equal(result@status, "needs_llm")
})

test_that("select_transition uses llm_choice", {
  engine <- make_test_engine()
  candidates <- list(
    TransitionCandidate(to = "a", eval_result = "error", fallback_to_llm = TRUE),
    TransitionCandidate(
      to = "end", eval_result = "not_evaluated",
      fallback_to_llm = FALSE
    )
  )
  result <- select_transition(engine, candidates, llm_choice = "end")
  expect_equal(result@status, "continue")
  expect_equal(result@node_id, "end")
  expect_equal(result@transition_trace@selection_basis, "llm")
})

test_that("select_transition falls to otherwise when all false", {
  engine <- make_test_engine()
  candidates <- list(
    TransitionCandidate(to = "a", eval_result = "false", fallback_to_llm = FALSE),
    TransitionCandidate(
      to = "end",
      eval_result = "not_evaluated",
      fallback_to_llm = FALSE
    )
  )
  result <- select_transition(engine, candidates)
  expect_equal(result@status, "continue")
  expect_equal(result@node_id, "end")
  expect_equal(result@transition_trace@selection_basis, "rule")
})

# -- policy resolution --------------------------------------------------------

test_that("policy resolution: 3-layer - node overrides graph", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(max_iterations = 5L),
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  gp <- GlobalPolicy(max_iterations = 3L)
  engine <- make_test_engine(nodes = nodes, global_policy = gp)
  policy <- resolve_policy(engine, "start")
  expect_equal(policy$max_iterations, 5L)
})

test_that("policy resolution: graph when no node override", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  gp <- GlobalPolicy(max_iterations = 7L)
  engine <- make_test_engine(nodes = nodes, global_policy = gp)
  policy <- resolve_policy(engine, "start")
  expect_equal(policy$max_iterations, 7L)
})

# -- skip evaluation ----------------------------------------------------------

test_that("skip_hint TRUE causes skip", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(skip_when = "always skip", skip_hint = "TRUE"),
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  expect_true(evaluate_skip(engine, "start"))
})

test_that("skip_hint FALSE does not skip", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(skip_when = "never skip", skip_hint = "FALSE"),
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  expect_false(evaluate_skip(engine, "start"))
})

# -- iteration limit ----------------------------------------------------------

test_that("iteration limit respected within range", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(max_iterations = 3L),
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  expect_false(check_iteration_limit(engine, "start"))
})

test_that("iteration limit exceeded triggers error in advance", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(max_iterations = 1L),
      transitions = list(Transition(to = "start", always = TRUE))
    )
  )
  engine <- make_test_engine(nodes = nodes)
  expect_error(
    {
      advance(engine)
      advance(engine)
    },
    "max_iterations"
  )
})

# -- advance() ----------------------------------------------------------------

test_that("advance moves to next node", {
  engine <- make_test_engine()
  result <- advance(engine)
  expect_equal(result@status, "continue")
  expect_equal(result@node_id, "end")
  expect_equal(engine_visit_counts(engine)[["start"]], 1L)
  expect_equal(engine_current_node(engine), "end")
})

test_that("advance returns completed at terminal node", {
  engine <- make_test_engine()
  advance(engine)
  result <- advance(engine)
  expect_equal(result@status, "completed")
  expect_equal(result@node_id, "end")
})

test_that("advance returns skipped when skip_hint is TRUE", {
  nodes <- list(
    start = Node(
      type = "decision", topic = "t",
      policy = NodePolicy(skip_when = "skip always", skip_hint = "TRUE"),
      transitions = list(Transition(to = "end", always = TRUE))
    ),
    end = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes)
  result <- advance(engine)
  expect_equal(result@status, "skipped")
  expect_equal(result@node_id, "start")
  expect_equal(engine_current_node(engine), "end")
})

test_that("advance returns S7 AdvanceResult", {
  engine <- make_test_engine()
  result <- advance(engine)
  expect_true(S7::S7_inherits(result, AdvanceResult))
})

test_that("TransitionTrace from advance has correct structure", {
  engine <- make_test_engine()
  result <- advance(engine)
  expect_true(S7::S7_inherits(result@transition_trace, TransitionTrace))
  expect_true(S7::S7_inherits(
    result@transition_trace@candidates[[1]],
    TransitionCandidate
  ))
})

# -- single-node graph --------------------------------------------------------

test_that("single-node graph returns completed", {
  nodes <- list(
    only = Node(type = "execution", transitions = list())
  )
  engine <- make_test_engine(nodes = nodes, entry = "only")
  result <- advance(engine)
  expect_equal(result@status, "completed")
})
