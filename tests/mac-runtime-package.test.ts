import { expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// Exercise the finished bundle, including after signing. A successful Xcode
// build cannot detect a Node executable that depends on the builder's Homebrew.
const app = process.env.OPENSTRUDEL_PACKAGED_APP;
it.skipIf(process.platform !== "darwin" || !app)("runs the packaged Home without the build machine's libraries or tools", () => {
  const runtime = resolve(app!, "Contents/Resources/Runtime");
  const node = join(runtime, "bin/node");
  const architectures = (path: string) => execFileSync("/usr/bin/lipo", ["-archs", path], { encoding: "utf8" }).trim();
  expect(architectures(node)).toBe(architectures(resolve(app!, "Contents/MacOS/OpenStrudel")));
  const libraries = execFileSync("/usr/bin/otool", ["-L", node], { encoding: "utf8" }).trim().split("\n").slice(1);
  expect(libraries.length).toBeGreaterThan(0);
  for (const library of libraries) {
    expect(library.trim(), "Packaged Node must depend only on macOS libraries").toMatch(/^\/(System\/Library|usr\/lib)\//);
  }
  const fixture = mkdtempSync(join(tmpdir(), "strudel-packaged-node-"));
  const env = { HOME: fixture, PATH: "/usr/bin:/bin:/usr/sbin:/sbin", LANG: "en_US.UTF-8" };
  try {
    const output = execFileSync(node, ["--input-type=module", "-e", `
      import { DatabaseSync } from 'node:sqlite';
      import { createHash } from 'node:crypto';
      const db = new DatabaseSync(':memory:');
      console.log(JSON.stringify({ answer: db.prepare('select 42 as value').get().value,
        digest: createHash('sha256').update('OpenStrudel').digest('hex'), version: process.versions.node }));
      db.close();
    `], { env, encoding: "utf8", timeout: 10_000 });
    expect(JSON.parse(output)).toMatchObject({ answer: 42, digest: expect.stringMatching(/^[0-9a-f]{64}$/) });
    const launchAgent = join(fixture, "prepared.plist");
    execFileSync(node, [join(runtime, "scripts/mac-launch-agent.mjs"), runtime, fixture, launchAgent], { env, timeout: 10_000 });
    const plist = JSON.parse(execFileSync("/usr/bin/plutil", ["-convert", "json", "-o", "-", launchAgent], { encoding: "utf8" }));
    expect(plist.ProgramArguments).toEqual([node, join(runtime, "dist/cli.js"), "start"]);
    expect(plist.OpenStrudelRuntimeVersion).toBe(readFileSync(join(runtime, "release.txt"), "utf8").trim());
  } finally { rmSync(fixture, { recursive: true, force: true }); }
});
