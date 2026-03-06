#' Knowledge Retriever
#'
#' Retrieves knowledge entries and constraints filtered by topic, parameter,
#' and context-dependent `when` conditions. Shared `evaluate_hint()` from
#' `hint_evaluator.R` handles computable_hint evaluation (ADR-0003).
#'
#' @name knowledge_retriever
#' @include hint_evaluator.R session_context.R knowledge.R constraints.R
NULL

# -- RetrievalResult S7 class --------------------------------------------------

#' @title RetrievalResult
#' @description Result of a knowledge + constraint retrieval operation.
#' Contains filtered entries, their IDs for audit logging (ADR-0006),
#' and applicable constraints.
#' @param entries List of [KnowledgeEntry] objects matching the query.
#' @param entry_ids_presented Character vector of entry IDs (for audit log).
#' @param constraints List of [Constraint] objects applicable to the context.
#' @export
RetrievalResult <- S7::new_class("RetrievalResult",
  properties = list(
    entries = S7::new_property(S7::class_list, default = list()),
    entry_ids_presented = S7::new_property(
      S7::class_character,
      default = character(0)
    ),
    constraints = S7::new_property(S7::class_list, default = list())
  ),
  validator = function(self) {
    for (i in seq_along(self@entries)) {
      if (!S7::S7_inherits(self@entries[[i]], KnowledgeEntry)) {
        return(sprintf("entries[[%d]] must be a KnowledgeEntry", i))
      }
    }
    for (i in seq_along(self@constraints)) {
      if (!S7::S7_inherits(self@constraints[[i]], Constraint)) {
        return(sprintf("constraints[[%d]] must be a Constraint", i))
      }
    }
    n_entries <- length(self@entries)
    n_ids <- length(self@entry_ids_presented)
    if (n_ids != n_entries) {
      return(sprintf(
        "`entry_ids_presented` length (%d) must match `entries` length (%d)",
        n_ids, n_entries
      ))
    }
    NULL
  }
)

# -- Knowledge retrieval -------------------------------------------------------

#' Retrieve knowledge entries for a topic
#'
#' Filters entries from one or more [KnowledgeStore] objects by topic,
#' then evaluates `when` conditions using the current [SessionContext].
#' Entries with a `when` but no `computable_hint` are always included
#' (the LLM will judge at runtime).
#'
#' @param stores List of [KnowledgeStore] objects to search.
#' @param topic Character string identifying the decision topic.
#' @param context A [SessionContext] object providing hint variables.
#' @return A [RetrievalResult] with matching entries and their IDs.
#' @export
retrieve_knowledge <- function(stores, topic, context) {
  if (!is.list(stores)) {
    cli::cli_abort("{.arg stores} must be a list of KnowledgeStore objects.")
  }
  if (!is.character(topic) || length(topic) != 1L) {
    cli::cli_abort("{.arg topic} must be a single character string.")
  }
  # nolint next: object_usage_linter. S7 class in R/session_context.R
  if (!S7::S7_inherits(context, SessionContext)) {
    cli::cli_abort("{.arg context} must be a {.cls SessionContext}.")
  }

  # nolint next: object_usage_linter. get_hint_variables in session_context.R
  vars <- get_hint_variables(context)
  matched <- list()
  seen_ids <- character(0)

  for (store in stores) {
    # nolint next: object_usage_linter. S7 class in R/knowledge.R
    if (!S7::S7_inherits(store, KnowledgeStore)) {
      cli::cli_abort("Each element of {.arg stores} must be a KnowledgeStore.")
    }
    if (store@topic != topic) next

    for (entry in store@entries) {
      if (entry@id %in% seen_ids) next
      if (.entry_applicable(entry, vars)) {
        matched <- c(matched, list(entry))
        seen_ids <- c(seen_ids, entry@id)
      }
    }
  }

  RetrievalResult(
    entries = matched,
    entry_ids_presented = seen_ids,
    constraints = list()
  )
}

# -- Constraint retrieval ------------------------------------------------------

#' Retrieve constraints for a parameter
#'
#' Filters constraints from [ConstraintSet] objects by parameter name.
#' Constraints with an `enabled_when` condition are evaluated against the
#' current context; those that evaluate to FALSE are excluded.
#'
#' @param constraint_sets List of [ConstraintSet] objects to search.
#' @param parameter Character string identifying the target parameter.
#' @param context A [SessionContext] object providing hint variables.
#' @return A list of applicable [Constraint] objects.
#' @export
retrieve_constraints <- function(constraint_sets, parameter, context) {
  if (!is.list(constraint_sets)) {
    cli::cli_abort(
      "{.arg constraint_sets} must be a list of ConstraintSet objects."
    )
  }
  if (!is.character(parameter) || length(parameter) != 1L) {
    cli::cli_abort("{.arg parameter} must be a single character string.")
  }
  # nolint next: object_usage_linter. S7 class in R/session_context.R
  if (!S7::S7_inherits(context, SessionContext)) {
    cli::cli_abort("{.arg context} must be a {.cls SessionContext}.")
  }

  # nolint next: object_usage_linter. get_hint_variables in session_context.R
  vars <- get_hint_variables(context)
  result <- list()

  for (cs in constraint_sets) {
    # nolint next: object_usage_linter. S7 class in R/constraints.R
    if (!S7::S7_inherits(cs, ConstraintSet)) {
      cli::cli_abort(
        "Each element of {.arg constraint_sets} must be a ConstraintSet."
      )
    }
    for (cst in cs@constraints) {
      if (!.constraint_matches_param(cst, parameter)) next
      if (!.constraint_enabled(cst, vars)) next
      result <- c(result, list(cst))
    }
  }

  result
}

# -- Internal helpers ----------------------------------------------------------

#' @keywords internal
.entry_applicable <- function(entry, vars) {
  hint <- entry@computable_hint
  has_hint <- length(hint) == 1L && nchar(hint) > 0L

  if (!has_hint) {
    return(TRUE)
  }

  # nolint next: object_usage_linter. evaluate_hint in hint_evaluator.R
  result <- suppressWarnings(evaluate_hint(hint, variables = vars))
  if (is.na(result)) {
    return(TRUE)
  }
  isTRUE(result)
}

#' @keywords internal
.constraint_matches_param <- function(cst, parameter) {
  param <- cst@param
  if (length(param) == 1L && nchar(param) > 0L) {
    return(param == parameter)
  }
  TRUE
}

#' @keywords internal
.constraint_enabled <- function(cst, vars) {
  ew <- cst@enabled_when
  if (length(ew) == 0L || nchar(ew) == 0L) {
    return(TRUE)
  }

  # nolint next: object_usage_linter. evaluate_hint in hint_evaluator.R
  result <- suppressWarnings(evaluate_hint(ew, variables = vars))
  if (is.na(result)) {
    return(TRUE)
  }
  isTRUE(result)
}
