#' Session Context S7 Classes
#'
#' Manages session state and variable scope during runtime graph traversal.
#' Provides access to `computable_hint` variables based on their availability
#' phase (ADR-0007).
#'
#' @name session_context
#' @include context_schema.R
#' @importFrom rlang %||%
NULL

# -- SessionContext -----------------------------------------------------------

#' @title SessionContext
#' @description Runtime session state for graph traversal. Tracks which
#' variables are available based on the session phase (data loaded,
#' parameters decided, post-fit).
#' @param schema A [ContextSchema] object defining available variables.
#' @param variables Named list of currently computed variable values.
#' @param data A data.frame (or NULL) representing the user's dataset.
#' @param parameters_decided Named list of parameters decided so far.
#' @export
SessionContext <- S7::new_class("SessionContext",
  properties = list(
    schema = ContextSchema,
    variables = S7::new_property(S7::class_list, default = list()),
    data = S7::new_property(
      class = S7::class_any,
      default = NULL
    ),
    parameters_decided = S7::new_property(S7::class_list, default = list())
  ),
  validator = function(self) {
    if (!is.null(self@data) && !is.data.frame(self@data)) {
      return("`data` must be a data.frame or NULL")
    }
    var_names <- names(self@variables)
    if (length(self@variables) > 0L && is.null(var_names)) {
      return("`variables` must be a named list")
    }
    param_names <- names(self@parameters_decided)
    if (length(self@parameters_decided) > 0L && is.null(param_names)) {
      return("`parameters_decided` must be a named list")
    }
    NULL
  }
)

#' Update session context after a node visit
#'
#' @param context A [SessionContext] object.
#' @param node_id ID of the node just visited (character or NULL).
#' @param data Updated data.frame (or NULL to keep current).
#' @param parameters Named list of newly decided parameters to merge.
#' @param fit_result Model fit result object to extract post-fit variables.
#' @return A new [SessionContext] with updated state.
#' @export
update_context <- function(context,
                           node_id = NULL,
                           data = NULL,
                           parameters = NULL,
                           fit_result = NULL) {
  if (!S7::S7_inherits(context, SessionContext)) {
    cli::cli_abort("{.arg context} must be a {.cls SessionContext}.")
  }

  new_data <- context@data
  if (!is.null(data)) {
    if (!is.data.frame(data)) {
      cli::cli_abort("{.arg data} must be a data.frame or NULL.")
    }
    new_data <- data
  }

  new_params <- context@parameters_decided
  if (!is.null(parameters)) {
    if (!is.list(parameters) || is.null(names(parameters))) {
      cli::cli_abort("{.arg parameters} must be a named list.")
    }
    for (nm in names(parameters)) {
      new_params[[nm]] <- parameters[[nm]]
    }
  }

  new_vars <- context@variables
  schema_vars <- context@schema@variables
  for (sv in schema_vars) {
    if (!is.null(new_vars[[sv@name]])) next
    available <- .check_availability(
      sv, new_data, new_params, fit_result, node_id
    )
    if (available) {
      val <- .try_extract_variable(sv, new_data, new_params, fit_result)
      if (!is.null(val)) {
        new_vars[[sv@name]] <- val
      }
    }
  }

  SessionContext(
    schema = context@schema,
    variables = new_vars,
    data = new_data,
    parameters_decided = new_params
  )
}

#' Check if a context variable is available
#'
#' @param context A [SessionContext] object.
#' @param variable_name Name of the variable to check (character).
#' @return Logical: `TRUE` if the variable is currently in scope.
#' @export
is_available <- function(context, variable_name) {
  if (!S7::S7_inherits(context, SessionContext)) {
    cli::cli_abort("{.arg context} must be a {.cls SessionContext}.")
  }
  if (!is.character(variable_name) || length(variable_name) != 1L) {
    cli::cli_abort("{.arg variable_name} must be a single character string.")
  }
  !is.null(context@variables[[variable_name]])
}

#' Get hint variables from context
#'
#' Extracts the currently available variables as a named list suitable for
#' passing to [evaluate_hint()].
#'
#' @param context A [SessionContext] object.
#' @return Named list of variable values.
#' @export
get_hint_variables <- function(context) {
  if (!S7::S7_inherits(context, SessionContext)) {
    cli::cli_abort("{.arg context} must be a {.cls SessionContext}.")
  }
  context@variables
}

# -- Internal helpers ---------------------------------------------------------

#' @keywords internal
.check_availability <- function(schema_var, data, params, fit_result, node_id) {
  phase <- schema_var@available_from
  switch(phase,
    data_loaded = !is.null(data),
    parameter_decided = length(params) > 0L,
    post_fit = !is.null(fit_result),
    FALSE
  )
}

#' @keywords internal
.try_extract_variable <- function(schema_var, data, params, fit_result) {
  env <- new.env(parent = baseenv())
  if (!is.null(data)) env$data <- data
  if (!is.null(params)) env$decisions <- params
  if (!is.null(fit_result)) env$result <- fit_result

  tryCatch(
    {
      setTimeLimit(elapsed = 1, transient = TRUE)
      on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
      eval(parse(text = schema_var@source_expression), envir = env)
    },
    error = function(e) NULL
  )
}
