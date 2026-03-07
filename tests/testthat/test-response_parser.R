# Tests for Response Parser (Issue #61)

make_simple_node <- function(type = "decision") {
  Node( # nolint: object_usage_linter. S7 class in R/decision_graph.R
    type = type, topic = "effect_measure", parameter = "sm",
    transitions = list(Transition(to = "end", always = TRUE)) # nolint: object_usage_linter.
  )
}

# -- ParsedResponse S7 class ---------------------------------------------------

test_that("ParsedResponse constructs with defaults", {
  pr <- ParsedResponse() # nolint: object_usage_linter. S7 class in R/response_parser.R
  expect_equal(pr@recommendation_text, "")
  expect_null(pr@suggested_value)
  expect_null(pr@transition_signal)
  expect_null(pr@code_block)
})

test_that("ParsedResponse validates suggested_value type", {
  expect_error(
    ParsedResponse(suggested_value = 42), # nolint: object_usage_linter.
    "suggested_value"
  )
})

test_that("ParsedResponse validates transition_signal type", {
  expect_error(
    ParsedResponse(transition_signal = 42), # nolint: object_usage_linter.
    "transition_signal"
  )
})

# -- parse_response: structured JSON -------------------------------------------

test_that("decision response with JSON extracts all fields", {
  resp <- '{"recommendation_text": "Use OR", "suggested_value": "OR"}'
  node <- make_simple_node()
  result <- parse_response(resp, node)
  expect_equal(result@recommendation_text, "Use OR")
  expect_equal(result@suggested_value, "OR")
  expect_equal(result@raw_response, resp)
})

test_that("response with transition_signal", {
  resp <- '{"recommendation_text": "Go A", "transition_signal": "node_a"}'
  node <- make_simple_node()
  result <- parse_response(resp, node, c("node_a", "node_b"))
  expect_equal(result@transition_signal, "node_a")
})

test_that("response with code_block in JSON", {
  resp <- '{"recommendation_text": "Run this", "code_block": "1 + 1"}'
  node <- make_simple_node(type = "execution")
  result <- parse_response(resp, node)
  expect_equal(result@code_block, "1 + 1")
})

# -- parse_response: text fallback ---------------------------------------------

test_that("plain text falls back to text parsing", {
  resp <- "I recommend using OR for this analysis."
  node <- make_simple_node()
  result <- parse_response(resp, node)
  expect_equal(result@recommendation_text, resp)
  expect_null(result@suggested_value)
})

test_that("text with markdown code block extracts code", {
  resp <- "Here is the code:\n```r\nmetabin(ai, n1i)\n```\nDone."
  node <- make_simple_node(type = "execution")
  result <- parse_response(resp, node)
  expect_equal(result@code_block, "metabin(ai, n1i)")
})

test_that("text with plain code fence extracts code", {
  resp <- "Run:\n```\nx <- 1 + 1\n```"
  node <- make_simple_node()
  result <- parse_response(resp, node)
  expect_equal(result@code_block, "x <- 1 + 1")
})

# -- parse_response: malformed -------------------------------------------------

test_that("NULL response returns default", {
  node <- make_simple_node()
  result <- parse_response(NULL, node)
  expect_equal(result@recommendation_text, "")
})

test_that("empty string returns default", {
  node <- make_simple_node()
  result <- parse_response("", node)
  expect_equal(result@recommendation_text, "")
})

test_that("non-character returns default", {
  node <- make_simple_node()
  result <- parse_response(42, node)
  expect_equal(result@recommendation_text, "")
})

# -- parse_response: transition validation -------------------------------------

test_that("invalid transition signal triggers warning and sets NULL", {
  resp <- '{"recommendation_text": "Go X", "transition_signal": "nonexistent"}'
  node <- make_simple_node()
  expect_warning(
    result <- parse_response(resp, node, c("node_a", "node_b")),
    "Invalid transition"
  )
  expect_null(result@transition_signal)
})

test_that("valid transition signal passes through", {
  resp <- '{"recommendation_text": "Go B", "transition_signal": "node_b"}'
  node <- make_simple_node()
  result <- parse_response(resp, node, c("node_a", "node_b"))
  expect_equal(result@transition_signal, "node_b")
})

test_that("transition validation skipped when no candidates", {
  resp <- '{"recommendation_text": "t", "transition_signal": "any"}'
  node <- make_simple_node()
  result <- parse_response(resp, node, character(0))
  expect_equal(result@transition_signal, "any")
})

# -- parse_response: alternate JSON keys ---------------------------------------

test_that("alternate key 'value' maps to suggested_value", {
  resp <- '{"recommendation": "Use RR", "value": "RR"}'
  node <- make_simple_node()
  result <- parse_response(resp, node)
  expect_equal(result@recommendation_text, "Use RR")
  expect_equal(result@suggested_value, "RR")
})

test_that("alternate key 'next_node' maps to transition_signal", {
  resp <- '{"recommendation_text": "t", "next_node": "b"}'
  node <- make_simple_node()
  result <- parse_response(resp, node, c("a", "b"))
  expect_equal(result@transition_signal, "b")
})
