import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, writeFile, readFile, stat, rm, access } from "node:fs/promises";
import { tmpdir, homedir, platform, availableParallelism } from "node:os";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { MAX_FILE_BYTES } from "./files.js";

const run = promisify(execFile);
const whisper = "/usr/local/bin/whisper-cli";
const model = "/opt/openstrudel/voice/ggml-large-v3-turbo-q5_0.bin";
const formats = "ogg,wav,mp3,mov,matroska,webm,flac,aac";
let queue: Promise<unknown> = Promise.resolve();

/** Recordings are recognised one at a time, in the order they arrive: a busy Home answers later, never refuses. */
export function transcribeVoice(bytes: Uint8Array, extension = "ogg", signal?: AbortSignal): Promise<string> {
  const next = queue.then(() => recognize(bytes, extension, signal));
  queue = next.catch(() => undefined);
  return next;
}

/** The processors this Home may use: its container's CPU quota when it has one. */
function processors(): number {
  try {
    const [quota, period] = readFileSync("/sys/fs/cgroup/cpu.max", "utf8").trim().split(/\s+/);
    if (quota && quota !== "max") return Math.max(1, Math.floor(Number(quota) / Number(period)));
  } catch {}
  return availableParallelism();
}

/** Installed OpenRamble on Mac; bundled, offline Whisper on the Linux server. */
async function recognize(bytes: Uint8Array, extension: string, signal?: AbortSignal): Promise<string> {
  signal?.throwIfAborted();
  if (!bytes.length) throw new Error("Голосовое сообщение пустое. Запишите его ещё раз.");
  if (bytes.length > MAX_FILE_BYTES) throw new Error("Отправьте голосовое до 25 МБ.");
  const system = platform();
  let directory: string | undefined;
  try {
    let executable: string | undefined;
    if (system === "darwin") {
      for (const path of [join(homedir(), ".local/bin/openramble"), "/Applications/OpenRamble.app/Contents/MacOS/openramble-cli"]) {
        try { await access(path); executable = path; break; } catch {}
      }
      if (!executable) throw new Error("Для голосовых установите OpenRamble и загрузите в нём модель распознавания.");
    } else if (system === "linux") {
      try { for (const path of [whisper, model, "/usr/bin/ffmpeg", "/usr/bin/ffprobe"]) await access(path); }
      catch { throw new Error("Для голосовых обновите OpenStrudel на сервере: в новой версии распознавание уже включено."); }
    } else {
      throw new Error("Голосовые доступны на Mac и сервере Linux. Пока отправьте сообщение текстом.");
    }
    directory = await mkdtemp(join(tmpdir(), "openstrudel-voice-"));
    const file = join(directory, "voice." + (extension.replace(/[^a-z0-9]/gi, "").slice(0, 12) || "ogg"));
    await writeFile(file, bytes, { mode: 0o600 });
    let text: string;
    if (executable) {
      try {
        const result = await run(executable, [file, "--format", "txt"], { signal, maxBuffer: 1_048_576 });
        text = result.stdout.trim();
      } catch {
        throw new Error("Не удалось распознать голосовое. Проверьте, что модель OpenRamble загружена, или отправьте текст.");
      }
    } else {
      const wav = join(directory, "audio.wav");
      let duration: number;
      try {
        const probe = await run("/usr/bin/ffprobe", ["-v", "error", "-protocol_whitelist", "file,pipe", "-format_whitelist", formats,
          "-show_entries", "format=duration", "-of", "json", file], { timeout: 15_000, signal, maxBuffer: 65_536 });
        duration = Number(JSON.parse(probe.stdout).format?.duration);
        if (!Number.isFinite(duration) || duration <= 0) throw new Error("Invalid duration");
      } catch { throw new Error("Не удалось прочитать голосовое. Попробуйте записать его ещё раз или отправьте текст."); }
      let hasSound = false;
      try {
        await run("/usr/bin/ffmpeg", ["-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-format_whitelist", formats,
          "-i", file, "-map", "0:a:0", "-t", String(duration + 1), "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav],
        { timeout: Math.max(30_000, duration * 1_000), signal, maxBuffer: 65_536 });
        // Bound the decoded recording as well, even if its container lied about duration.
        if ((await stat(wav)).size > (duration + 1) * 32_000 + 4096) throw new Error("Decoded audio too long");
        const pcm = await readFile(wav);
        for (let offset = 12; offset + 8 <= pcm.length;) {
          const size = pcm.readUInt32LE(offset + 4);
          if (pcm.toString("ascii", offset, offset + 4) === "data") {
            hasSound = pcm.subarray(offset + 8, Math.min(offset + 8 + size, pcm.length)).some(byte => byte !== 0);
            break;
          }
          offset += 8 + size + (size % 2);
        }
      } catch { throw new Error("Не удалось прочитать голосовое. Попробуйте записать его ещё раз или отправьте текст."); }
      // Whisper can invent a word for digital silence. Do not send an empty
      // waveform to the model; quiet but nonzero recordings remain untouched.
      if (!hasSound) throw new Error("Речь не распознана. Попробуйте записать сообщение ещё раз.");
      try {
        const output = join(directory, "transcript");
        const threads = String(Math.max(2, Math.min(8, processors())));
        await run(whisper, ["-m", model, "-f", wav, "-l", "auto", "-t", threads, "-ng", "-fa", "-nt", "-np", "-otxt", "-of", output],
          { timeout: Math.max(240_000, duration * 2_000), signal, maxBuffer: 1_048_576, env: { ...process.env, OPENBLAS_NUM_THREADS: threads, OMP_NUM_THREADS: threads } });
        text = (await readFile(output + ".txt", "utf8")).trim();
      } catch (error) {
        if (error && typeof error === "object" && "killed" in error && error.killed) {
          throw new Error("Распознавание заняло слишком много времени. Отправьте более короткое голосовое или текст.");
        }
        throw new Error("Не удалось распознать голосовое. Попробуйте записать его ещё раз или отправьте текст.");
      }
    }
    if (!text) throw new Error("Речь не распознана. Попробуйте записать сообщение ещё раз.");
    return text;
  } finally {
    if (directory) await rm(directory, { recursive: true, force: true });
  }
}
