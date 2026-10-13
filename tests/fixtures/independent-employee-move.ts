/** Two disposable, independent homes for native transfer acceptance. */
import { createServer } from "node:http";
import { mkdtemp, rm, writeFile, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { OpenStrudelRuntime } from "../../src/runtime.js";
import { MockCodexEngine } from "../../src/codex.js";
import { agentTransfer } from "../../src/agent-move.js";

const output = resolve(process.argv[2]!);
const directory = await mkdtemp(join(tmpdir(), "strudel-independent-ui-"));
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.OPENSTRUDEL_SETUP_CODE;
let failRelease = false;
const nodes = await Promise.all(["Ноутбук QA", "Mac mini QA"].map(async (name, index) => {
  const root = join(directory, String(index));
  const runtime = new OpenStrudelRuntime({ rootDirectory: root, dbPath: join(root, "home.sqlite"), engine: new MockCodexEngine(), startTelegram: false, mobilePort: 0 });
  runtime.api.home.save({ ...runtime.api.home.state, name });
  runtime.account.read = async () => ({ connected: true, email: "preview@example.com", managed: true, planType: "plus" });
  Object.assign((runtime.api.mobile as any).options, { port: 0, host: "127.0.0.1", hostname: "127.0.0.1", directory: join(root, "mobile") });
  const moves = (runtime.api as any).agentMoves;
  const handle = moves.handle.bind(moves);
  moves.handle = async (action: string, input: unknown) => {
    const result = await handle(action, input);
    await appendFile(output + ".steps.jsonl", JSON.stringify({ device: index, action, time: Date.now() }) + "\n", { mode: 0o600 });
    if (action === "release" && failRelease) { failRelease = false; throw new Error("Тестовое прерывание после сохранения этапа. Можно продолжить перенос."); }
    return result;
  };
  const address = await runtime.api.listen("127.0.0.1", 0);
  return { runtime, name, url: `http://127.0.0.1:${address.port}` };
}));
const source = nodes[0]!.runtime;
const employee = source.store.createProfile({ name: "Редактор переезда", instructions: "Пиши понятно. Сохрани синюю тетрадь.", model: "gpt-6.1-sol" });
const conversation = source.store.profileConversation(employee.id);
source.store.importHistory(conversation.id, [
  { sourceId: "move-ui-1", author: "Вы", date: new Date().toISOString(), direction: "inbound", text: "Запомни: тетрадь синяя." },
  { sourceId: "move-ui-2", author: "Редактор", date: new Date().toISOString(), direction: "outbound", text: "Сохранил: тетрадь синяя." },
]);
const file = source.messages.files.put(conversation.id, source.messages.contextFor(conversation.id), { name: "notebook.txt", contentBase64: Buffer.from("Blue notebook").toString("base64") });
source.scheduler.save({ conversationId: conversation.id, name: "Сверить тетрадь", prompt: "Проверить синюю тетрадь", cron: "0 9 1 1 *", timezone: "UTC" });

const control = createServer(async (req, res) => {
  res.setHeader("content-type", "application/json");
  const path = new URL(req.url ?? "/", "http://localhost");
  if (path.pathname === "/invite") {
    const index = Number(path.searchParams.get("device") ?? 1);
    const node = nodes[index];
    if (!node) { res.writeHead(404).end(); return; }
    const invitation = await node.runtime.api.mobile.invite(true);
    const url = new URL(invitation.url); url.searchParams.set("name", node.name);
    res.end(JSON.stringify({ ...invitation, url: url.toString() })); return;
  }
  if (path.pathname === "/fail-release") failRelease = true;
  res.end(JSON.stringify(nodes.map(({ runtime, name }) => ({ name, homeId: runtime.api.home.state.id,
    employee: runtime.store.getProfile(employee.id), transfer: agentTransfer(runtime.store, employee.id),
    messages: runtime.store.getConversation(conversation.id) ? runtime.store.listMessages(conversation.id).length : 0,
    file: !!runtime.messages.files.get(file.id), schedules: runtime.scheduler.list(conversation.id).length,
  }))));
});
await new Promise<void>(done => control.listen(0, "127.0.0.1", done));
await writeFile(output, JSON.stringify({ pid: process.pid, controlURL: `http://127.0.0.1:${(control.address() as { port: number }).port}`, sourceURL: nodes[0]!.url, targetURL: nodes[1]!.url, employee: employee.id }), { mode: 0o600 });
console.log("Two independent UI homes ready.");
const stop = async () => { control.close(); await Promise.all(nodes.map(n => n.runtime.stop())); await rm(directory, { recursive: true, force: true }); process.exit(0); };
process.once("SIGTERM", stop); process.once("SIGINT", stop);
