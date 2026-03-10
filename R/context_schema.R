#' Context Schema S7 Classes
#'
#' S7 classes defining the variable scope available to `computable_hint`
#' expressions and expected data structure for a plugin (ADR-0007).
#'
#' @name context_schema
#' @importFrom rlang %||%
NULL

# -- DataExpectation ----------------------------------------------------------

.valid_roles <- c("outcome", "group", "study_id", "covariate", "weight")

#' @title DataExpectation
#' @description Expected column in the user's data. Used by context_gathering
#' nodes and `validate_plugin()` for informational checks.
#' @param column Expected column name (character).
#' @param role Semantic role (character). One of `"outcome"`, `"group"`,
#'   `"study_id"`, `"covariate"`, `"weight"`.
#' @param required Whether this column must be present (logical).
#' @export
DataExpectation <- S7::new_class("DataExpectation",
  properties = list(
    column = S7::class_character,
    role = S7::class_character,
    required = S7::class_logical
  ),
  validator = function(self) {
    if (length(self@column) != 1L || nchar(self@column) == 0L) {
      return("`column` must be a non-empty single string")
    }
    if (length(self@role) != 1L || !self@role %in% .valid_roles) {
      return(sprintf(
        "`role` must be one of: %s",
        paste(dQuote(.valid_roles, FALSE), collapse = ", ")
      ))
    }
    if (length(self@required) != 1L || is.na(self@required)) {
      return("`required` must be TRUE or FALSE")
    }
    NULL
  }
)

# -- ContextVariable ----------------------------------------------------------

.valid_available_from <- c("data_loaded", "parameter_decided", "post_fit")

#' @title ContextVariable
#' @description A statically declared variable available to `computable_hint`
#' and `skip_hint` expressions.
#' @param name Variable name as used in R expressions (character).
#' @param description Human-readable description (character).
#' @param available_from Phase when this variable becomes computable
#'   (character). One of `"data_loaded"`, `"parameter_decided"`, `"post_fit"`.
#' @param depends_on_node Optional graph node ID dependency (character).
#' @param source_expression R expression to extract the variable value
#'   (character).
#' @export
ContextVariable <- S7::new_class("ContextVariable",
  properties = list(
    name = S7::class_character,
    description = S7::class_character,
    available_from = S7::class_character,
    depends_on_node = S7::new_property(
      S7::class_character,
      default = character(0)
    ),
    source_expression = S7::class_character
  ),
  validator = function(self) {
    if (length(self@name) != 1L || nchar(self@name) == 0L) {
      return("`name` must be a non-empty single string")
    }
    if (length(self@description) != 1L || nchar(self@description) == 0L) {
      return("`description` must be a non-empty single string")
    }
    valid_avail <- length(self@available_from) == 1L &&
      self@available_from %in% .valid_available_from
    if (!valid_avail) {
      return(sprintf(
        "`available_from` must be one of: %s",
        paste(dQuote(.valid_available_from, FALSE), collapse = ", ")
      ))
    }
    has_src <- length(self@source_expression) == 1L &&
      nchar(self@source_expression) > 0L
    if (!has_src) {
      return("`source_expression` must be a non-empty single string")
    }
    NULL
  }
)

# -- ContextSchema ------------------------------------------------------------

#' @title ContextSchema
#' @description The context schema defining variable scope and data expectations
#' for a plugin.
#' @param variables A list of [ContextVariable] objects.
#' @param data_expectations Optional list of [DataExpectation] objects.
#' @usage NULL
#' @export
ContextSchema <- S7::new_class("ContextSchema",
  properties = list(
    variables = S7::class_list,
    data_expectations = S7::new_property(S7::class_list, default = list())
  ),
  validator = function(self) {
    for (i in seq_along(self@variables)) {
      if (!S7::S7_inherits(self@variables[[i]], ContextVariable)) {
        return(sprintf(
          "variables[[%d]] must be a ContextVariable object", i
        ))
      }
    }
    for (i in seq_along(self@data_expectations)) {
      if (!S7::S7_inherits(self@data_expectations[[i]], DataExpectation)) {
        return(sprintf(
          "data_expectations[[%d]] must be a DataExpectation object", i
        ))
      }
    }
    NULL
  }
)

# -- YAML Reader --------------------------------------------------------------

#' Read a Context Schema from YAML
#'
#' Parses a `context_schema.yaml` file and returns a [ContextSchema] object.
#'
#' @param path Path to the YAML file.
#' @return A [ContextSchema] object.
#' @export
read_context_schema <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }
  raw <- tryCatch(
    yaml::yaml.load_file(path),
    error = function(e) {
      cli::cli_abort("Failed to parse YAML: {conditionMessage(e)}", parent = e)
    }
  )
  parse_context_schema(raw)
}

#' @keywords internal
parse_context_schema <- function(raw) {
  vars_raw <- raw[["variables"]]
  if (is.null(vars_raw) || length(vars_raw) == 0L) {
    cli::cli_abort("{.field variables} must be a non-empty list")
  }
  variables <- lapply(vars_raw, parse_context_variable)

  de_raw <- raw[["data_expectations"]]
  data_expectations <- list()
  if (!is.null(de_raw) && length(de_raw) > 0L) {
    data_expectations <- lapply(de_raw, parse_data_expectation)
  }

  ContextSchema(
    variables = variables,
    data_expectations = data_expectations
  )
}

#' @keywords internal
parse_context_variable <- function(raw) {
  name <- raw[["name"]]
  if (is.null(name)) {
    cli::cli_abort("ContextVariable is missing required field {.field name}")
  }
  desc <- raw[["description"]]
  if (is.null(desc)) {
    cli::cli_abort(
      "ContextVariable {.val {name}} is missing required field {.field description}"
    )
  }
  avail <- raw[["available_from"]]
  if (is.null(avail)) {
    cli::cli_abort(
      "ContextVariable {.val {name}} is missing required field {.field available_from}"
    )
  }
  src_expr <- raw[["source_expression"]]
  if (is.null(src_expr)) {
    cli::cli_abort(
      "ContextVariable {.val {name}} is missing required field {.field source_expression}"
    )
  }

  ContextVariable(
    name = name,
    description = desc,
    available_from = avail,
    depends_on_node = raw[["depends_on_node"]] %||% character(0),
    source_expression = src_expr
  )
}

#' @keywords internal
parse_data_expectation <- function(raw) {
  col <- raw[["column"]]
  if (is.null(col)) {
    cli::cli_abort(
      "DataExpectation is missing required field {.field column}"
    )
  }
  role <- raw[["role"]]
  if (is.null(role)) {
    cli::cli_abort(
      "DataExpectation {.val {col}} is missing required field {.field role}"
    )
  }
  req <- raw[["required"]]
  if (is.null(req)) {
    cli::cli_abort(
      "DataExpectation {.val {col}} is missing required field {.field required}"
    )
  }

  DataExpectation(
    column = col,
    role = role,
    required = as.logical(req)
  )
}
