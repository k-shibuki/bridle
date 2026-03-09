---
trigger: reference API, OpenAlex, Semantic Scholar, fetch_references, rate limiting, profile fallback, abstract retrieval, academic API, BRIDLE_OPENALEX_EMAIL, BRIDLE_S2_API_KEY
---
# ADR-0010: Reference API — OpenAlex + Semantic Scholar

## Context

`fetch_references()` retrieves bibliographic metadata (title, authors, abstract, journal, year) for references cited in R package documentation. This metadata enriches the knowledge entries drafted by `draft_knowledge()`, providing the AI Drafter with domain context about *why* certain statistical methods exist and when they are appropriate.

The initial implementation used CrossRef (metadata by DOI) and PubMed (medical literature abstracts). Two problems emerged:

1. **CrossRef lacks abstracts**: CrossRef is a DOI registry; most records contain only metadata (title, authors, journal) without abstracts. Abstracts are critical because they summarize when and why a method should be used — exactly the domain knowledge `draft_knowledge()` needs.

2. **PubMed is medical-only**: Statistical methodology papers span multiple disciplines (psychology, ecology, education, economics). PubMed covers only medical/biomedical literature, missing a large portion of relevant references. For example, `metafor` cites papers from *Research Synthesis Methods*, *Psychological Methods*, and *Journal of Educational and Behavioral Statistics* — none indexed by PubMed.

Two alternative academic APIs were evaluated:

| API | Coverage | Abstract availability | Rate limits | Authentication |
|-----|----------|----------------------|-------------|----------------|
| **OpenAlex** | 250M+ works across all disciplines | Via `abstract_inverted_index` (requires reconstruction) | Polite pool: 10 req/s with `mailto`; anonymous: 3 req/s | Optional (`mailto` for polite pool) |
| **Semantic Scholar** | 200M+ papers, strong CS/medical coverage | Direct abstract text | Authenticated: ~100 req/s; anonymous: ~0.33 req/s | Optional (API key for higher limits) |

## Decision

Use **OpenAlex as primary** and **Semantic Scholar as secondary** reference API, with profile-based rate limiting and environment variable fallback.

### API selection rationale

- **OpenAlex primary**: Broadest disciplinary coverage, generous rate limits with `mailto`, entirely free and open. Covers statistical methodology across all fields.
- **Semantic Scholar secondary**: Provides direct abstract text (no reconstruction needed) and serves as a fallback when OpenAlex's `abstract_inverted_index` is missing. API key authentication unlocks higher rate limits for bulk use.

### Data scope

Only metadata and abstracts are retrieved. Full-text retrieval is out of scope — abstracts provide sufficient context for `draft_knowledge()` to understand method rationale and applicability.

### Profile-based rate limiting

Following the pattern established in `k-shibuki/lyra`, each API has multiple access profiles with different rate limits:

**OpenAlex profiles**:

| Profile | Condition | Min interval | Notes |
|---------|-----------|-------------|-------|
| `identified` | `BRIDLE_OPENALEX_EMAIL` is set | 0.25s (4 req/s) | Polite pool; `mailto` query parameter |
| `anonymous` | No email configured | 0.33s (3 req/s) | Lower priority in OpenAlex queue |

**Semantic Scholar profiles**:

| Profile | Condition | Min interval | Notes |
|---------|-----------|-------------|-------|
| `authenticated` | `BRIDLE_S2_API_KEY` is set | 1.1s (~1 req/s) | `x-api-key` header |
| `anonymous` | No API key configured | 3.0s (~0.33 req/s) | Severely throttled |

Rate limiting is implemented with `Sys.sleep()` between requests, tracking the last request timestamp per API. This is sufficient for single-threaded R execution.

### Environment variable fallback

Profile selection is automatic based on environment variables:

```
BRIDLE_OPENALEX_EMAIL → identified profile (recommended)
BRIDLE_S2_API_KEY     → authenticated profile (optional)
```

When no environment variables are set, both APIs fall back to anonymous profiles. A one-time `cli::cli_warn()` informs the user that setting `BRIDLE_OPENALEX_EMAIL` improves rate limits.

### Fallback strategy

```
fetch_references(dois)
  |-> OpenAlex lookup (primary)
  |     |-> abstract_inverted_index → text reconstruction
  |     |-> If abstract is empty → Semantic Scholar lookup (secondary)
  |-> Return merged metadata
```

OpenAlex is always tried first. Semantic Scholar is used only when OpenAlex does not provide an abstract for a given DOI. This minimizes API calls to Semantic Scholar (which has stricter anonymous rate limits).

### Error handling

| Error | Response |
|-------|----------|
| HTTP 429 (Too Many Requests) | `httr2::req_retry()` with exponential backoff; increase `min_interval` by 1.5× for subsequent requests |
| HTTP 401/403 (Authentication failure) | Downgrade to anonymous profile for the remainder of the session; `cli::cli_warn()` once |
| HTTP 404 (DOI not found) | Skip the reference; record as `NA` in results |
| Network timeout | Retry up to 3 times with `httr2::req_retry()` |

### Abstract reconstruction (OpenAlex)

OpenAlex stores abstracts as an `abstract_inverted_index`: a mapping from words to their positions in the text. Reconstruction:

```r
reconstruct_abstract <- function(inverted_index) {
  positions <- unlist(inverted_index, use.names = TRUE)
  words <- rep(names(inverted_index), lengths(inverted_index))
  paste(words[order(positions)], collapse = " ")
}
```

## Consequences

- **Easier**: Broad disciplinary coverage means references from any field (not just medicine) can be enriched with abstracts
- **Easier**: Profile-based rate limiting adapts automatically to the user's credentials — no manual configuration needed
- **Easier**: The fallback chain (OA → S2) maximizes abstract retrieval without requiring both APIs to be configured
- **Harder**: Two external API dependencies instead of two different ones — still requires HTTP mocking in tests
- **Harder**: OpenAlex's `abstract_inverted_index` format adds reconstruction complexity (though the algorithm is straightforward)
- **Harder**: Rate limit changes by either API may require updating profile intervals
