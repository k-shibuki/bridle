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

# -- Scanner composite helpers ------------------------------------------------
# These depend on mock_resolve, mock_version, mock_rd_for above.
# Co-located here so lintr's object_usage_linter resolves all references
# within a single file (see test-strategy.mdc §8 Helper Colocation).

mock_empty_rd_db <- function(package) {
  rd <- list(structure(
    list(structure("testfn", Rd_tag = "TEXT")),
    Rd_tag = "\\alias"
  ))
  list("testfn.Rd" = rd)
}

with_scan_mocks <- function(fn, code) {
  testthat::local_mocked_bindings(resolve_function = mock_resolve(fn))
  testthat::local_mocked_bindings(get_package_version = mock_version)
  testthat::local_mocked_bindings(get_rd_db = mock_empty_rd_db)
  code
}

setup_all_mocks <- function(fn, rd_db = NULL) {
  if (is.null(rd_db)) rd_db <- mock_rd_for("testfn")
  list(
    resolve = mock_resolve(fn),
    version = mock_version,
    rd = function(pkg) rd_db
  )
}

# -- HTTP mock factories (used by fetch_references) ----------------------------

make_json_response <- function(body_data, status = 200L) {
  json_str <- jsonlite::toJSON(body_data, auto_unbox = TRUE, null = "null")
  structure(
    list(
      method = "GET",
      url = "https://mock.test",
      status_code = as.integer(status),
      headers = structure(
        list(`content-type` = "application/json"),
        class = "httr2_headers"
      ),
      body = charToRaw(as.character(json_str)),
      cache = new.env(parent = emptyenv())
    ),
    class = "httr2_response"
  )
}

mock_openalex_response <- function(doi = "10.1234/test",
                                   title = "Test Paper",
                                   authors = list(
                                     list(author = list(
                                       display_name = "John Doe"
                                     ))
                                   ),
                                   abstract_inverted_index = list(
                                     An = list(0L),
                                     abstract = list(1L)
                                   ),
                                   journal = "Test Journal",
                                   year = 2020L,
                                   status = 200L) {
  body <- list(
    doi = paste0("https://doi.org/", doi),
    title = title,
    authorships = authors,
    publication_year = year,
    primary_location = list(source = list(display_name = journal))
  )
  body[["abstract_inverted_index"]] <- abstract_inverted_index
  make_json_response(body, status = status)
}

mock_s2_response <- function(doi = "10.1234/test",
                             title = "Test Paper",
                             authors = list(list(name = "John Doe")),
                             abstract = "An abstract.",
                             venue = "Test Journal",
                             year = 2020L,
                             status = 200L) {
  body <- list(
    externalIds = list(DOI = doi),
    title = title,
    authors = authors,
    venue = venue,
    year = year
  )
  body[["abstract"]] <- abstract
  make_json_response(body, status = status)
}

# -- Plugin test builders (used by validate_plugin) ----------------------------

make_graph <- function(nodes = NULL, entry = "start") {
  if (is.null(nodes)) {
    nodes <- list(
      start = Node( # nolint: object_usage_linter. S7 constructor
        type = "decision",
        topic = "effect_measure",
        parameter = "sm",
        transitions = list(
          Transition(to = "end", always = TRUE) # nolint: object_usage_linter. S7 constructor
        )
      ),
      end = Node( # nolint: object_usage_linter. S7 constructor
        type = "execution",
        transitions = list()
      )
    )
  }
  DecisionGraph(entry_node = entry, nodes = nodes) # nolint: object_usage_linter. S7 constructor
}

make_knowledge <- function(topic = "effect_measure",
                           param = "sm",
                           pkg = "meta",
                           func = "metabin") {
  KnowledgeStore( # nolint: object_usage_linter. S7 constructor
    topic = topic,
    target_parameter = param,
    package = pkg,
    func = func,
    entries = list(KnowledgeEntry( # nolint: object_usage_linter. S7 constructor
      id = "e1",
      when = "always",
      properties = "Use RR for binary outcomes"
    ))
  )
}

make_constraint <- function(param = "sm", pkg = "meta", func = "metabin") {
  ConstraintSet( # nolint: object_usage_linter. S7 constructor
    package = pkg,
    func = func,
    constraints = list(Constraint( # nolint: object_usage_linter. S7 constructor
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
    vars <- list(ContextVariable( # nolint: object_usage_linter. S7 constructor
      name = "k",
      description = "number of studies",
      available_from = "data_loaded",
      source_expression = "nrow(data)"
    ))
  }
  ContextSchema(variables = vars) # nolint: object_usage_linter. S7 constructor
}
# -- SessionContext mock factory (used by session_context, graph_engine, etc.) --

make_session_context <- function(variables = list(),
                                 data = NULL,
                                 parameters = list(),
                                 schema = NULL) {
  if (is.null(schema)) {
    schema <- make_context()
  }
  ctx <- SessionContext(schema = schema, variables = variables) # nolint: object_usage_linter. S7 constructor
  if (!is.null(data)) {
    ctx@data <- data
  }
  if (length(parameters) > 0L) {
    ctx@parameters_decided <- parameters
  }
  ctx
}

# -- GraphEngine mock factory (used by graph_engine, console, integration) -----

make_test_engine <- function(nodes = NULL, entry = "start",
                             context = NULL, global_policy = NULL) {
  if (is.null(nodes)) {
    nodes <- list(
      start = Node( # nolint: object_usage_linter. S7 constructor
        type = "decision", topic = "effect_measure", parameter = "sm",
        transitions = list(Transition(to = "end", always = TRUE)) # nolint: object_usage_linter. S7 constructor
      ),
      end = Node(type = "execution", transitions = list()) # nolint: object_usage_linter. S7 constructor
    )
  }
  gp <- global_policy %||% GlobalPolicy() # nolint: object_usage_linter. S7 constructor
  graph <- DecisionGraph( # nolint: object_usage_linter. S7 constructor
    entry_node = entry, global_policy = gp, nodes = nodes
  )
  ctx <- context %||% make_session_context()
  make_graph_engine(graph, ctx) # nolint: object_usage_linter. exported function in R/graph_engine.R
}
