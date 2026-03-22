#' Console REPL
#'
#' Readline-based CLI loop that drives the bridle agent through
#' the decision graph, presenting LLM recommendations and
#' collecting user responses (ADR-0002).
#'
#' @name console
#' @include bridle_agent.R
#' @include orchestrator.R
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
      .console_process_turn(agent, chat),
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

.console_process_turn <- function(agent, chat) {
  prep <- turn_prepare(agent) # nolint: object_usage_linter. orchestrator.R
  if (identical(prep$status, "completed")) {
    return(list(status = "completed"))
  }
  if (identical(prep$status, "skipped")) {
    cli::cli_alert_info("Skipped node {.val {prep$node_id}}")
    return(list(status = "continue"))
  }

  node <- prep$node
  node_id <- prep$node_id
  context <- agent$engine@context

  cli::cli_h2("Node: {node_id} ({node@type})")

  llm_response <- .call_llm(chat, prep$prompt_text)
  if (is.null(llm_response)) {
    return(list(status = "error"))
  }

  parsed <- parse_response( # nolint: object_usage_linter. response_parser.R
    llm_response,
    node,
    prep$transition_candidates
  )

  .display_response(parsed, node)

  if (identical(node@type, "execution") && !is.null(parsed@code_block)) {
    code_result <- .run_code(agent, parsed@code_block, context)
    if (!is.null(code_result) && code_result@success) {
      eng <- agent$engine
      eng@context <- update_context( # nolint: object_usage_linter. session_context.R
        eng@context,
        node_id = node_id,
        fit_result = code_result@value
      )
      agent$engine <- eng
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

  turn_resolve( # nolint: object_usage_linter. orchestrator.R
    agent,
    list(
      prepare = prep,
      parsed = parsed,
      user_action = user_action
    )
  )

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
