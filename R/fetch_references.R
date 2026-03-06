#' Fetch Reference Metadata
#'
#' Resolves DOIs and retrieves bibliographic metadata (title, authors,
#' abstract) via CrossRef API and PubMed Entrez API to enrich the
#' `ScanResult` reference list for the AI Drafter.
#'
#' @name fetch_references
#' @importFrom rlang %||%
NULL

#' Fetch Reference Metadata from CrossRef and PubMed
#'
#' Takes a [ScanResult] and resolves its reference strings into structured
#' bibliographic metadata. DOIs are resolved via CrossRef; PubMed is used
#' as a fallback for abstract retrieval.
#'
#' @param scan_result A [ScanResult] object.
#' @param mailto Email address for polite CrossRef API access (character).
#' @param timeout Request timeout in seconds (numeric).
#' @return A list of reference metadata lists, each containing `doi`,
#'   `title`, `authors`, `abstract`, `journal`, `year`.
#' @export
fetch_references <- function(scan_result, mailto = NULL, timeout = 10) {
  refs <- scan_result@references
  if (length(refs) == 0L) {
    return(list())
  }

  dois <- extract_dois(refs)
  if (length(dois) == 0L) {
    return(list())
  }

  results <- list()
  for (doi in dois) {
    meta <- tryCatch(
      fetch_crossref_metadata(doi, mailto, timeout),
      error = function(e) {
        cli::cli_warn(
          "Failed to fetch metadata for DOI {.val {doi}}: {conditionMessage(e)}"
        )
        NULL
      }
    )
    if (!is.null(meta)) {
      if (is.null(meta$abstract) || nchar(meta$abstract) == 0L) {
        abstract <- tryCatch(
          fetch_pubmed_abstract(meta$title, timeout),
          error = function(e) NULL
        )
        if (!is.null(abstract)) {
          meta$abstract <- abstract
        }
      }
      results <- c(results, list(meta))
    }
  }
  results
}

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

#' Fetch metadata from CrossRef API (mockable wrapper)
#' @keywords internal
fetch_crossref_metadata <- function(doi, mailto = NULL, timeout = 10) {
  resp <- crossref_get(doi, mailto, timeout)
  parse_crossref_response(resp)
}

#' Perform HTTP GET to CrossRef API
#' @keywords internal
crossref_get <- function(doi, mailto = NULL, timeout = 10) {
  url <- paste0("https://api.crossref.org/works/", doi)
  req <- httr2::request(url)
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(req, max_tries = 3, backoff = ~2)
  if (!is.null(mailto)) {
    req <- httr2::req_url_query(req, mailto = mailto)
  }
  req <- httr2::req_headers(req, `User-Agent` = "bridle R package")
  httr2::req_perform(req)
}

#' Parse CrossRef API response into structured metadata
#' @keywords internal
parse_crossref_response <- function(resp) {
  body <- httr2::resp_body_json(resp)
  work <- body[["message"]]
  if (is.null(work)) {
    return(NULL)
  }

  title_parts <- work[["title"]]
  title <- if (is.list(title_parts) && length(title_parts) > 0L) {
    title_parts[[1L]]
  } else if (is.character(title_parts)) {
    paste(title_parts, collapse = " ")
  } else {
    ""
  }

  authors <- extract_crossref_authors(work[["author"]])
  abstract <- work[["abstract"]] %||% ""
  abstract <- gsub("<[^>]+>", "", abstract)

  journal_parts <- work[["container-title"]]
  journal <- if (is.list(journal_parts) && length(journal_parts) > 0L) {
    journal_parts[[1L]]
  } else if (is.character(journal_parts)) {
    paste(journal_parts, collapse = " ")
  } else {
    ""
  }

  year <- extract_crossref_year(work)

  list(
    doi = work[["DOI"]] %||% "",
    title = title,
    authors = authors,
    abstract = abstract,
    journal = journal,
    year = year
  )
}

#' Extract author names from CrossRef author list
#' @keywords internal
extract_crossref_authors <- function(author_list) {
  if (is.null(author_list)) {
    return(character(0))
  }
  vapply(author_list, function(a) {
    given <- a[["given"]] %||% ""
    family <- a[["family"]] %||% ""
    trimws(paste(given, family))
  }, character(1))
}

#' Extract publication year from CrossRef work metadata
#' @keywords internal
extract_crossref_year <- function(work) {
  pub <- work[["published-print"]] %||%
    work[["published-online"]] %||%
    work[["created"]]
  if (!is.null(pub)) {
    parts <- pub[["date-parts"]]
    if (is.list(parts) && length(parts) > 0L) {
      first <- parts[[1L]]
      if (length(first) > 0L) {
        return(as.integer(first[[1L]]))
      }
    }
  }
  NA_integer_
}

#' Fetch abstract from PubMed Entrez API (mockable wrapper)
#' @keywords internal
fetch_pubmed_abstract <- function(title, timeout = 10) {
  pmid <- pubmed_search(title, timeout)
  if (is.null(pmid)) {
    return(NULL)
  }
  pubmed_fetch_abstract(pmid, timeout)
}

#' Search PubMed for a paper by title
#' @keywords internal
pubmed_search <- function(title, timeout = 10) {
  resp <- pubmed_search_get(title, timeout)
  body <- httr2::resp_body_json(resp)
  ids <- body[["esearchresult"]][["idlist"]]
  if (is.null(ids) || length(ids) == 0L) {
    return(NULL)
  }
  ids[[1L]]
}

#' Perform PubMed search HTTP request
#' @keywords internal
pubmed_search_get <- function(title, timeout = 10) {
  url <- "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
  req <- httr2::request(url)
  req <- httr2::req_url_query(req,
    db = "pubmed",
    term = paste0(title, "[Title]"),
    retmode = "json",
    retmax = 1L
  )
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(req, max_tries = 2, backoff = ~2)
  httr2::req_perform(req)
}

#' Fetch abstract text from PubMed by PMID
#' @keywords internal
pubmed_fetch_abstract <- function(pmid, timeout = 10) {
  resp <- pubmed_efetch_get(pmid, timeout)
  text <- httr2::resp_body_string(resp)
  extract_abstract_from_xml(text)
}

#' Perform PubMed efetch HTTP request
#' @keywords internal
pubmed_efetch_get <- function(pmid, timeout = 10) {
  url <- "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
  req <- httr2::request(url)
  req <- httr2::req_url_query(req,
    db = "pubmed",
    id = pmid,
    rettype = "xml"
  )
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(req, max_tries = 2, backoff = ~2)
  httr2::req_perform(req)
}

#' Extract abstract text from PubMed XML response
#' @keywords internal
extract_abstract_from_xml <- function(xml_text) {
  pattern <- "<AbstractText[^>]*>(.*?)</AbstractText>"
  m <- regmatches(xml_text, gregexpr(pattern, xml_text, perl = TRUE))[[1L]]
  if (length(m) == 0L) {
    return(NULL)
  }
  parts <- gsub("<[^>]+>", "", m)
  paste(parts, collapse = " ")
}
