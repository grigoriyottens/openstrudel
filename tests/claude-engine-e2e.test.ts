import { afterEach, beforeEach, expect, it, onTestFinished } from "vitest";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { homedir, tmpdir } from "node:os";
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
const results = (request: MockRequest): any[] => request.body?.messages?.flatMap((m: any) => Array.isArray(m.content) ? m.content.filter((b: any) => b.type === "tool_result") : []) ?? [];
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

it("keeps an approve-all turn out of the Home's private data", async () => {
  const data = join(root, ".data"), cwd = join(data, "workspace/personal");
  mkdirSync(join(data, "codex"), { recursive: true });
  writeFileSync(join(data, "openstrudel.sqlite"), "providers.anthropic.key=sk-ant-PLANTED\n");
  writeFileSync(join(data, "codex/auth.json"), '{"access_token":"CHATGPT-PLANTED"}\n');
  // The owner's own files, like ~/.ssh, stay closed too.
  const owner = mkdtempSync(join(homedir(), ".openstrudel-sandbox-test-"));
  writeFileSync(join(owner, "id_ed25519"), "OWNER-PLANTED\n");
  onTestFinished(() => rmSync(owner, { recursive: true, force: true }));
  const steps = [
    { name: "Bash", input: { command: `cat ${join(owner, "id_ed25519")}`, description: "Read the owner's key" } },
    { name: "Bash", input: { command: "cat ../../openstrudel.sqlite", description: "Read the database" } },
    { name: "Bash", input: { command: `ln -s ${data} escape && echo inside > note.txt && cat note.txt`, description: "Link" } },
    { name: "Read", input: { file_path: join(cwd, "escape/codex/auth.json") } },
    { name: "Write", input: { file_path: join(cwd, "escape/pwned.txt"), content: "pwned" } },
  ];
  mock = await mockAnthropic(request => { const step = steps[results(request).length]; return step ? { tool: step } : { text: "Готово" }; });
  const asked: unknown[] = [];
  await claude("deepseek", "sk-deepseek-secret").run("Покажи", { approvalMode: "approve_all", onRequest: async (...request) => { asked.push(request); return { decision: "accept" }; } });
  const outputs = results(mock.requests.at(-1)!).map(r => JSON.stringify(r.content));
  expect(outputs).toHaveLength(5);
  expect(outputs[2]).toContain("inside");
  expect(outputs.join("\n")).not.toContain("PLANTED");
  expect(existsSync(join(data, "pwned.txt"))).toBe(false);
  expect(asked).toEqual([]);
}, 90_000);

it("keeps MCP service tokens out of the CLI's process arguments", async () => {
  const seen: string[] = [];
  const service = createServer((req, res) => { seen.push(String(req.headers.authorization)); res.writeHead(500).end(); });
  await new Promise<void>(resolve => service.listen(0, "127.0.0.1", resolve));
  try {
    const url = `http://127.0.0.1:${(service.address() as AddressInfo).port}/mcp`;
    mkdirSync(join(root, ".data/extensions/personal"), { recursive: true });
    writeFileSync(join(root, ".data/extensions/personal/config.toml"), `[mcp_servers.svc]\nurl = "${url}"\n[mcp_servers.svc.http_headers]\nAuthorization = "Bearer MCP-SECRET-TOKEN"\n`);
    let cli: string[] = [];
    // While the CLI waits for the model, list what every process on this machine can read about it.
    mock = await mockAnthropic(() => {
      cli = execFileSync("ps", ["-ww", "-ax", "-o", "args="], { encoding: "utf8" }).split("\n").filter(line => line.includes("--mcp-config") && (line.includes(root) || line.includes(url)));
      return { text: "Готово" };
    });
    await claude("kimi", "sk-kimi-secret").run("Привет");
    expect(cli).toEqual([expect.stringContaining(`--mcp-config ${join(root, ".data/providers/kimi/claude/personal/mcp-")}`)]);
    expect(cli.join("\n")).not.toContain("MCP-SECRET-TOKEN");
    expect(seen).toContain("Bearer MCP-SECRET-TOKEN");
  } finally { service.closeAllConnections(); await new Promise(resolve => service.close(resolve)); }
}, 90_000);
