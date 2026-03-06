#' Knowledge Store S7 Classes
#'
#' S7 classes for the knowledge domain model. Each knowledge file corresponds
#' to a single topic (decision point) and links to decision graph nodes via
#' the `topic` field (ADR-0003).
#'
#' @name knowledge
#' @importFrom rlang %||%
NULL

# -- CompetingView ------------------------------------------------------------

#' @title CompetingView
#' @description A divergent recommendation for the same condition, typically
#' added during expert review.
#' @param view The competing recommendation (character).
#' @param source Citation or source for this view (character).
#' @export
CompetingView <- S7::new_class("CompetingView",
  properties = list(
    view = S7::class_character,
    source = S7::class_character
  ),
  validator = function(self) {
    if (length(self@view) != 1L || nchar(self@view) == 0L) {
      return("`view` must be a non-empty single string")
    }
    if (length(self@source) != 1L || nchar(self@source) == 0L) {
      return("`source` must be a non-empty single string")
    }
    NULL
  }
)

# -- KnowledgeEntry -----------------------------------------------------------

#' @title KnowledgeEntry
#' @description A single knowledge entry within a topic. Contains an
#' applicability condition (`when`), descriptive properties, and optional
#' references and competing views.
#' @param id Unique identifier within the plugin (character).
#' @param when Natural-language applicability condition (character).
#' @param computable_hint Optional R expression for the `when` condition.
#' @param properties Character vector of descriptive facts.
#' @param related Optional character vector of cross-references.
#' @param competing_views Optional list of [CompetingView] objects.
#' @param references Optional character vector of citations.
#' @export
KnowledgeEntry <- S7::new_class("KnowledgeEntry",
  properties = list(
    id = S7::class_character,
    when = S7::class_character,
    computable_hint = S7::new_property(
      S7::class_character,
      default = character(0)
    ),
    properties = S7::class_character,
    related = S7::new_property(S7::class_character, default = character(0)),
    competing_views = S7::new_property(S7::class_list, default = list()),
    references = S7::new_property(S7::class_character, default = character(0))
  ),
  validator = function(self) {
    if (length(self@id) != 1L || nchar(self@id) == 0L) {
      return("`id` must be a non-empty single string")
    }
    if (length(self@when) != 1L || nchar(self@when) == 0L) {
      return("`when` must be a non-empty single string")
    }
    if (length(self@properties) == 0L) {
      return("`properties` must contain at least one element")
    }
    for (i in seq_along(self@competing_views)) {
      if (!S7::S7_inherits(self@competing_views[[i]], CompetingView)) {
        return(sprintf("competing_views[[%d]] must be a CompetingView object", i))
      }
    }
    NULL
  }
)

# -- KnowledgeStore -----------------------------------------------------------

#' @title KnowledgeStore
#' @description A collection of knowledge entries for a single topic, linked to
#' decision graph nodes via the `topic` field.
#' @param topic The decision point this knowledge addresses (character).
#' @param target_parameter R package parameter name(s) (character vector).
#' @param package Target package name (character).
#' @param func Target function name (character).
#' @param entries A list of [KnowledgeEntry] objects.
#' @usage NULL
#' @export
KnowledgeStore <- S7::new_class("KnowledgeStore",
  properties = list(
    topic = S7::class_character,
    target_parameter = S7::class_character,
    package = S7::class_character,
    func = S7::class_character,
    entries = S7::class_list
  ),
  validator = function(self) {
    if (length(self@topic) != 1L || nchar(self@topic) == 0L) {
      return("`topic` must be a non-empty single string")
    }
    if (length(self@target_parameter) == 0L) {
      return("`target_parameter` must have at least one element")
    }
    if (length(self@package) != 1L || nchar(self@package) == 0L) {
      return("`package` must be a non-empty single string")
    }
    if (length(self@func) != 1L || nchar(self@func) == 0L) {
      return("`func` must be a non-empty single string")
    }
    if (length(self@entries) == 0L) {
      return("`entries` must contain at least one KnowledgeEntry")
    }
    ids <- character(length(self@entries))
    for (i in seq_along(self@entries)) {
      entry <- self@entries[[i]]
      if (!S7::S7_inherits(entry, KnowledgeEntry)) {
        return(sprintf("entries[[%d]] must be a KnowledgeEntry object", i))
      }
      ids[i] <- entry@id
    }
    if (anyDuplicated(ids)) {
      dup <- ids[duplicated(ids)][[1L]]
      return(sprintf("Duplicate entry id: \"%s\"", dup))
    }
    NULL
  }
)

# -- YAML Reader --------------------------------------------------------------

#' Read Knowledge from YAML
#'
#' Parses a knowledge YAML file and returns a [KnowledgeStore] object.
#'
#' @param path Path to the YAML file.
#' @return A [KnowledgeStore] object.
#' @export
read_knowledge <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }
  raw <- tryCatch(
    yaml::yaml.load_file(path),
    error = function(e) {
      cli::cli_abort("Failed to parse YAML: {conditionMessage(e)}", parent = e)
    }
  )
  parse_knowledge_store(raw)
}

#' @keywords internal
parse_knowledge_store <- function(raw) {
  topic <- raw[["topic"]]
  if (is.null(topic)) {
    cli::cli_abort("{.field topic} is required")
  }
  target_param <- raw[["target_parameter"]]
  if (is.null(target_param)) {
    cli::cli_abort("{.field target_parameter} is required")
  }
  if (is.list(target_param)) {
    target_param <- unlist(target_param)
  }
  pkg <- raw[["package"]]
  if (is.null(pkg)) {
    cli::cli_abort("{.field package} is required")
  }
  func <- raw[["function"]]
  if (is.null(func)) {
    cli::cli_abort("{.field function} is required")
  }
  entries_raw <- raw[["entries"]]
  if (is.null(entries_raw) || length(entries_raw) == 0L) {
    cli::cli_abort("{.field entries} must be a non-empty list")
  }
  entries <- lapply(entries_raw, parse_knowledge_entry)

  KnowledgeStore(
    topic = topic,
    target_parameter = target_param,
    package = pkg,
    func = func,
    entries = entries
  )
}

#' @keywords internal
parse_knowledge_entry <- function(raw) {
  id <- raw[["id"]]
  if (is.null(id)) {
    cli::cli_abort("Knowledge entry is missing required field {.field id}")
  }
  when_val <- raw[["when"]]
  if (is.null(when_val)) {
    cli::cli_abort("Knowledge entry {.val {id}} is missing required field {.field when}")
  }
  props <- raw[["properties"]]
  if (is.null(props) || length(props) == 0L) {
    cli::cli_abort(
      "Knowledge entry {.val {id}} must have non-empty {.field properties}"
    )
  }
  if (is.list(props)) {
    props <- unlist(props)
  }

  competing <- list()
  cv_raw <- raw[["competing_views"]]
  if (!is.null(cv_raw) && length(cv_raw) > 0L) {
    competing <- lapply(cv_raw, parse_competing_view)
  }

  related <- raw[["related"]]
  if (is.list(related)) {
    related <- unlist(related)
  }

  refs <- raw[["references"]]
  if (is.list(refs)) {
    refs <- unlist(refs)
  }

  KnowledgeEntry(
    id = id,
    when = when_val,
    computable_hint = raw[["computable_hint"]] %||% character(0),
    properties = props,
    related = related %||% character(0),
    competing_views = competing,
    references = refs %||% character(0)
  )
}

#' @keywords internal
parse_competing_view <- function(raw) {
  view <- raw[["view"]]
  if (is.null(view)) {
    cli::cli_abort("CompetingView is missing required field {.field view}")
  }
  source_val <- raw[["source"]]
  if (is.null(source_val)) {
    cli::cli_abort("CompetingView is missing required field {.field source}")
  }
  CompetingView(view = view, source = source_val)
}
