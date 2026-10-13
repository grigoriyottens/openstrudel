# OpenStrudel: active work, 13 October 2026

User requests remain active when new questions arrive. Implementation and verification are separate; a build is not product acceptance.

| Request | Implementation | Verification |
| --- | --- | --- |
| Embedded Parakeet dictation: one optional download, automatic language recognition, no language picker or second application | Implemented checkpoint, not release-ready; commit `caf9b97` | Mac mini: 7 focused tests pass, including actual EN/RU/FR/ES audio recognition with automatic language detection after the first model download. Mac first download, cancel/retry and ready state checked earlier. Pending: microphone-to-draft, offline isolation, long recordings and iOS |
| Remove the top Conversations entry; keep employee navigation | Complete for the requested Mac sidebar; merged in PR #24 (`945ee2b`) | Actual Mac sidebar and switching employees checked. Included in source main, not yet in a new distributed app |
| Move an employee to another device from settings or by dragging to its sidebar section | Pending | Pending: two real runtimes, conversations/files/schedules, interrupted transfer, return trip; no duplicate execution |
| Paste a private SSH key as well as choose a file | Implemented | Unit tests and four real loopback SSH tests pass. Native UI selected an encrypted key, verified the host fingerprint, authenticated and correctly rejected the unsupported macOS target. Paste button accepted a replacement key and cleared the previous passphrase |
| Investigate disappearing corporate ChatGPT connection | Investigating | Historical corporate identity is distinct from the personal identity. Exact deletion/replacement event not yet established; no claim of a cause |
| Simpler card checkout for server rental | Researching | Verify actual signup/checkout requirements and current WAI VDS readiness; do not label crypto-only or account-required hosting as card-only checkout |
| WAI Core Team: full Operations access for every partner | Implementation in sibling wai-web worktree; explicit trusted-group delegation with initiating sender audit | Deployed; actual group tool reads and private live-model replay passed |
| Contracts, acceptance acts, invoices, Zoom and Notion handoff for Wolf | Canonical Operations skills expanded; act drafts reuse versioned DOCX workflow | Live bot returned September clauses with page references and delivered the original PDF in private QA. Isolated financial mutation fixtures and Notion scenarios still pending |
| Notion operational cases: cancel lesson, one-off mentor replacement, follow-up | Existing CRM/cancellation paths inspected; one-off mentor substitution needs implementation or a proven existing command | Real reads and isolated write fixtures pending; examples are not orders to alter real lessons/invoices |
| Regression checks and release | Pending | Check latest main and concurrent releases before merging/publishing; verify delivered app separately |
| Telegram messages and answers visible in the app, with clear reply destination and delegation | Visible conversation choices inside each employee chat; existing bounded history API and native Codex delegation retained | Conditional discovery, isolation and remembered selection verified in API/native tests and actual Mac fixture. Pending: real Telegram inbound/reply displayed in the updated app, iOS layout |
| Merge current work to main and remove unnecessary branches immediately, then continue acceptance | Explicit user steering during this continuation | Preserve unmerged commits and branches attached to other chats. Merging source is separate from publishing Sparkle/TestFlight |

## Decisions

- Use Parakeet now, as explicitly requested. Do not add a second model or model selector for Hebrew. Hebrew interface remains supported; dictation does not support Hebrew.
- Ubuntu 24.04 LTS remains the supported automatic setup target. Ubuntu 26.04 exists; the installer currently rejects it. Changing this requires its own installation/recovery validation, not just copy changes.
- Preserve employees at the source until a verified transfer safely changes execution ownership. A failed network reply is not permission to delete data or activate two copies.
- Reuse the existing account identity (person plus workspace). Equal emails are not sufficient to consolidate corporate and personal connections.
- Keep credentials and private diagnostic data out of this document and Git.

## Mac mini continuation

The user requested a handoff on 13 October, before further implementation. The complete continuation prompt is [handoff-mac-mini-2026-10-13.md](handoff-mac-mini-2026-10-13.md). The checkpoint branch is `codex/employee-transfer-dictation`; only the completed sidebar change was merged to main. Do not treat the Parakeet checkpoint or the earlier Apple-recognizer acceptance as completed Parakeet validation.

## Active continuation on Mac mini

- 13 October: fetched origin and checked all worktrees. The primary checkout's unrelated untracked files remain intact.
- Reused the clean attached server-journey-completion checkout for `codex/employee-transfer-dictation` at `e5b4910`. It includes current main `945ee2b`. PR #25 attached to the continuing task.
- Read the entire Mac mini handoff. Preserve its acceptance boundaries: Parakeet is WIP, sidebar removal is merged but not distributed, no new paid server is authorized without a concrete price.
- User clarified that these tasks are additive. Merge/release authorization applies once relevant checks pass; do not discard earlier Operations work.
- Latest group decision: WAI Core Team is a trusted partner group. All its members share the owner's work access, with no per-person onboarding. Preserve the real sender in audit. No automatic access inheritance by unrelated groups or private chats.
- Current independent Operations worktree: `/Users/mikwiseman/Code/.worktrees/wai-operations`, branch `codex/openstrudel-operations`. Its checkpoint and evidence are separate from native WIP.

### Operations checkpoint, 13 October

- `wai-web` commit `f49d978e` is on main and deployed to its documented API origin. Only `waiuni-api` restarted; unchanged web, Zoom and Notion workers remained running. Atomic directory exchange, env backup and automatic failure rollback were used.
- Public MCP in the actual Core Team context exposes 59 tools. Successful real reads: AiGid contract search and exact September provisions with citations, client files, meeting transcript, billing configuration, Notion deals and school tracks.
- Existing Core Team employee instructions retain character and participation rules. The obsolete group finance restriction was replaced by the user's full partner-access decision. Legacy imported binding now accepts all group members.
- Installed Wai Operations 0.4.0 as skills in that group's scope, reusing the existing company MCP. No duplicate service or credentials in prompts.
- Live model replay is running in the existing private QA group (confirmed two members in Telegram), with the same employee and Operations skills. No test messages were sent to Core Team.
- Local rollback: `~/Library/Application Support/OpenStrudelBackups/backup-20261013T130101Z-2472daba`; private evidence stays under the checkout's ignored `.data/operations-2026-10-13`.

- Mac mini Parakeet real-language run passed. First cold recognition ~8.5s; following short RU/FR/ES fixtures ~0.11s. First download + four recognitions ~141s. Log `/tmp/openstrudel-parakeet-mini-tests.log`.
- Removed only the inactive Go object cache (~4.2 GB logical bytes), after checking running compilers and open files. Codex history, source data and active builds were preserved.
- First private model replay found a QA configuration error: a generic static MCP token had no Telegram sender context. Replaced it with the same per-message transport configuration already used by Core Team; a repeat is in progress.

### Verified document delivery and native follow-up

- Wai-Web `a3493aa4` includes the latest concurrent main changes and is deployed. 145 API suites / 2,006 tests pass (8 skipped); TypeScript build passes. Backup: `/var/backups/waiuni-operations/20261013T134018Z`.
- Added a single-file download tool with a ten-minute ticket, current issuer access/session checks, file-version check, private cache headers and path/symlink validation. Real original downloaded successfully (333,871 bytes); no file was made public.
- Private Telegram QA: user request 1678020, Wolf reply 1678021 and actual PDF attachment 1678022. Same Core Team persona. No QA posts in the partner group. Wai Operations 0.4.1 installed in Core and QA through the existing company MCP.
- Five-minute real-audio fixture recognized to its end: 5,091 characters / 72 repeated meeting references in 21–23s, peak resident memory 1,058 MiB on Mac mini. Still pending: actual microphone path, cancellation/offline isolation and iOS.
- Reproduced and fixed late/regressive model-download progress callbacks; regression is red before and green after the fix.
- SSH paste UI and shared key normalization implemented; native tests and real SSH acceptance in progress.
- Found additional product follow-ups: plugin upgrades currently require remove/reinstall; removing an ordinary MCP server can fail during live refresh (invalid transport); CLI services/plugins default root conversation lookup can report employee not found. Preserve these in the remaining-work list.
- Removed ~1.27 GB of closed, reproducible Sparkle/npm/pnpm caches. Active WaiVPN/Go and other app build caches remain intact. Local production backup marked healthy; retention removed nothing.
- Private live-model QA also passed Notion deal lookup and latest AiGid Zoom recording/transcript, with working source links and no business writes (request 1678023, reply 1678025).
- SSH acceptance: ordinary and encrypted pasted keys, wrong password/key/host identity and cancellation pass against a real loopback SSH server. Four tests; log `/tmp/openstrudel-ssh-paste-real-green.log`. Initial fixture incorrectly attempted root on macOS; corrected to the fixture user's account. UI paste/file paths still need acceptance.
- Reproduced MCP removal failure against the real Codex app-server: a loaded thread retained a per-service approval override after that service was removed. Native unsubscribe deliberately defers thread unload, so reload alone still failed. An actual extension mutation now restarts only that idle scoped Codex process, retaining persisted threads and identity state. Regression passes against the real app-server.
- Plugin updates now preview the previous package digest, reject stale previews, preserve disabled state, and roll back package/config/native plugin cache on failure. CLI services/plugins also resolve the root conversation correctly. Focused tests pass, including a native plugin rollback.
- Current server regression: 55 suites / 371 tests pass; TypeScript checking passes. Mac catalogue: 8 tests pass. Mac application builds successfully and the actual isolated window shows Telegram history alongside the employee's app conversation; switching employees and returning preserves the selected conversation.
- This is source integration at the user's explicit request to merge now and continue. Parakeet microphone/offline/iOS acceptance, employee transfers, Operations write fixtures and release delivery remain open. No new Sparkle or TestFlight publication is claimed.
