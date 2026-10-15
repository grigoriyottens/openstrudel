import { describe, expect, it, vi } from "vitest";
import { createSetupServer } from "../src/setup.js";
import type { AddressInfo } from "node:net";
import vm from "node:vm";

describe("server setup", () => {
  it("creates a fresh invitation when Safari reopens the private link in the same tab", async () => {
    const server = createSetupServer({ invite: vi.fn() }, "a".repeat(64));
    await new Promise<void>(done => server.listen(0, "127.0.0.1", done));
    try {
      const source = await (await fetch(`http://127.0.0.1:${(server.address() as AddressInfo).port}/setup.js`)).text();
      const nodes = new Map<string, any>(), events = new Map<string, () => void>();
      const location = { hash: "#" + "a".repeat(64), pathname: "/review/" };
      const pairing = vi.fn(async (_path: string, _options: { headers: { Authorization: string } }) => ({ ok: true, json: async () => ({ url: "openstrudel://connect?qa", expiresAt: new Date(Date.now() + 86_400_000).toISOString() }) }));
      const context = vm.createContext({
        document: { getElementById: (id: string) => { if (!nodes.has(id)) nodes.set(id, { append() {} }); return nodes.get(id); }, createElement: () => ({}) },
        location, history: { replaceState: () => { location.hash = ""; } },
        fetch: pairing, AbortSignal, setInterval() {},
        addEventListener: (name: string, callback: () => void) => events.set(name, callback),
        i18n: { language: "en" }, StrudelLocale: { languages: [["en", "English"]] },
        languageReady: Promise.resolve(), applyInterfaceLanguage() {}, t: (key: string) => key,
      });
      vm.runInContext(source, context);
      await vi.waitFor(() => expect(pairing).toHaveBeenCalledTimes(1));
      // A day-long link needs no countdown.
      await vi.waitFor(() => expect(nodes.get("expiry")?.textContent).toBe("Ссылка действует сутки и подключает одно устройство."));
      location.hash = "#" + "b".repeat(64);
      events.get("hashchange")?.();
      await vi.waitFor(() => expect(pairing).toHaveBeenCalledTimes(2));
      expect(pairing.mock.calls[1]?.[1]?.headers.Authorization).toBe("Bearer " + "b".repeat(64));
      expect(location.hash).toBe("");
    } finally { await new Promise<void>(done => server.close(() => done())); }
  });
  it("never grants a pairing invitation without the installation's private setup code", async () => {
    const mobile = { invite: vi.fn(async () => ({ url: "openstrudel://connect?test", expiresAt: new Date().toISOString() })) };
    const server = createSetupServer(mobile, "a".repeat(64));
    await new Promise<void>(done => server.listen(0, "127.0.0.1", done));
    const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    try {
      const page = await fetch(url);
      expect(page.headers.get("cache-control")).toBe("no-store");
      expect(page.headers.get("content-security-policy")).toContain("frame-ancestors 'none'");
      const html = await page.text();
      expect(html).not.toContain("a".repeat(64));
      expect(html).toContain('<html lang="en"');
      expect(html).toContain('Open OpenStrudel');
      expect(html).toContain('id="language"');
      // Relative assets must also work behind /openstrudel-review/ proxies.
      expect(html).toContain('src="localization.js"');
      expect(html).not.toContain('src="/localization.js"');
      const localization = await fetch(url + "/localization.js");
      expect(localization.status).toBe(200);
      expect(await localization.text()).toContain('document.currentScript');
      const catalogue = await (await fetch(url + "/localizations.json")).json();
      for (const language of ["en", "ru", "fr", "es", "he"]) {
        expect(catalogue["Open OpenStrudel"][language]).toBeTruthy();
      }
      expect((await fetch(url + "/pairing", { method: "POST" })).status).toBe(401);
      expect((await fetch(url + "/pairing", { method: "POST", headers: { authorization: "Bearer wrong" } })).status).toBe(401);
      expect((await fetch(url + "/pairing", { method: "POST", headers: { authorization: "Bearer " + "a".repeat(64), origin: "https://other.test" } })).status).toBe(403);
      expect(mobile.invite).not.toHaveBeenCalled();
      const paired = await fetch(url + "/pairing", { method: "POST", headers: { authorization: "Bearer " + "a".repeat(64), origin: url } });
      expect(paired.status).toBe(201);
      expect(mobile.invite).toHaveBeenCalledWith(true);
      expect((await paired.json()).url).toBe("openstrudel://connect?test");
      expect((await fetch(url + "/v1/profiles")).status).toBe(404);
    } finally { await new Promise<void>(done => server.close(() => done())); }
  });
  it("rejects a missing or guessable setup credential", () => {
    const mobile = { invite: vi.fn() };
    for (const secret of ["", "123456", "password", "a".repeat(32)]) {
      expect(() => createSetupServer(mobile, secret)).toThrow();
    }
  });
});
