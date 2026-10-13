# Build 36: server setup and connection recovery

The server setup flow now finishes with ChatGPT sign-in and a clear action to create an assistant on that server. Both existing-server and DigitalOcean routes use the same final step. An interrupted installation retains its saved identity; a matching failed download can retry a corrected Home package without replacing the owner or an installed Home.

Saved connections distinguish unavailable Keychain access from a disconnected server. An explicit Unlock connection action recovers the existing credential off the main thread, retaining drafts and history. New assistant names and setup notices follow the selected interface language; imported-name collisions use a numeric suffix.

## Published delivery

[PR #18](https://github.com/mikwiseman/openstrudel/pull/18) is merged. Build 36 was built from main commit `1ed928817b3836ddf9468b39d42a34db5064067c` and published on 13 October 2026.

| Surface | Verified result |
| --- | --- |
| macOS | Developer ID signed; app and DMG accepted by Apple notarization, stapled, and accepted by Gatekeeper |
| Sparkle | Signed feed and immutable DMG published; public download hashes verified; an isolated build 33 downloaded, installed and relaunched as 36 |
| Mac mini | Production app and Home updated with a consistent rollback snapshot and atomic app exchange; native history, device, account and Telegram screens verified |
| Home package | Versioned archive and stable download alias published and verified |
| App Review server | Updated from 35 to 36 with an independent volume and retained rollback container; identity, TLS certificate, settings, account and records preserved |
| iOS | Archive signed and uploaded; Apple processing is `VALID`, with build 36 `IN_BETA_TESTING` for the existing internal group |
| Public App Store review | Build 34 remains `WAITING_FOR_REVIEW`; the pending submission was not replaced |

Downloads: [Mac 36](https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-36-arm64.dmg), [Home 36](https://waiwai.is/openstrudel/downloads/OpenStrudel-Home-1.0-36.tar.gz), [Sparkle feed](https://waiwai.is/openstrudel/updates/appcast.xml).

- Mac DMG SHA-256: `ddd575602415a35997a18042c6d6de7fca0191491c473aad4e5fbcb4ab7d95f1`.
- Home archive SHA-256: `25243b74523e0af6c6ec928fc572d958edfcb019b4bd8c57ecaf4de24cc8802a`.

## Validation

- TypeScript typecheck passed.
- 93 targeted runtime, packaging, installer, store and archive tests passed.
- 163 native tests in 24 suites passed on the release-numbered source.
- The existing full runtime run passed 356 tests; source changes since that run are documented UI recovery labels and the release number.
- The native QA app reconnected to the existing paid server and displayed its 16 assistants, Server Desk history and verified attachment. Earlier live file creation, reading, app relaunch and deliberate service interruption remain documented in the server-journey report.

- Mac mini retained all 6 employee records, 15 conversations, 1,930 messages and 3 schedules. Profile, Telegram binding, schedule and account configuration checks passed; four connected accounts remained available. The Telegram connection check and a polling cycle passed without sending messages to a group.
- A consistent copy of the production database passed the new runtime's migration, SQLite integrity and foreign-key checks with unchanged record IDs before deployment. The rollback snapshot was marked healthy only after native UI verification.
- The App Review Home preserved its 2 employees, 3 conversations and 53 existing messages. Its real Codex sandbox allowed a workspace read and denied a private file. A real model turn called the terminal tool, calculated `17 × 23`, and returned `OPENSTRUDEL_36_READY_391`; the session contained the corresponding tool output.
- A bounded native check alternated 20 times between histories containing 1,110 and 599 messages. Process RSS was 53.2 MiB before, 35.2 MiB immediately after, and 65.7 MiB at the final observation several minutes later. This short resident-memory observation does not diagnose the historical 30–40 GB report or measure total memory across every process.

Private signing, publication, TestFlight, deployment and test receipts are under `.data/release/2026-10-13-36/`. No account credentials or connection links are included in this report.

## Remaining acceptance

The subsequent [Mac 39 acceptance](2026-10-13-local-network.md) closes clean-OS installation, fresh native ChatGPT sign-in and server-side retry of the preserved failed Home 35 recipe. Provider API access was recovered through the documented WAI VDS host. The [current queue](../remaining-work-2026-10-12.md) records QA retirement and remaining boundaries. The proposed portable dictation engine has not replaced Apple dictation; physical-device, natural-speech and extended native memory checks remain separately scoped.
