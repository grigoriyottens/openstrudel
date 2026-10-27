#!/usr/bin/env bash
# Bundled with the Mac app. The caller invokes one function over pinned SSH.
# Setup payloads arrive on stdin, never as shell arguments or log messages.
set -euo pipefail
umask 077
SETUP_STATE_DIR=/var/lib/openstrudel-cloud
SETUP_INSTALL_ROOT=/opt/openstrudel-home

check_server() {
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' '{"os":"unknown","version":"","architecture":"","memoryMiB":0,"diskGiB":0,"freeGiB":0,"administrator":false,"python":false,"installationID":null,"existing":false,"portBusy":false}'
    return
  fi
  python3 - "$SETUP_STATE_DIR" "$SETUP_INSTALL_ROOT" <<'PY'
import json, os, pathlib, platform, shutil, subprocess, sys
system = {}
path = pathlib.Path('/etc/os-release')
if path.exists():
    for line in path.read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep: system[key] = value.strip('"')
admin = os.geteuid() == 0
if not admin and shutil.which('sudo'):
    admin = subprocess.run(['sudo', '-n', 'true'], capture_output=True).returncode == 0
def privileged(args):
    return subprocess.run(args if os.geteuid() == 0 else ['sudo', '-n'] + args, capture_output=True, text=True, timeout=10)
mem = pathlib.Path('/proc/meminfo')
memory = next((int(line.split()[1]) // 1024 for line in mem.read_text().splitlines() if line.startswith('MemTotal:')), 0) if mem.exists() else 0
disk = shutil.disk_usage('/var' if pathlib.Path('/var').exists() else '/')
identity = None
existing = any(p.exists() for p in [pathlib.Path(sys.argv[2]), pathlib.Path.home() / 'OpenStrudel-Home'])
runtime = True
shared = False
if admin:
    result = privileged(['cat', str(pathlib.Path(sys.argv[1]) / 'installation-id')])
    if result.returncode == 0: identity = result.stdout.strip()
    if shutil.which('docker'):
        all_containers = privileged(['docker', 'ps', '-aq'])
        shared = bool(all_containers.stdout.strip()) and identity is None
        result = privileged(['docker', 'ps', '-a', '--filter', 'label=com.docker.compose.project=openstrudel', '--format', '{{.ID}}'])
        existing = existing or bool(result.stdout.strip())
        result = privileged(['docker', 'volume', 'ls', '--filter', 'label=com.docker.compose.project=openstrudel', '--format', '{{.Name}}'])
        existing = existing or bool(result.stdout.strip())
        result = privileged(['docker', 'version', '--format', '{{.Server.Version}}'])
        runtime = result.returncode == 0 and result.stdout.strip().split('.')[0].isdigit() and int(result.stdout.strip().split('.')[0]) >= 29
        runtime = runtime and privileged(['docker', 'compose', 'version']).returncode == 0
busy = False
if shutil.which('ss'):
    result = subprocess.run(['ss', '-H', '-ltn', 'sport = :7789'], capture_output=True, text=True)
    busy = bool(result.stdout.strip())
print(json.dumps(dict(os=system.get('ID', platform.system().lower()), version=system.get('VERSION_ID',''), architecture=platform.machine(), memoryMiB=memory, diskGiB=disk.total//2**30, freeGiB=disk.free//2**30, administrator=admin, python=True, installationID=identity, existing=existing, portBusy=busy, runtimeCompatible=runtime, sharedRuntime=shared)))
PY
}

stage_setup() {
  # This staging directory is separate from all user data. The identity and
  # recipe are checked before an existing file can be reused.
  python3 -c '
import base64, fcntl, ipaddress, json, os, pathlib, re, shutil, subprocess, sys, uuid
payload = json.load(sys.stdin)
identity = str(uuid.UUID(payload["installationId"]))
host = payload["host"]
if not isinstance(host, str) or len(host) > 253 or not all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", part) for part in host.split(".")): raise ValueError("Invalid host")
if all(c in "0123456789." for c in host): ipaddress.IPv4Address(host)
if not all(re.fullmatch(r"[a-f0-9]{64}", payload[k]) for k in ["ownerTokenHash", "releaseHash"]): raise ValueError("Invalid digest")
# The versioned archive behind the hash. A recipe saved before it was pinned has none.
release_file = payload.get("releaseFile")
if release_file is not None and not (isinstance(release_file, str) and re.fullmatch(r"OpenStrudel-Home-1\.0-[0-9]+(\.[0-9]+)?\.tar\.gz", release_file)): raise ValueError("Invalid release file")
installer = base64.b64decode(payload["installer"], validate=True)
if len(installer) > 60000 or not installer.startswith(b"#!/usr/bin/env bash\n"): raise ValueError("Invalid installer")
root = pathlib.Path(sys.argv[1])
installation = pathlib.Path(sys.argv[2])
if not (root / "installation-id").exists() and shutil.which("docker"):
    containers = subprocess.run(["docker", "ps", "-aq"], capture_output=True, text=True, timeout=10)
    if containers.returncode or containers.stdout.strip(): raise ValueError("OPENSTRUDEL_SHARED")
if not (root / "installation-id").exists() and (installation.exists() or installation.is_symlink()): raise ValueError("OPENSTRUDEL_EXISTING")
if root.is_symlink(): raise ValueError("OPENSTRUDEL_EXISTING")
root.mkdir(mode=0o700, exist_ok=True)
if root.stat().st_uid != os.geteuid() or root.stat().st_mode & 0o077: raise ValueError("OPENSTRUDEL_EXISTING")
lock = os.open(str(root / "setup.lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
marker = root / "installation-id"
if marker.exists() or marker.is_symlink():
    if marker.is_symlink() or marker.read_text().strip() != identity: raise ValueError("OPENSTRUDEL_EXISTING")
else:
    if any((root / p).exists() or (root / p).is_symlink() for p in ["bootstrap.json", "install.sh", "complete"]) or installation.exists(): raise ValueError("OPENSTRUDEL_EXISTING")
    temporary = root / ".installation-id.new"
    if temporary.is_symlink(): raise ValueError("OPENSTRUDEL_EXISTING")
    if temporary.exists(): temporary.unlink()
    descriptor = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as out: out.write(identity + "\n"); out.flush(); os.fsync(out.fileno())
    # Publish the complete identity without replacing any existing marker.
    # A stopped write must never leave an empty identity blocking safe replay.
    os.link(temporary, marker)
    temporary.unlink()
bootstrap = json.dumps({k:payload[k] for k in ["installationId", "privateKeyPEM", "ownerTokenHash"]}, sort_keys=True).encode()
files = [("bootstrap.json", bootstrap, 0o600), ("release.sha256", payload["releaseHash"].encode(), 0o600), ("connection-host", host.encode(), 0o600), ("install.sh", installer, 0o700)]
if release_file is not None: files.insert(2, ("release.file", release_file.encode(), 0o600))
release_names = ["release.sha256", "release.file", "install.sh"]
changed = [name for name, content, mode in files if (root / name).is_file() and (root / name).read_bytes() != content]
replace_release = False
previous = payload.get("previousReleaseHash")
if changed and (previous or changed == ["install.sh"]):
    if previous is not None and (not isinstance(previous, str) or not re.fullmatch(r"[a-f0-9]{64}", previous)): raise ValueError("OPENSTRUDEL_EXISTING")
    # An explicit retry may update a failed download, or the installer bundled
    # with a newer app for the same release, never a running service or an
    # installed Home. Keep the same bootstrap, owner and host throughout.
    attempt_lock = os.open(str(root / "attempt.lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    fcntl.flock(attempt_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    state = subprocess.run(["systemctl", "show", "openstrudel-install.service", "--property=ActiveState", "--value"], capture_output=True, text=True, timeout=10)
    if state.returncode or state.stdout.strip() != "failed" or installation.exists() or installation.is_symlink() or (root / "complete").exists() or (root / "complete").is_symlink(): raise ValueError("OPENSTRUDEL_EXISTING")
    if any(name not in release_names for name in changed): raise ValueError("OPENSTRUDEL_EXISTING")
    if (root / "release.sha256").read_text().strip() not in [previous, payload["releaseHash"]]: raise ValueError("OPENSTRUDEL_EXISTING")
    replace_release = True
# Validate the entire recipe before completing any interrupted write.
for name, content, mode in files:
    file = root / name
    if file.is_symlink() or (file.exists() and file.read_bytes() != content and not (replace_release and name in release_names)): raise ValueError("OPENSTRUDEL_EXISTING")
for name, content, mode in files:
    file = root / name
    if not file.exists() or (replace_release and name in changed):
        temporary = root / ("." + name + ".new")
        # A killed write can leave this known temporary file. The matching
        # installation owns this private directory and the lock is held.
        if temporary.is_symlink(): raise ValueError("OPENSTRUDEL_EXISTING")
        if temporary.exists(): temporary.unlink()
        descriptor = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
        with os.fdopen(descriptor, "wb") as out: out.write(content); out.flush(); os.fsync(out.fileno())
        os.rename(temporary, file)
' "$SETUP_STATE_DIR" "$SETUP_INSTALL_ROOT"
}

install_server() {
  [[ "$(id -u)" == 0 ]] || return 1
  stage_setup
  # A deliberate retry renews the attempt budget only after a failed unit.
  # A running installation keeps its budget and is never started twice.
  if [[ "$(systemctl show openstrudel-install.service --property=ActiveState --value 2>/dev/null)" == failed ]]; then
    (
      flock -n 8 || exit 1
      printf '0\n' > "$SETUP_STATE_DIR/attempts.new"
      mv "$SETUP_STATE_DIR/attempts.new" "$SETUP_STATE_DIR/attempts"
    ) 8>"$SETUP_STATE_DIR/attempt.lock"
    systemctl reset-failed openstrudel-install.service
  fi
  /bin/bash "$SETUP_STATE_DIR/install.sh" --install-service
}

server_status() {
  python3 - "$SETUP_STATE_DIR" "$SETUP_INSTALL_ROOT" <<'PY'
import json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
def text(name):
    path = root / name
    return path.read_text().strip() if path.is_file() and not path.is_symlink() else None
result = subprocess.run(['systemctl', 'show', 'openstrudel-install.service', '--property=ActiveState', '--value'], capture_output=True, text=True)
state = result.stdout.strip()
if text('complete') == 'complete': state = 'complete'
installation = pathlib.Path(sys.argv[2])
canUpdateRelease = state == 'failed' and not installation.exists() and not installation.is_symlink() and text('complete') is None
print(json.dumps(dict(installationID=text('installation-id'), state=state, stage=text('stage') or 'dependencies', canUpdateRelease=canUpdateRelease)))
PY
}
