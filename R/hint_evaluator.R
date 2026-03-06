#' Hint Expression Evaluator
#'
#' Evaluates `computable_hint` R expressions in a restricted sandbox
#' environment. Shared by GraphEngine (#57) and KnowledgeRetriever (#58).
#'
#' Defence-in-depth: plugin YAML is community-reviewed but we still use
#' `baseenv()` as parent (blocks `system()`, `file.*()`, etc.) and
#' `setTimeLimit()` to prevent infinite loops (ADR-0003, rule 2-4).
#'
#' @name hint_evaluator
NULL

#' Evaluate a computable_hint expression
#'
#' @param expression Character string containing an R expression
#'   (e.g. `"k < 5"`).
#' @param variables Named list of variables available for the expression.
#' @param timeout_s Maximum elapsed seconds before aborting (numeric).
#' @return `TRUE` or `FALSE` when the expression is evaluable;
#'   `NA` when variables are unavailable, the expression is malformed,
#'   or evaluation errors occur (ADR-0003 fallback trigger).
#' @export
evaluate_hint <- function(expression, variables = list(), timeout_s = 1.0) {
  if (!is.character(expression) || length(expression) != 1L) {
    return(NA)
  }
  if (nchar(trimws(expression)) == 0L) {
    return(NA)
  }

  expr <- tryCatch(
    parse(text = expression),
    error = function(e) {
      warning(
        sprintf("Hint parse error in '%s': %s", expression, conditionMessage(e)),
        call. = FALSE
      )
      NULL
    }
  )
  if (is.null(expr)) {
    return(NA)
  }

  env <- .make_hint_env(variables)

  result <- tryCatch(
    {
      setTimeLimit(elapsed = timeout_s, transient = TRUE)
      on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
      eval(expr, envir = env)
    },
    error = function(e) {
      warning(
        sprintf("Hint eval error in '%s': %s", expression, conditionMessage(e)),
        call. = FALSE
      )
      NA
    }
  )

  if (is.logical(result) && length(result) == 1L) {
    return(result)
  }

  if (is.na(result) || is.null(result)) {
    return(NA)
  }

  tryCatch(
    as.logical(result),
    error = function(e) NA,
    warning = function(w) NA
  )
}

# Allowlist of base functions safe for hint evaluation.
# Deliberately excludes system(), file.*(), download.file(), etc.
.hint_safe_fns <- c(
  # control flow
  "{", "(", "if", "return",
  # comparison
  "<", ">", "<=", ">=", "==", "!=",
  # logical
  "&&", "||", "!", "&", "|", "xor", "isTRUE", "isFALSE",
  # arithmetic
  "+", "-", "*", "/", "^", "%%", "%/%", ":", "abs", "sqrt",
  "log", "log2", "log10", "exp", "ceiling", "floor", "round",
  "min", "max", "sum", "mean", "prod",
  # type checks
  "is.na", "is.null", "is.numeric", "is.character", "is.logical",
  "is.integer", "is.double", "is.finite", "is.infinite", "is.nan",
  # coercion
  "as.numeric", "as.integer", "as.character", "as.logical", "as.double",
  # vector ops
  "length", "nchar", "c", "seq_len", "seq_along",
  # accessors
  "$", "[[", "[", "names", "nrow", "ncol", "dim",
  # NA handling
  "NA", "NA_real_", "NA_integer_", "NA_character_", "NA_complex_",
  "NULL", "TRUE", "FALSE",
  # string
  "paste", "paste0", "sprintf", "grep", "grepl", "sub", "gsub",
  "trimws", "nchar", "startsWith", "endsWith",
  # misc
  "identical", "any", "all", "which", "match", "%in%",
  "exists", "missing"
)

#' @keywords internal
.make_hint_env <- function(variables) {
  safe_env <- new.env(parent = emptyenv())
  base <- baseenv()
  for (fn_name in .hint_safe_fns) {
    obj <- tryCatch(get(fn_name, envir = base), error = function(e) NULL)
    if (!is.null(obj)) {
      assign(fn_name, obj, envir = safe_env)
    }
  }
  list2env(as.list(variables), envir = safe_env)
  safe_env
}
