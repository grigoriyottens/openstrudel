import { createServer, type Server } from "node:http";
import { afterEach, expect, it, vi } from "vitest";
import { Store } from "../src/store.js";
import { connectProvider, disconnectProvider, providerFailure, providerInfo, providerModels, providerSummaries, ProviderKeyError } from "../src/providers.js";
import { normalizeModels, readModelSelection, saveModelSelection } from "../src/model-settings.js";
import { isOpenAIAuthenticationError } from "../src/account-errors.js";

const stores: Store[] = [];
afterEach(() => { for (const store of stores.splice(0)) store.close(); vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
const memory = () => { const store = new Store(":memory:"); stores.push(store); return store; };
const reply = (status: number, body: unknown = {}) => vi.fn(async (_url: string, _init?: RequestInit) => new Response(JSON.stringify(body), { status }));

it("checks a pasted key with the provider and keeps only a masked hint visible", async () => {
  const store = memory();
  const models = reply(200, { data: [] }); vi.stubGlobal("fetch", models);
  expect(await connectProvider(store, "xai", "  xai-secret-7Qa\n")).toEqual({ id: "xai", name: "xAI", auth: "key", connected: true, keyHint: "••••7Qa", keysUrl: "https://console.x.ai", usedBy: 2 });
  const [url, init] = models.mock.calls[0]!;
  expect(url).toBe("https://api.x.ai/v1/models");
  expect(init!.headers).toEqual({ authorization: "Bearer xai-secret-7Qa" });
  expect(init!.signal).toBeInstanceOf(AbortSignal);
  expect(store.getSetting("providers.xai.key")).toBe("xai-secret-7Qa");
  expect(JSON.stringify(providerSummaries(store))).not.toContain("xai-secret");

  const messages = reply(200); vi.stubGlobal("fetch", messages);
  await connectProvider(store, "anthropic", "sk-ant-1");
  const [messagesURL, request] = messages.mock.calls[0]!;
  expect(messagesURL).toBe("https://api.anthropic.com/v1/messages");
  expect(request!.method).toBe("POST");
  expect(request!.headers).toMatchObject({ "x-api-key": "sk-ant-1", "anthropic-version": "2023-06-01" });
  expect(JSON.parse(String(request!.body))).toMatchObject({ model: "claude-fable-5-1", max_tokens: 1 });
  vi.stubEnv("OPENSTRUDEL_PROVIDER_KIMI_BASE_URL", "http://127.0.0.1:9/anthropic/");
  const compatible = reply(200); vi.stubGlobal("fetch", compatible);
  await connectProvider(store, "kimi", "kimi-key");
  expect(compatible.mock.calls[0]![0]).toBe("http://127.0.0.1:9/anthropic/v1/messages");
  expect(compatible.mock.calls[0]![1]!.headers).toMatchObject({ authorization: "Bearer kimi-key" });
  expect(providerSummaries(store).map(p => [p.id, p.connected])).toEqual([["chatgpt", false], ["openai", false], ["anthropic", true], ["xai", true], ["kimi", true], ["zai", false], ["deepseek", false], ["openrouter", false]]);
});

it("saves nothing when the key is rejected or cannot be checked", async () => {
  const store = memory();
  vi.stubGlobal("fetch", reply(401, { error: { message: "Incorrect API key" } }));
  await expect(connectProvider(store, "openai", "sk-bad")).rejects.toMatchObject({ status: 400, message: "OpenAI API не принял ключ. Проверьте его и вставьте снова." });
  vi.stubGlobal("fetch", reply(500, { error: { message: "Upstream\noverloaded" } }));
  await expect(connectProvider(store, "openai", "sk-1")).rejects.toMatchObject({ status: 502, message: "OpenAI API не подтвердил ключ: 500 Upstream overloaded" });
  vi.stubGlobal("fetch", reply(400, { type: "error", error: { type: "invalid_request_error", message: "Your credit balance is too low" } }));
  await expect(connectProvider(store, "anthropic", "sk-ant")).rejects.toMatchObject({ status: 400, message: "Anthropic не подтвердил ключ: 400 Your credit balance is too low" });
  vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("fetch failed"); }));
  await expect(connectProvider(store, "openai", "sk-1")).rejects.toMatchObject({ status: 502, message: "Не удалось связаться с OpenAI API. Проверьте подключение к интернету и попробуйте ещё раз." });
  await expect(connectProvider(store, "openai", " \n")).rejects.toMatchObject({ status: 400, message: "Вставьте ключ." });
  await expect(connectProvider(store, "chatgpt", "sk-1")).rejects.toMatchObject({ status: 404 });
  expect(providerSummaries(store).some(p => p.connected)).toBe(false);
});

it("removing a key returns its employees to the device default and its defaults to automatic", () => {
  const store = memory();
  store.setSetting("providers.xai.key", "xai-key");
  const grok = store.createProfile({ name: "Grok" }), chat = store.createProfile({ name: "Chat" }), inherits = store.createProfile({ name: "Inherits" });
  saveModelSelection(store, { provider: "xai", model: "grok-4.5", serviceTier: "default" }, grok.id);
  saveModelSelection(store, { provider: "chatgpt", model: "gpt-6-sol", serviceTier: "priority" }, chat.id);
  saveModelSelection(store, { provider: "xai", model: "grok-4.7", serviceTier: "default" });
  saveModelSelection(store, { provider: "xai", model: "grok-4.7", serviceTier: "default" }, "main");
  expect(providerSummaries(store).find(p => p.id === "xai")!.usedBy).toBe(4);
  expect(disconnectProvider(store, "xai")).toBe(3);
  expect(store.getSetting("providers.xai.key")).toBeNull();
  expect(readModelSelection(store, grok.id)).toEqual({ provider: null, model: null, serviceTier: null });
  expect(readModelSelection(store, chat.id)).toEqual({ provider: "chatgpt", model: "gpt-6-sol", serviceTier: "priority" });
  expect(readModelSelection(store, inherits.id)).toEqual({ provider: null, model: null, serviceTier: null });
  expect(readModelSelection(store)).toEqual({ provider: null, model: null, serviceTier: "default" });
  expect(readModelSelection(store, "main")).toEqual({ provider: null, model: null, serviceTier: null });
  expect(() => disconnectProvider(store, "chatgpt")).toThrow();
});

it("attributes key route failures to their provider, never to an OpenAI sign-in", () => {
  const xai = providerInfo("xai")!;
  const rejected = providerFailure(xai, new Error("unexpected status 401 Unauthorized: Incorrect API key, url: https://api.x.ai/v1/responses"));
  expect(rejected).toBeInstanceOf(ProviderKeyError);
  expect((rejected as Error).message).toBe("xAI не принял ключ. Замените его в настройках аккаунтов.");
  expect(isOpenAIAuthenticationError(rejected)).toBe(false);
  expect(providerFailure(xai, new Error("invalid_grant"))).toBeInstanceOf(ProviderKeyError);
  const limited = providerFailure(xai, new Error("unexpected status 429 Too Many Requests: You exceeded your current quota")) as Error;
  expect(limited.message).toBe("У ключа xAI закончился лимит или баланс. Проверьте оплату у провайдера или повторите позже.");
  expect(limited.message).not.toMatch(/usage limit|rate limit|quota/i);
  const other = new Error("model is overloaded");
  expect(providerFailure(xai, other)).toBe(other);
  expect((providerFailure(xai, new Error("unexpected status 429")) as Error).message).toBe(limited.message);
  expect((providerFailure(xai, new Error("unexpected status 402 Payment Required")) as Error).message).toBe(limited.message);
  const conflict = new Error("unexpected status 409 Conflict: conversation busy");
  expect(providerFailure(xai, conflict)).toBe(conflict);
});

it("a replaced or removed key ends its route's native threads; the same key keeps them", async () => {
  const store = memory(), conversation = store.primaryConversation(), other = store.getOrCreateConversation({ channel: "api", externalId: "other" });
  vi.stubGlobal("fetch", reply(200, { data: [] }));
  const threads = () => [store.getSetting("codex.thread.provider-xai." + conversation.id), store.getSetting("codex.threadCheckpoint.provider-xai." + conversation.id), store.getSetting("codex.threadOwner." + conversation.id), store.getConversation(conversation.id)!.codexThreadId,
    store.getSetting("codex.thread.default." + other.id), store.getConversation(other.id)!.codexThreadId];
  const use = () => {
    store.setSetting("codex.thread.provider-xai." + conversation.id, "xai-thread"); store.setSetting("codex.threadCheckpoint.provider-xai." + conversation.id, "m1"); store.setSetting("codex.threadOwner." + conversation.id, "provider-xai"); store.setConversationThread(conversation.id, "xai-thread");
    store.setSetting("codex.thread.default." + other.id, "chat-thread"); store.setSetting("codex.threadOwner." + other.id, "default"); store.setConversationThread(other.id, "chat-thread");
  };
  await connectProvider(store, "xai", "xai-org-a"); use();
  await connectProvider(store, "xai", "xai-org-a");
  expect(threads()).toEqual(["xai-thread", "m1", "provider-xai", "xai-thread", "chat-thread", "chat-thread"]);
  // Another organization's key cannot resume threads holding the first one's encrypted reasoning.
  await connectProvider(store, "xai", "xai-org-b");
  expect(threads()).toEqual([null, null, null, null, "chat-thread", "chat-thread"]);
  use(); disconnectProvider(store, "xai");
  expect(threads()).toEqual([null, null, null, null, "chat-thread", "chat-thread"]);
});

it("serves providers per device with owner-only writes, a provider-aware catalog and status", async () => {
  vi.stubEnv("OPENSTRUDEL_CODEX_MODE", "");
  const checks: string[] = [];
  const provider: Server = createServer((request, response) => {
    checks.push(String(request.headers.authorization));
    response.writeHead(request.headers.authorization === "Bearer xai-good" ? 200 : 401).end("{}");
  });
  await new Promise<void>(done => provider.listen(0, "127.0.0.1", done));
  vi.stubEnv("OPENSTRUDEL_PROVIDER_XAI_BASE_URL", `http://127.0.0.1:${(provider.address() as any).port}/v1`);
  const chatgpt = normalizeModels([{ model: "gpt-6-sol", displayName: "GPT-6 Sol", isDefault: true, serviceTiers: [{ id: "priority", name: "Fast" }] }], null);
  const { OpenStrudelRuntime } = await import("../src/runtime.js");
  let runtime!: InstanceType<typeof OpenStrudelRuntime>;
  runtime = new OpenStrudelRuntime({ dbPath: ":memory:", startTelegram: false, apiToken: "owner", engine: {
    models: async () => [...chatgpt, ...(runtime.store.getSetting("providers.xai.key") ? providerModels(providerInfo("xai")!) : [])],
    run: async () => ({ threadId: "t", response: "OK", events: [] }),
  } });
  const address = await runtime.api.listen("127.0.0.1", 0);
  const call = (path: string, method = "GET", body?: unknown, headers: Record<string, string> = { authorization: "Bearer owner" }) =>
    fetch(`http://127.0.0.1:${address.port}${path}`, { method, headers: { "content-type": "application/json", ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
  try {
    runtime.store.setSetting("codex.auth.mode", "managed");
    runtime.account.read = async () => ({ connected: true, email: "owner@example.invalid", planType: "plus", managed: true });
    const employee = runtime.store.createProfile({ name: "Researcher" });
    expect((await (await call("/health")).json()).providers).toBe(1);
    const initial = await (await call("/v1/providers")).json();
    expect(initial.canManage).toBe(true);
    expect(initial.providers[0]).toEqual({ id: "chatgpt", name: "ChatGPT", auth: "signin", connected: true, keyHint: null, keysUrl: null, usedBy: 3 });
    expect(initial.providers.map((p: any) => p.id)).toEqual(["chatgpt", "openai", "anthropic", "xai", "kimi", "zai", "deepseek", "openrouter"]);

    const session = await call("/auth/session", "POST", { key: runtime.api.web.invite(false).key });
    const member = { cookie: session.headers.get("set-cookie")!.split(";")[0]!, "x-openstrudel-csrf": (await session.json()).csrf };
    expect((await (await call("/v1/providers", "GET", undefined, member)).json()).canManage).toBe(false);
    expect((await call("/v1/providers/xai", "PUT", { key: "xai-good" }, member)).status).toBe(403);
    expect((await call("/v1/providers/xai", "DELETE", undefined, member)).status).toBe(403);
    expect(checks).toEqual([]);

    const rejected = await call("/v1/providers/xai", "PUT", { key: "xai-bad" });
    expect(rejected.status).toBe(400);
    expect((await rejected.json()).error).toBe("xAI не принял ключ. Проверьте его и вставьте снова.");
    const saved = await (await call("/v1/providers/xai", "PUT", { key: "xai-good" })).json();
    expect(saved.provider).toMatchObject({ id: "xai", connected: true, keyHint: "••••ood" });
    expect(checks).toEqual(["Bearer xai-bad", "Bearer xai-good"]);

    const settings = await (await call("/v1/settings/models")).json();
    expect(settings.providers.map((p: any) => p.id)).toEqual(["chatgpt", "xai"]);
    expect(settings.models.map((m: any) => [m.provider, m.id])).toEqual([["chatgpt", "gpt-6-sol"], ["xai", "grok-4.7"], ["xai", "grok-4.5"]]);
    expect(settings.recommended).toMatchObject({ provider: "chatgpt", id: "gpt-6-sol" });
    expect(settings.selection).toEqual({ provider: null, model: null, serviceTier: "default" });
    expect(settings.effective).toEqual({ provider: "chatgpt", model: "gpt-6-sol", serviceTier: "default" });
    const override = "/v1/settings/models?agentId=" + employee.id;
    expect((await call(override, "POST", { provider: "anthropic", model: "claude-fable-5-1", serviceTier: "default" })).status).toBe(409);
    expect((await call(override, "POST", { provider: "xai", model: "grok-9", serviceTier: "default" })).status).toBe(409);
    expect((await call(override, "POST", { provider: "xai", model: "grok-4.7", serviceTier: "priority" })).status).toBe(409);
    expect((await call(override, "POST", { provider: "xai", model: "grok-4.5", serviceTier: "default" }, member)).status).toBe(403);
    const chosen = await (await call(override, "POST", { provider: "xai", model: "grok-4.5", serviceTier: "default" })).json();
    expect(chosen.effective).toEqual({ provider: "xai", model: "grok-4.5", serviceTier: "default" });
    expect(runtime.store.getProfile(employee.id)).toMatchObject({ provider: "xai", model: "grok-4.5" });
    // An older app sends only a model: that is a ChatGPT model.
    expect((await (await call("/v1/settings/models?agentId=main", "POST", { model: "gpt-6-sol", serviceTier: "priority" })).json()).selection).toEqual({ provider: "chatgpt", model: "gpt-6-sol", serviceTier: "priority" });

    expect((await (await call("/v1/account?agentId=" + employee.id)).json())).toEqual({ account: { connected: true, email: null, planType: null, provider: "xai", providerName: "xAI" }, accountId: "provider-xai", loginPending: false, canManage: true });
    // Creating an employee with a model makes the same owner-only, connected, offered choice as the model settings.
    const create = (body: unknown, headers?: Record<string, string>) => call("/v1/profiles", "POST", body, headers);
    expect((await create({ name: "Writer", provider: "xai", model: "grok-4.7" }, member)).status).toBe(403);
    expect((await create({ name: "Writer", model: "gpt-6-sol" }, member)).status).toBe(403);
    expect((await create({ name: "Writer", provider: "bogus", model: "m" })).status).toBe(400);
    expect((await create({ name: "Writer", provider: "xai" })).status).toBe(400);
    expect((await create({ name: "Writer", provider: "anthropic", model: "claude-fable-5-1" })).status).toBe(409);
    expect((await create({ name: "Writer", provider: "xai", model: "grok-9" })).status).toBe(409);
    expect(runtime.store.listProfiles().map(p => p.name)).toEqual(["Researcher"]);
    expect((await (await create({ name: "Writer", provider: "xai", model: "grok-4.7" })).json()).profile).toMatchObject({ provider: "xai", model: "grok-4.7" });
    expect((await (await create({ name: "Chat", model: "gpt-6-sol" })).json()).profile).toMatchObject({ provider: "chatgpt", model: "gpt-6-sol" });

    expect(await (await call("/v1/providers/xai", "DELETE")).json()).toEqual({ ok: true, reset: 2 });
    expect(runtime.store.getProfile(employee.id)).toMatchObject({ provider: null, model: null });
    expect((await (await call("/v1/account?agentId=" + employee.id)).json()).accountId).not.toBe("provider-xai");
    expect((await call("/v1/providers/chatgpt", "PUT", { key: "x" })).status).toBe(404);
  } finally { await runtime.stop(); provider.close(); }
});

it("says on Services and skills that a Claude-engine provider uses only MCP services", async () => {
  const { OpenStrudelRuntime } = await import("../src/runtime.js");
  const runtime = new OpenStrudelRuntime({ dbPath: ":memory:", startTelegram: false, apiToken: "owner", engine: {
    run: async () => ({ threadId: "t", response: "OK", events: [] }),
    extensions: async () => ({ list: async () => ({ items: [{ id: "skill:1", name: "Notes", description: "", kind: "skill", enabled: true, removable: true }] }) }) as any,
  } });
  const address = await runtime.api.listen("127.0.0.1", 0);
  const list = async () => (await fetch(`http://127.0.0.1:${address.port}/v1/extensions?conversationId=${runtime.store.primaryConversation().id}`, { headers: { authorization: "Bearer owner" } })).json();
  try {
    runtime.store.setSetting("providers.kimi.key", "kimi-key");
    saveModelSelection(runtime.store, { provider: "kimi", model: "kimi-k3", serviceTier: "default" }, "main");
    expect(await list()).toEqual({ items: [expect.objectContaining({ name: "Notes" })], notice: "С Kimi сотрудник использует только сервисы MCP. Навыки и плагины работают с ChatGPT, OpenAI API и xAI." });
    saveModelSelection(runtime.store, { provider: "chatgpt", model: "gpt-6-sol", serviceTier: "default" }, "main");
    expect((await list()).notice).toBeUndefined();
  } finally { await runtime.stop(); }
});
