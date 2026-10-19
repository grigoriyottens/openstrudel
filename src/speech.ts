import type { Store } from "./store.js";
import { transcribeVoice } from "./voice.js";
import { HomeError } from "./home.js";
import { recordDiagnostic, type DiagnosticReason } from "./diagnostics.js";

const origin = "https://api.elevenlabs.io";
const keySetting = "speech.elevenlabs.key";
export const MAX_SPEECH_BYTES = 20_000_000;
export const transcriptionModel = "scribe_v2";
export const voiceModel = "eleven_v4";
type Voice = { id: string; name: string };

/** Speech is configured on the Home that does the work, like its model accounts.
 * The public settings never contain the key. Local mode never sends audio away. */
export function speechSettings(store: Store) {
  const voices: Voice[] = JSON.parse(store.getSetting("speech.elevenlabs.voices") ?? "[]");
  return {
    provider: store.getSetting("speech.provider") === "elevenlabs" ? "elevenlabs" : "local",
    connected: Boolean(store.getSetting(keySetting)), transcriptionModel, voiceModel,
    voiceId: store.getSetting("speech.elevenlabs.voice") ?? null, voices,
  };
}

class SpeechFailure extends HomeError {
  constructor(message: string, status: number, readonly reason: DiagnosticReason, readonly providerStatus?: number) { super(message, status); }
}

function problem(status: number): Error {
  if (status === 401 || status === 403) return new SpeechFailure("ElevenLabs не принял ключ или его разрешения. Проверьте ключ в настройках голоса.", 400, "provider_auth", status);
  if (status === 402 || status === 429) return new SpeechFailure("ElevenLabs временно недоступен или закончился лимит. Проверьте баланс и повторите позже.", 503, "provider_limit", status);
  if (status === 400 || status === 422) return new SpeechFailure("ElevenLabs не смог обработать запись. Проверьте формат файла и наличие речи.", 400, "invalid_audio", status);
  return new SpeechFailure("ElevenLabs сейчас не отвечает. Попробуйте ещё раз.", 503, "provider_unavailable", status);
}

async function request(key: string, path: string, init: RequestInit = {}, signal?: AbortSignal) {
  try {
    const timeout = AbortSignal.timeout(180_000);
    const response = await fetch(origin + path, { ...init, redirect: "error", headers: { ...init.headers, "xi-api-key": key },
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
    if (!response.ok) { await response.body?.cancel(); throw problem(response.status); }
    return response;
  } catch (error) {
    if (error instanceof HomeError || signal?.aborted) throw error;
    // Provider errors can contain request details. Return only our own text.
    const timedOut = error instanceof Error && error.name === "TimeoutError";
    throw new SpeechFailure(timedOut ? "ElevenLabs не успел распознать запись. Попробуйте ещё раз." : "Не удалось связаться с ElevenLabs. Запись можно распознать повторно.", 503, timedOut ? "timeout" : "network");
  }
}

export async function saveSpeechSettings(store: Store, input: Record<string, unknown>) {
  if (Object.keys(input).some(k => !["provider", "key", "voiceId", "removeKey"].includes(k))) throw new HomeError("Неизвестная настройка голоса.");
  if (input.provider !== undefined && input.provider !== "local" && input.provider !== "elevenlabs") throw new HomeError("Выберите распознавание на устройстве или ElevenLabs.");
  if (input.removeKey !== undefined && typeof input.removeKey !== "boolean") throw new HomeError("Проверьте настройку ключа.");
  if (input.removeKey && (input.key !== undefined || input.provider === "elevenlabs")) throw new HomeError("Сначала отключите ElevenLabs.");
  let key = store.getSetting(keySetting), voices = speechSettings(store).voices;
  if (input.key !== undefined) {
    if (typeof input.key !== "string" || !/^[^\s]{20,512}$/.test(input.key.trim())) throw new HomeError("Вставьте API-ключ ElevenLabs.");
    key = input.key.trim();
    await request(key, "/v1/models").then(r => r.json());
    // A transcription-only key need not have access to the voice library.
    voices = [];
    try {
      const data = await (await request(key, "/v1/voices")).json() as { voices?: Array<{voice_id?: string; name?: string}> };
      voices = (data.voices ?? []).filter(v => v.voice_id && v.name).slice(0, 100).map(v => ({ id: v.voice_id!, name: v.name! }));
    } catch {}
  }
  if (input.provider === "elevenlabs" && !key) throw new HomeError("Добавьте API-ключ ElevenLabs.");
  if (input.voiceId !== undefined && (typeof input.voiceId !== "string" || !voices.some(v => v.id === input.voiceId))) throw new HomeError("Выберите доступный голос ElevenLabs.");
  // Commit only after validation; a rejected replacement preserves the working key.
  if (input.removeKey) {
    for (const setting of [keySetting, "speech.elevenlabs.voices", "speech.elevenlabs.voice"]) store.deleteSetting(setting);
    store.setSetting("speech.provider", "local");
  } else {
    if (input.key !== undefined) {
      store.setSetting(keySetting, key!);
      store.setSetting("speech.elevenlabs.voices", JSON.stringify(voices));
      const previous = store.getSetting("speech.elevenlabs.voice");
      const voice = voices.find(v => v.id === previous) ?? voices.find(v => v.id === "JBFqnCBsd6RMkjVDRZzb") ?? voices[0];
      if (voice) store.setSetting("speech.elevenlabs.voice", voice.id); else store.deleteSetting("speech.elevenlabs.voice");
    }
    if (input.provider) store.setSetting("speech.provider", String(input.provider));
    if (input.voiceId) store.setSetting("speech.elevenlabs.voice", String(input.voiceId));
  }
  return speechSettings(store);
}

export function isSpeechFile(name: string, mimeType?: string): boolean {
  return /^(audio|video)\//i.test(mimeType ?? "") || /\.(aac|aif|aiff|amr|flac|m4a|m4b|mp3|mp4|mpeg|mpg|mov|mkv|webm|ogg|oga|opus|wav|wma|wmv|avi|3gp)$/i.test(name);
}

export async function transcribeRecording(store: Store, bytes: Uint8Array, name = "voice.ogg", signal?: AbortSignal): Promise<string> {
  const provider = speechSettings(store).provider as "local" | "elevenlabs", started = Date.now();
  recordDiagnostic(store, "speech.started", { provider, bytes: bytes.length });
  try {
    const text = await recognizeRecording(store, bytes, name, signal);
    recordDiagnostic(store, "speech.completed", { provider, bytes: bytes.length, durationMs: Date.now() - started });
    return text;
  } catch (error) {
    const reason = signal?.aborted ? "cancelled" : !bytes.length ? "empty_audio" : bytes.length > MAX_SPEECH_BYTES ? "file_too_large"
      : error instanceof SpeechFailure ? error.reason : provider === "local" ? "local_recognition" : "invalid_audio";
    recordDiagnostic(store, "speech.failed", { provider, bytes: bytes.length, durationMs: Date.now() - started, reason,
      ...(error instanceof SpeechFailure && error.providerStatus ? { status: error.providerStatus } : {}) });
    throw error;
  }
}

async function recognizeRecording(store: Store, bytes: Uint8Array, name: string, signal?: AbortSignal): Promise<string> {
  if (!bytes.length) throw new HomeError("Запись пустая. Запишите её ещё раз.");
  if (bytes.length > MAX_SPEECH_BYTES) throw new HomeError("Для распознавания выберите аудио или видео до 20 МБ.", 413);
  if (speechSettings(store).provider === "local") return transcribeVoice(bytes, name.split(".").at(-1));
  const key = store.getSetting(keySetting);
  if (!key) throw new HomeError("Добавьте API-ключ ElevenLabs в настройках голоса.");
  const form = new FormData();
  form.set("model_id", transcriptionModel);
  form.set("tag_audio_events", "false");
  form.set("timestamps_granularity", "none");
  form.set("file", new Blob([new Uint8Array(bytes)]), name.replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(-180) || "voice.ogg");
  const response = await request(key, "/v1/speech-to-text", { method: "POST", body: form }, signal);
  let result: { text?: string };
  try { result = await response.json() as { text?: string }; }
  catch (error) {
    if (signal?.aborted) throw error;
    throw new SpeechFailure("ElevenLabs сейчас не отвечает. Попробуйте ещё раз.", 503,
      error instanceof Error && error.name === "TimeoutError" ? "timeout" : "provider_unavailable");
  }
  if (typeof result.text !== "string" || !result.text.trim()) throw new HomeError("Речь не распознана. Попробуйте записать сообщение ещё раз.");
  return result.text.trim();
}

/** Voice generation is exposed as an ordinary employee tool, only when connected. */
export async function generateSpeech(store: Store, text: string): Promise<Buffer> {
  const settings = speechSettings(store), key = store.getSetting(keySetting);
  if (!key || !settings.voiceId) throw new HomeError("Подключите ElevenLabs и выберите голос в настройках.");
  if (!text.trim() || text.length > 5000) throw new HomeError("Для озвучивания нужен текст до 5000 символов.");
  const response = await request(key, "/v1/text-to-speech/" + encodeURIComponent(settings.voiceId) + "?output_format=mp3_44100_128", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text, model_id: voiceModel }),
  });
  const reader = response.body?.getReader();
  if (!reader) throw new HomeError("ElevenLabs не вернул аудио. Попробуйте ещё раз.");
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.length;
      if (size > MAX_SPEECH_BYTES) throw new HomeError("Аудио получилось слишком большим. Сократите текст.");
      chunks.push(value);
    }
  } finally { await reader.cancel(); }
  if (!size) throw new HomeError("ElevenLabs не вернул аудио. Попробуйте ещё раз.");
  return Buffer.concat(chunks);
}
