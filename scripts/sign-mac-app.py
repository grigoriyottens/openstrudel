#!/usr/bin/env python3
"""Sign a packaged app inside out using an already unlocked release keychain."""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=pathlib.Path)
parser.add_argument("--identity", required=True)
parser.add_argument("--keychain", type=pathlib.Path, required=True)
args = parser.parse_args()
app = args.app.resolve()
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if not info["CFBundleIdentifier"].startswith("is.openstrudel.mac"):
    parser.error("Expected an OpenStrudel Mac app")
framework = app / "Contents/Frameworks/Sparkle.framework"
if not framework.is_dir():
    parser.error("Sparkle.framework is missing")


def sign(path, *extra):
    subprocess.run(["codesign", "--force", "--timestamp", "--options", "runtime",
                    "--sign", args.identity, "--keychain", str(args.keychain),
                    *extra, str(path)], check=True)


with tempfile.TemporaryDirectory(prefix="openstrudel-sign-") as temporary:
    entitlements = pathlib.Path(temporary) / "node.plist"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.cs.allow-jit": True}))
    app_entitlements = pathlib.Path(temporary) / "app.plist"
    app_entitlements.write_bytes(plistlib.dumps({"com.apple.security.device.audio-input": True}))
    runtime = app / "Contents/Resources/Runtime"
    for path in sorted(runtime.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        # Only native code requires a signature; scripts/data retain their bytes.
        with path.open("rb") as file:
            magic = file.read(4)
        if magic not in [b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"]:
            continue
        extra = ["--entitlements", str(entitlements)] if path.name in ["node", "codex-code-mode-host"] else []
        # Claude Code is a Bun binary: keep the JIT entitlements its vendor signed it with.
        if path.parent.name == "claude-agent-sdk-darwin-arm64" and path.name == "claude":
            extra = ["--preserve-metadata=entitlements"]
        sign(path, *extra)

    version = framework / "Versions/B"
    sign(version / "XPCServices/Installer.xpc")
    sign(version / "XPCServices/Downloader.xpc", "--preserve-metadata=entitlements")
    sign(version / "Autoupdate")
    sign(version / "Updater.app")
    for embedded in sorted((app / "Contents/Frameworks").glob("*.framework")):
        sign(embedded)
    # Xcode's Debug layout loads these before entering the application.
    for library in sorted((app / "Contents/MacOS").glob("*.dylib")):
        sign(library)
    sign(app, "--entitlements", str(app_entitlements))

subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
