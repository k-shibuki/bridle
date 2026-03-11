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
#' Assembles a prompt from scan data and optional references,
#' sends it to an LLM via ellmer, and writes draft YAML files to
#' the specified output directory. Accepts either a [ScanResult]
#' (single function) or a [PackageScanResult] (full package).
#'
#' In addition to the three LLM-generated sections (decision graph,
#' knowledge, constraints), this function generates `context_schema.yaml`
#' and `manifest.yaml` heuristically from the decision graph structure.
#'
#' @param scan_result A [ScanResult] or [PackageScanResult] object.
#' @param references Optional list of reference metadata from
#'   [fetch_references()].
#' @param provider LLM provider name for ellmer (character), e.g.
#'   `"anthropic"`, `"openai"`. If `NULL`, uses ellmer default.
#' @param model Model name (character). If `NULL`, uses provider default.
#' @param output_dir Directory to write draft YAML files (character).
#' @return A list with `decision_graph`, `knowledge`, `constraints`,
#'   `context_schema`, and `manifest` elements.
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
  is_pkg_result <- S7::S7_inherits(scan_result, PackageScanResult) # nolint: object_usage_linter. S7 in scan_result.R
  label <- if (is_pkg_result) {
    scan_result@package
  } else {
    scan_result@func
  }

  drafts$context_schema <- generate_draft_context_schema(drafts)
  drafts$manifest <- generate_draft_manifest(drafts)

  write_draft_files(drafts, output_dir, scan_result@package, label)
  drafts
}

#' Send a prompt to an LLM via ellmer (mockable wrapper)
#'
#' Uses `resolve_chat_provider()` from `llm_utils.R` to select the
#' correct provider-specific constructor and inject credentials.
#' @keywords internal
bridle_chat <- function(prompt, provider = NULL, model = NULL) {
  rlang::check_installed("ellmer", reason = "for AI drafting")

  sys_prompt <- paste(
    "You are an expert R statistical methodology consultant.",
    "Generate YAML content for a bridle knowledge plugin.",
    "Output ONLY valid YAML, no markdown fences or commentary."
  )

  resolved <- resolve_chat_provider( # nolint: object_usage_linter. function defined in R/llm_utils.R
    provider, model,
    extra_args = list(system_prompt = sys_prompt, echo = "none")
  )

  chat_obj <- do.call(resolved$constructor_fn, resolved$args)
  chat_obj$chat(prompt)
}

#' Assemble the draft prompt from scan data and references
#' @keywords internal
assemble_draft_prompt <- function(scan_result, references = NULL) {
  is_pkg <- S7::S7_inherits(scan_result, PackageScanResult) # nolint: object_usage_linter. S7 class in scan_result.R
  if (is_pkg) {
    return(assemble_package_prompt(scan_result, references))
  }
  assemble_function_prompt(scan_result, references)
}

#' Assemble prompt for a single ScanResult
#' @keywords internal
assemble_function_prompt <- function(scan_result, references = NULL) {
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

  parts <- c(parts, format_references_prompt(references))
  parts <- c(parts, format_task_prompt())

  paste(parts, collapse = "\n")
}

#' Assemble prompt for a PackageScanResult (multi-function)
#' @keywords internal
assemble_package_prompt <- function(pkg_result, references = NULL) {
  parts <- character(0)
  parts <- c(parts, sprintf("Package: %s\n", pkg_result@package))

  roles <- pkg_result@function_roles
  analysis_fns <- names(roles[roles == "analysis"])
  parts <- c(parts, sprintf(
    "Analysis functions: %s\n", paste(analysis_fns, collapse = ", ")
  ))

  if (length(pkg_result@function_families) > 0L) {
    parts <- c(parts, "\n## Function Families\n")
    for (fam in pkg_result@function_families) {
      parts <- c(parts, sprintf(
        "- %s family: common params (%s), members: %s",
        fam$name,
        paste(fam$common_parameters, collapse = ", "),
        paste(names(fam$members), collapse = ", ")
      ))
    }
  }

  if (length(pkg_result@cross_function_constraints) > 0L) {
    parts <- c(parts, "\n## Cross-Function Constraints\n")
    for (cfc in pkg_result@cross_function_constraints) {
      parts <- c(parts, sprintf("- %s: %s", cfc$function_name, cfc$reason))
    }
  }

  for (fn_name in names(pkg_result@functions)) {
    sr <- pkg_result@functions[[fn_name]]
    parts <- c(parts, sprintf("\n## Function: %s\n", fn_name))

    stat_params <- Filter(
      function(p) p@classification == "statistical_decision",
      sr@parameters
    )
    if (length(stat_params) > 0L) {
      parts <- c(parts, "Key parameters:")
      for (p in stat_params) {
        default_info <- if (p@has_default) {
          sprintf(" (default: %s)", p@default_expression)
        } else {
          ""
        }
        parts <- c(parts, sprintf("- %s%s", p@name, default_info))
      }
    }

    if (length(sr@valid_values) > 0L) {
      parts <- c(parts, "Valid values:")
      for (nm in names(sr@valid_values)) {
        parts <- c(parts, sprintf(
          "- %s: %s", nm, paste(sr@valid_values[[nm]], collapse = ", ")
        ))
      }
    }
  }

  parts <- c(parts, format_references_prompt(references))
  parts <- c(parts, format_task_prompt())

  paste(parts, collapse = "\n")
}

#' Format references section for prompt
#' @keywords internal
format_references_prompt <- function(references) {
  if (is.null(references) || length(references) == 0L) {
    return(character(0))
  }
  parts <- "\n## References\n"
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
  parts
}

#' Format task instruction for prompt
#' @keywords internal
format_task_prompt <- function() {
  c(
    "\n## Task\n",
    paste(
      "Generate a bridle knowledge plugin with three YAML sections",
      "separated by '---':\n",
      "1. decision_graph: A decision flow with nodes and transitions.\n",
      "2. knowledge: Knowledge entries with when/properties/references.\n",
      "3. constraints: Technical constraints for parameter validation."
    )
  )
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

#' Generate context_schema from graph structure (heuristic)
#'
#' Derives [ContextVariable] definitions from the decision graph's node
#' types: `decision` nodes with `parameter` yield `parameter_decided`
#' variables; `execution` nodes yield a `post_fit` variable.
#' A baseline `data_loaded` variable (`k`) is always included.
#'
#' Handles both named-map and sequence-form node lists. For unnamed
#' nodes, falls back to the `id` field or a positional name.
#' Only the first `execution` node generates a `fit_result` variable
#' to avoid duplicate names in the schema.
#' @keywords internal
generate_draft_context_schema <- function(drafts) {
  graph_raw <- drafts$decision_graph
  nodes_raw <- graph_raw[["graph"]][["nodes"]] %||% graph_raw[["nodes"]]
  if (is.null(nodes_raw) || length(nodes_raw) == 0L) {
    return(NULL)
  }

  variables <- list(list(
    name = "k",
    description = "number of studies",
    available_from = "data_loaded",
    source_expression = "nrow(data)"
  ))

  node_names <- names(nodes_raw)
  has_execution <- FALSE

  for (idx in seq_along(nodes_raw)) {
    node <- nodes_raw[[idx]]
    nm <- node_names[[idx]] %||% node[["id"]] %||% paste0("node_", idx)
    node_type <- node[["type"]]

    if (identical(node_type, "decision") && !is.null(node[["parameter"]])) {
      params <- node[["parameter"]]
      if (is.list(params)) params <- unlist(params)
      for (p in params) {
        variables <- c(variables, list(list(
          name = p,
          description = sprintf("selected %s", gsub("_", " ", p)),
          available_from = "parameter_decided",
          depends_on_node = nm,
          source_expression = sprintf("decisions$%s", p)
        )))
      }
    }

    if (identical(node_type, "execution") && !has_execution) {
      has_execution <- TRUE
      variables <- c(variables, list(list(
        name = "fit_result",
        description = "fitted model result object",
        available_from = "post_fit",
        depends_on_node = nm,
        source_expression = "result"
      )))
    }
  }

  list(variables = variables)
}

#' Generate manifest with sensible defaults
#'
#' Extracts `max_iterations` from the draft graph's `global_policy` if
#' present. Falls back to `10L`, matching the runtime default in
#' `graph_engine.R` (`.default_max_iterations`). Non-numeric or
#' non-whole-number values are silently replaced by the default.
#' @keywords internal
generate_draft_manifest <- function(drafts) {
  graph_raw <- drafts$decision_graph
  gp <- graph_raw[["graph"]][["global_policy"]] %||%
    graph_raw[["global_policy"]]
  raw <- gp[["max_iterations"]]
  max_iter <- if (
    !is.null(raw) &&
      length(raw) == 1L &&
      !is.na(raw) &&
      is.numeric(raw) &&
      raw == floor(raw)
  ) {
    as.integer(raw)
  } else {
    10L
  }
  list(policy_defaults = list(max_iterations = max_iter))
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

  if (!is.null(drafts$context_schema)) {
    cs_path <- file.path(output_dir, "context_schema.yaml")
    yaml::write_yaml(drafts$context_schema, cs_path)
    cli::cli_inform("Draft context schema: {.path {cs_path}}")
  }

  if (!is.null(drafts$manifest)) {
    manifest_path <- file.path(output_dir, "manifest.yaml")
    yaml::write_yaml(drafts$manifest, manifest_path)
    cli::cli_inform("Draft manifest: {.path {manifest_path}}")
  }
}
