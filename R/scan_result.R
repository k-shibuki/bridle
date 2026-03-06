#' Scan Result S7 Classes
#'
#' S7 classes representing the output of `scan_package()`. `ParameterInfo`
#' captures a single parameter's metadata; `ScanResult` aggregates all
#' scanner layers' output for one package function (ADR-0004, ADR-0008).
#'
#' @name scan_result
#' @importFrom rlang %||%
NULL

# -- ParameterInfo ------------------------------------------------------------

.valid_classifications <- c(
  "data_input", "statistical_decision", "presentation", "deprecated", "unknown"
)

#' @title ParameterInfo
#' @description Metadata for a single function parameter extracted by the
#' scanner layers.
#' @param name Parameter name (character).
#' @param has_default Whether the parameter has a default value (logical).
#' @param default_expression Deparsed default expression (character). Empty
#'   string when no default exists.
#' @param classification Parameter category (character). One of
#'   `"data_input"`, `"statistical_decision"`, `"presentation"`,
#'   `"deprecated"`, `"unknown"`.
#' @export
ParameterInfo <- S7::new_class("ParameterInfo",
  properties = list(
    name = S7::class_character,
    has_default = S7::class_logical,
    default_expression = S7::new_property(
      S7::class_character,
      default = ""
    ),
    classification = S7::new_property(
      S7::class_character,
      default = "unknown"
    )
  ),
  validator = function(self) {
    if (length(self@name) != 1L || nchar(self@name) == 0L) {
      return("`name` must be a non-empty single string")
    }
    if (length(self@has_default) != 1L || is.na(self@has_default)) {
      return("`has_default` must be TRUE or FALSE")
    }
    if (length(self@default_expression) != 1L) {
      return("`default_expression` must be a single string")
    }
    valid_cls <- length(self@classification) == 1L &&
      self@classification %in% .valid_classifications
    if (!valid_cls) {
      return(sprintf(
        "`classification` must be one of: %s",
        paste(dQuote(.valid_classifications, FALSE), collapse = ", ")
      ))
    }
    NULL
  }
)

# -- ScanResult ---------------------------------------------------------------

.valid_layers <- c("layer1_formals", "layer2_rd", "layer3a_source", "layer3b_fuzz")

#' @title ScanResult
#' @description Aggregated scanner output for one package function. Layers are
#' additive: Layer 1 produces the base result; Layer 2 and Layer 3 refine it.
#' @param package Target package name (character).
#' @param func Target function name (character).
#' @param parameters A list of [ParameterInfo] objects.
#' @param dependency_graph Adjacency list: named list where each element is a
#'   character vector of parameter names that the key depends on.
#' @param constraints A list of [Constraint] objects extracted from scanning.
#' @param valid_values Named list mapping parameter names to character vectors
#'   of valid values (populated by Layer 2+).
#' @param references Character vector of bibliography entries (from Layer 2+).
#' @param scan_metadata Named list with scanner metadata: `layers_completed`
#'   (character vector), `timestamp` (character), `package_version` (character).
#' @usage NULL
#' @export
ScanResult <- S7::new_class("ScanResult",
  properties = list(
    package = S7::class_character,
    func = S7::class_character,
    parameters = S7::class_list,
    dependency_graph = S7::new_property(S7::class_list, default = list()),
    constraints = S7::new_property(S7::class_list, default = list()),
    valid_values = S7::new_property(S7::class_list, default = list()),
    references = S7::new_property(S7::class_character, default = character(0)),
    scan_metadata = S7::class_list
  ),
  validator = function(self) {
    if (length(self@package) != 1L || nchar(self@package) == 0L) {
      return("`package` must be a non-empty single string")
    }
    if (length(self@func) != 1L || nchar(self@func) == 0L) {
      return("`func` must be a non-empty single string")
    }
    if (length(self@parameters) == 0L) {
      return("`parameters` must contain at least one ParameterInfo")
    }
    param_names <- character(length(self@parameters))
    for (i in seq_along(self@parameters)) {
      p <- self@parameters[[i]]
      if (!S7::S7_inherits(p, ParameterInfo)) {
        return(sprintf("parameters[[%d]] must be a ParameterInfo object", i))
      }
      param_names[i] <- p@name
    }
    if (anyDuplicated(param_names)) {
      dup <- param_names[duplicated(param_names)][[1L]]
      return(sprintf("Duplicate parameter name: \"%s\"", dup))
    }
    for (cst in self@constraints) {
      if (!S7::S7_inherits(cst, Constraint)) {
        return("All elements of `constraints` must be Constraint objects")
      }
    }
    layers <- self@scan_metadata[["layers_completed"]]
    if (is.null(layers) || length(layers) == 0L) {
      return("`scan_metadata$layers_completed` is required")
    }
    for (l in layers) {
      if (!l %in% .valid_layers) {
        return(sprintf(
          "Invalid layer in `scan_metadata$layers_completed`: \"%s\"", l
        ))
      }
    }
    NULL
  }
)
