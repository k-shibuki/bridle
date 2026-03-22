#' Core orchestration layer
#'
#' Per-turn prepare/resolve pipeline shared by the REPL and future interfaces
#' (ADR-0011, GitHub #244). Does not call the LLM or read user input.
#'
#' @name orchestrator
#' @include bridle_agent.R
#' @importFrom rlang %||%
NULL

# -- Public API ----------------------------------------------------------------

#' Prepare a graph turn through prompt assembly
#'
#' Calls [advance()], retrieves knowledge, and runs [assemble_runtime_prompt()].
#' Does not invoke the LLM.
#'
#' @param agent A `bridle_agent` object.
#' @return A named `list` with `status` one of `"completed"`, `"skipped"`, or
#'   `"continue"`. For `"continue"`, includes `node_id`, `node`,
#'   `advance_result`, `retrieval`, `prompt_result`, `prompt_text`,
#'   `node_type`, and `transition_candidates`.
#' @export
turn_prepare <- function(agent) {
  if (!inherits(agent, "bridle_agent")) {
    cli::cli_abort("{.arg agent} must be a {.cls bridle_agent}.")
  }

  engine <- agent$engine
  advance_result <- advance(engine) # nolint: object_usage_linter. graph_engine.R
  node_id <- engine_current_node(engine) # nolint: object_usage_linter. graph_engine.R
  node <- agent$graph@nodes[[node_id]]

  if (identical(advance_result@status, "completed")) {
    return(list(status = "completed"))
  }
  if (identical(advance_result@status, "skipped")) {
    return(list(
      status = "skipped",
      node_id = advance_result@node_id,
      advance_result = advance_result
    ))
  }

  context <- engine@context
  retrieval <- .orch_agent_retrieve(agent, node, context)
  trace <- advance_result@transition_trace

  prompt_result <- assemble_runtime_prompt( # nolint: object_usage_linter. prompt_assembler.R
    node = node,
    retrieval_result = retrieval,
    context = context,
    transition_trace = trace
  )

  transition_candidates <- if (!is.null(trace)) {
    vapply(trace@candidates, function(c) c@to, character(1))
  } else {
    character(0)
  }

  list(
    status = "continue",
    node_id = node_id,
    node = node,
    advance_result = advance_result,
    retrieval = retrieval,
    prompt_result = prompt_result,
    prompt_text = prompt_result@prompt_text,
    node_type = prompt_result@node_type,
    transition_candidates = transition_candidates
  )
}

#' Apply resolution after LLM output and user choice
#'
#' Updates session context (parameters), applies LLM-selected transitions when
#' needed, and writes the decision log entry.
#'
#' Code execution nodes update `fit_result` in the REPL **before** this call;
#' `parameter_value` does not carry sandbox results.
#'
#' @param agent A `bridle_agent` object.
#' @param parameter_value A named `list` with `prepare` (from `turn_prepare()`),
#'   `parsed` ([ParsedResponse]), and `user_action` (`list(action, override)`).
#' @param transition_choice Optional override for `parsed@transition_signal`.
#' @return A named `list` with `status` `"continue"`.
#' @export
turn_resolve <- function(agent, parameter_value, transition_choice = NULL) {
  if (!inherits(agent, "bridle_agent")) {
    cli::cli_abort("{.arg agent} must be a {.cls bridle_agent}.")
  }
  if (!is.list(parameter_value) || is.null(parameter_value$prepare)) {
    cli::cli_abort("{.arg parameter_value} must be a list containing {.field prepare}.")
  }
  prepare <- parameter_value$prepare
  parsed <- parameter_value$parsed
  user_action <- parameter_value$user_action
  if (is.null(parsed) || is.null(user_action)) {
    cli::cli_abort(
      "{.arg parameter_value} must contain {.field parsed} and {.field user_action}."
    )
  }

  node_id <- prepare$node_id
  node <- prepare$node
  advance_result <- prepare$advance_result
  retrieval <- prepare$retrieval
  trace <- advance_result@transition_trace

  llm_choice <- transition_choice %||% parsed@transition_signal

  param <- node@parameter
  has_param <- length(param) > 0L && nzchar(param)

  accept_with_param <- identical(user_action$action, "accept") &&
    !is.null(parsed@suggested_value) && has_param
  if (accept_with_param) {
    params <- list()
    params[[param]] <- parsed@suggested_value
    eng <- agent$engine
    eng@context <- update_context( # nolint: object_usage_linter. session_context.R
      eng@context,
      node_id = node_id,
      parameters = params
    )
    agent$engine <- eng
  }

  reject_with_override <- identical(user_action$action, "reject") &&
    !is.null(user_action$override) && has_param
  if (reject_with_override) {
    params <- list()
    params[[param]] <- user_action$override
    eng <- agent$engine
    eng@context <- update_context( # nolint: object_usage_linter. session_context.R
      eng@context,
      node_id = node_id,
      parameters = params
    )
    agent$engine <- eng
  }

  if (identical(advance_result@status, "needs_llm") && !is.null(trace)) {
    eng <- agent$engine
    st <- select_transition(eng, trace@candidates, llm_choice) # nolint: object_usage_linter. graph_engine.R
    if (identical(st@status, "continue")) {
      eng@.state$current_node <- st@node_id
    }
    agent$engine <- eng
  }

  .orch_log_turn(
    agent, node_id, node, trace, retrieval, parsed, user_action
  )

  list(status = "continue")
}

#' Aggregate plugin knowledge for free-mode prompts
#'
#' Compiles all knowledge stores, constraints, a graph summary, and the
#' context variable schema into one string for LLM system prompts.
#'
#' @param agent A `bridle_agent` object.
#' @return A single character string.
#' @export
aggregate_knowledge <- function(agent) {
  if (!inherits(agent, "bridle_agent")) {
    cli::cli_abort("{.arg agent} must be a {.cls bridle_agent}.")
  }

  parts <- c(
    .fmt_knowledge_agg(agent$knowledge),
    .fmt_constraints_agg(agent$constraints),
    .fmt_graph_agg(agent$graph),
    .fmt_schema_agg(agent$engine@context@schema)
  )
  paste(parts[nzchar(parts)], collapse = "\n\n")
}

# -- Retrieval (shared with REPL) ---------------------------------------------

.orch_agent_retrieve <- function(agent, node, context) {
  topic <- node@topic
  if (length(topic) == 0L || !nzchar(topic)) {
    return(RetrievalResult( # nolint: object_usage_linter. knowledge_retriever.R
      entries = list(),
      entry_ids_presented = character(0),
      constraints = list()
    ))
  }
  retrieval <- retrieve_knowledge( # nolint: object_usage_linter. knowledge_retriever.R
    agent$knowledge, topic, context
  )
  param <- node@parameter
  if (length(param) > 0L && nzchar(param)) {
    extra_constraints <- retrieve_constraints( # nolint: object_usage_linter. knowledge_retriever.R
      agent$constraints, param, context
    )
    retrieval@constraints <- c(retrieval@constraints, extra_constraints)
  }
  retrieval
}

# -- Logging -------------------------------------------------------------------

.orch_log_turn <- function(agent, node_id, node, trace, retrieval,
                           parsed, user_action) {
  if (is.null(agent$logger)) {
    return(invisible(NULL))
  }

  trace_list <- if (!is.null(trace)) {
    list(
      candidates = lapply(trace@candidates, function(c) {
        list(
          to = c@to,
          when = if (length(c@when) > 0L) c@when else NULL,
          eval_result = c@eval_result,
          fallback_to_llm = c@fallback_to_llm
        )
      }),
      selected_transition = trace@selected_transition,
      selection_basis = trace@selection_basis
    )
  } else {
    NULL
  }

  knowledge_ctx <- list(
    entry_ids_presented = retrieval@entry_ids_presented
  )

  llm_out <- list(
    recommendation_text = parsed@recommendation_text,
    suggested_value = parsed@suggested_value
  )

  user_resp <- list(
    action = user_action$action,
    override = user_action$override %||% NULL
  )

  log_visit( # nolint: object_usage_linter. decision_logger.R
    agent$logger,
    node_id = node_id,
    node_type = node@type,
    transition_trace = trace_list,
    knowledge_context = knowledge_ctx,
    llm_output = llm_out,
    user_response = user_resp
  )
}

# -- aggregate_knowledge formatters --------------------------------------------

.fmt_knowledge_agg <- function(stores) {
  if (length(stores) == 0L) {
    return("")
  }
  blocks <- vapply(stores, function(store) {
    if (!S7::S7_inherits(store, KnowledgeStore)) { # nolint: object_usage_linter. knowledge.R
      return("")
    }
    hdr <- sprintf(
      "## Topic: %s (%s::%s)",
      store@topic, store@package, store@func
    )
    tp <- paste(store@target_parameter, collapse = ", ")
    hdr2 <- sprintf("Target parameters: %s", tp)
    ent_lines <- vapply(store@entries, function(ent) {
      props <- paste0("  - ", ent@properties, collapse = "\n")
      sprintf(
        "### %s\nWhen: %s\n%s",
        ent@id,
        ent@when,
        props
      )
    }, character(1))
    paste(c(hdr, hdr2, ent_lines), collapse = "\n")
  }, character(1))
  paste(c("# Knowledge", blocks), collapse = "\n\n")
}

.fmt_constraints_agg <- function(sets) {
  if (length(sets) == 0L) {
    return("")
  }
  blocks <- vapply(sets, function(cs) {
    if (!S7::S7_inherits(cs, ConstraintSet)) { # nolint: object_usage_linter. constraints.R
      return("")
    }
    hdr <- sprintf("## Constraints: %s::%s", cs@package, cs@func)
    lines <- vapply(cs@constraints, function(ct) {
      msg <- ct@message
      msg_txt <- if (length(msg) > 0L && nzchar(msg)) msg else "(no message)"
      sprintf(
        "- [%s] %s (%s): %s",
        ct@id, ct@type, ct@source, msg_txt
      )
    }, character(1))
    paste(c(hdr, lines), collapse = "\n")
  }, character(1))
  paste(c("# Technical constraints", blocks), collapse = "\n\n")
}

.fmt_graph_agg <- function(graph) {
  lines <- character(length(graph@nodes))
  for (i in seq_along(graph@nodes)) {
    nm <- names(graph@nodes)[[i]]
    nd <- graph@nodes[[i]]
    tp <- if (length(nd@topic) > 0L) nd@topic else ""
    pr <- if (length(nd@parameter) > 0L) nd@parameter else ""
    lines[[i]] <- sprintf(
      "- %s: type=%s topic=%s parameter=%s",
      nm, nd@type, tp, pr
    )
  }
  paste(
    c(
      "# Decision graph",
      sprintf("Entry: %s", graph@entry_node),
      lines
    ),
    collapse = "\n"
  )
}

.fmt_schema_agg <- function(schema) {
  if (is.null(schema) || length(schema@variables) == 0L) {
    return("")
  }
  var_lines <- vapply(schema@variables, function(v) {
    sprintf(
      "- %s (%s): %s",
      v@name, v@available_from, v@description
    )
  }, character(1))
  paste(c("# Context variables", var_lines), collapse = "\n")
}
