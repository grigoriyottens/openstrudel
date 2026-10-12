import { afterEach, expect, it } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

it("packages a committed Home release that both shipped installers can extract", () => {
  const root = mkdtempSync(join(tmpdir(), "strudel-release-")); roots.push(root);
  const archive = join(root, "Home.tar.gz");
  const packed = spawnSync("python3", ["scripts/package-home.py", "--ref", "HEAD", "--output", archive], { encoding: "utf8" });
  expect(packed.status, packed.stderr).toBe(0);
  for (const [script, fn] of [["cloud-init.sh", "extract_archive"], ["install-server.sh", "extract_release"]]) {
    const destination = join(root, script!);
    const extracted = spawnSync("bash", ["-c", 'source "$1"; "$2" "$3" "$4"', "test", resolve("scripts", script!), fn!, archive, destination], { encoding: "utf8" });
    expect(extracted.status, extracted.stderr).toBe(0);
    for (const file of ["Dockerfile", "deploy/compose.yaml", "scripts/container-start.sh", "scripts/check-sandbox.mjs", "src/cloud-bootstrap.ts", "package-lock.json"]) {
      expect(readFileSync(join(destination, "OpenStrudel-Home", file))).toEqual(execFileSync("git", ["show", `HEAD:${file}`]));
    }
  }
  const original = readFileSync(archive);
  expect(spawnSync("python3", ["scripts/package-home.py", "--ref", "HEAD", "--output", archive]).status).not.toBe(0);
  expect(readFileSync(archive)).toEqual(original);
}, 30_000);
