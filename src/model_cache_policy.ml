type provider_policy = {
  provider : string;
  default_prompt_cache_ttl_s : int option;
  source_url : string;
  notes : string;
}

(* B728: provider-level prompt cache TTL defaults for cache-aware blocking and
   cost estimation. Keep this table provider-scoped; use [model_overrides] only
   when public provider docs say a model differs from its provider default.

   Source leads:
   - OpenAI: developers.openai.com/api/docs/guides/prompt-caching
   - Anthropic: platform.claude.com/docs/en/build-with-claude/prompt-caching
   - Gemini: ai.google.dev/gemini-api/docs/generate-content/caching
   - Groq: console.groq.com/docs/prompt-caching
   - DeepSeek: api-docs.deepseek.com/guides/kv_cache *)
let provider_policies =
  [
    {
      provider = "anthropic";
      default_prompt_cache_ttl_s = Some 300;
      source_url =
        "https://platform.claude.com/docs/en/build-with-claude/prompt-caching";
      notes = "Default ephemeral prompt cache lifetime is 5 minutes.";
    };
    {
      provider = "deepseek";
      default_prompt_cache_ttl_s = None;
      source_url = "https://api-docs.deepseek.com/guides/kv_cache";
      notes =
        "Documents automatic clearing after a few hours to a few days, not a \
         fixed TTL.";
    };
    {
      provider = "gemini";
      default_prompt_cache_ttl_s = None;
      source_url =
        "https://ai.google.dev/gemini-api/docs/generate-content/caching";
      notes =
        "Gemini implicit caching is enabled for newer models but does not \
         document a fixed TTL; explicit cached-content resources default to 1h \
         but are a separate API path.";
    };
    {
      provider = "groq";
      default_prompt_cache_ttl_s = None;
      source_url = "https://console.groq.com/docs/prompt-caching";
      notes =
        "Prompt caching is limited to documented supported models, so no \
         provider-wide default is encoded.";
    };
    {
      provider = "openai";
      default_prompt_cache_ttl_s = None;
      source_url =
        "https://developers.openai.com/api/docs/guides/prompt-caching";
      notes =
        "Prompt cache retention defaults depend on organization data-retention \
         policy for most models, so no single provider default is encoded.";
    };
    {
      provider = "openai-codex";
      default_prompt_cache_ttl_s = None;
      source_url =
        "https://developers.openai.com/api/docs/guides/prompt-caching";
      notes =
        "Codex models use OpenAI prompt caching; retention defaults are \
         policy-dependent unless a model-specific override is documented.";
    };
  ]

type model_override = {
  provider : string;
  model_id : string;
  prompt_cache_ttl_s : int option;
  source_url : string;
  notes : string;
}

let model_overrides =
  [
    {
      provider = "openai";
      model_id = "gpt-5.5";
      prompt_cache_ttl_s = Some 86400;
      source_url =
        "https://developers.openai.com/api/docs/guides/prompt-caching";
      notes =
        "OpenAI documents gpt-5.5 as supporting only 24h prompt cache \
         retention.";
    };
    {
      provider = "openai-codex";
      model_id = "gpt-5.5";
      prompt_cache_ttl_s = Some 86400;
      source_url =
        "https://developers.openai.com/api/docs/guides/prompt-caching";
      notes =
        "Codex catalog exposes the same gpt-5.5 model id via the Codex \
         provider.";
    };
    {
      provider = "groq";
      model_id = "openai/gpt-oss-20b";
      prompt_cache_ttl_s = Some 7200;
      source_url = "https://console.groq.com/docs/prompt-caching";
      notes =
        "Groq prompt caching docs list this model as supported and say cached \
         data expires after 2 hours without use.";
    };
    {
      provider = "groq";
      model_id = "openai/gpt-oss-120b";
      prompt_cache_ttl_s = Some 7200;
      source_url = "https://console.groq.com/docs/prompt-caching";
      notes =
        "Groq prompt caching docs list this model as supported and say cached \
         data expires after 2 hours without use.";
    };
  ]

let default_prompt_cache_ttl_s provider =
  match
    List.find_opt
      (fun (policy : provider_policy) -> policy.provider = provider)
      provider_policies
  with
  | Some policy -> policy.default_prompt_cache_ttl_s
  | None -> None

let effective_prompt_cache_ttl_s ~provider ~model_id =
  match
    List.find_opt
      (fun (override : model_override) ->
        override.provider = provider && override.model_id = model_id)
      model_overrides
  with
  | Some override -> override.prompt_cache_ttl_s
  | None -> default_prompt_cache_ttl_s provider
