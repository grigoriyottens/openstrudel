#!/usr/bin/env python3
"""Package committed Home sources in the format required by both installers."""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", required=True, help="Committed source revision")
    parser.add_argument("--output", required=True, type=Path, help="New .tar.gz file")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", args.ref + "^{commit}"], cwd=repo, text=True
    ).strip()
    if args.output.exists():
        parser.error("Output already exists; published releases must not be overwritten")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".home-package-", dir=args.output.parent) as temporary:
        archive = Path(temporary) / "Home.tar.gz"
        # Only committed release inputs, never the working tree or local state.
        subprocess.run([
            "git", "archive", "--format=tar.gz", "--prefix=OpenStrudel-Home/", "--output=" + str(archive.resolve()), revision, "--",
            ".dockerignore", ".env.example", "AGENTS.md", "Dockerfile", "README.md", "deploy", "docs", "licenses",
            "package-lock.json", "package.json", "public", "scripts", "src", "tsconfig.json",
        ], cwd=repo, check=True)
        with tarfile.open(archive) as contents:
            members = contents.getmembers()
            if len(members) > 10_000 or sum(m.size for m in members) > 100_000_000:
                raise ValueError("Release exceeds the installer's archive limits")
            for member in members:
                path = PurePosixPath(member.name)
                if (path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "OpenStrudel-Home"
                        or any(p in (".data", ".env", "auth.json") for p in path.parts)
                        or not (member.isfile() or member.isdir())):
                    raise ValueError("Unsafe release archive entry")
            for required in ("Dockerfile", "package.json", "package-lock.json", "tsconfig.json", "src/cloud-bootstrap.ts",
                             "deploy/compose.yaml", "deploy/docker/openstrudel.apparmor", "deploy/docker/seccomp.json",
                             "scripts/container-start.sh", "scripts/check-sandbox.mjs", "licenses/Grok-LICENSE.txt",
                             "licenses/Grok-THIRD_PARTY_NOTICES.md"):
                if not contents.getmember("OpenStrudel-Home/" + required).isfile():
                    raise ValueError("Missing release input: " + required)
        # Atomic publication of the completed local artifact, refusing collisions.
        os.link(archive, args.output)
    print(hashlib.sha256(args.output.read_bytes()).hexdigest() + "  " + str(args.output))
    print("Source: " + revision)


if __name__ == "__main__":
    main()
