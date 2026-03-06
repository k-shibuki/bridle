#' Package Scanner
#'
#' Analyzes an R package function to produce a [ScanResult]. Layer 1 extracts
#' parameter names, default expressions, AST-parsed dependency graphs, and
#' automatic parameter classification (ADR-0004).
#'
#' @name scan_package
#' @importFrom rlang %||%
NULL

#' Scan a Package Function
#'
#' Entry point for the plugin generation scanner. Implements Layer 1
#' (formals analysis) and Layer 2 (Rd documentation analysis).
#' Layer 3 will be added in subsequent Issues.
#'
#' @param package Package name (character).
#' @param func Function name (character).
#' @return A [ScanResult] object.
#' @export
scan_package <- function(package, func) {
  if (!is.character(package) || length(package) != 1L || nchar(package) == 0L) {
    cli::cli_abort("{.arg package} must be a non-empty string.")
  }
  if (!is.character(func) || length(func) != 1L || nchar(func) == 0L) {
    cli::cli_abort("{.arg func} must be a non-empty string.")
  }

  fn <- resolve_function(package, func)
  result <- scan_layer1(package = package, func_name = func, fn = fn)
  scan_layer2(result)
}

#' Resolve a function from a package namespace
#' @keywords internal
resolve_function <- function(package, func) {
  ns <- tryCatch(
    getNamespace(package),
    error = function(e) {
      cli::cli_abort(
        "Package {.pkg {package}} is not available.",
        parent = e
      )
    }
  )

  fn <- ns[[func]]
  if (is.null(fn) || !is.function(fn)) {
    cli::cli_abort(
      "Function {.fn {func}} not found in package {.pkg {package}}."
    )
  }
  fn
}

# -- Layer 1: Formals Analysis ------------------------------------------------

#' @keywords internal
scan_layer1 <- function(package, func_name, fn) {
  fmls_raw <- formals(fn)
  fmls <- safe_formals(fmls_raw)

  if (length(fmls) == 0L) {
    return(ScanResult( # nolint: object_usage_linter. Defined in scan_result.R.
      package = package,
      func = func_name,
      parameters = list(ParameterInfo( # nolint: object_usage_linter.
        name = "..none..",
        has_default = FALSE,
        default_expression = "",
        classification = "unknown"
      )),
      dependency_graph = list(),
      constraints = list(),
      scan_metadata = list(
        layers_completed = "layer1_formals",
        timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        package_version = get_package_version(package)
      )
    ))
  }

  param_names <- names(fmls)

  parameters <- vector("list", length(param_names))
  for (idx in seq_along(param_names)) {
    nm <- param_names[[idx]]
    if (is_formal_missing(fmls, nm)) {
      parameters[[idx]] <- ParameterInfo( # nolint: object_usage_linter.
        name = nm,
        has_default = FALSE,
        default_expression = "",
        classification = classify_parameter(nm, NULL, FALSE)
      )
    } else {
      expr <- fmls[[nm]]
      def_str <- safe_deparse(expr)
      classification <- classify_parameter(nm, expr, TRUE)
      parameters[[idx]] <- ParameterInfo( # nolint: object_usage_linter.
        name = nm,
        has_default = TRUE,
        default_expression = def_str,
        classification = classification
      )
    }
  }

  dep_graph <- build_dependency_graph(fmls, param_names)

  constraints <- extract_formals_constraints(
    fmls, param_names, dep_graph, package, func_name
  )

  ScanResult( # nolint: object_usage_linter. Defined in scan_result.R.
    package = package,
    func = func_name,
    parameters = parameters,
    dependency_graph = dep_graph,
    constraints = constraints,
    scan_metadata = list(
      layers_completed = "layer1_formals",
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      package_version = get_package_version(package)
    )
  )
}

# -- AST Walking --------------------------------------------------------------

#' Walk an expression AST and collect referenced symbols
#' @keywords internal
walk_ast_symbols <- function(expr) {
  is_atomic <- is.null(expr) || is.numeric(expr) || is.logical(expr) ||
    is.character(expr) || is.complex(expr)
  if (is_atomic) {
    return(character(0))
  }
  if (is.symbol(expr)) {
    nm <- as.character(expr)
    if (nchar(nm) > 0L) {
      return(nm)
    }
    return(character(0))
  }
  if (is.call(expr)) {
    args <- as.list(expr)[-1L]
    symbols <- unlist(lapply(args, walk_ast_symbols), use.names = FALSE)
    return(unique(symbols %||% character(0)))
  }
  if (is.pairlist(expr)) {
    symbols <- unlist(lapply(as.list(expr), walk_ast_symbols), use.names = FALSE)
    return(unique(symbols %||% character(0)))
  }
  character(0)
}

#' Build a dependency graph from formals
#'
#' For each parameter with a default expression, walks the AST to find
#' references to other parameters. Returns a named list (adjacency list).
#' @keywords internal
build_dependency_graph <- function(fmls, param_names) {
  graph <- list()
  for (nm in param_names) {
    expr <- fmls[[nm]]
    if (inherits(expr, "bridle_missing_formal")) {
      next
    }
    refs <- walk_ast_symbols(expr)
    deps <- intersect(refs, param_names)
    deps <- setdiff(deps, nm)
    if (length(deps) > 0L) {
      graph[[nm]] <- deps
    }
  }
  graph
}

# -- Parameter Classification -------------------------------------------------

.data_input_patterns <- c(
  "^event", "^n\\.", "^mean\\.", "^sd\\.", "^time\\.", "^cor",
  "^data$", "^studlab$", "^subset$"
)

.presentation_patterns <- c(
  "^digit", "^label", "^print\\.", "^text\\.", "^col\\.", "^title",
  "^xlab$", "^ylab$", "^smlab$", "^comb\\.", "^overall$",
  "^overall\\.", "^subgroup$", "^test\\."
)

.statistical_patterns <- c(
  "^method", "^sm$", "^model\\.", "^tau", "^random$",
  "^fixed$", "^common$", "^level", "^hakn$", "^adhoc\\.",
  "^prediction$", "^null\\.effect$"
)

#' Classify a parameter by naming convention and default type
#' @keywords internal
classify_parameter <- function(name, expr, has_default) {
  if (name == "...") {
    return("unknown")
  }

  if (matches_any_pattern(name, .data_input_patterns)) {
    return("data_input")
  }

  if (matches_any_pattern(name, .statistical_patterns)) {
    return("statistical_decision")
  }

  if (matches_any_pattern(name, .presentation_patterns)) {
    return("presentation")
  }

  if (has_default && is_deprecation_expr(expr)) {
    return("deprecated")
  }

  "unknown"
}

#' @keywords internal
matches_any_pattern <- function(name, patterns) {
  for (p in patterns) {
    if (grepl(p, name, perl = TRUE)) {
      return(TRUE)
    }
  }
  FALSE
}

#' Detect lifecycle deprecation patterns in default expressions
#' @keywords internal
is_deprecation_expr <- function(expr) {
  if (!is.call(expr)) {
    return(FALSE)
  }
  dep_str <- safe_deparse(expr)
  grepl("deprecated|lifecycle", dep_str, ignore.case = TRUE)
}

# -- Constraint Extraction from Formals ---------------------------------------

#' Extract constraints from default expressions
#'
#' Identifies `ifelse()`/`switch()` patterns in formals that imply `forces`
#' constraints (conditional defaults).
#' @keywords internal
extract_formals_constraints <- function(fmls, param_names, dep_graph, package,
                                        func_name) {
  constraints <- list()
  counter <- 0L

  for (nm in names(dep_graph)) {
    expr <- fmls[[nm]]
    deps <- dep_graph[[nm]]

    if (is_conditional_default(expr)) {
      counter <- counter + 1L
      cid <- sprintf("%s_%s_cond_%d", package, func_name, counter)
      constraints <- c(constraints, list(Constraint( # nolint: object_usage_linter.
        id = cid,
        source = "formals_default",
        type = "forces",
        param = nm,
        condition = safe_deparse(expr),
        forces = stats::setNames(
          as.list(rep("(see condition)", length(deps))),
          deps
        ),
        message = sprintf(
          "Default of `%s` depends on: %s",
          nm, paste(deps, collapse = ", ")
        ),
        confirmed_by = "formals_default",
        confidence = "medium"
      )))
    }
  }

  constraints
}

#' Check if an expression is a conditional default (ifelse/switch/if)
#' @keywords internal
is_conditional_default <- function(expr) {
  if (!is.call(expr)) {
    return(FALSE)
  }
  fn <- expr[[1L]]
  if (is.symbol(fn)) {
    fn_name <- as.character(fn)
    if (fn_name %in% c("ifelse", "switch", "if")) {
      return(TRUE)
    }
  }
  for (i in seq_along(expr)[-1L]) {
    if (is_conditional_default(expr[[i]])) {
      return(TRUE)
    }
  }
  FALSE
}

# -- Helpers ------------------------------------------------------------------

.missing_sentinel <- structure(list(), class = "bridle_missing_formal")

#' Safely convert formals pairlist to a named list
#'
#' Missing formals (no default) are replaced with a sentinel object.
#' This avoids R's "argument is missing" error when accessing pairlist
#' elements for `...` and other params without defaults.
#' @keywords internal
safe_formals <- function(fmls) {
  if (is.null(fmls)) {
    return(list())
  }
  nms <- names(fmls)
  result <- vector("list", length(nms))
  names(result) <- nms
  for (nm in nms) {
    converted <- tryCatch(
      {
        val <- fmls[[nm]]
        if (is.symbol(val) && identical(deparse(val), "")) {
          .missing_sentinel
        } else {
          val
        }
      },
      error = function(e) .missing_sentinel
    )
    result[nm] <- list(converted)
  }
  result
}

#' Check if a formal parameter has no default value
#' @keywords internal
is_formal_missing <- function(fmls, nm) {
  inherits(fmls[[nm]], "bridle_missing_formal")
}

#' Safely deparse an expression to a single string
#' @keywords internal
safe_deparse <- function(expr) {
  paste(deparse(expr, width.cutoff = 500L), collapse = " ")
}

#' Get installed package version (mockable wrapper)
#' @keywords internal
get_package_version <- function(package) {
  as.character(utils::packageVersion(package))
}

# -- Layer 2: Rd Documentation Analysis ---------------------------------------

#' Enrich a ScanResult with Rd documentation analysis
#'
#' Extracts valid-value lists, parameter descriptions, references, and
#' deprecated parameter flags from the package's Rd database.
#' Gracefully skips if Rd is unavailable.
#' @keywords internal
scan_layer2 <- function(scan_result) {
  rd_db <- tryCatch(
    get_rd_db(scan_result@package),
    error = function(e) {
      cli::cli_warn(
        "Layer 2: Cannot access Rd for {.pkg {scan_result@package}}."
      )
      NULL
    }
  )
  if (is.null(rd_db)) {
    return(scan_result)
  }

  rd <- find_function_rd(rd_db, scan_result@func)
  if (is.null(rd)) {
    cli::cli_warn(
      "Layer 2: No Rd documentation for {.fn {scan_result@func}}."
    )
    return(scan_result)
  }

  param_descs <- extract_rd_param_descriptions(rd)
  valid_vals <- extract_rd_valid_values(param_descs)
  refs <- extract_rd_references(rd)
  deprecated <- detect_rd_deprecated(param_descs)

  updated_params <- update_deprecated_params(
    scan_result@parameters, deprecated
  )

  layers <- c(scan_result@scan_metadata[["layers_completed"]], "layer2_rd")
  metadata <- scan_result@scan_metadata
  metadata[["layers_completed"]] <- layers

  ScanResult( # nolint: object_usage_linter. S7 class in R/scan_result.R
    package = scan_result@package,
    func = scan_result@func,
    parameters = updated_params,
    dependency_graph = scan_result@dependency_graph,
    constraints = scan_result@constraints,
    valid_values = valid_vals,
    descriptions = param_descs,
    references = refs,
    scan_metadata = metadata
  )
}

#' Get Rd database for a package (mockable wrapper)
#' @keywords internal
get_rd_db <- function(package) {
  tools::Rd_db(package)
}

#' Find the Rd object for a specific function by name or alias
#' @keywords internal
find_function_rd <- function(rd_db, func_name) {
  rd_name <- paste0(func_name, ".Rd")
  if (rd_name %in% names(rd_db)) {
    return(rd_db[[rd_name]])
  }
  for (rd in rd_db) {
    aliases <- get_rd_aliases(rd)
    if (func_name %in% aliases) {
      return(rd)
    }
  }
  NULL
}

#' Extract alias names from an Rd object
#' @keywords internal
get_rd_aliases <- function(rd) {
  aliases <- character(0)
  for (section in rd) {
    tag <- attr(section, "Rd_tag")
    if (identical(tag, "\\alias")) {
      aliases <- c(aliases, rd_text(section))
    }
  }
  aliases
}

#' Get a specific section from an Rd object by tag
#' @keywords internal
get_rd_section <- function(rd, tag_name) {
  for (section in rd) {
    tag <- attr(section, "Rd_tag")
    if (identical(tag, tag_name)) {
      return(section)
    }
  }
  NULL
}

#' Convert Rd content to plain text recursively
#' @keywords internal
rd_text <- function(x) {
  if (is.character(x)) {
    return(paste(x, collapse = ""))
  }
  if (is.list(x)) {
    parts <- vapply(x, rd_text, character(1))
    return(paste(parts, collapse = ""))
  }
  ""
}

#' Extract parameter descriptions from the \\arguments section
#' @keywords internal
extract_rd_param_descriptions <- function(rd) {
  args_section <- get_rd_section(rd, "\\arguments")
  if (is.null(args_section)) {
    return(list())
  }

  descriptions <- list()
  for (item in args_section) {
    tag <- attr(item, "Rd_tag")
    if (!identical(tag, "\\item")) next
    if (length(item) < 2L) next

    param_name <- trimws(rd_text(item[[1L]]))
    desc_text <- trimws(rd_text(item[[2L]]))
    if (nchar(param_name) > 0L) {
      descriptions[[param_name]] <- desc_text
    }
  }
  descriptions
}

#' Extract valid values from parameter descriptions
#'
#' Scans description text for enumeration patterns such as
#' "one of X, Y, Z" or "must be X or Y".
#' @keywords internal
extract_rd_valid_values <- function(descriptions) {
  valid_values <- list()
  for (param in names(descriptions)) {
    values <- extract_values_from_text(descriptions[[param]])
    if (length(values) > 0L) {
      valid_values[[param]] <- values
    }
  }
  valid_values
}

#' Extract enumerated values from a text string
#' @keywords internal
extract_values_from_text <- function(text) {
  patterns <- c(
    "(?i)\\bone of\\b\\s+(.+?)(?:\\.|;|\\n|$)",
    "(?i)\\bmust be\\b\\s+(.+?)(?:\\.|;|\\n|$)",
    "(?i)(?:possible|allowed|valid)\\s+values?\\s*(?:are|:)?\\s+(.+?)(?:\\.|;|\\n|$)"
  )
  for (pat in patterns) {
    m <- regmatches(text, regexec(pat, text, perl = TRUE))[[1L]]
    if (length(m) >= 2L) {
      values <- extract_quoted_values(m[[2L]])
      if (length(values) > 0L) {
        return(values)
      }
      values <- extract_unquoted_values(m[[2L]])
      if (length(values) > 0L) {
        return(values)
      }
    }
  }
  character(0)
}

#' Extract values enclosed in quotes from text
#' @keywords internal
extract_quoted_values <- function(text) {
  m <- gregexpr('["\']([^"\']+)["\']', text, perl = TRUE)
  raw <- regmatches(text, m)[[1L]]
  if (length(raw) == 0L) {
    return(character(0))
  }
  gsub('^["\']|["\']$', "", raw)
}

#' Extract comma/or-separated bare values from text
#' @keywords internal
extract_unquoted_values <- function(text) {
  text <- trimws(text)
  parts <- strsplit(text, "\\s*,\\s*|\\s+or\\s+|\\s+and\\s+", perl = TRUE)[[1L]]
  parts <- trimws(parts)
  parts <- gsub('^["\']|["\']$', "", parts)
  parts <- parts[nchar(parts) > 0L & nchar(parts) < 50L]
  if (length(parts) >= 2L) {
    return(parts)
  }
  character(0)
}

#' Extract references from the \\references section
#' @keywords internal
extract_rd_references <- function(rd) {
  ref_section <- get_rd_section(rd, "\\references")
  if (is.null(ref_section)) {
    return(character(0))
  }

  text <- trimws(rd_text(ref_section))
  if (nchar(text) == 0L) {
    return(character(0))
  }

  refs <- strsplit(text, "\n\\s*\n+")[[1L]]
  refs <- trimws(refs)
  refs[nchar(refs) > 0L]
}

#' Detect deprecated parameters from Rd descriptions
#' @keywords internal
detect_rd_deprecated <- function(descriptions) {
  deprecated <- character(0)
  for (param in names(descriptions)) {
    desc <- descriptions[[param]]
    is_deprecated <- grepl(
      "(?i)\\bdeprecated\\b", desc,
      perl = TRUE
    )
    if (is_deprecated) {
      deprecated <- c(deprecated, param)
    }
  }
  deprecated
}

#' Update parameter classifications for deprecated params detected by Rd
#' @keywords internal
update_deprecated_params <- function(parameters, deprecated_params) {
  if (length(deprecated_params) == 0L) {
    return(parameters)
  }
  for (i in seq_along(parameters)) {
    p <- parameters[[i]]
    if (p@name %in% deprecated_params && p@classification != "deprecated") {
      parameters[[i]] <- ParameterInfo( # nolint: object_usage_linter. S7 class in R/scan_result.R
        name = p@name,
        has_default = p@has_default,
        default_expression = p@default_expression,
        classification = "deprecated"
      )
    }
  }
  parameters
}
