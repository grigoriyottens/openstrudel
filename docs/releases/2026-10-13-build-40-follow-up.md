# Build 40 delivery and MacBook follow-up

Verified on 13 October 2026 after resuming the Mac mini work on the MacBook. Starting source: main `e0c909a03a5203f8c443ec76dea2b71150f6b9af`, containing PRs #25–27. The primary MacBook checkout was fast-forwarded from `1b17617`; unrelated untracked files were preserved. Follow-up changes use a separate worktree.

## Delivered artifacts

| Surface | Fresh verification |
| --- | --- |
| Mac/Sparkle | Public feed offers 1.0 (40). Downloaded DMG matches the signed enclosure length, Ed25519 signature and SHA-256. App has bundle version 40; strict nested signature verification, Gatekeeper notarized Developer ID assessment and stapled DMG validation pass |
| Installed Mac | Actual Sparkle 39 → 40 download, Install and Relaunch completed. Top Conversations control is gone; existing local/remote employees and Telegram source choices are visible |
| Home | Public stable archive matches all 147 tracked packaged source files at the source revision above |
| iOS | App Store Connect build 40 (`0a410dec-d3d6-406c-abc5-7764accafaaa`) is `VALID`; its build beta detail reports `IN_BETA_TESTING` internally |
| Public App Store | Version 1.0 still selects build 34, `WAITING_FOR_REVIEW`. The pending submission was not replaced |

- [Mac 40 DMG](https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-40-arm64.dmg): 219,069,693 bytes; SHA-256 `d29437fe254753591dfaa6063686a1ec3d8c4fca2f7458dca77487ac4f2fc005`.
- [Home stable archive](https://waiwai.is/openstrudel/downloads/OpenStrudel-Home-1.0.tar.gz), as read during this check: SHA-256 `4c9132ed7acc977b4df36817ee7bf7c06d2054850f7e1ee8fb33339930501ab3`. This alias can change; do not use its current bytes to repair an older pinned installation implicitly.
- Installed bundled runtime release digest: `9d08f5911ce7f676c0253a0b2d168a4e4a4caebcff35060ae7a6e62fb3818a49`.

Internal TestFlight availability is not external beta approval or App Store publication. This continuation did not repeat every acceptance run recorded on the Mini.

## Two defects found during the update

### Local runtime stayed old when a remote employee was selected

After Sparkle updated the UI, the local launch agent still referenced the previous runtime digest and `/health` did not advertise employee transfers. The selected chat belonged to another device. Root startup called `startLocalHome()` only when the active client was local, so the existing runtime reconciliation never ran.

`DeviceLibrary.localClientToRestore` now finds the saved managed local connection independently of the selected employee. Startup uses it without changing the selected device. Signed-out/unauthenticated clients, pairing attempts, unrelated loopback endpoints and local erase remain excluded.

The regression fails under the old selection rule and passes with the fix. All 12 DeviceLibrary tests pass. Three existing Mac installer tests also pass, covering release-change restart and preserved installation behavior. The application was compiled by the native build wrapper.

This Mac's already installed runtime was reconciled through its bundled installer. Live health now reports `employeeTransferVersion: 1` and `agentArchiveVersion: 1`; the launch agent digest matches the installed app. SQLite integrity and the existing one local employee/six messages were preserved. The permanent startup fix is newer than public build 40; a new signed distribution and automatic-update replay remain necessary.

### Rollback backup copied a reproducible dictation model

The first real backup failed with no space left while copying the downloaded Parakeet weights. The backup helper now excludes only `Dictation/parakeet-v3-q8.gguf`; it retains recordings and custom models. The original model remains available to the app. The new regression fails before the fix; all 12 storage tests pass afterward.

A complete replacement rollback snapshot was created before updating, with 23 successful SQLite integrity checks. It was marked healthy only after the app/runtime and data checks; the standard retention policy removed the oldest managed healthy snapshot. The failed partial snapshot's user data was preserved. Only its incomplete downloadable model copy was removed.

## Remaining boundaries

- The actual Mac drag gesture remains unverified: the CUA gesture does not invoke the source provider even in the previously tested minimal SwiftUI fixture. Context-menu/settings transfer and isolated round-trip/recovery acceptance remain the proven paths. No production employee was moved for this inspection.
- The Mini is visible and online through its saved public app connection. The current MacBook environment cannot resolve its SSH alias or read its remote Codex thread; online app connectivity does not imply those management routes are available.
- Live WAI VDS still disables purchases and supplies no payable amount. Its profile pins `2d2276516882aee51f79c003320ac226101f3291c1d365f25b03b520ef516a69` against the mutable Home alias, which no longer matches. Agree on a versioned artifact and profile before enabling payment; do not weaken integrity checks. The native protocol client is not a completed checkout UI.
- One-off mentor changes already exist in wai-web main (`25d33df0`). Exact deployment and live private replay were not confirmed here. Preserve the independent Operations work rather than duplicating it.
- Physical iPhone microphone/camera, fresh Google authorization, broad WAN/assistive-technology coverage and the next public App Store materials remain separate checks.
- Active Claude design worktrees contain additional unmerged changes. Their UI work is not included in this build or this acceptance claim.
- Sparkle 40 embeds Russian notes. Use English for the next signed feed generation; never edit the signed XML directly.

Private evidence is under the continuation worktree's ignored `.data/resume-2026-10-13/`; rollback snapshots are under `~/Library/Application Support/OpenStrudelBackups`. Credentials, personal transcripts and private reviewer links are excluded from Git. The full current queue is [current work](../current-work-2026-10-13.md).
