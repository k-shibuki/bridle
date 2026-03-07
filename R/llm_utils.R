#' LLM Utilities
#'
#' Thin wrapper around ellmer for stateful LLM chat sessions.
#' Provider-agnostic: supports GitHub Models (default), Anthropic,
#' OpenAI, Google Gemini, and any ellmer-supported backend.
#'
#' @name llm_utils
NULL

# Provider dispatch table: maps provider name to ellmer constructor
.provider_constructors <- list(
  github = "chat_github",
  openai = "chat_openai",
  anthropic = "chat_anthropic",
  gemini = "chat_gemini",
  ollama = "chat_ollama"
)

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

  resolved_provider <- provider %||%
    Sys.getenv("BRIDLE_LLM_PROVIDER", unset = "github")

  constructor_name <- .provider_constructors[[resolved_provider]]
  if (is.null(constructor_name)) {
    cli::cli_abort(
      "Unknown LLM provider {.val {resolved_provider}}. Supported: {.val {names(.provider_constructors)}}."
    )
  }

  chat_fn <- utils::getFromNamespace(constructor_name, "ellmer")

  args <- list(system_prompt = system_prompt)
  if (!is.null(model)) args$model <- model

  tryCatch(
    do.call(chat_fn, args),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to create {resolved_provider} chat session.",
          "i" = "Check credentials in {.file .Renviron}.",
          "x" = conditionMessage(e)
        ),
        parent = e
      )
    }
  )
}
