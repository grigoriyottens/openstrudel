# Remaining work and acceptance

Execution started on 12 October 2026 after the five-language update was merged in PR #13. This replaces stale unchecked items in older plans with an explicit current queue. A checked item needs evidence from the surface it changes.

## 1. Connect a server

- [x] Add a clear Mac/server choice to Connect a device on Mac; retain the existing link/QR path on iOS.
- [x] Set up an existing Ubuntu server from its address, sign-in name and password or SSH key. Show the host identity before authentication; keep credentials out of arguments and logs.
- [x] Read-only compatibility and existing-installation check, explicit installation, durable resume, and confirmed progress. Never overwrite an unrelated installation or user data.
- [x] Reuse the current pinned bootstrap and verify the resulting authenticated HTTPS service before adding it to the device list.
- [x] Verify wrong credentials, changed host key, unsupported system, occupied installation/port, cancellation and reconnect; exercise a real SSH connection and a real server installation where access is available.

## 2. Get a server

- [x] Recheck WAI VDS and EQVPS APIs, current offers and reseller capabilities. Keep public catalog prices distinct from authenticated quotes and availability.
- [ ] Complete the reachable Mac setup path, including provider identity, cost confirmation, return from sign-in and saved progress. Do not expose an unavailable checkout as a working purchase.
- [ ] Validate payment and provisioning only against an explicitly approved concrete offer. Keep the existing iOS companion scope.

## 3. Complete verification

- [x] Test actual on-device recognition for English, Russian, French, Spanish and Hebrew; record unsupported languages and measured results without claiming native-speaker review.
- [ ] Exercise microphone denial/recovery, saved recording after interruption, clipboard text/images, language switching and accessibility layouts in the release candidate.
- [ ] Recheck real device routing, remote creation, offline recovery, backups/restore, models/speeds, services and Computer Use affected by the candidate.
- [x] Check available physical iPhone/iPad access. Simulator tests do not close physical microphone or camera checks.
- [x] Run a bounded long-history/memory regression. The historical report of 30–40 GB remains unproven unless reproduced or tied to a concrete fix.

## 4. Ship the verified result

- [ ] Merge tested changes into main; retain a clean local checkout and reviewable PR.
- [ ] Build and sign the Mac release, notarize it, publish Home/web and Sparkle artifacts, then verify downloaded artifacts and an actual isolated updater installation.
- [ ] Back up before production installation, verify data and health afterward, then mark the rollback snapshot healthy.
- [ ] Build/upload the new iOS version, verify processing and TestFlight availability, and revalidate the private App Review connection.
- [ ] Pair English metadata/screenshots with the localized binary. Recheck the current Apple review state before deciding whether to replace the pending submission; do not describe an upload as approval.

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

Private evidence: `.data/remaining-work-2026-10-12/` (`ssh-auth-real.log`, `real-vm-native.log`, `server-keychain-green.log`, `server-unlock-green.log`, `five-language-recognition.log`, `sim-model-retry.log`, `model-simulator-retry.xcresult`, `final-api-tests.log`, `recovery-language-green.log`). Credentials and server recovery fixtures are deliberately excluded from Git.
