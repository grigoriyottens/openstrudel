import { afterEach, expect, it } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { createBridge } from "../plugins/telegram-bridge/bridge.mjs";

const cleanups: (() => unknown | Promise<unknown>)[] = [];
afterEach(async () => { for (const cleanup of cleanups.splice(0).reverse()) await cleanup(); });
const config = { telegramToken: "test:token", botId: 42, botUsername: "recipes_bot", chatId: -10, mcpToken: "t".repeat(64), webhookUrl: "https://example.test/hook", webhookToken: "native-key" };
const update = (id = 1, extra = {}) => ({ update_id: id, message: { message_id: id, chat: { id: -10, title: "Recipes", type: "group" }, from: { id: 5, first_name: "Cook", is_bot: false }, text: "/ask@recipes_bot Dinner without cilantro", ...extra } });
function setup(options: { database?: string; telegramFailure?: boolean; webhookFailure?: boolean } = {}) {
  const calls: { url: string; body: any }[] = [];
  const database = options.database ?? ":memory:";
  const bridge = createBridge({ ...config, database }, { log: () => {}, fetch: async (url: string, init: RequestInit) => {
    const body = JSON.parse(String(init.body)); calls.push({ url, body });
    if (url === config.webhookUrl) {
      if (options.webhookFailure) throw new Error("connection reset after upload");
      return new Response("", { status: 200 });
    }
    if (options.telegramFailure && url.endsWith("/sendMessage")) throw new Error("connection reset after upload");
    return Response.json({ ok: true, result: { message_id: calls.length + 100 } });
  } });
  cleanups.push(() => bridge.close());
  return { bridge, calls };
}

it("delivers a native webhook run through a real MCP client and deduplicates both sides", async () => {
  const { bridge, calls } = setup();
  await bridge.acceptUpdates([update(), update()]);
  await bridge.dispatchPending();
  expect(calls.filter(c => c.url === config.webhookUrl)).toHaveLength(1);
  const request = calls.find(c => c.url === config.webhookUrl)!.body;
  expect(request).toMatchObject({ request_id: "42:1", text: "Dinner without cilantro", chat: { id: -10 } });
  const url = await bridge.listen(0, "127.0.0.1");
  expect((await fetch(url)).status).toBe(401);
  const client = new Client({ name: "pilot", version: "1" }); cleanups.push(() => client.close());
  await client.connect(new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: { authorization: `Bearer ${config.mcpToken}` } } }));
  expect((await client.listTools()).tools.map(t => t.name)).toEqual(["get_telegram_request", "reply_to_telegram", "send_to_telegram"]);
  const args = { name: "reply_to_telegram", arguments: { request_id: request.request_id, text: "Кабачковые оладьи без кинзы." } };
  expect(await client.callTool(args)).toMatchObject({ content: [{ type: "text", text: expect.stringContaining('"delivered":true') }] });
  expect(await client.callTool(args)).toMatchObject({ content: [{ type: "text", text: expect.stringContaining('"delivered":true') }] });
  expect(calls.filter(c => c.url.endsWith("/sendMessage"))).toHaveLength(1);
  expect(calls.find(c => c.url.endsWith("/sendMessage"))!.body).toMatchObject({ chat_id: -10, reply_parameters: { message_id: 1 }, text: "Кабачковые оладьи без кинзы." });
  expect(await client.callTool({ name: "reply_to_telegram", arguments: { request_id: "foreign:1", text: "no" } })).toMatchObject({ isError: true });
});

it("lets the native agent start a Telegram conversation without an incoming request, with durable send deduplication", async () => {
  const dir = mkdtempSync(join(tmpdir(), "telegram-bridge-send-")); cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
  const database = join(dir, "queue.sqlite");
  const first = setup({ database });
  const url = await first.bridge.listen(0, "127.0.0.1");
  const client = new Client({ name: "native-agent", version: "1" }); cleanups.push(() => client.close());
  await client.connect(new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: { authorization: `Bearer ${config.mcpToken}` } } }));
  const send = { name: "send_to_telegram", arguments: { delivery_key: "native-dinner-1", text: "Сегодня готовим оладьи.", chat_id: -99 } };
  expect(await client.callTool(send)).toMatchObject({ content: [{ type: "text", text: expect.stringContaining('"delivered":true') }] });
  const outbound = first.calls.filter(c => c.url.endsWith("/sendMessage"));
  expect(outbound).toHaveLength(1);
  expect(outbound[0].body).toMatchObject({ chat_id: -10, text: "Сегодня готовим оладьи." });
  expect(outbound[0].body.reply_parameters).toBeUndefined();
  expect(first.calls.some(c => c.url === config.webhookUrl)).toBe(false);
  await client.close(); await first.bridge.close();
  const second = setup({ database });
  expect(await second.bridge.send("native-dinner-1", "Сегодня готовим оладьи.")).toMatchObject({ delivered: true });
  expect(second.calls).toEqual([]);
  await expect(second.bridge.send("native-dinner-1", "Другой текст")).rejects.toThrow(/different reply/);
});

it("rejects other chats, bots, and commands for another bot, but accepts addressed messages and replies", async () => {
  const { bridge, calls } = setup();
  await bridge.acceptUpdates([
    update(1, { chat: { id: -11 } }), update(2, { from: { id: 6, is_bot: true } }),
    update(3, { text: "/ask@other_bot no" }), update(4, { text: "ordinary group conversation" }),
    update(5, { text: "@recipes_bot dinner?" }), update(6, { text: "Double it", reply_to_message: { message_id: 80, from: { id: 42, is_bot: true }, text: "Recipe for two" } }),
  ]);
  await bridge.dispatchPending();
  expect(calls.filter(c => c.url === config.webhookUrl).map(c => c.body.request_id)).toEqual(["42:5", "42:6"]);
  expect(calls.find(c => c.body.request_id === "42:6")!.body.reply_context.text).toBe("Recipe for two");
  expect(bridge.offset()).toBe(7);
});

it("persists accepted work and never repeats an ambiguous dispatch or Telegram delivery after restart", async () => {
  const dir = mkdtempSync(join(tmpdir(), "telegram-bridge-")); cleanups.push(() => rmSync(dir, { recursive: true, force: true }));
  const database = join(dir, "queue.sqlite");
  const first = setup({ database, telegramFailure: true });
  await first.bridge.acceptUpdates([update()]); await first.bridge.dispatchPending();
  await expect(first.bridge.reply("42:1", "Answer")).rejects.toThrow(/uncertain/i);
  await first.bridge.close();
  const second = setup({ database });
  await second.bridge.acceptUpdates([update()]); await second.bridge.dispatchPending();
  await expect(second.bridge.reply("42:1", "Answer")).rejects.toThrow(/uncertain/i);
  expect(second.calls).toEqual([]); expect(second.bridge.offset()).toBe(2);
  const ambiguous = setup({ webhookFailure: true });
  await ambiguous.bridge.acceptUpdates([update()]); await ambiguous.bridge.dispatchPending(); await ambiguous.bridge.dispatchPending();
  expect(ambiguous.calls.filter(c => c.url === config.webhookUrl)).toHaveLength(1);
  expect(ambiguous.bridge.health().states.dispatch_unknown).toBe(1);
});

it("splits long replies without breaking UTF-16 characters or silently truncating text", async () => {
  const { bridge, calls } = setup(); await bridge.acceptUpdates([update()]); await bridge.dispatchPending();
  const text = "а".repeat(4095) + "🍅" + "б".repeat(5000);
  await bridge.reply("42:1", text);
  const pieces = calls.filter(c => c.url.endsWith("/sendMessage")).map(c => c.body.text);
  expect(pieces.join("")).toBe(text); expect(pieces.every(p => p.length <= 4096 && !/[\uD800-\uDBFF]$/.test(p))).toBe(true);
});
