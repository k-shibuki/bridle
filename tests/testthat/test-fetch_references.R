# Tests for fetch_references() (CrossRef / PubMed API)
# Follows test-strategy.mdc: Given/When/Then, failure >= success cases
# All HTTP calls mocked via local_mocked_bindings on thin wrappers

# mock_crossref_response provided by helper-mocks.R

make_scan_result_with_refs <- function(refs) {
  ScanResult( # nolint: object_usage_linter. S7 class in R/scan_result.R
    package = "testpkg",
    func = "testfn",
    parameters = list(
      ParameterInfo(name = "x", has_default = TRUE) # nolint: object_usage_linter.
    ),
    references = refs,
    scan_metadata = list(
      layers_completed = "layer1_formals",
      timestamp = "2026-01-01T00:00:00+0000",
      package_version = "0.0.1"
    )
  )
}

# -- extract_dois() ------------------------------------------------------------

test_that("extract_dois: extracts DOI from reference string", {
  # Given: reference text containing a DOI
  # When:  extracting DOIs
  # Then:  returns the DOI
  refs <- "Author (2020). Title. doi:10.1234/test.article"
  dois <- bridle:::extract_dois(refs)
  expect_true("10.1234/test.article" %in% dois)
})

test_that("extract_dois: extracts multiple DOIs", {
  # Given: references with different DOIs
  # When:  extracting
  # Then:  returns all unique DOIs
  refs <- c(
    "Paper A. doi:10.1234/a",
    "Paper B. https://doi.org/10.5678/b"
  )
  dois <- bridle:::extract_dois(refs)
  expect_true("10.1234/a" %in% dois)
  expect_true("10.5678/b" %in% dois)
})

test_that("extract_dois: returns empty for no DOIs", {
  # Given: references without DOIs
  # When:  extracting
  # Then:  returns empty character
  refs <- c("Author (2020). Title. Journal 1:1-10.")
  dois <- bridle:::extract_dois(refs)
  expect_equal(dois, character(0))
})

test_that("extract_dois: deduplicates", {
  # Given: same DOI appearing twice
  # When:  extracting
  # Then:  returns unique
  refs <- c("A. doi:10.1234/same", "B. 10.1234/same")
  dois <- bridle:::extract_dois(refs)
  expect_equal(sum(dois == "10.1234/same"), 1L)
})

# -- parse_crossref_response() ------------------------------------------------

test_that("parse_crossref_response: extracts metadata", {
  # Given: a mock CrossRef response
  # When:  parsing
  # Then:  returns structured metadata
  resp <- mock_crossref_response()
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.

  meta <- bridle:::parse_crossref_response(resp)
  expect_equal(meta$doi, "10.1234/test")
  expect_equal(meta$title, "Test Paper")
  expect_equal(meta$authors, "John Doe")
  expect_equal(meta$abstract, "An abstract.")
  expect_equal(meta$journal, "Test Journal")
  expect_equal(meta$year, 2020L)
})

test_that("parse_crossref_response: handles missing author", {
  # Given: response without authors
  # When:  parsing
  # Then:  authors is empty character
  resp <- mock_crossref_response(authors = NULL)
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.

  meta <- bridle:::parse_crossref_response(resp)
  expect_equal(meta$authors, character(0))
})

test_that("parse_crossref_response: handles missing abstract", {
  # Given: response without abstract
  # When:  parsing
  # Then:  abstract is empty string
  resp <- mock_crossref_response(abstract = NULL)
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.

  meta <- bridle:::parse_crossref_response(resp)
  expect_equal(meta$abstract, "")
})

# -- extract_abstract_from_xml() -----------------------------------------------

test_that("extract_abstract_from_xml: extracts text", {
  # Given: PubMed XML with AbstractText
  # When:  extracting
  # Then:  returns abstract text
  xml <- "<Abstract><AbstractText>The result shows...</AbstractText></Abstract>"
  result <- bridle:::extract_abstract_from_xml(xml)
  expect_equal(result, "The result shows...")
})

test_that("extract_abstract_from_xml: handles multiple sections", {
  # Given: structured abstract with multiple AbstractText elements
  # When:  extracting
  # Then:  concatenates all parts
  xml <- paste0(
    '<AbstractText Label="BACKGROUND">Bg.</AbstractText>',
    '<AbstractText Label="METHODS">Methods.</AbstractText>'
  )
  result <- bridle:::extract_abstract_from_xml(xml)
  expect_true(grepl("Bg\\.", result))
  expect_true(grepl("Methods\\.", result))
})

test_that("extract_abstract_from_xml: returns NULL for no abstract", {
  # Given: XML without AbstractText
  # When:  extracting
  # Then:  returns NULL
  xml <- "<PubmedArticle><Title>No abstract</Title></PubmedArticle>"
  result <- bridle:::extract_abstract_from_xml(xml)
  expect_null(result)
})

# -- extract_crossref_authors() ------------------------------------------------

test_that("extract_crossref_authors: formats names", {
  # Given: author list with given and family names
  # When:  extracting
  # Then:  returns formatted names
  authors <- list(
    list(given = "Alice", family = "Smith"),
    list(given = "Bob", family = "Jones")
  )
  result <- bridle:::extract_crossref_authors(authors)
  expect_equal(result, c("Alice Smith", "Bob Jones"))
})

test_that("extract_crossref_authors: handles missing given name", {
  # Given: author without given name
  # When:  extracting
  # Then:  returns family name only
  authors <- list(list(family = "Consortium"))
  result <- bridle:::extract_crossref_authors(authors)
  expect_equal(result, "Consortium")
})

# -- fetch_references() integration tests --------------------------------------

test_that("fetch_references: empty references returns empty", {
  # Given: ScanResult with no references
  # When:  fetching references
  # Then:  returns empty list
  sr <- make_scan_result_with_refs(character(0))
  result <- fetch_references(sr)
  expect_equal(result, list())
})

test_that("fetch_references: references without DOIs returns empty", {
  # Given: ScanResult with references that have no DOIs
  # When:  fetching references
  # Then:  returns empty list (no DOIs to resolve)
  sr <- make_scan_result_with_refs("Author (2020). Title. Journal.")
  result <- fetch_references(sr)
  expect_equal(result, list())
})

test_that("fetch_references: successful DOI resolution", {
  # Given: ScanResult with a reference containing a DOI
  # When:  fetching with mocked CrossRef
  # Then:  returns structured metadata
  sr <- make_scan_result_with_refs("Author (2020). doi:10.1234/test")

  mock_resp <- mock_crossref_response()
  local_mocked_bindings(crossref_get = function(doi, mailto, timeout) mock_resp) # nolint: object_usage_linter.
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.

  result <- fetch_references(sr)
  expect_length(result, 1L)
  expect_equal(result[[1L]]$title, "Test Paper")
  expect_equal(result[[1L]]$doi, "10.1234/test")
})

test_that("fetch_references: network error produces warning", {
  # Given: CrossRef API returns an error
  # When:  fetching
  # Then:  warning emitted, empty result for that DOI
  sr <- make_scan_result_with_refs("Author. doi:10.1234/fail")

  local_mocked_bindings(crossref_get = function(doi, mailto, timeout) { # nolint: object_usage_linter.
    stop("Connection timeout")
  })

  expect_warning(
    result <- fetch_references(sr),
    "Failed to fetch metadata"
  )
  expect_length(result, 0L)
})

test_that("fetch_references: PubMed fallback for missing abstract", {
  # Given: CrossRef returns no abstract, PubMed has one
  # When:  fetching
  # Then:  abstract retrieved from PubMed
  sr <- make_scan_result_with_refs("Author. doi:10.1234/noabs")

  mock_resp <- mock_crossref_response(abstract = NULL)
  local_mocked_bindings(crossref_get = function(doi, mailto, timeout) mock_resp) # nolint: object_usage_linter.
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.
  local_mocked_bindings(fetch_pubmed_abstract = function(title, timeout) { # nolint: object_usage_linter.
    "PubMed abstract text"
  })

  result <- fetch_references(sr)
  expect_length(result, 1L)
  expect_equal(result[[1L]]$abstract, "PubMed abstract text")
})

test_that("fetch_references: PubMed failure doesn't break flow", {
  # Given: CrossRef works but PubMed fails
  # When:  fetching
  # Then:  result has empty abstract, no error
  sr <- make_scan_result_with_refs("Author. doi:10.1234/nopub")

  mock_resp <- mock_crossref_response(abstract = NULL)
  local_mocked_bindings(crossref_get = function(doi, mailto, timeout) mock_resp) # nolint: object_usage_linter.
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.
  local_mocked_bindings(fetch_pubmed_abstract = function(title, timeout) { # nolint: object_usage_linter.
    stop("PubMed unavailable")
  })

  result <- fetch_references(sr)
  expect_length(result, 1L)
  expect_equal(result[[1L]]$abstract, "")
})

test_that("fetch_references: multiple DOIs with mixed success", {
  # Given: two DOIs, one succeeds and one fails
  # When:  fetching
  # Then:  returns partial results with warning
  sr <- make_scan_result_with_refs(c(
    "A. doi:10.1234/good",
    "B. doi:10.1234/bad"
  ))

  call_count <- 0L
  local_mocked_bindings(crossref_get = function(doi, mailto, timeout) { # nolint: object_usage_linter.
    call_count <<- call_count + 1L
    if (grepl("bad", doi)) stop("Not found")
    mock_crossref_response(doi = doi)
  })
  local_mocked_bindings(resp_body_json = function(resp) resp$body, .package = "httr2") # nolint: object_usage_linter.

  expect_warning(
    result <- fetch_references(sr),
    "Failed to fetch"
  )
  expect_length(result, 1L)
  expect_equal(result[[1L]]$doi, "10.1234/good")
})
