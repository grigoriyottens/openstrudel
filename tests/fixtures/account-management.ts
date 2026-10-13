/** Isolated UI journey. Real account catalogue/merge/rename routes, simulated
 * OpenAI sign-in and quota responses. No provider tokens or external effects. */
import { createServer } from "node:http";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { OpenStrudelRuntime } from "../../src/runtime.js";

delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.OPENSTRUDEL_CODEX_HOME;
const directory = mkdtempSync(join(tmpdir(), "strudel-account-management-"));
const runtime = new OpenStrudelRuntime({ rootDirectory: directory, dbPath: ":memory:", startTelegram: false, engine: { async run() { throw new Error("UI fixture cannot run agents"); } } });
let offline = false, pending = "", controlURL = "", complete = false;
const identities = new Map<string, { email: string; workspace: string }>();
const services = new Set<string>();
function authorize(id: string, workspace: string, email: string) {
  identities.set(id, { email, workspace });
  const home = join(directory, ".data", ...(id === "default" ? [] : ["accounts", id]), "codex");
  mkdirSync(home, { recursive: true });
  const claims = Buffer.from(JSON.stringify({ sub: "fixture-user" })).toString("base64url");
  writeFileSync(join(home, "auth.json"), JSON.stringify({ tokens: { account_id: workspace, id_token: `header.${claims}.signature`, access_token: "fixture-only", refresh_token: "fixture-only" } }), { mode: 0o600 });
  runtime.store.setSetting(id === "default" ? "codex.auth.mode" : `codex.account.${id}.mode`, "managed");
}
function configure(id: string) {
  if (services.has(id)) return;
  services.add(id);
  const service = runtime.accounts.get(id);
  service.read = async () => ({ connected: !offline && identities.has(id), email: identities.get(id)?.email ?? null, planType: id === "default" ? "plus" : "business", managed: identities.has(id), ...(offline ? { issue: "unavailable" as const } : {}) });
  service.usage = async () => ({ checkedAt: new Date().toISOString(), ordinaryUsageAllowed: null, unavailable: offline,
    windows: offline ? [] : [{ name: "Weekly", remainingPercent: 82, usedPercent: 18, windowDurationMins: 10080, resetsAt: Math.floor(Date.now()/1000)+86400 }],
    credits: { hasCredits: true, unlimited: false, balance: "25" }, resetCredits: { availableCount: 2, nextExpiresAt: null } });
  service.startLogin = async () => { pending = id; complete = false; return { type: "device", loginId: "fixture-login", userCode: "TEST-ONLY", verificationUrl: controlURL + "/login" }; };
  service.status = async loginId => ({ loginId, status: complete ? "completed" : "pending" });
  service.cancel = async loginId => { pending = ""; return { loginId, status: "canceled" }; };
}
for (const [index,id] of ["default", ...Array.from({ length: 4 }, () => runtime.accounts.add("OpenAI").id)].entries()) {
  authorize(id, "workspace-" + index, index < 2 ? "alex@example.com" : ["", "", "studio@example.com", "research@example.com", "family@example.com"][index]!);
  configure(id);
}
const originalAdd = runtime.accounts.add.bind(runtime.accounts);
runtime.accounts.add = name => { const entry = originalAdd(name); configure(entry.id); return entry; };
runtime.store.createProfile({ name: "Writing assistant" });
const control = createServer((req,res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  res.setHeader("content-type", "application/json");
  if (url.pathname === "/complete" && pending) {
    authorize(pending, url.searchParams.get("duplicate") === "1" ? "workspace-0" : "workspace-new", url.searchParams.get("duplicate") === "1" ? "alex@example.com" : "new@example.com");
    complete = true;
  }
  if (url.pathname === "/offline") offline = url.searchParams.get("value") === "1";
  res.end(JSON.stringify({ pending: Boolean(pending), complete, offline, accounts: runtime.accounts.entries().length }));
});
await new Promise<void>(done => control.listen(0,"127.0.0.1",done));
controlURL = `http://127.0.0.1:${(control.address() as {port:number}).port}`;
const address = await runtime.api.listen("127.0.0.1",0);
writeFileSync(resolve(process.argv[2]!), JSON.stringify({ controlURL, url:`http://127.0.0.1:${address.port}`, pid:process.pid }),{mode:0o600});
console.log("Isolated account management fixture ready.");
const stop = async () => { control.close(); await runtime.stop(); rmSync(directory,{recursive:true,force:true}); process.exit(0); };
process.once("SIGTERM",stop);process.once("SIGINT",stop);
