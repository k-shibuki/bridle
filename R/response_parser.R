#' Response Parser
#'
#' Parses LLM responses to extract recommendations, parameter values,
#' transition signals, and code blocks. Uses structured output as
#' primary path with text-parse fallback (D2 design decision).
#'
#' @name response_parser
#' @include graph_engine.R
NULL

# -- ParsedResponse S7 class ---------------------------------------------------

#' @title ParsedResponse
#' @description Structured result from LLM response parsing.
#' @param recommendation_text Human-readable recommendation text (character).
#' @param suggested_value Suggested parameter value (character or NULL).
#' @param transition_signal Target node for transition (character or NULL).
#' @param code_block Extracted R code block (character or NULL).
#' @param raw_response Original response text for audit log (character).
#' @export
ParsedResponse <- S7::new_class("ParsedResponse",
  properties = list(
    recommendation_text = S7::new_property(
      S7::class_character,
      default = ""
    ),
    suggested_value = S7::new_property(S7::class_any, default = NULL),
    transition_signal = S7::new_property(S7::class_any, default = NULL),
    code_block = S7::new_property(S7::class_any, default = NULL),
    raw_response = S7::new_property(S7::class_character, default = "")
  ),
  validator = function(self) {
    if (length(self@recommendation_text) != 1L) {
      return("`recommendation_text` must be a single string")
    }
    sv <- self@suggested_value
    if (!is.null(sv) && (!is.character(sv) || length(sv) != 1L)) {
      return("`suggested_value` must be a single string or NULL")
    }
    ts <- self@transition_signal
    if (!is.null(ts) && (!is.character(ts) || length(ts) != 1L)) {
      return("`transition_signal` must be a single string or NULL")
    }
    cb <- self@code_block
    if (!is.null(cb) && (!is.character(cb) || length(cb) != 1L)) {
      return("`code_block` must be a single string or NULL")
    }
    if (length(self@raw_response) != 1L) {
      return("`raw_response` must be a single string")
    }
    NULL
  }
)

# -- parse_response ------------------------------------------------------------

#' Parse an LLM response
#'
#' Extracts structured content from an LLM response string. Tries
#' JSON extraction first, falls back to text parsing. Invalid transition
#' signals (non-existent targets) trigger a warning and are set to NULL.
#'
#' @param response Character string of the LLM response.
#' @param node A `Node` S7 object (used for context).
#' @param transition_candidates Character vector of valid target node IDs.
#' @return A [ParsedResponse] S7 object.
#' @export
parse_response <- function(response, node, transition_candidates = character(0)) {
  if (is.null(response) || !is.character(response) || length(response) != 1L) {
    return(.default_parsed_response(""))
  }
  if (nchar(trimws(response)) == 0L) {
    return(.default_parsed_response(""))
  }

  result <- tryCatch(
    .extract_structured(response),
    error = function(e) NULL
  )

  if (is.null(result)) {
    result <- .parse_text_response(response)
  }

  .validate_transition_signal(result, transition_candidates)
}

# -- Internal: structured extraction -------------------------------------------

#' @keywords internal
.extract_structured <- function(response) {
  json_match <- regmatches(
    response,
    regexpr("\\{[^{}]*\\}", response, perl = TRUE)
  )
  if (length(json_match) == 0L || nchar(json_match) == 0L) {
    stop("No JSON block found")
  }

  parsed <- jsonlite::fromJSON(json_match, simplifyVector = FALSE)

  ParsedResponse(
    recommendation_text = as.character(
      parsed$recommendation_text %||% parsed$recommendation %||% ""
    ),
    suggested_value = .as_nullable_string(
      parsed$suggested_value %||% parsed$value
    ),
    transition_signal = .as_nullable_string(
      parsed$transition_signal %||% parsed$transition %||% parsed$next_node
    ),
    code_block = .as_nullable_string(parsed$code_block %||% parsed$code),
    raw_response = response
  )
}

# -- Internal: text-based fallback ---------------------------------------------

#' @keywords internal
.parse_text_response <- function(response) {
  code_block <- .extract_code_block(response)

  ParsedResponse(
    recommendation_text = response,
    suggested_value = NULL,
    transition_signal = NULL,
    code_block = code_block,
    raw_response = response
  )
}

#' @keywords internal
.extract_code_block <- function(text) {
  pattern <- "```(?:r|R)?\\s*\\n(.*?)\\n```"
  m <- regmatches(text, regexpr(pattern, text, perl = TRUE))
  if (length(m) == 0L || nchar(m) == 0L) {
    return(NULL)
  }
  code <- sub("^```(?:r|R)?\\s*\\n", "", m, perl = TRUE)
  code <- sub("\\n```$", "", code, perl = TRUE)
  if (nchar(trimws(code)) == 0L) {
    return(NULL)
  }
  code
}

# -- Internal: validation ------------------------------------------------------

#' @keywords internal
.validate_transition_signal <- function(parsed, valid_targets) {
  ts <- parsed@transition_signal
  if (is.null(ts) || length(valid_targets) == 0L) {
    return(parsed)
  }

  if (!ts %in% valid_targets) {
    warning(
      sprintf(
        "Invalid transition signal '%s'; valid targets: %s",
        ts, paste(valid_targets, collapse = ", ")
      ),
      call. = FALSE
    )
    ParsedResponse(
      recommendation_text = parsed@recommendation_text,
      suggested_value = parsed@suggested_value,
      transition_signal = NULL,
      code_block = parsed@code_block,
      raw_response = parsed@raw_response
    )
  } else {
    parsed
  }
}

# -- Internal: helpers ---------------------------------------------------------

#' @keywords internal
.default_parsed_response <- function(raw = "") {
  ParsedResponse(
    recommendation_text = "", raw_response = raw
  )
}

#' @keywords internal
.as_nullable_string <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  s <- as.character(x)
  if (length(s) != 1L || nchar(s) == 0L) {
    return(NULL)
  }
  s
}
