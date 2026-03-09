#' Fetch Reference Metadata
#'
#' Resolves DOIs and retrieves bibliographic metadata (title, authors,
#' abstract) via OpenAlex and Semantic Scholar APIs to enrich the
#' `ScanResult` reference list for the AI Drafter.
#'
#' @name fetch_references
#' @importFrom rlang %||%
NULL

# -- API state management -----------------------------------------------------

.api_state <- new.env(parent = emptyenv())

#' Detect API profiles from environment variables
#'
#' Initializes `.api_state` with rate-limit intervals and credentials
#' based on `BRIDLE_OPENALEX_EMAIL` and `BRIDLE_S2_API_KEY`.
#' Idempotent: skips if already initialized, preserving dynamic interval
#' expansions and auth downgrade state across multiple calls.
#' @keywords internal
detect_profiles <- function() {
  if (isTRUE(.api_state$initialized)) {
    return(invisible(NULL))
  }

  oa_email <- Sys.getenv("BRIDLE_OPENALEX_EMAIL", unset = "")
  s2_key <- Sys.getenv("BRIDLE_S2_API_KEY", unset = "")

  .api_state$oa_email <- if (nzchar(oa_email)) oa_email else NULL
  .api_state$oa_interval <- if (nzchar(oa_email)) 0.25 else 0.33
  .api_state$oa_last <- 0
  .api_state$oa_429_streak <- 0L

  .api_state$s2_api_key <- if (nzchar(s2_key)) s2_key else NULL
  .api_state$s2_interval <- if (nzchar(s2_key)) 1.1 else 3.0
  .api_state$s2_last <- 0
  .api_state$s2_429_streak <- 0L
  .api_state$s2_downgraded <- FALSE

  .api_state$warned_no_env <- FALSE

  if (!nzchar(oa_email) && !nzchar(s2_key)) {
    cli::cli_warn(c(
      "No API credentials configured.",
      "i" = "Set {.envvar BRIDLE_OPENALEX_EMAIL} for faster OpenAlex access.",
      "i" = "Set {.envvar BRIDLE_S2_API_KEY} for faster Semantic Scholar access."
    ))
    .api_state$warned_no_env <- TRUE
  }

  .api_state$initialized <- TRUE
  invisible(NULL)
}

#' Reset API state for testing
#' @keywords internal
reset_api_state <- function() {
  rm(list = ls(.api_state), envir = .api_state)
  invisible(NULL)
}

#' Wrapper around Sys.sleep for testability
#' @keywords internal
rate_limit_sleep <- function(seconds) {
  Sys.sleep(seconds)
}

#' Enforce per-API rate limit
#'
#' Sleeps if the minimum interval since the last request has not elapsed,
#' then updates the last-request timestamp.
#' @param api `"openalex"` or `"s2"`.
#' @keywords internal
enforce_rate_limit <- function(api) {
  prefix <- switch(api,
    openalex = "oa",
    s2 = "s2"
  )
  interval <- .api_state[[paste0(prefix, "_interval")]]
  last <- .api_state[[paste0(prefix, "_last")]]

  elapsed <- proc.time()[["elapsed"]] - last
  if (elapsed < interval) {
    rate_limit_sleep(interval - elapsed)
  }

  .api_state[[paste0(prefix, "_last")]] <- proc.time()[["elapsed"]]
  invisible(NULL)
}

# -- Abstract reconstruction --------------------------------------------------

#' Reconstruct abstract from OpenAlex inverted index
#'
#' OpenAlex stores abstracts as a mapping from words to position indices.
#' Returns `NULL` for `NULL` or empty input.
#' @param inverted_index Named list mapping words to integer position vectors.
#' @return Character string or `NULL`.
#' @keywords internal
reconstruct_abstract <- function(inverted_index) {
  if (is.null(inverted_index) || length(inverted_index) == 0L) {
    return(NULL)
  }
  positions <- unlist(inverted_index, use.names = TRUE)
  words <- rep(names(inverted_index), lengths(inverted_index))
  paste(words[order(positions)], collapse = " ")
}

# -- DOI extraction -----------------------------------------------------------

#' Extract DOIs from reference strings
#' @keywords internal
extract_dois <- function(refs) {
  doi_pattern <- "10\\.\\d{4,}/[^\\s,;]+"
  dois <- character(0)
  for (ref in refs) {
    m <- regmatches(ref, gregexpr(doi_pattern, ref, perl = TRUE))[[1L]]
    dois <- c(dois, m)
  }
  unique(trimws(gsub("[.)]+$", "", dois)))
}

# -- OpenAlex API layer -------------------------------------------------------

#' Perform HTTP GET to OpenAlex API
#'
#' Thin wrapper for mocking. Uses `select` to limit response fields
#' and `mailto` for identified-profile requests.
#' @keywords internal
openalex_get <- function(doi, timeout = 10) {
  url <- paste0("https://api.openalex.org/works/https://doi.org/", doi)
  req <- httr2::request(url)
  req <- httr2::req_url_query(req,
    select = paste0(
      "id,title,abstract_inverted_index,publication_year,",
      "authorships,doi,primary_location"
    )
  )
  if (!is.null(.api_state$oa_email)) {
    req <- httr2::req_url_query(req, mailto = .api_state$oa_email)
  }
  req <- httr2::req_headers(req, `User-Agent` = "bridle R package")
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(req, max_tries = 3, backoff = ~2)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  httr2::req_perform(req)
}

#' Parse OpenAlex API response into structured metadata
#' @keywords internal
parse_openalex_response <- function(resp) {
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)

  doi_raw <- body[["doi"]] %||% ""
  doi <- sub("^https://doi\\.org/", "", doi_raw)

  title <- body[["title"]] %||% ""

  authorships <- body[["authorships"]] %||% list()
  authors <- vapply(authorships, function(a) {
    a[["author"]][["display_name"]] %||% ""
  }, character(1))

  abstract <- reconstruct_abstract(body[["abstract_inverted_index"]])

  journal <- body[["primary_location"]][["source"]][["display_name"]]

  year <- body[["publication_year"]]
  if (!is.null(year)) year <- as.integer(year)

  list(
    doi = doi,
    title = title,
    authors = authors,
    abstract = abstract,
    journal = journal %||% NA_character_,
    year = year %||% NA_integer_
  )
}

#' Fetch metadata from OpenAlex with rate limiting and error handling
#'
#' Returns parsed metadata on success, `NULL` on 404 or error.
#' Tracks 429 streak and expands rate-limit interval on throttling.
#' @keywords internal
fetch_openalex <- function(doi, timeout = 10) {
  enforce_rate_limit("openalex")
  resp <- tryCatch(
    openalex_get(doi, timeout),
    error = function(e) {
      cli::cli_warn(
        "OpenAlex request failed for DOI {.val {doi}}: {conditionMessage(e)}"
      )
      NULL
    }
  )
  if (is.null(resp)) {
    return(NULL)
  }

  status <- httr2::resp_status(resp)

  if (status == 429L) {
    .api_state$oa_429_streak <- .api_state$oa_429_streak + 1L
    .api_state$oa_interval <- .api_state$oa_interval * 1.5
    threshold <- if (!is.null(.api_state$oa_email)) 5L else 2L
    if (.api_state$oa_429_streak >= threshold) {
      cli::cli_warn(
        "OpenAlex rate limit exceeded; skipping remaining DOIs."
      )
    }
    return(NULL)
  }
  if (status == 404L) {
    return(NULL)
  }
  if (status >= 400L) {
    cli::cli_warn("OpenAlex returned HTTP {status} for DOI {.val {doi}}")
    return(NULL)
  }

  .api_state$oa_429_streak <- 0L
  parse_openalex_response(resp)
}

# -- Semantic Scholar API layer ------------------------------------------------

#' Perform HTTP GET to Semantic Scholar API
#'
#' Thin wrapper for mocking. Includes `x-api-key` header when authenticated.
#' @keywords internal
s2_get <- function(doi, timeout = 10) {
  url <- paste0(
    "https://api.semanticscholar.org/graph/v1/paper/DOI:", doi
  )
  req <- httr2::request(url)
  req <- httr2::req_url_query(req,
    fields = "paperId,title,abstract,year,authors,venue,externalIds"
  )
  if (!is.null(.api_state$s2_api_key)) {
    req <- httr2::req_headers(req, `x-api-key` = .api_state$s2_api_key)
  }
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(req, max_tries = 3, backoff = ~2)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  httr2::req_perform(req)
}

#' Parse Semantic Scholar API response into structured metadata
#' @keywords internal
parse_s2_response <- function(resp) {
  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)

  doi <- body[["externalIds"]][["DOI"]] %||% ""
  title <- body[["title"]] %||% ""

  author_list <- body[["authors"]] %||% list()
  authors <- vapply(author_list, function(a) {
    a[["name"]] %||% ""
  }, character(1))

  abstract <- body[["abstract"]]

  journal <- body[["venue"]]
  if (identical(journal, "")) journal <- NA_character_

  year <- body[["year"]]
  if (!is.null(year)) year <- as.integer(year)

  list(
    doi = doi,
    title = title,
    authors = authors,
    abstract = abstract,
    journal = journal %||% NA_character_,
    year = year %||% NA_integer_
  )
}

#' Fetch metadata from Semantic Scholar with rate limiting and error handling
#'
#' Handles auth downgrade (401/403 → anonymous), 429 streak tracking,
#' and dynamic interval expansion.
#' @keywords internal
fetch_s2 <- function(doi, timeout = 10) {
  enforce_rate_limit("s2")
  resp <- tryCatch(
    s2_get(doi, timeout),
    error = function(e) {
      cli::cli_warn(
        "Semantic Scholar request failed for DOI {.val {doi}}: {conditionMessage(e)}"
      )
      NULL
    }
  )
  if (is.null(resp)) {
    return(NULL)
  }

  status <- httr2::resp_status(resp)

  if (status %in% c(401L, 403L) && !.api_state$s2_downgraded) {
    .api_state$s2_downgraded <- TRUE
    .api_state$s2_interval <- 3.0
    .api_state$s2_api_key <- NULL
    cli::cli_warn(
      "Semantic Scholar API key rejected; falling back to anonymous access."
    )
    enforce_rate_limit("s2")
    resp <- tryCatch(
      s2_get(doi, timeout),
      error = function(e) NULL
    )
    if (is.null(resp)) {
      return(NULL)
    }
    status <- httr2::resp_status(resp)
  }

  if (status == 429L) {
    .api_state$s2_429_streak <- .api_state$s2_429_streak + 1L
    .api_state$s2_interval <- .api_state$s2_interval * 1.5
    threshold <- if (!is.null(.api_state$s2_api_key)) 5L else 2L
    if (.api_state$s2_429_streak >= threshold) {
      cli::cli_warn(
        "Semantic Scholar rate limit exceeded; skipping remaining DOIs."
      )
    }
    return(NULL)
  }
  if (status == 404L) {
    return(NULL)
  }
  if (status >= 400L) {
    return(NULL)
  }

  .api_state$s2_429_streak <- 0L
  parse_s2_response(resp)
}

#' Fetch only the abstract from Semantic Scholar
#'
#' Delegates to [fetch_s2()] and extracts the abstract field.
#' @keywords internal
fetch_s2_abstract <- function(doi, timeout = 10) {
  meta <- fetch_s2(doi, timeout)
  if (is.null(meta)) {
    return(NULL)
  }
  meta$abstract
}

# -- Public API ---------------------------------------------------------------

#' Collect DOIs from a PackageScanResult across all scanned functions
#'
#' Iterates over `@functions`, extracts `@references` from each
#' [ScanResult], and returns a deduplicated DOI vector.
#' @param pkg_result A [PackageScanResult] object.
#' @return Character vector of unique DOIs.
#' @keywords internal
collect_package_dois <- function(pkg_result) {
  all_refs <- character(0)
  for (sr in pkg_result@functions) {
    all_refs <- c(all_refs, sr@references)
  }
  if (length(all_refs) == 0L) {
    return(character(0))
  }
  extract_dois(all_refs)
}

#' Fetch reference metadata for a set of DOIs
#'
#' Shared implementation used by both [ScanResult] and [PackageScanResult]
#' code paths. Handles rate limiting, OpenAlex primary + S2 fallback.
#' @param dois Character vector of DOIs to fetch.
#' @param timeout Request timeout in seconds.
#' @return A list of reference metadata lists.
#' @keywords internal
fetch_dois <- function(dois, timeout = 10) {
  if (length(dois) == 0L) {
    return(list())
  }

  detect_profiles()

  results <- list()

  for (doi in dois) {
    oa_threshold <- if (!is.null(.api_state$oa_email)) 5L else 2L
    s2_threshold <- if (!is.null(.api_state$s2_api_key)) 5L else 2L
    hit_limit <- .api_state$oa_429_streak >= oa_threshold ||
      .api_state$s2_429_streak >= s2_threshold
    if (hit_limit) break

    meta <- fetch_openalex(doi, timeout)

    if (.api_state$oa_429_streak >= oa_threshold) break

    if (is.null(meta)) {
      meta <- fetch_s2(doi, timeout)
      if (is.null(meta)) next
    } else if (is.null(meta$abstract) || !nzchar(meta$abstract)) {
      abstract <- fetch_s2_abstract(doi, timeout)
      if (!is.null(abstract) && nzchar(abstract)) {
        meta$abstract <- abstract
      }
    }

    results <- c(results, list(meta))
  }

  results
}

#' Fetch Reference Metadata from OpenAlex and Semantic Scholar
#'
#' Takes a [ScanResult] or [PackageScanResult] and resolves reference
#' strings into structured bibliographic metadata. OpenAlex is the primary
#' source; Semantic Scholar supplements missing abstracts or serves as
#' fallback when OpenAlex returns 404.
#'
#' For [PackageScanResult], DOIs are collected from all scanned functions
#' and deduplicated before fetching — the same paper referenced by
#' multiple functions is fetched only once.
#'
#' API access profiles are configured via environment variables:
#' - `BRIDLE_OPENALEX_EMAIL`: enables identified (polite) pool
#' - `BRIDLE_S2_API_KEY`: enables authenticated access
#'
#' @param scan_result A [ScanResult] or [PackageScanResult] object.
#' @param timeout Request timeout in seconds (numeric).
#' @return A list of reference metadata lists, each containing `doi`,
#'   `title`, `authors`, `abstract`, `journal`, `year`.
#' @export
fetch_references <- function(scan_result, timeout = 10) {
  if (S7::S7_inherits(scan_result, PackageScanResult)) {
    dois <- collect_package_dois(scan_result)
    return(fetch_dois(dois, timeout))
  }
  if (!S7::S7_inherits(scan_result, ScanResult)) {
    cli::cli_abort(
      "{.arg scan_result} must be a {.cls ScanResult} or {.cls PackageScanResult}."
    )
  }

  refs <- scan_result@references
  if (length(refs) == 0L) {
    return(list())
  }

  dois <- extract_dois(refs)
  fetch_dois(dois, timeout)
}
