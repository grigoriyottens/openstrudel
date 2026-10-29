import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { parse } from "smol-toml";
import type { Accounts } from "../src/accounts.js";
import type { ScopedAuthorization } from "../src/authorization.js";
import { Store } from "../src/store.js";
import { saveConversationModelSelection, saveModelSelection } from "../src/model-settings.js";

const runtime = vi.hoisted(() => ({ options: [] as any[], run: vi.fn(), close: vi.fn() }));
vi.mock("../src/codex.js", async original => ({ ...await original<object>(), CodexEngineAdapter: class {
  constructor(options: unknown) { runtime.options.push(options); }
  run = runtime.run;
  close = runtime.close;
} }));
import { RestrictedExecutor } from "../src/restricted-executor.js";

const secret = "synthetic-restricted-connector-token";
const allowed = { name: "school_mentor_schedule", capability: "schedule.read" };
const definition = (name = allowed.name) => ({ name, description: "Current permitted lessons", inputSchema: { type: "object", properties: {}, additionalProperties: false } });
const authorization = (): ScopedAuthorization => ({ fingerprint: "a".repeat(64), actor: { userId: "123", chatId: "123", messageId: "123:4" },
  connector: { url: "https://school.invalid/api/mcp/company", headers: { Authorization: "Bearer " + secret } }, tools: [allowed] });
const stores: Store[] = [], executors: RestrictedExecutor[] = [];
const calls: Array<{ body: any; headers: Headers; init: RequestInit }> = [];
let respond: (body: any, headers: Headers) => Response | Promise<Response>;
const result = (id: number, value: unknown, headers: Record<string, string> = {}) => Response.json({ jsonrpc: "2.0", id, result: value }, { headers });

function fixture(auth = authorization()) {
  const store = new Store(":memory:"); stores.push(store);
  saveModelSelection(store, { provider: "chatgpt", model: "pinned-model", serviceTier: "default" });
  const service = { authTokens: vi.fn().mockResolvedValue({ accessToken: "synthetic-account-token", chatgptAccountId: "account" }) };
  const accounts = { store, active: new Map<string, number>(), choose: vi.fn().mockResolvedValue({ id: "default", service }) } as unknown as Accounts;
  const executor = new RestrictedExecutor(accounts); executors.push(executor);
  const options = { authorization: auth, conversationId: store.primaryConversation().id, messageId: "stored-message", assertCurrent: vi.fn() };
  return { store, service, accounts, executor, options };
}

beforeEach(() => {
  calls.length = 0; runtime.options.length = 0; runtime.run.mockReset(); runtime.close.mockReset();
  respond = body => {
    if (body.method === "initialize") return result(body.id, { protocolVersion: "2025-03-26", capabilities: { tools: {} } }, { "mcp-session-id": "synthetic-session" });
    if (body.method === "notifications/initialized") return new Response(null, { status: 202 });
    if (body.method === "tools/list") return result(body.id, { tools: [definition(), definition("company_finance"), definition("send_telegram_message")] });
    if (body.method === "tools/call") return result(body.id, { content: [{ type: "text", text: '{"ok":true,"lessons":[]}' }] });
    throw new Error("Unexpected method");
  };
  vi.stubGlobal("fetch", vi.fn(async (_url: unknown, init: RequestInit) => {
    const body = JSON.parse(init.body as string), headers = new Headers(init.headers);
    calls.push({ body, headers, init });
    return respond(body, headers);
  }));
  runtime.run.mockResolvedValue({ response: "Готово", threadId: "ephemeral", events: [] });
});
afterEach(() => { for (const executor of executors.splice(0)) executor.close(); for (const store of stores.splice(0)) store.close(); vi.unstubAllGlobals(); });

it("exposes only granted business tools and sends verified transport outside the model", async () => {
  const { executor, options, accounts } = fixture();
  runtime.run.mockImplementation(async (_text, turn) => {
    expect(turn.tools.definitions).toEqual([{ type: "function", ...definition() }]);
    expect(JSON.stringify(turn)).not.toContain(secret);
    expect(turn).toMatchObject({ model: "pinned-model", employees: [], approvalMode: "approve_all" });
    expect(turn.threadId).toBeUndefined(); expect(turn.profile).toBeUndefined();
    await expect(turn.tools.call("company_finance", {})).rejects.toThrow("недоступно");
    await expect(turn.tools.call("send_telegram_message", {})).rejects.toThrow("недоступно");
    await expect(turn.tools.call("exec_command", {})).rejects.toThrow("недоступно");
    await expect(turn.tools.call(allowed.name, {})).resolves.toMatchObject({ content: [{ type: "text" }] });
    expect(accounts.active.get("default")).toBe(1);
    return { response: "Расписание проверено" };
  });
  expect(await executor.run("Проверь занятия", options)).toEqual({ response: "Расписание проверено" });
  expect(accounts.choose).toHaveBeenCalledExactlyOnceWith("main", false);
  expect(calls.map(c => c.body.method)).toEqual(["initialize", "notifications/initialized", "tools/list", "tools/call"]);
  for (const { headers, init } of calls) {
    expect(Object.fromEntries(headers)).toMatchObject({ authorization: "Bearer " + secret, "x-hermes-platform": "telegram", "x-hermes-user-id": "123", "x-hermes-chat-id": "123", "x-hermes-message-id": "123:4", "x-hermes-session-id": "openstrudel:" + options.conversationId });
    expect(init.redirect).toBe("error");
  }
  expect(calls[2]!.headers.get("mcp-session-id")).toBe("synthetic-session");
  expect(calls[2]!.headers.get("mcp-protocol-version")).toBe("2025-03-26");
  expect(options.assertCurrent.mock.calls.length).toBeGreaterThan(8);
  expect(accounts.active.size).toBe(0);
  expect(runtime.close).toHaveBeenCalledOnce();
});

it("creates fresh empty isolated homes every turn and removes them even on failure", async () => {
  const { executor, options } = fixture();
  const roots: string[] = [];
  runtime.run.mockImplementation(async () => {
    const config = runtime.options.at(-1);
    roots.push(dirname(config.codexHome));
    expect(config.restricted).toBe(true);
    expect(config.provider).toBeUndefined(); expect(config.sharedExtensionsPath).toBeUndefined(); expect(config.telegramServers).toBeUndefined();
    expect(readdirSync(config.workingDirectory)).toEqual([]);
    const toml = parse(readFileSync(join(config.codexHome, "config.toml"), "utf8")) as any;
    expect(toml).toMatchObject({ default_permissions: "restricted", approval_policy: "never", web_search: "disabled", permissions: { restricted: { network: { enabled: false } } }, features: { shell_tool: false, unified_exec: false, apps: false, plugins: false, memories: false, code_mode_host: true } });
    expect(toml.permissions.restricted.filesystem).toEqual({ ":minimal": "read", [config.workingDirectory]: "read" });
    expect(JSON.stringify(toml)).not.toContain(secret);
    if (roots.length === 2) throw Error("internal secret " + secret);
    return { response: "OK" };
  });
  await executor.run("one", options);
  await expect(executor.run("two", options)).rejects.toThrow("сейчас недоступен");
  expect(new Set(roots).size).toBe(2);
  expect(roots.every(root => !existsSync(root))).toBe(true);
});

it("refuses a non-ChatGPT conversation selection without fallback or MCP traffic", async () => {
  const { executor, options, store, accounts } = fixture();
  saveConversationModelSelection(store, options.conversationId, { provider: "openai", model: "api-model", serviceTier: "default" });
  await expect(executor.run("test", options)).rejects.toThrow("недоступен");
  expect(accounts.choose).not.toHaveBeenCalled(); expect(calls).toEqual([]); expect(runtime.run).not.toHaveBeenCalled();
});

it("does not retry a partial turn or disclose auth failures", async () => {
  const { executor, options, accounts, service } = fixture();
  service.authTokens.mockRejectedValue(Error("Authorization: Bearer " + secret));
  runtime.run.mockImplementation(async () => { await runtime.options[0].authTokens(); });
  await expect(executor.run("test", options)).rejects.toThrow("сейчас недоступен");
  expect(accounts.choose).toHaveBeenCalledOnce(); expect(runtime.run).toHaveBeenCalledOnce();
  expect(accounts.active.size).toBe(0);
});

it("rejects revoked access before and after a remote mutation and after the turn", async () => {
  const { executor, options } = fixture();
  let active = true;
  options.assertCurrent.mockImplementation(() => { if (!active) throw Error("revoked"); });
  const standard = respond;
  respond = (body, headers) => { if (body.method === "tools/call") active = false; return standard(body, headers); };
  let retained: any;
  runtime.run.mockImplementation(async (_text, turn) => {
    retained = turn.tools.call;
    await expect(retained(allowed.name, {})).rejects.toThrow("Права доступа изменились");
    const before = calls.length;
    await expect(retained(allowed.name, {})).rejects.toThrow("Права доступа изменились");
    expect(calls).toHaveLength(before);
    return { response: "must not be delivered" };
  });
  await expect(executor.run("test", options)).rejects.toThrow("Права доступа изменились");
  active = true;
  await expect(retained(allowed.name, {})).rejects.toThrow("Права доступа изменились");
});

it("pins identity even when arguments try to claim another user or chat", async () => {
  const auth = authorization(); auth.connector.headers["X-Hermes-User-Id"] = "999";
  const { executor, options } = fixture(auth);
  runtime.run.mockImplementation(async (_text, turn) => {
    await turn.tools.call(allowed.name, { userId: "999", chatId: "-999", authorization: "other" });
    return { response: "OK" };
  });
  await executor.run("test", options);
  expect(calls.at(-1)!.headers.get("x-hermes-user-id")).toBe("123");
  expect(calls.at(-1)!.headers.get("x-hermes-chat-id")).toBe("123");
  expect(calls.at(-1)!.headers.get("authorization")).toBe("Bearer " + secret);
});

it.each(["http", "rpc", "echo", "fetch"])("sanitizes %s errors without returning credentials", async mode => {
  const { executor, options } = fixture();
  respond = body => {
    if (mode === "http") return new Response("Bearer " + secret, { status: 500 });
    if (mode === "rpc") return Response.json({ jsonrpc: "2.0", id: body.id, error: { message: secret } });
    if (mode === "echo") return result(body.id, { protocolVersion: "2025-03-26", secret });
    throw Error(secret);
  };
  await expect(executor.run("test", options)).rejects.toThrow("сейчас недоступен");
  expect(runtime.run).not.toHaveBeenCalled();
});

it("preserves safe business error codes and replaces upstream text", async () => {
  const { executor, options } = fixture();
  const standard = respond;
  respond = (body, headers) => body.method === "tools/call" ? result(body.id, { isError: true, content: [{ type: "text", text: JSON.stringify({ code: "report_revision_conflict", text: "private service internals" }) }] }) : standard(body, headers);
  runtime.run.mockImplementation(async (_text, turn) => {
    const failure = await turn.tools.call(allowed.name, {});
    expect(failure).toMatchObject({ ok: false, code: "report_revision_conflict" });
    expect(JSON.stringify(failure)).not.toContain("private service internals");
    return { response: "OK" };
  });
  await executor.run("test", options);
});

it("uses only service workflow and validated timezone, never the Home's SOUL", async () => {
  const { executor, options, store } = fixture();
  store.setSetting("owner.timezone", "Europe/Moscow");
  store.setSetting("agent.soul", "PRIVATE CORPORATE DETAILS");
  const standard = respond;
  respond = (body, headers) => body.method === "initialize" ? result(body.id, { protocolVersion: "2025-03-26", instructions: "Show preview and use its fingerprint." }) : standard(body, headers);
  await executor.run("test", options);
  expect(runtime.options[0].restrictedInstructions).toContain("Europe/Moscow");
  expect(runtime.options[0].restrictedInstructions).toContain("Show preview and use its fingerprint.");
  expect(JSON.stringify(runtime.options[0])).not.toContain("PRIVATE CORPORATE DETAILS");
});

it("paginates the filtered catalogue and accepts bounded SSE responses", async () => {
  const { executor, options } = fixture();
  const standard = respond;
  respond = (body, headers) => {
    if (body.method !== "tools/list") return standard(body, headers);
    if (!body.params.cursor) return result(body.id, { tools: [definition("company_finance")], nextCursor: "page-2" });
    expect(body.params.cursor).toBe("page-2");
    const data = JSON.stringify({ jsonrpc: "2.0", id: body.id, result: { tools: [definition()] } });
    return new Response("event: message\ndata: " + data + "\n\n", { headers: { "content-type": "text/event-stream" } });
  };
  await executor.run("test", options);
  expect(runtime.run.mock.calls[0]![1].tools.definitions.map((t: any) => t.name)).toEqual([allowed.name]);
  expect(calls.filter(c => c.body.method === "tools/list")).toHaveLength(2);
});

it.each(["too-many", "repeated-cursor", "duplicate", "oversized"])("fails closed on invalid discovery: %s", async mode => {
  const { executor, options } = fixture();
  const standard = respond;
  respond = (body, headers) => {
    if (body.method !== "tools/list") return standard(body, headers);
    if (mode === "too-many") return result(body.id, { tools: Array.from({ length: 101 }, (_, i) => definition("tool" + i)) });
    if (mode === "repeated-cursor") return result(body.id, { tools: [], nextCursor: "loop" });
    if (mode === "duplicate") return result(body.id, { tools: [definition(), definition()] });
    return result(body.id, { tools: [definition()], padding: "x".repeat(1024 * 1024) });
  };
  await expect(executor.run("test", options)).rejects.toThrow("недоступен");
  expect(runtime.run).not.toHaveBeenCalled();
});

it("rechecks authorization after account choice and never starts an already cancelled turn", async () => {
  const { executor, options, accounts } = fixture();
  vi.mocked(accounts.choose).mockImplementation(async () => { options.assertCurrent.mockImplementation(() => { throw Error("revoked"); }); return { id: "default", service: {} as any }; });
  await expect(executor.run("test", options)).rejects.toThrow("Права доступа изменились");
  expect(calls).toEqual([]); expect(runtime.run).not.toHaveBeenCalled();
  const controller = new AbortController(); controller.abort();
  await expect(executor.run("test", { ...options, signal: controller.signal })).rejects.toThrow("Права доступа изменились");
  expect(accounts.choose).toHaveBeenCalledOnce();
});

it("close revokes outstanding tool handles and prevents subsequent runs", async () => {
  const { executor, options } = fixture();
  runtime.run.mockImplementation(async (_text, turn) => {
    executor.close();
    expect(turn.signal.aborted).toBe(true);
    await expect(turn.tools.call(allowed.name, {})).rejects.toThrow("Права доступа изменились");
    return { response: "late" };
  });
  await expect(executor.run("test", options)).rejects.toThrow("Права доступа изменились");
  await expect(executor.run("again", options)).rejects.toThrow("Права доступа изменились");
});
