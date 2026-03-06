# Shared mock value factories for bridle tests.
# testthat auto-sources helper-*.R files before running tests.
#
# IMPORTANT: local_mocked_bindings() must be called inline in each test_that
# block due to scope constraints. These helpers provide VALUES only.

# -- Scanner mock factories (used by scan_package, scan_layer2, scan_layer3a) --

mock_resolve <- function(fn) {
  function(package, func) fn
}

mock_version <- function(package) "0.0.0.9999"

# -- Rd structure builders (used by scan_layer2, scan_layer3a) -----------------

make_rd_text <- function(text) {
  structure(text, Rd_tag = "TEXT")
}

make_rd_item <- function(name, description) {
  structure(
    list(
      list(make_rd_text(name)),
      list(make_rd_text(description))
    ),
    Rd_tag = "\\item"
  )
}

make_rd_arguments <- function(...) {
  structure(list(...), Rd_tag = "\\arguments")
}

make_rd_references <- function(text) {
  structure(list(make_rd_text(text)), Rd_tag = "\\references")
}

make_rd_alias <- function(name) {
  structure(list(make_rd_text(name)), Rd_tag = "\\alias")
}

make_mock_rd <- function(alias, arguments = list(), references = NULL) {
  rd <- list(make_rd_alias(alias))
  if (length(arguments) > 0L) {
    items <- lapply(names(arguments), function(nm) {
      make_rd_item(nm, arguments[[nm]])
    })
    rd <- c(rd, list(do.call(make_rd_arguments, items)))
  }
  if (!is.null(references)) {
    rd <- c(rd, list(make_rd_references(references)))
  }
  rd
}

mock_rd_for <- function(func_name, arguments = list(), references = NULL) {
  rd <- list(make_rd_alias(func_name))
  if (length(arguments) > 0L) {
    items <- lapply(names(arguments), function(nm) {
      make_rd_item(nm, arguments[[nm]])
    })
    args_section <- structure(items, Rd_tag = "\\arguments")
    rd <- c(rd, list(args_section))
  }
  if (!is.null(references)) {
    ref_section <- structure(
      list(make_rd_text(references)),
      Rd_tag = "\\references"
    )
    rd <- c(rd, list(ref_section))
  }
  rd_db <- list()
  rd_db[[paste0(func_name, ".Rd")]] <- rd
  rd_db
}

# -- HTTP mock factories (used by fetch_references) ----------------------------

mock_crossref_response <- function(doi = "10.1234/test",
                                   title = "Test Paper",
                                   authors = list(
                                     list(given = "John", family = "Doe")
                                   ),
                                   abstract = "An abstract.",
                                   journal = "Test Journal",
                                   year = 2020L) {
  body <- list(
    message = list(
      DOI = doi,
      title = list(title),
      author = authors,
      abstract = abstract,
      `container-title` = list(journal),
      `published-print` = list(
        `date-parts` = list(list(year))
      )
    )
  )
  structure(
    list(body = body),
    class = "httr2_response"
  )
}

# -- Plugin test builders (used by validate_plugin) ----------------------------

# nolint start: object_usage_linter. S7 constructors from same package.
make_graph <- function(nodes = NULL, entry = "start") {
  if (is.null(nodes)) {
    nodes <- list(
      start = Node(
        type = "decision",
        topic = "effect_measure",
        parameter = "sm",
        transitions = list(
          Transition(to = "end", always = TRUE)
        )
      ),
      end = Node(
        type = "execution",
        transitions = list()
      )
    )
  }
  DecisionGraph(entry_node = entry, nodes = nodes)
}

make_knowledge <- function(topic = "effect_measure",
                           param = "sm",
                           pkg = "meta",
                           func = "metabin") {
  KnowledgeStore(
    topic = topic,
    target_parameter = param,
    package = pkg,
    func = func,
    entries = list(KnowledgeEntry(
      id = "e1",
      when = "always",
      properties = "Use RR for binary outcomes"
    ))
  )
}

make_constraint <- function(param = "sm", pkg = "meta", func = "metabin") {
  ConstraintSet(
    package = pkg,
    func = func,
    constraints = list(Constraint(
      id = "c1",
      source = "formals_default",
      type = "valid_values",
      param = param,
      values = c("RR", "OR", "RD")
    ))
  )
}

make_context <- function(vars = NULL) {
  if (is.null(vars)) {
    vars <- list(ContextVariable(
      name = "k",
      description = "number of studies",
      available_from = "data_loaded",
      source_expression = "nrow(data)"
    ))
  }
  ContextSchema(variables = vars)
}
# nolint end
