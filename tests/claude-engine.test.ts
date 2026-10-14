import { afterEach, beforeEach, expect, it } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { CanUseTool, Options, query as sdkQuery, SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import { ClaudeEngine } from "../src/claude.js";
import { ProviderKeyError, providerInfo } from "../src/providers.js";

type Call = { prompt: SDKUserMessage[]; options: Options; interrupted: Promise<void> };
let root: string;
beforeEach(() => { root = mkdtempSync(join(tmpdir(), "claude-engine-")); });
afterEach(() => { rmSync(root, { recursive: true, force: true }); });

const init = (session = "s-1") => ({ type: "system", subtype: "init", session_id: session });
const success = (result: string, session = "s-1") => ({ type: "result", subtype: "success", is_error: false, result, session_id: session });
/** A stand-in for `query` that records the turn and replays scripted SDK messages. */
function fake(script: (call: Call) => AsyncGenerator<any> | any[] = () => [init(), success("Привет")]) {
  const calls: Call[] = [];
  const query = (({ prompt, options }: { prompt: AsyncIterable<SDKUserMessage>; options: Options }) => {
    let interrupt!: () => void;
    const call: Call = { prompt: [], options, interrupted: new Promise<void>(resolve => { interrupt = resolve; }) };
    return Object.assign((async function* () {
      for await (const message of prompt) call.prompt.push(message);
      calls.push(call);
      yield* script(call);
    })(), { interrupt: async () => interrupt() });
  }) as unknown as typeof sdkQuery;
  return { query, calls };
}
const interrupted = { type: "result", subtype: "error_during_execution", is_error: true, errors: ["Request was aborted."], session_id: "s-1" };
const aborted = (call: Call) => new Promise(resolve => call.options.abortController!.signal.aborted ? resolve(null) : call.options.abortController!.signal.addEventListener("abort", resolve));
const engine = (id: string, query: typeof sdkQuery, key: string | null = "sk-test-key") => new ClaudeEngine({ root, provider: providerInfo(id)!, key: () => key, query });
const allow = (call: Call, name: string, input: Record<string, unknown>, extra: Partial<Parameters<CanUseTool>[2]> = {}) =>
  call.options.canUseTool!(name, input, { signal: new AbortController().signal, ...extra } as Parameters<CanUseTool>[2]);

it("isolates each turn and places the key by the provider's auth style", async () => {
  process.env.ANTHROPIC_API_KEY = "sk-host-leak";
  process.env.OPENSTRUDEL_SECRET_FIXTURE = "host-only";
  try {
    const kimi = fake(), anthropic = fake();
    await engine("kimi", kimi.query).forContext("work").run("Hi");
    await engine("anthropic", anthropic.query).run("Hi");
    const [bearer, apiKey] = [kimi.calls[0]!.options, anthropic.calls[0]!.options];
    expect(bearer.settingSources).toEqual([]);
    expect(bearer.strictMcpConfig).toBe(true);
    expect(bearer.permissionMode).toBe("default");
    expect(bearer.cwd).toBe(join(root, ".data/workspace/work"));
    expect(bearer.env).toMatchObject({ CLAUDE_CONFIG_DIR: join(root, ".data/providers/kimi/claude/work"), HOME: join(root, ".data/providers/kimi/claude/work/home"),
      ANTHROPIC_BASE_URL: "https://api.moonshot.ai/anthropic", ANTHROPIC_AUTH_TOKEN: "sk-test-key", ANTHROPIC_API_KEY: "",
      CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1",
      ANTHROPIC_DEFAULT_HAIKU_MODEL: "kimi-k3", ANTHROPIC_SMALL_FAST_MODEL: "kimi-k3", CLAUDE_CODE_SUBAGENT_MODEL: "kimi-k3" });
    expect(bearer.model).toBe("kimi-k3");
    expect(JSON.stringify(bearer.env)).not.toMatch(/sk-host-leak|host-only/);
    expect(apiKey.env).toMatchObject({ ANTHROPIC_API_KEY: "sk-test-key", ANTHROPIC_BASE_URL: "https://api.anthropic.com", CLAUDE_CONFIG_DIR: join(root, ".data/providers/anthropic/claude/personal") });
    expect(apiKey.env).not.toHaveProperty("ANTHROPIC_AUTH_TOKEN");
    expect(apiKey.env).not.toHaveProperty("ANTHROPIC_DEFAULT_HAIKU_MODEL");
    expect(apiKey.model).toBe("claude-fable-5-1");
    expect(() => engine("kimi", kimi.query).forContext("../personal")).toThrow("Область не найдена");
    await expect(engine("kimi", kimi.query, null).run("Hi")).rejects.toThrow("Подключите Kimi на этом устройстве");
  } finally { delete process.env.ANTHROPIC_API_KEY; delete process.env.OPENSTRUDEL_SECRET_FIXTURE; }
});

it("reports the session at once, resumes it and sends a changed SOUL every turn", async () => {
  const { query, calls } = fake(call => [init(call.options.resume ?? "s-new"), success("Ответ", call.options.resume ?? "s-new")]);
  const events: unknown[] = [];
  const first = await engine("zai", query).run("Привет", { profile: "Имя: Ада", model: "glm-5.3-flash", onEvent: event => events.push(event) });
  expect(first).toEqual({ threadId: "s-new", response: "Ответ", events: [] });
  expect(events).toEqual([{ type: "thread.started", payload: { threadId: "s-new" } }]);
  expect(calls[0]!.options.resume).toBeUndefined();
  expect(calls[0]!.options.model).toBe("glm-5.3-flash");
  expect(calls[0]!.prompt).toEqual([{ type: "user", message: { role: "user", content: [{ type: "text", text: "Привет" }] }, parent_tool_use_id: null }]);
  const second = await engine("zai", query).run("Ещё", { threadId: "s-new", profile: "Имя: Ада\nОтвечай стихами" });
  expect(second.threadId).toBe("s-new");
  expect(calls[1]!.options.resume).toBe("s-new");
  const prompt = calls[1]!.options.systemPrompt as { type: string; preset: string; append: string; snapshot: boolean };
  expect(prompt).toMatchObject({ type: "preset", preset: "claude_code", snapshot: false });
  expect(prompt.append).toContain("Current employee SOUL (authoritative):\nИмя: Ада\nОтвечай стихами");
  expect(prompt.append).toContain("AskUserQuestion");
  expect(prompt.append).not.toMatch(/Codex's|request_user_input/);
});

it("serves employee tools in-process and returns their JSON or error", async () => {
  const { query, calls } = fake();
  const seen: unknown[] = [];
  await engine("deepseek", query).run("Hi", { tools: { definitions: [
    { type: "function", name: "save_schedule", description: "Save", inputSchema: { type: "object", properties: { id: { type: ["string", "null"] }, cron: { type: "string" } }, required: ["id", "cron"], additionalProperties: false } },
    { type: "function", name: "list_employees", description: "List", inputSchema: { type: "object", properties: {}, required: [], additionalProperties: false } },
  ], call: async (name, args) => { seen.push([name, args]); if (name === "list_employees") throw new Error("Список недоступен"); return { saved: true }; } } });
  const server = calls[0]!.options.mcpServers!.openstrudel as any;
  const [a, b] = InMemoryTransport.createLinkedPair();
  await server.instance.connect(a);
  const client = new Client({ name: "test", version: "1" });
  await client.connect(b);
  const { tools } = await client.listTools();
  expect(tools.map(t => t.name)).toEqual(["save_schedule", "list_employees"]);
  expect(tools[0]!.inputSchema).toMatchObject({ properties: { id: { type: ["string", "null"] }, cron: { type: "string" } }, required: ["id", "cron"] });
  expect(await client.callTool({ name: "save_schedule", arguments: { id: null, cron: "0 9 * * *" } })).toMatchObject({ content: [{ type: "text", text: '{"saved":true}' }] });
  expect(await client.callTool({ name: "list_employees", arguments: {} })).toMatchObject({ isError: true, content: [{ type: "text", text: "Список недоступен" }] });
  expect(seen).toEqual([["save_schedule", { id: null, cron: "0 9 * * *" }], ["list_employees", {}]]);
  await client.close();
  expect(await allow(calls[0]!, "mcp__openstrudel__save_schedule", {}, { mcpServer: { name: "openstrudel", source: "sdk" } })).toMatchObject({ behavior: "allow" });
});

it("asks the owner through the same requests Codex makes", async () => {
  const { query, calls } = fake();
  const requests: Array<[string, Record<string, any>]> = [];
  let decision = "accept";
  await engine("kimi", query).run("Hi", { approvalMode: "ask", onRequest: async (method, params) => {
    requests.push([method, params]);
    if (method === "item/tool/requestUserInput") return { answers: { "0": { answers: ["B"] } } };
    if (method === "mcpServer/elicitation/request") return { action: "decline", content: null, _meta: null };
    return { decision };
  } });
  const call = calls[0]!, cwd = join(root, ".data/workspace/personal");
  expect(call.options.sandbox).toEqual({ enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: true, failIfUnavailable: false });
  expect(await allow(call, "Bash", { command: "rm -rf build", description: "Clean" })).toMatchObject({ behavior: "allow" });
  decision = "decline";
  expect(await allow(call, "Bash", { command: "curl x", description: "Fetch" })).toMatchObject({ behavior: "deny" });
  expect(await allow(call, "Write", { file_path: join(cwd, "notes/a.md"), content: "x" })).toMatchObject({ behavior: "allow" });
  expect(await allow(call, "Edit", { file_path: "/etc/hosts", old_string: "a", new_string: "b" })).toMatchObject({ behavior: "deny" });
  const question = { question: "Pick one?", header: "Pick", multiSelect: false, options: [{ label: "A", description: "a" }, { label: "B", description: "b" }] };
  expect(await allow(call, "AskUserQuestion", { questions: [question] })).toEqual({ behavior: "allow", updatedInput: { questions: [question], answers: { "Pick one?": "B" } } });
  expect(await allow(call, "mcp__notion__search", { query: "q" }, { mcpServer: { name: "notion", source: "dynamic" } })).toMatchObject({ behavior: "deny" });
  expect(await allow(call, "Skill", { skill: "x" })).toMatchObject({ behavior: "deny" });
  expect(await allow(call, "WebFetch", { url: "https://example.com" })).toMatchObject({ behavior: "allow" });
  expect(requests).toEqual([
    ["item/commandExecution/requestApproval", { command: "rm -rf build", cwd, reason: "Clean" }],
    ["item/commandExecution/requestApproval", { command: "curl x", cwd, reason: "Fetch" }],
    ["item/fileChange/requestApproval", { reason: "Edit /etc/hosts", grantRoot: "/etc" }],
    ["item/tool/requestUserInput", { questions: [{ id: "0", header: "Pick", question: "Pick one?", options: question.options }] }],
    ["mcpServer/elicitation/request", { mode: "form", serverName: "notion", message: 'Allow the notion MCP server to run tool "search"?',
      requestedSchema: { type: "object", properties: {} }, _meta: { codex_approval_kind: "mcp_tool_call", tool_params: { query: "q" } } }],
  ]);
});

it("keeps approve-all writes in the workspace and never runs commands for a group", async () => {
  const { query, calls } = fake();
  const asked: string[] = [];
  const onRequest = async (method: string) => { asked.push(method); return { decision: "accept" }; };
  await engine("kimi", query).run("Hi", { approvalMode: "approve_all", onRequest });
  await engine("kimi", query).forContext("group-" + "a".repeat(64)).run("Hi", { approvalMode: "approve_all", groupContext: true, onRequest });
  await engine("kimi", query).run("Hi", { approvalMode: "ask" });
  const [all, group, unattended] = calls as [Call, Call, Call];
  expect(all.options.sandbox).toEqual({ enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false, failIfUnavailable: true });
  expect(await allow(all, "Bash", { command: "make" })).toMatchObject({ behavior: "allow" });
  expect(await allow(all, "mcp__notion__search", {}, { mcpServer: { name: "notion", source: "dynamic" } })).toMatchObject({ behavior: "allow" });
  expect(await allow(all, "Write", { file_path: "report.md", content: "x" })).toMatchObject({ behavior: "allow" });
  expect(await allow(all, "Write", { file_path: "../../outside.md", content: "x" })).toMatchObject({ behavior: "deny" });
  expect(group.options.sandbox).toBeUndefined();
  expect(await allow(group, "Bash", { command: "ls" })).toMatchObject({ behavior: "deny" });
  expect(await allow(group, "Write", { file_path: "a.md", content: "x" })).toMatchObject({ behavior: "deny" });
  expect(await allow(unattended, "Bash", { command: "ls" })).toMatchObject({ behavior: "deny" });
  expect(await allow(unattended, "AskUserQuestion", { questions: [] })).toMatchObject({ behavior: "deny" });
  expect(asked).toEqual([]);
});

it("stops the turn gracefully, and kills it only when the engine closes", async () => {
  // An interrupt lets the CLI finish its transcript and exit before the next turn resumes the session.
  const { query, calls } = fake(async function* (call) { yield init(); await call.interrupted; yield interrupted; });
  const stop = new AbortController();
  const run = engine("kimi", query).run("Hi", { signal: stop.signal });
  setTimeout(() => stop.abort(), 10);
  await expect(run).rejects.toThrow("Ответ остановлен");
  expect(calls[0]!.options.abortController!.signal.aborted).toBe(false);
  const hung = fake(async function* (call) { yield init(); await aborted(call); throw new Error("Claude Code process aborted by user"); });
  const closing = engine("kimi", hung.query);
  const pending = closing.run("Hi");
  setTimeout(() => closing.close(), 10);
  await expect(pending).rejects.toThrow("Ответ остановлен");
});

it("fails fast on a rejected key and keeps other provider errors short", async () => {
  const retrying = fake(async function* (call) {
    yield init();
    yield { type: "system", subtype: "api_retry", attempt: 1, max_retries: 10, retry_delay_ms: 500, error_status: 401, error: "authentication_failed", session_id: "s-1" };
    await call.interrupted;
    yield interrupted;
  });
  const error = await engine("kimi", retrying.query).run("Hi").catch(e => e);
  expect(error).toBeInstanceOf(ProviderKeyError);
  expect(error.provider.id).toBe("kimi");
  expect(retrying.calls[0]!.options.abortController!.signal.aborted).toBe(false);
  const final = fake(() => [init(), { type: "result", subtype: "success", is_error: true, api_error_status: 403, result: "API Error: 403 forbidden", session_id: "s-1" }]);
  await expect(engine("anthropic", final.query).run("Hi")).rejects.toBeInstanceOf(ProviderKeyError);
  const dump = fake(() => [init(), { type: "result", subtype: "success", is_error: true, api_error_status: 400, result: "API Error: 400 model glm-9 does not exist\n" + "x".repeat(600), session_id: "s-1" }]);
  await expect(engine("zai", dump.query).run("Hi")).rejects.toThrow(/^GLM не завершил ответ: 400 model glm-9 does not exist$/);
  const crash = fake(async function* () { yield init(); throw new Error("Claude Code process exited with code 1"); });
  await expect(engine("zai", crash.query).run("Hi")).rejects.toThrow("GLM не завершил ответ: Claude Code process exited with code 1");
});

it("sends images only to models that accept them", async () => {
  const png = join(root, "photo"), text = join(root, "note.png");
  writeFileSync(png, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from("pixels")]));
  writeFileSync(text, "not an image");
  const { query, calls } = fake();
  await engine("zai", query).run("Что на фото?", { model: "glm-5.3-flash", images: [png, text] });
  await engine("zai", query).run("Что на фото?", { model: "glm-5.3", images: [png] });
  expect(calls[0]!.prompt[0]!.message.content).toEqual([{ type: "text", text: "Что на фото?" },
    { type: "image", source: { type: "base64", media_type: "image/png", data: Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from("pixels")]).toString("base64") } }]);
  expect(calls[1]!.prompt[0]!.message.content).toEqual([{ type: "text", text: "Что на фото?" }]);
});

it("brings the context's MCP services and lists the registry models", async () => {
  mkdirSync(join(root, ".data/extensions/work"), { recursive: true });
  writeFileSync(join(root, ".data/extensions/work/config.toml"), `[mcp_servers.notion]\nenabled = true\nurl = "https://mcp.notion.com/mcp"\n[mcp_servers.notion.http_headers]\nAuthorization = "Bearer n"\n
[mcp_servers.files]\ncommand = "/usr/bin/files-mcp"\nargs = ["--root", "."]\n[mcp_servers.files.env]\nMODE = "read"\n
[mcp_servers.off]\nenabled = false\ncommand = "off"\n[mcp_servers.cua_repl]\nenabled = true\ncommand = "/Applications/Codex.app/cua"\n`);
  const { query, calls } = fake();
  await engine("openrouter", query).forContext("work").run("Hi", { tools: { definitions: [], call: async () => null } });
  const servers = calls[0]!.options.mcpServers!;
  expect(Object.keys(servers).sort()).toEqual(["files", "notion", "openstrudel"]);
  expect(servers.notion).toEqual({ type: "http", url: "https://mcp.notion.com/mcp", headers: { Authorization: "Bearer n" } });
  expect(servers.files).toEqual({ type: "stdio", command: "/usr/bin/files-mcp", args: ["--root", "."], env: { MODE: "read" } });
  expect(calls[0]!.options.disallowedTools).toContain("WebSearch");
  const models = await engine("openrouter", query).models();
  expect(models[0]).toMatchObject({ id: "anthropic/claude-opus-5.5", isDefault: true, provider: "openrouter", speeds: [{ id: "default", name: "Обычная", description: "" }] });
  expect(models.filter(m => m.isDefault)).toHaveLength(1);
});
