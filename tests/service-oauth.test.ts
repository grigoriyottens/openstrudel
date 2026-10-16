import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import { serviceOAuth, validateServiceCallback } from "../src/service-oauth.js";

it.each(["openstrudel://oauth/service/fixture", "https://home.example/oauth/service/fixture"])(
  "completes native Codex OAuth at %s without changing config or accepting a foreign callback", async callbackURL => {
    const home = mkdtempSync(join(tmpdir(), "strudel-service-oauth-"));
    let origin = "", exchanges = 0, connected = 0, closed = 0, verifier = "";
    const server = createServer(async (request, response) => {
      let body = ""; for await (const part of request) body += part;
      const path = new URL(request.url!, origin).pathname;
      const json = (status: number, value: unknown) => { response.writeHead(status, { "content-type": "application/json" }); response.end(JSON.stringify(value)); };
      if (path.startsWith("/.well-known/oauth-protected-resource")) return json(200, { resource: origin + "/mcp", authorization_servers: [origin] });
      if (path.startsWith("/.well-known/")) return json(200, { issuer: origin, authorization_endpoint: origin + "/authorize", token_endpoint: origin + "/token", registration_endpoint: origin + "/register", response_types_supported: ["code"], grant_types_supported: ["authorization_code", "refresh_token"], code_challenge_methods_supported: ["S256"], token_endpoint_auth_methods_supported: ["none"] });
      if (path === "/register") return json(201, { ...JSON.parse(body), client_id: "fixture" });
      if (path === "/token") { exchanges++; verifier = new URLSearchParams(body).get("code_verifier")!; return json(200, { access_token: "fixture-token", token_type: "Bearer", expires_in: 3600 }); }
      if (path === "/mcp") {
        if (!request.headers.authorization) { response.setHeader("www-authenticate", `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource/mcp"`); return json(401, { error: "unauthorized" }); }
        const message = body ? JSON.parse(body) : {};
        if (message.id !== undefined) return json(200, { jsonrpc: "2.0", id: message.id, result: message.method === "initialize" ? { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "fixture", version: "1" } } : { tools: [] } });
        response.writeHead(202).end(); return;
      }
      json(404, {});
    });
    await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
    origin = "http://127.0.0.1:" + (server.address() as { port: number }).port;
    const config = `[mcp_servers.fixture]\nurl = "${origin}/mcp"\n`;
    writeFileSync(join(home, "config.toml"), config);
    let login: Awaited<ReturnType<typeof serviceOAuth>> | undefined;
    try {
      login = await serviceOAuth({ name: "fixture", home, callbackURL, connected: async () => { connected++; }, closed: () => { closed++; } });
      const authorization = new URL(login.url!);
      const callback = new URL(authorization.searchParams.get("redirect_uri")!);
      expect(callback.href.startsWith(callbackURL + "/")).toBe(true);
      callback.searchParams.set("code", "fixture-code"); callback.searchParams.set("state", "foreign-state");
      await expect(login.oauth!.complete(callback.href)).rejects.toThrow("не относится");
      expect(exchanges).toBe(0);
      callback.searchParams.set("state", authorization.searchParams.get("state")!);
      await login.oauth!.complete(callback.href);
      expect(exchanges).toBe(1); expect(connected).toBe(1); expect(closed).toBe(1);
      expect(createHash("sha256").update(verifier).digest("base64url")).toBe(authorization.searchParams.get("code_challenge"));
      expect(readFileSync(join(home, "config.toml"), "utf8")).toBe(config);
      await expect(login.oauth!.complete(callback.href)).rejects.toThrow("завершён");
      expect(exchanges).toBe(1);
    } finally {
      login?.oauth?.cancel();
      await new Promise<void>(resolve => server.close(() => resolve()));
      rmSync(home, { recursive: true, force: true });
    }
  }, 30_000,
);

it("rejects callback substitution, duplicate fields and fragments while preserving issuer and denial", () => {
  const expected = new URL("openstrudel://oauth/service/login/server");
  for (const value of [
    "https://evil.test/service/login/server?state=state&code=code",
    "openstrudel://oauth:123/service/login/server?state=state&code=code",
    "openstrudel://oauth/service/other/server?state=state&code=code",
    expected + "?state=state&state=state&code=code",
    expected + "?state=state&code=one&code=two",
    expected + "?state=state&code=code#error",
    expected + "?state=state&code=code&error=denied",
    expected + "?state=state",
  ]) expect(() => validateServiceCallback(value, expected, "state"), value).toThrow();
  expect(validateServiceCallback(expected + "?state=state&error=access_denied&iss=https%3A%2F%2Fissuer.test", expected, "state").searchParams.get("iss")).toBe("https://issuer.test");
});
