---
trigger: reference API, OpenAlex, Semantic Scholar, fetch_references, rate limiting, profile fallback, abstract retrieval, academic API, BRIDLE_OPENALEX_EMAIL, BRIDLE_S2_API_KEY, DOI normalization, 429 threshold, auth downgrade, abstract_inverted_index
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

```text
BRIDLE_OPENALEX_EMAIL → identified profile (recommended)
BRIDLE_S2_API_KEY     → authenticated profile (optional)
```

When no environment variables are set, both APIs fall back to anonymous profiles. A one-time `cli::cli_warn()` informs the user that setting `BRIDLE_OPENALEX_EMAIL` improves rate limits.

### Fallback strategy

```text
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

## Addendum: Implementation Details

Concrete API specifications, state management design, and error-handling mechanics that refine the Decision section above.

### OpenAlex API specification

**DOI lookup endpoint**:

```text
GET https://api.openalex.org/works/https://doi.org/{doi}
```

The DOI is embedded directly in the path (URL-encoded by `httr2`). This is the single-work endpoint, not the search endpoint.

**Query parameters**:

| Parameter | Value | Condition |
|-----------|-------|-----------|
| `select` | `id,title,abstract_inverted_index,publication_year,authorships,doi,primary_location` | Always |
| `mailto` | Value of `BRIDLE_OPENALEX_EMAIL` | `identified` profile only |

**DOI normalization**: OpenAlex returns the `doi` field as `https://doi.org/10.xxx/yyy`. The parser must strip the `https://doi.org/` prefix to produce `10.xxx/yyy`, matching the input DOI format used by `extract_dois()`.

**Response field mapping**:

| Output field | OpenAlex path | Notes |
|-------------|--------------|-------|
| `doi` | `doi` | After prefix stripping |
| `title` | `title` | Plain string |
| `authors` | `authorships[].author.display_name` | Character vector |
| `abstract` | `abstract_inverted_index` | Via `reconstruct_abstract()`; `NULL` or `{}` → `NULL` |
| `journal` | `primary_location.source.display_name` | May be `NULL` if no source |
| `year` | `publication_year` | Integer |

### Semantic Scholar API specification

**DOI lookup endpoint**:

```text
GET https://api.semanticscholar.org/graph/v1/paper/DOI:{doi}
```

The `DOI:` prefix is required by the S2 API to distinguish DOI lookups from S2 paper ID lookups.

**Query parameters**:

| Parameter | Value | Condition |
|-----------|-------|-----------|
| `fields` | `paperId,title,abstract,year,authors,venue,externalIds` | Always |

**Request headers**:

| Header | Value | Condition |
|--------|-------|-----------|
| `x-api-key` | Value of `BRIDLE_S2_API_KEY` | `authenticated` profile only |

**Response field mapping**:

| Output field | S2 path | Notes |
|-------------|---------|-------|
| `doi` | `externalIds.DOI` | Already in `10.xxx/yyy` format |
| `title` | `title` | Plain string |
| `authors` | `authors[].name` | Character vector |
| `abstract` | `abstract` | Direct text or `NULL` |
| `journal` | `venue` | May be empty string |
| `year` | `year` | Integer or `NULL` |

### Rate limiting state management

State is held in a package-level `environment` (`.api_state`), initialized by `detect_profiles()` on the first `fetch_references()` call per session:

```text
.api_state fields:
  oa_last        numeric   Last OA request timestamp (0 = never)
  oa_interval    numeric   Current OA min interval (0.25 or 0.33)
  oa_email       string|NULL
  oa_429_streak  integer   Consecutive OA 429 count
  s2_last        numeric   Last S2 request timestamp
  s2_interval    numeric   Current S2 min interval (1.1 or 3.0)
  s2_api_key     string|NULL
  s2_429_streak  integer   Consecutive S2 429 count
  s2_downgraded  logical   TRUE after 401/403
  warned_no_env  logical   TRUE after one-time env var warning
```

`enforce_rate_limit(api)` reads `{api}_last` and `{api}_interval`, sleeps if needed, then updates `{api}_last`.

**Dynamic interval expansion**: On HTTP 429, `{api}_interval *= 1.5`. This widened interval persists for all subsequent requests in the session.

**Consecutive 429 threshold**: If `{api}_429_streak` reaches the threshold (anonymous: 2, authenticated/identified: 5), remaining DOIs are skipped with `cli::cli_warn()`. The streak resets to 0 on any non-429 response.

### Auth downgrade lifecycle

Scope: entire R session (stored in `.api_state$s2_downgraded`).

1. S2 request returns HTTP 401 or 403.
2. `.api_state$s2_downgraded <- TRUE`.
3. `.api_state$s2_interval <- 3.0` (anonymous interval).
4. `.api_state$s2_api_key <- NULL` (stop sending header).
5. `cli::cli_warn()` once: "Semantic Scholar API key rejected; falling back to anonymous access."
6. All subsequent S2 requests in this session use anonymous profile.

OpenAlex does not require authentication, so auth downgrade applies only to S2.

### Fallback: OA 404 path

The Decision section describes fallback for missing abstracts. An additional path exists when OpenAlex does not have the DOI at all (HTTP 404):

1. `fetch_openalex()` returns `NULL`.
2. `fetch_references()` promotes S2 to the full metadata source for that DOI.
3. `fetch_s2()` retrieves the complete S2 response (all fields, not just abstract).
4. If S2 also 404s, the DOI is skipped entirely.
