# OpenStrudel: active work, 13 October 2026

User requests remain active when new questions arrive. Implementation and verification are separate; a build is not product acceptance.

The active 16 October continuation is in [current-work-2026-10-16.md](current-work-2026-10-16.md). The entries below retain the earlier acceptance history; they are not the current release status.

**Latest checkpoint: 14 October 2026.** Design PR #30 and release PR #31 are merged in main. Mac/Home/Sparkle **42** are public; the installed Mac is 42 and iOS 42 is in internal TestFlight. The App Review Home was updated to 42 with preserved data and a real model reply. Public App Store version 1.0 still retains build **34**, `WAITING_FOR_REVIEW`. The user explicitly authorized publication before the remaining provider acceptance. See [build 42 delivery](releases/2026-10-14-build-42.md).

The original Sparkle signing key is now backed up and read back from 1Password (Development, **OpenStrudel Sparkle EdDSA private key**). The temporary export was removed; the application's public key is unchanged. Mac mini SSH is reachable again, but its last observed installed version was 40, not proof of automatic installation of 42.

AgentMetal's native checkout and resumable setup are implemented and tested; [current acceptance boundaries](releases/2026-10-14-agentmetal.md) remain explicit. No paid VM exists yet. Existing-server setup now accepts Ubuntu 24.04 LTS and newer LTS releases, including 26.04, and selects Docker's matching OS repository. These source changes are newer than public build 42. EQVPS is deferred by the user: do not fund its partner balance or introduce resale billing. A separate user-requested chat, **Автономная работа MacBook и Mac mini**, is auditing work continuity across current projects.

The table below preserves component acceptance history; build 42 delivery supersedes the older release numbers.

| Request | Implementation | Verification |
| --- | --- | --- |
| Embedded Parakeet dictation: one optional download, automatic language recognition, no language picker or second application | Published in build 40 | Mac microphone-to-draft, EN/RU/FR/ES, offline recognition, bounded cancellation and idle model unload pass. iOS Simulator downloaded the model and transcribed saved audio into an editable draft; its microphone supplies silence, so physical microphone acceptance remains separate |
| Remove the top Conversations entry; keep employee navigation | Published in build 40 | Rechecked in the installed Mac app after the real Sparkle 39 → 40 update. Employee navigation and existing history remain available |
| Move an employee to another device from settings or by dragging to its sidebar section | Implemented on the existing durable transfer protocol for independent devices | Seven backend tests and four native coordinator tests pass. Actual Mac context/settings paths, return trip and recovery after a lost release reply/app restart pass with history, file and schedule. CUA drag does not initiate even in a minimal stock SwiftUI control, so the drag gesture remains unverified |
| Paste a private SSH key as well as choose a file | Implemented | Unit tests and four real loopback SSH tests pass. Native UI selected an encrypted key, verified the host fingerprint, authenticated and correctly rejected the unsupported macOS target. Paste button accepted a replacement key and cleared the previous passphrase |
| Investigate disappearing corporate ChatGPT connection | Available history examined; historical cause remains unproven | Corporate credentials existed in the 4 October snapshot; the default slot has a 7 October OAuth callback/exchange followed by a personal identity. No durable account-change journal links this older transition to the reported recent five-account incident. Current three distinct identities are unchanged across both 13 October backups and live data. No logout or token restore performed |
| Simpler card checkout for server rental | AgentMetal direct card checkout and resumable native installation are implemented, separately from the gated WAI checkout and existing DigitalOcean flow | Live compatible offer and Stripe $2.20 one-day checkout reached from the Mac app. Saved order survives restart; 46 focused native and 54 installer/runtime/localization tests pass. Payment, a real AgentMetal VM, ChatGPT sign-in and first remote reply remain pending. See the AgentMetal report |
| WAI Core Team: full Operations access for every partner | Implementation in sibling wai-web worktree; explicit trusted-group delegation with initiating sender audit | Deployed; actual group tool reads and private live-model replay passed |
| Contracts, acceptance acts, invoices, Zoom and Notion handoff for Wolf | Merged in wai-web; canonical Operations skills and versioned DOCX workflow | Prior live private QA delivered source PDF/contract evidence. Separate Operations work records isolated draft/payment-link cases with cleanup. Real bank invoice/payment and full live lesson mutation acceptance remain separate; examples are not production orders |
| Notion operational cases: cancel lesson, one-off mentor replacement, follow-up | One-off mentor changes are already in wai-web main (`25d33df0`), including Notion/calendar recovery tests and the canonical handoff | School deploy record and source both confirm `23e0ea6a`, which contains `25d33df0`; its deploy unit completed successfully. Exact live private bot mutation replay remains unverified. Preserve the existing implementation rather than reimplementing it |
| Regression checks and release | Mac/Home 40 published; iOS 40 in internal TestFlight | Mac signatures/notarization, all 147 packaged Home source files, actual Sparkle installation, installed build and retained data verified here. Public App Store 34 remains in review. Automatic local-runtime startup and backup follow-ups below are newer than build 40 |
| Telegram messages and answers visible in the app, with clear reply destination and delegation | Visible conversation choices inside each employee chat; existing bounded history API and native Codex delegation retained | Conditional discovery, isolation and remembered selection pass. Real Mac QA app automatically displayed private Telegram request 1678090 and reply 1678091, including running state. Bot read the contract through MCP, identified missing act/invoice evidence and made no writes. iOS Simulator also received a new request and reply automatically; both persisted after app update/restart |
| Merge current work to main and remove unnecessary branches immediately, then continue acceptance | Explicit user steering during this continuation | Preserve unmerged commits and branches attached to other chats. Merging source is separate from publishing Sparkle/TestFlight |
| Keep the local runtime current when a remote employee was selected before an app update | Follow-up fix chooses the saved local connection independently of the selected chat | Reproduced after real Sparkle 39 → 40. The notarized local 40 → 41 replacement now restarts Home automatically with the remote employee selected. Runtime digest matches the installed bundle; all employee, conversation and message rows match the pre-update hashes. Public Sparkle is still 40; delivery of 41 through Sparkle remains deferred |
| Keep rollback backups usable with downloaded dictation models | Exclude only the reproducible Parakeet weights, preserving unique dictation files | Real backup first failed for lack of space while duplicating the model. After the fix, backup and 23 SQLite integrity checks passed; 12 storage tests pass, including recordings/custom-model preservation |
| Service notices and action approvals | Shared five-language translations; original provider details and wire decisions retained | Reproduced Russian approval controls and untranslated catalog failure in the English Mac app; focused native and runtime regressions pass. Real Google Calendar reads succeeded before and after installing build 41; the updated approval card and final result were checked in the app |
| Portable Mac runtime packaging | Pinned official Node archive and SHA-256, architecture match, license and system-library checks | A notarized candidate containing Homebrew Node failed actual startup. The new finished-bundle regression fails on it and passes on the signed standalone runtime. Earlier invalid candidates are explicitly excluded from release |
| Earlier device, account, model, clipboard, icon and localization requests | Already implemented in main; see component reports below | Do not confuse earlier accepted paths with a complete new run. Fresh Google sign-in, physical-device checks and design-branch acceptance remain open |

### Earlier tasks retained

- **Devices and onboarding:** independent local/remote Homes, creation on a selected device, plain connection flow, restore, offline recovery and device-first navigation. Existing Ubuntu 24.04 setup, real authorization and remote tool/file tasks passed; paid disposable Kamatera VM was deleted after acceptance. [Server journey](releases/2026-10-13-local-network.md).
- **ChatGPT accounts and limits:** person-plus-workspace deduplication, rename without losing identity, shared toolbar/settings snapshots, plan details, separate limits/reset/credits, loading/error states. Historical disappearance is not assigned a speculative cause. [Account report](releases/2026-10-13-account-consistency.md).
- **Model, reasoning and speed:** prefer the account-advertised model/default effort; fallback `gpt-6.1-sol` with Medium, device defaults and per-employee overrides, capability-based Fast/Ultra Fast. Actual Computer Use was exercised in the earlier scoped Calculator test. [Model and tools report](model-speed-computer-use-review.md).
- **Clipboard, backups and sign-out:** image/text paste into the composer, attachment handling, archive/restore and operation states have prior acceptance. Keep platform and live-service boundaries from [the broader matrix](remaining-work-2026-10-12.md); the model-backup regression above is new.
- **Presentation:** chosen smiling bun across application surfaces; English default plus RU/FR/ES/HE, with RTL and existing layout coverage. Sparkle 42 has English release notes. The completed design work is merged through PR #30 and delivered in build 42; see its release report for current platform verification.
- **Apple:** review account/connection infrastructure and English materials were prepared in prior work. Public build 34 remains queued; uploading internal 40 did not replace it. Refresh privacy/metadata/screenshots against the eventual public binary, without canceling the pending review merely for an internal release.
- **Other operating systems:** Windows/Linux Home support does not imply a finished desktop dictation app. No such client release is claimed.

### Next work from this checkpoint

1. Complete the paid AgentMetal pilot using one intended checkout: confirm the VM, installation, account authorization, first real task, and recovery. Do not pay both the original API checkout and the separate unpaid native QA checkout.
2. Continue physical-device and service acceptance independently of the shipped build 42. Keep paid acceptance, automatic updater installation, and public App Store review distinct.
3. Fresh Google OAuth and live private replay of the deployed one-off mentor command remain separate. An existing Google Calendar connection completed a real read-only request in the Mac app (six calendars, no event reads or writes). OpenAI’s full service catalog currently returns a provider HTTP 403 challenge; installed services remain accessible. Do not bypass the challenge or disconnect working services merely to manufacture a fresh OAuth test.
4. Resolve the VDS offer/artifact contract, then finish the native checkout experience and the approved paid pilot. Keep purchase disabled until those checks pass.
5. Retain explicit remaining boundaries: physical iPhone microphone/camera and WAN coverage, actual drag gesture, public App Store metadata/privacy and review state. Simulator results and source tests are not substitutes.

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
- PR #25 is merged and pushed: main `f8ef8db3a1f785d9bbbba0b5d682086999f13d10`. Removed 23 local and 26 remote branches only after proving every tip is included in main; attached branches belonging to other chats remain. Branch tips are recorded in the private evidence directory. Further work continues in `codex/acceptance-continuation`.
- Actual Mac microphone acceptance passed after the user approved the system prompt: Russian speech became an editable unsent draft. Recording an English phrase, switching employees and returning retained the recording; recognition appended its text to the original draft. Canceling a recording also returned to the composer. No QA message was sent to a working group.
- SSH UI acceptance is complete, including invalid pasted key feedback. The isolated loopback SSH test server was stopped after verification.

### Independent-device transfer and dictation acceptance

- Updated the continuation checkout to main `1b17617`, preserving WIP. PR #26's framework signing, iOS privacy manifest and runtime licenses are included. No new public release has been published during this continuation.
- Independent employee moves reuse prepare/stage/release/activate/cancel/finish. Each Home keeps its own credentials; the native client stores only a durable operation journal and checks both device identities. The source is released only after the destination confirms the archive digest. Lost replies are replayed idempotently; cancellation installs the destination barrier before unfreezing the source.
- Native entry points share one confirmation/progress view: employee settings, context menu and dropping onto a device section. A pending move survives closing its sheet or restarting the app. Disconnecting a device involved in an unfinished move is blocked with a direct explanation.
- Actual isolated Mac move: moved the editor between two independent runtimes, deliberately lost the source release reply, restarted the application, and verified recovery with both history messages, file and schedule intact. Only the destination is runnable. The context-menu path works; drag/drop and the UI return trip remain under test.
- Parakeet's native abort callback cannot interrupt one long encoder pass. Long recordings now use bounded windows with overlapping context and native word timestamps. Cancellation of a five-minute recording takes under five seconds, subsequent recognition works, and all 71 full phrases in a controlled five-minute fixture are preserved. The model renders “twelve” as “12”; the acceptance assertion now treats those equivalent forms correctly. Final green offline/memory receipt is still pending.
- Full server regression after transfer changes: 55 suites / 373 tests pass. Focused native transfer/catalogue/archive/localization checks: 21 tests pass.
- Changed ad-hoc QA signing caused macOS to request Keychain access for the saved disposable connection. Computer Use cannot operate SecurityAgent; the user has been asked to confirm that system prompt. Do not change Keychain ACLs or bypass the prompt. Independent tests continue.
- Created a dedicated OpenStrudel Acceptance iPhone 16e simulator. Other projects' running simulators remain untouched. iOS build and real dictation/layout checks are next; this does not substitute for a physical iPhone test.

### Further native acceptance, 13 October evening

- Full native run: 185 tests across 28 suites pass (`/tmp/openstrudel-native-acceptance-all.log`). The later progress/transfer changes also pass seven focused tests across two suites (`/tmp/openstrudel-progress-transfer-tests.log`).
- Offline dictation is now verified with network denied: cancellation of a five-minute fixture took 0.719 seconds; a subsequent recognition retained all 71 full phrases. Resident model memory fell from 805 MiB to 10 MiB after 63 seconds idle. Evidence: `/tmp/openstrudel-dictation-offline-accepted.log`.
- Actual settings-path transfer found a SwiftUI presentation defect: an optional profile captured by a Boolean sheet could still be nil on first opening. Replaced it with an identifiable presentation containing the selected employee snapshot. The confirmation stays open until completion; Open employee selects the destination. The editor returned between both independent fixture devices with history, file and schedule preserved.
- CUA drag does not call the source provider even for a minimal standalone SwiftUI Text and Button. Retained the standard `draggable`/`dropDestination` implementation instead of adding an unproven AppKit workaround. The real drag gesture is not counted as passed.
- Stable Developer ID signing is used for the disposable Mac QA app. Its old ad-hoc disposable connection was replaced through normal reconnect; current credentials survive subsequent QA builds. No production credentials or Keychain ACLs changed. A QA-only initial signing mismatch in Debug dylibs was corrected by signing all nested code before the bundle.
- iOS Simulator paired with a real isolated Home. First model download completed; actual local recognition of saved synthetic audio produced an editable, unsent draft. Simulator microphone capture was silent even with speaker playback, so saved-audio recognition is not reported as microphone verification. The user has deferred physical iPhone acceptance.
- Found and reproduced why the download stayed at Preparing: async URLSession download does not invoke download-delegate byte callbacks. Observe the task's Foundation Progress from `didCreateTask` instead. A real streamed HTTP regression receives intermediate progress; old implementation fails it, new implementation passes. Updated iOS UI validation is in progress.
- Removed only closed, reproducible QA binaries after open-file checks. Preserved accepted evidence, release archives/dSYM, rollback snapshots, other projects' simulators and all Codex history.

### Remaining execution order

1. Finish updated iOS download/recovery and affected layouts; retain the explicit physical-device boundary.
2. Verify real Telegram inbound and bot reply in the updated native conversation, keeping QA messages out of Core Team.
3. Complete isolated Operations mutation cases and canonical Notion mentor-replacement path; do not alter actual client lessons or issue real financial documents for test prompts.
4. Finish corporate-account event correlation and current card-checkout readiness with evidence, without inventing an unavailable commercial flow.
5. Review changed source and current main, merge verified changes, sign/notarize and publish the Mac/Home/TestFlight artifacts, then verify actual installed/delivered versions. Pending public App Store review remains a separate decision.
6. Remove temporary QA grants/processes only after their acceptance runs finish; preserve user data and intentional employee deletions.

- Updated iOS Simulator first-download UI shows byte progress (observed 30%, 14% after retry, 67%), returns to Download on cancel, continues after closing/reopening the sheet and reaches Ready for offline dictation. The existing editable draft remained intact throughout.
- Historical-account investigation exhausted the available credential snapshots and read-only Codex auth logs without exposing raw log contents. The 7 October OAuth exchange is evidence of a login in the default slot, not proof of the later reported disappearance. Existing person-plus-workspace regression coverage remains the applicable protection; no speculative recovery was applied.
- Live WAI VDS catalog still has no payable price and explicitly disables purchase. The ready native integration must remain gated; enabling payment is a separate provider acceptance dependency.

### Release 40 acceptance checkpoint

- Native build 40 passes 186 tests in 28 suites; 47 targeted runtime, employee-transfer and release-package tests also pass, with TypeScript checking. Previous full runtime regression remains 373 tests.
- Actual iPhone Simulator, connected to the production Mini through its advertised pinned public endpoint, received private QA request 1678092 and Wolf’s reply automatically. Both remained after updating/restarting the app. This is not a different-network reachability test or a physical iPhone microphone test.
- Fixed the selected conversation remaining clipped in the horizontal source list: the standard scroll reader now reveals the selected item, including after restore. Actual narrow iPhone layout passed.
- Long iOS transcripts could settle above the latest reply after content size changes. The iOS transcript now uses the native bottom size-change anchor while following replies; selecting the private QA conversation shows the complete last reply and timestamp. macOS lazy-layout behavior is unchanged.
- Live distribution rechecked before preparing release 40: Sparkle 39, latest iOS 38 VALID, public 1.0 still WAITING_FOR_REVIEW. No public App Store submission is being replaced.
