import { describe, expect, it } from "vitest";
import { Store } from "../src/store.js";

describe("Store", () => {
  it("names new assistants in the creating client's language without renaming existing ones", () => {
    const store = new Store(":memory:");
    try {
      expect(store.createProfile({}).name).toBe("New assistant");
      const original = store.createProfile({ name: "Новый сотрудник", instructions: "Existing rules" });
      expect(store.createProfile({ defaultName: "Новый сотрудник" }).name).toBe("Новый сотрудник 2");
      expect(store.createProfile({ defaultName: "Nouvel assistant" }).name).toBe("Nouvel assistant");
      expect(store.createProfile({ name: "My name", defaultName: "Nouvel assistant" }).name).toBe("My name");
      expect(store.getProfile(original.id)).toMatchObject({ name: "Новый сотрудник", instructions: "Existing rules" });
      const longName = "x".repeat(80);
      store.createProfile({ name: longName });
      expect(store.createProfile({ defaultName: longName }).name).toBe("x".repeat(78) + " 2");
      expect(() => store.createProfile({ defaultName: "x".repeat(81) })).toThrow();
    } finally { store.close(); }
  });
  it("keeps a short role and access domain separate from the full employee rules", () => {
    const store = new Store(":memory:");
    const p = store.createProfile({ name: "Редактор", instructions: "Full rules", purpose: "Помогает писать", domain: "work" });
    store.updateProfile(p.id, { name: "Редактор", instructions: "New rules" });
    expect(store.getProfile(p.id)).toMatchObject({ purpose: "Помогает писать", domain: "work", instructions: "New rules" });
    expect(() => store.createProfile({ name: "Invalid", domain: "other" as any })).toThrow();
    store.close();
  });
  it("uses the latest employee answer as a bounded preview, keeping the personality separate", () => {
    const store = new Store(":memory:");
    const employee = store.createProfile({ name: "News", instructions: "Private personality" });
    const chat = store.profileConversation(employee.id);
    store.addMessage({ conversationId: chat.id, channel: "api", direction: "outbound", text: "First answer" });
    store.addMessage({ conversationId: chat.id, channel: "telegram", direction: "outbound", text: "Latest answer" });
    store.addMessage({ conversationId: chat.id, channel: "api", direction: "inbound", text: "Next question" });
    expect(store.listProfiles()[0]).toMatchObject({ preview: "Latest answer", instructions: "Private personality" });
    store.close();
  });

  it("persists only conversations, messages, employees and settings", () => {
    const store = new Store(":memory:");
    const conversation = store.getOrCreateConversation({ channel: "api", externalId: "chat-1" });
    store.addMessage({ conversationId: conversation.id, channel: "api", direction: "inbound", text: "Привет" });
    store.addMessage({ conversationId: conversation.id, channel: "api", direction: "outbound", text: "Здравствуйте" });
    const profile = store.createProfile({ name: "Исследователь", instructions: "Собирай факты" });
    expect(store.listMessages(conversation.id)).toHaveLength(2);
    expect(store.getProfile(profile.id)?.name).toBe("Исследователь");
    const tables = (store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as Array<{ name: string }>).map((row) => row.name);
    expect(tables).toEqual(expect.arrayContaining(["conversations", "messages", "employee_profiles", "telegram_updates", "settings"]));
    expect(tables).not.toEqual(expect.arrayContaining(["tasks", "devices", "receipts", "task_events", "messages_fts"]));
    store.close();
  });

  it("deduplicates external messages and Telegram updates", () => {
    const store = new Store(":memory:");
    const conversation = store.getOrCreateConversation({ channel: "telegram", externalId: "42" });
    const first = store.addMessage({ conversationId: conversation.id, channel: "telegram", direction: "inbound", text: "hello", externalId: "42:1" });
    const second = store.addMessage({ conversationId: conversation.id, channel: "telegram", direction: "inbound", text: "hello again", externalId: "42:1" });
    expect(second.id).toBe(first.id);
    expect(store.wasTelegramUpdateProcessed(12)).toBe(false);
    store.markTelegramUpdate(12);
    expect(store.wasTelegramUpdateProcessed(12)).toBe(true);
    store.close();
  });
});
