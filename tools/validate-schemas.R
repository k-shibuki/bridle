#!/usr/bin/env Rscript
# tools/validate-schemas.R -- YAML schema checker
#
# Phase A: syntax + top-level structure + type/required/enum checks
# Phase B: schema-code consistency (S7 class vs YAML schema)
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

  # 4. Structural validation (Phase B): type checks on schema contents
  if (!is.null(parsed) && "schema" %in% names(parsed)) {
    schema_block <- parsed$schema

    if (!is.null(schema_block$version) && !is.character(schema_block$version)) {
      add_error(basename_f, "'schema.version' must be a character string")
    }

    validate_properties <- function(props, path_prefix) {
      if (!is.list(props)) return()
      for (prop_name in names(props)) {
        prop <- props[[prop_name]]
        prop_path <- paste0(path_prefix, ".", prop_name)
        if (!is.list(prop)) next

        if (!is.null(prop$type) && !is.character(prop$type)) {
          add_error(basename_f, paste0("'", prop_path, ".type' must be a string"))
        }

        if (!is.null(prop$required) && !is.logical(prop$required)) {
          add_error(basename_f, paste0("'", prop_path, ".required' must be logical"))
        }

        if (!is.null(prop$enum) && !is.list(prop$enum) && !is.character(prop$enum)) {
          add_error(basename_f, paste0("'", prop_path, ".enum' must be a list or character vector"))
        }

        if (!is.null(prop$properties)) {
          validate_properties(prop$properties, prop_path)
        }
      }
    }

    for (section_name in names(schema_block)) {
      section <- schema_block[[section_name]]
      if (is.list(section) && !is.null(section$properties)) {
        validate_properties(section$properties, paste0("schema.", section_name))
      }
    }
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

# Check: knowledge example topics should reference valid decision_graph example node topics
graph_file <- "decision_graph.schema.yaml"
knowledge_file <- "knowledge.schema.yaml"

if (graph_file %in% names(all_parsed) && knowledge_file %in% names(all_parsed)) {
  graph_data <- all_parsed[[graph_file]]
  knowledge_data <- all_parsed[[knowledge_file]]

  graph_nodes <- NULL
  if (!is.null(graph_data$example$graph$nodes)) {
    graph_nodes <- vapply(
      graph_data$example$graph$nodes,
      function(n) if (is.list(n) && !is.null(n$topic)) n$topic else "",
      character(1L)
    )
    graph_nodes <- graph_nodes[nzchar(graph_nodes)]
  }

  knowledge_topic <- if (!is.null(knowledge_data$example$topic)) {
    knowledge_data$example$topic
  }

  if (!is.null(graph_nodes) && !is.null(knowledge_topic) && length(graph_nodes) > 0L) {
    if (!knowledge_topic %in% graph_nodes) {
      add_error(
        knowledge_file,
        paste0(
          "Knowledge example topic '", knowledge_topic,
          "' not found in decision_graph example node topics: ",
          paste(graph_nodes, collapse = ", ")
        )
      )
    }
  }
}

# --- Phase B: Schema-code consistency checks ---
# When S7 classes exist in R/, verify they match their YAML schemas.

phase_b <- list()

add_phase_b <- function(file, check, severity, message) {
  phase_b[[length(phase_b) + 1L]] <<- list(
    file = file, check = check, severity = severity, message = message
  )
}

safe_prop_name <- function(name) {
  reserved <- c("function", "if", "else", "for", "while", "repeat",
                "in", "next", "break", "TRUE", "FALSE", "NULL")
  if (name %in% reserved) paste0(name, "_name") else name
}

extract_s7_properties <- function(r_lines) {
  props <- list()
  in_props <- FALSE
  depth <- 0L
  for (line in r_lines) {
    stripped <- trimws(line)
    if (!in_props && grepl("properties\\s*=\\s*list\\(", stripped)) {
      in_props <- TRUE
      depth <- nchar(gsub("[^(]", "", stripped)) - nchar(gsub("[^)]", "", stripped))
      next
    }
    if (!in_props) next
    depth <- depth + nchar(gsub("[^(]", "", stripped)) - nchar(gsub("[^)]", "", stripped))
    if (depth <= 0L) { in_props <- FALSE; next }
    if (grepl("^\\s*#", stripped)) next
    m <- regmatches(stripped, regexec(
      "^\\s*(\\w+)\\s*=\\s*(S7::.+?)\\s*,?\\s*$", stripped, perl = TRUE
    ))[[1L]]
    if (length(m) >= 3L) props[[m[2L]]] <- m[3L]
  }
  props
}

s7_type_keyword <- function(yaml_type) {
  yaml_type <- trimws(yaml_type)
  base <- sub("\\s*\\|\\s*null$", "", yaml_type)
  base <- sub("\\s*\\|.*", "", base)
  switch(base,
    "string" = "class_character", "integer" = "class_integer",
    "number" = "class_double", "boolean" = "class_logical",
    "list" = "class_list", "map" = "class_list",
    {
      if (grepl("^list\\[string\\]$", base)) "class_character"
      else if (grepl("^(list|map)\\[", base)) "class_list"
      else "class_list"
    }
  )
}

r_dir <- "R"
r_files <- list.files(r_dir, pattern = "\\.R$", full.names = TRUE)

if (length(r_files) == 0L) {
  add_phase_b("R/", "B5", "info", "No R files found — skipping schema-code consistency checks")
} else {
  for (spath in schema_files) {
    base_name <- sub("\\.schema\\.yaml$", "", basename(spath))
    r_path <- file.path(r_dir, paste0(gsub("[.-]+", "_", tolower(base_name)), ".R"))

    if (!file.exists(r_path)) {
      add_phase_b(basename(spath), "B5", "info",
        paste0("No corresponding R file: ", r_path))
      next
    }

    r_lines <- readLines(r_path, warn = FALSE)
    s7_props <- extract_s7_properties(r_lines)

    if (length(s7_props) == 0L) {
      add_phase_b(basename(spath), "B5", "info",
        paste0("No S7 class definition found in ", r_path))
      next
    }

    schema_data <- tryCatch(yaml::read_yaml(spath), error = function(e) NULL)
    if (is.null(schema_data) || is.null(schema_data$schema)) next

    schema_fields <- schema_data$schema
    schema_fields$version <- NULL

    # For schemas with nested structure (e.g., decision_graph has graph.*),
    # drill into the nested section so B1/B2 check sub-fields as S7 properties.
    matched_rule <- NULL
    for (rule in schema_rules) {
      if (grepl(rule$pattern, basename(spath), fixed = TRUE)) {
        matched_rule <- rule
        break
      }
    }
    if (!is.null(matched_rule$nested) &&
        matched_rule$nested %in% names(schema_fields)) {
      nested_section <- schema_fields[[matched_rule$nested]]
      if (is.list(nested_section)) {
        schema_fields <- nested_section
      }
    }

    # B1: Schema fields present as S7 properties
    for (fname in names(schema_fields)) {
      sname <- safe_prop_name(fname)
      if (!sname %in% names(s7_props)) {
        add_phase_b(basename(spath), "B1", "error",
          paste0("Schema field '", fname, "' missing from S7 class in ", r_path))
      }
    }

    # B3: No class_any in S7 properties
    for (pname in names(s7_props)) {
      if (grepl("class_any", s7_props[[pname]], fixed = TRUE)) {
        add_phase_b(basename(spath), "B3", "error",
          paste0("Property '", pname, "' uses prohibited class_any in ", r_path))
      }
    }

    # B2: Type consistency
    for (fname in names(schema_fields)) {
      field <- schema_fields[[fname]]
      if (!is.list(field) || is.null(field$type)) next
      sname <- safe_prop_name(fname)
      if (!sname %in% names(s7_props)) next
      expected_kw <- s7_type_keyword(field$type)
      actual_type <- s7_props[[sname]]
      if (!grepl(expected_kw, actual_type, fixed = TRUE)) {
        # A custom S7 class (e.g., new_property(GlobalPolicy, ...)) is a valid
        # and preferred implementation for schema map/list types. Only flag when
        # the S7 type uses a *different* built-in class (e.g., class_character
        # where class_list was expected).
        uses_custom_s7_class <- grepl("new_property\\(", actual_type) &&
          !grepl("class_", actual_type, fixed = TRUE)
        if (!uses_custom_s7_class) {
          add_phase_b(basename(spath), "B2", "warning", paste0(
            "Type mismatch for '", fname, "': schema '", field$type,
            "' expects S7 ", expected_kw, " but found '", actual_type, "' in ", r_path
          ))
        }
      }
    }
  }
}

phase_b_errors <- Filter(function(x) x$severity == "error", phase_b)
phase_b_warnings <- Filter(function(x) x$severity == "warning", phase_b)
phase_b_infos <- Filter(function(x) x$severity == "info", phase_b)

for (item in phase_b_errors) {
  add_error(item$file, paste0("[", item$check, "] ", item$message))
}

# Output
if (json_mode) {
  result <- list(
    checked = checked,
    errors  = length(errors),
    details = errors,
    phase_b = phase_b
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
  if (length(phase_b_warnings) > 0L) {
    for (w in phase_b_warnings) {
      cli::cli_bullets(c("!" = "[{w$check}] {w$file}: {w$message}"))
    }
  }
  if (length(phase_b_infos) > 0L) {
    for (info in phase_b_infos) {
      cli::cli_bullets(c("i" = "[{info$check}] {info$message}"))
    }
  }
}

quit(status = if (length(errors) > 0L) 1L else 0L, save = "no")
