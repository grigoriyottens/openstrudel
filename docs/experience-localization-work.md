# Interface, accounts and local dictation

Implemented and checked on 12 October 2026. These changes have not been published as a new signed release or submitted to Apple.

## Requested scope

- English by default; Russian, French, Spanish and Hebrew on every screen. A device-level language choice, including before sign-in; preserve drafts when it changes. Use right-to-left layout for Hebrew and keep codes, addresses and user content readable.
- ChatGPT accounts: recognizable plan and personal/workspace category, distinguish multiple accounts, actual subscription windows and reset times, a separate credit balance and additional reset passes when returned.
- Integrated, optional local dictation. First use explains and offers the download. Reuse installed assets; no dependency on launching another app. Keep a recoverable recording through interruptions and conversation changes.
- Clipboard images: Command-V, image preview and image-aware assistant input; ordinary text paste remains native.
- Remote setup is queued in [the server setup brief](server-setup-queue-2026-10-12.md), with current provider evidence and acceptance criteria. No purchase without a chosen offer and approval.
- English App Store copy and screenshots. Build 34 was still WAITING_FOR_REVIEW when checked on 12 October. Decide on replacement only after the new experience is verified.

## Implementation

- One shared catalog supplies the native and web interfaces. English is the default. The explicit choice persists, Hebrew uses right-to-left layout, and interpolated addresses/names stay isolated from surrounding bidirectional text. Names and conversations are user data, not translation inputs. Standard system permission descriptions have localized resources.
- Onboarding, device/account/backup/app settings, assistant settings, services, Telegram, model choices, computer access, voice, transfer, recovery and destructive-action copy use the catalog. Visible service notices and errors follow a language change. English, French, Spanish and Hebrew consistently call the characters assistants.
- Accounts show recognized plan names and a personal/workspace category only when the plan identifies it. Unknown plans are not inferred from an email address. Account selectors include identity and plan; duplicate identities have a short connection suffix. Subscription windows, reset times, credit balances and additional reset passes are separate. Missing information is not shown as zero. Initial loading, refresh and per-device state do not retain another device's cards.
- Dictation is integrated using Apple's on-device `DictationTranscriber` on macOS/iOS 26. It does not launch OpenRamble or another app and is not an embedded OpenAI speech model. First use checks existing assets without downloading. Download, progress, cancel, retry and unsupported-language states are explicit. Installed assets are reused. A recording remains recoverable after an interruption or failed transcription.
- The Mac composer now uses a native text view so image-only pasteboard data participates in the actual Edit > Paste / Command-V path. Ordinary text paste, undo, Return, Shift-Return and input methods retain native handling. Pasted images are checked by decoded format and dimensions; supported PNG/JPEG/WebP/GIF data keeps its original bytes, while TIFF/HEIC is converted to oriented PNG. Existing attachment limits remain in force.

## Verification

The disposable two-device fixture runs independent stores and TLS endpoints on this Mac. QA Mac and QA Mini are process names, not evidence of tests on two physical computers. Account balances and service states in these UI tests are fixtures.

| Check | Observed result |
| --- | --- |
| Native logic | 17 tests passed: attachment import/composer (8), dictation assets (3), interface language (4), account presentation (2). After final copy changes, the affected language and asset suites passed again (7 tests). |
| Backend and web localization | 14 account tests and 4 localization tests passed. TypeScript typecheck passed. Catalog tests check all five languages, interpolation slots, and absence of the standalone marketing term requested for removal. |
| Actual Mac application | English accounts with separate windows/credits/reset passes; personal and workspace examples; missing limits; changing languages and preserving drafts; image-only Command-V enabled in the native menu, visible preview, send and received image count; plain-text paste, multiline editing and undo. |
| iPhone Simulator | Fresh onboarding in all five languages; French, Spanish and Hebrew layouts inspected; Hebrew layout mirrors correctly. Pairing, consent, a test conversation, update/relaunch and persistence of connection/history/language passed. Model error and microphone-denied notice change language in place. |
| First-use dictation UI | Explicit download offered; after accepting, the model became ready and Start dictating requested microphone access. Denying access produced an actionable inline message without blocking chat. Installed assets may have been reused; this does not measure network download size or speed. |
| Actual speech recognition | A Russian audio fixture was processed by the real on-device module on Mac; the recognition and asset-installation tests passed (2 tests). This is synthetic recorded audio, not a live microphone or a five-language accuracy benchmark. |
| Actual model image input | The current product engine sent the pastry image to the real connected OpenAI account. The response correctly described a golden-brown cinnamon roll with two visible eyes. This complements the native paste-to-attachment transport check. |
| Account-recommended model | The live catalog marked `gpt-6-astra` as default. An explicit `gpt-6.1-sol` request was rejected as unsupported for this account. Automatic selection then used the account recommendation and completed the image test. The requested Sol/Medium fallback for a missing recommendation remains unchanged. |
| Browser | English and Hebrew layouts, narrow viewport, account loading/cards, separate credits, language switching with preserved draft and attachment contrast were inspected in the in-app browser. No console warnings or errors were observed in the final check. |
| Store screenshots | Both real-app screenshot tests passed on iPhone 17 Pro Max and iPad Pro 13-inch (M4), iOS/iPadOS 26.2. All four English captures were inspected, including the current smiling pastry icon. |

Private logs, screenshots, fixture scripts and results are under `.data/localization-2026-10-12/`. Key files: `native-verified.log`, `localization-copy-final.log`, `services-verified.log`, `typecheck-verified.log`, `voice-install-recognition.log`, `vision-proof.json`, `mac-clipboard-preview.png`, `mac-accounts-en.png`, `english-store.xcresult` and `store-screenshots/manifest.json`. No authentication material belongs in Git.

## Release boundaries and remaining checks

- Physical iPhone/iPad, camera QR scanning, live microphone recording, long/interrupted recordings on hardware and dictation accuracy in all five languages have not been revalidated in this pass. Native recording recovery tests and the Russian file transcription are narrower evidence.
- The current OpenRamble package and recording lifecycle were reviewed; its macOS-only inference package was not added as a second runtime. Apple dictation availability is checked per device and language.
- Paid server provisioning remains queued. The live WAI VDS catalog still disables OpenStrudel checkout; EQVPS and Vultr documentation are evidence of provider capabilities, not completed purchases or a production provider migration.
- [English store text and screenshots](app-store-localization-2026-10-12.md) are prepared. The metadata draft fits Apple's field lengths. Build 34 remains `VALID` and `WAITING_FOR_REVIEW` in the final live API check. Its review was not canceled, and these new language claims were not applied to the older binary.
- No new signed archive, Sparkle package, production install, web deployment or App Store submission is implied by these development builds and simulator checks.

## Sources

- [Codex account endpoints](https://learn.chatgpt.com/docs/app-server#auth-endpoints), checked against the JSON schemas generated by the installed Codex 0.156.1.
- [Apple DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)
- [Apple AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- OpenRamble LocalASR and DictationCore in the local repository, read on 12 October.
