import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it, vi } from "vitest";
import { OpenStrudelRuntime } from "../src/runtime.js";
import { mockResponses } from "./fixtures/mock-responses.js";

const files = (directory: string): string[] => readdirSync(directory, { withFileTypes: true, recursive: true }).filter(entry => entry.isFile()).map(entry => join(entry.parentPath, entry.name));

it("runs an xAI turn through the real Codex app-server with only the provider's key", async () => {
  const provider = await mockResponses("pong from grok");
  const root = mkdtempSync(join(tmpdir(), "openstrudel-provider-e2e-"));
  vi.stubEnv("OPENSTRUDEL_CODEX_MODE", "");
  vi.stubEnv("OPENSTRUDEL_PROVIDER_XAI_BASE_URL", provider.url);
  // Never started: no local connection file is published and no Telegram or setup server runs.
  const runtime = new OpenStrudelRuntime({ rootDirectory: root, dbPath: join(root, ".data/openstrudel.sqlite"), startTelegram: false, apiToken: "e2e" });
  try {
    runtime.store.setSetting("providers.xai.key", "xai-e2e-key");
    expect((await runtime.messages.handle({ channel: "api", text: "Say pong", externalChatId: "home" })).text).toBe("pong from grok");
    const turns = provider.requests.filter(request => request.url.startsWith("/v1/responses"));
    expect(turns.length).toBeGreaterThan(0);
    for (const turn of turns) {
      expect(turn.headers.authorization).toBe("Bearer xai-e2e-key");
      expect(Object.keys(turn.headers).filter(name => /chatgpt|openai/i.test(name))).toEqual([]);
      expect(turn.body.model).toBe("grok-4.7");
      expect(turn.body.tools.map((tool: any) => tool.type)).not.toContain("web_search");
    }
    for (const file of files(join(root, ".data/providers"))) expect(readFileSync(file).includes("xai-e2e-key"), file).toBe(false);
  } finally {
    await runtime.stop(); await provider.close(); vi.unstubAllEnvs();
    // A stopped Codex releases its thread-writer lock a moment later.
    for (let attempt = 0; attempt < 20 && existsSync(root); attempt++) { rmSync(root, { recursive: true, force: true, maxRetries: 5 }); await new Promise(done => setTimeout(done, 300)); }
  }
}, 120_000);
