# App Review access

The App Store review depends on `https://magic.mikwiseman.com/openstrudel-review/`.
The full URL, including its private fragment, lives in App Store Connect's review
notes. Do not put it, account credentials, or `runtime.env` in Git.

## Independent deployment

Host: `62.238.6.198`. Deployment: `/opt/openstrudel-review`.

- Compose project `openstrudel-review`, container `openstrudel-review-home-1`.
- External volume `openstrudel-review-data`: database, provider login and Home TLS
  identity. Its name never contains a release number; Compose cannot remove it.
- `.env` selects an immutable image tag. `runtime.env` keeps the original setup
  code, public host `magic.mikwiseman.com`, public port `27789` and setup port `8080`.
- Copy `../docker/seccomp.json` alongside this Compose file and retain the normal
  `openstrudel-container` AppArmor profile. The runtime verifies its sandbox at start.
- The existing `telegram-core_default` network joins the review service to Caddy.
  The setup port is published only on loopback; the pinned Home port is public.
- `Caddyfile` is a persistent fragment in `/opt/telegram-core/Caddyfile`. Preserve
  it when updating Telegram's proxy. Validate then reload Caddy; do not replace
  its config with only the Telegram route. Caddy's data volume retains HTTPS state.

Normal Home or desktop updates do not redeploy this project. A review Home update
changes only the image tag, keeping the volume, environment and proxy route.

## Before submitting or updating

1. Preserve a consistent rollback copy of this deployment and its data volume.
   Include its secrets in the protected backup, never in release artifacts.
2. From outside the server, put the full review URL in a mode-600 local file and run:

   ```sh
   node scripts/check-review-access.mjs /private/path/review-page.txt
   ```

   This checks public HTTPS, page assets, the original setup code and the Home's
   advertised address and TLS identity. It creates a new unclaimed invitation:
   run it as a deployment gate, not periodically while a reviewer is connecting.
   Paired devices remain connected. `/openstrudel-review/healthz` is a safe
   read-only availability probe; the container also checks its setup server.
3. Apply the image update with `docker compose --project-directory
   /opt/openstrudel-review up -d --pull never`. Wait for `healthy`, repeat the
   external check and verify an already paired app still reads history and replies.
4. Test a clean installation on the supported device sizes: original URL in Safari → open
   app → connect → open assistants → data consent → real reply → relaunch.
   Also test pasting the HTTPS page into the app's connection field.

For simulator tests, keep code signing enabled. `CODE_SIGNING_ALLOWED=NO` omits
the simulated Keychain entitlements and makes enrollment fail before the network
request. Ad-hoc simulator signing is enough; use the normal release entitlements.

Never reinstall this host or remove the proxy/network/volume as routine cleanup.
Before a necessary host migration, restore the review deployment elsewhere,
preserve its setup code and Home key, move DNS and prove the same URL and an
already paired device work. Keep review access available throughout App Review.

## Availability alerts

The existing WAI monitors on the public edge and WaiWeb check
`/openstrudel-review/healthz` every five minutes. They confirm consecutive failures,
deduplicate alerts and report recovery to the owner's private Telegram chat.
Their checked-in definitions are `deploy/monitoring/checks-edge.json` and
`checks-waiweb.json` in the `waiwai` repository. Keep this check when moving hosts.
The probe does not mint invitations or send model requests.

## Recovery on 27 October 2026

The 14 October host reinstall removed the old review deployment and HTTPS route
while App Store Connect still referenced it. Recovery used the external restic
snapshot from 14 October, restoring only the isolated review data and its access
identity. The ordinary Home and Telegram bridge were retained.

The original URL/code was checked against the backup. The external access check
first reproduced the TLS failure, then passed after restoration. The recovered
OpenAI subscription returned a real reply. Keep the current review's device-test
and submission receipts with the private release artifacts.
