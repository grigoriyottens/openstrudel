# Kamatera acceptance — 12 October 2026

## Result

A real test server was created through Kamatera's official API, then configured through OpenStrudel's existing-server wizard on this Mac. Installation, reconnecting after closing the app, authenticated HTTPS, a remote employee, archive export/restore and a full server reboot were verified. A follow-up also completed real ChatGPT sign-in in the native app, created an assistant through the composer and received a verified model reply. This is not proof of integrated purchase or every service connection.

The cloud test found a release defect: the published Home 35 archive omitted the `OpenStrudel-Home/` prefix required by both installers. SSH and preflight worked; extraction correctly rejected the archive. The previous local VM acceptance had installed Home 33, so it did not cover Home 35 packaging.

The corrected **Home 35.1 package** is published at [the immutable download](https://waiwai.is/openstrudel/downloads/OpenStrudel-Home-1.0-35.1.tar.gz) and the current Home alias. Runtime source is unchanged from build 35: `b04bfe45f8f136e95ae5af112873f66111b96874`. This is a packaging correction, not a new Mac, iOS or Sparkle release.

SHA-256: `421ba9bb34baaa9b5adf8014763f6e6c9ce4f53a96bedf38fa54da2423ad65b2`.

## Cloud configuration and cost

One server, `openstrudel-qa-20261012`, in Amsterdam: Ubuntu 24.04, 2 shared vCPUs, 4 GiB RAM and 40 GiB SSD. No backup or managed-service add-ons. The provider returned **$0.026/hour while on or off** and a $19 equivalent monthly price. This server was bought directly for acceptance, not through an embedded OpenStrudel checkout. The user approved removal after the full acceptance run. The server is still running for the remaining checks; deletion must be confirmed through the provider before this work is closed.

## Verified behavior

| Check | Result |
| --- | --- |
| Provisioning | Provider queue completed; allocated VM accepted the newly created test SSH key |
| Native server setup | Address, root sign-in and SSH key; matching host fingerprint; Ubuntu/memory/storage preflight; installation progress; ready screen |
| Published package | Both real installer extractors accepted the final artifact; independent HTTPS download from this Mac matched its SHA-256 |
| Continue later | The test Mac app was quit during installation. The server completed independently; relaunch recovered the saved identity without asking for the SSH key again |
| Connection | The native wizard verified authenticated HTTPS and added the server as an independent device |
| Remote employee | An opt-in native integration test created an employee on the actual Kamatera Home; the local device's employee collection remained empty; the employee appeared in the real app sidebar |
| ChatGPT and first reply | The native account flow opened the official OpenAI device authorization. After successful sign-in, the server assistant was renamed to Server Pilot through a real request and answered in English: 17 × 23 = 391. No authentication files were copied to bypass sign-in. |
| Backup | Native HomeClient exported, previewed and restored the server archive. Existing IDs survived; repeating the same import returned the same imported IDs without duplicating them |
| Reboot | Linux boot ID changed. Home restarted automatically; certificate, installation/node identity and the existing profile data persisted |
| Authentication | An external request to employee data without a token returned 401 |
| Runtime isolation | The shipped sandbox probe passed before and after reboot: workspace readable, private file inaccessible. AppArmor and metadata guard services were active after reboot |

The corrected installation reused OS packages/Docker installed during the first failed attempt, but had no existing Home directory, containers or user data. The failed staging directory was preserved separately. A new isolated Mac QA profile performed the corrected installation. This is explicitly **not** a successful retry of the old Home 35 recovery record.

## Regression protection

`scripts/package-home.py` packages an explicit committed revision with the correct prefix, validates archive limits/types and required files, excludes the working tree, and refuses to overwrite an output. The new regression test runs the real archive through both shipped extractors and compares critical files with Git.

All 40 tests in `home-release.test.ts`, `cloud-init.test.ts` and `server-installer.test.ts` passed. The native real-server test passed before reboot (creation/export) and after reboot (creation/export/restore/idempotent replay). The native integration fixture now accepts another server's address without overwriting the earlier local VM fixture.

Use [the packaging procedure](home-release-packaging.md) for future Home releases. Publication retained rollback copies of the previous Home alias and manifest; previous immutable artifacts and the signed Sparkle feed were not changed.

## Still unverified or unresolved

- No integrated Kamatera purchase flow was added. OpenStrudel currently offers setup of an existing server and a separate DigitalOcean flow; provider provisioning in this test used the official API.
- A pending install pins its release digest. An already failed Home 35 attempt does not recover merely because the public alias now points to 35.1. The continuation now preserves identity, permits replacement only before installation after a failed service, and atomically publishes the installation marker. Native and script fault-injection tests pass; the real failed-35 retry remains unverified. Do not overwrite users' recovery records or data to bypass that test.
- The published server still appends the Russian suffix `(импорт)` even in the English client. Source now uses numeric collision suffixes and client-localized default assistant names; existing employees keep their names. Build and unit checks passed, with the final connected UI pass pending. See the continuation report below.
- This run does not close physical-iPhone dictation/interruptions, fresh Google OAuth, live-microphone quality, Windows/Linux desktop or long-running native memory checks. Prior evidence remains scoped in [release 35 acceptance](release-35-acceptance.md).
- The proposed OpenRamble-based dictation direction is documented [separately](dictation-direction-2026-10-12.md); the Apple speech engine in shipped clients was not replaced.

## UX follow-up in progress

| Before | After proposed in the checkpoint | Why |
| --- | --- | --- |
| Finishing installation drops the user into the app and leaves ChatGPT setup in settings. | Keep the setup sheet open for ChatGPT sign-in, then offer “Create an assistant here.” | The server journey should finish at a working assistant. |
| Account settings show the container hostname. | Use the device label the user sees in navigation. | Users should recognize which server owns the account. |
| The device code is selectable but has no copy action. | Show a short entry hint and a Copy code action with feedback. | Sign-in should not depend on knowing text-selection conventions. |

The Mac mini continuation has added the five-language catalog, passed native tests and Mac/iOS Simulator builds, fixed interrupted identity publication, and verified a useful server task plus app/service restart recovery. These changes are not a published release. The exact evidence and remaining account, Keychain and clean-install checks are in [the continuation report](server-journey-mini-2026-10-12.md).

## Evidence and rollback

Private receipts, provider queue/configuration, SSH test keys, installation fixture, archive, screenshots, publication receipt and native logs/results are under `.data/kamatera-acceptance-2026-10-12/`. They are intentionally excluded from Git. The first native result bundle is under `native/OpenStrudel/.data/kamatera-acceptance-2026-10-12/native-server.xcresult`; the restore result is in the main evidence directory.

Publication rollback is `/var/www/openstrudel-home35-1-backup-20261012T130055Z` on `wai-web-prod`. The original failed cloud staging directory is retained on the test VM as `/var/lib/openstrudel-cloud-failed-35`; it contains private bootstrap material and must not be published.
