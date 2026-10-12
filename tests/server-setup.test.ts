import { afterEach, describe, expect, it } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const script = resolve("scripts/server-setup.sh");
const roots: string[] = [];
const quote = (s: string) => "'" + s.replaceAll("'", "'\\''") + "'";
function fixture() {
  const root = mkdtempSync(join(tmpdir(), "strudel-server-setup-")); roots.push(root);
  mkdirSync(join(root, "bin"));
  writeFileSync(join(root, "bin/docker"), "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  const privateKeyPEM = generateKeyPairSync("ec", { namedCurve: "prime256v1", privateKeyEncoding: { type: "pkcs8", format: "pem" }, publicKeyEncoding: { type: "spki", format: "pem" } }).privateKey;
  const payload = { installationId: "438425ea-61bb-4ac0-bb4e-1b556bf05bba", host: "server.example.com", privateKeyPEM, ownerTokenHash: "a".repeat(64), releaseHash: "b".repeat(64), installer: Buffer.from("#!/usr/bin/env bash\ntrue\n").toString("base64") };
  return { root, payload };
}
function shell(root: string, action: string, payload?: unknown) {
  return spawnSync("bash", ["-c", `source ${quote(script)}\nexport PATH=${quote(join(root, "bin"))}:$PATH\nSETUP_STATE_DIR=${quote(join(root, "state"))}\nSETUP_INSTALL_ROOT=${quote(join(root, "home"))}\n${action}`], { encoding: "utf8", input: payload === undefined ? undefined : JSON.stringify(payload), timeout: 15_000 });
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

describe("Server setup over SSH", () => {
  it("stages the same identity idempotently without logging credentials", () => {
    const { root, payload } = fixture();
    for (let attempt = 0; attempt < 2; attempt++) {
      const result = shell(root, "stage_setup", payload);
      expect(result.status, result.stderr).toBe(0);
      expect(result.stdout + result.stderr).not.toContain(payload.privateKeyPEM);
      expect(result.stdout + result.stderr).not.toContain(payload.ownerTokenHash);
    }
    expect(readFileSync(join(root, "state/installation-id"), "utf8").trim()).toBe(payload.installationId);
    expect(JSON.parse(readFileSync(join(root, "state/bootstrap.json"), "utf8")).privateKeyPEM).toBe(payload.privateKeyPEM);
    expect(readFileSync(join(root, "state/connection-host"), "utf8")).toBe(payload.host);
  });
  it("refuses a different installation or changed recipe before overwriting data", () => {
    const { root, payload } = fixture();
    expect(shell(root, "stage_setup", payload).status).toBe(0);
    const original = readFileSync(join(root, "state/bootstrap.json"));
    for (const changed of [{ ...payload, installationId: "238425ea-61bb-4ac0-bb4e-1b556bf05bba" }, { ...payload, ownerTokenHash: "c".repeat(64) }, { ...payload, releaseHash: "c".repeat(64) }]) {
      expect(shell(root, "stage_setup", changed).status).not.toBe(0);
      expect(readFileSync(join(root, "state/bootstrap.json"))).toEqual(original);
    }
  });
  it("preserves an unrelated installation and does not adopt a public staging directory", () => {
    const { root, payload } = fixture();
    mkdirSync(join(root, "home")); writeFileSync(join(root, "home/user-data"), "keep");
    expect(shell(root, "stage_setup", payload).status).not.toBe(0);
    expect(readFileSync(join(root, "home/user-data"), "utf8")).toBe("keep");
    expect(existsSync(join(root, "state/installation-id"))).toBe(false);
    rmSync(join(root, "home"), { recursive: true });
    mkdirSync(join(root, "state"), { recursive: true }); chmodSync(join(root, "state"), 0o755);
    expect(shell(root, "stage_setup", payload).status).not.toBe(0);
  });
  it("refuses a server with other containers before staging or changing the host", () => {
    const { root, payload } = fixture();
    writeFileSync(join(root, "bin/docker"), "#!/bin/sh\nprintf 'existing-user-container\\n'\n", { mode: 0o700 });
    const result = shell(root, `export PATH=${quote(join(root, "bin"))}:$PATH\nstage_setup`, payload);
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("OPENSTRUDEL_SHARED");
    expect(existsSync(join(root, "state/installation-id"))).toBe(false);
  });
  it("resumes an interrupted atomic staging write only inside its own private directory", () => {
    const { root, payload } = fixture();
    mkdirSync(join(root, "state"), { mode: 0o700 });
    writeFileSync(join(root, "state/installation-id"), payload.installationId + "\n");
    writeFileSync(join(root, "state/.bootstrap.json.new"), "interrupted");
    expect(shell(root, "stage_setup", payload).status).toBe(0);
    expect(JSON.parse(readFileSync(join(root, "state/bootstrap.json"), "utf8")).installationId).toBe(payload.installationId);
  });
  it("refuses symlink staging paths without modifying the destination", () => {
    const { root, payload } = fixture();
    mkdirSync(join(root, "other"), { mode: 0o700 });
    symlinkSync(join(root, "other"), join(root, "state"));
    expect(shell(root, "stage_setup", payload).status).not.toBe(0);
    expect(existsSync(join(root, "other/bootstrap.json"))).toBe(false);
  });
  it.each(["example.com\nOTHER=value", "-option", "example.com/path", "a;whoami", "999.1.2.3"])("rejects an unsafe advertised host %s before creating state", host => {
    const { root, payload } = fixture();
    expect(shell(root, "stage_setup", { ...payload, host }).status).not.toBe(0);
    expect(existsSync(join(root, "state"))).toBe(false);
  });
  it("returns a bounded compatibility result without installing anything", () => {
    const { root } = fixture();
    const result = shell(root, "check_server");
    expect(result.status, result.stderr).toBe(0);
    const check = JSON.parse(result.stdout);
    expect(typeof check.os).toBe("string");
    expect(typeof check.existing).toBe("boolean");
    expect(existsSync(join(root, "state"))).toBe(false);
  });
});
