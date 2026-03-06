#' Decision Logger S7 Class
#'
#' JSONL streaming audit log for every node visit during a bridle session,
#' conforming to `decision_log.schema.yaml` (ADR-0006).
#'
#' @name decision_logger
#' @importFrom rlang %||%
NULL

# -- DecisionLogger -----------------------------------------------------------

#' @title DecisionLogger
#' @description Manages a JSONL audit log file for one session. Each call to
#' [log_visit()] appends one JSON line. One session = one log file.
#' @param session_id Unique session identifier (character).
#' @param log_path Path to the JSONL log file (character).
#' @param turn_counter Current turn count (integer). Auto-incremented.
#' @param enabled Whether logging is active (logical).
#' @export
DecisionLogger <- S7::new_class("DecisionLogger",
  properties = list(
    session_id = S7::class_character,
    log_path = S7::class_character,
    turn_counter = S7::new_property(S7::class_integer, default = 0L),
    enabled = S7::new_property(S7::class_logical, default = TRUE)
  ),
  validator = function(self) {
    if (length(self@session_id) != 1L || nchar(self@session_id) == 0L) {
      return("`session_id` must be a non-empty single string")
    }
    if (length(self@log_path) != 1L || nchar(self@log_path) == 0L) {
      return("`log_path` must be a non-empty single string")
    }
    if (length(self@enabled) != 1L || is.na(self@enabled)) {
      return("`enabled` must be TRUE or FALSE")
    }
    NULL
  }
)

#' Log a node visit
#'
#' Appends one JSONL line to the log file. Increments turn_counter in place.
#'
#' @param logger A [DecisionLogger] object.
#' @param node_id Node identifier (character).
#' @param node_type Node type (character).
#' @param transition_trace Transition trace (list).
#' @param plugin_name Plugin name (character).
#' @param plugin_version Plugin version (character).
#' @param graph_version Graph version hash (character).
#' @param constraints_trace Optional constraint trace (list).
#' @param knowledge_context Optional knowledge context (list).
#' @param llm_output Optional LLM output (list).
#' @param user_response Optional user response (list).
#' @param decision_state Optional decision state (list).
#' @param policy_applied Optional policy info (list).
#' @return The updated [DecisionLogger] (invisibly), with incremented turn.
#' @export
log_visit <- function(logger,
                      node_id,
                      node_type,
                      transition_trace,
                      plugin_name = "unknown",
                      plugin_version = "0.0.0",
                      graph_version = "unknown",
                      constraints_trace = NULL,
                      knowledge_context = NULL,
                      llm_output = NULL,
                      user_response = NULL,
                      decision_state = NULL,
                      policy_applied = NULL) {
  if (!S7::S7_inherits(logger, DecisionLogger)) {
    cli::cli_abort("{.arg logger} must be a {.cls DecisionLogger}.")
  }
  if (!logger@enabled) {
    return(invisible(logger))
  }

  new_turn <- logger@turn_counter + 1L

  entry <- list(
    meta = list(
      session_id = logger@session_id,
      turn_id = new_turn,
      plugin_name = plugin_name,
      plugin_version = plugin_version,
      graph_version = graph_version,
      timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    node_id = node_id,
    node_type = node_type,
    transition_trace = transition_trace
  )

  if (!is.null(constraints_trace)) entry$constraints_trace <- constraints_trace
  if (!is.null(knowledge_context)) entry$knowledge_context <- knowledge_context
  if (!is.null(llm_output)) entry$llm_output <- llm_output
  if (!is.null(user_response)) entry$user_response <- user_response
  if (!is.null(decision_state)) entry$decision_state <- decision_state
  if (!is.null(policy_applied)) entry$policy_applied <- policy_applied

  json_line <- jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null")
  write(json_line, file = logger@log_path, append = TRUE)

  logger@turn_counter <- new_turn
  invisible(logger)
}

#' Analyze a decision log
#'
#' Reads a JSONL log file and computes summary statistics: override rate
#' by node, fallback rate, and session duration.
#'
#' @param path Path to a JSONL log file.
#' @return A list with `n_visits`, `override_rate_by_node`, `fallback_rate`,
#'   and `duration_s`.
#' @export
analyze_log <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort("Log file not found: {.path {path}}")
  }

  lines <- readLines(path, warn = FALSE)
  lines <- lines[nchar(trimws(lines)) > 0L]

  if (length(lines) == 0L) {
    return(list(
      n_visits = 0L,
      override_rate_by_node = list(),
      fallback_rate = 0,
      duration_s = 0
    ))
  }

  entries <- lapply(lines, function(ln) {
    tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
  })
  entries <- Filter(Negate(is.null), entries)

  n_visits <- length(entries)

  node_visits <- list()
  node_overrides <- list()
  fallback_count <- 0L
  timestamps <- character(0)

  for (e in entries) {
    nid <- e$node_id %||% "unknown"
    node_visits[[nid]] <- (node_visits[[nid]] %||% 0L) + 1L

    ur <- e$user_response
    if (!is.null(ur) && !is.null(ur$outcome)) {
      if (ur$outcome %in% c("rejected", "modified")) {
        node_overrides[[nid]] <- (node_overrides[[nid]] %||% 0L) + 1L
      }
    }

    tt <- e$transition_trace
    if (!is.null(tt) && !is.null(tt$selection_basis)) {
      if (tt$selection_basis == "llm") {
        fallback_count <- fallback_count + 1L
      }
    }

    ts <- e$meta$timestamp_utc
    if (!is.null(ts)) timestamps <- c(timestamps, ts)
  }

  override_rate <- list()
  for (nid in names(node_visits)) {
    overrides <- node_overrides[[nid]] %||% 0L
    override_rate[[nid]] <- overrides / node_visits[[nid]]
  }

  duration_s <- 0
  if (length(timestamps) >= 2L) {
    ts_parsed <- as.POSIXct(timestamps, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ts_valid <- ts_parsed[!is.na(ts_parsed)]
    if (length(ts_valid) >= 2L) {
      duration_s <- as.numeric(
        difftime(max(ts_valid), min(ts_valid), units = "secs")
      )
    }
  }

  list(
    n_visits = n_visits,
    override_rate_by_node = override_rate,
    fallback_rate = if (n_visits > 0L) fallback_count / n_visits else 0,
    duration_s = duration_s
  )
}
