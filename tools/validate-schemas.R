#!/usr/bin/env Rscript
# tools/validate-schemas.R -- Lightweight YAML schema checker
#
# Phase A: syntax + top-level structure only.
# After WP3b (S7 validators), this script delegates to S7 constructors.
#
# Usage: Rscript tools/validate-schemas.R [--json]
# Exit code: 0 = all OK, 1 = errors found

args <- commandArgs(trailingOnly = TRUE)
json_mode <- "--json" %in% args

schemas_dir <- "docs/schemas"

# Schema files in docs/schemas/ are *definitions* (meta-schemas), not instances.
# They all have a top-level `schema` key containing version + structure definition.
# Instance-level keys (graph, topic, constraints, ...) live under schema.
schema_rules <- list(
  decision_graph = list(pattern = "decision_graph", keys = "schema", nested = "graph"),
  knowledge      = list(pattern = "knowledge",      keys = "schema", nested = "topic"),
  constraints    = list(pattern = "constraints",     keys = "schema", nested = NULL),
  context_schema = list(pattern = "context_schema",  keys = "schema", nested = "variables"),
  decision_log   = list(pattern = "decision_log",    keys = "schema", nested = NULL)
)

errors <- list()
checked <- 0L

add_error <- function(file, message) {
  errors[[length(errors) + 1L]] <<- list(file = file, message = message)
}

# Discover schema files
schema_files <- list.files(
  schemas_dir,
  pattern = "\\.schema\\.yaml$",
  full.names = TRUE
)

if (length(schema_files) == 0L) {
  add_error(schemas_dir, "No *.schema.yaml files found")
}

for (path in schema_files) {
  checked <- checked + 1L
  basename_f <- basename(path)

  # 1. YAML syntax check
  parsed <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      add_error(basename_f, paste("YAML parse error:", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(parsed)) next

  # 2. Top-level structure check
  matched <- FALSE
  for (rule in schema_rules) {
    if (grepl(rule$pattern, basename_f, fixed = TRUE)) {
      matched <- TRUE
      missing_keys <- setdiff(rule$keys, names(parsed))
      if (length(missing_keys) > 0L) {
        add_error(
          basename_f,
          paste("Missing top-level key(s):", paste(missing_keys, collapse = ", "))
        )
      }
      # Check nested key under schema (if defined)
      if (!is.null(rule$nested) && "schema" %in% names(parsed)) {
        if (!rule$nested %in% names(parsed$schema)) {
          add_error(
            basename_f,
            paste("Missing key under 'schema':", rule$nested)
          )
        }
      }
      break
    }
  }

  # 3. Filename convention (*.schema.yaml matched by list.files, just log unrecognised types)
  if (!matched) {
    add_error(
      basename_f,
      "Unrecognised schema type (no matching rule for filename pattern)"
    )
  }
}

# --- Phase A+ Cross-reference checks ---
# Collect parsed schemas for cross-reference validation
all_parsed <- list()
for (path in schema_files) {
  parsed <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (!is.null(parsed)) {
    all_parsed[[basename(path)]] <- parsed
  }
}

# Check: knowledge topics should reference valid decision_graph node topics
graph_file <- "decision_graph.schema.yaml"
knowledge_file <- "knowledge.schema.yaml"

if (graph_file %in% names(all_parsed) && knowledge_file %in% names(all_parsed)) {
  graph_schema <- all_parsed[[graph_file]]
  knowledge_schema <- all_parsed[[knowledge_file]]

  # Extract node topics from the graph example if present
  graph_nodes <- NULL
  if (!is.null(graph_schema$schema$graph$nodes)) {
    graph_nodes <- vapply(
      graph_schema$schema$graph$nodes,
      function(n) n$topic %||% "",
      character(1L)
    )
    graph_nodes <- graph_nodes[nzchar(graph_nodes)]
  }

  # Extract knowledge topic from example if present
  knowledge_topic <- knowledge_schema$schema$topic %||% NULL

  if (!is.null(graph_nodes) && !is.null(knowledge_topic) && length(graph_nodes) > 0L) {
    if (!knowledge_topic %in% graph_nodes) {
      add_error(
        knowledge_file,
        paste0(
          "Knowledge topic '", knowledge_topic,
          "' not found in decision_graph node topics: ",
          paste(graph_nodes, collapse = ", ")
        )
      )
    }
  }
}

# Output
if (json_mode) {
  result <- list(
    checked = checked,
    errors  = length(errors),
    details = errors
  )
  cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE), "\n")
} else {
  if (length(errors) == 0L) {
    cli::cli_alert_success("All {checked} schema file{?s} passed validation")
  } else {
    cli::cli_alert_danger("{length(errors)} error{?s} in {checked} schema file{?s}:")
    for (err in errors) {
      cli::cli_bullets(c("x" = "{err$file}: {err$message}"))
    }
  }
}

quit(status = if (length(errors) > 0L) 1L else 0L, save = "no")
