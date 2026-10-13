# Remaining work and acceptance

Execution started on 12 October 2026 after the five-language update was merged in PR #13. This replaces stale unchecked items in older plans with an explicit current queue. A checked item needs evidence from the surface it changes.

Latest delivery and remaining queue: [build 40 verification](releases/2026-10-13-build-40-follow-up.md) and [current work](current-work-2026-10-13.md). Mac/Sparkle and Home 40 are public; iOS 40 is valid and in internal TestFlight. Public App Store review retains build 34. Parakeet is now the shipped native dictation engine; the older Apple-recognizer results below retain their original scope and do not imply Hebrew support in Parakeet. Earlier [Mac 39/server acceptance](releases/2026-10-13-local-network.md), [account release 38](releases/2026-10-13-account-consistency.md), [build 36](releases/2026-10-13-server-recovery.md), [build 35](release-35-acceptance.md) and [Kamatera](kamatera-acceptance-2026-10-12.md) remain historical evidence. Embedded provider checkout and physical-device checks remain separate.

## Current continuation

- [x] Create a server assistant in the native app, execute a real file task with tools, read the file back and open its attachment.
- [x] Verify app restart and a deliberate interruption of the exact QA Home service. History, draft, device identity, certificate and employee records survived; the app reconnected automatically and the assistant read the file again.
- [x] Implement and publish final ChatGPT onboarding, atomic interrupted-install recovery, explicit saved-Keychain recovery and localized generated copy. TypeScript, 356 runtime tests, 163 native tests and Mac/iOS Simulator builds passed. Release 36 adds signed artifact, actual Sparkle installation, production data preservation and TestFlight processing evidence.
- [x] Verify saved-connection recovery after macOS authorization. On 13 October the QA app showed the same server online, 16 existing assistants, Server Desk history and its file attachment. No credential replacement or second installation was used.
- [x] Deliver build 36 through main, Sparkle, public Mac/Home downloads and internal TestFlight. Verify the updated Mac mini and App Review server, including a real model tool call and retained data.
- [x] Verify the fresh-server account sheet, copy-code action, actual ChatGPT authorization and first remote assistant in the native app. Two real tool requests produced the correct calculation and an attachment opened in Quick Look. No credentials were injected to bypass sign-in.
- [x] Install on a clean Ubuntu 24.04 ARM64 VM. The local-network permission issue is fixed in Mac 39. Host disk exhaustion and a Lima SSH-key rotation required fixture recovery through the local console; this is recorded separately from successful native SSH retry.
- [x] Verify server-side recovery of the exact preserved failed Home 35 recipe on an independent disposable Ubuntu VM. The original recipe failed, the unmodified corrected scripts installed Home 38, and owner/key/installation identity, authenticated health, unauthenticated refusal and sandbox checks passed. The working paid QA installation was not overwritten; this is not a replay of the original Mac's saved UI session.
- [x] Recover provider API access through the documented WAI VDS host without copying credentials into chat. The exact paid VM identity, name and public IP were independently matched.
- [x] Delete the exact paid disposable VM after acceptance. Kamatera confirmed `openstrudel-qa-20261012` was off before termination; a subsequent inventory contained neither its UUID nor its name. Both local test VMs and their unused Ubuntu image cache were also removed after retaining evidence.
- [x] Publish Mac/Sparkle 39, verify a real 38 → 39 update and the installed Mac mini, deploy Home 38 to App Review with rollback, and independently verify internal TestFlight 38. Combined regression: 172 native tests and 367 runtime tests passed.

Detailed evidence and remaining boundaries: [Mac mini continuation](server-journey-mini-2026-10-12.md). The older checked items below describe build 35 and keep their original acceptance scope.

## 1. Connect a server

- [x] Add a clear Mac/server choice to Connect a device on Mac; retain the existing link/QR path on iOS.
- [x] Set up an existing Ubuntu server from its address, sign-in name and password or SSH key. Show the host identity before authentication; keep credentials out of arguments and logs.
- [x] Read-only compatibility and existing-installation check, explicit installation, durable resume, and confirmed progress. Never overwrite an unrelated installation or user data.
- [x] Reuse the current pinned bootstrap and verify the resulting authenticated HTTPS service before adding it to the device list.
- [x] Verify wrong credentials, changed host key, unsupported system, occupied installation/port, cancellation and reconnect; exercise a real SSH connection and a real server installation where access is available.

## 2. Get a server

- [x] Recheck WAI VDS and EQVPS APIs, current offers and reseller capabilities. Keep public catalog prices distinct from authenticated quotes and availability.
- [x] Expose the existing named DigitalOcean flow from the Mac device entry, with provider quote/confirmation and saved-state logic covered by native tests. Keep the unavailable WAI checkout out of this path. Rendered paid-account quote/sign-in acceptance is still part of the paid pilot below.
- [ ] Validate payment and provisioning only against an explicitly approved concrete offer. Keep the existing iOS companion scope.

## 3. Complete verification

- [x] Test actual on-device recognition for English, Russian, French, Spanish and Hebrew; record unsupported languages and measured results without claiming native-speaker review.
- [x] Exercise microphone denial/recovery, recording recovery logic, clipboard text/images, language switching and native/browser layouts. Physical microphone/long-recording and comprehensive assistive-technology checks remain separate.
- [x] Recheck affected device routing, remote creation/export, account/offline recovery, models/speeds and connection-page behavior. Existing backup/restore, service and real Computer Use checks remain in their component reports; a fresh Google authorization and physical WAN matrix were not repeated.
- [x] Check available physical iPhone/iPad access. Simulator tests do not close physical microphone or camera checks.
- [x] Run a bounded long-history/memory regression. The historical report of 30–40 GB remains unproven unless reproduced or tied to a concrete fix.

## 4. Ship the verified result

- [x] Merge tested implementation into main in PRs #13–15; keep final test/documentation evidence reviewable separately.
- [x] Build and sign the Mac release, notarize it, publish Home/web and Sparkle artifacts, then verify downloaded artifacts and an actual isolated updater installation.
- [x] Back up before production installation, verify data and health afterward, then mark the rollback snapshot healthy.
- [x] Build/upload iOS 35, verify processing and internal TestFlight availability, and revalidate both private App Review connection paths on Simulator.
- [x] Prepare English metadata/screenshots for the localized binary and recheck Apple state. Decision: retain build 34 in `WAITING_FOR_REVIEW`. Applying build 35's metadata/screenshots and submitting it to public review is still a distinct release step.

## External dependencies

Paid resources, provider account access and physical-device interaction are recorded separately from completed implementation. Missing access must produce a precise next action rather than a false completion claim. No production provider migration is implied by documentation research.

Evidence will be collected under `.data/remaining-work-2026-10-12/`. Existing evidence remains in the earlier acceptance reports and is not described as newly repeated.

## Development evidence, 12 October

- Existing-server setup was exercised in the Mac app against a disposable Lima Ubuntu 24.04 ARM64 VM (4 GB, 35 GB, no host data mounts). Installation survived an interrupted host/VM run, resumed the same installation and reached `ready` with the Home container running. The VM downloaded the currently published Home 33; native installer changes are the new candidate.
- Real OpenSSH tests passed for password, private key, encrypted private key, wrong password/passphrase, changed host identity and cancellation. The four integration tests took 2.8 seconds. Other applications' existing Docker containers are rejected before staging, including a preflight/install race regression.
- A real native integration check resumed authenticated pinned HTTPS on the installed VM, added an independent device, created a remote employee and exported its archive. It uses a separate QA owner issued through the ordinary pairing API. It does not claim a real model reply or a cloud purchase.
- Re-signing the ad hoc QA app exposed a Keychain authorization wait on the main thread. Silent reads/writes now fail with recovery guidance; an explicit authorization wait runs off the UI thread. A locked saved setup cannot be overwritten by starting another installation. The protected macOS authorization window needs human interaction. Back was checked while authorization was pending; the original QA installation remains saved. Production credentials were untouched.
- Real Apple on-device recognition processed synthetic recorded English, Russian, French, Spanish and Hebrew audio. Measured recognition stages were 0.762/0.339/0.377/0.335/0.382 seconds after preparation. This verifies the engine path, not live microphone quality or native-speaker review.
- The iPhone simulator model UI test passed: recommended account model, device Fast setting, per-employee Ultra Fast where available, inheritance and hiding unsupported speeds. Build signing must remain enabled (ad hoc for Simulator) for Keychain pairing. The physical WaiPhone launch was blocked by its lock screen; the user explicitly deferred this check and requested Simulator testing. The Mini had less than 1 GB free when checked, so the local Simulator was used.
- The real browser rendered a synthetic 5,000-message history and eight round trips between conversations. Latest 100 messages were shown; JavaScript heap was 7.09 MB initially and 7.88 MB afterward, with no console errors. This short browser check does not diagnose the historical Mac 30–40 GB report or prove long-running native memory behavior.
- A TLS regression exposed a missing public allowlist entry for the new localization assets: an unpaired browser could not load the sign-in language picker. Both static assets are now available before pairing; private employee/history APIs still require authorization. The failing regression was run before the fix.
- Targeted backend suites passed 36 tests. Native server/device/DigitalOcean suites passed; four old Russian-only recovery assertions were corrected to compare localized messages, then all 20 recovery tests passed. TypeScript typecheck and whitespace checks passed.
- WAI VDS still reports `live_gated` with checkout disabled and no payable quote. EQVPS advertises a $15/month plan, but an authenticated quote and deployable reseller integration have not been supplied. No provider charge, account creation or infrastructure migration was performed. The existing DigitalOcean sign-in entry is reachable; an actual purchase remains unverified.
- After the user allowed Keychain access, the rebuilt Mac QA app resumed the saved VM installation without SSH credentials or another install. It showed “Your server is ready”; Open server added it to the QA device list and displayed the existing remote test assistant. This closes the earlier pending authorization check. The QA app's saved state is separate from production.
- Final private-review UI tests executed on the iPhone Simulator with zero failures: opening the page in Safari and pasting it in a fresh app. Both paired, received an actual model reply and retained history after relaunch. Intermediate failed/skipped attempts are not counted as passes.
- Signed Mac 35 and Home 35 were published with rollback copies and verified public download hashes. An isolated 33 → 35 Sparkle update installed and relaunched; the production Mac then confirmed the public channel is current. iOS 35 is `VALID` and `IN_BETA_TESTING` internally. Build 34 remains the public App Store review submission.

Private evidence: `.data/remaining-work-2026-10-12/` (`ssh-auth-real.log`, `real-vm-native.log`, `server-keychain-green.log`, `server-unlock-green.log`, `five-language-recognition.log`, `sim-model-retry.log`, `model-simulator-retry.xcresult`, `final-api-tests.log`, `recovery-language-green.log`). Credentials and server recovery fixtures are deliberately excluded from Git.
