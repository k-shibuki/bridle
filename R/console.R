#' Console REPL
#'
#' Readline-based CLI loop that drives the bridle agent through
#' the decision graph, presenting LLM recommendations and
#' collecting user responses (ADR-0002).
#'
#' @name console
#' @include bridle_agent.R
NULL

#' Testable readline wrapper
#'
#' Wraps [base::readline()] so tests can inject a fixed input queue
#' via [testthat::local_mocked_bindings()].
#'
#' @param prompt Prompt string displayed to the user.
#' @return User input as a character string.
#' @export
bridle_readline <- function(prompt = "> ") {
  readline(prompt)
}

#' Run the interactive console
#'
#' Processes nodes by orchestrating: policy check, knowledge retrieval,
#' prompt assembly, LLM call, response parsing, user interaction,
#' transition selection, and decision logging.
#'
#' @param agent A `bridle_agent` object.
#' @return Invisible NULL. Called for side effects.
#' @export
bridle_console <- function(agent) {
  if (!inherits(agent, "bridle_agent")) {
    cli::cli_abort("{.arg agent} must be a {.cls bridle_agent}.")
  }

  chat <- .init_chat(agent)
  cli::cli_h1("bridle session started")
  cli::cli_text("Type {.kbd y} to accept, {.kbd n} to reject, {.kbd explain}, or {.kbd abort}")
  cli::cli_rule()

  repeat {
    result <- tryCatch(
      .process_turn(agent, chat),
      error = function(e) {
        cli::cli_alert_danger("Error: {conditionMessage(e)}")
        list(status = "error")
      }
    )

    if (identical(result$status, "completed")) {
      cli::cli_rule()
      cli::cli_alert_success("Session complete.")
      break
    }
    if (identical(result$status, "aborted")) {
      cli::cli_rule()
      cli::cli_alert_warning("Session aborted by user.")
      break
    }
  }

  invisible(NULL)
}

# -- Turn processing -----------------------------------------------------------

.process_turn <- function(agent, chat) {
  engine <- agent$engine
  advance_result <- advance(engine) # nolint: object_usage_linter. defined in R/graph_engine.R
  node_id <- engine_current_node(engine) # nolint: object_usage_linter. defined in R/graph_engine.R
  node <- agent$graph@nodes[[node_id]]

  if (identical(advance_result@status, "completed")) {
    return(list(status = "completed"))
  }

  if (identical(advance_result@status, "skipped")) {
    cli::cli_alert_info("Skipped node {.val {node_id}}")
    return(list(status = "continue"))
  }

  cli::cli_h2("Node: {node_id} ({node@type})")

  context <- engine@context
  retrieval <- .retrieve_for_node(agent, node, context)
  trace <- advance_result@transition_trace

  prompt_result <- assemble_runtime_prompt( # nolint: object_usage_linter. defined in R/prompt_assembler.R
    node = node,
    retrieval_result = retrieval,
    context = context,
    transition_trace = trace
  )

  llm_response <- .call_llm(chat, prompt_result@prompt_text)
  if (is.null(llm_response)) {
    return(list(status = "error"))
  }

  candidates <- if (!is.null(trace)) {
    vapply(trace@candidates, function(c) c@to, character(1))
  } else {
    character(0)
  }
  parsed <- parse_response(llm_response, node, candidates) # nolint: object_usage_linter. defined in R/response_parser.R

  .display_response(parsed, node)

  if (identical(node@type, "execution") && !is.null(parsed@code_block)) {
    code_result <- .run_code(agent, parsed@code_block, context)
    if (!is.null(code_result) && code_result@success) {
      engine@context <- update_context( # nolint: object_usage_linter. defined in R/session_context.R
        context,
        node_id = node_id,
        fit_result = code_result@value
      )
    }
  }

  user_action <- .get_user_action(parsed, node)

  if (identical(user_action$action, "abort")) {
    return(list(status = "aborted"))
  }

  if (identical(user_action$action, "explain")) {
    explain_prompt <- paste0(
      "Please explain your reasoning in more detail for: ",
      parsed@recommendation_text
    )
    explanation <- .call_llm(chat, explain_prompt)
    if (!is.null(explanation)) {
      cli::cli_rule()
      cli::cli_text(explanation)
      cli::cli_rule()
    }
    user_action <- .get_user_action(parsed, node)
    if (identical(user_action$action, "abort")) {
      return(list(status = "aborted"))
    }
  }

  param <- node@parameter
  has_param <- length(param) > 0L && nzchar(param)

  accept_with_param <- identical(user_action$action, "accept") &&
    !is.null(parsed@suggested_value) && has_param
  if (accept_with_param) {
    params <- list()
    params[[param]] <- parsed@suggested_value
    engine@context <- update_context( # nolint: object_usage_linter. cross-file ref
      engine@context,
      node_id = node_id,
      parameters = params
    )
  }

  reject_with_override <- identical(user_action$action, "reject") &&
    !is.null(user_action$override) && has_param
  if (reject_with_override) {
    params <- list()
    params[[param]] <- user_action$override
    engine@context <- update_context( # nolint: object_usage_linter. cross-file ref
      engine@context,
      node_id = node_id,
      parameters = params
    )
  }

  if (identical(advance_result@status, "needs_llm") && !is.null(trace)) {
    llm_choice <- parsed@transition_signal
    select_transition(engine, trace@candidates, llm_choice) # nolint: object_usage_linter. defined in R/graph_engine.R
  }

  .log_turn(agent, node_id, node, trace, retrieval, parsed, user_action)

  list(status = "continue")
}

# -- Component helpers ---------------------------------------------------------

.init_chat <- function(agent) {
  tryCatch(
    bridle_runtime_chat( # nolint: object_usage_linter. defined in R/llm_utils.R
      system_prompt = "You are a statistical analysis assistant.",
      provider = agent$provider,
      model = agent$model
    ),
    error = function(e) {
      cli::cli_alert_danger("Failed to initialize LLM chat session.")
      cli::cli_alert_info("Check credentials in {.file .Renviron}. See {.file .Renviron.example} for setup.")
      cli::cli_abort(conditionMessage(e), parent = e)
    }
  )
}

.retrieve_for_node <- function(agent, node, context) {
  topic <- node@topic
  if (length(topic) == 0L || !nzchar(topic)) {
    return(RetrievalResult( # nolint: object_usage_linter. S7 class in R/knowledge_retriever.R
      entries = list(),
      entry_ids_presented = character(0),
      constraints = list()
    ))
  }
  retrieval <- retrieve_knowledge( # nolint: object_usage_linter. cross-file ref
    agent$knowledge, topic, context
  )
  param <- node@parameter
  if (length(param) > 0L && nzchar(param)) {
    extra_constraints <- retrieve_constraints( # nolint: object_usage_linter. defined in R/constraint_set.R
      agent$constraints, param, context
    )
    retrieval@constraints <- c(retrieval@constraints, extra_constraints)
  }
  retrieval
}

.call_llm <- function(chat, prompt_text) {
  tryCatch(
    chat$chat(prompt_text),
    error = function(e) {
      cli::cli_alert_danger("LLM call failed: {conditionMessage(e)}")
      cli::cli_alert_info("You can retry or type {.kbd abort} to end session.")
      NULL
    }
  )
}

.run_code <- function(agent, code, context) {
  cli::cli_alert_info("Executing code...")
  result <- bridle_eval_code( # nolint: object_usage_linter. defined in R/code_sandbox.R
    code,
    agent$sandbox,
    data = context@data,
    parameters = context@parameters_decided
  )
  if (result@success) {
    if (nzchar(result@output)) cli::cli_text(result@output)
    cli::cli_alert_success("Code executed successfully ({result@elapsed_s}s)")
  } else {
    cli::cli_alert_danger("Code execution failed: {result@error}")
  }
  if (length(result@warnings) > 0L) {
    for (w in result@warnings) cli::cli_alert_warning(w)
  }
  result
}

# -- User interaction ----------------------------------------------------------

.display_response <- function(parsed, node) {
  cli::cli_rule()
  cli::cli_text(parsed@recommendation_text)
  if (!is.null(parsed@suggested_value)) {
    cli::cli_alert_info("Suggested value: {.val {parsed@suggested_value}}")
  }
  if (!is.null(parsed@code_block) && identical(node@type, "execution")) {
    cli::cli_rule("Generated code")
    cli::cli_code(parsed@code_block)
  }
  cli::cli_rule()
}

.get_user_action <- function(parsed, node) {
  input <- trimws(tolower(bridle_readline("[y/n/explain/abort] > ")))

  if (input %in% c("abort", "q", "quit")) {
    return(list(action = "abort"))
  }
  if (input == "explain") {
    return(list(action = "explain"))
  }
  if (input %in% c("n", "no")) {
    override <- NULL
    param <- node@parameter
    if (length(param) > 0L && nzchar(param)) {
      override <- bridle_readline("Enter override value: ")
      if (!nzchar(trimws(override))) override <- NULL
    }
    return(list(action = "reject", override = override))
  }
  list(action = "accept")
}

# -- Logging -------------------------------------------------------------------

.log_turn <- function(agent, node_id, node, trace, retrieval, parsed,
                      user_action) {
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

  log_visit( # nolint: object_usage_linter. defined in R/decision_logger.R
    agent$logger,
    node_id = node_id,
    node_type = node@type,
    transition_trace = trace_list,
    knowledge_context = knowledge_ctx,
    llm_output = llm_out,
    user_response = user_resp
  )
}
