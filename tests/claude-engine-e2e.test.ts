import { afterEach, beforeEach, expect, it } from "vitest";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ClaudeEngine } from "../src/claude.js";
import { ProviderKeyError, providerInfo } from "../src/providers.js";
import { mockAnthropic, type MockRequest } from "./fixtures/mock-anthropic.js";

// The real Claude Code binary from the pinned SDK against a local Messages endpoint.
let root: string, mock: Awaited<ReturnType<typeof mockAnthropic>> | undefined, engines: ClaudeEngine[] = [];
beforeEach(() => { root = mkdtempSync(join(tmpdir(), "claude-e2e-")); });
// close() stops a CLI process that a failed test left running.
afterEach(async () => { for (const engine of engines) engine.close(); engines = []; await mock?.close(); mock = undefined; rmSync(root, { recursive: true, force: true }); });

const claude = (id: string, key: string) => { const engine = new ClaudeEngine({ root, provider: { ...providerInfo(id)!, baseUrl: mock!.url }, key: () => key }); engines.push(engine); return engine; };
// Claude Code may follow a tool result with its own system-role messages.
const toolResult = (request: MockRequest) => {
  const content = request.body?.messages?.findLast((m: any) => m.role === "user")?.content;
  return Array.isArray(content) ? content.find((b: any) => b.type === "tool_result") : undefined;
};
const endpoints = () => [...new Set(mock!.requests.map(r => `${r.method} ${r.path}`))];

it("answers, resumes the same session with a changed SOUL and sends a bearer token", async () => {
  let turn = 0;
  mock = await mockAnthropic(() => ({ text: `Ответ ${++turn}` }));
  const engine = claude("kimi", "sk-kimi-secret");
  const started: unknown[] = [];
  const first = await engine.run("Привет", { profile: "Имя: Ада", onEvent: event => started.push(event) });
  expect(first.response).toBe("Ответ 1");
  expect(first.threadId).toMatch(/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/);
  expect(started).toEqual([{ type: "thread.started", payload: { threadId: first.threadId } }]);
  const second = await engine.run("Как тебя зовут?", { threadId: first.threadId, profile: "Имя: Бета" });
  expect(second).toEqual({ threadId: first.threadId, response: "Ответ 2", events: [] });
  const last = mock.requests.at(-1)!;
  expect(JSON.stringify(last.body.messages)).toContain("Ответ 1");
  expect(JSON.stringify(last.body.system)).toContain("Имя: Бета");
  expect(JSON.stringify(last.body.system)).not.toContain("Имя: Ада");
  expect(endpoints()).toEqual(["POST /v1/messages?beta=true"]);
  for (const request of mock.requests) {
    expect(request.headers.authorization).toBe("Bearer sk-kimi-secret");
    expect(request.headers["x-api-key"]).toBeUndefined();
    expect(request.body.model).toBe("kimi-k3");
  }
  const config = join(root, ".data/providers/kimi/claude/personal");
  expect(readdirSync(config, { recursive: true }).map(String).filter(f => f.endsWith(".jsonl"))).toEqual([expect.stringContaining(first.threadId + ".jsonl")]);
}, 90_000);

it("calls an OpenStrudel tool with an Anthropic key and returns its result to the model", async () => {
  mock = await mockAnthropic(request => {
    const result = toolResult(request);
    return result ? { text: "Сохранено: " + JSON.stringify(result.content) } : { tool: { name: "mcp__openstrudel__save_schedule", input: { id: null, cron: "0 9 * * *" } } };
  });
  const engine = claude("anthropic", "sk-ant-secret");
  const calls: unknown[] = [];
  const result = await engine.run("Напоминай каждое утро", { tools: { definitions: [{ type: "function", name: "save_schedule", description: "Save a schedule",
    inputSchema: { type: "object", properties: { id: { type: ["string", "null"] }, cron: { type: "string" } }, required: ["id", "cron"], additionalProperties: false } }],
  call: async (name, args) => { calls.push([name, args]); return { saved: true, id: "sch-1" }; } } });
  expect(calls).toEqual([["save_schedule", { id: null, cron: "0 9 * * *" }]]);
  expect(result.response).toContain('{\\"saved\\":true,\\"id\\":\\"sch-1\\"}');
  expect(mock.requests[0]!.body.tools.map((t: any) => t.name)).toContain("mcp__openstrudel__save_schedule");
  expect(endpoints()).toEqual(["POST /v1/messages?beta=true"]);
  for (const request of mock.requests) {
    expect(request.headers["x-api-key"]).toBe("sk-ant-secret");
    expect(request.headers.authorization).toBeUndefined();
    expect(request.body.model).toBe("claude-fable-5-1");
  }
}, 90_000);

it("stops at once when the provider rejects the key instead of retrying for minutes", async () => {
  mock = await mockAnthropic(() => ({ status: 401, type: "authentication_error", message: "invalid key" }));
  const started = Date.now();
  await expect(claude("zai", "sk-revoked").run("Привет")).rejects.toBeInstanceOf(ProviderKeyError);
  expect(Date.now() - started).toBeLessThan(15_000);
}, 90_000);

it("keeps the key out of command environments and a private HOME", async () => {
  mock = await mockAnthropic(request => toolResult(request) ? { text: "Готово" } : { tool: { name: "Bash", input: { command: "env", description: "Show environment" } } });
  const engine = claude("deepseek", "sk-deepseek-secret");
  // Without a sandbox (Linux without bubblewrap) the command asks; with one it runs without asking.
  await engine.run("Покажи окружение", { onRequest: async () => ({ decision: "accept" }) });
  const output = JSON.stringify(toolResult(mock.requests.at(-1)!));
  expect(output).toContain(`HOME=${join(root, ".data/providers/deepseek/claude/personal/home")}`);
  expect(output).not.toContain("sk-deepseek-secret");
}, 90_000);
