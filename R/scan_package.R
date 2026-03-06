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
#' Entry point for the plugin generation scanner. Currently implements Layer 1
#' (formals analysis). Layers 2 and 3 will be added in subsequent Issues.
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
  scan_layer1(package = package, func_name = func, fn = fn)
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
  if (is.null(expr) || is.numeric(expr) || is.logical(expr) ||
    is.character(expr) || is.complex(expr)) {
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
