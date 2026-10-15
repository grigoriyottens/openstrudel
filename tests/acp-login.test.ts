import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { GrokLogin } from "../src/acp-login.js";
import { readModelSelection, saveModelSelection } from "../src/model-settings.js";
import { Store } from "../src/store.js";

vi.setConfig({ testTimeout: 30_000 });
let root: string, store: Store;
beforeEach(() => { root = mkdtempSync(join(tmpdir(), "grok-login-")); store = new Store(":memory:"); });
afterEach(() => { store.close(); rmSync(root, { recursive: true, force: true }); });

const fixture = resolve("tests/fixtures/mock-grok.mjs");
function grok(options: { timeouts?: { start: number; login: number }; bin?: string; args?: string[] } = {}, target = store) {
  const log = join(root, "log.jsonl"), script = join(root, "scenario.json");
  writeFileSync(log, ""); writeFileSync(script, "{}");
  const login = new GrokLogin(target, root, { timeouts: options.timeouts,
    command: () => ({ bin: options.bin ?? process.execPath, args: options.args ?? [fixture], env: { MOCK_GROK_SCENARIO: script, MOCK_GROK_LOG: log } }) });
  const launches = () => readFileSync(log, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line)).filter(m => m.start).map(m => m.start);
  return { login, launches, home: () => realpathSync(join(root, ".data/providers/grok/home")) };
}

it("signs in with Grok's own device code and records only that it completed", async () => {
  const { login, launches, home } = grok();
  const start = await login.start();
  expect(start).toEqual({ type: "device", loginId: expect.any(String), verificationUrl: "https://accounts.x.ai/device?user_code=ABCD-1234", userCode: "ABCD-1234" });
  // Another owner device joins the same sign-in.
  expect(await login.start()).toEqual(start);
  expect(login.status(start.loginId)).toEqual({ loginId: start.loginId, status: "pending" });
  const [launch] = launches();
  expect(launches()).toHaveLength(1);
  expect(launch.args).toEqual(["login", "--device-auth"]);
  expect(launch.cwd).toBe(home());
  expect(launch.env).toMatchObject({ HOME: home(), GROK_HOME: home() });
  writeFileSync(join(home(), "approve"), "");
  await vi.waitFor(() => expect(login.status(start.loginId).status).toBe("completed"));
  expect(login.status(start.loginId).provider).toEqual({ id: "grok", name: "Grok", auth: "signin", connected: true, keyHint: null, keysUrl: null, usedBy: 2 });
  // The token stays in Grok's home; OpenStrudel keeps only the sign-in time. The picker reads Grok's catalog when it first needs it.
  expect(existsSync(join(home(), "auth.json"))).toBe(true);
  expect(store.getSetting("providers.grok.signedIn")).toMatch(/^\d{4}-/);
  expect(Number(store.getSetting("providers.grok.connectedAt"))).toBeGreaterThan(0);
  expect(store.getSetting("providers.grok.models")).toBeNull();
  expect(launches().map(launch => launch.args)).toEqual([["login", "--device-auth"]]);
  expect(login.status("another")).toEqual({ loginId: "another", status: "canceled" });
});

it("cancels, reports a refused sign-in, and gives up on a CLI that shows no code", async () => {
  const { login, home } = grok();
  const first = await login.start();
  expect(login.cancel(first.loginId)).toEqual({ loginId: first.loginId, status: "canceled" });
  const second = await login.start();
  expect(second.loginId).not.toBe(first.loginId);
  writeFileSync(join(home(), "deny"), "");
  await vi.waitFor(() => expect(login.status(second.loginId)).toEqual({ loginId: second.loginId, status: "failed", error: "Вход в Grok не завершён: Error: access_denied" }));
  expect(store.getSetting("providers.grok.signedIn")).toBeNull();
  const silent = grok({ args: ["-e", "setInterval(() => {}, 1000)"], timeouts: { start: 200, login: 1000 } });
  await expect(silent.login.start()).rejects.toMatchObject({ status: 502, message: "Grok не отвечает. Повторите вход позже." });
  await expect(grok({ bin: join(root, "missing-grok") }).login.start()).rejects.toMatchObject({ status: 502 });
});

it("signs out through the CLI, removes Grok's home and returns its employees to the device default", async () => {
  const { login, launches, home } = grok();
  const start = await login.start();
  writeFileSync(join(home(), "approve"), "");
  await vi.waitFor(() => expect(login.status(start.loginId).status).toBe("completed"));
  const employee = store.createProfile({ name: "Researcher" }), conversation = store.primaryConversation();
  saveModelSelection(store, { provider: "grok", model: "grok-4.7", serviceTier: "default" }, employee.id);
  store.setSetting("codex.thread.provider-grok." + conversation.id, "s-1"); store.setSetting("codex.threadOwner." + conversation.id, "provider-grok");
  expect(await login.logout()).toBe(1);
  expect(launches().at(-1).args).toEqual(["logout"]);
  expect(existsSync(join(root, ".data/providers/grok/home"))).toBe(false);
  for (const name of ["signedIn", "connectedAt", "models"]) expect(store.getSetting("providers.grok." + name)).toBeNull();
  expect(store.getSetting("codex.thread.provider-grok." + conversation.id)).toBeNull();
  expect(readModelSelection(store, employee.id)).toEqual({ provider: null, model: null, serviceTier: null });
});

it("serves the sign-in only to the owner, and never signs out while a turn runs", async () => {
  const { OpenStrudelRuntime } = await import("../src/runtime.js");
  const runtime = new OpenStrudelRuntime({ dbPath: ":memory:", startTelegram: false, apiToken: "owner", rootDirectory: root, engine: { run: async () => ({ threadId: "t", response: "OK", events: [] }) } });
  const { login, home } = grok({}, runtime.store);
  (runtime.accounts as { grok: GrokLogin }).grok = login;
  const address = await runtime.api.listen("127.0.0.1", 0);
  const call = async (path: string, method = "GET") => {
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/providers/grok/${path}`, { method, headers: { authorization: "Bearer owner" } });
    return { status: response.status, body: await response.json() };
  };
  try {
    const started = await call("login", "POST");
    expect(started).toEqual({ status: 201, body: { type: "device", loginId: expect.any(String), verificationUrl: "https://accounts.x.ai/device?user_code=ABCD-1234", userCode: "ABCD-1234" } });
    expect(await call("login/" + started.body.loginId)).toEqual({ status: 200, body: { loginId: started.body.loginId, status: "pending" } });
    expect(await call("login/" + started.body.loginId, "DELETE")).toEqual({ status: 200, body: { loginId: started.body.loginId, status: "canceled" } });
    const again = await call("login", "POST");
    writeFileSync(join(home(), "approve"), "");
    await vi.waitFor(async () => expect((await call("login/" + again.body.loginId)).body.status).toBe("completed"));
    runtime.accounts.active.set("provider-grok", 1);
    expect((await call("logout", "POST")).status).toBe(409);
    runtime.accounts.active.set("provider-grok", 0);
    expect(await call("logout", "POST")).toEqual({ status: 200, body: { ok: true, reset: 0 } });
    expect(runtime.store.getSetting("providers.grok.signedIn")).toBeNull();
  } finally { await runtime.stop(); }
});
