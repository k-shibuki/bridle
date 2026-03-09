#' Package Scanner
#'
#' Analyzes an R package to produce a [PackageScanResult] that maps the full
#' decision space including function classification, family structure, and
#' cross-function constraints (ADR-0004, ADR-0004 Addendum).
#'
#' @name scan_package
#' @importFrom rlang %||%
NULL

#' Scan an R Package
#'
#' Entry point for the plugin generation scanner. Enumerates exported
#' functions, classifies them by role, scans analysis functions through
#' Layers 1-3, detects function families, and extracts cross-function
#' constraints.
#'
#' @param package Package name (character).
#' @return A [PackageScanResult] object.
#' @export
scan_package <- function(package) {
  if (!is.character(package) || length(package) != 1L || nchar(package) == 0L) {
    cli::cli_abort("{.arg package} must be a non-empty string.")
  }

  ns <- get_package_namespace(package)

  exports <- get_namespace_exports(package)
  non_s3 <- exclude_s3_methods(exports, package)
  roles <- classify_functions(non_s3, ns, package)
  analysis_fns <- names(roles[roles == "analysis"])

  cli::cli_inform(
    "Scanning {.pkg {package}}: {length(non_s3)} exports, {length(analysis_fns)} analysis functions."
  )

  functions <- list()
  for (fn_name in analysis_fns) {
    tryCatch(
      {
        functions[[fn_name]] <- scan_function(package, fn_name)
      },
      error = function(e) {
        cli::cli_warn(
          "Skipping {.fn {fn_name}}: {conditionMessage(e)}"
        )
      }
    )
  }

  families <- detect_families(functions)
  cross_constraints <- extract_cross_constraints(functions, roles)

  PackageScanResult( # nolint: object_usage_linter. S7 class in scan_result.R
    package = package,
    functions = functions,
    function_roles = roles,
    function_families = families,
    cross_function_constraints = cross_constraints,
    scan_metadata = list(
      package_version = get_package_version(package),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      bridle_version = as.character(utils::packageVersion("bridle")),
      total_exports = length(exports),
      scanned_functions = length(functions)
    )
  )
}

#' Scan a Single Package Function
#'
#' Internal function-level scanner. Runs Layer 1 (formals), Layer 2 (Rd),
#' and Layer 3a (source) analysis on a single function.
#'
#' @param package Package name (character).
#' @param func Function name (character).
#' @return A [ScanResult] object.
#' @keywords internal
scan_function <- function(package, func) {
  if (!is.character(package) || length(package) != 1L || nchar(package) == 0L) {
    cli::cli_abort("{.arg package} must be a non-empty string.")
  }
  if (!is.character(func) || length(func) != 1L || nchar(func) == 0L) {
    cli::cli_abort("{.arg func} must be a non-empty string.")
  }

  fn <- resolve_function(package, func)
  result <- scan_layer1(package = package, func_name = func, fn = fn)
  result <- scan_layer2(result)
  scan_layer3a(result, fn)
}

# -- Package-Level Helpers ---------------------------------------------------

#' Get a package namespace (mockable wrapper)
#' @keywords internal
get_package_namespace <- function(package) {
  tryCatch(
    getNamespace(package),
    error = function(e) {
      cli::cli_abort(
        "Package {.pkg {package}} is not available.",
        parent = e
      )
    }
  )
}

#' Get exported function names from a package namespace (mockable)
#' @keywords internal
get_namespace_exports <- function(package) {
  getNamespaceExports(package)
}

#' Exclude S3 methods from a list of exported names
#' @keywords internal
exclude_s3_methods <- function(exports, package) {
  s3_table <- tryCatch(
    get_s3_method_table(package),
    error = function(e) data.frame(method = character(0), stringsAsFactors = FALSE)
  )

  s3_methods <- if (nrow(s3_table) > 0L && "method" %in% names(s3_table)) {
    as.character(s3_table$method)
  } else if (nrow(s3_table) > 0L) {
    paste0(s3_table[[1L]], ".", s3_table[[2L]])
  } else {
    character(0)
  }

  remaining <- setdiff(exports, s3_methods)
  ns <- getNamespace(package)
  Filter(function(nm) is.function(ns[[nm]]), remaining)
}

#' Get S3 methods table for a package (mockable)
#' @keywords internal
get_s3_method_table <- function(package) {
  ns <- asNamespace(package)
  tbl <- ns[[".__S3MethodsTable__."]]
  if (is.null(tbl)) {
    return(data.frame(method = character(0), stringsAsFactors = FALSE))
  }
  method_names <- ls(tbl)
  data.frame(method = method_names, stringsAsFactors = FALSE)
}

#' Classify exported functions by role
#' @keywords internal
classify_functions <- function(func_names, ns, package) {
  rd_db <- tryCatch(
    get_rd_db(package),
    error = function(e) NULL
  )

  roles <- character(length(func_names))
  names(roles) <- func_names

  for (fn_name in func_names) {
    fn <- ns[[fn_name]]
    fml_names <- names(formals(fn))
    rd_title <- get_rd_title(rd_db, fn_name)
    roles[[fn_name]] <- classify_single_function(fn_name, fml_names, rd_title)
  }
  roles
}

#' Classify a single function by heuristic signals
#' @keywords internal
classify_single_function <- function(fn_name, fml_names, rd_title) {
  score_analysis <- 0L
  score_viz <- 0L
  score_diag <- 0L

  analysis_formals <- c("data", "method", "measure", "yi", "vi", "ai", "bi")
  viz_formals <- c("col", "pch", "lty", "xlim", "ylim", "main", "xlab", "ylab")

  if (any(analysis_formals %in% fml_names)) score_analysis <- score_analysis + 1L
  if (any(viz_formals %in% fml_names)) score_viz <- score_viz + 1L
  if (length(fml_names) == 1L && identical(fml_names[1L], "x")) score_diag <- score_diag + 1L

  rd_lower <- tolower(rd_title)
  analysis_words <- c("fit", "model", "analysis", "estimat", "calculat", "effect size")
  viz_words <- c("plot", "forest", "funnel", "graph", "draw", "diagram")
  diag_words <- c("influence", "diagnostic", "residual", "leave1out", "sensitivity")

  for (w in analysis_words) {
    if (grepl(w, rd_lower, fixed = TRUE)) score_analysis <- score_analysis + 1L
  }
  for (w in viz_words) {
    if (grepl(w, rd_lower, fixed = TRUE)) score_viz <- score_viz + 1L
  }
  for (w in diag_words) {
    if (grepl(w, rd_lower, fixed = TRUE)) score_diag <- score_diag + 1L
  }

  if (grepl("^(forest|funnel|plot|draw|baujat|labbe|radial|qqnorm)", fn_name)) {
    score_viz <- score_viz + 2L
  }
  if (grepl("^(influence|leave1out|residuals|rstudent|cooks\\.distance)", fn_name)) {
    score_diag <- score_diag + 2L
  }
  if (grepl("^(rma|escalc|metabin|metacont|metaprop)", fn_name)) {
    score_analysis <- score_analysis + 2L
  }

  scores <- c(analysis = score_analysis, visualization = score_viz, diagnostic = score_diag)
  max_score <- max(scores)

  if (max_score == 0L) {
    return("utility")
  }
  winner <- names(which.max(scores))
  winner
}

#' Get Rd title for a function (returns empty string if unavailable)
#' @keywords internal
get_rd_title <- function(rd_db, func_name) {
  if (is.null(rd_db)) {
    return("")
  }
  rd <- find_function_rd(rd_db, func_name)
  if (is.null(rd)) {
    return("")
  }
  title_section <- get_rd_section(rd, "\\title")
  if (is.null(title_section)) {
    return("")
  }
  trimws(rd_text(title_section))
}

#' Detect function families by shared prefix
#' @keywords internal
detect_families <- function(scan_results) {
  func_names <- names(scan_results)
  if (length(func_names) < 2L) {
    return(list())
  }

  prefix_groups <- list()
  for (fn_name in func_names) {
    parts <- strsplit(fn_name, "\\.", perl = TRUE)[[1L]]
    if (length(parts) >= 2L) {
      prefix <- parts[1L]
      prefix_groups[[prefix]] <- c(prefix_groups[[prefix]], fn_name)
    }
  }

  families <- list()
  for (prefix in names(prefix_groups)) {
    members <- prefix_groups[[prefix]]
    if (length(members) < 2L) next

    all_params <- lapply(members, function(fn_name) {
      sr <- scan_results[[fn_name]]
      vapply(sr@parameters, function(p) p@name, character(1))
    })
    names(all_params) <- members

    common <- Reduce(intersect, all_params)
    common <- setdiff(common, "..none..")

    member_info <- list()
    for (fn_name in members) {
      unique_params <- setdiff(all_params[[fn_name]], c(common, "..none.."))
      member_info[[fn_name]] <- list(unique_parameters = unique_params)
    }

    families[[prefix]] <- list(
      name = prefix,
      common_parameters = common,
      members = member_info
    )
  }
  families
}

#' Extract cross-function constraints from scan results
#' @keywords internal
extract_cross_constraints <- function(scan_results, roles) {
  constraints <- list()

  for (fn_name in names(scan_results)) {
    sr <- scan_results[[fn_name]]
    vv <- sr@valid_values

    if ("measure" %in% names(vv)) {
      vals <- vv[["measure"]]
      if (length(vals) > 0L && length(vals) <= 5L) {
        constraints <- c(constraints, list(list(
          function_name = fn_name,
          constraint = sprintf(
            "measure %%in%% c(%s)",
            paste0('"', vals, '"', collapse = ", ")
          ),
          reason = sprintf(
            "%s restricts 'measure' to: %s",
            fn_name, paste(vals, collapse = ", ")
          )
        )))
      }
    }

    for (cst in sr@constraints) {
      if (cst@type == "forces" && cst@source == "formals_default") {
        constraints <- c(constraints, list(list(
          function_name = fn_name,
          constraint = cst@condition,
          reason = cst@message
        )))
      }
    }
  }
  constraints
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
      parameters = list(ParameterInfo( # nolint: object_usage_linter. S7 class in scan_result.R
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
      parameters[[idx]] <- ParameterInfo( # nolint: object_usage_linter. S7 class in scan_result.R
        name = nm,
        has_default = FALSE,
        default_expression = "",
        classification = classify_parameter(nm, NULL, FALSE)
      )
    } else {
      expr <- fmls[[nm]]
      def_str <- safe_deparse(expr)
      classification <- classify_parameter(nm, expr, TRUE)
      parameters[[idx]] <- ParameterInfo( # nolint: object_usage_linter. S7 class in scan_result.R
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
      constraints <- c(constraints, list(Constraint( # nolint: object_usage_linter. S7 class in constraints.R
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

# -- Layer 3a: Source Code Static Analysis ------------------------------------

#' Enrich a ScanResult with source code static analysis
#'
#' Extracts `match.arg()` valid values and `stop()`/`warning()` constraints
#' from function body AST. Applies confidence grading based on cross-layer
#' confirmation (ADR-0004, ADR-0008).
#' @keywords internal
scan_layer3a <- function(scan_result, fn) {
  if (is.primitive(fn)) {
    cli::cli_warn(
      "Layer 3a: Cannot access source for {.fn {scan_result@func}}."
    )
    return(scan_result)
  }
  fn_body <- body(fn)
  if (is.null(fn_body)) {
    return(scan_result)
  }

  fmls <- formals(fn)
  param_names <- names(fmls)
  if (is.null(param_names)) param_names <- character(0)

  ma_values <- find_match_arg_values(fn_body, fmls, param_names)
  stop_constraints <- find_stop_constraints(
    fn_body, param_names,
    scan_result@package, scan_result@func
  )

  updated_constraints <- upgrade_confidence(
    scan_result@constraints, ma_values,
    scan_result@valid_values, stop_constraints
  )
  all_constraints <- c(updated_constraints, stop_constraints)

  merged_valid <- merge_valid_values(scan_result@valid_values, ma_values)

  layers <- c(
    scan_result@scan_metadata[["layers_completed"]], "layer3a_source"
  )
  metadata <- scan_result@scan_metadata
  metadata[["layers_completed"]] <- layers

  ScanResult( # nolint: object_usage_linter. S7 class in R/scan_result.R
    package = scan_result@package,
    func = scan_result@func,
    parameters = scan_result@parameters,
    dependency_graph = scan_result@dependency_graph,
    constraints = all_constraints,
    valid_values = merged_valid,
    descriptions = scan_result@descriptions,
    references = scan_result@references,
    scan_metadata = metadata
  )
}

#' Find match.arg() calls and extract valid values
#' @keywords internal
find_match_arg_values <- function(fn_body, fmls, param_names) {
  calls <- collect_calls(fn_body, "match.arg")
  result <- list()
  for (cl in calls) {
    info <- parse_match_arg(cl, fmls, param_names)
    if (!is.null(info)) {
      result[[info$param]] <- info$values
    }
  }
  result
}

#' Parse a single match.arg() call to extract param and choices
#' @keywords internal
parse_match_arg <- function(call_expr, fmls, param_names) {
  args <- as.list(call_expr)[-1L]
  if (length(args) == 0L) {
    return(NULL)
  }

  param_expr <- args[[1L]]
  param_name <- if (is.symbol(param_expr)) {
    as.character(param_expr)
  } else {
    return(NULL)
  }
  if (!param_name %in% param_names) {
    return(NULL)
  }

  if (length(args) >= 2L) {
    choices_expr <- args[[2L]]
    values <- extract_char_vector(choices_expr)
    if (length(values) > 0L) {
      return(list(param = param_name, values = values))
    }
  }

  fml_default <- tryCatch(fmls[[param_name]], error = function(e) NULL)
  if (!is.null(fml_default)) {
    values <- extract_char_vector(fml_default)
    if (length(values) > 0L) {
      return(list(param = param_name, values = values))
    }
  }
  NULL
}

#' Extract character vector from a c() expression
#' @keywords internal
extract_char_vector <- function(expr) {
  if (is.character(expr)) {
    return(expr)
  }
  if (!is.call(expr)) {
    return(character(0))
  }
  fn <- expr[[1L]]
  if (!is.symbol(fn) || as.character(fn) != "c") {
    return(character(0))
  }
  args <- as.list(expr)[-1L]
  values <- character(0)
  for (a in args) {
    if (is.character(a) && length(a) == 1L) {
      values <- c(values, a)
    }
  }
  values
}

#' Find stop()/warning() calls with parameter-related conditions
#' @keywords internal
find_stop_constraints <- function(fn_body, param_names, package, func) {
  stop_calls <- collect_conditional_stops(fn_body, param_names)
  constraints <- list()
  counter <- 0L
  for (sc in stop_calls) {
    counter <- counter + 1L
    cid <- sprintf("%s_%s_stop_%d", package, func, counter)
    constraints <- c(constraints, list(
      Constraint( # nolint: object_usage_linter. S7 class in R/constraints.R
        id = cid,
        source = "source_code",
        type = "conditional",
        param = sc$param,
        condition = sc$condition,
        enabled_when = sc$condition,
        message = sc$message,
        confirmed_by = "source_code",
        confidence = "medium"
      )
    ))
  }
  constraints
}

#' Collect function calls by name from an AST recursively
#' @keywords internal
collect_calls <- function(expr, fn_name) {
  if (is.null(expr) || is.atomic(expr) || is.symbol(expr)) {
    return(list())
  }
  if (!is.call(expr) && !is.recursive(expr)) {
    return(list())
  }

  result <- list()
  if (is.call(expr)) {
    fn <- expr[[1L]]
    if (is.symbol(fn) && as.character(fn) == fn_name) {
      result <- list(expr)
    }
    for (i in seq_along(expr)[-1L]) {
      result <- c(result, collect_calls(expr[[i]], fn_name))
    }
  } else if (is.recursive(expr)) {
    for (i in seq_along(expr)) {
      result <- c(result, collect_calls(expr[[i]], fn_name))
    }
  }
  result
}

#' Collect stop()/warning() calls inside if-conditions referencing params
#' @keywords internal
collect_conditional_stops <- function(expr, param_names) {
  if (is.null(expr) || is.atomic(expr) || is.symbol(expr)) {
    return(list())
  }
  if (!is.call(expr) && !is.recursive(expr)) {
    return(list())
  }

  results <- list()
  if (is.call(expr)) {
    fn <- expr[[1L]]
    is_if <- is.symbol(fn) && as.character(fn) == "if"
    if (is_if && length(expr) >= 3L) {
      cond <- expr[[2L]]
      body_expr <- expr[[3L]]
      cond_params <- intersect(walk_ast_symbols(cond), param_names)
      if (length(cond_params) > 0L) {
        stops <- c(
          collect_calls(body_expr, "stop"),
          collect_calls(body_expr, "warning")
        )
        for (s in stops) {
          msg <- extract_stop_message(s)
          for (p in cond_params) {
            results <- c(results, list(list(
              param = p,
              condition = safe_deparse(cond),
              message = msg
            )))
          }
        }
      }
    }
    for (i in seq_along(expr)[-1L]) {
      results <- c(results, collect_conditional_stops(expr[[i]], param_names))
    }
  } else if (is.recursive(expr)) {
    for (i in seq_along(expr)) {
      results <- c(results, collect_conditional_stops(expr[[i]], param_names))
    }
  }
  results
}

#' Extract message string from a stop() or warning() call
#' @keywords internal
extract_stop_message <- function(call_expr) {
  args <- as.list(call_expr)[-1L]
  for (a in args) {
    if (is.character(a) && length(a) == 1L) {
      return(a)
    }
  }
  safe_deparse(call_expr)
}

#' Upgrade constraint confidence based on cross-layer confirmation
#' @keywords internal
upgrade_confidence <- function(constraints, ma_values,
                               rd_valid_values, stop_constraints) {
  for (i in seq_along(constraints)) {
    cst <- constraints[[i]]
    param <- cst@param

    confirmed <- cst@confirmed_by
    has_ma <- param %in% names(ma_values)
    has_rd <- param %in% names(rd_valid_values)

    if (has_ma && !"source_code" %in% confirmed) {
      confirmed <- c(confirmed, "source_code")
    }
    if (has_rd && !"rd_description" %in% confirmed) {
      confirmed <- c(confirmed, "rd_description")
    }

    new_confidence <- if (length(confirmed) >= 2L) {
      "high"
    } else if (length(confirmed) == 1L) {
      "medium"
    } else {
      cst@confidence
    }

    needs_update <- !identical(confirmed, cst@confirmed_by) ||
      !identical(new_confidence, cst@confidence)
    if (needs_update) {
      constraints[[i]] <- Constraint( # nolint: object_usage_linter. S7 class in R/constraints.R
        id = cst@id,
        source = cst@source,
        type = cst@type,
        param = cst@param,
        condition = cst@condition,
        forces = cst@forces,
        requires = cst@requires,
        values = cst@values,
        incompatible = cst@incompatible,
        enabled_when = cst@enabled_when,
        message = cst@message,
        confirmed_by = confirmed,
        confidence = new_confidence
      )
    }
  }
  constraints
}

#' Merge valid values from Layer 3a match.arg into existing values
#' @keywords internal
merge_valid_values <- function(existing, new_values) {
  merged <- existing
  for (param in names(new_values)) {
    if (param %in% names(merged)) {
      merged[[param]] <- unique(c(merged[[param]], new_values[[param]]))
    } else {
      merged[[param]] <- new_values[[param]]
    }
  }
  merged
}
