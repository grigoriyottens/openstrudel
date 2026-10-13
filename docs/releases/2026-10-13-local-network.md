# Mac server setup and local-network access, 13 October 2026

Build 39 follows Mac 38, including its account-management improvements. The iOS target remains build 38. This Mac-only patch preserves the published Home runtime from build 38.

## Reproduced issue

On a clean server-setup journey, the Mac app reported that the server did not respond even though the same endpoint was reachable from Terminal. macOS recorded a local-network privacy denial for the app's short-lived `ssh-keyscan` helper while its permission prompt was still pending. Terminal's successful connection did not establish permission for the app.

The app now declares its local-network purpose and keeps a Network.framework TCP connection to the requested SSH endpoint alive while macOS requests permission. It sends no application data or credentials. After the endpoint becomes ready, the existing OpenSSH host-key verification and authentication run unchanged. Back cancels the connection; a 30-second deadline bounds the wait. If local-network permission remains unavailable, the error names the relevant System Settings pane.

This follows [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), including its short-lived-helper limitation. It does not change system permissions, bypass host-key checking or grant network access automatically.

## Verification

- All 172 native tests in 26 suites passed, including actual loopback connections, bounded failure, pending cancellation and cancellation before startup. All 367 runtime tests and TypeScript typechecking passed after integrating account release 38.
- A separately signed QA app with a distinct executable UUID reproduced the pending-permission case. After the user accepted the macOS prompt, the native wizard reached SSH identity confirmation, authentication and Ubuntu preflight, then began installing Home 36.
- The displayed SSH fingerprint matched the server's independently inspected public host key.
- A controlled restart of the disposable Lima VM regenerated its SSH host keys through cloud-init. The app correctly rejected that changed identity. This fixture behavior must not be counted as a successful native SSH retry or fixed by weakening host-key checks.

## Fresh-server acceptance

After the user accepted the local-network prompt, the native flow installed Home on a disposable Ubuntu 24.04 ARM64 VM. The final sheet offered ChatGPT sign-in, copied the device code and opened the official OpenAI authorization. A fresh sign-in completed, the sheet displayed the connected account, and **Create an assistant here** opened a new assistant on that server.

Two real requests then completed through the native composer: calculating 17 × 23 with a tool, and creating `server-first-task.txt`. The attachment opened in Quick Look. Independent inspection confirmed two `exec` tool calls, four completed message records, one attachment and an intact database. The file contains `OPENSTRUDEL_CLEAN_SERVER_391` followed by a newline, is 29 bytes and has SHA-256 `8e52347311414b4a81496f866517d375dc2a5c1f4db4ef2b04e134c6a9a2e4dd`.

The VM's installer was resumed through its local console after host disk exhaustion and the SSH-key rotation described above. The native client subsequently resumed the saved pinned HTTPS connection. This proves the first-sign-in and useful-task flow; it does not turn that fixture recovery into a successful native SSH retry.

## Failed-release recovery

The exact preserved failed Home 35 staging directory was copied privately to a second disposable local Ubuntu VM. The working paid QA Home was left intact. The original recipe reached a real failed systemd state after rejecting the changed download digest. The current, unmodified `server-setup.sh` then accepted the corrected release digest and installer, reset the failed attempt budget, and completed Home 38 installation on its first attempt.

The bootstrap bytes, installation ID and owner-token hash were unchanged. The HTTPS certificate's public key matched the original saved private key; employee data without authentication returned 401. Authenticated local health, SQLite integrity and the shipped sandbox probe passed. This is a real server-side retry of the preserved recipe on another disposable VM; the original Mac recovery record was not rewritten and an old native-client reconnect is not claimed by this check.

## Delivery

- [PR #22](https://github.com/mikwiseman/openstrudel/pull/22) merged as `4248e66d6f402eafeab2ca38c4565cf7466a155b`.
- The Mac application and DMG were Developer ID signed, notarized, stapled and accepted by Gatekeeper. The [immutable Mac 39 download](https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-39-arm64.dmg), current Mac alias and signed Sparkle feed were published atomically with rollback copies. Downloaded hashes matched. DMG SHA-256: `8c89c732585f5c7744bd2411632bec92151c1172b84b9dcbbc1e00d2118cc664`.
- A real isolated Sparkle installation updated build 38 to 39 and relaunched the signed result. Its temporary public feed was removed afterward.
- Mac mini was backed up, then its application bundle was replaced atomically. The bundled Home 38 runtime was unchanged, so its running process was retained. All six employees, 15 conversations, 1,944 messages, three schedules, three connected accounts and existing Telegram settings survived. Native settings, Telegram health and the public updater passed; the rollback snapshot was marked healthy.
- The App Review Home was updated separately from 36 to 38 using a new image and copied volume, with the original container and volume retained for rollback. Its identity, certificate, account, settings and existing records survived. The sandbox probe and a real calculation-tool request passed. Mac 39 has no additional Home changes.
- iOS remains build **38**, independently verified as `VALID` and `IN_BETA_TESTING` for the internal **Mik** group. Build 39 changes only macOS. The public App Store submission remains build 34 in `WAITING_FOR_REVIEW`; it was not cancelled or replaced.
- After acceptance, Kamatera confirmed deletion of the exact approved paid QA VM. Both local test VMs were stopped and deleted; the 4.08 GiB unused Ubuntu image cache was removed only after an open-file check. Production data, Codex history, active simulators, release archives and rollback evidence were preserved. The host had approximately 24 GiB free afterward; this is an observation, not a storage reservation.

Private logs and test results are under `.data/release/2026-10-13-37/` and `.data/release/2026-10-13-39/`. The latter includes fresh-server screenshots and database evidence, notarization receipts, public artifact verification, updater installation, local deployment, App Review deployment/tool execution and TestFlight state. Credentials and the preserved failed-install fixture are excluded from Git.
