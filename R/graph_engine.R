#' Graph Engine S7 Classes
#'
#' Runtime graph traversal engine for decision graph navigation.
#' Evaluates transitions, resolves policies, and produces audit-ready
#' trace structures (ADR-0002, ADR-0003, ADR-0005, ADR-0006).
#'
#' @name graph_engine
#' @include decision_graph.R
#' @include hint_evaluator.R
#' @include session_context.R
#' @importFrom rlang %||%
NULL

# -- TransitionCandidate ------------------------------------------------------

.valid_eval_results <- c("true", "false", "error", "not_evaluated")

#' @title TransitionCandidate
#' @description Evaluation result for a single transition edge.
#' @param to Target node ID (character).
#' @param when Natural-language condition text (character or NULL).
#' @param computable_hint R expression hint (character or NULL).
#' @param eval_result Evaluation outcome (character).
#' @param fallback_to_llm Whether LLM judgment is needed (logical).
#' @export
TransitionCandidate <- S7::new_class("TransitionCandidate",
  properties = list(
    to = S7::class_character,
    when = S7::new_property(S7::class_character, default = character(0)),
    computable_hint = S7::new_property(S7::class_character, default = character(0)),
    eval_result = S7::class_character,
    fallback_to_llm = S7::class_logical
  ),
  validator = function(self) {
    if (length(self@to) != 1L || nchar(self@to) == 0L) {
      return("`to` must be a non-empty single string")
    }
    valid_er <- length(self@eval_result) == 1L &&
      self@eval_result %in% .valid_eval_results
    if (!valid_er) {
      return(sprintf(
        "`eval_result` must be one of: %s",
        paste(.valid_eval_results, collapse = ", ")
      ))
    }
    if (length(self@fallback_to_llm) != 1L || is.na(self@fallback_to_llm)) {
      return("`fallback_to_llm` must be TRUE or FALSE")
    }
    NULL
  }
)

# -- TransitionTrace ----------------------------------------------------------

.valid_selection_basis <- c("hint", "llm", "user", "rule")

#' @title TransitionTrace
#' @description Audit trace for transition evaluation at a node.
#' @param candidates List of [TransitionCandidate] objects.
#' @param selected_transition Target node ID that was selected (character).
#' @param selection_basis How the selection was made (character).
#' @export
TransitionTrace <- S7::new_class("TransitionTrace",
  properties = list(
    candidates = S7::class_list,
    selected_transition = S7::class_character,
    selection_basis = S7::class_character
  ),
  validator = function(self) {
    for (i in seq_along(self@candidates)) {
      if (!S7::S7_inherits(self@candidates[[i]], TransitionCandidate)) {
        return(sprintf("candidates[[%d]] must be a TransitionCandidate", i))
      }
    }
    if (length(self@selected_transition) != 1L) {
      return("`selected_transition` must be a single string")
    }
    valid_sb <- length(self@selection_basis) == 1L &&
      self@selection_basis %in% .valid_selection_basis
    if (!valid_sb) {
      return(sprintf(
        "`selection_basis` must be one of: %s",
        paste(.valid_selection_basis, collapse = ", ")
      ))
    }
    NULL
  }
)

# -- AdvanceResult ------------------------------------------------------------

.valid_advance_status <- c("continue", "needs_llm", "skipped", "completed")

#' @title AdvanceResult
#' @description Result of a single graph engine step.
#' @param status Step outcome (character).
#' @param node_id Current node ID (character).
#' @param transition_trace Audit trace (TransitionTrace or NULL).
#' @export
AdvanceResult <- S7::new_class("AdvanceResult",
  properties = list(
    status = S7::class_character,
    node_id = S7::class_character,
    transition_trace = S7::new_property(
      class = S7::class_any,
      default = NULL
    )
  ),
  validator = function(self) {
    valid_st <- length(self@status) == 1L &&
      self@status %in% .valid_advance_status
    if (!valid_st) {
      return(sprintf(
        "`status` must be one of: %s",
        paste(.valid_advance_status, collapse = ", ")
      ))
    }
    if (length(self@node_id) != 1L) {
      return("`node_id` must be a single string")
    }
    has_tt <- !is.null(self@transition_trace)
    if (has_tt && !S7::S7_inherits(self@transition_trace, TransitionTrace)) {
      return("`transition_trace` must be a TransitionTrace or NULL")
    }
    NULL
  }
)

# -- GraphEngine --------------------------------------------------------------

#' @title GraphEngine
#' @description Runtime engine for decision graph traversal. Uses an
#' internal environment for mutable state (current_node, visit_counts)
#' so that `advance()` mutations are visible to callers.
#' @param graph A [DecisionGraph] object.
#' @param context A [SessionContext] object.
#' @param .state Internal mutable state environment (do not set directly).
#' @export
GraphEngine <- S7::new_class("GraphEngine",
  properties = list(
    graph = DecisionGraph,
    context = SessionContext,
    .state = S7::class_environment
  ),
  validator = function(self) {
    cn <- self@.state$current_node
    if (is.null(cn) || length(cn) != 1L || nchar(cn) == 0L) {
      return("`.state$current_node` must be a non-empty single string")
    }
    if (!cn %in% names(self@graph@nodes)) {
      return(sprintf(
        "`current_node` '%s' not found in graph nodes", cn
      ))
    }
    NULL
  }
)

#' Create a GraphEngine from graph and context
#'
#' @param graph A [DecisionGraph] object.
#' @param context A [SessionContext] object.
#' @return A [GraphEngine] positioned at the entry node.
#' @export
make_graph_engine <- function(graph, context) {
  state <- new.env(parent = emptyenv())
  state$current_node <- graph@entry_node
  state$visit_counts <- integer(0)
  GraphEngine(graph = graph, context = context, .state = state)
}

#' Get the current node ID from a GraphEngine
#' @param engine A [GraphEngine] object.
#' @return Character string of the current node ID.
#' @export
engine_current_node <- function(engine) {
  engine@.state$current_node
}

#' Get visit counts from a GraphEngine
#' @param engine A [GraphEngine] object.
#' @return Named integer vector of visit counts.
#' @export
engine_visit_counts <- function(engine) {
  engine@.state$visit_counts
}

# -- Policy Resolution (ADR-0005) --------------------------------------------

#' Resolve effective policy for a node (3-layer: manifest < graph < node)
#'
#' @param engine A [GraphEngine] object.
#' @param node_id Node ID (character).
#' @return A list with resolved policy fields.
#' @export
resolve_policy <- function(engine, node_id) {
  if (!S7::S7_inherits(engine, GraphEngine)) {
    cli::cli_abort("{.arg engine} must be a {.cls GraphEngine}.")
  }
  node <- engine@graph@nodes[[node_id]]
  gp <- engine@graph@global_policy

  max_iter <- 10L
  if (!is.na(gp@max_iterations)) max_iter <- gp@max_iterations
  np <- node@policy
  if (!is.na(np@max_iterations)) max_iter <- np@max_iterations

  list(
    # nolint next: object_usage_linter. has_value defined in decision_graph.R
    skip_when = if (has_value(np@skip_when)) np@skip_when else NULL,
    # nolint next: object_usage_linter. has_value defined in decision_graph.R
    skip_hint = if (has_value(np@skip_hint)) np@skip_hint else NULL,
    max_iterations = max_iter
  )
}

# -- Skip Evaluation ----------------------------------------------------------

#' Evaluate whether a node should be skipped
#'
#' @param engine A [GraphEngine] object.
#' @param node_id Node ID (character).
#' @return Logical: `TRUE` if the node should be skipped.
#' @export
evaluate_skip <- function(engine, node_id) {
  policy <- resolve_policy(engine, node_id)
  if (is.null(policy$skip_hint)) {
    return(FALSE)
  }
  # nolint next: object_usage_linter. get_hint_variables in session_context.R
  vars <- get_hint_variables(engine@context)
  # nolint next: object_usage_linter. evaluate_hint in hint_evaluator.R
  result <- evaluate_hint(policy$skip_hint, variables = vars)
  isTRUE(result)
}

# -- Transition Evaluation ----------------------------------------------------

#' Evaluate all transition candidates for a node
#'
#' @param engine A [GraphEngine] object.
#' @param node_id Node ID (character).
#' @return A list of [TransitionCandidate] objects.
#' @export
evaluate_transitions <- function(engine, node_id) {
  if (!S7::S7_inherits(engine, GraphEngine)) {
    cli::cli_abort("{.arg engine} must be a {.cls GraphEngine}.")
  }
  node <- engine@graph@nodes[[node_id]]
  # nolint next: object_usage_linter. get_hint_variables in session_context.R
  vars <- get_hint_variables(engine@context)
  # nolint next: object_usage_linter. has_value in decision_graph.R
  opt_when <- function(tr) if (has_value(tr@when)) tr@when else character(0)

  lapply(node@transitions, function(tr) {
    if (isTRUE(tr@always)) {
      return(TransitionCandidate(
        to = tr@to, when = opt_when(tr),
        computable_hint = character(0),
        eval_result = "true", fallback_to_llm = FALSE
      ))
    }

    if (isTRUE(tr@otherwise)) {
      return(TransitionCandidate(
        to = tr@to, when = character(0),
        computable_hint = character(0),
        eval_result = "not_evaluated", fallback_to_llm = FALSE
      ))
    }

    has_hint <- has_value(tr@computable_hint) # nolint: object_usage_linter. defined in R/decision_graph.R
    hint_expr <- if (has_hint) tr@computable_hint else NULL

    if (is.null(hint_expr)) {
      return(TransitionCandidate(
        to = tr@to, when = opt_when(tr),
        computable_hint = character(0),
        eval_result = "not_evaluated", fallback_to_llm = TRUE
      ))
    }

    hint_result <- suppressWarnings(
      evaluate_hint(hint_expr, variables = vars) # nolint: object_usage_linter. defined in R/hint_evaluator.R
    )

    if (is.na(hint_result)) {
      return(TransitionCandidate(
        to = tr@to, when = opt_when(tr),
        computable_hint = hint_expr,
        eval_result = "error", fallback_to_llm = TRUE
      ))
    }

    TransitionCandidate(
      to = tr@to, when = opt_when(tr),
      computable_hint = hint_expr,
      eval_result = if (isTRUE(hint_result)) "true" else "false",
      fallback_to_llm = FALSE
    )
  })
}

# -- Transition Selection -----------------------------------------------------

#' Select the next transition from evaluated candidates
#'
#' @param engine A [GraphEngine] object.
#' @param candidates List of [TransitionCandidate] objects.
#' @param llm_choice Optional LLM-selected node ID (character).
#' @return An [AdvanceResult] object.
#' @export
select_transition <- function(engine, candidates, llm_choice = NULL) {
  if (!S7::S7_inherits(engine, GraphEngine)) {
    cli::cli_abort("{.arg engine} must be a {.cls GraphEngine}.")
  }

  if (!is.null(llm_choice)) {
    for (c in candidates) {
      if (c@to == llm_choice) {
        trace <- TransitionTrace(
          candidates = candidates,
          selected_transition = llm_choice,
          selection_basis = "llm"
        )
        return(AdvanceResult(
          status = "continue",
          node_id = llm_choice,
          transition_trace = trace
        ))
      }
    }
  }

  for (c in candidates) {
    if (c@eval_result == "true") {
      trace <- TransitionTrace(
        candidates = candidates,
        selected_transition = c@to,
        selection_basis = "hint"
      )
      return(AdvanceResult(
        status = "continue",
        node_id = c@to,
        transition_trace = trace
      ))
    }
  }

  needs_llm <- any(vapply(candidates, function(c) c@fallback_to_llm, logical(1)))
  if (needs_llm) {
    trace <- TransitionTrace(
      candidates = candidates,
      selected_transition = "",
      selection_basis = "llm"
    )
    return(AdvanceResult(
      status = "needs_llm",
      node_id = engine@.state$current_node,
      transition_trace = trace
    ))
  }

  otherwise <- Filter(
    function(c) {
      c@eval_result == "not_evaluated" && !c@fallback_to_llm
    },
    candidates
  )
  if (length(otherwise) > 0L) {
    target <- otherwise[[1]]@to
    trace <- TransitionTrace(
      candidates = candidates,
      selected_transition = target,
      selection_basis = "rule"
    )
    return(AdvanceResult(
      status = "continue",
      node_id = target,
      transition_trace = trace
    ))
  }

  AdvanceResult(
    status = "completed",
    node_id = engine@.state$current_node,
    transition_trace = NULL
  )
}

# -- Iteration Limit ----------------------------------------------------------

#' Check if a node has exceeded its iteration limit
#'
#' @param engine A [GraphEngine] object.
#' @param node_id Node ID (character).
#' @return Logical: `TRUE` if the limit is exceeded.
#' @export
check_iteration_limit <- function(engine, node_id) {
  policy <- resolve_policy(engine, node_id)
  vc <- engine@.state$visit_counts
  current <- if (node_id %in% names(vc)) vc[[node_id]] else 0L
  current >= policy$max_iterations
}

# -- Advance (main step) -----------------------------------------------------

#' Advance the graph engine one step
#'
#' Performs: policy resolution -> skip evaluation -> transition evaluation
#' -> selection -> visit count update. Returns an [AdvanceResult].
#'
#' @param engine A [GraphEngine] object.
#' @return An [AdvanceResult] object.
#' @export
advance <- function(engine) {
  if (!S7::S7_inherits(engine, GraphEngine)) {
    cli::cli_abort("{.arg engine} must be a {.cls GraphEngine}.")
  }

  node_id <- engine@.state$current_node
  node <- engine@graph@nodes[[node_id]]

  vc <- engine@.state$visit_counts
  cur <- if (node_id %in% names(vc)) vc[[node_id]] else 0L
  vc[[node_id]] <- cur + 1L
  engine@.state$visit_counts <- vc

  if (check_iteration_limit(engine, node_id)) {
    cli::cli_abort(
      "Node {.val {node_id}} exceeded max_iterations ({resolve_policy(engine, node_id)$max_iterations})."
    )
  }

  if (evaluate_skip(engine, node_id)) {
    transitions <- node@transitions
    if (length(transitions) > 0L) {
      target <- transitions[[1]]@to
      engine@.state$current_node <- target
      return(AdvanceResult(
        status = "skipped",
        node_id = node_id,
        transition_trace = NULL
      ))
    }
    return(AdvanceResult(status = "completed", node_id = node_id))
  }

  if (length(node@transitions) == 0L) {
    return(AdvanceResult(status = "completed", node_id = node_id))
  }

  candidates <- evaluate_transitions(engine, node_id)
  result <- select_transition(engine, candidates)

  if (result@status == "continue") {
    engine@.state$current_node <- result@node_id
  }

  result
}
