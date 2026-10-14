import type { Store } from "./store.js";
import { HomeError } from "./home.js";
import { chatgptSignedIn } from "./account.js";
import { isOpenAIAuthenticationError } from "./account-errors.js";
import { readModelSelection, resolveModelSelection, saveModelSelection, type ModelChoice } from "./model-settings.js";

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

export interface ProviderSummary { id: string; name: string; auth: "signin" | "key"; connected: boolean; keyHint: string | null; keysUrl: string | null; usedBy: number }

/** Keys live only in this Home's private settings. They are never returned, logged or exported. */
export const providerKey = (store: Store, id: string): string | null => store.getSetting(`providers.${id}.key`);
/** Codex reserves built-in ids such as `openai`; a thread-scoped provider must not collide with them. */
export const codexProviderId = (id: string) => "openstrudel-" + id;
export const providerNotConnected = (id: string) => new HomeError(`Подключите ${providerInfo(id)?.name ?? id} на этом устройстве или выберите другую модель.`, 409);

export function providerModels(info: ProviderInfo): ModelChoice[] {
  return info.models.map(m => ({ id: m.id, name: m.name, description: "", isDefault: m.recommended === true, ...(m.effort ? { defaultReasoningEffort: m.effort } : {}),
    speeds: [{ id: "default", name: "Обычная", description: "" }], provider: info.id }));
}

/** ChatGPT first, then every registry provider. `usedBy` counts the agents whose selection resolves to it. */
export function providerSummaries(store: Store): ProviderSummary[] {
  const used = [undefined, "main", ...store.listProfiles().map(p => p.id)].map(agent => resolveModelSelection(store, agent).provider);
  const usedBy = (id: string) => used.filter(provider => provider === id).length;
  return [{ id: "chatgpt", name: "ChatGPT", auth: "signin", connected: chatgptSignedIn(store), keyHint: null, keysUrl: null, usedBy: usedBy("chatgpt") },
    ...providerInfos().map(p => {
      const key = providerKey(store, p.id);
      return { id: p.id, name: p.name, auth: "key" as const, connected: Boolean(key), keyHint: key ? "••••" + key.slice(-3) : null, keysUrl: p.keysUrl, usedBy: usedBy(p.id) };
    })];
}

/** A key is saved only after the provider accepts it. */
export async function connectProvider(store: Store, id: string, value: unknown): Promise<ProviderSummary> {
  const info = providerInfo(id);
  if (!info) throw new HomeError("Провайдер не найден.", 404);
  const key = typeof value === "string" ? value.trim() : "";
  if (!key || key.length > 4096 || /\s/.test(key)) throw new HomeError("Вставьте ключ.");
  const auth: Record<string, string> = info.auth === "x-api-key" ? { "x-api-key": key } : { authorization: "Bearer " + key };
  let response: Response;
  try {
    response = await fetch(info.baseUrl + (info.check === "models" ? "/models" : "/v1/messages"), info.check === "models" ? { headers: auth, signal: AbortSignal.timeout(10_000) } : {
      method: "POST", headers: { ...auth, "anthropic-version": "2023-06-01", "content-type": "application/json" }, signal: AbortSignal.timeout(10_000),
      body: JSON.stringify({ model: info.models.find(m => m.recommended)!.id, max_tokens: 1, messages: [{ role: "user", content: "ping" }] }),
    });
  } catch { throw new HomeError(`Не удалось связаться с ${info.name}. Проверьте подключение к интернету и попробуйте ещё раз.`, 502); }
  if (response.status === 401 || response.status === 403) throw new HomeError(`${info.name} не принял ключ. Проверьте его и вставьте снова.`);
  if (!response.ok) {
    const body: any = await response.json().catch(() => null);
    const detail = String(body?.error?.message ?? body?.message ?? response.statusText).replace(/\s+/g, " ").slice(0, 200);
    throw new HomeError(`${info.name} не подтвердил ключ: ${response.status} ${detail}`.trim(), response.status >= 500 ? 502 : 400);
  }
  store.setSetting(`providers.${id}.key`, key);
  return providerSummaries(store).find(p => p.id === id)!;
}

/** Employees on the provider return to the device default; a device or main-chat default returns to automatic. */
export function disconnectProvider(store: Store, id: string): number {
  if (!providerInfo(id)) throw new HomeError("Провайдер не найден.", 404);
  let reset = Number(store.db.prepare("UPDATE employee_profiles SET provider=NULL,model=NULL,service_tier=NULL WHERE provider=?").run(id).changes);
  for (const agent of [undefined, "main"]) if (readModelSelection(store, agent).provider === id) { saveModelSelection(store, { provider: null, model: null, serviceTier: agent ? null : "default" }, agent); reset++; }
  store.deleteSetting(`providers.${id}.key`);
  return reset;
}

/** A key route's failure names its provider. It never invalidates a ChatGPT account. */
export function providerFailure(info: ProviderInfo, error: unknown): unknown {
  if (error instanceof HomeError || error instanceof ProviderKeyError) return error;
  const message = error instanceof Error ? error.message : String(error);
  if (isOpenAIAuthenticationError(error) || /\b40[13]\b|forbidden|authentication|invalid.{0,20}(?:api.?key|token)/i.test(message)) return new ProviderKeyError(info);
  if (/\b40[29]\b|rate.?limit|quota|insufficient|billing|credit|balance|usage limit|too many requests/i.test(message)) return new HomeError(`У ключа ${info.name} закончился лимит или баланс. Проверьте оплату у провайдера или повторите позже.`, 429);
  return error;
}
