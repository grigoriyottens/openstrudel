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

Private logs and test results are under `.data/release/2026-10-13-37/`. Signing, distribution and deployment evidence for build 39 will be recorded separately after validation completes.
