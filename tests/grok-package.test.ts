import { afterAll, beforeAll, expect, it } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { grokHome } from "../src/acp.js";

// The pinned Grok Build, run offline only: no account, and on macOS no network at all where Grok's own sandbox is not under test.
let runtime: string;
beforeAll(() => {
  runtime = mkdtempSync(join(tmpdir(), "grok-package-"));
  symlinkSync(resolve("node_modules"), join(runtime, "node_modules"));
  execFileSync(process.execPath, [resolve("scripts/extract-grok.mjs"), runtime], { encoding: "utf8" });
}, 60_000);
afterAll(() => { rmSync(runtime, { recursive: true, force: true }); });

it("unpacks the pinned Grok Build to bin/grok, which accepts the commands OpenStrudel runs", () => {
  const pinned = JSON.parse(readFileSync("package.json", "utf8")).dependencies["@xai-official/grok"];
  const home = grokHome(runtime), env = { PATH: "/usr/bin:/bin", HOME: home, GROK_HOME: home, GROK_DISABLE_AUTOUPDATER: "1" };
  const grok = (...args: string[]) => process.platform === "darwin"
    ? spawnSync("/usr/bin/sandbox-exec", ["-p", "(version 1)(allow default)(deny network*)", join(runtime, "bin/grok"), "--no-auto-update", ...args], { env, encoding: "utf8", timeout: 30_000 })
    : spawnSync(join(runtime, "bin/grok"), ["--no-auto-update", ...args], { env, encoding: "utf8", timeout: 30_000 });
  expect(grok("--version").stdout).toContain(`grok ${pinned} `);
  for (const command of [["--sandbox", "openstrudel", "agent", "stdio"], ["login", "--device-auth"], ["logout"]]) expect(grok(...command, "--help").status, command.join(" ")).toBe(0);
}, 60_000);

it("ships Grok Build's Apache-2.0 license and the notices of the pinned version", () => {
  expect(readFileSync("licenses/Grok-LICENSE.txt", "utf8")).toMatch(/^Copyright 2023-2026 SpaceXAI\n[\s\S]*Apache License\s+Version 2\.0/);
  // Every platform package carries the same notices; a new Grok Build must bring its own.
  expect(readFileSync("licenses/Grok-THIRD_PARTY_NOTICES.md", "utf8")).toBe(readFileSync(`node_modules/@xai-official/grok-${process.platform}-${process.arch}/THIRD_PARTY_NOTICES.md`, "utf8"));
});

it("runs under its own sandbox: the workspace, system paths and Grok's home, never the Home's data or the owner's files", () => {
  // Every profile may use the temp folders, so this Home lives in the checkout, as in scripts/check-sandbox.mjs.
  const root = mkdtempSync(resolve(".grok-sandbox-"));
  try {
    const home = grokHome(root), workspace = join(root, ".data/workspace/personal"), other = join(root, ".data/workspace/work");
    for (const dir of [workspace, other]) mkdirSync(dir, { recursive: true });
    writeFileSync(join(workspace, "notes.md"), "mine"); writeFileSync(join(other, "notes.md"), "theirs"); writeFileSync(join(root, ".data/openstrudel.sqlite"), "keys");
    const reads = [join(workspace, "notes.md"), join(other, "notes.md"), join(root, ".data/openstrudel.sqlite"), resolve("package.json"), "/etc/hosts"];
    const writes = [join(home, "probe"), join(home, "config.toml"), join(workspace, "probe")];
    // A stdio MCP server inherits Grok's sandbox; `grok mcp doctor` starts it without an account or a model.
    writeFileSync(join(workspace, "probe.sh"), `{
for file in ${reads.map(f => JSON.stringify(f)).join(" ")}; do if cat "$file" >/dev/null 2>&1; then echo "read $file"; else echo "no read $file"; fi; done
for file in ${writes.map(f => JSON.stringify(f)).join(" ")}; do if : >> "$file" 2>/dev/null; then echo "write $file"; else echo "no write $file"; fi; done
} > ${JSON.stringify(join(workspace, "probe.out"))}
exit 1\n`);
    writeFileSync(join(home, "config.toml"), `[mcp_servers.probe]\ncommand = "/bin/sh"\nargs = [${JSON.stringify(join(workspace, "probe.sh"))}]\n`);
    // Grok's Seatbelt profile cannot start inside sandbox-exec. Without an account and with every proxy dead, Grok reaches no server.
    const dead = "http://127.0.0.1:9", env = { PATH: "/usr/bin:/bin", HOME: home, GROK_HOME: home, GROK_DISABLE_AUTOUPDATER: "1", HTTPS_PROXY: dead, HTTP_PROXY: dead, ALL_PROXY: dead };
    const grok = (profile: string) => spawnSync(join(runtime, "bin/grok"), ["--no-auto-update", "--sandbox", profile, "mcp", "doctor", "probe"], { cwd: workspace, env, encoding: "utf8", timeout: 30_000 });
    // A profile Grok cannot apply stops it rather than run unprotected.
    const missing = grok("missing");
    expect(missing.status).not.toBe(0);
    expect(missing.stderr).toContain("Refusing to start with its protections missing.");
    grok("openstrudel");
    expect(readFileSync(join(workspace, "probe.out"), "utf8").split("\n").filter(Boolean)).toEqual([
      `read ${reads[0]}`, `no read ${reads[1]}`, `no read ${reads[2]}`, `no read ${reads[3]}`, "read /etc/hosts",
      // Grok keeps its sign-in, sessions and memory in its home; its settings and this profile stay as OpenStrudel wrote them.
      `write ${writes[0]}`, `no write ${writes[1]}`, `write ${writes[2]}`]);
  } finally { rmSync(root, { recursive: true, force: true }); }
}, 60_000);
