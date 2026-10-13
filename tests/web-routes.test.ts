import { expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { OpenStrudelRuntime } from "../src/runtime.js";
import { MockCodexEngine } from "../src/codex.js";

it("serves every script and character the page loads, with the inline script under the nonce", async () => {
  const root = mkdtempSync(join(tmpdir(), "strudel-web-routes-"));
  const runtime = new OpenStrudelRuntime({ rootDirectory: root, dbPath: ":memory:", apiToken: "test-owner", engine: new MockCodexEngine(), startTelegram: false });
  const address = await runtime.api.listen("127.0.0.1", 0), base = `http://127.0.0.1:${address.port}`;
  try {
    const page = await fetch(base + "/");
    const html = await page.text();
    const policy = page.headers.get("content-security-policy")!;
    const nonce = /script-src 'self' 'nonce-([^']+)'/.exec(policy)?.[1];
    expect(nonce).toBeTruthy();
    const inline = [...html.matchAll(/<script(?![^>]*\bsrc=)([^>]*)>/g)];
    expect(inline.length).toBeGreaterThan(0);
    for (const [, attributes] of inline) expect(attributes).toContain(`nonce="${nonce}"`);
    const scripts = [...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map((match) => match[1]!);
    expect(scripts).toContain("/markdown.js");
    for (const path of scripts) {
      const response = await fetch(base + path);
      expect(response.status, path).toBe(200);
      expect(response.headers.get("content-type"), path).toContain("text/javascript");
    }
    const main = await fetch(base + "/characters/main.png");
    expect(main.status).toBe(200);
    expect(main.headers.get("content-type")).toBe("image/png");
    expect((await fetch(base + "/characters/../index.html")).status).not.toBe(200);
    expect((await fetch(base + "/characters/other.png")).status).not.toBe(200);
  } finally { await runtime.stop(); rmSync(root, { recursive: true, force: true }); }
});
