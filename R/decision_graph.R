#' Decision Graph S7 Classes
#'
#' S7 classes representing the decision graph domain model.
#' The decision graph is the core plugin artifact that defines a decision flow
#' to efficiently narrow the parameter space (ADR-0002).
#'
#' @name decision_graph
#' @importFrom rlang %||%
NULL

# -- Transition ---------------------------------------------------------------

#' @title Transition
#' @description A directed edge between two nodes in the decision graph.
#' Exactly one condition field must be specified: `when`, `always`, or
#' `otherwise`. `computable_hint` is only valid alongside `when`.
#' @param to Target node ID (character).
#' @param when Natural-language condition text (character). Mutually exclusive
#'   with `always` and `otherwise`.
#' @param computable_hint R expression hint for `when` (character). Only valid
#'   when `when` is also specified.
#' @param always If `TRUE`, transition unconditionally (logical).
#' @param otherwise If `TRUE`, transition as fallback (logical).
#' @export
Transition <- S7::new_class("Transition",
  properties = list(
    to = S7::class_character,
    when = S7::new_property(S7::class_character, default = character(0)),
    computable_hint = S7::new_property(S7::class_character, default = character(0)),
    always = S7::new_property(S7::class_logical, default = NA),
    otherwise = S7::new_property(S7::class_logical, default = NA)
  ),
  validator = function(self) {
    has_when <- length(self@when) > 0L
    has_always <- isTRUE(self@always)
    has_otherwise <- isTRUE(self@otherwise)
    n_set <- sum(has_when, has_always, has_otherwise)

    if (n_set == 0L) {
      return("Transition must specify exactly one of `when`, `always`, or `otherwise`")
    }
    if (n_set > 1L) {
      which_set <- c("when", "always", "otherwise")[c(has_when, has_always, has_otherwise)]
      return(sprintf(
        "Transition must specify exactly one condition, got: %s",
        paste(which_set, collapse = ", ")
      ))
    }
    if (length(self@computable_hint) > 0L && !has_when) {
      return("`computable_hint` is only valid when `when` is also specified")
    }
    NULL
  }
)

# -- NodePolicy ---------------------------------------------------------------

#' @title NodePolicy
#' @description Per-node policy overrides (ADR-0005). `skip_when`/`skip_hint`
#' follow ADR-0003 semantics for conditional node skipping.
#' @param skip_when Natural-language condition for skipping this node.
#' @param skip_hint R expression hint for `skip_when`.
#' @param max_iterations Max times this node can be visited (integer).
#' @export
NodePolicy <- S7::new_class("NodePolicy",
  properties = list(
    skip_when = S7::new_property(S7::class_character, default = character(0)),
    skip_hint = S7::new_property(S7::class_character, default = character(0)),
    max_iterations = S7::new_property(S7::class_integer, default = NA_integer_)
  ),
  validator = function(self) {
    if (length(self@skip_hint) > 0L && length(self@skip_when) == 0L) {
      return("`skip_hint` is only valid when `skip_when` is also specified")
    }
    if (!is.na(self@max_iterations) && self@max_iterations < 1L) {
      return("`max_iterations` must be a positive integer")
    }
    NULL
  }
)

# -- GlobalPolicy -------------------------------------------------------------

#' @title GlobalPolicy
#' @description Graph-level default policy values. Overridden by node-level
#' policy (ADR-0005).
#' @param max_iterations Default max node visits per session (integer).
#' @export
GlobalPolicy <- S7::new_class("GlobalPolicy",
  properties = list(
    max_iterations = S7::new_property(S7::class_integer, default = NA_integer_)
  ),
  validator = function(self) {
    if (!is.na(self@max_iterations) && self@max_iterations < 1L) {
      return("`max_iterations` must be a positive integer")
    }
    NULL
  }
)

# -- Node ---------------------------------------------------------------------

.valid_node_types <- c("context_gathering", "decision", "execution", "diagnosis")

#' @title Node
#' @description A single node in the decision graph. Each node has a type,
#' optional topic/parameter bindings, and an ordered list of transitions.
#' @param type Node type. One of `"context_gathering"`, `"decision"`,
#'   `"execution"`, `"diagnosis"`.
#' @param topic Topic string matching a `knowledge/*.yaml` file.
#' @param parameter R package parameter(s) decided at this node.
#' @param description Brief description of the node's purpose.
#' @param policy A [NodePolicy] object for per-node overrides.
#' @param transitions A list of [Transition] objects.
#' @usage NULL
#' @export
Node <- S7::new_class("Node",
  properties = list(
    type = S7::class_character,
    topic = S7::new_property(S7::class_character, default = character(0)),
    parameter = S7::new_property(S7::class_character, default = character(0)),
    description = S7::new_property(S7::class_character, default = character(0)),
    policy = S7::new_property(NodePolicy, default = NodePolicy()),
    transitions = S7::class_list
  ),
  validator = function(self) {
    if (length(self@type) != 1L) {
      return("`type` must be a single string")
    }
    if (!self@type %in% .valid_node_types) {
      return(sprintf(
        "`type` must be one of: %s (got \"%s\")",
        paste(dQuote(.valid_node_types, FALSE), collapse = ", "),
        self@type
      ))
    }
    for (i in seq_along(self@transitions)) {
      if (!S7::S7_inherits(self@transitions[[i]], Transition)) {
        return(sprintf("transitions[[%d]] must be a Transition object", i))
      }
    }
    NULL
  }
)

# -- DecisionGraph ------------------------------------------------------------

#' @title DecisionGraph
#' @description The top-level decision graph object. Contains an entry node,
#' optional global policy, optional template reference, and a named list
#' of Node objects.
#' @param entry_node ID of the entry-point node (character).
#' @param template Optional template reference (character).
#' @param global_policy A [GlobalPolicy] object for graph-level defaults.
#' @param nodes A named list of [Node] objects.
#' @usage NULL
#' @export
DecisionGraph <- S7::new_class("DecisionGraph",
  properties = list(
    entry_node = S7::class_character,
    template = S7::new_property(S7::class_character, default = character(0)),
    global_policy = S7::new_property(GlobalPolicy, default = GlobalPolicy()),
    nodes = S7::class_list
  ),
  validator = function(self) {
    if (length(self@entry_node) != 1L || nchar(self@entry_node) == 0L) {
      return("`entry_node` must be a non-empty single string")
    }
    node_names <- names(self@nodes)
    if (is.null(node_names) || length(self@nodes) == 0L) {
      return("`nodes` must be a non-empty named list")
    }
    for (nm in node_names) {
      if (!S7::S7_inherits(self@nodes[[nm]], Node)) {
        return(sprintf("nodes[[\"%s\"]] must be a Node object", nm))
      }
    }
    if (!self@entry_node %in% node_names) {
      return(sprintf(
        "`entry_node` \"%s\" not found in nodes (available: %s)",
        self@entry_node,
        paste(dQuote(node_names, FALSE), collapse = ", ")
      ))
    }
    for (nm in node_names) {
      node <- self@nodes[[nm]]
      for (i in seq_along(node@transitions)) {
        target <- node@transitions[[i]]@to
        if (!target %in% node_names) {
          return(sprintf(
            "Node \"%s\" transition[%d] targets \"%s\" which does not exist",
            nm, i, target
          ))
        }
      }
    }
    NULL
  }
)

# -- Helper: check if an optional property is set ----------------------------

#' @keywords internal
has_value <- function(x) {
  length(x) > 0L && !all(is.na(x))
}

# -- YAML Reader --------------------------------------------------------------

#' Read a Decision Graph from YAML
#'
#' Parses a `decision_graph.yaml` file and returns a [DecisionGraph] object.
#'
#' @param path Path to the YAML file.
#' @return A [DecisionGraph] object.
#' @export
read_decision_graph <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }
  raw <- tryCatch(
    yaml::yaml.load_file(path),
    error = function(e) {
      cli::cli_abort("Failed to parse YAML: {conditionMessage(e)}", parent = e)
    }
  )
  graph_raw <- raw[["graph"]]
  if (is.null(graph_raw)) {
    cli::cli_abort("YAML must contain a top-level {.field graph} key")
  }
  parse_decision_graph(graph_raw)
}

#' @keywords internal
parse_decision_graph <- function(graph_raw) {
  entry_node <- graph_raw[["entry_node"]]
  if (is.null(entry_node)) {
    cli::cli_abort("{.field entry_node} is required in the graph definition")
  }

  gp <- GlobalPolicy()
  gp_raw <- graph_raw[["global_policy"]]
  if (!is.null(gp_raw)) {
    gp <- parse_global_policy(gp_raw)
  }

  nodes_raw <- graph_raw[["nodes"]]
  if (is.null(nodes_raw) || length(nodes_raw) == 0L) {
    cli::cli_abort("{.field nodes} must be a non-empty map")
  }

  nodes <- stats::setNames(
    lapply(names(nodes_raw), function(nm) {
      parse_node(nodes_raw[[nm]], node_id = nm)
    }),
    names(nodes_raw)
  )

  DecisionGraph(
    entry_node = entry_node,
    template = graph_raw[["template"]] %||% character(0),
    global_policy = gp,
    nodes = nodes
  )
}

#' @keywords internal
parse_global_policy <- function(raw) {
  max_iter <- raw[["max_iterations"]]
  GlobalPolicy(
    max_iterations = if (!is.null(max_iter)) as.integer(max_iter) else NA_integer_
  )
}

#' @keywords internal
parse_node <- function(raw, node_id) {
  node_type <- raw[["type"]]
  if (is.null(node_type)) {
    cli::cli_abort("Node {.val {node_id}} is missing required field {.field type}")
  }

  transitions_raw <- raw[["transitions"]]
  if (is.null(transitions_raw)) {
    transitions_raw <- list()
  }
  transitions <- lapply(transitions_raw, parse_transition)

  policy <- NodePolicy()
  if (!is.null(raw[["policy"]])) {
    policy <- parse_node_policy(raw[["policy"]])
  }

  param <- raw[["parameter"]]
  if (is.list(param)) {
    param <- unlist(param)
  }

  Node(
    type = node_type,
    topic = raw[["topic"]] %||% character(0),
    parameter = param %||% character(0),
    description = raw[["description"]] %||% character(0),
    policy = policy,
    transitions = transitions
  )
}

#' @keywords internal
parse_node_policy <- function(raw) {
  max_iter <- raw[["max_iterations"]]
  NodePolicy(
    skip_when = raw[["skip_when"]] %||% character(0),
    skip_hint = raw[["skip_hint"]] %||% character(0),
    max_iterations = if (!is.null(max_iter)) as.integer(max_iter) else NA_integer_
  )
}

#' @keywords internal
parse_transition <- function(raw) {
  to <- raw[["to"]]
  if (is.null(to)) {
    cli::cli_abort("Transition is missing required field {.field to}")
  }
  Transition(
    to = to,
    when = raw[["when"]] %||% character(0),
    computable_hint = raw[["computable_hint"]] %||% character(0),
    always = if (isTRUE(raw[["always"]])) TRUE else NA,
    otherwise = if (isTRUE(raw[["otherwise"]])) TRUE else NA
  )
}

# -- Template Composition (ADR-0009) ------------------------------------------

#' Build a Decision Graph from Template Composition
#'
#' Merges a shared template YAML and a function-specific YAML into a flat
#' [DecisionGraph]. If the function-specific YAML has no `template` key,
#' the in-memory graph section is parsed directly (no composition needed).
#'
#' @param func_graph_path Path to the function-specific `decision_graph.yaml`.
#' @param template_dir Directory containing `*.template.yaml` files.
#'   Defaults to the same directory as `func_graph_path`.
#' @return A flat [DecisionGraph] S7 object (runtime-ready).
#' @export
build_graph <- function(func_graph_path, template_dir = NULL) {
  if (!file.exists(func_graph_path)) {
    cli::cli_abort("File not found: {.path {func_graph_path}}")
  }

  raw <- tryCatch(
    yaml::yaml.load_file(func_graph_path),
    error = function(e) {
      cli::cli_abort("Failed to parse YAML: {conditionMessage(e)}", parent = e)
    }
  )
  graph_raw <- raw[["graph"]]
  if (is.null(graph_raw)) {
    cli::cli_abort("YAML must contain a top-level {.field graph} key")
  }

  template_id <- graph_raw[["template"]]
  if (is.null(template_id) || !nzchar(template_id)) {
    return(parse_decision_graph(graph_raw))
  }

  if (is.null(template_dir)) {
    template_dir <- dirname(func_graph_path)
  }
  template_path <- file.path(template_dir, paste0(template_id, ".template.yaml"))
  if (!file.exists(template_path)) {
    cli::cli_abort(
      "Template file not found: {.path {paste0(template_id, '.template.yaml')}} in {.path {template_dir}}"
    )
  }

  tmpl_raw <- tryCatch(
    yaml::yaml.load_file(template_path),
    error = function(e) {
      cli::cli_abort(
        "Failed to parse template YAML: {conditionMessage(e)}",
        parent = e
      )
    }
  )
  tmpl <- tmpl_raw[["template"]]
  if (is.null(tmpl)) {
    cli::cli_abort("Template YAML must contain a top-level {.field template} key")
  }

  merge_template(graph_raw, tmpl)
}

#' Merge template nodes into a function-specific graph
#' @keywords internal
merge_template <- function(graph_raw, tmpl) {
  entry_point <- tmpl[["entry_point"]]
  exit_point <- tmpl[["exit_point"]]
  if (is.null(entry_point) || is.null(exit_point)) {
    cli::cli_abort("Template must define {.field entry_point} and {.field exit_point}")
  }

  tmpl_nodes_raw <- tmpl[["nodes"]]
  if (is.null(tmpl_nodes_raw) || length(tmpl_nodes_raw) == 0L) {
    cli::cli_abort("Template must define at least one node")
  }

  if (!entry_point %in% names(tmpl_nodes_raw)) {
    cli::cli_abort(
      "Template {.field entry_point} {.val {entry_point}} not found in template nodes"
    )
  }
  if (!exit_point %in% names(tmpl_nodes_raw)) {
    cli::cli_abort(
      "Template {.field exit_point} {.val {exit_point}} not found in template nodes"
    )
  }

  func_nodes_raw <- graph_raw[["nodes"]]
  if (is.null(func_nodes_raw)) func_nodes_raw <- list()

  collisions <- intersect(names(tmpl_nodes_raw), names(func_nodes_raw))
  if (length(collisions) > 0L) {
    cli::cli_abort(
      "Node name collision: {.val {collisions}} exist{?s} in both template and function graph"
    )
  }

  exit_node_raw <- tmpl_nodes_raw[[exit_point]]
  exit_transitions <- exit_node_raw[["transitions"]]
  if (!is.null(exit_transitions) && length(exit_transitions) > 0L) {
    cli::cli_warn(c(
      "Template {.field exit_point} node {.val {exit_point}} has non-empty transitions.",
      "i" = "They will be replaced by function graph connections."
    ))
  }

  entry_node <- graph_raw[["entry_node"]]
  if (is.null(entry_node)) {
    cli::cli_abort("{.field entry_node} is required in the graph definition")
  }

  post_exit_transitions <- find_exit_transitions(func_nodes_raw, entry_node)
  tmpl_nodes_raw[[exit_point]][["transitions"]] <- post_exit_transitions

  merged_nodes_raw <- c(func_nodes_raw, tmpl_nodes_raw)

  gp <- GlobalPolicy()
  gp_raw <- graph_raw[["global_policy"]]
  if (!is.null(gp_raw)) {
    gp <- parse_global_policy(gp_raw)
  }

  nodes <- stats::setNames(
    lapply(names(merged_nodes_raw), function(nm) {
      parse_node(merged_nodes_raw[[nm]], node_id = nm)
    }),
    names(merged_nodes_raw)
  )

  DecisionGraph(
    entry_node = entry_node,
    global_policy = gp,
    nodes = nodes
  )
}

#' Find post-exit root nodes in the function graph
#'
#' Identifies function-graph nodes that have no incoming transitions
#' from other function-graph nodes and are not the entry_node. These
#' are the "post-exit" roots that the template's exit_point should
#' connect to.
#' @keywords internal
find_exit_transitions <- function(func_nodes_raw, entry_node) {
  func_names <- names(func_nodes_raw)
  if (length(func_names) == 0L) {
    return(list())
  }

  targeted <- character(0)
  for (nm in func_names) {
    trs <- func_nodes_raw[[nm]][["transitions"]]
    if (is.null(trs)) next
    for (tr in trs) {
      target <- tr[["to"]]
      if (target %in% func_names) {
        targeted <- c(targeted, target)
      }
    }
  }
  targeted <- unique(targeted)

  roots <- setdiff(func_names, c(targeted, entry_node))

  if (length(roots) == 0L) {
    return(list())
  }

  lapply(roots, function(r) list(to = r, always = TRUE))
}
