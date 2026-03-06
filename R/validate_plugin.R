#' Plugin Validator
#'
#' Performs comprehensive consistency checks on a plugin's artifacts:
#' decision graph, knowledge files, constraints, and context schema
#' (ADR-0002, ADR-0005, ADR-0007).
#'
#' @name validate_plugin
#' @importFrom rlang %||%
NULL

# -- ValidationResult ---------------------------------------------------------

.valid_severity <- c("error", "warning")

#' @title ValidationResult
#' @description Collects all validation violations found by
#' [validate_plugin()]. Contains errors (must-fix) and warnings (should-fix).
#' @param errors Character vector of error messages.
#' @param warnings Character vector of warning messages.
#' @export
ValidationResult <- S7::new_class("ValidationResult",
  properties = list(
    errors = S7::new_property(S7::class_character, default = character(0)),
    warnings = S7::new_property(S7::class_character, default = character(0))
  )
)

#' Check whether a ValidationResult has any violations
#' @param result A [ValidationResult] object.
#' @return Logical: `TRUE` if there are zero errors and zero warnings.
#' @export
is_valid <- function(result) {
  if (!S7::S7_inherits(result, ValidationResult)) {
    cli::cli_abort("{.arg result} must be a {.cls ValidationResult}.")
  }
  length(result@errors) == 0L && length(result@warnings) == 0L
}

# -- Main entry point ---------------------------------------------------------

#' Validate Plugin Consistency
#'
#' Checks a plugin for internal consistency across its artifacts. All
#' violations are collected and returned — the function does not stop at the
#' first error.
#'
#' @param decision_graph A [DecisionGraph] object.
#' @param knowledge A list of [KnowledgeStore] objects (one per topic).
#' @param constraints A list of [ConstraintSet] objects (may be empty).
#' @param context_schema A [ContextSchema] object (or `NULL` to skip
#'   variable scope checks).
#' @return A [ValidationResult] object.
#' @export
validate_plugin <- function(decision_graph,
                            knowledge = list(),
                            constraints = list(),
                            context_schema = NULL) {
  if (!S7::S7_inherits(decision_graph, DecisionGraph)) { # nolint: object_usage_linter.
    cli::cli_abort("{.arg decision_graph} must be a {.cls DecisionGraph}.")
  }

  errors <- character(0)
  warnings <- character(0)

  reach <- check_reachability(decision_graph)
  errors <- c(errors, reach$errors)

  cov <- check_coverage(decision_graph, knowledge, constraints)
  errors <- c(errors, cov$errors)
  warnings <- c(warnings, cov$warnings)

  cons <- check_consistency(decision_graph, knowledge)
  errors <- c(errors, cons$errors)
  warnings <- c(warnings, cons$warnings)

  integ <- check_constraint_integrity(decision_graph, constraints)
  errors <- c(errors, integ$errors)

  if (!is.null(context_schema)) {
    scope <- check_variable_scope(
      decision_graph, knowledge, context_schema
    )
    errors <- c(errors, scope$errors)
  }

  ValidationResult(errors = errors, warnings = warnings)
}

# -- Check 1: Reachability (BFS from entry_node) -----------------------------

#' @keywords internal
check_reachability <- function(graph) {
  errors <- character(0)
  node_names <- names(graph@nodes)
  visited <- character(0)
  queue <- graph@entry_node

  while (length(queue) > 0L) {
    current <- queue[[1L]]
    queue <- queue[-1L]
    if (current %in% visited) next
    visited <- c(visited, current)

    node <- graph@nodes[[current]]
    for (tr in node@transitions) {
      if (!tr@to %in% visited) {
        queue <- c(queue, tr@to)
      }
    }
  }

  unreachable <- setdiff(node_names, visited)
  for (u in unreachable) {
    errors <- c(errors, sprintf(
      "Unreachable node: \"%s\" is not reachable from entry_node \"%s\"",
      u, graph@entry_node
    ))
  }
  list(errors = errors)
}

# -- Check 2: Coverage -------------------------------------------------------

#' @keywords internal
check_coverage <- function(graph, knowledge_list, constraints_list) {
  errors <- character(0)
  warnings <- character(0)

  graph_params <- collect_graph_parameters(graph)

  knowledge_params <- character(0)
  for (ks in knowledge_list) {
    if (S7::S7_inherits(ks, KnowledgeStore)) { # nolint: object_usage_linter.
      knowledge_params <- c(knowledge_params, ks@target_parameter)
    }
  }

  constraint_params <- character(0)
  for (cs in constraints_list) {
    if (S7::S7_inherits(cs, ConstraintSet)) { # nolint: object_usage_linter.
      for (cst in cs@constraints) {
        if (length(cst@param) > 0L) {
          constraint_params <- c(constraint_params, cst@param)
        }
      }
    }
  }

  all_params <- unique(c(knowledge_params, constraint_params))

  uncovered <- setdiff(all_params, graph_params)
  for (p in uncovered) {
    warnings <- c(warnings, sprintf(
      "Coverage: parameter \"%s\" appears in knowledge/constraints but not in any graph node",
      p
    ))
  }

  list(errors = errors, warnings = warnings)
}

#' @keywords internal
collect_graph_parameters <- function(graph) {
  params <- character(0)
  for (node in graph@nodes) {
    if (length(node@parameter) > 0L) {
      params <- c(params, node@parameter)
    }
  }
  unique(params)
}

# -- Check 3: Consistency (topics) -------------------------------------------

#' @keywords internal
check_consistency <- function(graph, knowledge_list) {
  errors <- character(0)
  warnings <- character(0)

  graph_topics <- character(0)
  for (node in graph@nodes) {
    if (length(node@topic) > 0L) {
      graph_topics <- c(graph_topics, node@topic)
    }
  }
  graph_topics <- unique(graph_topics)

  knowledge_topics <- character(0)
  for (ks in knowledge_list) {
    if (S7::S7_inherits(ks, KnowledgeStore)) { # nolint: object_usage_linter.
      knowledge_topics <- c(knowledge_topics, ks@topic)
    }
  }
  knowledge_topics <- unique(knowledge_topics)

  orphan_topics <- setdiff(knowledge_topics, graph_topics)
  for (t in orphan_topics) {
    errors <- c(errors, sprintf(
      "Consistency: knowledge topic \"%s\" does not match any graph node topic",
      t
    ))
  }

  missing_knowledge <- setdiff(graph_topics, knowledge_topics)
  for (t in missing_knowledge) {
    warnings <- c(warnings, sprintf(
      "Consistency: graph node topic \"%s\" has no corresponding knowledge file",
      t
    ))
  }

  list(errors = errors, warnings = warnings)
}

# -- Check 4: Constraint integrity -------------------------------------------

#' @keywords internal
check_constraint_integrity <- function(graph, constraints_list) {
  errors <- character(0)
  graph_params <- collect_graph_parameters(graph)

  for (cs in constraints_list) {
    if (!S7::S7_inherits(cs, ConstraintSet)) next # nolint: object_usage_linter.
    for (cst in cs@constraints) {
      referenced <- collect_constraint_params(cst)
      unknown <- setdiff(referenced, graph_params)
      for (p in unknown) {
        errors <- c(errors, sprintf(
          "Constraint integrity: constraint \"%s\" references unknown parameter \"%s\"",
          cst@id, p
        ))
      }
    }
  }
  list(errors = errors)
}

#' @keywords internal
collect_constraint_params <- function(cst) {
  params <- character(0)
  if (length(cst@param) > 0L) {
    params <- c(params, cst@param)
  }
  params <- c(params, names(cst@forces))
  params <- c(params, names(cst@requires))
  params <- c(params, names(cst@incompatible))
  unique(params)
}

# -- Check 5: Variable scope (ADR-0007) --------------------------------------

#' @keywords internal
check_variable_scope <- function(graph, knowledge_list, context_schema) {
  errors <- character(0)

  declared_vars <- list()
  for (cv in context_schema@variables) {
    declared_vars[[cv@name]] <- cv
  }

  node_order <- compute_node_order(graph)

  for (nm in names(graph@nodes)) {
    node <- graph@nodes[[nm]]
    hints <- collect_node_hints(node)
    for (hint in hints) {
      vars_used <- extract_hint_variables(hint)
      for (v in vars_used) {
        if (!v %in% names(declared_vars)) next
        cv <- declared_vars[[v]]
        err <- check_availability(cv, nm, node_order)
        if (!is.null(err)) {
          errors <- c(errors, err)
        }
      }
    }
  }

  for (ks in knowledge_list) {
    if (!S7::S7_inherits(ks, KnowledgeStore)) next # nolint: object_usage_linter.
    for (entry in ks@entries) {
      has_hint <- length(entry@computable_hint) > 0L &&
        nchar(entry@computable_hint) > 0L
      if (has_hint) {
        vars_used <- extract_hint_variables(entry@computable_hint)
        for (v in vars_used) {
          if (!v %in% names(declared_vars)) next
        }
      }
    }
  }

  list(errors = errors)
}

#' Compute topological order of graph nodes via BFS
#' @keywords internal
compute_node_order <- function(graph) {
  order_map <- list()
  visited <- character(0)
  queue <- graph@entry_node
  idx <- 1L

  while (length(queue) > 0L) {
    current <- queue[[1L]]
    queue <- queue[-1L]
    if (current %in% visited) next
    visited <- c(visited, current)
    order_map[[current]] <- idx
    idx <- idx + 1L

    node <- graph@nodes[[current]]
    for (tr in node@transitions) {
      if (!tr@to %in% visited) {
        queue <- c(queue, tr@to)
      }
    }
  }
  order_map
}

#' Collect computable_hint and skip_hint expressions from a node
#' @keywords internal
collect_node_hints <- function(node) {
  hints <- character(0)
  for (tr in node@transitions) {
    if (length(tr@computable_hint) > 0L && nchar(tr@computable_hint) > 0L) {
      hints <- c(hints, tr@computable_hint)
    }
  }
  has_skip <- length(node@policy@skip_hint) > 0L &&
    nchar(node@policy@skip_hint) > 0L
  if (has_skip) {
    hints <- c(hints, node@policy@skip_hint)
  }
  hints
}

#' Extract variable names from a hint expression string
#' @keywords internal
extract_hint_variables <- function(hint_str) {
  parsed <- tryCatch(
    parse(text = hint_str),
    error = function(e) NULL
  )
  if (is.null(parsed) || length(parsed) == 0L) {
    return(character(0))
  }
  all.vars(parsed)
}

#' Check if a context variable is available at a given node
#' @keywords internal
check_availability <- function(cv, node_name, node_order) {
  if (length(cv@depends_on_node) == 0L || nchar(cv@depends_on_node) == 0L) {
    return(NULL)
  }

  dep_node <- cv@depends_on_node

  if (!dep_node %in% names(node_order)) {
    return(NULL)
  }
  if (!node_name %in% names(node_order)) {
    return(NULL)
  }

  dep_pos <- node_order[[dep_node]]
  use_pos <- node_order[[node_name]]

  if (use_pos <= dep_pos) {
    return(sprintf(
      "Variable scope: variable \"%s\" (available after node \"%s\") used at node \"%s\" before available",
      cv@name, dep_node, node_name
    ))
  }
  NULL
}
