#!/usr/bin/env Rscript
# tools/scaffold-class.R -- Generate S7 class boilerplate from YAML schema
#
# Usage: Rscript tools/scaffold-class.R docs/schemas/knowledge.schema.yaml
# Exit code: 0 = success, 1 = error

`%||%` <- function(x, y) if (is.null(x)) y else x

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0L) {
    cli::cli_abort(c(
      "Schema path required.",
      "i" = "Usage: Rscript tools/scaffold-class.R <schema-path>",
      "i" = "Example: Rscript tools/scaffold-class.R docs/schemas/knowledge.schema.yaml"
    ))
  }

  schema_path <- args[1L]
  if (!file.exists(schema_path)) {
    cli::cli_abort("Schema file not found: {schema_path}")
  }

  raw <- yaml::read_yaml(schema_path)
  if (is.null(raw[["schema"]])) {
    cli::cli_abort("No 'schema:' key found in {schema_path}")
  }

  base_name <- sub("\\.schema\\.ya?ml$", "", basename(schema_path))
  class_name <- to_pascal_case(base_name)
  file_name <- to_snake_case(base_name)

  fields <- raw[["schema"]]
  fields[["version"]] <- NULL

  if (length(fields) == 0L) {
    cli::cli_abort("No fields found in schema (only version?)")
  }

  props <- list()
  for (fname in names(fields)) {
    props[[fname]] <- analyze_field(fields[[fname]], fname)
  }

  class_path <- file.path("R", paste0(file_name, ".R"))
  if (file.exists(class_path)) {
    cli::cli_abort(c(
      "Target file already exists: {class_path}",
      "i" = "Remove it manually if you want to regenerate."
    ))
  }

  code <- generate_class_code(class_name, props, base_name)
  dir.create("R", showWarnings = FALSE)
  writeLines(code, class_path)
  cli::cli_alert_success("Generated {class_path}")

  test_dir <- file.path("tests", "testthat")
  test_path <- file.path(test_dir, paste0("test-", file_name, ".R"))
  if (!file.exists(test_path)) {
    dir.create(test_dir, recursive = TRUE, showWarnings = FALSE)
    test_code <- generate_test_skeleton(class_name, props, file_name)
    writeLines(test_code, test_path)
    cli::cli_alert_success("Generated {test_path}")
  } else {
    cli::cli_alert_info("Test file already exists: {test_path}")
  }

  prop_names <- paste(names(props), collapse = ", ")
  cli::cli_alert_info("Class: {class_name}")
  cli::cli_alert_info("Properties: {prop_names}")
}

to_pascal_case <- function(x) {
  parts <- strsplit(x, "[_.-]+")[[1L]]
  paste0(toupper(substring(parts, 1L, 1L)), substring(parts, 2L), collapse = "")
}

to_snake_case <- function(x) {
  gsub("[.-]+", "_", tolower(x))
}

analyze_field <- function(field, field_name) {
  if (!is.list(field)) {
    return(list(
      name = field_name, s7_type = "S7::class_character",
      required = FALSE, description = "", enum_values = NULL,
      is_complex = FALSE
    ))
  }

  type_str <- field[["type"]] %||% "string"
  required <- isTRUE(field[["required"]])
  description <- field[["description"]] %||% ""
  description <- gsub("\\s+", " ", trimws(description))
  enum_values <- field[["enum"]]
  has_nested <- !is.null(field[["items"]]) || !is.null(field[["properties"]])
  s7_type <- resolve_s7_type(type_str, required, has_nested)

  list(
    name = field_name, s7_type = s7_type, required = required,
    description = description, enum_values = enum_values,
    is_complex = has_nested
  )
}

resolve_s7_type <- function(type_str, required, has_nested) {
  if (grepl("\\|\\s*null", type_str)) {
    base_str <- trimws(sub("\\|\\s*null", "", type_str))
    base <- map_base_type(base_str)
    return(paste0("S7::new_union(", base, ", S7::class_missing)"))
  }

  if (grepl("\\|", type_str)) {
    parts <- trimws(strsplit(type_str, "\\|")[[1L]])
    if (all(parts %in% c("string", "list[string]"))) {
      return("S7::class_character")
    }
    mapped <- vapply(parts, map_base_type, character(1L))
    return(paste0("S7::new_union(", paste(mapped, collapse = ", "), ")"))
  }

  base <- map_base_type(type_str)

  is_list_type <- base %in% c("S7::class_list")
  if (!required && !has_nested && !is_list_type) {
    return(paste0("S7::new_union(", base, ", S7::class_missing)"))
  }

  base
}

map_base_type <- function(type_str) {
  type_str <- trimws(type_str)
  simple <- c(
    "string" = "S7::class_character", "integer" = "S7::class_integer",
    "number" = "S7::class_double", "boolean" = "S7::class_logical",
    "list" = "S7::class_list", "map" = "S7::class_list"
  )
  if (type_str %in% names(simple)) return(simple[[type_str]])
  if (grepl("^list\\[string\\]$", type_str)) return("S7::class_character")
  if (grepl("^(list|map)\\[", type_str)) return("S7::class_list")
  "S7::class_list"
}

safe_prop_name <- function(name) {
  reserved <- c(
    "function", "if", "else", "for", "while", "repeat", "in",
    "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN"
  )
  if (name %in% reserved) paste0(name, "_name") else name
}

generate_class_code <- function(class_name, props, base_name) {
  lines <- character()

  lines <- c(lines, sprintf("#' %s", class_name))
  lines <- c(lines, "#'")
  lines <- c(lines,
    sprintf("#' S7 class generated from \\code{docs/schemas/%s.schema.yaml}.", base_name)
  )
  lines <- c(lines, "#'")

  for (p in props) {
    sname <- safe_prop_name(p$name)
    desc <- if (nzchar(p$description)) p$description else "(no description)"
    if (nchar(desc) > 90L) desc <- paste0(substring(desc, 1L, 87L), "...")
    lines <- c(lines, sprintf("#' @param %s %s", sname, desc))
  }

  lines <- c(lines, "#'")
  lines <- c(lines, "#' @export")
  lines <- c(lines, sprintf("%s <- S7::new_class(\"%s\",", class_name, class_name))
  lines <- c(lines, "  properties = list(")

  prop_names <- names(props)
  for (i in seq_along(props)) {
    p <- props[[i]]
    sname <- safe_prop_name(p$name)
    comma <- if (i < length(props)) "," else ""

    if (p$is_complex) {
      lines <- c(lines, sprintf(
        "    # TODO: %s has nested structure; consider a dedicated S7 class", p$name
      ))
    }

    if (!p$required && grepl("class_list", p$s7_type) && !grepl("new_union", p$s7_type)) {
      lines <- c(lines, sprintf(
        "    %s = S7::new_property(class = %s, default = list())%s",
        sname, p$s7_type, comma
      ))
    } else if (!p$required && grepl("new_union", p$s7_type)) {
      lines <- c(lines, sprintf(
        "    %s = S7::new_property(class = %s, default = NULL)%s",
        sname, p$s7_type, comma
      ))
    } else {
      lines <- c(lines, sprintf("    %s = %s%s", sname, p$s7_type, comma))
    }
  }

  lines <- c(lines, "  ),")

  enum_props <- Filter(function(p) !is.null(p$enum_values), props)
  has_validation <- length(enum_props) > 0L

  lines <- c(lines, "  validator = function(self) {")

  if (has_validation) {
    lines <- c(lines, "    errs <- character()")
    for (p in enum_props) {
      sname <- safe_prop_name(p$name)
      vals <- paste0('"', p$enum_values, '"', collapse = ", ")
      lines <- c(lines, sprintf("    valid_%s <- c(%s)", sname, vals))
      lines <- c(lines, sprintf(
        "    if (length(self@%s) > 0L && !all(self@%s %%in%% valid_%s)) {",
        sname, sname, sname
      ))
      lines <- c(lines, sprintf(
        '      errs <- c(errs, sprintf("%s must be one of: %%s",',
        sname
      ))
      lines <- c(lines, sprintf(
        '        paste(valid_%s, collapse = ", ")))', sname
      ))
      lines <- c(lines, "    }")
    }
    lines <- c(lines, "    # TODO: Add cross-field constraints from the schema")
    lines <- c(lines, "    if (length(errs) > 0L) errs else NULL")
  } else {
    lines <- c(lines, "    # TODO: Add validation logic for schema constraints")
    lines <- c(lines, "    NULL")
  }

  lines <- c(lines, "  }")
  lines <- c(lines, ")")

  paste(lines, collapse = "\n")
}

generate_test_skeleton <- function(class_name, props, file_name) { # nolint: object_name
  lines <- character()

  req_props <- Filter(function(p) p$required, props)

  lines <- c(lines, sprintf('test_that("%s can be constructed with valid inputs", {', class_name))

  if (length(req_props) > 0L) {
    arg_lines <- vapply(req_props, function(p) {
      sname <- safe_prop_name(p$name)
      default_val <- switch(
        sub("S7::", "", sub("\\(.*", "", p$s7_type)),
        "class_character" = '"test"',
        "class_integer" = "1L",
        "class_double" = "1.0",
        "class_logical" = "TRUE",
        "class_list" = "list()",
        '"test"'
      )
      sprintf("    %s = %s", sname, default_val)
    }, character(1L))

    lines <- c(lines, sprintf("  obj <- %s(", class_name))
    lines <- c(lines, paste(arg_lines, collapse = ",\n"))
    lines <- c(lines, "  )")
  } else {
    lines <- c(lines, sprintf("  obj <- %s()", class_name))
  }

  lines <- c(lines, sprintf('  expect_s3_class(obj, "%s")', class_name))
  lines <- c(lines, "})")
  lines <- c(lines, "")

  enum_props <- Filter(function(p) !is.null(p$enum_values), props)
  for (p in enum_props) {
    sname <- safe_prop_name(p$name)
    lines <- c(lines, sprintf(
      'test_that("%s rejects invalid %s values", {', class_name, sname
    ))
    lines <- c(lines, "  # TODO: construct with invalid enum value and expect error")
    lines <- c(lines, sprintf('  expect_error(%s(%s = "INVALID_VALUE"))', class_name, sname))
    lines <- c(lines, "})")
    lines <- c(lines, "")
  }

  lines <- c(lines, sprintf(
    'test_that("%s validator catches constraint violations", {', class_name
  ))
  lines <- c(lines, "  # TODO: Add tests for cross-field validation")
  lines <- c(lines, "  expect_true(TRUE)")
  lines <- c(lines, "})")

  paste(lines, collapse = "\n")
}

main()
