import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { AcpEngine, AcpSessionLost, ProviderSignInError, grokCommand } from "../src/acp.js";
import { providerInfo } from "../src/providers.js";

// Every turn starts a real Node process for the scripted agent.
vi.setConfig({ testTimeout: 30_000 });
let root: string;
beforeEach(() => { root = mkdtempSync(join(tmpdir(), "acp-engine-")); });
afterEach(() => { rmSync(root, { recursive: true, force: true }); });

const fixture = resolve("tests/fixtures/mock-grok.mjs");
const configOptions = [{ id: "model", name: "Model", category: "model", type: "select", currentValue: "grok-4.7",
  options: [{ value: "grok-4.7", name: "Grok 4.7" }, { value: "grok-4.6", name: "Grok 4.6", description: "Faster" }] }];

/** The engine against the scripted agent, which logs every launch and message. */
function mock(scenario: Record<string, unknown> = {}) {
  const dir = mkdtempSync(join(root, "mock-")), script = join(dir, "scenario.json"), log = join(dir, "log.jsonl");
  writeFileSync(script, JSON.stringify({ configOptions, ...scenario })); writeFileSync(log, "");
  const models: unknown[] = [];
  const engine = new AcpEngine({ root, provider: providerInfo("grok")!, onModels: list => models.push(list),
    command: () => ({ bin: process.execPath, args: [fixture], env: { MOCK_GROK_SCENARIO: script, MOCK_GROK_LOG: log } }) });
  const messages = () => readFileSync(log, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line));
  return { engine, models, messages, calls: (method: string) => messages().filter(m => m.method === method).map(m => m.params),
    chosen: () => messages().filter(m => m.answered === "session/request_permission").map(m => m.result.outcome.optionId ?? m.result.outcome.outcome) };
}

it("runs the pinned agent in the workspace with a private home, the employee tools and services, and no host secrets", async () => {
  process.env.XAI_API_KEY = "xai-host-leak"; process.env.OPENSTRUDEL_SECRET_FIXTURE = "host-only";
  try {
    expect(grokCommand()).toEqual({ bin: resolve("bin/grok"), args: ["--no-auto-update"] });
    mkdirSync(join(root, ".data/extensions/work"), { recursive: true });
    writeFileSync(join(root, ".data/extensions/work/config.toml"), `[mcp_servers.linear]\nurl = "https://mcp.linear.app/mcp"\nhttp_headers = { Authorization = "Bearer lin" }\n[mcp_servers.files]\ncommand = "files-mcp"\nargs = ["--ro"]\nenv = { ROOT = "/srv" }\n[mcp_servers.cua_repl]\ncommand = "cua"\n`);
    const g = mock({ turn: [{ text: "Сейчас посмотрю." }, { tool: { toolCallId: "t1", title: "Read notes", kind: "read" } }, { text: "Ответ: " }, { thought: "думаю" }, { text: "42" }] });
    const events: unknown[] = [], tools = { definitions: [], call: vi.fn() };
    const result = await g.engine.forContext("work").run("Привет", { profile: "Имя: Ада", model: "grok-4.6", onEvent: event => events.push(event), tools });
    // The reply is the agent's last stretch of text; commentary before its tool calls and its thoughts are dropped.
    expect(result).toEqual({ threadId: "s-new", response: "Ответ: 42", events: [] });
    expect(events).toEqual([{ type: "thread.started", payload: { threadId: "s-new" } }]);
    const workspace = realpathSync(join(root, ".data/workspace/work")), home = realpathSync(join(root, ".data/providers/grok/home"));
    const [{ start }] = g.messages();
    expect(start.args).toEqual(["agent", "stdio"]);
    expect(start.cwd).toBe(workspace);
    // Grok's own home is private, so it reads no ~/.grok, ~/.claude or ~/.codex of the owner.
    expect(start.env).toMatchObject({ HOME: home, GROK_HOME: home, GROK_DISABLE_AUTOUPDATER: "1" });
    expect(statSync(home).mode & 0o777).toBe(0o700);
    expect(start.env).not.toHaveProperty("XAI_API_KEY");
    expect(JSON.stringify(start.env)).not.toMatch(/xai-host-leak|host-only/);
    expect(g.calls("authenticate")).toEqual([{ methodId: "cached_token" }]);
    const [created] = g.calls("session/new");
    expect(created.cwd).toBe(workspace);
    expect(created._meta.rules).toContain("ask_user_question");
    expect(created._meta.rules).toMatch(/Current employee SOUL \(authoritative\):\nИмя: Ада$/);
    expect(created.mcpServers).toEqual([
      { type: "http", name: "openstrudel", url: expect.stringMatching(/^http:\/\/127\.0\.0\.1:\d+\/[0-9a-f]{32}$/), headers: [{ name: "Authorization", value: expect.stringMatching(/^Bearer [0-9a-f]{64}$/) }] },
      { type: "http", name: "linear", url: "https://mcp.linear.app/mcp", headers: [{ name: "Authorization", value: "Bearer lin" }] },
      { name: "files", command: "files-mcp", args: ["--ro"], env: [{ name: "ROOT", value: "/srv" }] },
    ]);
    expect(g.calls("session/set_config_option")).toEqual([{ sessionId: "s-new", configId: "model", value: "grok-4.6" }]);
    expect(g.calls("session/prompt")).toEqual([{ sessionId: "s-new", prompt: [{ type: "text", text: "Привет" }] }]);
    expect(g.models).toEqual([[{ id: "grok-4.7", name: "Grok 4.7", description: "", isDefault: true, speeds: [{ id: "default", name: "Обычная", description: "" }], provider: "grok" },
      { id: "grok-4.6", name: "Grok 4.6", description: "Faster", isDefault: false, speeds: [{ id: "default", name: "Обычная", description: "" }], provider: "grok" }]]);
    expect(() => g.engine.forContext("../personal")).toThrow("Область не найдена");
  } finally { delete process.env.XAI_API_KEY; delete process.env.OPENSTRUDEL_SECRET_FIXTURE; }
});

it("resumes the saved session, keeps only the new reply, and reports a session the agent lost", async () => {
  const g = mock({ turn: [{ text: "Продолжаем" }] });
  expect(await g.engine.run("Дальше", { threadId: "s-old", model: "grok-4.7", profile: "Имя: Ада" })).toEqual({ threadId: "s-old", response: "Продолжаем", events: [] });
  expect(g.calls("session/new")).toEqual([]);
  expect(g.calls("session/load")).toEqual([expect.objectContaining({ sessionId: "s-old", cwd: realpathSync(join(root, ".data/workspace/personal")), _meta: { rules: expect.stringContaining("Имя: Ада") } })]);
  expect(g.calls("session/set_config_option")).toEqual([]);
  const lost = mock({ load: { code: -32002, message: "Session not found" } });
  await expect(lost.engine.run("Дальше", { threadId: "s-gone" })).rejects.toBeInstanceOf(AcpSessionLost);
  expect(lost.calls("session/prompt")).toEqual([]);
});

it("forwards each permission request by kind and answers only once", async () => {
  const permission = (toolCallId: string, kind: string | undefined, title: string, rawInput: unknown = {}, locations: unknown[] = []) => ({ permission: { toolCall: { toolCallId, kind, title, rawInput, locations } } });
  const turn = [permission("c1", "execute", "Run tests", { command: "npm test" }), permission("e1", "edit", "Edit notes.md", {}, [{ path: "/w/notes.md" }]),
    permission("r1", "read", "Read notes.md"), permission("m1", undefined, "linear__save_issue", { title: "Bug" }), permission("o1", undefined, "openstrudel__save_schedule"),
    permission("x1", "switch_mode", "Leave plan mode")];
  const g = mock({ turn });
  const onRequest = vi.fn(async (method: string, params: Record<string, any>) =>
    method === "mcpServer/elicitation/request" ? { action: "accept" } : { decision: params.command === "npm test" ? "accept" : "decline" });
  await g.engine.run("Работай", { onRequest });
  const cwd = realpathSync(join(root, ".data/workspace/personal"));
  expect(onRequest.mock.calls).toEqual([
    ["item/commandExecution/requestApproval", { command: "npm test", cwd, reason: "Run tests" }],
    ["item/fileChange/requestApproval", { reason: "Edit notes.md /w/notes.md" }],
    ["mcpServer/elicitation/request", { mode: "form", serverName: "linear", message: 'Allow the linear MCP server to run tool "save_issue"?', requestedSchema: { type: "object", properties: {} },
      _meta: { codex_approval_kind: "mcp_tool_call", tool_params: { title: "Bug" } } }],
  ]);
  // Never "allow always": a later request asks again.
  expect(g.chosen()).toEqual(["once", "no", "once", "once", "once", "no"]);
  const all = mock({ turn });
  await all.engine.run("Работай", { approvalMode: "approve_all", onRequest });
  expect(onRequest).toHaveBeenCalledTimes(3);
  expect(all.chosen()).toEqual(["once", "once", "once", "once", "once", "once"]);
  // A schedule has nobody to ask.
  const scheduled = mock({ turn: [permission("c1", "execute", "Run tests", { command: "npm test" })] });
  await scheduled.engine.run("Выпуск", { onRequest: () => { throw new Error("Выпуск остановлен: нужно разрешение пользователя. Продолжите в чате."); } });
  expect(scheduled.chosen()).toEqual(["no"]);
});

it("asks Grok's questions in OpenStrudel and serves the employee tools", async () => {
  const g = mock({ turn: [
    { ask: { toolCallId: "q1", questions: [{ question: "Какой формат?", header: "Формат", options: [{ label: "Кратко", description: "" }, { label: "Подробно", description: "" }], multiSelect: false }] } },
    { mcp: { name: "save_note", arguments: { text: "купить молоко" } } }] });
  const onRequest = vi.fn(async () => ({ answers: { "0": { answers: ["Кратко"] } } }));
  const call = vi.fn(async (_name: string, args: Record<string, unknown>) => ({ saved: args.text }));
  const tools = { definitions: [{ type: "function" as const, name: "save_note", description: "Save a note", inputSchema: { type: "object", properties: { text: { type: "string" } } } }], call };
  const result = await g.engine.run("Запиши", { onRequest, tools });
  expect(onRequest).toHaveBeenCalledWith("item/tool/requestUserInput", { questions: [{ id: "0", header: "Формат", question: "Какой формат?", options: [{ label: "Кратко", description: "" }, { label: "Подробно", description: "" }] }] });
  expect(g.messages().find(m => m.answered === "x.ai/ask_user_question").result).toEqual({ outcome: "accepted", answers: { "Какой формат?": "Кратко" } });
  expect(call).toHaveBeenCalledWith("save_note", { text: "купить молоко" });
  expect(JSON.parse(result.response)).toEqual({ content: [{ type: "text", text: JSON.stringify({ saved: "купить молоко" }) }] });
});

it("stops with session/cancel, kills an agent that ignores it after 5 s, and names failures", async () => {
  const waiting = mock({ turn: [{ text: "…" }, { waitCancel: true }] }), stop = new AbortController();
  const pending = waiting.engine.run("Долго", { signal: stop.signal });
  await vi.waitFor(() => expect(waiting.calls("session/prompt")).toHaveLength(1));
  stop.abort();
  await expect(pending).rejects.toThrow("Ответ остановлен");
  expect(waiting.calls("session/cancel")).toEqual([{ sessionId: "s-new" }]);
  // A pending approval answers "cancelled" at once.
  const asking = mock({ turn: [{ permission: { toolCall: { toolCallId: "c1", kind: "execute", title: "Run", rawInput: { command: "make" } } } }, { waitCancel: true }] }), quit = new AbortController();
  const approval = asking.engine.run("Собери", { signal: quit.signal, onRequest: () => new Promise(() => {}) });
  await vi.waitFor(() => expect(asking.calls("session/prompt")).toHaveLength(1));
  quit.abort();
  await expect(approval).rejects.toThrow("Ответ остановлен");
  expect(asking.chosen()).toEqual(["cancelled"]);
  const stuck = mock({ turn: [{ hang: true }] }), halt = new AbortController();
  const hanging = stuck.engine.run("Долго", { signal: halt.signal });
  await vi.waitFor(() => expect(stuck.calls("session/prompt")).toHaveLength(1));
  const started = Date.now(); halt.abort();
  await expect(hanging).rejects.toThrow("Ответ остановлен");
  expect(Date.now() - started).toBeGreaterThanOrEqual(4_900);
  const closing = mock({ turn: [{ hang: true }] });
  const closed = closing.engine.run("Долго");
  await vi.waitFor(() => expect(closing.calls("session/prompt")).toHaveLength(1));
  closing.engine.close();
  await expect(closed).rejects.toThrow("Ответ остановлен");

  const signedOut = await mock({ authenticate: { code: -32000, message: "Authentication required" } }).engine.run("Привет").catch(e => e);
  expect(signedOut).toBeInstanceOf(ProviderSignInError);
  expect(signedOut).toMatchObject({ status: 409, reason: "auth:grok", message: "Войдите в Grok снова в настройках аккаунтов." });
  // Grok answers -32000 also when its sign-in server cannot be reached (as the pinned CLI does offline); that is an outage, not a lost sign-in.
  const offline = await mock({ authenticate: { code: -32000, message: "error sending request for url (https://auth.x.ai/.well-known/openid-configuration)" } }).engine.run("Привет").catch(e => e);
  expect(offline).not.toBeInstanceOf(ProviderSignInError);
  expect(offline.message).toBe("Grok не завершил ответ: error sending request for url (https://auth.x.ai/.well-known/openid-configuration)");
  await expect(mock({ prompt: { code: -32603, message: "rate limit exceeded\nretry later" } }).engine.run("Привет")).rejects.toThrow(/^Grok не завершил ответ: rate limit exceeded$/);
  await expect(mock({ turn: [{ stderr: "panic: out of memory\n", exit: 3 }] }).engine.run("Привет")).rejects.toThrow(/^Grok не завершил ответ: panic: out of memory$/);
});

it("reads the agent's model catalog from a scratch session after sign-in", async () => {
  const g = mock();
  expect((await g.engine.models()).map(m => [m.id, m.isDefault])).toEqual([["grok-4.7", true], ["grok-4.6", false]]);
  expect(g.calls("session/new")).toEqual([expect.objectContaining({ mcpServers: [] })]);
  expect(g.calls("session/prompt")).toEqual([]);
});
