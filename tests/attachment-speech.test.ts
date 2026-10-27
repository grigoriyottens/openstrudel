import { afterEach, expect, it, vi } from "vitest";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";

vi.mock("../src/voice.js", () => ({ transcribeVoice: vi.fn(async () => { throw new Error("Речь не распознана. Попробуйте записать сообщение ещё раз."); }) }));

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

function service(prompts: string[]) {
  const root = mkdtempSync(join(tmpdir(), "attachment-speech-")); roots.push(root);
  const store = new Store(":memory:");
  const messages = new MessageService(store, { async run(input) { prompts.push(input); return { threadId: "t", response: "Видно экран настроек.", events: [] }; } }, root);
  return { store, messages };
}

it("answers about a video without speech instead of failing the whole request", async () => {
  const prompts: string[] = [];
  const { store, messages } = service(prompts);
  try {
    const result = await messages.handle({ channel: "api", text: "Что на этой записи экрана?", uploads: [{ id: "00000000-0000-4000-8000-000000000001", name: "screen.mp4", mimeType: "video/mp4", contentBase64: "AQID" }] });
    expect(result.text).toBe("Видно экран настроек.");
    expect(prompts[0]).toContain("screen.mp4");
    expect(prompts[0]).toContain("Что на этой записи экрана?");
  } finally { await messages.close(); store.close(); }
});

it("still explains an unrecognized voice note sent on its own", async () => {
  const prompts: string[] = [];
  const { store, messages } = service(prompts);
  try {
    await expect(messages.handle({ channel: "api", text: "", uploads: [{ id: "00000000-0000-4000-8000-000000000002", name: "voice.m4a", mimeType: "audio/mp4", contentBase64: "AQID" }] })).rejects.toThrow("Речь не распознана");
    expect(prompts).toEqual([]);
  } finally { await messages.close(); store.close(); }
});
