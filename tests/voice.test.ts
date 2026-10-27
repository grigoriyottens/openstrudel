import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { dirname, join } from "node:path";
import { readFile, rm, stat, writeFile } from "node:fs/promises";

function pcmWav(silent = false): Buffer {
  const wav = Buffer.alloc(46);
  wav.write("RIFF", 0); wav.writeUInt32LE(38, 4); wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
  wav.write("data", 36); wav.writeUInt32LE(2, 40); wav.writeInt16LE(silent ? 0 : 1000, 44);
  return wav;
}

const mocks = vi.hoisted(() => ({ run: vi.fn(), access: vi.fn(), platform: vi.fn(), directories: [] as string[] }));
vi.mock("node:child_process", () => ({ execFile: Object.assign(vi.fn(), { [Symbol.for("nodejs.util.promisify.custom")]: mocks.run }) }));
vi.mock("node:os", async (original) => ({ ...await original<typeof import("node:os")>(), platform: mocks.platform }));
vi.mock("node:fs/promises", async (original) => {
  const actual = await original<typeof import("node:fs/promises")>();
  return { ...actual, access: mocks.access, mkdtemp: async (prefix: string) => {
    const directory = await actual.mkdtemp(prefix); mocks.directories.push(directory); return directory;
  } };
});
import { transcribeVoice } from "../src/voice.js";

beforeEach(() => {
  mocks.platform.mockReturnValue("linux"); mocks.access.mockResolvedValue(undefined); mocks.run.mockReset();
  mocks.run.mockImplementation(async (binary: string, args: string[]) => {
    if (binary.endsWith("ffprobe")) return { stdout: JSON.stringify({ format: { duration: "3.25" } }) };
    if (binary.endsWith("ffmpeg")) await writeFile(args.at(-1)!, pcmWav());
    if (binary.endsWith("whisper-cli")) await writeFile(args[args.indexOf("-of") + 1] + ".txt", "Привет, мир.\n");
    return { stdout: "" };
  });
});
afterEach(async () => {
  for (const directory of mocks.directories.splice(0)) {
    try { await expect(stat(directory)).rejects.toMatchObject({ code: "ENOENT" }); }
    finally { await rm(directory, { recursive: true, force: true }); }
  }
  vi.clearAllMocks();
});

describe("offline voice", () => {
  it("queues a second recording behind the first instead of refusing it", async () => {
    let release!: () => void;
    const gate = new Promise<void>(done => { release = done; });
    const whisper = mocks.run.getMockImplementation()!;
    mocks.run.mockImplementation(async (binary: string, args: string[]) => {
      if (binary.endsWith("whisper-cli") && !mocks.run.mock.calls.slice(0, -1).some(([b]) => b.endsWith("whisper-cli"))) await gate;
      return whisper(binary, args);
    });
    const first = transcribeVoice(new Uint8Array([1])), second = transcribeVoice(new Uint8Array([2]));
    await vi.waitFor(() => expect(mocks.run.mock.calls.filter(([b]) => b.endsWith("whisper-cli"))).toHaveLength(1));
    // The second recording has not started while the first is being recognised.
    expect(mocks.run.mock.calls.filter(([b]) => b.endsWith("ffprobe"))).toHaveLength(1);
    release();
    await expect(first).resolves.toBe("Привет, мир.");
    await expect(second).resolves.toBe("Привет, мир.");
    expect(mocks.run.mock.calls.filter(([b]) => b.endsWith("whisper-cli"))).toHaveLength(2);
  });

  it("gives Whisper the processors the Home may use", async () => {
    await transcribeVoice(new Uint8Array([1]));
    const [, args, options] = mocks.run.mock.calls.find(([b]) => b.endsWith("whisper-cli"))!;
    const threads = Number(args[args.indexOf("-t") + 1]);
    expect(threads).toBeGreaterThanOrEqual(2); expect(threads).toBeLessThanOrEqual(8);
    expect(options.env.OMP_NUM_THREADS).toBe(String(threads));
  });

  it("rejects empty and oversized audio before starting a process", async () => {
    await expect(transcribeVoice(new Uint8Array())).rejects.toThrow("пустое");
    await expect(transcribeVoice(new Uint8Array(25 * 1024 * 1024 + 1))).rejects.toThrow("25 МБ");
    expect(mocks.run).not.toHaveBeenCalled();
  });

  it("explains a missing Linux speech installation without exposing paths", async () => {
    mocks.access.mockRejectedValue(new Error("ENOENT /private/path"));
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("обновите OpenStrudel");
    expect(mocks.run).not.toHaveBeenCalled();
  });

  it("rejects unknown duration before decoding and cleans up", async () => {
    for (const duration of ["N/A", "NaN", "0", "-1"]) {
      mocks.run.mockResolvedValueOnce({ stdout: JSON.stringify({ format: { duration } }) });
      await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("прочитать");
    }
    expect(mocks.run.mock.calls.every(([binary]) => binary.endsWith("ffprobe"))).toBe(true);
  });

  it("recognizes a long recording without the old five-minute rejection",async()=>{
    mocks.run.mockResolvedValueOnce({stdout:JSON.stringify({format:{duration:"654"}})});
    expect(await transcribeVoice(new Uint8Array([1]))).toBe("Привет, мир.");
    const call=mocks.run.mock.calls.find(([binary])=>binary.endsWith("ffmpeg"))!;
    expect(Number(call[1][call[1].indexOf("-t")+1])).toBeGreaterThan(654);
  });

  it("hides decoder internals and removes uploaded audio on failure", async () => {
    mocks.run.mockRejectedValueOnce(new Error("ffprobe: private contents and paths"));
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("Не удалось прочитать голосовое");
  });

  it("rejects decoded audio that exceeds the duration declared by its container", async () => {
    mocks.run.mockImplementation(async (binary: string, args: string[]) => {
      if (binary.endsWith("ffprobe")) return { stdout: '{"format":{"duration":"3"}}' };
      if (binary.endsWith("ffmpeg")) await writeFile(args.at(-1)!, new Uint8Array(301 * 32_000));
      return { stdout: "" };
    });
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("прочитать");
    expect(mocks.run).toHaveBeenCalledTimes(2);
  });

  it("rejects a digitally silent recording instead of accepting a hallucinated word", async () => {
    mocks.run.mockImplementation(async (binary: string, args: string[]) => {
      if (binary.endsWith("ffprobe")) return { stdout: '{"format":{"duration":"3"}}' };
      if (binary.endsWith("ffmpeg")) await writeFile(args.at(-1)!, pcmWav(true));
      if (binary.endsWith("whisper-cli")) await writeFile(args[args.indexOf("-of") + 1] + ".txt", "you");
      return { stdout: "" };
    });
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("Речь не распознана");
    expect(mocks.run).toHaveBeenCalledTimes(2);
  });

  it("reports a recognition timeout clearly and removes temporary files", async () => {
    mocks.run.mockImplementation(async (binary: string, args: string[]) => {
      if (binary.endsWith("ffprobe")) return { stdout: '{"format":{"duration":"3"}}' };
      if (binary.endsWith("ffmpeg")) await writeFile(args.at(-1)!, pcmWav());
      if (binary.endsWith("whisper-cli")) throw Object.assign(new Error("private stderr"), { killed: true });
      return { stdout: "" };
    });
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("слишком много времени");
  });

  it("rejects an empty transcript", async () => {
    mocks.run.mockImplementation(async (binary: string, args: string[]) => {
      if (binary.endsWith("ffprobe")) return { stdout: '{"format":{"duration":"3"}}' };
      if (binary.endsWith("ffmpeg")) await writeFile(args.at(-1)!, pcmWav());
      if (binary.endsWith("whisper-cli")) await writeFile(args[args.indexOf("-of") + 1] + ".txt", " \n");
      return { stdout: "" };
    });
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("Речь не распознана");
  });

  it("runs bounded offline decoding and multilingual recognition without a shell", async () => {
    const bytes = new Uint8Array([1, 2, 3]);
    mocks.run.mockImplementation(async (binary: string, args: string[], options: Record<string, unknown>) => {
      expect(options.shell).not.toBe(true);
      expect(options.timeout).toBeGreaterThan(0);
      expect(options.maxBuffer).toBeLessThanOrEqual(1_048_576);
      if (binary.endsWith("ffprobe")) {
        const path = args.at(-1)!;
        expect(await readFile(path)).toEqual(Buffer.from(bytes));
        expect((await stat(path)).mode & 0o777).toBe(0o600);
        expect(args).toContain("-protocol_whitelist");
        expect(args).toContain("-format_whitelist");
        return { stdout: '{"format":{"duration":"3.25"}}' };
      }
      if (binary.endsWith("ffmpeg")) {
        expect(args).toContain("-nostdin"); expect(args).toContain("16000"); expect(args).toContain("-t");
        await writeFile(args.at(-1)!, pcmWav());
      }
      if (binary.endsWith("whisper-cli")) {
        const threads = args[args.indexOf("-t") + 1];
        expect(args).toEqual(expect.arrayContaining(["-l", "auto", "-t", threads, "-ng", "-fa"]));
        expect(options.env).toMatchObject({ OPENBLAS_NUM_THREADS: threads, OMP_NUM_THREADS: threads });
        const prefix = args[args.indexOf("-of") + 1];
        expect(dirname(prefix)).toBe(mocks.directories.at(-1));
        await writeFile(prefix + ".txt", "Привет, мир.\n");
      }
      return { stdout: "" };
    });
    expect(await transcribeVoice(bytes, "ogg;$(touch bad)")).toBe("Привет, мир.");
    expect(mocks.run).toHaveBeenCalledTimes(3);
  });

  it("keeps one recognition in memory and goes on with the next after a failure", async () => {
    let reject!: (error: Error) => void;
    mocks.run.mockImplementationOnce(() => new Promise((_resolve, fail) => { reject = fail; }));
    const first = transcribeVoice(new Uint8Array([1]));
    const firstResult = first.catch(error => error);
    await vi.waitFor(() => expect(reject).toBeTypeOf("function"));
    const second = transcribeVoice(new Uint8Array([2]));
    // The second recording waits; it does not start a second model alongside the first.
    expect(mocks.run).toHaveBeenCalledTimes(1);
    reject(new Error("broken audio"));
    expect(await firstResult).toMatchObject({ message: expect.stringContaining("прочитать") });
    expect(await second).toBe("Привет, мир.");
    expect(await transcribeVoice(new Uint8Array([3]))).toBe("Привет, мир.");
  });

  it("preserves the installed Mac OpenRamble path", async () => {
    mocks.platform.mockReturnValue("darwin"); mocks.run.mockResolvedValue({ stdout: "  Проверка OpenRamble.\n" });
    expect(await transcribeVoice(new Uint8Array([1]))).toBe("Проверка OpenRamble.");
    expect(mocks.run).toHaveBeenCalledTimes(1);
    expect(mocks.run.mock.calls[0][0]).toContain("openramble");
    expect(mocks.run.mock.calls[0][1]).toEqual([join(mocks.directories[0], "voice.ogg"), "--format", "txt"]);
  });

  it("bounds a stalled Mac recognizer by the recording's size and reports the timeout", async () => {
    mocks.platform.mockReturnValue("darwin"); mocks.run.mockResolvedValue({ stdout: "Готово." });
    await transcribeVoice(new Uint8Array([1]));
    await transcribeVoice(new Uint8Array(6_000_000));
    const [small, large] = mocks.run.mock.calls.map(call => call[2].timeout);
    expect(small).toBe(180_000);
    expect(large).toBeGreaterThan(small);
    mocks.run.mockRejectedValue(Object.assign(new Error("Command failed"), { killed: true }));
    await expect(transcribeVoice(new Uint8Array([1]))).rejects.toThrow("слишком много времени");
  });
});
