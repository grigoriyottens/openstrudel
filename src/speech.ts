import type { Store } from "./store.js";
import { MAX_FILE_BYTES } from "./files.js";
import { transcribeVoice } from "./voice.js";
import { HomeError } from "./home.js";
import { recordDiagnostic, type DiagnosticReason } from "./diagnostics.js";

const origin = "https://api.elevenlabs.io";
const keySetting = "speech.elevenlabs.key";
export const MAX_SPEECH_BYTES = MAX_FILE_BYTES;
export const transcriptionModel = "scribe_v2";
export const voiceModel = "eleven_v4";
export const MAX_SPEECH_TEXT = 10_000; // Eleven v4 API character limit.
type Voice = { id: string; name: string };

/** Speech is configured on the Home that does the work, like its model accounts.
 * The public settings never contain the key. Local mode never sends audio away. */
export function speechSettings(store: Store) {
  const voices: Voice[] = JSON.parse(store.getSetting("speech.elevenlabs.voices") ?? "[]");
  const provider: "local" | "elevenlabs" = store.getSetting("speech.provider") === "elevenlabs" ? "elevenlabs" : "local";
  return {
    provider, connected: Boolean(store.getSetting(keySetting)),
    // Where recordings actually go: the operator's speech server overrides the saved choice.
    transcription: speechServer() ? "server" as const : provider, transcriptionModel, voiceModel,
    voiceId: store.getSetting("speech.elevenlabs.voice") ?? null, voices,
  };
}

class SpeechFailure extends HomeError {
  constructor(message: string, status: number, readonly reason: DiagnosticReason, readonly providerStatus?: number) { super(message, status); }
}

type Service = { origin: string; key: string; errors: Record<"auth" | "busy" | "audio" | "down" | "late" | "network", string> };
const elevenLabs = (key: string): Service => ({ origin, key, errors: {
  auth: "ElevenLabs не принял ключ или его разрешения. Проверьте ключ в настройках голоса.",
  busy: "ElevenLabs временно недоступен или закончился лимит. Проверьте баланс и повторите позже.",
  audio: "ElevenLabs не смог обработать запись. Проверьте формат файла и наличие речи.",
  down: "ElevenLabs сейчас не отвечает. Попробуйте ещё раз.",
  late: "ElevenLabs не успел распознать запись. Попробуйте ещё раз.",
  network: "Не удалось связаться с ElevenLabs. Запись можно распознать повторно.",
} });

/** A server Home can send recordings to its own OpenRamble server, which answers like ElevenLabs Scribe. When the
 * operator sets one, every recording goes there, whatever the voice settings choose; voice generation stays on ElevenLabs. */
function speechServer(): Service | null {
  const url = process.env.OPENSTRUDEL_STT_URL?.trim();
  return url ? { origin: url.replace(/\/+$/, ""), key: process.env.OPENSTRUDEL_STT_KEY?.trim() ?? "", errors: {
    auth: "Сервер распознавания не принял ключ. Проверьте OPENSTRUDEL_STT_KEY.",
    busy: "Сервер распознавания сейчас занят. Повторите через минуту.",
    audio: "Сервер распознавания не смог обработать запись. Проверьте формат файла и наличие речи.",
    down: "Сервер распознавания сейчас не отвечает. Попробуйте ещё раз.",
    late: "Сервер распознавания не успел распознать запись. Попробуйте ещё раз.",
    network: "Не удалось связаться с сервером распознавания. Запись можно распознать повторно.",
  } } : null;
}

function problem(service: Service, status: number, code?: unknown): Error {
  // ElevenLabs answers an exhausted quota with 401 too; its error code tells them apart.
  if (code === "quota_exceeded") return new SpeechFailure("У ElevenLabs закончился лимит. Пополните баланс ElevenLabs или дождитесь его обновления.", 503, "provider_limit", status);
  if (code === "audio_too_long" || code === "audio_too_long_for_deadline") return new SpeechFailure("Запись слишком длинная для распознавания. Разделите её на части.", 400, "invalid_audio", status);
  if (status === 401 || status === 403) return new SpeechFailure(service.errors.auth, 400, "provider_auth", status);
  if (status === 402 || status === 429) return new SpeechFailure(service.errors.busy, 503, "provider_limit", status);
  if (status === 400 || status === 422) return new SpeechFailure(service.errors.audio, 400, "invalid_audio", status);
  return new SpeechFailure(service.errors.down, 503, "provider_unavailable", status);
}

async function request(service: Service, path: string, init: RequestInit = {}, signal?: AbortSignal, timeoutMs = 180_000) {
  try {
    const timeout = AbortSignal.timeout(timeoutMs);
    const response = await fetch(service.origin + path, { ...init, redirect: "error", headers: { ...init.headers, "xi-api-key": service.key },
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
    if (!response.ok) {
      const code = await response.json().then((body: any) => body?.detail?.status, () => undefined);
      throw problem(service, response.status, code);
    }
    return response;
  } catch (error) {
    if (error instanceof HomeError || signal?.aborted) throw error;
    // Provider errors can contain request details. Return only our own text.
    const timedOut = error instanceof Error && error.name === "TimeoutError";
    throw new SpeechFailure(timedOut ? service.errors.late : service.errors.network, 503, timedOut ? "timeout" : "network");
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
    await request(elevenLabs(key), "/v1/models").then(r => r.json());
    // A transcription-only key need not have access to the voice library.
    voices = [];
    try {
      const data = await (await request(elevenLabs(key), "/v1/voices")).json() as { voices?: Array<{voice_id?: string; name?: string}> };
      voices = (data.voices ?? []).filter(v => v.voice_id && v.name).map(v => ({ id: v.voice_id!, name: v.name! }));
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
  const provider = speechSettings(store).transcription, started = Date.now();
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
  if (bytes.length > MAX_SPEECH_BYTES) throw new HomeError("Для распознавания выберите аудио или видео до 25 МБ.", 413);
  const server = speechServer();
  if (!server && speechSettings(store).provider === "local") return transcribeVoice(bytes, name.split(".").at(-1), signal);
  const key = store.getSetting(keySetting);
  if (!server && !key) throw new HomeError("Добавьте API-ключ ElevenLabs в настройках голоса.");
  const service = server ?? elevenLabs(key!);
  const form = new FormData();
  form.set("model_id", transcriptionModel);
  form.set("tag_audio_events", "false");
  form.set("timestamps_granularity", "none");
  // A voice note waits 170 s, under the Home's 180 s limit. A longer recording waits up to half its length at the
  // lowest voice bitrate (1.5 KB/s), at most 10 minutes: the longest wait the server still puts ahead of meetings.
  const wait = Math.min(600, Math.max(170, Math.ceil(bytes.length / 3_000)));
  if (server) form.set("deadline_s", String(wait));
  form.set("file", new Blob([new Uint8Array(bytes)]), name.replace(/[^\p{L}\p{N}._ -]/gu, "_").slice(-180) || "voice.ogg");
  const response = await request(service, "/v1/speech-to-text", { method: "POST", body: form }, signal, server ? (wait + 10) * 1_000 : undefined);
  let result: { text?: string };
  try { result = await response.json() as { text?: string }; }
  catch (error) {
    if (signal?.aborted) throw error;
    throw new SpeechFailure(service.errors.down, 503,
      error instanceof Error && error.name === "TimeoutError" ? "timeout" : "provider_unavailable");
  }
  if (typeof result.text !== "string" || !result.text.trim()) throw new HomeError("Речь не распознана. Попробуйте записать сообщение ещё раз.");
  return result.text.trim();
}

/** Voice generation is exposed as an ordinary employee tool, only when connected. */
export async function generateSpeech(store: Store, text: string): Promise<Buffer> {
  const settings = speechSettings(store), key = store.getSetting(keySetting);
  if (!key || !settings.voiceId) throw new HomeError("Подключите ElevenLabs и выберите голос в настройках.");
  if (!text.trim() || text.length > MAX_SPEECH_TEXT) throw new HomeError("Для озвучивания нужен текст до 10000 символов.");
  const response = await request(elevenLabs(key), "/v1/text-to-speech/" + encodeURIComponent(settings.voiceId) + "?output_format=mp3_44100_128", {
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
