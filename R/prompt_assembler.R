#' Prompt Assembler
#'
#' Pure function that constructs prompt strings from knowledge entries,
#' constraints, context, and transition queries. Does NOT call the LLM —
#' the caller (REPL #62) handles invocation.
#'
#' @name prompt_assembler
#' @include knowledge_retriever.R graph_engine.R
NULL

# -- PromptResult S7 class -----------------------------------------------------

#' @title PromptResult
#' @description Result of prompt assembly for a single node.
#' @param prompt_text Assembled prompt string (character).
#' @param entry_ids_presented Knowledge entry IDs included (character vector).
#' @param node_type Type of the node being processed (character).
#' @param includes_transition_query Whether the prompt asks the LLM to choose
#'   a transition (logical).
#' @export
PromptResult <- S7::new_class("PromptResult",
  properties = list(
    prompt_text = S7::class_character,
    entry_ids_presented = S7::new_property(
      S7::class_character,
      default = character(0)
    ),
    node_type = S7::class_character,
    includes_transition_query = S7::new_property(
      S7::class_logical,
      default = FALSE
    )
  ),
  validator = function(self) {
    if (length(self@prompt_text) != 1L) {
      return("`prompt_text` must be a single string")
    }
    valid_types <- c("decision", "diagnosis", "execution", "context_gathering")
    if (length(self@node_type) != 1L || !self@node_type %in% valid_types) {
      return(sprintf(
        "`node_type` must be one of: %s",
        paste(dQuote(valid_types, FALSE), collapse = ", ")
      ))
    }
    if (length(self@includes_transition_query) != 1L) {
      return("`includes_transition_query` must be a single logical")
    }
    NULL
  }
)

# -- assemble_runtime_prompt ---------------------------------------------------

#' Assemble a runtime prompt for a node
#'
#' Combines knowledge entries, constraints, context state, and transition
#' candidates into a structured prompt string for LLM consumption.
#'
#' @param node A `Node` S7 object from the decision graph.
#' @param retrieval_result A [RetrievalResult] S7 object from the retriever.
#' @param context A [SessionContext] S7 object.
#' @param transition_trace Optional [TransitionTrace] S7 object. When present
#'   and candidates include `needs_llm` items, a transition query is appended.
#' @return A [PromptResult] S7 object.
#' @export
assemble_runtime_prompt <- function(node, retrieval_result, context,
                                    transition_trace = NULL) {
  node_type <- node@type
  topic <- node@topic
  param <- node@parameter

  sections <- character(0)

  sections <- c(sections, .build_header(node_type, topic, param))
  sections <- c(sections, .build_knowledge_section(retrieval_result))
  sections <- c(sections, .build_constraints_section(retrieval_result))
  sections <- c(sections, .build_context_section(context, param))

  has_query <- FALSE
  if (!is.null(transition_trace)) {
    tq <- .build_transition_query(transition_trace)
    if (nchar(tq) > 0L) {
      sections <- c(sections, tq)
      has_query <- TRUE
    }
  }

  sections <- c(sections, .build_node_type_section(node_type, param))

  PromptResult(
    prompt_text = paste(sections[nchar(sections) > 0L], collapse = "\n\n"),
    entry_ids_presented = retrieval_result@entry_ids_presented,
    node_type = node_type,
    includes_transition_query = has_query
  )
}

# -- Internal: section builders ------------------------------------------------

#' @keywords internal
.build_header <- function(node_type, topic, parameter) {
  parts <- sprintf("## Node: %s", topic)
  if (nchar(parameter) > 0L) {
    parts <- paste0(parts, sprintf(" (parameter: `%s`)", parameter))
  }
  parts <- paste0(parts, sprintf("\nType: %s", node_type))
  parts
}

#' @keywords internal
.build_knowledge_section <- function(retrieval_result) {
  entries <- retrieval_result@entries
  if (length(entries) == 0L) {
    return("")
  }

  lines <- "## Knowledge"
  for (entry in entries) {
    lines <- c(lines, sprintf(
      "\n### %s\n- When: %s\n- %s",
      entry@id, entry@when,
      paste(entry@properties, collapse = "\n- ")
    ))
  }
  paste(lines, collapse = "\n")
}

#' @keywords internal
.build_constraints_section <- function(retrieval_result) {
  constraints <- retrieval_result@constraints
  if (length(constraints) == 0L) {
    return("")
  }

  lines <- "## Constraints"
  for (cst in constraints) {
    msg <- if (length(cst@message) == 1L && nchar(cst@message) > 0L) {
      cst@message
    } else {
      sprintf("type=%s, param=%s", cst@type, cst@param)
    }
    lines <- c(lines, sprintf("- [%s] %s", cst@id, msg))
  }
  paste(lines, collapse = "\n")
}

#' @keywords internal
.build_context_section <- function(context, parameter) {
  vars <- context@variables
  params <- context@parameters_decided
  if (length(vars) == 0L && length(params) == 0L) {
    return("")
  }

  lines <- "## Current Context"
  if (length(params) > 0L) {
    lines <- c(lines, "Decided parameters:")
    for (nm in names(params)) {
      lines <- c(lines, sprintf("- %s = %s", nm, as.character(params[[nm]])))
    }
  }
  if (length(vars) > 0L) {
    lines <- c(lines, "Available variables:")
    for (nm in names(vars)) {
      lines <- c(lines, sprintf("- %s = %s", nm, as.character(vars[[nm]])))
    }
  }
  paste(lines, collapse = "\n")
}

#' @keywords internal
.build_transition_query <- function(transition_trace) {
  candidates <- transition_trace@candidates
  needs_llm <- vapply(candidates, function(c) {
    isTRUE(c@fallback_to_llm)
  }, logical(1))

  if (!any(needs_llm)) {
    return("")
  }

  llm_candidates <- candidates[needs_llm]
  lines <- "## Transition Decision Required"
  lines <- c(lines, "Choose the most appropriate next step:")
  for (i in seq_along(llm_candidates)) {
    cand <- llm_candidates[[i]]
    when_text <- if (length(cand@when) == 1L && nchar(cand@when) > 0L) {
      cand@when
    } else {
      "(no condition)"
    }
    lines <- c(lines, sprintf("%d. Go to `%s` — when: %s", i, cand@to, when_text))
  }
  lines <- c(
    lines,
    "\nRespond with the number of your choice and a brief justification."
  )
  paste(lines, collapse = "\n")
}

#' @keywords internal
.build_node_type_section <- function(node_type, parameter) {
  switch(node_type,
    decision = sprintf(
      "## Task\nDecide the value for parameter `%s` based on the knowledge and context above.",
      parameter
    ),
    execution = "## Task\nGenerate R code to execute the analysis based on the decided parameters.",
    diagnosis = "## Task\nDiagnose the analysis results and determine if adjustments are needed.",
    context_gathering = "## Task\nDescribe the data and gather necessary context for the analysis.",
    ""
  )
}
