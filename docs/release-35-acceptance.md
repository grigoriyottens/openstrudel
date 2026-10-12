# Release 35 acceptance — 12 October 2026

Follow-up: the [real Kamatera installation](kamatera-acceptance-2026-10-12.md) found that Home 35 was packaged without the directory required by the installers. Home 35.1 corrects the package and is now the current download; Mac/Sparkle/iOS 35 are unchanged. The follow-up records actual cloud installation, reboot and backup restoration, plus the remaining account/recovery boundaries.

Build 35 is published for Mac and Home/web. The development Mac is updated with a verified rollback snapshot. iOS build 35 is available to the existing internal TestFlight group. The public App Store submission still uses build 34 and is waiting for review; build 35 has not replaced it.

Mac and Home source: `b04bfe45f8f136e95ae5af112873f66111b96874`, including PRs [13](https://github.com/mikwiseman/openstrudel/pull/13), [14](https://github.com/mikwiseman/openstrudel/pull/14) and [15](https://github.com/mikwiseman/openstrudel/pull/15). Subsequent test/documentation commits do not change these release artifacts.

## Delivered behavior

- English is the default interface language. Russian, French, Spanish and Hebrew are available before connection and in settings. Native and web use one catalog; Hebrew mirrors the layout while addresses, codes and user content remain readable. Drafts survive language changes.
- Account settings distinguish the returned identity, recognized plan and personal/workspace category. Subscription windows, reset dates, credits and additional reset passes are separate. Unknown values remain unknown, with loading, error and retry states.
- Dictation is optional and integrated through Apple's on-device `DictationTranscriber` on macOS/iOS 26. First use offers the required language assets; installed assets are reused. Download, cancel, retry, unsupported-language and recording-recovery states are present. This is not an embedded OpenAI speech model and does not launch another app.
- Image-only Command-V works through the Mac's native text editor, with attachment previews and existing size/format checks. Plain text, undo, multiline input and input methods retain native behavior. Images reach the model as images.
- Connect a device offers a connection link, setup of an existing server, or the named DigitalOcean flow. Server setup accepts an address, sign-in name and password/key, confirms the SSH identity, checks compatibility and existing workloads, installs, and verifies authenticated HTTPS before adding the device. Interrupted installations resume the same identity without another purchase or runtime.
- The private connection page also uses the five-language catalog. Reopening its fragment link in Safari refreshes an expired invitation. Localization resources are public before pairing; employee/history APIs remain authenticated.
- The existing automatic model choice follows the selected account's recommendation and reasoning level, with GPT-6.1 Sol / Medium as the fallback when none is returned. Per-assistant overrides and capability-dependent Fast/Ultra Fast remain available. The live account used in acceptance recommends GPT-6-Astra / Medium.

## Checks and their scope

| Surface | Evidence |
| --- | --- |
| Real Mac interface | Account cards, all five language choices, Hebrew layout, preserved drafts, image-only paste/preview/send, text paste and undo. Server setup was inspected in English and Hebrew. The installed production build shows English, the current pastry icon, and both existing devices. |
| Real SSH | Four integration tests exercised password, key, encrypted key, wrong password/passphrase, changed host identity and cancellation. Cancellation completed in 0.411 seconds; the suite took 2.8 seconds. |
| Real server installation | The native setup installed Home on a disposable Ubuntu 24.04 ARM64 Lima VM, resumed after interruption, verified pinned HTTPS, added an independent device, created a remote assistant and exported its archive. The VM downloaded the then-public Home 33. It is a local VM, not a purchased cloud server or a second physical computer. |
| Recovery and isolation | Targeted native server/device/DigitalOcean tests passed. All 20 recovery tests passed after updating four obsolete Russian-only assertions. Six scoped data-reset tests passed. Locked Keychain state cannot be overwritten by a second installation; explicit authorization runs off the UI thread. |
| Keychain authorization in the app | After the user allowed access, the rebuilt QA app recovered the same saved installation, showed “Your server is ready” and opened the remote device with its existing test assistant. It required neither SSH credentials nor another install. |
| Dictation | Real Apple recognition processed synthetic recorded speech in EN/RU/FR/ES/HE. Recognition stages after preparation took 0.762/0.339/0.377/0.335/0.382 seconds. First-use, microphone denial, retry and recovery logic were checked. These timings are not live microphone latency or language-accuracy benchmarks. |
| Actual model image input | The connected account correctly described the pastry image, including its two visible eyes. This complements the native clipboard-to-attachment check. |
| iPhone Simulator | Fresh onboarding in five languages, Hebrew layout, language persistence, model defaults/overrides/inheritance and available speeds. Two actual App Review tests passed: Safari page → app (39.963 s), and pasted page in a fresh installation → app (44.921 s). Both received a real model reply and retained history after relaunch. |
| iPad Simulator | English store screenshot capture passed on iPad Pro 13-inch (M4); captures were inspected alongside the iPhone set. |
| Browser | English/Hebrew, narrow layout, account states, preserved drafts and attachments. The connection page was also exercised in French, Spanish and Russian, including errors, countdown and reopening the same fragment. No console errors in the final checked flows. |
| Long history | A synthetic 5,000-message conversation displayed its latest 100 messages through eight conversation round trips. Browser heap changed from 7.09 MB to 7.88 MB. This bounded check does not reproduce or resolve the historical native 30–40 GB report. |
| Backend | 36 targeted setup/bootstrap/localization/pagination tests passed; 15 final connection-page/localization/TLS tests passed. TypeScript typecheck and whitespace checks passed. Regressions were reproduced before the SSH, recovery, resource-allowlist and Safari fixes. |
| Computer Use | The earlier real-account Calculator permission/17 × 23 = 391 test and denial test remain the evidence in [the component report](model-speed-computer-use-review.md). This release does not claim every application or a fresh machine was revalidated. |

Failed intermediate runs remain in the private evidence. In particular, the first review test opened another disposable app registered for the same URL scheme; a later run skipped because its fixture was not propagated. Neither is counted as a pass. The two final runs above executed one test each with zero failures after removing the conflicting disposable Simulator app and starting from a fresh Safari document.

## Mac publication and installation

- Release builds used the repository's stable-cache wrapper; the app was copied under its build lock before bundling and signing.
- Developer ID signatures, notarization, stapling and Gatekeeper checks passed for the final app and DMG. App notarization: `59a61358-b864-4900-9ece-fe8af725fd9a`; DMG: `f2cb48c1-c44b-44ca-8a30-a8f6e748ab39`.
- The signed Sparkle feed and archive signatures were checked independently. An isolated, signed copy of build 33 in `/Applications` downloaded build 35, installed it and automatically relaunched. About confirmed `1.0 (35)` and the interface changed to English. Production Home's PID was unchanged. The test copy has a separate identifier, preferences and feed, and contains no service runtime.
- The first isolated attempt under the checkout's Documents directory stalled inside the system rename operation. It was stopped; the test was repeated successfully from the standard Applications location. This is not evidence for updates from arbitrary protected folders.
- Before the production install, writes were quiesced and `scripts/backup-local-state.py` captured the installed app, state and SQLite snapshot. The atomic app swap and runtime install passed health and SQLite integrity checks. Counts were preserved: one local assistant, two conversations and six messages. Both existing devices appeared online in the real app.
- Runtime digest: `32a8c2b17fe15ee564ca0c69ba7d61ad1cd4f15a5782c6d2e69cc7ce6c728410`. The managed rollback snapshot was marked healthy.
- Immutable archives were uploaded before aliases and the signed feed. Publication checked the previous hashes, retained a hard-linked rollback set and verified the final routes over public HTTPS. A separate download from this Mac matched every final hash. The installed production app's update check reports it is current.
- The Mac mini was used for existing Sparkle signing tools, not rebuilt or updated to 35: its disk was low. Publishing the update is not proof of installation there.

| Public artifact | SHA-256 |
| --- | --- |
| [Mac 1.0 (35)](https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-35-arm64.dmg) | `bfbaddbd6825f33fab189f11149702e09bc02732f3141995f0f22ae27c848c4c` |
| [Home 1.0 (35)](https://waiwai.is/openstrudel/downloads/OpenStrudel-Home-1.0-35.tar.gz) | `d3024341171aaf54d25232ad3fd1116a0d6f4079f656382be1e4b28621ad1e48` |
| [Sparkle feed](https://waiwai.is/openstrudel/updates/appcast.xml) | `5b06de336b6d3baad1191777275b3fbb54a475904c75bee5a187229702acfb7c` |

## Home and Apple review

The dedicated review Home now runs image `openstrudel:35-b04bfe4`. A cloned data volume, consistent backup and previous container were retained for rollback. After cutover, authenticated health and an actual model response passed. The public connection page renders English by default; its private access code and credentials remain outside Git. Unrelated containers were not changed.

iOS build 35 was archived, validated, uploaded and processed as `VALID`. Build ID: `10a8700a-ddb4-416c-b43d-09aa05c4ffae`. Its membership in the existing internal group was read back; the beta state is `IN_BETA_TESTING`, external state `READY_FOR_BETA_SUBMISSION`. The packaged icon and five locales were inspected. Upload and internal availability do not imply external beta or App Store approval.

The final App Store Connect read still shows version 1.0 with build 34, `VALID`, `WAITING_FOR_REVIEW`. Its review was left intact. The [English localized metadata and screenshots](app-store-localization-2026-10-12.md) are prepared for the localized binary and were not applied to the older pending binary. A new public submission remains a distinct step.

## Open boundaries

- The user deferred the locked physical WaiPhone and requested Simulator testing. Physical iPhone/iPad microphone, camera QR scanning and long/interrupted recordings remain unverified. Five-language copy/recognition has not had native-speaker review.
- WAI VDS still has no enabled checkout/payable offer. EQVPS public pricing and reseller documentation were researched, but there is no authenticated quote or verified integration. DigitalOcean's existing sign-in and saved-installation flow is available; a real paid purchase, renewal and provider migration were not performed. The next paid pilot needs a concrete offer and spending limit.
- Fresh Google authorization, all third-party account variants, multi-physical-device WAN/offline behavior and long-running native memory are not claimed as rechecked by this release. Existing targeted tests and prior acceptance reports have narrower coverage.
- Build 35's public App Store metadata/screenshots and external review are not published. Build 34 remains in Apple's queue.

## Private evidence and rollback

Logs, screenshots, xcresults and fixtures are under `.data/remaining-work-2026-10-12/` and `.data/localization-2026-10-12/`. Final signed Mac artifacts are in `.data/release/2026-10-12-35-final/`; the iOS archive and export are in `.data/release/2026-10-12-35/`. Earlier Mac 35 candidates in other folders were not published.

Key receipts: `local35-deployment.json`, `public35-deployment.json`, `public35-independent-verified.json`, `review35-final-deployment.json`, `review35-final-live-check.log`, `sparkle-qa/installed.json`, `asc-internal35-verified.json`, `asc-build35-beta-final.json`, `asc-version-final.json`, `review35-english-final.log`, `review35-fresh-pasted.log`.

Local rollback: `~/Library/Application Support/OpenStrudelBackups/backup-20261012T110710Z-0aa30a6a`. Publication rollback: `/var/www/openstrudel-release35-backup-20261012T112431Z` on the web host. Review Home rollback: `/root/openstrudel-review-cutover-35-b04bfe4` and `openstrudel-review-rollback-35-2f487d5`. These are retained recovery artifacts, not disposable build caches.
