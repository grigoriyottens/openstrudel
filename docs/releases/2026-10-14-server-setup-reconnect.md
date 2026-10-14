# Resume server setup after a lost connection

The own-server installer could show “The server did not respond” after one failed SSH status request, even while its systemd job continued successfully. A retry used SSH before checking the already-running Home and replayed the installer for an active job. Pending setup was accessible only inside the add-device wizard.

The native flow now keeps its existing bounded polling loop through a connection interruption, including a lost acknowledgement of the installation command. It checks the pinned, authenticated Home first on retry, observes an active or completed matching job without reinstalling, and still stops immediately on authentication, host-key or installation-identity failures. A pending recipe has one direct continuation row in My devices. The continuation sheet uses one destination value, avoiding two independently changing presentation flags.

## Verification

- Three new regressions were observed failing before the fix: lost status response, lost installation acknowledgement, and a ready server unnecessarily requiring SSH. They pass after the change. Authentication and identity failures remain terminal; the existing ownership and release-replacement tests also pass.
- 48 native tests across server setup, SSH readiness, AgentMetal recovery and localization passed. The AgentMetal fixture now closes an in-progress interrupted installation instead of expecting a transient network failure to be terminal.
- 24 shell-installer and localization tests passed. The Release Mac app built successfully and passed deep signature verification with the existing Developer ID identity.
- The existing real server had already completed its original installation. The corrected Release binary was exercised in a separate QA bundle: My devices → Continue server setup → Checking server → Your server is ready → Open server. It authenticated the saved HTTPS identity, added the device and removed the pending setup without entering SSH credentials again. The server remained on its original installation attempt (1); no rebuild or reinstall was performed.

## Local installation

The verified setup fix was installed atomically on the owner's Mac on 14 October. The bundle still identifies as 1.0 (42); its native executable SHA-256 is `ffa6cec98c29d223528f854aec0a92bef0ca13ae82aae7b0f8516a1941db68d1`. A new managed rollback snapshot was created first. The bundled runtime code is unchanged: the 31 differing Mach-O files have identical CodeDirectory hashes, identifiers and signing teams, with signing-envelope differences only. The running Home services were retained.

After relaunch, the real My devices screen showed This Mac online (1 assistant), Mac mini online (7), and the new server online (4). Existing Wai Core Team history reopened. All 23 local SQLite databases passed integrity checks, and core profile/conversation/message counts did not decrease relative to the rollback snapshot. This local binary contains the setup recovery fix; the newer sidebar, naming and presence prototypes in the working tree are not included.

Private red/green logs, staged apps, screenshots and the local rollback receipt are in `.data/server-setup-reconnect/`. A separate QA bundle and Keychain namespace exercise the pending-setup UI against the owner's existing server. Test initialization stays outside the production app and source change. No credentials belong in this document or Git.

This is a local Mac fix. It does not claim a newly published download, a fresh server installation, a paid hosting-provider acceptance run or an iOS release.
