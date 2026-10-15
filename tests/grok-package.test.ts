import { afterEach, beforeEach, expect, it } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// The pinned Grok Build, run offline only: no account, and on macOS no network at all.
let runtime: string;
beforeEach(() => { runtime = mkdtempSync(join(tmpdir(), "grok-package-")); symlinkSync(resolve("node_modules"), join(runtime, "node_modules")); });
afterEach(() => { rmSync(runtime, { recursive: true, force: true }); });

it("unpacks the pinned Grok Build to bin/grok, which accepts the commands OpenStrudel runs", () => {
  execFileSync(process.execPath, [resolve("scripts/extract-grok.mjs"), runtime], { encoding: "utf8" });
  const pinned = JSON.parse(readFileSync("package.json", "utf8")).dependencies["@xai-official/grok"];
  const env = { PATH: "/usr/bin:/bin", HOME: runtime, GROK_HOME: join(runtime, "grok-home"), GROK_DISABLE_AUTOUPDATER: "1" };
  const grok = (...args: string[]) => process.platform === "darwin"
    ? spawnSync("/usr/bin/sandbox-exec", ["-p", "(version 1)(allow default)(deny network*)", join(runtime, "bin/grok"), "--no-auto-update", ...args], { env, encoding: "utf8", timeout: 30_000 })
    : spawnSync(join(runtime, "bin/grok"), ["--no-auto-update", ...args], { env, encoding: "utf8", timeout: 30_000 });
  expect(grok("--version").stdout).toContain(`grok ${pinned} `);
  for (const command of [["agent", "stdio"], ["login", "--device-auth"], ["logout"]]) expect(grok(...command, "--help").status, command.join(" ")).toBe(0);
  // Grok's own sandbox is a top-level option that `agent` does not offer, so the engine passes none.
  expect(grok("agent", "--help").stdout).not.toContain("--sandbox");
}, 60_000);
