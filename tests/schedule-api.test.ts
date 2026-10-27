import { expect, it } from "vitest";
import { OpenStrudelRuntime } from "../src/runtime.js";

it("lets a colleague schedule only into their own chat, never into another Telegram chat", async () => {
  const runtime = new OpenStrudelRuntime({ dbPath: ":memory:", startTelegram: false, apiToken: "owner", engine: { run: async () => ({ threadId: "t", response: "OK", events: [] }) } });
  const address = await runtime.api.listen("127.0.0.1", 0);
  const call = (path: string, body: unknown, headers: Record<string, string> = { authorization: "Bearer owner" }) =>
    fetch(`http://127.0.0.1:${address.port}${path}`, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });
  try {
    const own = runtime.store.primaryConversation();
    const other = runtime.store.createProfile({ name: "Team" });
    const group = runtime.store.linkTelegramChat({ chatId: "-100", title: "Owner group", allowedSenders: ["7"] });
    runtime.store.bindTelegramChat(group.chatId, other.id);
    const login = await call("/auth/session", { key: runtime.api.web.invite(false).key }, {});
    const { csrf } = await login.json();
    const member = { cookie: login.headers.get("set-cookie")!.split(";")[0]!, "x-openstrudel-csrf": csrf };
    const schedule = { name: "Digest", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow" };
    expect((await call(`/v1/conversations/${own.id}/schedules`, { ...schedule, delivery: "telegram", telegramChatId: "-100" }, member)).status).toBe(403);
    expect((await call(`/v1/conversations/${own.id}/schedules`, schedule, member)).status).toBe(201);
    expect((await call(`/v1/conversations/${own.id}/schedules`, { ...schedule, delivery: "telegram", telegramChatId: "-100" })).status).toBe(201);
  } finally { await runtime.stop(); }
});

it("keeps a colleague's save_schedule in their own chat outside groups too", async () => {
  const { Store } = await import("../src/store.js");
  const { MessageService } = await import("../src/messages.js");
  const { Scheduler } = await import("../src/scheduler.js");
  const { employeeTools } = await import("../src/personality.js");
  const store = new Store(":memory:");
  const messages = new MessageService(store, { run: async () => ({ threadId: "t", response: "OK", events: [] }) });
  const scheduler = new Scheduler(store, messages);
  try {
    const own = store.primaryConversation(), other = store.createProfile({ name: "Team" });
    const group = store.linkTelegramChat({ chatId: "-100", title: "Owner group", allowedSenders: ["7"] });
    store.bindTelegramChat(group.chatId, other.id);
    const tools = (byOwner: boolean) => employeeTools(store, messages as any, messages.interactions, { profile: null, conversationId: own.id, messageId: "m", channel: "api", scheduler, scope: "personal", byOwner } as any);
    const request = { id: null, name: "Digest", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow", telegramChatId: "-100" };
    await expect(tools(false).call("save_schedule", request)).rejects.toThrow();
    await expect(tools(true).call("save_schedule", request)).resolves.toMatchObject({ telegramChatId: "-100" });
  } finally { await messages.close(); store.close(); }
});
