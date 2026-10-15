/** Synthetic UI acceptance only. No scheduler, Telegram, real OAuth or provider calls. */
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createServer } from "node:http";
import { OpenStrudelRuntime } from "../../src/runtime.js";
import { MockCodexEngine } from "../../src/codex.js";

const root = await mkdtemp(join(tmpdir(), "strudel-primary-ui-"));
async function make(name: string) {
  const directory = join(root, name); await mkdir(directory);
  const runtime = new OpenStrudelRuntime({ dbPath: join(directory, "home.db"), rootDirectory: directory, apiToken: process.env.OPENSTRUDEL_TIMELINE_FIXTURE === "1" ? undefined : "synthetic-acceptance-owner", engine: new MockCodexEngine(), startTelegram: false, mobilePort: 0 });
  runtime.api.home.save({ ...runtime.api.home.state, name });
  for (const entry of [runtime.accounts.entries()[0]!, runtime.accounts.add("Рабочий")]) {
    const service = runtime.accounts.get(entry.id);
    service.read = async () => ({ connected: true, email: entry.id === "default" ? "personal@example.invalid" : "work@example.invalid", managed: true, planType: "plus" });
    service.usage = async () => ({ checkedAt: new Date().toISOString(), ordinaryUsageAllowed: true, windows: [{ name: "5 часов", usedPercent: 26, remainingPercent: 74, windowDurationMins: 300, resetsAt: Math.floor(Date.now() / 1000) + 9000 }] });
  }
  const address = await runtime.api.listen("127.0.0.1", 0), url = "http://127.0.0.1:" + address.port;
  runtime.api.home.setEndpoint({ url });
  return { runtime, url };
}
const main = await make("Главное"), worker = await make("Рабочий Mac");
const profile = worker.runtime.store.createProfile({ name: "Редактор", instructions: "Пиши коротко и понятно." });
const chat = worker.runtime.store.profileConversation(profile.id);
worker.runtime.store.addMessage({ conversationId: chat.id, channel: "api", direction: "outbound", text: "Это тестовая история. Агент работает на дополнительном Mac." });
if (process.env.OPENSTRUDEL_TIMELINE_FIXTURE === "1") {
  // Synthetic Telegram boundary: never contact Telegram or run a receiver.
  (worker.runtime.telegram as any).token = "999:synthetic-ui-only";
  let sent = 100;
  (worker.runtime.telegram as any).call = async () => ({ message_id: ++sent });
  const store = worker.runtime.store;
  for (const [index, title] of ["WAI Core Team · тест", "Редакция · тест"].entries()) {
    const id = "-100900000000" + index;
    store.linkTelegramChat({ chatId: id, title, allowedSenders: ["7"] });
    const group = store.bindTelegramChat(id, profile.id);
    const accepted = store.addMessage({ conversationId: group.conversationId!, channel: "telegram", direction: "inbound",
      text: index ? "Подготовь короткий текст для сайта." : "Собери решения встречи и следующий шаг.", externalId: id + ":11", author: index ? "Юля" : "Гриша" });
    store.setMessageStatus(accepted.id, "completed");
    const reply = store.addMessage({ conversationId: accepted.conversationId, channel: "telegram", direction: "outbound", replyToId: accepted.id,
      text: index ? "Черновик готов. Уточните дату публикации." : "Решили подготовить общий документ. Следующий шаг — согласовать ответственных." });
    store.db.prepare("INSERT INTO telegram_outbox(key,chat_id,payload,status,message_id,error) VALUES(?,?,?,?,?,?)")
      .run(id + ":reply:" + reply.id + ":0", id, "{}", index ? "unknown" : "delivered", index ? null : "12", index ? "Lost confirmation" : null);
    const chatter = store.addMessage({ conversationId: accepted.conversationId, channel: "telegram", direction: "inbound", text: "Посторонняя беседа — не показывать", externalId: id + ":13" });
    store.db.prepare("UPDATE messages SET context_only=1 WHERE id=?").run(chatter.id);
  }
  const privateMessage = store.addMessage({ conversationId: chat.id, channel: "api", direction: "inbound", text: "Это личное обращение из приложения." });
  store.setMessageStatus(privateMessage.id, "completed");
}
await worker.runtime.api.homeLink.join(main.runtime.api.home.invite({ url: main.url }));
const controller = createServer(async (req, res) => {
  if (req.url === "/invitation") { res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify(await main.runtime.api.mobile.invite(true))); return; }
  if (req.url === "/offline") { await worker.runtime.api.homeLink.stop(); res.end("offline"); return; }
  if (req.url === "/online") { worker.runtime.api.homeLink.start(); res.end("online"); return; }
  res.writeHead(404).end();
});
await new Promise<void>(done => controller.listen(0, "127.0.0.1", done));
const invitation = main.runtime.api.web.invite(true);
const output = resolve(process.argv[2] ?? "/tmp/openstrudel-primary-ui.json");
await writeFile(output, JSON.stringify({ url: main.url, workerURL: worker.url, browser: main.url + "/#invite=" + invitation.key, controller: "http://127.0.0.1:" + (controller.address() as any).port, profileId: profile.id, root }), { mode: 0o600 });
console.log("Synthetic primary Home fixture ready.");
const stop = async () => { controller.close(); await worker.runtime.stop(); await main.runtime.stop(); await rm(root, { recursive: true, force: true }); process.exit(0); };
process.once("SIGTERM", stop); process.once("SIGINT", stop);
