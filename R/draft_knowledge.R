#' Draft Knowledge Plugin Artifacts
#'
#' Uses ellmer to generate draft plugin artifacts (decision graph,
#' knowledge entries, technical constraints) from a [ScanResult] and
#' fetched references.
#'
#' @name draft_knowledge
#' @importFrom rlang %||%
NULL

#' Draft Knowledge Plugin Artifacts
#'
#' Assembles a prompt from [ScanResult] data and optional references,
#' sends it to an LLM via ellmer, and writes draft YAML files to
#' the specified output directory.
#'
#' @param scan_result A [ScanResult] object.
#' @param references Optional list of reference metadata from
#'   [fetch_references()].
#' @param provider LLM provider name for ellmer (character), e.g.
#'   `"anthropic"`, `"openai"`. If `NULL`, uses ellmer default.
#' @param model Model name (character). If `NULL`, uses provider default.
#' @param output_dir Directory to write draft YAML files (character).
#' @return A list with `decision_graph`, `knowledge`, and `constraints`
#'   elements containing the parsed draft content.
#' @export
draft_knowledge <- function(scan_result, references = NULL,
                            provider = NULL, model = NULL,
                            output_dir = ".") {
  prompt <- assemble_draft_prompt(scan_result, references)

  response <- tryCatch(
    bridle_chat(prompt, provider = provider, model = model),
    error = function(e) {
      cli::cli_abort(
        "LLM drafting failed: {conditionMessage(e)}",
        parent = e
      )
    }
  )

  drafts <- parse_draft_response(response)
  write_draft_files(drafts, output_dir, scan_result@package, scan_result@func)
  drafts
}

#' Send a prompt to an LLM via ellmer (mockable wrapper)
#' @keywords internal
bridle_chat <- function(prompt, provider = NULL, model = NULL) {
  rlang::check_installed("ellmer", reason = "for AI drafting")
  args <- list()
  if (!is.null(provider)) args[["name"]] <- provider
  if (!is.null(model)) args[["model"]] <- model
  args[["system_prompt"]] <- paste(
    "You are an expert R statistical methodology consultant.",
    "Generate YAML content for a bridle knowledge plugin.",
    "Output ONLY valid YAML, no markdown fences or commentary."
  )
  args[["echo"]] <- "none"
  chat_fn <- utils::getFromNamespace("chat", "ellmer")
  chat_obj <- do.call(chat_fn, args)
  chat_obj$chat(prompt)
}

#' Assemble the draft prompt from ScanResult and references
#' @keywords internal
assemble_draft_prompt <- function(scan_result, references = NULL) {
  parts <- character(0)

  parts <- c(parts, sprintf(
    "Package: %s\nFunction: %s\n",
    scan_result@package, scan_result@func
  ))

  parts <- c(parts, "## Parameters\n")
  for (p in scan_result@parameters) {
    default_info <- if (p@has_default) {
      sprintf(" (default: %s)", p@default_expression)
    } else {
      " (no default)"
    }
    parts <- c(parts, sprintf(
      "- %s [%s]%s", p@name, p@classification, default_info
    ))
  }

  if (length(scan_result@dependency_graph) > 0L) {
    parts <- c(parts, "\n## Dependencies\n")
    for (nm in names(scan_result@dependency_graph)) {
      deps <- paste(scan_result@dependency_graph[[nm]], collapse = ", ")
      parts <- c(parts, sprintf("- %s depends on: %s", nm, deps))
    }
  }

  if (length(scan_result@valid_values) > 0L) {
    parts <- c(parts, "\n## Valid Values\n")
    for (nm in names(scan_result@valid_values)) {
      vals <- paste(scan_result@valid_values[[nm]], collapse = ", ")
      parts <- c(parts, sprintf("- %s: %s", nm, vals))
    }
  }

  if (length(scan_result@constraints) > 0L) {
    parts <- c(parts, "\n## Known Constraints\n")
    for (cst in scan_result@constraints) {
      parts <- c(parts, sprintf(
        "- [%s] %s: %s (confidence: %s)",
        cst@type, cst@param, cst@message, cst@confidence
      ))
    }
  }

  if (!is.null(references) && length(references) > 0L) {
    parts <- c(parts, "\n## References\n")
    for (ref in references) {
      authors <- paste(ref$authors, collapse = ", ")
      parts <- c(parts, sprintf(
        "- %s (%s). %s. %s",
        authors, ref$year %||% "n.d.", ref$title, ref$journal %||% ""
      ))
      if (nchar(ref$abstract %||% "") > 0L) {
        parts <- c(parts, sprintf("  Abstract: %s", ref$abstract))
      }
    }
  }

  parts <- c(parts, "\n## Task\n")
  parts <- c(parts, paste(
    "Generate a bridle knowledge plugin with three YAML sections",
    "separated by '---':\n",
    "1. decision_graph: A decision flow with nodes and transitions.\n",
    "2. knowledge: Knowledge entries with when/properties/references.\n",
    "3. constraints: Technical constraints for parameter validation."
  ))

  paste(parts, collapse = "\n")
}

#' Parse the LLM response into structured draft content
#' @keywords internal
parse_draft_response <- function(response) {
  sections <- strsplit(response, "---")[[1L]]
  sections <- trimws(sections)
  sections <- sections[nchar(sections) > 0L]

  decision_graph <- if (length(sections) >= 1L) {
    tryCatch(yaml::yaml.load(sections[[1L]]), error = function(e) list())
  } else {
    list()
  }

  knowledge <- if (length(sections) >= 2L) {
    tryCatch(yaml::yaml.load(sections[[2L]]), error = function(e) list())
  } else {
    list()
  }

  constraints <- if (length(sections) >= 3L) {
    tryCatch(yaml::yaml.load(sections[[3L]]), error = function(e) list())
  } else {
    list()
  }

  list(
    decision_graph = decision_graph,
    knowledge = knowledge,
    constraints = constraints
  )
}

#' Write draft YAML files to the output directory
#' @keywords internal
write_draft_files <- function(drafts, output_dir, package, func) {
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  graph_path <- file.path(output_dir, "decision_graph.yaml")
  yaml::write_yaml(drafts$decision_graph, graph_path)
  cli::cli_inform("Draft decision graph: {.path {graph_path}}")

  knowledge_dir <- file.path(output_dir, "knowledge")
  if (!dir.exists(knowledge_dir)) {
    dir.create(knowledge_dir, recursive = TRUE)
  }
  knowledge_path <- file.path(knowledge_dir, paste0(func, ".yaml"))
  yaml::write_yaml(drafts$knowledge, knowledge_path)
  cli::cli_inform("Draft knowledge: {.path {knowledge_path}}")

  constraints_dir <- file.path(output_dir, "constraints")
  if (!dir.exists(constraints_dir)) {
    dir.create(constraints_dir, recursive = TRUE)
  }
  constraints_path <- file.path(constraints_dir, "technical.yaml")
  yaml::write_yaml(drafts$constraints, constraints_path)
  cli::cli_inform("Draft constraints: {.path {constraints_path}}")
}
