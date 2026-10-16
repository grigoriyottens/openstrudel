import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { request as httpsRequest } from "node:https";
import { expect, it, vi } from "vitest";
import { OpenStrudelRuntime } from "../src/runtime.js";
import { MockCodexEngine } from "../src/codex.js";
import { digest } from "../src/home.js";
import { validateServiceCallback } from "../src/service-oauth.js";

it("keeps remote service sign-in owner-only, bound to its client, single-use, and reachable over Home TLS", async () => {
  const directory = mkdtempSync(join(tmpdir(), "strudel-oauth-api-"));
  const complete = vi.fn(), cancel = vi.fn();
  const callbacks = new Map<string, string>();
  const connect = vi.fn(async (id: string, options?: { callbackURL: string }) => {
    if (!options) return { url: "https://service.test/legacy" };
    const callback = options.callbackURL + "/server";
    callbacks.set(new URL(options.callbackURL).pathname.split("/").pop()!, callback);
    return { url: "https://service.test/authorize", oauth: {
      cancel,
      complete: async (value: string) => { validateServiceCallback(value, new URL(callback), "fixture-state"); complete(id); },
    } };
  });
  const engine = Object.assign(new MockCodexEngine(), { connect });
  const runtime = new OpenStrudelRuntime({ rootDirectory: directory, dbPath: ":memory:", apiToken: "fixture-owner", engine, startTelegram: false, mobilePort: 0 });
  try {
    const address = await runtime.api.listen("127.0.0.1", 0), base = `http://127.0.0.1:${address.port}`;
    const call = (path: string, method = "GET", body?: unknown, headers: Record<string, string> = {}) => fetch(base + path, {
      method, headers: { "content-type": "application/json", ...headers }, ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    const owner = { authorization: "Bearer fixture-owner" };
    const session = async (isOwner: boolean) => {
      const response = await call("/auth/session", "POST", { key: runtime.api.web.invite(isOwner).key });
      return { cookie: response.headers.get("set-cookie")!.split(";")[0]!, "x-openstrudel-csrf": (await response.json()).csrf };
    };
    const mine = await session(true), other = await session(true), colleague = await session(false);
    expect((await call("/v1/connections/connect", "POST", { id: "mcp:fixture", callback: "app" }, colleague)).status).toBe(403);
    expect(connect).not.toHaveBeenCalled();
    const start = async (callback: "app" | "web", auth = mine) => {
      const response = await call("/v1/connections/connect", "POST", { id: "mcp:fixture", callback }, auth);
      expect(response.status).toBe(200);
      const result = await response.json(); expect(result).not.toHaveProperty("oauth");
      expect(result.signInId).toMatch(/^[a-f0-9]{48}$/); return result.signInId as string;
    };
    const id = await start("app"), path = "/v1/connections/oauth/" + id;
    const returned = callbacks.get(id)! + "?code=test&state=fixture-state";
    expect((await call(path, "POST", { url: returned }, other)).status).toBe(404);
    expect((await call(path, "DELETE", undefined, colleague)).status).toBe(403);
    expect((await call(path, "POST", { url: returned.replace("fixture-state", "wrong") }, mine)).ok).toBe(false);
    expect(complete).not.toHaveBeenCalled();
    expect((await call(path, "POST", { url: returned }, mine)).status).toBe(200);
    expect(complete).toHaveBeenCalledExactlyOnceWith("mcp:fixture");
    expect((await call(path, "POST", { url: returned }, mine)).status).toBe(404);
    expect((await call("/v1/connections/connect", "POST", { id: "mcp:fixture" }, owner)).status).toBe(200);

    // Provider redirects have neither our bearer nor our SameSite=Strict cookie.
    const web = await start("web"), publicPath = new URL(callbacks.get(web)!).pathname;
    expect((await call(publicPath + "?state=wrong&code=test")).status).toBe(400);
    const response = await call(publicPath + "?state=fixture-state&code=test");
    expect(response.status).toBe(200); expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("content-security-policy")).toContain("default-src 'none'");
    expect((await call(publicPath + "?state=fixture-state&code=test")).status).toBe(400);

    const tls = async (path: string, method = "GET", body?: unknown, token?: string) => new Promise<{ status: number; text: string }>((resolve, reject) => {
      const request = httpsRequest({ hostname: "127.0.0.1", port: runtime.api.mobile.port!, rejectUnauthorized: false, path, method,
        headers: { "content-type": "application/json", ...(token ? { authorization: "Bearer " + token } : {}) } }, response => {
        let text = ""; response.on("data", part => text += part); response.on("end", () => resolve({ status: response.statusCode!, text }));
      }); request.on("error", reject); request.end(body ? JSON.stringify(body) : undefined);
    });
    const invitation = await runtime.api.mobile.invite(true);
    const paired = await tls("/pair", "POST", {}, new URL(invitation.url).searchParams.get("key")!);
    const token = JSON.parse(paired.text).token;
    const tlsStart = await tls("/v1/connections/connect", "POST", { id: "mcp:fixture", callback: "web" }, token);
    expect(tlsStart.status).toBe(200);
    const tlsId = JSON.parse(tlsStart.text).signInId, tlsPath = new URL(callbacks.get(tlsId)!).pathname;
    expect((await tls(tlsPath + "?state=fixture-state&code=test")).status).toBe(200);

    const revokedSession = await session(true);
    const revokedID = await start("web", revokedSession);
    await call("/auth/logout", "POST", {}, revokedSession);
    const completedBeforeRevocation = complete.mock.calls.length;
    expect((await call(new URL(callbacks.get(revokedID)!).pathname + "?state=fixture-state&code=test")).status).toBe(400);
    expect(complete.mock.calls.length).toBe(completedBeforeRevocation);
    const revokedMobile = await tls("/v1/connections/connect", "POST", { id: "mcp:fixture", callback: "web" }, token);
    const revokedMobileID = JSON.parse(revokedMobile.text).signInId;
    runtime.api.mobile.revokeClient(digest(token).slice(0,20));
    expect((await tls(new URL(callbacks.get(revokedMobileID)!).pathname + "?state=fixture-state&code=test")).status).toBe(400);
    expect(complete.mock.calls.length).toBe(completedBeforeRevocation);

    const canceled = await start("app");
    expect((await call("/v1/connections/oauth/" + canceled, "DELETE", undefined, mine)).status).toBe(200);
    expect((await call("/v1/connections/oauth/" + canceled, "POST", { url: callbacks.get(canceled) }, mine)).status).toBe(404);
    for (let i = 0; i < 8; i++) await start("app");
    expect((await call("/v1/connections/connect", "POST", { id: "mcp:fixture", callback: "app" }, mine)).status).toBe(429);
  } finally { await runtime.stop(); rmSync(directory, { recursive: true, force: true }); }
  expect(cancel).toHaveBeenCalledTimes(14);
});

it("cancels an OAuth login whose client leaves before receiving the browser URL", async () => {
  const directory = mkdtempSync(join(tmpdir(), "strudel-oauth-abort-"));
  const cancel = vi.fn();
  let release!: () => void;
  const ready = new Promise<void>(resolve => { release = resolve; });
  const connect = vi.fn(async () => {
    await ready;
    return { url: "https://service.test/authorize", oauth: { cancel, complete: async () => {} } };
  });
  const runtime = new OpenStrudelRuntime({ rootDirectory: directory, dbPath: ":memory:",
    apiToken: "fixture-owner", engine: Object.assign(new MockCodexEngine(), { connect }), startTelegram: false });
  try {
    const address = await runtime.api.listen("127.0.0.1", 0);
    const controller = new AbortController();
    const response = fetch(`http://127.0.0.1:${address.port}/v1/connections/connect`, {
      method: "POST", signal: controller.signal,
      headers: { authorization: "Bearer fixture-owner", "content-type": "application/json" },
      body: JSON.stringify({ id: "mcp:fixture", callback: "app" }),
    }).catch(error => error);
    await vi.waitFor(() => expect(connect).toHaveBeenCalledOnce());
    controller.abort(); await response;
    // Give the actual socket close event a turn before the provider responds.
    await new Promise(resolve => setTimeout(resolve, 20));
    release();
    await vi.waitFor(() => expect(cancel).toHaveBeenCalledOnce());
  } finally { release(); await runtime.stop(); rmSync(directory, { recursive: true, force: true }); }
});
