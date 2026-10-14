import { createSdkMcpServer, query as sdkQuery, tool, type CanUseTool, type McpServerConfig, type PermissionResult, type SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import { mkdirSync, readFileSync } from "node:fs";
import { resolve, sep } from "node:path";
import { z } from "zod";
import { INSTRUCTIONS } from "./codex.js";
import { readToml } from "./extensions.js";
import type { ModelChoice } from "./model-settings.js";
import { ProviderKeyError, providerModels, providerNotConnected, type ProviderInfo } from "./providers.js";
import type { CodexEngine, CodexRunResult } from "./types.js";

export interface ClaudeEngineOptions {
  /** Home root; private state lives under `<root>/.data`. */
  root: string;
  /** A registry provider whose engine is "claude". */
  provider: ProviderInfo;
  /** Read at the start of every turn so a replaced key applies to the next turn. */
  key: () => string | null;
  /** Test seam for the SDK entry point. */
  query?: typeof sdkQuery;
}

type RunOptions = NonNullable<Parameters<CodexEngine["run"]>[1]>;

const contexts = /^(personal|work|group-[a-f0-9]{64}|(?:import|agent)-[a-f0-9]{32})$/;
const instructions = INSTRUCTIONS.replace("Use Codex's native tools, memory, skills and connectors.", "Use your native tools and connected services.")
  .replace("request_user_input", "AskUserQuestion").replace("Follow Codex's native approval policy", "Follow the approval policy");
// Claude Code sends background and helper work to Claude aliases; another vendor must only see its own model.
const aliases = ["ANTHROPIC_DEFAULT_FABLE_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_SMALL_FAST_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL"];
const edits = ["Edit", "MultiEdit", "Write", "NotebookEdit"];

/** The Claude Agent SDK behind the same CodexEngine contract. One per provider;
 * each turn is one CLI process that resumes its session by id. */
export class ClaudeEngine implements CodexEngine {
  private readonly running = new Set<AbortController>();
  constructor(readonly options: ClaudeEngineOptions) {}
  forContext(context: string): CodexEngine {
    if (!contexts.test(context)) throw new Error("Область не найдена");
    return { run: (input, options) => this.turn(context, input, options), models: () => this.models() };
  }
  run: CodexEngine["run"] = (input, options) => this.forContext("personal").run(input, options);
  async models(): Promise<ModelChoice[]> { return providerModels(this.options.provider); }
  close(): void { for (const turn of this.running) turn.abort(); }

  private async turn(context: string, input: string, options: RunOptions = {}): Promise<CodexRunResult> {
    const { root, provider } = this.options, key = this.options.key();
    if (!key) throw providerNotConnected(provider.id);
    const config = resolve(root, ".data/providers", provider.id, "claude", context), home = resolve(config, "home"), cwd = resolve(root, ".data/workspace", context);
    for (const dir of [home, cwd]) mkdirSync(dir, { recursive: true, mode: 0o700 });
    const model = options.model ?? (provider.models.find(m => m.recommended) ?? provider.models[0])!.id;
    const env: Record<string, string> = {};
    for (const name of ["PATH", "SHELL", "TMPDIR", "LANG", "LC_ALL", "TZ", "USER", "LOGNAME", "TERM"]) if (process.env[name]) env[name] = process.env[name]!;
    Object.assign(env, { HOME: home, CLAUDE_CONFIG_DIR: config, ANTHROPIC_BASE_URL: provider.baseUrl,
      ...provider.auth === "bearer" ? { ANTHROPIC_AUTH_TOKEN: key, ANTHROPIC_API_KEY: "" } : { ANTHROPIC_API_KEY: key },
      CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK: "1",
      // Commands and MCP servers inherit the CLI environment; the key must not reach them.
      CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1" });
    if (provider.id !== "anthropic") for (const name of aliases) env[name] = model;

    const mode = options.approvalMode ?? "ask", group = options.groupContext === true, ask = options.onRequest;
    const inside = (path: unknown) => typeof path === "string" && (resolve(cwd, path) + sep).startsWith(cwd + sep);
    const canUseTool: CanUseTool = async (name, input, { mcpServer }) => {
      const allow: PermissionResult = { behavior: "allow", updatedInput: input }, deny = (message: string): PermissionResult => ({ behavior: "deny", message });
      const path = input.file_path ?? input.notebook_path, edit = edits.includes(name);
      const accepted = (answer: any) => answer?.decision === "accept" ? allow : deny("The user declined this action.");
      try {
        if (mcpServer?.source === "sdk" || ["WebFetch", "WebSearch", "SandboxNetworkAccess"].includes(name)) return allow;
        if (name === "AskUserQuestion") {
          if (!ask) return deny("No user is available to answer.");
          const questions = (input.questions as any[]).map((q, i) => ({ id: String(i), header: q.header, question: q.question, options: q.options }));
          const { answers } = await ask("item/tool/requestUserInput", { questions }) as { answers: Record<string, { answers: string[] }> };
          return { behavior: "allow", updatedInput: { ...input, answers: Object.fromEntries(questions.map(q => [q.question, answers[q.id]?.answers.join(", ") ?? ""])) } };
        }
        if (group && (name === "Bash" || edit)) return deny("Commands and file changes are not available in a group chat.");
        // Codex workspace-write: the workspace is writable without asking; anything beyond it needs the owner.
        if (edit && inside(path)) return allow;
        if (mode === "approve_all") return edit ? deny("Only files inside the workspace can be changed.") : allow;
        if (!ask) return deny("No user is available to approve this action.");
        if (name === "Bash") return accepted(await ask("item/commandExecution/requestApproval", { command: input.command, cwd, reason: input.description }));
        if (edit) return accepted(await ask("item/fileChange/requestApproval", { reason: `${name} ${path}`, grantRoot: resolve(cwd, String(path), "..") }));
        if (name.startsWith("mcp__") && mcpServer) {
          const answer = await ask("mcpServer/elicitation/request", { mode: "form", serverName: mcpServer.name,
            message: `Allow the ${mcpServer.name} MCP server to run tool "${name.slice(`mcp__${mcpServer.name}__`.length)}"?`,
            requestedSchema: { type: "object", properties: {} }, _meta: { codex_approval_kind: "mcp_tool_call", tool_params: input } }) as { action?: string };
          return answer?.action === "accept" ? allow : deny("The user declined this action.");
        }
        return deny("This action is not available.");
      } catch (error) { return deny(error instanceof Error ? error.message : String(error)); }
    };

    const servers: Record<string, McpServerConfig> = extensionServers(resolve(root, ".data/extensions", context, "config.toml"));
    const tools = options.tools;
    if (tools) servers.openstrudel = createSdkMcpServer({ name: "openstrudel", alwaysLoad: true, tools: tools.definitions.map(d =>
      tool(d.name, d.description, (z.fromJSONSchema(d.inputSchema as any) as z.ZodObject).shape, async args => {
        try { return { content: [{ type: "text", text: JSON.stringify(await tools.call(d.name, args)) }] }; }
        catch (error) { return { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], isError: true }; }
      })) });
    const images = provider.models.find(m => m.id === model)?.images ? (options.images ?? []).flatMap(path => {
      const data = readFileSync(path), media = imageType(data);
      return media ? [{ type: "image" as const, source: { type: "base64" as const, media_type: media, data: data.toString("base64") } }] : [];
    }) : [];
    const message: SDKUserMessage = { type: "user", message: { role: "user", content: [{ type: "text", text: input }, ...images] }, parent_tool_use_id: null };

    const abort = new AbortController();
    this.running.add(abort);
    let threadId = "", response: string | undefined, rejected = false, stopped = false, failure: string | undefined, stop = () => {};
    try {
      const turn = (this.options.query ?? sdkQuery)({ prompt: (async function* () { yield message; })(), options: {
        cwd, env, model, abortController: abort, resume: options.threadId ?? undefined, permissionMode: "default", canUseTool, mcpServers: servers,
        // Nothing from ~/.claude, the workspace's .mcp.json or CLAUDE.md. User text never runs CLI slash commands or @file mentions.
        settingSources: [], strictMcpConfig: true, verbatimPrompts: true,
        // Not recorded in the session, so a changed SOUL applies on resume.
        systemPrompt: { type: "preset", preset: "claude_code", append: instructions + (options.profile ? `\n\nCurrent employee SOUL (authoritative):\n${options.profile}` : ""), snapshot: false },
        // Schedules live in OpenStrudel; the CLI's own cron dies with this per-turn process.
        disallowedTools: ["CronCreate", "CronDelete", "CronList", "ScheduleWakeup", ...provider.webSearch ? [] : ["WebSearch"]],
        sandbox: group ? undefined : { enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: mode !== "approve_all", failIfUnavailable: mode === "approve_all" },
      } });
      // An interrupt, unlike an abort, ends the turn only after the CLI has written its transcript and exited,
      // so the next turn never resumes a session another process is still writing. close() still kills.
      stop = () => { if (!stopped) { stopped = true; turn.interrupt().catch(() => abort.abort()); } };
      options.signal?.addEventListener("abort", stop, { once: true });
      if (options.signal?.aborted) stop();
      for await (const m of turn) {
        if (!threadId && "session_id" in m && m.session_id) { threadId = m.session_id; options.onEvent?.({ type: "thread.started", payload: { threadId } }); }
        // The CLI retries a rejected key for minutes; the owner has to replace it instead.
        if (m.type === "system" && m.subtype === "api_retry" && (m.error_status === 401 || m.error_status === 403) || m.type === "assistant" && m.error === "authentication_failed") { rejected = true; stop(); }
        if (m.type === "result") {
          if (m.subtype === "success" && !m.is_error) response = m.result;
          else if (m.subtype === "success" && (m.api_error_status === 401 || m.api_error_status === 403)) rejected = true;
          else failure = (m.subtype === "success" ? m.result : m.errors.join("\n")) || m.subtype;
        }
      }
    } catch (error) { if (!stopped && !abort.signal.aborted) failure = error instanceof Error ? error.message : String(error); }
    finally { options.signal?.removeEventListener("abort", stop); this.running.delete(abort); }
    if (rejected) throw new ProviderKeyError(provider);
    if (response === undefined && (stopped || abort.signal.aborted)) throw new Error("Ответ остановлен");
    if (failure !== undefined) throw new Error(`${provider.name} не завершил ответ: ${failure.replace(/^API Error:\s*/, "").split("\n")[0]!.slice(0, 300)}`);
    return { threadId, response: response || "Готово.", events: [] };
  }
}

/** The context's Codex-style MCP services. Computer Use runs on Codex's own kernel and is left out. */
function extensionServers(path: string): Record<string, McpServerConfig> {
  return Object.fromEntries(Object.entries(readToml(path).mcp_servers ?? {}).flatMap(([name, s]: [string, any]): Array<[string, McpServerConfig]> =>
    s.enabled === false || name === "cua_repl" ? [] : s.url ? [[name, { type: "http", url: s.url, headers: s.http_headers }]]
      : s.command ? [[name, { type: "stdio", command: s.command, args: s.args ?? [], env: s.env }]] : []));
}

/** The API checks the bytes, not the uploaded name or declared type. */
function imageType(data: Buffer): "image/png" | "image/jpeg" | "image/gif" | "image/webp" | undefined {
  if (data.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return "image/png";
  if (data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) return "image/jpeg";
  if (data.subarray(0, 4).toString("latin1") === "GIF8") return "image/gif";
  if (data.subarray(0, 4).toString("latin1") === "RIFF" && data.subarray(8, 12).toString("latin1") === "WEBP") return "image/webp";
}
