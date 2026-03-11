#' LLM Utilities
#'
#' Thin wrapper around ellmer for stateful LLM chat sessions.
#' Provider-agnostic: supports GitHub Models (default), Anthropic,
#' OpenAI, Google Gemini, and any ellmer-supported backend.
#'
#' @name llm_utils
NULL

# Provider dispatch table: maps provider name to ellmer constructor.
# GitHub Models uses chat_openai_compatible because ellmer 0.4.0's
# chat_github sends to /responses (Responses API) which GitHub Models
# does not support — it only serves /chat/completions.
.provider_constructors <- list(
  github = "chat_openai_compatible",
  openai = "chat_openai",
  anthropic = "chat_anthropic",
  gemini = "chat_gemini",
  ollama = "chat_ollama"
)

.github_models_base_url <- "https://models.github.ai/inference"

.github_models_default_model <- "gpt-4o-mini"

#' Resolve provider and build constructor args
#'
#' Shared logic for `bridle_chat` and `bridle_runtime_chat`. Resolves
#' provider name, selects the constructor, and injects GitHub Models
#' credentials when needed.
#' @param provider Provider name (character or NULL).
#' @param model Model name (character or NULL).
#' @param extra_args Named list of additional args to include.
#' @return A list with `constructor_fn` and `args` ready for `do.call`.
#' @keywords internal
resolve_chat_provider <- function(provider, model, extra_args = list()) {
  resolved <- provider %||%
    Sys.getenv("BRIDLE_LLM_PROVIDER", unset = "github")

  constructor_name <- .provider_constructors[[resolved]]
  if (is.null(constructor_name)) {
    cli::cli_abort(
      "Unknown LLM provider {.val {resolved}}. Supported: {.val {names(.provider_constructors)}}."
    )
  }

  chat_fn <- utils::getFromNamespace(constructor_name, "ellmer")
  args <- extra_args
  if (!is.null(model)) args$model <- model

  if (resolved == "github") {
    args$base_url <- .github_models_base_url
    pat <- Sys.getenv("GITHUB_PAT", unset = "")
    if (!nzchar(pat)) {
      cli::cli_abort("GITHUB_PAT environment variable is required for GitHub Models provider.")
    }
    args$credentials <- function() pat
    if (is.null(model)) args$model <- .github_models_default_model
  }

  list(constructor_fn = chat_fn, args = args)
}

#' Create a stateful runtime chat session
#'
#' Wraps `ellmer::Chat$new()` with provider dispatch. Returns a chat
#' object that maintains conversation history across calls.
#'
#' Provider resolution order:
#' 1. Explicit `provider` argument
#' 2. `BRIDLE_LLM_PROVIDER` environment variable
#' 3. Default: `"github"` (uses `GITHUB_PAT`)
#'
#' @param system_prompt System prompt for the chat session (character).
#' @param provider Provider name (character or NULL for auto-detect).
#' @param model Model name (character or NULL for provider default).
#' @return A chat object from ellmer.
#' @export
bridle_runtime_chat <- function(system_prompt = "",
                                provider = NULL,
                                model = NULL) {
  rlang::check_installed("ellmer", reason = "for LLM chat sessions")

  resolved <- resolve_chat_provider(
    provider, model,
    extra_args = list(system_prompt = system_prompt)
  )

  tryCatch(
    do.call(resolved$constructor_fn, resolved$args),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to create chat session.",
          "i" = "Check credentials in {.file .Renviron}.",
          "x" = conditionMessage(e)
        ),
        parent = e
      )
    }
  )
}
