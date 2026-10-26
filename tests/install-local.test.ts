import { expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

it.skipIf(process.platform !== "darwin")("leaves the Mac app's Home agent alone instead of replacing it with this checkout", () => {
  const home = mkdtempSync(join(tmpdir(), "install-local-"));
  const agent = join(home, "Library/LaunchAgents/is.openstrudel.home.plist");
  const appHome = '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Label</key><string>is.openstrudel.home</string>'
    + "<key>WorkingDirectory</key><string>/Users/someone/Library/Application Support/OpenStrudel/data</string></dict></plist>";
  try {
    mkdirSync(join(home, "Library/LaunchAgents"), { recursive: true });
    writeFileSync(agent, appHome);
    // A stub npm proves the script stops before building anything.
    const bin = join(home, "bin"); mkdirSync(bin);
    writeFileSync(join(bin, "npm"), "#!/bin/sh\necho npm-ran >&2\nexit 1\n", { mode: 0o755 });
    const run = spawnSync("bash", ["scripts/install-local.sh"], { env: { ...process.env, HOME: home, PATH: bin + ":" + process.env.PATH }, encoding: "utf8" });
    expect(run.status).toBe(1);
    expect(run.stderr).toContain("is.openstrudel.home.plist");
    expect(run.stderr).not.toContain("npm-ran");
    expect(readFileSync(agent, "utf8")).toBe(appHome);
  } finally { rmSync(home, { recursive: true, force: true }); }
});
