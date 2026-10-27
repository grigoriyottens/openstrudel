# Local build and rollback storage

- Use `python3 scripts/native-build.py -- <xcodebuild arguments>` for native builds and tests. Run XcodeGen first when project configuration changes. The wrapper manages `-project` and `-derivedDataPath`; do not create a fresh DerivedData under each dated `.data` run.
- DerivedData lives in `~/Library/Caches/OpenStrudelBuilds/derived/<checkout-id>`. Each checkout reuses its stable directory; a file lock serializes builds of that checkout. Different worktrees stay independent. After builds, marked caches unused for 7 days are eligible for deletion. Above a soft 12 GiB budget, unused caches older than 24 hours are eligible. Active/open caches are retained. `--prune` runs just this maintenance.
- Keep release `.xcarchive`, dSYM, signed packages, and required test results outside DerivedData, with explicit `-archivePath` / `-resultBundlePath`. They are not cache-pruning targets. Keep private state and handoffs out of the cache root.
- Before signing, packaging or installing an app, use the wrapper's `--copy-product <relative-product-path> <new-staging-destination>` option before `--`. It snapshots the product under the build lock. Package/sign that staged copy so later builds cannot modify it.
- Before a local production update, use `python3 scripts/backup-local-state.py` for the rollback snapshot. It stores user state, consistent SQLite backups, the installed app and launch configuration in `~/Library/Application Support/OpenStrudelBackups`, excluding old deployment trees and reproducible runtime files. Quiesce application writes when a consistent snapshot across multiple files is required.
- After the updated service passes its health and data checks, run `python3 scripts/backup-local-state.py --mark-healthy <backup-path>`. This retains the latest two managed rollback snapshots from healthy deployments. Pending or foreign backups are not automatically deleted. Never copy the entire old deployment/backup tree into another backup.
- Never automatically delete or rewrite Codex chat history, user databases, private exports or unique project data as part of disk maintenance. Preserve the existing deployment validation, signing, atomic installation and rollback sequence.

# Published installers on WaiWeb

- WaiWeb shares one 40 GB disk with PostgreSQL and the meeting pipeline. On 23 October 2026 old OpenStrudel installers filled it and PostgreSQL crashed.
- Keep only the latest build there: its versioned DMG and Home archive, the stable `OpenStrudel-1.0-arm64.dmg` and `OpenStrudel-Home-1.0.tar.gz` as hard links to them, the latest APK, `SHA256SUMS` listing only those files, and the signed `updates/appcast.xml`.
- Every release ends by deleting the previous build's installers and every staging and backup directory it created on WaiWeb (step 8 of [docs/mac-release.md](docs/mac-release.md)). Rollback packages stay on the release Mac.

# App Review access

- The active App Store submission depends on the isolated review Home and HTTPS route at `magic.mikwiseman.com/openstrudel-review/`. A host reinstall removed them once while review was pending.
- Preserve its external data volume, setup code, Home TLS key and proxy route across updates. Follow [the review deployment runbook](deploy/review/README.md); check the original URL externally and an already paired device before considering an update complete.
