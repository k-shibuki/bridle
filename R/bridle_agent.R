#' Bridle Agent
#'
#' Creates a runtime agent that orchestrates all Phase 2 components:
#' graph traversal, knowledge retrieval, prompt assembly, LLM chat,
#' response parsing, code execution, and decision logging.
#'
#' @name bridle_agent
#' @include prompt_assembler.R response_parser.R code_sandbox.R
#' @include decision_logger.R
NULL

#' Create a bridle agent
#'
#' Initializes all runtime components from a plugin directory
#' containing YAML configuration files.
#'
#' @param plugin_dir Path to plugin directory containing YAML files
#'   (`decision_graph.yaml`, `knowledge.yaml`, `constraints.yaml`,
#'   `context_schema.yaml`).
#' @param provider LLM provider name (character or NULL for auto-detect).
#'   See [bridle_runtime_chat()] for resolution order.
#' @param model LLM model name (character or NULL for provider default).
#' @param log_dir Directory for JSONL decision logs (character or NULL
#'   to disable logging).
#' @param sandbox_timeout Timeout in seconds for code execution (numeric).
#' @return A list with class `"bridle_agent"` containing graph, knowledge,
#'   constraints, logger, sandbox, provider, model, and a `console()` method.
#'   The graph engine is accessed with `$engine` (stored in an internal
#'   `.runtime` environment so mutations from helper functions update the same
#'   runtime instance).
#' @export
bridle_agent <- function(plugin_dir,
                         provider = NULL,
                         model = NULL,
                         log_dir = NULL,
                         sandbox_timeout = 10) {
  if (!dir.exists(plugin_dir)) {
    cli::cli_abort("Plugin directory {.path {plugin_dir}} does not exist.")
  }

  graph_path <- file.path(plugin_dir, "decision_graph.yaml")
  if (!file.exists(graph_path)) {
    cli::cli_abort("Missing {.file decision_graph.yaml} in {.path {plugin_dir}}.")
  }
  graph <- build_graph(graph_path) # nolint: object_usage_linter. defined in R/decision_graph.R

  manifest <- .load_manifest(plugin_dir)
  if (!is.null(manifest)) {
    graph <- .merge_manifest_policy(graph, manifest)
  }

  knowledge <- .load_yaml_list(
    plugin_dir, "knowledge.yaml", read_knowledge # nolint: object_usage_linter. cross-file ref
  )
  constraints <- .load_yaml_list(
    plugin_dir, "constraints.yaml", read_constraints # nolint: object_usage_linter. cross-file ref
  )
  context_schema <- .load_optional(
    plugin_dir, "context_schema.yaml", read_context_schema # nolint: object_usage_linter. defined in R/context_schema.R
  )

  validation <- validate_plugin( # nolint: object_usage_linter. cross-file ref
    graph, knowledge, constraints, context_schema
  )
  if (length(validation@errors) > 0L) {
    cli::cli_abort(c(
      "Plugin validation failed:",
      stats::setNames(validation@errors, rep("x", length(validation@errors)))
    ))
  }

  schema <- context_schema %||%
    ContextSchema(variables = list()) # nolint: object_usage_linter. S7 cross-file
  context <- SessionContext(schema = schema) # nolint: object_usage_linter. S7 class in R/session_context.R
  engine <- make_graph_engine(graph, context) # nolint: object_usage_linter. defined in R/graph_engine.R

  logger <- NULL
  if (!is.null(log_dir)) {
    if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
    session_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
    log_path <- file.path(log_dir, paste0("session_", session_id, ".jsonl"))
    logger <- DecisionLogger( # nolint: object_usage_linter. S7 cross-file
      session_id = session_id, log_path = log_path
    )
  }

  sandbox <- CodeSandbox(timeout_s = sandbox_timeout) # nolint: object_usage_linter. S7 class in R/code_sandbox.R

  runtime <- new.env(parent = emptyenv(), hash = FALSE)
  runtime[["engine"]] <- engine

  agent <- list(
    graph = graph,
    knowledge = knowledge,
    constraints = constraints,
    .runtime = runtime,
    logger = logger,
    sandbox = sandbox,
    provider = provider,
    model = model,
    console = function() bridle_console(agent) # nolint: object_usage_linter. defined in R/console.R
  )
  class(agent) <- "bridle_agent"
  agent
}

#' @keywords internal
#' @export
`$.bridle_agent` <- function(x, name) {
  if (identical(name, "engine")) {
    return(.subset2(x, ".runtime")[["engine"]])
  }
  NextMethod("$", x)
}

#' @keywords internal
#' @export
`$<-.bridle_agent` <- function(x, name, value) {
  if (identical(name, "engine")) {
    rt <- .subset2(x, ".runtime")
    rt[["engine"]] <- value
    return(x)
  }
  NextMethod("$<-", x)
}

.load_yaml_list <- function(dir, filename, reader) {
  path <- file.path(dir, filename)
  if (file.exists(path)) {
    return(list(reader(path)))
  }
  subdir <- tools::file_path_sans_ext(filename)
  dir_path <- file.path(dir, subdir)
  if (dir.exists(dir_path)) {
    files <- sort(list.files(dir_path, pattern = "\\.ya?ml$", full.names = TRUE))
    return(lapply(files, reader))
  }
  list()
}

.load_optional <- function(dir, filename, reader) {
  path <- file.path(dir, filename)
  if (file.exists(path)) reader(path) else NULL
}

#' Load manifest.yaml from plugin directory
#' @keywords internal
.load_manifest <- function(plugin_dir) {
  path <- file.path(plugin_dir, "manifest.yaml")
  if (!file.exists(path)) {
    return(NULL)
  }
  tryCatch(
    yaml::yaml.load_file(path),
    error = function(e) {
      cli::cli_warn(
        "Failed to load {.file manifest.yaml}: {conditionMessage(e)}"
      )
      NULL
    }
  )
}

#' Merge manifest policy_defaults into graph's GlobalPolicy
#'
#' Manifest values are overridden by graph-level GlobalPolicy values
#' (the 3-layer chain: manifest < graph < node per ADR-0005).
#' @keywords internal
.merge_manifest_policy <- function(graph, manifest) {
  pd <- manifest[["policy_defaults"]]
  if (is.null(pd)) {
    return(graph)
  }

  gp <- graph@global_policy
  manifest_max <- pd[["max_iterations"]]

  if (!is.null(manifest_max)) {
    manifest_max <- tryCatch(
      as.integer(manifest_max),
      warning = function(w) {
        cli::cli_warn(
          "Invalid {.field policy_defaults.max_iterations} in manifest.yaml: {.val {pd[['max_iterations']]}}"
        )
        NA_integer_
      }
    )
    if (!is.na(manifest_max) && is.na(gp@max_iterations)) {
      gp <- GlobalPolicy(max_iterations = manifest_max) # nolint: object_usage_linter. S7 cross-file
    }
  }

  graph@global_policy <- gp
  graph
}
