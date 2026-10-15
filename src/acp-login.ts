import { randomUUID } from "node:crypto";
import { rmSync } from "node:fs";
import { grokCommand, grokHome, launchGrok, type GrokCommand } from "./acp.js";
import { HomeError } from "./home.js";
import { safeURL } from "./interactions.js";
import { disconnectProvider, markConnected, providerConnectedAt, providerSummaries, type ProviderSummary } from "./providers.js";
import type { Store } from "./store.js";

/** The shape of a ChatGPT device sign-in. */
export type GrokLoginStart = { type: "device"; loginId: string; verificationUrl: string; userCode: string };
export type GrokLoginStatus = { loginId: string; status: "pending" | "completed" | "failed" | "canceled"; error?: string; provider?: ProviderSummary };
export interface GrokLoginOptions {
  /** Test seams: the pinned CLI and how long Grok may take to show a code and to finish. */
  command?: () => GrokCommand;
  timeouts?: { start: number; login: number };
}
type Session = { start: GrokLoginStart; status: GrokLoginStatus["status"]; error?: string; kill: () => void; timer: NodeJS.Timeout };

/** Grok signs in inside its own CLI with a device code (`grok login --device-auth`), the same from a Mac, a phone or a server.
 * The token stays in Grok's private home; OpenStrudel records only that the sign-in completed. One sign-in at a time. */
export class GrokLogin {
  private session?: Session;
  private starting?: Promise<GrokLoginStart>;
  constructor(private readonly store: Store, private readonly root: string, private readonly options: GrokLoginOptions = {}) {}

  /** A second owner device joins the sign-in in progress. */
  start(): Promise<GrokLoginStart> {
    if (this.session?.status === "pending") return Promise.resolve(this.session.start);
    return this.starting ??= this.begin().finally(() => { this.starting = undefined; });
  }

  status(loginId: string): GrokLoginStatus {
    const session = this.session;
    if (session?.start.loginId !== loginId) return { loginId, status: "canceled" };
    return { loginId, status: session.status, ...session.error ? { error: session.error } : {},
      ...session.status === "completed" ? { provider: providerSummaries(this.store).find(p => p.id === "grok") } : {} };
  }

  cancel(loginId: string): GrokLoginStatus {
    if (this.session?.start.loginId === loginId) this.finish("canceled");
    return this.status(loginId);
  }

  /** Grok signs out first; its home, with every local trace of the token, goes once the CLI stopped writing there. */
  async logout(): Promise<number> {
    this.close();
    const home = grokHome(this.root), grok = launchGrok(this.command(), ["logout"], home, home);
    grok.child.stdin!.end(); grok.child.stdout!.resume();
    const timer = setTimeout(grok.kill, 15_000);
    await grok.closed;
    clearTimeout(timer);
    rmSync(home, { recursive: true, force: true });
    return disconnectProvider(this.store, "grok");
  }

  close(): void { if (this.session?.status === "pending") this.finish("canceled"); }

  private command() { return (this.options.command ?? grokCommand)(); }

  private begin(): Promise<GrokLoginStart> {
    const home = grokHome(this.root), grok = launchGrok(this.command(), ["login", "--device-auth"], home, home), loginId = randomUUID();
    // A relayed request waits 30 s for this device's answer.
    const { start = 25_000, login = 15 * 60_000 } = this.options.timeouts ?? {};
    grok.child.stdin!.end();
    return new Promise((resolve, reject) => {
      let output = "", shown: Session | undefined;
      const said = () => output.split("\n").map(line => line.trim()).filter(Boolean).pop();
      const fail = (message: string) => { clearTimeout(timer); grok.kill(); reject(new HomeError(message, 502)); };
      const timer = setTimeout(() => fail("Grok не отвечает. Повторите вход позже."), start);
      // Grok 1.0.52 prints the page, then "Then enter this code:" or "Confirm this code in your browser:" with the code.
      const read = (chunk: Buffer) => {
        output = (output + chunk.toString("utf8")).replace(/\x1b\[[0-9;]*m/g, "").slice(-8192);
        const url = /https:\/\/\S+/.exec(output)?.[0], code = /(?:enter this code|confirm this code in your browser):\s*([A-Z0-9-]+)/i.exec(output)?.[1];
        if (shown || !url || !code) return;
        clearTimeout(timer);
        try {
          shown = this.session = { start: { type: "device", loginId, verificationUrl: safeURL(url), userCode: code }, status: "pending", kill: grok.kill,
            timer: setTimeout(() => this.finish("failed", "Код входа в Grok истёк. Начните вход снова."), login) };
          shown.timer.unref();
          resolve(shown.start);
        } catch (error) { fail(`Вход в Grok не завершён: ${error instanceof Error ? error.message : String(error)}`); }
      };
      grok.child.stdout!.on("data", read); grok.child.stderr!.on("data", read);
      grok.child.once("error", error => fail(`Вход в Grok не завершён: ${error.message}`));
      grok.child.once("close", code => {
        if (!shown) return fail(said() ? `Вход в Grok не завершён: ${said()}` : "Grok не отвечает. Повторите вход позже.");
        if (shown.status !== "pending") return;
        if (code !== 0) return this.finish("failed", `Вход в Grok не завершён: ${said() ?? code}`);
        // Grok holds a valid token now; every turn starts its own process, and the picker reads its catalog when it needs it.
        if (!providerConnectedAt(this.store, "grok")) markConnected(this.store, "grok");
        this.store.setSetting("providers.grok.signedIn", new Date().toISOString());
        this.finish("completed");
      });
    });
  }

  private finish(status: "completed" | "failed" | "canceled", error?: string) {
    const session = this.session;
    if (session?.status !== "pending") return;
    Object.assign(session, { status, error });
    clearTimeout(session.timer);
    session.kill();
  }
}
