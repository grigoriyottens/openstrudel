import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { stringify } from "smol-toml";
import type { Accounts } from "./accounts.js";
import type { ScopedAuthorization } from "./authorization.js";
import { CodexEngineAdapter, restrictedCodexConfig } from "./codex.js";
import { resolveModelSelection } from "./model-settings.js";
import type { DynamicTool } from "./types.js";
import { ownerTimezone } from "./timezone.js";

const supportedCodexVersion = "0.156.1";
const unavailable = () => new Error("Ограниченный доступ сейчас недоступен. Повторите запрос позже.");
const accessChanged = () => new Error("Права доступа изменились. Отправьте запрос заново.");
const record = (value: unknown): value is Record<string, any> => Boolean(value && typeof value === "object" && !Array.isArray(value));
const maxResponseBytes = 1024 * 1024;
const safeBusinessErrors: Record<string, string> = {
  forbidden: "Действие недоступно для этого участника.",
  unavailable: "Сервис временно недоступен. Повторите запрос позже.",
  invalid_arguments: "Проверьте параметры действия.",
  report_revision_conflict: "Отчёт изменился. Откройте актуальную версию перед правкой.",
  plan_changed: "Расписание изменилось. Подготовьте новый предварительный просмотр.",
  in_progress: "Действие уже выполняется. Проверьте результат перед повтором.",
};

export interface RestrictedRunOptions {
  authorization: ScopedAuthorization;
  conversationId: string;
  messageId: string;
  signal?: AbortSignal;
  assertCurrent: () => void;
}

/** No shared Codex state, stored history, native Home tools or model-visible
 * connector credentials. Each dynamic call uses the same verified transport. */
export class RestrictedExecutor {
  private readonly running = new Set<{ controller: AbortController; engine?: CodexEngineAdapter }>();
  private closed = false;
  constructor(private readonly accounts: Accounts) {}

  async run(text: string, options: RestrictedRunOptions): Promise<{ response: string }> {
    const run: { controller: AbortController; engine?: CodexEngineAdapter } = { controller: new AbortController() };
    const signal = AbortSignal.any([run.controller.signal, ...(options.signal ? [options.signal] : [])]);
    let finished = false, root: string | undefined, accountId: string | undefined;
    const current = () => {
      if (this.closed || finished || signal.aborted) throw accessChanged();
      try { options.assertCurrent(); } catch { throw accessChanged(); }
    };
    this.running.add(run);
    try {
      current();
      const version = JSON.parse(readFileSync(createRequire(import.meta.url).resolve("@openai/codex/package.json"), "utf8")).version;
      if (version !== supportedCodexVersion) throw unavailable();
      const selection = resolveModelSelection(this.accounts.store, "main", undefined, options.conversationId);
      if (selection.provider !== "chatgpt") throw unavailable();
      // Deliberately no provider or quota fallback and no retry of a partial turn.
      const chosen = await this.accounts.choose("main", false);
      current();
      accountId = chosen.id;
      this.accounts.active.set(accountId, (this.accounts.active.get(accountId) ?? 0) + 1);
      const authorization = structuredClone(options.authorization);
      const proxy = new RestrictedMcpProxy(authorization, options.conversationId, signal, current);
      const definitions = await proxy.discover();
      current();
      root = mkdtempSync(join(tmpdir(), "openstrudel-restricted-"));
      const cwd = join(root, "workspace"), codexHome = join(root, "codex");
      mkdirSync(cwd, { mode: 0o500 });
      mkdirSync(codexHome, { mode: 0o700 });
      // Startup discovery is restricted too, before the first thread exists.
      const config: Record<string, any> = {};
      for (const [key, value] of Object.entries(restrictedCodexConfig(cwd))) {
        const parts = key.split("."); let cursor = config;
        for (const part of parts.slice(0, -1)) cursor = cursor[part] ??= {};
        cursor[parts.at(-1)!] = value;
      }
      writeFileSync(join(codexHome, "config.toml"), stringify(config), { mode: 0o600 });
      let timezone: string | undefined;
      try { const saved = ownerTimezone(this.accounts.store); if (saved) timezone = new Intl.DateTimeFormat("en", { timeZone: saved }).resolvedOptions().timeZone; } catch { /* An invalid preference must not become instructions. */ }
      const clock = `Current time: ${new Date().toISOString()}. ` + (timezone ? `Default timezone: ${timezone}; use it unless the user gives another.` : "No default timezone is configured; use the lesson's timezone or ask before moving it. The server clock is not the user's timezone.");
      const engine = new CodexEngineAdapter({ restricted: true, workingDirectory: cwd, codexHome,
        restrictedInstructions: [clock, proxy.instructions].filter(Boolean).join("\n\n"),
        authTokens: async refresh => { current(); const tokens = await chosen.service.authTokens(refresh); current(); return tokens; } });
      run.engine = engine;
      const result = await engine.run(text, { ...selection, conversationId: options.conversationId, messageId: options.messageId,
        signal, employees: [], approvalMode: "approve_all", tools: { definitions, call: (name, args) => proxy.call(name, args) } });
      current();
      return { response: result.response };
    } catch (error) {
      // Account/provider/HTTP exceptions can contain request details or headers.
      if (error instanceof Error && [accessChanged().message, unavailable().message].includes(error.message)) throw error;
      throw unavailable();
    } finally {
      finished = true;
      run.controller.abort();
      run.engine?.close();
      this.running.delete(run);
      if (accountId) {
        const remaining = (this.accounts.active.get(accountId) ?? 1) - 1;
        if (remaining) this.accounts.active.set(accountId, remaining); else this.accounts.active.delete(accountId);
      }
      if (root) rmSync(root, { recursive: true, force: true });
    }
  }

  close(): void {
    this.closed = true;
    for (const run of this.running) { run.controller.abort(); run.engine?.close(); }
  }
}

class RestrictedMcpProxy {
  instructions = "";
  private nextId = 0;
  private sessionId?: string;
  private protocolVersion = "2025-03-26";
  private readonly allowed: Set<string>;
  private readonly exposed = new Set<string>();
  private readonly headers: Headers;
  private readonly secrets: string[];
  constructor(private readonly authorization: ScopedAuthorization, conversationId: string,
    private readonly signal: AbortSignal, private readonly current: () => void) {
    const url = new URL(authorization.connector.url);
    if (url.protocol !== "https:" || url.username || url.password || url.hash || url.search) throw unavailable();
    const actor = authorization.actor;
    if (!/^[1-9][0-9]{0,19}$/.test(actor.userId) || !/^-?[1-9][0-9]{0,19}$/.test(actor.chatId)
      || !new RegExp(`^${actor.chatId}:[1-9][0-9]*$`).test(actor.messageId)
      || !/^[A-Za-z0-9_.:-]{1,180}$/.test(conversationId)) throw unavailable();
    if (authorization.tools.length > 100 || authorization.tools.some(t => !/^[A-Za-z][A-Za-z0-9_.-]{0,95}$/.test(t.name))) throw unavailable();
    this.allowed = new Set(authorization.tools.map(t => t.name));
    if (this.allowed.size !== authorization.tools.length) throw unavailable();
    this.headers = new Headers(authorization.connector.headers);
    this.secrets = Object.entries(authorization.connector.headers)
      .filter(([key]) => /authorization|token|key|secret|cookie/i.test(key))
      .flatMap(([, value]) => [value, value.replace(/^Bearer\s+/i, "")]).filter(value => value.length >= 8);
    for (const key of [...this.headers.keys()]) if (/^x-hermes-|^mcp-|^host$|^content-length$|^connection$/i.test(key)) this.headers.delete(key);
    this.headers.set("content-type", "application/json");
    this.headers.set("accept", "application/json, text/event-stream");
    this.headers.set("x-hermes-platform", "telegram");
    this.headers.set("x-hermes-user-id", actor.userId);
    this.headers.set("x-hermes-chat-id", actor.chatId);
    this.headers.set("x-hermes-message-id", actor.messageId);
    this.headers.set("x-hermes-session-id", "openstrudel:" + conversationId);
  }

  async discover(): Promise<DynamicTool[]> {
    const initialized = await this.request("initialize", { protocolVersion: this.protocolVersion,
      capabilities: {}, clientInfo: { name: "openstrudel-restricted", version: "1" } });
    if (!["2024-11-05", "2025-03-26", "2025-06-18"].includes(initialized.protocolVersion)) throw unavailable();
    if (initialized.instructions !== undefined && (typeof initialized.instructions !== "string" || initialized.instructions.length > 32_000)) throw unavailable();
    this.instructions = initialized.instructions ?? "";
    this.protocolVersion = initialized.protocolVersion;
    await this.request("notifications/initialized", {}, true);
    const definitions: DynamicTool[] = [], seen = new Set<string>(), cursors = new Set<string>();
    let cursor: string | undefined;
    for (let page = 0; page < 100; page++) {
      const list = await this.request("tools/list", cursor ? { cursor } : {});
      if (!Array.isArray(list.tools) || seen.size + list.tools.length > 100) throw unavailable();
      for (const tool of list.tools) {
        if (!record(tool) || typeof tool.name !== "string" || seen.has(tool.name)) throw unavailable();
        seen.add(tool.name);
        if (!this.allowed.has(tool.name)) continue;
        if (!record(tool.inputSchema) || tool.inputSchema.type !== "object" || typeof tool.description !== "string") throw unavailable();
        definitions.push({ type: "function", name: tool.name, description: tool.description, inputSchema: tool.inputSchema });
        this.exposed.add(tool.name);
      }
      if (list.nextCursor === undefined || list.nextCursor === null) return definitions;
      if (typeof list.nextCursor !== "string" || !list.nextCursor || list.nextCursor.length > 1000 || cursors.has(list.nextCursor)) throw unavailable();
      cursor = list.nextCursor; cursors.add(cursor);
    }
    throw unavailable();
  }

  async call(name: string, args: Record<string, unknown>): Promise<unknown> {
    this.current();
    if (!this.allowed.has(name) || !this.exposed.has(name) || !record(args)) throw new Error("Действие недоступно для этого участника.");
    const result = await this.request("tools/call", { name, arguments: args });
    if (result.isError) {
      let code = result.structuredContent?.code;
      for (const item of result.content ?? []) if (!code && item?.type === "text") {
        try { code = JSON.parse(item.text)?.code; } catch { /* Never return raw service errors. */ }
      }
      const safeCode = typeof code === "string" && Object.hasOwn(safeBusinessErrors, code) ? code : "unavailable";
      return { ok: false, code: safeCode, text: safeBusinessErrors[safeCode] };
    }
    return result;
  }

  private async request(method: string, params: Record<string, unknown>, notification = false): Promise<Record<string, any>> {
    this.current();
    const id = ++this.nextId, headers = new Headers(this.headers);
    if (this.sessionId) headers.set("mcp-session-id", this.sessionId);
    if (method !== "initialize") headers.set("mcp-protocol-version", this.protocolVersion);
    try {
      const response = await fetch(this.authorization.connector.url, { method: "POST", redirect: "error", headers,
        signal: AbortSignal.any([this.signal, AbortSignal.timeout(30_000)]),
        body: JSON.stringify({ jsonrpc: "2.0", ...(notification ? {} : { id }), method, params }) });
      this.current();
      if (!response.ok) { await response.body?.cancel(); throw unavailable(); }
      const session = response.headers.get("mcp-session-id");
      if (session) {
        if (!/^[\x21-\x7e]{1,512}$/.test(session) || this.sessionId && session !== this.sessionId) throw unavailable();
        this.sessionId = session;
      }
      if (notification) { await response.body?.cancel(); return {}; }
      const body = await boundedResponse(response, id);
      this.current();
      if (!record(body) || body.jsonrpc !== "2.0" || body.id !== id || body.error || !record(body.result)) throw unavailable();
      if (this.secrets.some(secret => JSON.stringify(body.result).includes(secret))) throw unavailable();
      return body.result;
    } catch {
      this.current();
      throw unavailable();
    }
  }
}

async function boundedResponse(response: Response, id: number): Promise<unknown> {
  if (!response.body || Number(response.headers.get("content-length") ?? 0) > maxResponseBytes) throw unavailable();
  const reader = response.body.getReader(), decoder = new TextDecoder();
  let bytes = 0, text = "";
  const streaming = response.headers.get("content-type")?.includes("text/event-stream");
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > maxResponseBytes) throw unavailable();
      text += decoder.decode(chunk.value, { stream: true });
      if (streaming) {
        let boundary: RegExpExecArray | null;
        while ((boundary = /\r?\n\r?\n/.exec(text))) {
          const event = text.slice(0, boundary.index); text = text.slice(boundary.index + boundary[0].length);
          const data = event.split(/\r?\n/).filter(line => line.startsWith("data:")).map(line => line.slice(5).trimStart()).join("\n");
          if (!data) continue;
          const message = JSON.parse(data);
          if (message.id === id) return message;
        }
      }
    }
    text += decoder.decode();
    if (streaming) throw unavailable();
    return JSON.parse(text);
  } finally { await reader.cancel(); }
}
