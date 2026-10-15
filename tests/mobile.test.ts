import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:https";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { describe, expect, it, vi } from "vitest";
import { Store } from "../src/store.js";
import { MobileAccess } from "../src/mobile.js";
import { Home } from "../src/home.js";
import { OpenStrudelRuntime } from "../src/runtime.js";
import { MockCodexEngine } from "../src/codex.js";

function call(port: number, path: string, token?: string, origin?: string, nonce?: string, method?: string) {
  return new Promise<{ status: number; body: any }>((resolve, reject) => {
    const req = request({ hostname: "127.0.0.1", port, path, method: method ?? (path === "/pair" ? "POST" : "GET"), rejectUnauthorized: false,
      headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(origin ? { origin } : {}), ...(nonce ? { "x-openstrudel-pair-id": nonce } : {}) },
    }, res => {
      let body = "";
      res.on("data", chunk => { body += chunk; });
      res.on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(body) }));
    });
    req.on("error", reject); req.end();
  });
}

function send(port: number, path: string, options: { token?: string; method?: string; body?: unknown } = {}) {
  return new Promise<{ status: number; body: any }>((resolve, reject) => {
    const req = request({ hostname: "127.0.0.1", port, path, method: options.method ?? "GET", rejectUnauthorized: false,
      headers: { ...(options.token ? { authorization: `Bearer ${options.token}` } : {}), ...(options.body ? { "content-type": "application/json" } : {}) },
    }, res => {
      let body = "";
      res.on("data", chunk => { body += chunk; });
      res.on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(body) }));
    });
    req.on("error", reject); req.end(options.body ? JSON.stringify(options.body) : undefined);
  });
}

describe("iPhone pairing", () => {
  it("lets the owner revoke one colleague while every other connection keeps working", async () => {
    const root = await mkdtemp(join(tmpdir(), "strudel-colleagues-"));
    const runtime = new OpenStrudelRuntime({ rootDirectory: root, dbPath: ":memory:", apiToken: "test-owner", engine: new MockCodexEngine(), startTelegram: false, mobilePort: 0 });
    try {
      const address = await runtime.api.listen("127.0.0.1", 0);
      const local = async (path: string, method = "GET", body?: unknown) => {
        const response = await fetch(`http://127.0.0.1:${address.port}${path}`, { method, headers: { authorization: "Bearer test-owner", "content-type": "application/json" }, ...(body ? { body: JSON.stringify(body) } : {}) });
        return { status: response.status, body: await response.json() as any };
      };
      expect((await local("/health")).body).toMatchObject({ colleagueInvitesVersion: 1, ownerInvitesVersion: 1 });
      const invite = async (body: unknown) => (await local("/v1/mobile/pairing", "POST", body)).body;
      const pair = async (invitation: { url: string }, name?: string) => (await send(runtime.api.mobile.port!, "/pair", { method: "POST", token: new URL(invitation.url).searchParams.get("key")!, body: name ? { name } : undefined })).body.token as string;
      const owner = await pair(await invite({ owner: true }), "Mik's iPhone");
      const port = runtime.api.mobile.port!;
      const first = await invite({ owner: false, label: "Юля" }), second = await invite({ owner: false });
      expect(first.id).not.toBe(second.id);
      // Every waiting link is listed with its role and can be cancelled by its id.
      const waiting = await invite({ owner: true });
      expect((await local("/v1/mobile")).body.invitations.map((i: any) => i.role)).toEqual(["colleague", "colleague", "owner"]);
      expect((await local("/v1/mobile/pairing/" + waiting.id, "DELETE")).status).toBe(200);
      await invite({ owner: true });
      expect((await local("/v1/mobile/pairing", "DELETE")).status).toBe(200); // An older app closed the owner's sheet.
      expect((await local("/v1/mobile")).body.invitations.map((i: any) => i.id)).toEqual([first.id, second.id]);
      const yulia = await pair(first), dasha = await pair(second, "iPhone Даши");
      const status = (await send(port, "/v1/mobile", { token: owner })).body;
      expect(status.clients).toEqual([
        { id: expect.stringMatching(/^[a-f0-9]{20}$/), label: "Mik's iPhone", role: "owner", pairedAt: expect.any(String), current: true },
        { id: expect.any(String), label: "Юля", role: "colleague", pairedAt: expect.any(String), current: false },
        { id: expect.any(String), label: "iPhone Даши", role: "colleague", pairedAt: expect.any(String), current: false },
      ]);
      const [mine, colleague] = status.clients;
      expect((await send(port, "/v1/mobile/clients/" + mine.id, { token: yulia, method: "DELETE" })).status).toBe(403);
      expect((await send(port, "/v1/mobile/clients/" + mine.id, { token: owner, method: "DELETE" })).status).toBe(409);
      expect((await send(port, "/v1/mobile", { token: owner, method: "DELETE" })).status).toBe(409);
      expect((await send(port, "/v1/mobile/clients/" + "0".repeat(20), { token: owner, method: "DELETE" })).status).toBe(404);
      const revoked = await send(port, "/v1/mobile/clients/" + colleague.id, { token: owner, method: "DELETE" });
      expect(revoked.status).toBe(200);
      expect(revoked.body.clients.map((c: any) => c.label)).toEqual(["Mik's iPhone", "iPhone Даши"]);
      expect(await send(port, "/health", { token: yulia })).toEqual({ status: 401, body: { error: "Это устройство отключено. Подключитесь заново по новой ссылке." } });
      expect((await send(port, "/health", { token: owner })).status).toBe(200);
      expect((await send(port, "/health", { token: dasha })).status).toBe(200);
      // Another owner device, such as a lost phone, can be cut off from an owner device or from the Mac itself.
      const mac = await pair(await invite({ owner: true }), "Mik's Mac");
      const other = (await local("/v1/mobile")).body.clients.at(-1);
      expect(other).toMatchObject({ label: "Mik's Mac", role: "owner", pairedAt: expect.any(String), current: false });
      expect((await send(port, "/v1/mobile/clients/" + other.id, { token: owner, method: "DELETE" })).status).toBe(200);
      expect((await send(port, "/health", { token: mac })).status).toBe(401);
      expect((await local("/v1/mobile/clients/" + mine.id, "DELETE")).body.clients.map((c: any) => c.label)).toEqual(["iPhone Даши"]);
      expect((await send(port, "/health", { token: owner })).status).toBe(401);
    } finally { await runtime.stop(); await rm(root, { recursive: true, force: true }); }
  });

  it("keeps several colleague invitations for a day until each is used or cancelled", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-invitations-")), store = new Store(":memory:");
    let offset = 0;
    const mobile = new MobileAccess(store, (_req, res) => res.end("{}"), { directory, port: 0, host: "127.0.0.1", now: () => Date.now() + offset });
    try {
      const key = (invitation: { url: string }) => new URL(invitation.url).searchParams.get("key")!;
      const owner = await mobile.invite(true), yulia = await mobile.invite(false, "Юля"), dasha = await mobile.invite(false), later = await mobile.invite(false);
      mobile.cancelInvite(); // An older app's owner sheet closed.
      expect((await call(mobile.port!, "/pair", key(owner))).status).toBe(401);
      expect(mobile.status().invitations.map(i => i.label)).toEqual(["Юля", null, null]);
      mobile.cancelInvite(dasha.id);
      expect(await call(mobile.port!, "/pair", key(dasha))).toEqual({ status: 401, body: { error: "Ссылка устарела или уже использована. Попросите новую." } });
      offset += 23 * 3_600_000;
      await mobile.close(); await mobile.restore();
      expect((await call(mobile.port!, "/pair", key(yulia))).status).toBe(200);
      offset += 2 * 3_600_000;
      expect((await call(mobile.port!, "/pair", key(later))).status).toBe(401);
      expect(mobile.status().clients).toEqual([expect.objectContaining({ label: "Юля", role: "colleague" })]);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });

  it("uses the shared device name in invitations without changing the network address", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-device-name-")), store = new Store(":memory:");
    const home = new Home(store);
    const mobile = new MobileAccess(store, (_req, res) => res.end('{}'), { directory, port: 0, host: "127.0.0.1", hostname: "server.example" });
    try {
      home.save({ ...home.state, name: "Рабочий сервер" });
      const invitation = new URL((await mobile.invite()).url);
      expect(invitation.searchParams.get("name")).toBe("Рабочий сервер");
      expect(invitation.searchParams.get("host")).toBe("server.example");
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });

  it("serves sign-in language assets over TLS before pairing without exposing private API data", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-public-languages-")), store = new Store(":memory:");
    const mobile = new MobileAccess(store, (req, res) => res.end(JSON.stringify({ path: req.url })), { directory, port: 0, host: "127.0.0.1" });
    try {
      await mobile.invite();
      for (const path of ["/localization.js", "/localizations.json"]) {
        expect((await call(mobile.port!, path)).status).toBe(200);
      }
      for (const path of ["/v1/profiles", "/v1/conversation", "/v1/mobile"]) {
        expect((await call(mobile.port!, path)).status).toBe(401);
      }
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("signs out only the requesting device without disturbing agents or another connection", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-signout-")), store = new Store(":memory:");
    const mobile = new MobileAccess(store, (_req, res) => res.end('{"ok":true}'), { directory, port: 0, host: "127.0.0.1" });
    try {
      const agent = store.createProfile({ name: "Продолжает работать" });
      const pair = async (owner: boolean) => (await call(mobile.port!, "/pair", new URL((await mobile.invite(owner)).url).searchParams.get("key")!)).body.token;
      await mobile.invite();
      const first = await pair(false), second = await pair(true);
      expect((await call(mobile.port!, "/auth/device/logout", first, "https://evil.test", undefined, "POST")).status).toBe(403);
      expect((await call(mobile.port!, "/health", first)).status).toBe(200);
      expect((await call(mobile.port!, "/auth/device/logout", first, undefined, undefined, "POST")).status).toBe(200);
      expect((await call(mobile.port!, "/health", first)).status).toBe(401);
      expect((await call(mobile.port!, "/health", second)).status).toBe(200);
      expect(mobile.status().connections).toBe(1);
      expect(store.getProfile(agent.id)).toMatchObject(agent);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("recovers a lost pairing response across restart only for the same client attempt", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-pair-retry-")), store = new Store(":memory:");
    let mobile = new MobileAccess(store, (_req, res) => res.end('{}'), { directory, port: 0, host: "127.0.0.1" });
    try {
      const key = new URL((await mobile.invite()).url).searchParams.get("key")!;
      const attempt = "12345678-1234-1234-1234-123456789012";
      const first = await call(mobile.port!, "/pair", key, undefined, attempt);
      await mobile.close();
      mobile = new MobileAccess(store, (_req, res) => res.end('{}'), { directory, port: 0, host: "127.0.0.1" });
      await mobile.restore();
      expect((await call(mobile.port!, "/pair", key, undefined, attempt)).body).toEqual(first.body);
      expect(mobile.status().connections).toBe(1);
      expect((await call(mobile.port!, "/pair", key, undefined, "22345678-1234-1234-1234-123456789012")).status).toBe(401);
      expect((await call(mobile.port!, "/pair", key)).status).toBe(401);
      mobile.revokeClient(mobile.status().clients[0]!.id);
      expect((await call(mobile.port!, "/pair", key, undefined, attempt)).status).toBe(401);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("keeps each lost pairing response recoverable until its own invitation is replaced or cancelled", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-pair-receipts-")), store = new Store(":memory:");
    const mobile = new MobileAccess(store, (_req, res) => res.end('{}'), { directory, port: 0, host: "127.0.0.1" });
    try {
      const key = (invitation: { url: string }) => new URL(invitation.url).searchParams.get("key")!;
      const attempt = (n: number) => `${n}2345678-1234-1234-1234-123456789012`;
      const yulia = key(await mobile.invite(false, "Юля")), dasha = await mobile.invite(false, "Даша"), owner = key(await mobile.invite(true));
      const first = (await call(mobile.port!, "/pair", yulia, undefined, attempt(1))).body;
      await call(mobile.port!, "/pair", key(dasha), undefined, attempt(2));
      await call(mobile.port!, "/pair", owner, undefined, attempt(3));
      await mobile.invite(false); await mobile.invite(true); mobile.cancelInvite(); mobile.cancelInvite(dasha.id);
      expect((await call(mobile.port!, "/pair", yulia, undefined, attempt(1))).body).toEqual(first);
      expect((await call(mobile.port!, "/pair", key(dasha), undefined, attempt(2))).status).toBe(401);
      expect((await call(mobile.port!, "/pair", owner, undefined, attempt(3))).status).toBe(401);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("clears a plain pairing credential once the device uses it or its window ends", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-pair-plain-")), store = new Store(":memory:");
    let offset = 0;
    const mobile = new MobileAccess(store, (_req, res) => res.end('{}'), { directory, port: 0, host: "127.0.0.1", now: () => Date.now() + offset });
    const stored = (token: string) => (store.db.prepare("SELECT value FROM settings").all() as { value: string }[]).some(row => row.value.includes(token));
    try {
      const pair = async (n: number) => {
        const key = new URL((await mobile.invite(false)).url).searchParams.get("key")!;
        return (await call(mobile.port!, "/pair", key, undefined, `${n}2345678-1234-1234-1234-123456789012`)).body.token as string;
      };
      const used = await pair(1), lost = await pair(2);
      expect([stored(used), stored(lost)]).toEqual([true, true]);
      expect((await call(mobile.port!, "/health", used)).status).toBe(200);
      expect([stored(used), stored(lost)]).toEqual([false, true]);
      offset += 301_000;
      expect((await call(mobile.port!, "/health", used)).status).toBe(200);
      expect(stored(lost)).toBe(false);
      const later = await pair(3), legacy = "f".repeat(64);
      store.setSetting("mobile.pair_receipt", JSON.stringify({ keyHash: "0".repeat(64), nonce: "x", token: legacy, expires: 0 }));
      offset += 301_000;
      await mobile.close(); await mobile.restore();
      expect([stored(later), stored(legacy)]).toEqual([false, false]);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("issues owner access only from an owner invitation and retains ordinary clients as clients", async () => {
    const directory=await mkdtemp(join(tmpdir(),"strudel-owner-"));const store=new Store(":memory:");
    const mobile=new MobileAccess(store,(_req,res,owner)=>res.end(JSON.stringify({owner})),{directory,port:0,host:"127.0.0.1"});
    try {
      const ownerInvite=new URL((await mobile.invite(true)).url);
      const owner=await call(mobile.port!,"/pair",ownerInvite.searchParams.get("key")!);
      expect((await call(mobile.port!,"/v1/mobile",owner.body.token)).body.owner).toBe(true);
      const phoneInvite=new URL((await mobile.invite()).url);
      const phone=await call(mobile.port!,"/pair",phoneInvite.searchParams.get("key")!);
      expect((await call(mobile.port!,"/v1/mobile",phone.body.token)).status).toBe(403);
      expect(store.getSetting("mobile.owners")).not.toContain(owner.body.token);
    } finally {await mobile.close();store.close();await rm(directory,{recursive:true,force:true});}
  });
  it("advertises a public endpoint while keeping the private listener separate", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-public-"));
    const store = new Store(":memory:");
    const mobile = new MobileAccess(store, (_req, res) => res.end("{}"), {directory,port:0,host:"127.0.0.1",hostname:"8.8.8.8",advertisedPort:17789});
    try {
      const invitation = new URL((await mobile.invite()).url);
      expect(invitation.searchParams.get("host")).toBe("8.8.8.8");
      expect(invitation.searchParams.get("port")).toBe("17789");
      expect(mobile.port).not.toBe(17789);
    } finally { await mobile.close(); store.close(); await rm(directory,{recursive:true,force:true}); }
  });
  it.skipIf(process.platform !== "darwin")("negotiates TLS 1.3 with Apple's client and the launch agent's system OpenSSL", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-tls-"));
    const store = new Store(":memory:");
    const mobile = new MobileAccess(store, (_req, res) => res.end("{}"), { directory, port: 0, host: "127.0.0.1" });
    vi.stubEnv("PATH", "/usr/bin:/bin");
    try {
      await mobile.invite();
      const result = await promisify(execFile)("/usr/bin/curl", ["-ksSv", "--max-time", "10", `https://127.0.0.1:${mobile.port}/health`]);
      expect(JSON.parse(result.stdout).error).toContain("Подключитесь заново");
      expect(result.stderr).toContain("SSL connection using TLSv1.3");
    } finally { vi.unstubAllEnvs(); await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
  it("requires a one-use invitation, persists only token hashes, and revokes access", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-mobile-"));
    const store = new Store(":memory:");
    const mobile = new MobileAccess(store, (_req, res) => res.end(JSON.stringify({ ok: true })), { directory, port: 0, host: "127.0.0.1", hostname: "test.local" });
    try {
      const invite = await mobile.invite();
      const url = new URL(invite.url);
      const port = Number(url.searchParams.get("port"));
      const key = url.searchParams.get("key")!;
      expect(url.searchParams.get("pin")).toMatch(/^[a-f0-9]{64}$/);
      expect((await call(port, "/health")).status).toBe(401);
      expect((await call(port, "/pair", "wrong")).status).toBe(401);
      expect((await call(port, "/pair", key, "https://evil.test")).status).toBe(403);
      const paired = await call(port, "/pair", key);
      expect(paired.status).toBe(200);
      expect((await call(port, "/pair", key)).status).toBe(401);
      expect((await call(port, "/health", paired.body.token)).body.ok).toBe(true);
      expect(store.getSetting("mobile.tokens")).not.toContain(paired.body.token);
      expect(mobile.status().connections).toBe(1);
      await mobile.close();
      await mobile.restore();
      expect((await call(mobile.port!, "/health", paired.body.token)).status).toBe(200);
      await mobile.revoke();
      expect(mobile.status().connections).toBe(0);
      const next = new URL((await mobile.invite()).url);
      expect((await call(Number(next.searchParams.get("port")), "/health", paired.body.token)).status).toBe(401);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });

  it("keeps the owner's own link for a day, replaces it with the next one and lists it beside colleague links", async () => {
    const directory = await mkdtemp(join(tmpdir(), "strudel-mobile-"));
    const store = new Store(":memory:");
    let offset = 0;
    const mobile = new MobileAccess(store, (_req, res) => res.end("{}"), { directory, port: 0, host: "127.0.0.1", hostname: "test.local", now: () => Date.now() + offset });
    try {
      const key = (invitation: { url: string }) => new URL(invitation.url).searchParams.get("key")!;
      const first = await mobile.invite(true), yulia = await mobile.invite(false, "Юля"), second = await mobile.invite(true);
      expect(Date.parse(second.expiresAt) - Date.now()).toBeGreaterThan(23 * 3_600_000);
      expect(Math.abs(Date.parse(second.expiresAt) - Date.parse(yulia.expiresAt))).toBeLessThan(60_000);
      expect((await call(mobile.port!, "/pair", key(first))).status).toBe(401);
      expect(mobile.status().invitations).toEqual([
        { id: yulia.id, label: "Юля", role: "colleague", expiresAt: yulia.expiresAt },
        { id: second.id, label: null, role: "owner", expiresAt: second.expiresAt },
      ]);
      offset += 23 * 3_600_000;
      await mobile.close(); await mobile.restore();
      expect(mobile.status().invitations.map(i => i.id)).toEqual([yulia.id, second.id]);
      mobile.cancelInvite(second.id);
      expect((await call(mobile.port!, "/pair", key(second))).status).toBe(401);
      const third = await mobile.invite(true);
      expect((await call(mobile.port!, "/pair", key(third))).status).toBe(200);
      expect(mobile.status().clients).toEqual([expect.objectContaining({ role: "owner" })]);
      const fourth = await mobile.invite(true);
      offset += 24 * 3_600_000 + 1_000;
      expect((await call(mobile.port!, "/pair", key(fourth))).status).toBe(401);
      expect(mobile.status().invitations).toEqual([]);
    } finally { await mobile.close(); store.close(); await rm(directory, { recursive: true, force: true }); }
  });
});
