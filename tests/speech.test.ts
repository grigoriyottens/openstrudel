import { diagnosticReport } from "../src/diagnostics.js";
import { afterEach, expect, it, vi } from "vitest";
import { Store } from "../src/store.js";
import { generateSpeech, saveSpeechSettings, speechSettings, transcribeRecording } from "../src/speech.js";
import { transcribeVoice } from "../src/voice.js";
import { MessageService } from "../src/messages.js";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
vi.mock("../src/voice.js", () => ({ transcribeVoice: vi.fn(async () => "Local transcript") }));
const key = "only-a-test-key-for-elevenlabs";
const stores: Store[] = [];
function store(cloud = false) {
  const s = new Store(":memory:"); stores.push(s);
  if (cloud) { s.setSetting("speech.provider", "elevenlabs"); s.setSetting("speech.elevenlabs.key", key); }
  return s;
}
afterEach(() => { vi.unstubAllGlobals(); vi.clearAllMocks(); for (const s of stores.splice(0)) s.close(); });

it("keeps local recognition local even when an ElevenLabs key was saved", async () => {
  const s = store(true); s.setSetting("speech.provider", "local");
  vi.stubGlobal("fetch", vi.fn());
  expect(await transcribeRecording(s, new Uint8Array([1, 2]), "clip.m4a")).toBe("Local transcript");
  expect(transcribeVoice).toHaveBeenCalledWith(new Uint8Array([1, 2]), "m4a", undefined);
  expect(fetch).not.toHaveBeenCalled();
});

it("validates a replacement before saving, never returns its key, and disconnects explicitly", async () => {
  const s = store(true);
  vi.stubGlobal("fetch", vi.fn(async () => new Response(key, { status: 401 })));
  await expect(saveSpeechSettings(s, { provider: "elevenlabs", key: key + "-new" })).rejects.toThrow("ElevenLabs не принял");
  expect(s.getSetting("speech.elevenlabs.key")).toBe(key);
  vi.stubGlobal("fetch", vi.fn(async (url: string) => Response.json(url.endsWith("/voices") ? { voices: [{ voice_id: "voice-1", name: "First" }] } : [])));
  const settings = await saveSpeechSettings(s, { provider: "elevenlabs", key: key + "-new" });
  expect(settings).toMatchObject({ connected: true, voiceId: "voice-1", transcriptionModel: "scribe_v2", voiceModel: "eleven_v4" });
  expect(JSON.stringify(settings)).not.toContain(key);
  expect(JSON.stringify(speechSettings(s))).not.toContain(key);
  await expect(saveSpeechSettings(s, { voiceId: "missing" })).rejects.toThrow("голос");
  expect(await saveSpeechSettings(s, { removeKey: true })).toMatchObject({ connected: false, provider: "local", voices: [], voiceId: null });
  expect(s.getSetting("speech.elevenlabs.key")).toBeNull();
});

it("accepts a transcription-only key without promising voice generation", async () => {
  const s = store();
  vi.stubGlobal("fetch", vi.fn(async (url: string) => url.endsWith("/voices") ? new Response("denied", { status: 403 }) : Response.json([])));
  expect(await saveSpeechSettings(s, { provider: "elevenlabs", key })).toMatchObject({ connected: true, voiceId: null, voices: [] });
});

it.each(["voice.ogg", "audio.mp3", "recording.m4a", "clip.mp4", "movie.mov", "sound.flac"])("sends %s directly to Scribe v2 and keeps the actual text", async name => {
  const s = store(true), bytes = new Uint8Array([3, 4, 5]);
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    expect(url).toBe("https://api.elevenlabs.io/v1/speech-to-text");
    expect(init.redirect).toBe("error"); expect(init.headers).toMatchObject({ "xi-api-key": key });
    const body = init.body as FormData;
    expect(body.get("model_id")).toBe("scribe_v2");
    expect(body.get("language_code")).toBeNull();
    expect(body.get("no_verbatim")).toBeNull();
    expect((body.get("file") as File).name).toBe(name);
    expect(new Uint8Array(await (body.get("file") as File).arrayBuffer())).toEqual(bytes);
    return Response.json({ text: "  Встреча завтра в 12. Ничего не меняй.  " });
  }));
  expect(await transcribeRecording(s, bytes, name)).toBe("Встреча завтра в 12. Ничего не меняй.");
  expect(transcribeVoice).not.toHaveBeenCalled();
});

it("bounds recordings before upload, rejects silence and never silently falls back after cloud failure", async () => {
  const s = store(true); vi.stubGlobal("fetch", vi.fn(async () => Response.json({ text: "   " })));
  await expect(transcribeRecording(s, new Uint8Array())).rejects.toThrow("пустая");
  await expect(transcribeRecording(s, new Uint8Array(25 * 1024 * 1024 + 1))).rejects.toThrow("25 МБ");
  expect(fetch).not.toHaveBeenCalled();
  await expect(transcribeRecording(s, new Uint8Array([1]))).rejects.toThrow("Речь не распознана");
  vi.stubGlobal("fetch", vi.fn(async () => new Response(key, { status: 429 })));
  await expect(transcribeRecording(s, new Uint8Array([1]))).rejects.toThrow("лимит");
  vi.stubGlobal("fetch", vi.fn(async () => { throw new Error(key); }));
  const failure = await transcribeRecording(s, new Uint8Array([1])).catch(error => error.message);
  expect(failure).not.toContain(key); expect(transcribeVoice).not.toHaveBeenCalled();
});

it("propagates cancellation without another attempt", async () => {
  const s = store(true), controller = new AbortController();
  vi.stubGlobal("fetch", vi.fn((_url, init: RequestInit) => new Promise((_resolve, reject) => init.signal!.addEventListener("abort", () => reject(init.signal!.reason)))));
  const pending = transcribeRecording(s, new Uint8Array([1]), "voice.ogg", controller.signal);
  controller.abort(); await expect(pending).rejects.toBeDefined();
  expect(fetch).toHaveBeenCalledTimes(1);
});

it("uses the selected voice and current voice model, returning real MP3 bytes", async () => {
  const s = store(true); s.setSetting("speech.elevenlabs.voice", "voice-1");
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    expect(url).toContain("/voice-1?output_format=mp3_44100_128");
    expect(JSON.parse(String(init.body))).toEqual({ text: "Проверка", model_id: "eleven_v4" });
    return new Response(new Uint8Array([73, 68, 51]), { headers: { "content-type": "audio/mpeg" } });
  }));
  expect(await generateSpeech(s, "Проверка")).toEqual(Buffer.from("ID3"));
});

it("shows an attachment transcript before the answer, keeps retry identity, and generates a downloadable file", async () => {
  const s = store(true), root = mkdtempSync(join(tmpdir(), "speech-test-")); s.setSetting("speech.elevenlabs.voice", "voice-1");
  const run = vi.fn(async (text, options) => {
    expect(text).toContain("quoted source material"); expect(text).toContain("Встреча в 12");
    expect(s.listMessages(options.conversationId).some(m => m.kind === "notice" && m.text.includes("Встреча в 12"))).toBe(true);
    await options.tools.call("generate_speech", { text: "Встреча в 12" });
    return { threadId: "test", response: "Готово", events: [] };
  });
  vi.stubGlobal("fetch", vi.fn(async (url: string) => url.includes("speech-to-text") ? Response.json({ text: "Встреча в 12" }) : new Response("ID3")));
  const service = new MessageService(s, { run }, root);
  try {
    const c = s.primaryConversation(), file = service.files.put(c.id, service.contextFor(c.id), { name: "clip.mp4", mimeType: "video/mp4", contentBase64: "AQID" });
    const input = { channel: "api" as const, conversationId: c.id, text: "Послушай и озвучь", attachments: [file.id], externalId: "same-request" };
    const result = await service.handle(input);
    expect(result.attachments?.[0]).toMatchObject({ name: "speech.mp3", mimeType: "audio/mpeg", size: 3 });
    expect(await service.handle(input)).toEqual(result);
    expect(run).toHaveBeenCalledTimes(1); expect(fetch).toHaveBeenCalledTimes(2);
    expect(s.listMessages(c.id).filter(m => m.kind === "notice")).toHaveLength(1);
  } finally { await service.close(); rmSync(root, { recursive: true, force: true }); }
});


it("records the actual provider failure and successful retry without retaining audio or text", async () => {
  const s = store(true);
  vi.stubGlobal("fetch", vi.fn(async () => new Response("secret provider response", { status: 429 })));
  await expect(transcribeRecording(s, new Uint8Array([1, 2, 3]), "private-name.ogg")).rejects.toThrow("лимит");
  expect(diagnosticReport(s).events[0]).toMatchObject({ event: "speech.failed", provider: "elevenlabs", status: 429, reason: "provider_limit", bytes: 3 });
  vi.stubGlobal("fetch", vi.fn(async () => Response.json({ text: "private spoken words" })));
  await transcribeRecording(s, new Uint8Array([1, 2, 3]), "private-name.ogg");
  expect(diagnosticReport(s).events[0]).toMatchObject({ event: "speech.completed", provider: "elevenlabs", bytes: 3 });
  expect(JSON.stringify(diagnosticReport(s))).not.toMatch(/secret|private|spoken/);
});

it("distinguishes a provider timeout from network failure", async () => {
  const s = store(true);
  vi.stubGlobal("fetch", vi.fn(async () => { throw new DOMException("private request", "TimeoutError"); }));
  await expect(transcribeRecording(s, new Uint8Array([1]))).rejects.toThrow("не успел");
  expect(diagnosticReport(s).events[0]).toMatchObject({ event: "speech.failed", reason: "timeout" });
});

it("does not expose a malformed provider response to the user or diagnostics", async () => {
  const s = store(true);
  vi.stubGlobal("fetch", vi.fn(async () => new Response("private provider content")));
  await expect(transcribeRecording(s, new Uint8Array([1]))).rejects.toThrow("ElevenLabs сейчас не отвечает");
  expect(JSON.stringify(diagnosticReport(s))).not.toContain("private");
});


it("accepts speech text beyond the old 5000-character cap up to the selected model's real bound",async()=>{
 const s=store(true);s.setSetting("speech.elevenlabs.voice","fixture-voice");
 vi.stubGlobal("fetch",vi.fn(async()=>new Response(new Uint8Array([1,2,3]))));
 expect(await generateSpeech(s,"a".repeat(6000))).toEqual(Buffer.from([1,2,3]));
 await expect(generateSpeech(s,"a".repeat(10001))).rejects.toThrow("10000");
});
it("says an exhausted ElevenLabs quota is a limit, not a rejected key, and tells the owner it is about voice", async () => {
  const s = store(true);
  vi.stubGlobal("fetch", vi.fn(async () => Response.json({ detail: { status: "quota_exceeded", message: `This request exceeds your quota. ${key}` } }, { status: 401 })));
  const failure = await transcribeRecording(s, new Uint8Array([1, 2]), "voice.ogg").catch(error => error);
  expect(failure.message).toMatch(/закончился лимит/);
  expect(failure.message).not.toContain(key);
  expect(failure.reason).toBe("provider_limit");
  const { errorProblem, problemText } = await import("../src/operations.js");
  expect(errorProblem(failure)).toBe("voice");
  expect(problemText.voice).toMatch(/ElevenLabs/);
  vi.stubGlobal("fetch", vi.fn(async () => Response.json({ detail: { status: "invalid_api_key" } }, { status: 401 })));
  expect((await transcribeRecording(s, new Uint8Array([1, 2]), "voice.ogg").catch(error => error)).reason).toBe("provider_auth");
});
