/** Providers reachable with an API key. ChatGPT sign-in stays in accounts.ts.
 * Responses-native providers run on Codex; the rest use their documented
 * Anthropic-compatible endpoint through the Claude Agent SDK. */
export type ProviderEngine = "codex" | "claude";

export interface ProviderModel {
  id: string;
  name: string;
  recommended?: boolean;
  /** Reasoning effort sent with each turn; null leaves the provider default. */
  effort?: string | null;
  contextWindow: number;
  /** False for text-only models: attached images are referenced by path only. */
  images: boolean;
}

export interface ProviderInfo {
  id: string;
  name: string;
  engine: ProviderEngine;
  /** Codex: OpenAI Responses base (`…/v1`). Claude: Anthropic base (`ANTHROPIC_BASE_URL`). */
  baseUrl: string;
  /** `x-api-key` only for Anthropic itself; compatible endpoints take a bearer token. */
  auth: "bearer" | "x-api-key";
  keysUrl: string;
  /** How a pasted key is checked before it is saved. */
  check: "models" | "messages";
  /** Codex's native web search tool is sent only where the provider accepts it. */
  webSearch: boolean;
  /** Empty for `openai`: its catalog is Codex's own `model/list`. */
  models: ProviderModel[];
}

const providers: ProviderInfo[] = [
  { id: "openai", name: "OpenAI API", engine: "codex", baseUrl: "https://api.openai.com/v1", auth: "bearer",
    keysUrl: "https://platform.openai.com/api-keys", check: "models", webSearch: true, models: [] },
  { id: "anthropic", name: "Anthropic", engine: "claude", baseUrl: "https://api.anthropic.com", auth: "x-api-key",
    keysUrl: "https://platform.claude.com/settings/keys", check: "messages", webSearch: true, models: [
      { id: "claude-fable-5-1", name: "Claude Fable 5.1", recommended: true, contextWindow: 1_000_000, images: true },
      { id: "claude-opus-5-5", name: "Claude Opus 5.5", contextWindow: 1_000_000, images: true },
      { id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", contextWindow: 1_000_000, images: true },
      { id: "claude-haiku-5-5", name: "Claude Haiku 5.5", contextWindow: 1_000_000, images: true },
    ] },
  { id: "xai", name: "xAI", engine: "codex", baseUrl: "https://api.x.ai/v1", auth: "bearer",
    keysUrl: "https://console.x.ai", check: "models", webSearch: false, models: [
      { id: "grok-4.7", name: "Grok 4.7", recommended: true, effort: "medium", contextWindow: 500_000, images: true },
      { id: "grok-4.5", name: "Grok 4.5", effort: "medium", contextWindow: 500_000, images: true },
    ] },
  { id: "kimi", name: "Kimi", engine: "claude", baseUrl: "https://api.moonshot.ai/anthropic", auth: "bearer",
    keysUrl: "https://platform.moonshot.ai/console/api-keys", check: "messages", webSearch: false, models: [
      { id: "kimi-k3", name: "Kimi K3", recommended: true, contextWindow: 1_048_576, images: true },
      { id: "kimi-k2.7-code", name: "Kimi K2.7 Code", contextWindow: 262_144, images: true },
    ] },
  { id: "zai", name: "GLM", engine: "claude", baseUrl: "https://api.z.ai/api/anthropic", auth: "bearer",
    keysUrl: "https://z.ai/manage-apikey/apikey-list", check: "messages", webSearch: false, models: [
      { id: "glm-5.3", name: "GLM-5.3", recommended: true, contextWindow: 1_048_576, images: false },
      { id: "glm-5.3-flash", name: "GLM-5.3 Flash", contextWindow: 1_048_576, images: true },
    ] },
  { id: "deepseek", name: "DeepSeek", engine: "claude", baseUrl: "https://api.deepseek.com/anthropic", auth: "bearer",
    keysUrl: "https://platform.deepseek.com/api_keys", check: "messages", webSearch: false, models: [
      { id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", recommended: true, contextWindow: 1_048_576, images: false },
      { id: "deepseek-flash", name: "DeepSeek V4.1 Flash", contextWindow: 1_048_576, images: true },
    ] },
  { id: "openrouter", name: "OpenRouter", engine: "claude", baseUrl: "https://openrouter.ai/api", auth: "bearer",
    keysUrl: "https://openrouter.ai/settings/keys", check: "messages", webSearch: false, models: [
      { id: "anthropic/claude-opus-5.5", name: "Claude Opus 5.5", recommended: true, contextWindow: 1_000_000, images: true },
      { id: "openai/gpt-6.1-sol", name: "GPT-6.1 Sol", contextWindow: 1_050_000, images: true },
      { id: "google/gemini-4-argon", name: "Gemini 4 Argon", contextWindow: 1_048_576, images: true },
      { id: "x-ai/grok-4.7", name: "Grok 4.7", contextWindow: 500_000, images: true },
      { id: "moonshotai/kimi-k3", name: "Kimi K3", contextWindow: 1_048_576, images: true },
      { id: "z-ai/glm-5.3", name: "GLM-5.3", contextWindow: 1_048_576, images: false },
      { id: "deepseek/deepseek-v4-pro", name: "DeepSeek V4 Pro", contextWindow: 1_048_576, images: false },
    ] },
];

/** `OPENSTRUDEL_PROVIDER_<ID>_BASE_URL` points a provider at a regional endpoint, proxy or test server. */
export function providerInfo(id: string): ProviderInfo | undefined {
  const info = providers.find(p => p.id === id);
  const override = info && process.env[`OPENSTRUDEL_PROVIDER_${info.id.toUpperCase()}_BASE_URL`];
  return info && override ? { ...info, baseUrl: override.replace(/\/+$/, "") } : info;
}

export function providerInfos(): ProviderInfo[] {
  return providers.map(p => providerInfo(p.id)!);
}

/** A key route's authentication failure. Never an OpenAI sign-in problem. */
export class ProviderKeyError extends Error {
  constructor(readonly provider: ProviderInfo) { super(`${provider.name} не принял ключ. Замените его в настройках аккаунтов.`); }
}
