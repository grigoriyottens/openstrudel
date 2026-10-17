import { afterEach, describe, expect, it, vi } from "vitest";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";
import { Scheduler } from "../src/scheduler.js";
import { scheduleTiming } from "../src/schedule-timing.js";

const stores: Store[] = [];
afterEach(() => { for (const store of stores.splice(0)) store.close(); });
function setup() {
  const store = new Store(":memory:"); stores.push(store);
  let calls = 0;
  const messages = new MessageService(store, { async run() { calls++; return { threadId: "scheduled", response: "Digest", events: [] }; } });
  const scheduler = new Scheduler(store, messages);
  return { store, messages, scheduler, calls: () => calls };
}
describe("durable one-time reminders", () => {
  const now = new Date("2030-01-15T06:00:00Z");
  const request = { name: "Reminder", prompt: "Send the requested reminder here", cron: "@once 2030-01-15T09:01:00+03:00", timezone: "Europe/Moscow" };

  it("wakes at a newly saved deadline without waiting for the periodic recovery check", async () => {
    vi.useFakeTimers(); vi.setSystemTime(now);
    const { store, scheduler, calls } = setup(), c = store.primaryConversation();
    try {
      scheduler.start();
      await vi.advanceTimersByTimeAsync(0);
      scheduler.save({...request,conversationId:c.id,cron:"@once 2030-01-15T06:00:03Z"});
      await vi.advanceTimersByTimeAsync(2999); expect(calls()).toBe(0);
      await vi.advanceTimersByTimeAsync(1); await scheduler.idle(); expect(calls()).toBe(1);
      await vi.advanceTimersByTimeAsync(60_000); expect(calls()).toBe(1);
    } finally { scheduler.stop(); vi.useRealTimers(); }
  });

  it("keeps the exact instant, runs once after a restart and never repeats next year", async () => {
    const { store, messages, scheduler, calls } = setup(), c = store.primaryConversation();
    const saved = scheduler.save({ ...request, conversationId: c.id }, now);
    expect(saved.nextRunAt).toBe("2030-01-15T06:01:00.000Z");
    await scheduler.tick(new Date("2030-01-15T06:00:59Z")); await scheduler.idle();
    expect(calls()).toBe(0);
    const reopened = new Scheduler(store, messages); reopened.recover();
    await reopened.tick(new Date("2030-01-15T06:01:04Z")); await reopened.idle();
    expect(calls()).toBe(1);
    expect(reopened.list(c.id)[0]).toMatchObject({ enabled: false, lastRunStatus: "completed" });
    expect(reopened.runs(c.id)[0]).toMatchObject({ status: "completed", scheduledFor: saved.nextRunAt });
    await reopened.tick(new Date("2031-01-15T06:01:04Z")); await reopened.idle();
    expect(calls()).toBe(1);
  });

  it("catches up a missed one-time request without changing its original timestamp", async () => {
    const { store, scheduler, calls } = setup(), c = store.primaryConversation();
    scheduler.save({ ...request, conversationId: c.id }, now);
    await scheduler.tick(new Date("2030-01-16T08:00:00Z")); await scheduler.idle();
    await scheduler.tick(new Date("2030-01-16T08:00:15Z")); await scheduler.idle();
    expect(calls()).toBe(1);
    expect(scheduler.runs(c.id)[0]?.scheduledFor).toBe("2030-01-15T06:01:00.000Z");
  });

  it("does not retry an uncertain one-time delivery after recovery", async () => {
    const { store, scheduler, calls } = setup(), c = store.primaryConversation();
    store.linkTelegramChat({chatId:"123",title:"Test",allowedSenders:["123"]});
    let sends = 0;
    scheduler.deliver = async () => { sends++; throw new Error("Reply lost after send"); };
    scheduler.save({ ...request, conversationId: c.id, delivery: "telegram", telegramChatId: "123" }, now);
    await scheduler.tick(new Date("2030-01-15T06:01:04Z")); await scheduler.idle();
    scheduler.recover();
    await scheduler.tick(new Date("2030-01-15T06:02:00Z")); await scheduler.idle();
    expect(calls()).toBe(1); expect(sends).toBe(1);
    expect(scheduler.list(c.id)[0]).toMatchObject({enabled:false,lastRunStatus:"uncertain"});
  });

  it("disarms a claimed reminder on crash recovery without executing it again", async () => {
    const { store, scheduler, calls } = setup(), c = store.primaryConversation();
    const saved = scheduler.save({ ...request, conversationId: c.id }, now);
    store.db.prepare("INSERT INTO schedule_runs(id,schedule_id,conversation_id,scheduled_for,status,created_at) VALUES(?,?,?,?,?,?)")
      .run("interrupted-once", saved.id, c.id, saved.nextRunAt, "running", saved.nextRunAt);
    scheduler.recover();
    await scheduler.tick(new Date("2030-01-15T06:02:00Z")); await scheduler.idle();
    expect(calls()).toBe(0);
    expect(scheduler.list(c.id)[0]).toMatchObject({enabled:false,lastRunStatus:"uncertain"});
  });

  it("allows pause before delivery and rejects re-enabling an elapsed reminder", async () => {
    const { store, scheduler, calls } = setup(), c = store.primaryConversation();
    const saved = scheduler.save({ ...request, conversationId: c.id }, now);
    scheduler.remove(saved.id, c.id);
    const later = new Date("2030-01-15T06:02:00Z");
    await scheduler.tick(later); await scheduler.idle();
    expect(calls()).toBe(0);
    expect(() => scheduler.save({...saved, enabled:true}, later)).toThrow("Время напоминания уже прошло");
    expect(() => scheduler.save({...saved, enabled:false}, later)).not.toThrow();
    expect(() => scheduler.save({...saved, enabled:true, cron:"@once 2030-01-15T09:03:00+03:00"}, later)).not.toThrow();
  });

  it.each([
    "@once 2030-01-15T09:00:00", "@once 2030-02-30T09:00:00Z",
    "@once 2030-13-01T09:00:00Z", "@once 2030-01-15T25:00:00Z", "@once tomorrow",
  ])("rejects an ambiguous or invalid date: %s", cron => {
    expect(() => scheduleTiming(cron, "Europe/Moscow", now)).toThrow();
  });

  it("preserves explicit DST offsets rather than inferring server local time", () => {
    expect(scheduleTiming("@once 2030-11-03T01:30:00-04:00", "America/New_York", now).nextRunAt).toBe("2030-11-03T05:30:00.000Z");
    expect(scheduleTiming("@once 2030-11-03T01:30:00-05:00", "America/New_York", now).nextRunAt).toBe("2030-11-03T06:30:00.000Z");
  });
});
describe("durable cron", () => {
  it("keeps the failed receipt after lost authorization and uses recovery only for later runs", async () => {
    const store = new Store(":memory:"); stores.push(store);
    let authorized = false, calls = 0;
    const messages = new MessageService(store, { async run() {
      calls++;
      if (!authorized) throw new Error("refresh_token_expired");
      return { threadId: "restored", response: "Digest", events: [] };
    } });
    const scheduler = new Scheduler(store, messages), c = store.primaryConversation();
    scheduler.save({ conversationId: c.id, name: "Daily", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow" }, new Date("2026-09-26T10:00:00Z"));
    await scheduler.tick(new Date("2026-09-27T03:00:01Z")); await scheduler.idle();
    expect(scheduler.runs(c.id)[0]).toMatchObject({ status: "failed", error: expect.stringContaining("Войдите в OpenAI на устройстве сотрудника") });
    authorized = true;
    scheduler.recover();
    await scheduler.tick(new Date("2026-09-27T04:00:01Z")); await scheduler.idle();
    expect(calls).toBe(1);
    await scheduler.tick(new Date("2026-09-28T03:00:01Z")); await scheduler.idle();
    expect(calls).toBe(2);
    expect(scheduler.runs(c.id).map(r => r.status)).toEqual(["completed", "failed"]);
    expect(scheduler.list(c.id)).toHaveLength(1);
  });

  it("does not publish a second edition when Telegram delivery is ambiguous", async () => {
    const { store, scheduler, calls } = setup();
    const c = store.primaryConversation();
    store.linkTelegramChat({chatId:"123",title:"Test",allowedSenders:["123"]});
    scheduler.deliver = async () => { throw new Error("Connection lost after sending"); };
    const before = new Date("2026-09-26T10:00:00Z");
    const primary = scheduler.save({conversationId:c.id,name:"Morning",prompt:"Digest",cron:"0 6 * * *",timezone:"Europe/Moscow",delivery:"telegram",telegramChatId:"123"},before);
    scheduler.save({conversationId:c.id,name:"Backstop",prompt:"Digest",cron:"0 9 * * *",timezone:"Europe/Moscow",backupOf:primary.id},before);
    await scheduler.tick(new Date("2026-09-27T03:00:01Z")); await scheduler.idle();
    expect(scheduler.runs(c.id)[0]?.status).toBe("uncertain");
    await scheduler.tick(new Date("2026-09-27T06:00:01Z")); await scheduler.idle();
    expect(calls()).toBe(1);
    expect(scheduler.runs(c.id)[0]?.status).toBe("skipped");
  });
  it("runs a backstop only when the primary edition did not complete that day", async () => {
    const { store, scheduler, calls } = setup();
    const c = store.primaryConversation();
    const before = new Date("2026-09-26T10:00:00Z");
    const primary = scheduler.save({conversationId:c.id,name:"Morning",prompt:"Digest",cron:"0 6 * * *",timezone:"Europe/Moscow"},before);
    scheduler.save({conversationId:c.id,name:"Backstop",prompt:"Digest",cron:"0 9 * * *",timezone:"Europe/Moscow",backupOf:primary.id},before);
    await scheduler.tick(new Date("2026-09-27T03:00:01Z")); await scheduler.idle();
    await scheduler.tick(new Date("2026-09-27T06:00:01Z")); await scheduler.idle();
    expect(calls()).toBe(1);
    expect(scheduler.runs(c.id)[0]?.status).toBe("skipped");
    store.db.prepare("UPDATE schedule_runs SET status='failed' WHERE schedule_id=?").run(primary.id);
    store.db.prepare("UPDATE schedules SET enabled=0 WHERE id=?").run(primary.id);
    await scheduler.tick(new Date("2026-09-28T06:00:01Z")); await scheduler.idle();
    expect(calls()).toBe(2);
  });

  it("keeps an empty recurring check silent in the chat and Telegram", async () => {
    const store = new Store(":memory:"); stores.push(store);
    const messages = new MessageService(store,{async run(){return {threadId:"quiet",response:"NO_REPLY",events:[]};}});
    const scheduler = new Scheduler(store,messages);
    const c = store.primaryConversation();
    store.linkTelegramChat({chatId:"123",title:"Test",allowedSenders:["123"]});
    const sent:string[]=[]; scheduler.deliver=async(_,text)=>{sent.push(text);};
    scheduler.save({conversationId:c.id,name:"Dates",prompt:"Only today",cron:"0 9 * * *",timezone:"Europe/Moscow",delivery:"telegram",telegramChatId:"123"},new Date("2026-09-26T10:00:00Z"));
    await scheduler.tick(new Date("2026-09-27T06:00:01Z")); await scheduler.idle();
    expect(sent).toEqual([]);
    expect(store.listMessages(c.id)).toEqual([]);
    expect(scheduler.runs(c.id)[0]?.status).toBe("quiet");
  });
  it("keeps an app-only edition in the app even when the chat has a Telegram binding", async () => {
    const { store, scheduler } = setup();
    const c = store.primaryConversation();
    store.linkTelegramChat({ chatId: "123", title: "Test", allowedSenders: ["456"] });
    store.db.prepare("UPDATE telegram_chats SET conversation_id=? WHERE chat_id=?").run(c.id, "123");
    const delivered: string[] = [];
    scheduler.deliver = async chatId => { delivered.push(chatId); };
    scheduler.save({ conversationId: c.id, name: "App edition", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow", delivery: "app" }, new Date("2026-09-26T10:00:00Z"));
    await scheduler.tick(new Date("2026-09-27T04:00:00Z"));
    await scheduler.idle();
    expect(delivered).toEqual([]);
    expect(scheduler.runs(c.id)[0]?.status).toBe("completed");
  });
  it("does not confirm a pause for a missing schedule or a different chat", () => {
    const { store, scheduler } = setup();
    const c = store.primaryConversation();
    const s = scheduler.save({ conversationId: c.id, name: "Morning", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow" });
    expect(() => scheduler.remove("missing", c.id)).toThrow("Расписание этого чата не найдено");
    expect(() => scheduler.remove(s.id, "another-chat")).toThrow("Расписание этого чата не найдено");
    expect(scheduler.list(c.id)[0]?.enabled).toBe(true);
    scheduler.remove(s.id, c.id);
    expect(scheduler.list(c.id)[0]?.enabled).toBe(false);
  });

  it("uses the requested timezone and catches up once after sleep", async () => {
    const { store, scheduler, calls } = setup();
    const c = store.primaryConversation();
    const schedule = scheduler.save({ conversationId: c.id, name: "Morning", prompt: "Digest", cron: "0 6 * * *", timezone: "Europe/Moscow" }, new Date("2026-09-26T10:00:00Z"));
    expect(schedule.nextRunAt).toBe("2026-09-27T03:00:00.000Z");
    await scheduler.tick(new Date("2026-09-29T10:00:00Z"));
    await scheduler.idle();
    await scheduler.tick(new Date("2026-09-29T10:00:05Z"));
    await scheduler.idle();
    expect(calls()).toBe(1);
    expect(scheduler.list(c.id)[0]?.nextRunAt).toBe("2026-09-30T03:00:00.000Z");
    expect(scheduler.runs(c.id)).toEqual([expect.objectContaining({ status: "completed", scheduledFor: "2026-09-29T03:00:00.000Z" })]);
  });
  it("does not rerun an interrupted action on recovery", async () => {
    const { store, scheduler, calls } = setup();
    const c = store.primaryConversation();
    const s = scheduler.save({ conversationId: c.id, name: "Morning", prompt: "Action", cron: "0 6 * * *", timezone: "Europe/Moscow" }, new Date("2026-09-26T10:00:00Z"));
    store.db.prepare("INSERT INTO schedule_runs(id,schedule_id,conversation_id,scheduled_for,status,created_at) VALUES(?,?,?,?,?,?)").run("interrupted", s.id, c.id, "2026-09-27T03:00:00.000Z", "running", "2026-09-27T03:00:00.000Z");
    scheduler.recover();
    await scheduler.tick(new Date("2026-09-27T04:00:00Z")); await scheduler.idle();
    expect(calls()).toBe(0);
    expect(scheduler.runs(c.id)[0]?.status).toBe("uncertain");
  });
});
