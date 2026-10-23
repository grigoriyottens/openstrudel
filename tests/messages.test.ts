import { describe, expect, it, vi } from "vitest";
import { MessageService } from "../src/messages.js";
import { Store } from "../src/store.js";
import type { CodexEngine, CodexRunResult } from "../src/types.js";

class SerialProbeEngine implements CodexEngine {
  active = 0;
  maxActive = 0;
  calls: Array<{ input: string; threadId: string | null | undefined }> = [];
  private sequence = 0;

  async run(input: string, options: Parameters<CodexEngine["run"]>[1] = {}): Promise<CodexRunResult> {
    this.calls.push({ input, threadId: options.threadId });
    this.active += 1;
    this.maxActive = Math.max(this.maxActive, this.active);
    await new Promise((resolve) => setTimeout(resolve, 15));
    this.active -= 1;
    return {
      threadId: options.threadId ?? `thread-${++this.sequence}`,
      response: `Ответ: ${input}`,
      events: [],
    };
  }
}

class RecoveryProbeEngine implements CodexEngine {
  calls = 0;

  async run(input: string, options: Parameters<CodexEngine["run"]>[1] = {}): Promise<CodexRunResult> {
    this.calls += 1;
    if (options.threadId) throw new Error("thread-store conflict: already has an active writer (code -32600)");
    return { threadId: "recovered-thread", response: `Ответ: ${input}`, events: [] };
  }
}

describe("MessageService", () => {
  it("preserves a full long response and accepts more than six uploaded files",async()=>{
    const store=new Store(":memory:"),text="A".repeat(20000);
    const messages=new MessageService(store,{async run(){return{threadId:"long",response:text,events:[]};}});
    try {
      const result=await messages.handle({channel:"api",text:"read",uploads:Array.from({length:7},(_,i)=>({name:`${i}.txt`,contentBase64:Buffer.from("file").toString("base64")}))});
      expect(result.text).toBe(text);
      expect(store.listMessages(result.conversationId)[0]?.attachments).toHaveLength(7);
    }finally{await messages.close();store.close();}
  });
  it("decides a sender's access when the turn starts, and only from the adapter's sender", async () => {
    const store = new Store(":memory:"), seen: any[] = [];
    let release!: () => void;
    const messages = new MessageService(store, { run: async (_input, options) => {
      seen.push(options);
      if (seen.length === 1) await new Promise<void>(resolve => { release = resolve; });
      return { threadId: "t", response: "OK", events: [] };
    } });
    const group = (text: string, id: number, sender?: string) => ({ channel: "telegram" as const, text, externalChatId: "-100", externalId: `-100:${id}`, telegramSenderId: sender });
    try {
      store.setSetting("access.people", JSON.stringify(["77"]));
      const first = await messages.submit(group("first", 1, "77"));
      await vi.waitFor(() => expect(seen).toHaveLength(1));
      const waiting = await messages.submit(group("second", 2, "77"));
      // Removing someone also applies to their messages already waiting in the queue.
      store.setSetting("access.people", "[]");
      release(); await Promise.all([first.completion, waiting.completion]);
      await messages.handle(group("no sender", 3));
      await messages.handle({ channel: "api", text: "app", externalChatId: "home" });
      await messages.handle({ channel: "api", text: "schedule", externalChatId: "home", scheduled: true });
      expect(seen.map(o => o.access)).toEqual([true, false, false, true, true]);
    } finally { await messages.close(); store.close(); }
  });
  it("shows a readable startup timeout and keeps its receipt without replaying the request", async () => {
    const store = new Store(":memory:");
    const run = vi.fn(async () => { throw new Error("Codex не ответил на thread/start"); });
    const messages = new MessageService(store, { run });
    const request = { channel: "api" as const, externalChatId: "home", externalId: "timed-out-action", text: "Проверь соединение" };
    try {
      await expect(messages.handle(request)).rejects.toThrow("Codex не ответил вовремя");
      await expect(messages.handle(request)).rejects.toThrow("Codex не ответил вовремя");
      expect(run).toHaveBeenCalledOnce();
      const conversation = store.getOrCreateConversation({ channel: "api", externalId: "home" });
      const stored = store.listMessages(conversation.id);
      const requests = stored.filter(message => message.direction === "inbound");
      expect(requests).toHaveLength(1);
      expect(requests[0]).toMatchObject({ status: "failed" });
      expect(requests[0]!.error).not.toContain("thread/start");
      expect(stored.filter(message => message.kind === "notice")).toHaveLength(1);
    } finally { await messages.close(); store.close(); }
  });

  it("keeps a rejected turn and its thread, refreshes account status, and never replays it after sign-in", async () => {
    const store = new Store(":memory:");
    try {
      const conversation = store.getOrCreateConversation({ channel: "api", externalId: "home" });
      store.setConversationThread(conversation.id, "existing-thread");
      let authorized = false;
      const run = vi.fn(async () => {
        if (!authorized) throw new Error("workspace routing discovery unauthorized (401)");
        return { threadId: "existing-thread", response: "Готово", events: [] };
      });
      const messages = new MessageService(store, { run });
      messages.onAuthenticationError = vi.fn();
      const request = { channel: "api" as const, externalChatId: "home", externalId: "original-action", text: "Сделай действие" };
      await expect(messages.handle(request)).rejects.toThrow("Войдите в OpenAI на устройстве сотрудника");
      expect(messages.onAuthenticationError).toHaveBeenCalledOnce();
      expect(store.listMessages(conversation.id)[0]).toMatchObject({ status: "failed" });
      authorized = true;
      await expect(messages.handle(request)).rejects.toThrow("Войдите в OpenAI на устройстве сотрудника");
      expect(run).toHaveBeenCalledOnce();
      expect(store.getConversation(conversation.id)?.codexThreadId).toBe("existing-thread");
      expect((await messages.handle({ ...request, externalId: "explicit-new-action" })).text).toBe("Готово");
      expect(run).toHaveBeenCalledTimes(2);
    } finally { store.close(); }
  });

  it("serializes rapid messages per conversation and resumes the latest thread", async () => {
    const store = new Store(":memory:");
    const engine = new SerialProbeEngine();
    const messages = new MessageService(store, engine);

    const [first, second, third] = await Promise.all([
      messages.handle({ channel: "api", externalChatId: "home", text: "первое" }),
      messages.handle({ channel: "api", externalChatId: "home", text: "второе" }),
      messages.handle({ channel: "api", externalChatId: "home", text: "третье" }),
    ]);

    expect(engine.maxActive).toBe(1);
    expect(engine.calls.map((call) => call.threadId)).toEqual([null, "thread-1", "thread-1"]);
    expect([first.text, second.text, third.text]).toEqual(["Ответ: первое", "Ответ: второе", "Ответ: третье"]);
    expect(store.listMessages(first.conversationId).filter((message) => message.direction === "outbound")).toHaveLength(3);
    store.close();
  });

  it("updates an employee without changing its identity", () => {
    const store = new Store(":memory:");
    const profile = store.createProfile({ name: "Исследователь", instructions: "Собирай факты" });
    const updated = store.updateProfile(profile.id, { name: "Редактор", instructions: "Проверяй и сокращай" });
    expect(updated.id).toBe(profile.id);
    expect(store.getProfile(profile.id)).toMatchObject({ name: "Редактор", instructions: "Проверяй и сокращай" });
    store.close();
  });

  it("preserves a conflicting thread instead of silently retrying an action", async () => {
    const store = new Store(":memory:");
    const conversation = store.getOrCreateConversation({ channel: "api", externalId: "home" });
    store.setConversationThread(conversation.id, "stale-thread");
    const engine = new RecoveryProbeEngine();
    const messages = new MessageService(store, engine);

    await expect(messages.handle({ channel: "api", externalChatId: "home", text: "продолжай" })).rejects.toThrow("История сохранена");
    expect(engine.calls).toBe(1);
    expect(store.getConversation(conversation.id)?.codexThreadId).toBe("stale-thread");
    store.close();
  });
});
