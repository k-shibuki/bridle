# Tests for fetch_references() (OpenAlex / Semantic Scholar API)
# Issue #132: 27 scenarios (T01-T27)
# Mock points: openalex_get, s2_get (thin HTTP wrappers)

make_scan_result_with_refs <- function(refs) {
  ScanResult( # nolint: object_usage_linter. S7 constructor
    package = "testpkg",
    func = "testfn",
    parameters = list(
      ParameterInfo(name = "x", has_default = TRUE) # nolint: object_usage_linter. S7 constructor
    ),
    references = refs,
    scan_metadata = list(
      layers_completed = "layer1_formals",
      timestamp = "2026-01-01T00:00:00+0000",
      package_version = "0.0.1"
    )
  )
}

init_anonymous_profile <- function() {
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = NA,
    BRIDLE_S2_API_KEY = NA,
    .local_envir = parent.frame()
  )
  suppressWarnings(bridle:::detect_profiles())
}

# -- T01-T04: extract_dois() --------------------------------------------------

test_that("T01: extracts DOI from reference string", {
  # Given: reference text containing a DOI
  # When:  extracting DOIs
  # Then:  returns the DOI
  refs <- "Author (2020). Title. doi:10.1234/test.article"
  dois <- bridle:::extract_dois(refs)
  expect_true("10.1234/test.article" %in% dois)
})

test_that("T02: extracts multiple DOIs", {
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

test_that("T03: returns empty for no DOIs", {
  # Given: references without DOIs
  # When:  extracting
  # Then:  returns empty character
  refs <- c("Author (2020). Title. Journal 1:1-10.")
  dois <- bridle:::extract_dois(refs)
  expect_equal(dois, character(0))
})

test_that("T04: deduplicates DOIs", {
  # Given: same DOI appearing twice
  # When:  extracting
  # Then:  returns unique
  refs <- c("A. doi:10.1234/same", "B. 10.1234/same")
  dois <- bridle:::extract_dois(refs)
  expect_equal(sum(dois == "10.1234/same"), 1L)
})

# -- T05-T09: OpenAlex parsing ------------------------------------------------

test_that("T05: OA metadata parsing", {
  # Given: a mock OpenAlex response with all fields
  # When:  parsing
  # Then:  returns structured metadata with correct field mapping
  resp <- mock_openalex_response(
    doi = "10.1002/jrsm.1211",
    title = "metafor Package",
    authors = list(
      list(author = list(display_name = "Wolfgang Viechtbauer")),
      list(author = list(display_name = "Jane Doe"))
    ),
    abstract_inverted_index = list(
      Conducting = list(0L), `meta-analyses` = list(1L),
      `in` = list(2L), R = list(3L)
    ),
    journal = "Research Synthesis Methods",
    year = 2010L
  )
  meta <- bridle:::parse_openalex_response(resp)

  expect_equal(meta$doi, "10.1002/jrsm.1211")
  expect_equal(meta$title, "metafor Package")
  expect_equal(meta$authors, c("Wolfgang Viechtbauer", "Jane Doe"))
  expect_equal(meta$abstract, "Conducting meta-analyses in R")
  expect_equal(meta$journal, "Research Synthesis Methods")
  expect_equal(meta$year, 2010L)
})

test_that("T06: abstract reconstruction from inverted index", {
  # Given: an inverted index mapping words to positions
  # When:  reconstructing
  # Then:  produces correct word order
  idx <- list(The = list(0L), result = list(1L), is = list(2L))
  result <- bridle:::reconstruct_abstract(idx)
  expect_equal(result, "The result is")
})

test_that("T07: empty inverted index returns NULL", {
  # Given: an empty named list (JSON {})
  # When:  reconstructing
  # Then:  returns NULL
  expect_null(bridle:::reconstruct_abstract(setNames(list(), character(0))))
  expect_null(bridle:::reconstruct_abstract(list()))
})

test_that("T08: NULL inverted index returns NULL", {
  # Given: NULL input
  # When:  reconstructing
  # Then:  returns NULL
  expect_null(bridle:::reconstruct_abstract(NULL))
})

test_that("T09: DOI normalization strips https prefix", {
  # Given: OA response with full DOI URL
  # When:  parsing
  # Then:  DOI prefix is stripped
  resp <- mock_openalex_response(doi = "10.1234/x")
  meta <- bridle:::parse_openalex_response(resp)
  expect_equal(meta$doi, "10.1234/x")
})

# -- T10-T11: Semantic Scholar parsing -----------------------------------------

test_that("T10: S2 metadata parsing", {
  # Given: a mock S2 response with all fields
  # When:  parsing
  # Then:  returns structured metadata with correct field mapping
  resp <- mock_s2_response(
    doi = "10.1002/jrsm.1211",
    title = "metafor Package",
    authors = list(
      list(name = "Wolfgang Viechtbauer")
    ),
    abstract = "A comprehensive meta-analysis package.",
    venue = "Research Synthesis Methods",
    year = 2010L
  )
  meta <- bridle:::parse_s2_response(resp)

  expect_equal(meta$doi, "10.1002/jrsm.1211")
  expect_equal(meta$title, "metafor Package")
  expect_equal(meta$authors, "Wolfgang Viechtbauer")
  expect_equal(meta$abstract, "A comprehensive meta-analysis package.")
  expect_equal(meta$journal, "Research Synthesis Methods")
  expect_equal(meta$year, 2010L)
})

test_that("T11: S2 DOI prefix in request URL", {
  # Given: a DOI 10.1234/test
  # When:  fetch_s2 calls s2_get
  # Then:  s2_get receives the DOI (URL prefix DOI: applied inside s2_get)
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  captured_doi <- NULL
  local_mocked_bindings(s2_get = function(doi, timeout) {
    captured_doi <<- doi
    mock_s2_response(doi = doi)
  })

  bridle:::fetch_s2("10.1234/test", timeout = 1)
  expect_equal(captured_doi, "10.1234/test")
})

# -- T12-T14: Profile detection ------------------------------------------------

test_that("T12: anonymous profile when no env vars", {
  # Given: no API credentials configured
  # When:  detecting profiles
  # Then:  anonymous intervals selected, warning emitted
  bridle:::reset_api_state()
  withr::local_envvar(BRIDLE_OPENALEX_EMAIL = NA, BRIDLE_S2_API_KEY = NA)

  expect_warning(bridle:::detect_profiles(), "No API credentials")
  expect_equal(bridle:::.api_state$oa_interval, 0.33)
  expect_equal(bridle:::.api_state$s2_interval, 3.0)
  expect_null(bridle:::.api_state$oa_email)
  expect_null(bridle:::.api_state$s2_api_key)
})

test_that("T13: identified OA profile with email", {
  # Given: BRIDLE_OPENALEX_EMAIL is set
  # When:  detecting profiles
  # Then:  identified interval, email stored
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = "test@example.com",
    BRIDLE_S2_API_KEY = NA
  )

  bridle:::detect_profiles()
  expect_equal(bridle:::.api_state$oa_interval, 0.25)
  expect_equal(bridle:::.api_state$oa_email, "test@example.com")
})

test_that("T14: authenticated S2 profile with API key", {
  # Given: BRIDLE_S2_API_KEY is set
  # When:  detecting profiles
  # Then:  authenticated interval, key stored
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = NA,
    BRIDLE_S2_API_KEY = "test-key-abc"
  )

  bridle:::detect_profiles()
  expect_equal(bridle:::.api_state$s2_interval, 1.1)
  expect_equal(bridle:::.api_state$s2_api_key, "test-key-abc")
})

# -- T15-T27: fetch_references integration ------------------------------------

test_that("T15: empty references returns empty list", {
  # Given: ScanResult with no references
  # When:  fetching references
  # Then:  returns empty list without API calls
  sr <- make_scan_result_with_refs(character(0))
  result <- fetch_references(sr)
  expect_equal(result, list())
})

test_that("T16: references without DOIs returns empty list", {
  # Given: ScanResult with references lacking DOIs
  # When:  fetching references
  # Then:  returns empty list
  sr <- make_scan_result_with_refs("Author (2020). Title. Journal.")
  result <- fetch_references(sr)
  expect_equal(result, list())
})

test_that("T17: successful OA lookup", {
  # Given: ScanResult with DOI, OA returns full metadata
  # When:  fetching references
  # Then:  returns structured metadata from OA
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  local_mocked_bindings(openalex_get = function(doi, timeout) {
    mock_openalex_response(doi = doi)
  })

  sr <- make_scan_result_with_refs("Author (2020). doi:10.1234/test")
  result <- fetch_references(sr)

  expect_length(result, 1L)
  expect_equal(result[[1L]]$doi, "10.1234/test")
  expect_equal(result[[1L]]$title, "Test Paper")
  expect_equal(result[[1L]]$abstract, "An abstract")
})

test_that("T18: OA missing abstract triggers S2 fallback", {
  # Given: OA returns metadata without abstract, S2 has abstract
  # When:  fetching references
  # Then:  abstract from S2 supplements OA metadata
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      mock_openalex_response(doi = doi, abstract_inverted_index = NULL)
    },
    s2_get = function(doi, timeout) {
      mock_s2_response(doi = doi, abstract = "S2 abstract text")
    }
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/noabs")
  result <- fetch_references(sr)

  expect_length(result, 1L)
  expect_equal(result[[1L]]$abstract, "S2 abstract text")
  expect_equal(result[[1L]]$title, "Test Paper")
})

test_that("T19: OA 404 promotes S2 to full metadata source", {
  # Given: OA returns 404, S2 has full metadata
  # When:  fetching references
  # Then:  full metadata from S2
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      mock_openalex_response(status = 404L)
    },
    s2_get = function(doi, timeout) {
      mock_s2_response(
        doi = doi, title = "S2 Title",
        abstract = "S2 abstract", venue = "S2 Journal"
      )
    }
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/oa404")
  result <- fetch_references(sr)

  expect_length(result, 1L)
  expect_equal(result[[1L]]$title, "S2 Title")
  expect_equal(result[[1L]]$abstract, "S2 abstract")
  expect_equal(result[[1L]]$journal, "S2 Journal")
})

test_that("T20: OA network error warns and skips DOI", {
  # Given: OA throws a connection error
  # When:  fetching references
  # Then:  warning emitted, S2 fallback attempted
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL), # nolint: object_usage_linter. mock binding
    openalex_get = function(doi, timeout) stop("Connection timeout"),
    s2_get = function(doi, timeout) mock_s2_response(doi = doi)
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/fail")
  expect_warning(
    result <- fetch_references(sr),
    "OpenAlex request failed"
  )
  expect_length(result, 1L)
})

test_that("T21: S2 fallback also fails leaves DOI skipped", {
  # Given: OA returns empty abstract, S2 returns 404
  # When:  fetching references
  # Then:  metadata returned with empty abstract
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      mock_openalex_response(doi = doi, abstract_inverted_index = NULL)
    },
    s2_get = function(doi, timeout) {
      mock_s2_response(status = 404L)
    }
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/nofallback")
  result <- fetch_references(sr)

  expect_length(result, 1L)
  expect_null(result[[1L]]$abstract)
})

test_that("T22: S2 auth downgrade on 401", {
  # Given: S2 returns 401 first, then succeeds after downgrade
  # When:  fetching references (OA 404 triggers S2 full metadata path)
  # Then:  auth downgraded, warning emitted, metadata retrieved
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = NA,
    BRIDLE_S2_API_KEY = "test-key"
  )
  suppressWarnings(bridle:::detect_profiles())
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )

  s2_calls <- 0L
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      mock_openalex_response(status = 404L)
    },
    s2_get = function(doi, timeout) {
      s2_calls <<- s2_calls + 1L
      if (s2_calls == 1L) {
        mock_s2_response(status = 401L)
      } else {
        mock_s2_response(doi = doi, title = "After Downgrade")
      }
    }
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/authtest")
  expect_warning(
    result <- fetch_references(sr),
    "API key rejected"
  )

  expect_true(bridle:::.api_state$s2_downgraded)
  expect_null(bridle:::.api_state$s2_api_key)
  expect_equal(bridle:::.api_state$s2_interval, 3.0)
  expect_length(result, 1L)
  expect_equal(result[[1L]]$title, "After Downgrade")
})

test_that("T23: rate limiting enforced between requests", {
  # Given: two DOIs with identified OA profile (0.25s interval)
  # When:  fetching references
  # Then:  second OA request delayed by interval
  bridle:::reset_api_state()
  withr::local_envvar(
    BRIDLE_OPENALEX_EMAIL = "test@example.com",
    BRIDLE_S2_API_KEY = NA
  )
  bridle:::detect_profiles()
  api_state <- bridle:::.api_state
  api_state$oa_interval <- 0.1

  call_times <- numeric(0)
  local_mocked_bindings(openalex_get = function(doi, timeout) {
    call_times <<- c(call_times, proc.time()[["elapsed"]])
    mock_openalex_response(doi = doi)
  })

  sr <- make_scan_result_with_refs(c(
    "A. doi:10.1234/a",
    "B. doi:10.5678/b"
  ))
  result <- fetch_references(sr)

  expect_length(result, 2L)
  expect_length(call_times, 2L)
  expect_gte(call_times[2L] - call_times[1L], 0.08)
})

test_that("T24: 429 expands interval by 1.5x", {
  # Given: OA returns 429 after retries
  # When:  fetching references
  # Then:  oa_interval multiplied by 1.5, streak incremented
  init_anonymous_profile()
  original_interval <- bridle:::.api_state$oa_interval
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      mock_openalex_response(status = 429L)
    },
    s2_get = function(doi, timeout) mock_s2_response(doi = doi)
  )

  sr <- make_scan_result_with_refs("Author. doi:10.1234/throttled")
  fetch_references(sr)

  expect_equal(
    bridle:::.api_state$oa_interval,
    original_interval * 1.5
  )
  expect_equal(bridle:::.api_state$oa_429_streak, 1L)
})

test_that("T25: no-env-var warning fires exactly once", {
  # Given: no env vars set
  # When:  detect_profiles called twice
  # Then:  warning emitted once (idempotency guard)
  bridle:::reset_api_state()
  withr::local_envvar(BRIDLE_OPENALEX_EMAIL = NA, BRIDLE_S2_API_KEY = NA)

  expect_warning(bridle:::detect_profiles(), "No API credentials")
  expect_no_warning(bridle:::detect_profiles())
  expect_true(bridle:::.api_state$warned_no_env)
})

test_that("T26: multiple DOIs with partial success", {
  # Given: two DOIs, first OA succeeds, second OA errors
  # When:  fetching references
  # Then:  1 result + warning, S2 fallback for failed DOI
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )

  oa_call <- 0L
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      oa_call <<- oa_call + 1L
      if (oa_call == 1L) {
        mock_openalex_response(doi = doi, title = "Paper A")
      } else {
        stop("Network error")
      }
    },
    s2_get = function(doi, timeout) {
      mock_s2_response(doi = doi, title = "Paper B from S2")
    }
  )

  sr <- make_scan_result_with_refs(c(
    "A. doi:10.1234/good",
    "B. doi:10.1234/bad"
  ))
  expect_warning(
    result <- fetch_references(sr),
    "OpenAlex request failed"
  )

  expect_length(result, 2L)
  expect_equal(result[[1L]]$title, "Paper A")
  expect_equal(result[[2L]]$title, "Paper B from S2")
})

test_that("T27: state persistence across fetch_references calls", {
  # Given: first call triggers 429 → interval expanded
  # When:  second call made
  # Then:  expanded interval persists (not reset by detect_profiles)
  init_anonymous_profile()
  local_mocked_bindings(
    rate_limit_sleep = function(s) invisible(NULL) # nolint: object_usage_linter. mock binding
  )

  oa_call <- 0L
  local_mocked_bindings(
    openalex_get = function(doi, timeout) {
      oa_call <<- oa_call + 1L
      if (oa_call == 1L) {
        mock_openalex_response(status = 429L)
      } else {
        mock_openalex_response(doi = doi)
      }
    },
    s2_get = function(doi, timeout) mock_s2_response(doi = doi)
  )

  sr1 <- make_scan_result_with_refs("A. doi:10.1234/first")
  fetch_references(sr1)

  expanded <- bridle:::.api_state$oa_interval
  expect_gt(expanded, 0.33)

  sr2 <- make_scan_result_with_refs("B. doi:10.5678/second")
  fetch_references(sr2)

  expect_equal(bridle:::.api_state$oa_interval, expanded)
})
