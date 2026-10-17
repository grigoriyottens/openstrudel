# OpenStrudel for Android

A native Kotlin / Jetpack Compose companion for OpenStrudel Homes. Employees
continue running on a connected Mac or server; Android uses the same Home API
as the Apple apps. It does not embed a second agent engine or a web view.

Requires Android 9 (API 28) or later. Use a current Home (build 48 or later) for
chat model selection, dictation, paged Telegram timelines and turn controls.
Features are offered according to the Home's capabilities and access rights.

## Build

Install JDK 17 and Android SDK platform 36. Point `ANDROID_HOME` or the ignored
`local.properties` at the existing SDK, then run from this directory:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest
android run --device DEVICE_SERIAL --apks app/build/outputs/apk/debug/app-debug.apk
```

The QA package is `is.openstrudel.android.qa`; distribution uses
`is.openstrudel.android`. They have independent private state. The Gradle heap
and workers are bounded; no emulator is required when a physical phone exists.

For a signed release, set `OPENSTRUDEL_ANDROID_SIGNING_PROPERTIES` to a private
properties file, or use `~/.openstrudel/android/signing.properties`. Its fields
are `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Keep it and the
keystore outside the repository, permission 0600. No credential is bundled in
an APK. Run `./gradlew :app:assembleRelease :app:lintRelease`, verify the APK
with `apksigner verify --verbose --print-certs`, and retain a staged copy and
its SHA-256 outside Gradle build caches before publishing.

## Connection and data

Open a one-time invitation, paste it, or use the native Google QR scanner.
The user reviews the Home before pairing. TLS accepts only the certificate or
public-key pin in that invitation; redirects never receive the credential.
The returned credential, drafts and outbox are encrypted with an Android
Keystore key in private non-backup storage. Connection removal is committed
before logout, so a late server reply cannot restore a removed connection.
Uncertain pairing and message retries use their original operation identifiers.

Dictation uses the recognition provider configured on the employee's Home.
A recording produces editable text; it never submits the text automatically.
Images and documents use Android's system picker. Attached files remain private
until sent. Pending uploads and drafts survive a restart. Downloaded copies are
bounded; old unreferenced draft copies are removed on startup.

The public HTTPS invitation route needs an Android App Links statement at
`https://waiwai.is/.well-known/assetlinks.json` for the **release** package and
its signing certificate. Preserve other apps' statements when deploying it.
The custom `openstrudel://` route also supports the website's explicit open button.

## Tests

Unit tests cover invitation parsing, TLS pins/expiry, redirect isolation,
idempotency, HTTP recovery and data merging. Device tests use isolated TLS
fixtures for persisted pairing, removal during an in-flight refresh, full-row
navigation, drafts, duplicate sends, editable transcription, per-chat settings
and arrival of new replies. They do not impersonate successful provider calls.

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
adb -s DEVICE_SERIAL install -r app/build/outputs/apk/debug/app-debug.apk
adb -s DEVICE_SERIAL install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s DEVICE_SERIAL shell am instrument -w -r \
  -e class app.openstrudel.CompanionTest,app.openstrudel.HomeTransportTest \
  is.openstrudel.android.qa.test/androidx.test.runner.AndroidJUnitRunner
```

Use the explicit instrumentation command when retaining QA connections:
Gradle's `connectedDebugAndroidTest` uninstalls the target after its run.
The fixture tests restore the previous encrypted state. `LiveTransportTest`
is an opt-in, read-only network diagnostic (`-e liveRead true`); do not count
its skipped default run as real Home acceptance. Physical-device evidence and
known limits are in `docs/android-acceptance-2026-10-17.md` at the repo root.
