# Server journey continuation — Mac mini, 12 October 2026

## Scope and release state

This continues the MacBook checkpoint `d3418d1` on `codex/server-journey-completion`. The objective is a complete journey from server setup to ChatGPT sign-in and a useful first assistant task, including recovery. These source changes have not yet been published as a Mac, iOS, Home or Sparkle release. The published Home package remains 35.1.

## Changes

- Both server setup routes retain the setup sheet for ChatGPT sign-in and then offer **Create an assistant here**. The device is saved before it is selected, so changing the active device does not dismiss the sheet prematurely. Reopening an already completed flow also advances to the account step.
- The sign-in code has a copy action, and account settings use the device's display name. The new server copy is available in English, Russian, French, Spanish and Hebrew. Account polling runs only while sign-in is pending and stops when the account connects or the sheet closes.
- A saved installation can resume when the SSH connection failed before the server wrote its installation identity. Identity publication is atomic: an interrupted write cannot leave an empty marker. A failed, matching, not-yet-installed attempt can update its pinned package without replacing its owner token or identity. Running, completed, foreign and installed attempts still refuse replacement.
- New assistants use the creating client's language for their default name. Import name collisions use numeric suffixes. Existing assistants are not renamed. Native and web clients translate known service notices without translating user or model messages.
- A legacy OpenAI expired-sign-in error now retains the sign-in recovery instruction in all five languages. Tests use the selected interface locale instead of assuming Russian or a five-character time.
- A locked Keychain connection now offers **Unlock connection** instead of asking the user to set up the device again. Startup stays silent; an explicit retry requests the existing credential off the main thread. The saved destination keeps the draft namespace stable, and a delayed credential result cannot reconnect after local erase. Missing credentials still require a connection link; revoked credentials retain the existing authenticated retry behavior. An unreadable saved pairing attempt fails before creating a replacement attempt or changing the current connection.

## Verified on this Mac

| Check | Evidence |
| --- | --- |
| TypeScript | `npm run typecheck` passed |
| Runtime regression suite | 54 files, 356 tests passed with two workers |
| Native unit suite | 163 tests in 24 suites passed, including Keychain refusal, missing credentials, successful recovery, failed pairing-attempt lookup and local erase during a pending permission request |
| macOS build | Updated application built through the managed native build wrapper |
| iOS build | Generic iOS Simulator build succeeded; this is not physical-device acceptance |
| Recovery boundaries | Script and native fault-injection tests cover interruption before identity publication, unchanged owner credentials, matching failed-release replacement and foreign identity refusal |
| Actual remote device | Native integration connected to the existing Kamatera test server using its saved identity, created an employee there, exported and restored a backup, and verified idempotent import replay |
| Useful task in the native UI | Created **Server Desk** on the remote server from the Mac app. The model created a file, read it back with a tool and attached it. Quick Look showed the expected contents. An independent SSH check confirmed the same 41-byte file |
| App restart | Quit and reopened the isolated QA app; the remote device, selected assistant, messages and attachment survived |
| Service interruption | Stopped only the QA Home container after preparing a consistent backup. The app showed an offline state and retained the unsent draft and history. After startup it reconnected automatically; the draft was sent once and the assistant read back the same file successfully |
| Access isolation | Employee data without authentication returned 401; the expected server certificate and identity were verified |
| Localization after the final copy edits | All four catalog checks passed |

The test file is `server-check-20261012.txt`, containing `OpenStrudel server check: 17 × 23 = 391.` Its SHA-256 is `111a787c57e12f8a6ac6a3da060b96a7231f331bfb643bb89755867daa94f9d4`.

The useful-task, restart and service-interruption checks used the initial isolated QA bundle built from this branch, before the final generated-name and service-notice localization edits. Updating that ad-hoc-signed QA bundle changed its signature, and the new binary could not read the old saved Keychain connection. The earlier authorized QA bundle was restored for connection testing. This exposed the missing Keychain recovery action; that action is now implemented, built and covered by the four new tests. The latest candidate visibly shows **Unlock connection** and remains responsive while macOS authorization is pending. Completing that real permission request requires the user: Computer Use refused control of SecurityAgent. No Keychain ACL, password or security setting was changed to bypass it. Final connected-state UI acceptance is still pending.

Before and after the QA service interruption, independent authenticated HTTPS checks verified all 16 existing employee records, the node identity and certificate were unchanged. The consistent private QA snapshot is on that server under `/var/lib/openstrudel-qa-snapshots/recovery-20261012T193431Z/`.

## Remaining acceptance gates

1. Complete the real Keychain permission request, then verify the final native account sheet visually: first sign-in, code copying, successful authorization, **Continue later**, and creating the first assistant. Prior MacBook evidence confirms official ChatGPT authorization and a real reply, but not every state of this new sheet.
2. Exercise the preserved failed Home 35 recovery record with the corrected installer. The working, authorized 35.1 installation must not be overwritten to manufacture this result. Fault-injection tests are not a substitute for that live acceptance.
3. Repeat installation on a clean supported OS. The current server reused Docker and packages from the failed first attempt. No second paid resource was created on Mac mini.
4. Keep integrated provider purchasing gated until real offer/payment/provisioning acceptance passes. Do not publish missing prices as a working checkout.
5. Remove the exact paid disposable Kamatera VM after all required server checks, and confirm removal in provider inventory. Turning it off does not stop its hourly charge. The MacBook provider helper is not installed on this Mac; at 22:59 the local 1Password CLI reported no signed-in account, and the browser console showed the Kamatera login page. The user was asked to restore provider access without sending credentials in chat. SSH access alone cannot confirm provider deletion.
6. Continue the separately scoped voice, physical-iPhone interruption, fresh third-party OAuth, cross-network and long-running memory checks. The server results do not close these items.

## Evidence handling

Private test logs, result bundles, fixture, QA bundles and recovery receipts are under `.data/server-journey-2026-10-12/` in this worktree. Credentials and private test state stay out of Git. Test artifacts use the native build wrapper's locked staging copy. Production app/runtime data were not replaced by this continuation.

The integration test exports the entire disposable server team. Repeating its restore grows the QA catalogue; do not use it as a polling health check or run it against a personal/production Home.

Disk maintenance removed 1,278 MiB of reproducible downloaded Swift package artifacts from an inactive AiGid DerivedData directory after checking file age (over 33 days), open files and active builds. It did not remove user data, Codex history, release archives or active build products. Free space remains low because other development work is active; the removed allocation is not a promise of a fixed amount of current free space.

See [the server plan](server-setup-queue-2026-10-12.md), [original cloud acceptance](kamatera-acceptance-2026-10-12.md) and [local dictation direction](dictation-direction-2026-10-12.md).
