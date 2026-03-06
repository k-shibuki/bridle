#' Code Sandbox
#'
#' Safe evaluation of LLM-generated R code in execution nodes. Uses a
#' restricted environment (`baseenv()` parent) with approved packages
#' injected and `setTimeLimit()` timeout enforcement.
#'
#' Mirrors `evaluate_hint()` design (ADR-0003) but supports multi-line code
#' that may produce data.frames, model objects, or console output.
#'
#' @name code_sandbox
#' @include context_schema.R session_context.R
NULL

# -- CodeSandbox S7 class ------------------------------------------------------

.default_allowed_packages <- c(
  "base", "stats", "utils", "meta", "metafor", "dplyr"
)

#' @title CodeSandbox
#' @description Configuration for safe R code evaluation.
#' @param allowed_packages Character vector of package names whose exports
#'   are available inside the sandbox.
#' @param timeout_s Maximum elapsed seconds before aborting (numeric).
#' @param max_memory_mb Memory limit in MB (numeric or NULL). Currently
#'   documented only; R's `setTimeLimit` does not enforce memory.
#' @export
CodeSandbox <- S7::new_class("CodeSandbox",
  properties = list(
    allowed_packages = S7::new_property(
      S7::class_character,
      default = .default_allowed_packages
    ),
    timeout_s = S7::new_property(S7::class_double, default = 10.0),
    max_memory_mb = S7::new_property(S7::class_any, default = NULL)
  ),
  validator = function(self) {
    if (length(self@allowed_packages) == 0L) {
      return("`allowed_packages` must contain at least one package name")
    }
    if (length(self@timeout_s) != 1L || self@timeout_s <= 0) {
      return("`timeout_s` must be a positive number")
    }
    mm <- self@max_memory_mb
    if (!is.null(mm)) {
      if (!is.numeric(mm) || length(mm) != 1L || mm <= 0) {
        return("`max_memory_mb` must be a positive number or NULL")
      }
    }
    NULL
  }
)

# -- CodeResult S7 class -------------------------------------------------------

#' @title CodeResult
#' @description Result of sandboxed code evaluation.
#' @param success Logical: `TRUE` if evaluation completed without error.
#' @param value The returned object (any type).
#' @param output Captured stdout as a single character string.
#' @param error Error message (character) or NULL if successful.
#' @param warnings Character vector of warning messages.
#' @param elapsed_s Elapsed wall-clock seconds (numeric).
#' @export
CodeResult <- S7::new_class("CodeResult",
  properties = list(
    success = S7::class_logical,
    value = S7::class_any,
    output = S7::new_property(S7::class_character, default = ""),
    error = S7::new_property(S7::class_any, default = NULL),
    warnings = S7::new_property(S7::class_character, default = character(0)),
    elapsed_s = S7::new_property(S7::class_double, default = 0.0)
  ),
  validator = function(self) {
    if (length(self@success) != 1L) {
      return("`success` must be a single logical value")
    }
    if (!is.null(self@error) && !is.character(self@error)) {
      return("`error` must be a character string or NULL")
    }
    if (length(self@elapsed_s) != 1L || self@elapsed_s < 0) {
      return("`elapsed_s` must be a non-negative number")
    }
    NULL
  }
)

# -- Blocked function names ----------------------------------------------------

.blocked_fns <- c(
  "system", "system2", "shell", "shell.exec",
  "file.create", "file.remove", "file.rename", "file.copy",
  "file.append", "file.symlink", "file.link",
  "unlink", "writeLines", "writeChar", "writeBin",
  "download.file", "url", "socketConnection",
  "Sys.setenv", "Sys.unsetenv",
  "q", "quit", "invokeRestart",
  "library", "require", "loadNamespace", "attachNamespace",
  "source", "sys.source"
)

# -- bridle_eval_code ----------------------------------------------------------

#' Evaluate R code in a restricted sandbox
#'
#' Parses and evaluates `code` in an isolated environment where only
#' functions from `sandbox@allowed_packages` are available. Dangerous
#' operations (file I/O, networking, system calls) are blocked.
#'
#' @param code Character string of R code to evaluate.
#' @param sandbox A [CodeSandbox] configuration object.
#' @param data Optional data.frame to make available as `data` inside the
#'   sandbox.
#' @param parameters Optional named list of decided parameters, available
#'   as `parameters` inside the sandbox.
#' @return A [CodeResult] S7 object.
#' @export
bridle_eval_code <- function(code, sandbox, data = NULL, parameters = NULL) {
  if (!is.character(code) || length(code) != 1L) {
    cli::cli_abort("{.arg code} must be a single character string.")
  }
  if (!S7::S7_inherits(sandbox, CodeSandbox)) {
    cli::cli_abort("{.arg sandbox} must be a {.cls CodeSandbox}.")
  }

  if (nchar(trimws(code)) == 0L) {
    return(CodeResult(success = TRUE, value = NULL, elapsed_s = 0.0))
  }

  parsed <- tryCatch(
    parse(text = code),
    error = function(e) {
      CodeResult(
        success = FALSE, value = NULL,
        error = paste("parse error:", conditionMessage(e)),
        elapsed_s = 0.0
      )
    }
  )
  if (S7::S7_inherits(parsed, CodeResult)) {
    return(parsed)
  }

  env <- .make_sandbox_env(sandbox, data, parameters)

  warns <- character(0)
  start_time <- proc.time()[["elapsed"]]

  result <- tryCatch(
    withCallingHandlers(
      {
        setTimeLimit(elapsed = sandbox@timeout_s, transient = TRUE)
        on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
        captured <- utils::capture.output(val <- eval(parsed, envir = env))
        list(value = val, output = paste(captured, collapse = "\n"))
      },
      warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("elapsed time limit|time limit", msg, ignore.case = TRUE)) {
        msg <- "timeout: code exceeded time limit"
      }
      list(error = msg)
    }
  )

  elapsed <- proc.time()[["elapsed"]] - start_time

  if (!is.null(result$error)) {
    return(CodeResult(
      success = FALSE, value = NULL,
      error = result$error, warnings = warns, elapsed_s = elapsed
    ))
  }

  CodeResult(
    success = TRUE,
    value = result$value,
    output = result$output %||% "",
    warnings = warns,
    elapsed_s = elapsed
  )
}

# -- Internal: build sandbox environment ---------------------------------------

#' @keywords internal
.make_sandbox_env <- function(sandbox, data, parameters) {
  env <- new.env(parent = baseenv())

  for (fn_name in .blocked_fns) {
    blocked_msg <- sprintf("blocked: %s() is not allowed in sandbox", fn_name)
    assign(fn_name, .make_blocker(blocked_msg), envir = env)
  }

  for (pkg_name in sandbox@allowed_packages) {
    if (!requireNamespace(pkg_name, quietly = TRUE)) next
    ns <- asNamespace(pkg_name)
    exports <- getNamespaceExports(ns)
    for (ex in exports) {
      if (ex %in% .blocked_fns) next
      obj <- tryCatch(get(ex, envir = ns), error = function(e) NULL)
      if (!is.null(obj) && is.function(obj)) {
        assign(ex, obj, envir = env)
      }
    }
  }

  if (!is.null(data)) env$data <- data
  if (!is.null(parameters)) env$parameters <- parameters

  env
}

#' @keywords internal
.make_blocker <- function(msg) {
  force(msg)
  function(...) stop(msg, call. = FALSE)
}
