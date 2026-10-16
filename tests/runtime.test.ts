import { describe, expect, it, vi } from "vitest";
import {mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import { MockCodexEngine } from "../src/codex.js";
import { OpenStrudelRuntime } from "../src/runtime.js";

describe("OpenStrudel runtime", () => {
  it.each(["app-server-scopes-3","app-server-scopes-5-telegram"])("renews a %s execution thread for native bot tools while retaining its chat and previous IDs",async version=>{
    const root=mkdtempSync(join(tmpdir(),"strudel-bot-upgrade-"));
    const runtime=new OpenStrudelRuntime({dbPath:join(root,"home.sqlite"),rootDirectory:root,engine:new MockCodexEngine(),startTelegram:false});
    const listen=runtime.api.listen.bind(runtime.api);
    vi.spyOn(runtime.api,"listen").mockImplementation(()=>listen("127.0.0.1",0));
    const conversation=runtime.store.primaryConversation();
    runtime.store.setConversationThread(conversation.id,"existing-codex-thread");
    runtime.store.setSetting("codex.transport.version",version);
    runtime.store.setSetting("codex.previous_threads","earlier migration");
    runtime.store.setSetting("codex.previous_threads.app-server-scopes-5-telegram","older Telegram catalog");
    runtime.store.setSetting("codex.thread.default."+conversation.id,"account-cached-thread");
    runtime.store.addMessage({conversationId:conversation.id,channel:"api",direction:"inbound",text:"Remember this decision"});
    try {
      await runtime.start();
      expect(runtime.store.getConversation(conversation.id)?.codexThreadId).toBeNull();
      expect(runtime.store.listMessages(conversation.id)[0]?.text).toBe("Remember this decision");
      expect(runtime.store.getSetting("codex.previous_threads")).toBe("earlier migration");
      expect(runtime.store.getSetting("codex.previous_threads.app-server-scopes-5-telegram")).toBe("older Telegram catalog");
      expect(JSON.parse(runtime.store.getSetting("codex.previous_threads.app-server-scopes-6-telegram-delivery")!)).toEqual([{conversationId:conversation.id,threadId:"existing-codex-thread"}]);
      expect(runtime.store.getSetting("codex.thread.default."+conversation.id)).toBeNull();
      expect(JSON.parse(runtime.store.getSetting("codex.previous_thread_routes.app-server-scopes-6-telegram-delivery")!)).toEqual([{key:"codex.thread.default."+conversation.id,value:"account-cached-thread"}]);
      expect(runtime.messages.telegram).toBe(runtime.telegram);
    } finally {await runtime.stop();rmSync(root,{recursive:true,force:true});}
  });
  it("does not renew an execution thread already using the current tool catalog",async()=>{
    const root=mkdtempSync(join(tmpdir(),"strudel-bot-current-"));
    const runtime=new OpenStrudelRuntime({dbPath:join(root,"home.sqlite"),rootDirectory:root,engine:new MockCodexEngine(),startTelegram:false});
    const listen=runtime.api.listen.bind(runtime.api);vi.spyOn(runtime.api,"listen").mockImplementation(()=>listen("127.0.0.1",0));
    const conversation=runtime.store.primaryConversation();
    runtime.store.setConversationThread(conversation.id,"current-thread");
    runtime.store.setSetting("codex.thread.default."+conversation.id,"current-account-thread");
    runtime.store.setSetting("codex.transport.version","app-server-scopes-6-telegram-delivery");
    try {
      await runtime.start();
      expect(runtime.store.getConversation(conversation.id)?.codexThreadId).toBe("current-thread");
      expect(runtime.store.getSetting("codex.thread.default."+conversation.id)).toBe("current-account-thread");
    } finally {await runtime.stop();rmSync(root,{recursive:true,force:true});}
  });
  it("keeps addressed employee requests in the main conversation and permits a direct employee chat", async () => {
    const runtime = new OpenStrudelRuntime({ dbPath: ":memory:", engine: new MockCodexEngine(), startTelegram: false });
    const chat = await runtime.messages.handle({ channel: "api", externalChatId: "home", text: "Привет" });
    expect(chat.text).toContain("Принял задачу");
    const profile = runtime.store.createProfile({ name: "Исследователь", instructions: "Ищи факты и новости" });
    const routed = await runtime.messages.handle({ channel: "api", externalChatId: "home", text: "@Исследователь собери факты" });
    expect(routed.profileId).toBeUndefined();
    expect(routed.conversationId).toBe(chat.conversationId);
    const direct = await runtime.messages.handle({ channel: "api", externalChatId: "home", profile: profile.id, text: "Собери факты" });
    expect(direct.profileId).toBe(profile.id);
    expect(direct.conversationId).not.toBe(chat.conversationId);
    const help = await runtime.messages.handle({ channel: "api", externalChatId: "home", text: "/help" });
    expect(help.text).toContain("обычными словами");
    await runtime.stop();
  });

  it("exposes only the small chat, employee and Telegram surface", async () => {
    const runtime = new OpenStrudelRuntime({ dbPath: ":memory:", engine: new MockCodexEngine(), startTelegram: false });
    const address = await runtime.api.listen("127.0.0.1", 0);
    const health = await fetch(`http://127.0.0.1:${address.port}/health`);
    expect(health.status).toBe(200);
    expect((await health.json()) as { ok: boolean }).toMatchObject({ ok: true });
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/messages`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: "hello" }) });
    expect(response.status).toBe(200);
    expect((await response.json()) as { text: string }).toHaveProperty("text");
    const profiles = await fetch(`http://127.0.0.1:${address.port}/v1/profiles`);
    expect(profiles.status).toBe(200);
    expect((await fetch(`http://127.0.0.1:${address.port}/v1/devices`)).status).toBe(200);
    for (const path of ["/v1/tasks", "/v1/search"]) {
      expect((await fetch(`http://127.0.0.1:${address.port}${path}`)).status).toBe(404);
    }
    await runtime.stop();
  });
});
