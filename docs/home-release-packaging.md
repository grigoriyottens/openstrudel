# Home release packaging

Package a committed revision with the repository helper:

```sh
python3 scripts/package-home.py --ref COMMIT --output /path/to/new/OpenStrudel-Home-VERSION.tar.gz
npm test -- tests/home-release.test.ts tests/cloud-init.test.ts tests/server-installer.test.ts
```

Both installers require a single `OpenStrudel-Home/` directory. A plain `git archive` without this prefix is not an installable Home release. The helper includes only committed release inputs, checks archive types, size and required files, and refuses to overwrite an existing artifact. Its test extracts the actual generated archive with both installers, then compares critical files to the requested commit.

Before publication, run both extractors against the final artifact as well. Preserve the archive, source revision and SHA-256. Upload under a new immutable filename, verify the public download, and only then update the current Home alias and `SHA256SUMS` with a retained rollback copy. Do not change the Mac archive or Sparkle feed for a Home-only packaging correction.

Acceptance must install the newly published archive on a clean supported server, not an earlier Home release. Confirm authenticated HTTPS from the Mac app, remote assistant persistence and recovery after restarting the server. A successful download or Docker build is insufficient.

An interrupted installation pins its original release digest. Changing the public alias does not repair that pending attempt. Never silently replace its identity, checksum or existing data to call it recovered. Record a clean-install retest separately from a recovery test.
