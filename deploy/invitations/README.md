# App invitation links

QR codes and sharing use
`https://waiwai.is/openstrudel/connect.html#<encodeURIComponent(native invitation)>`.
The fragment carries the one-use invitation and TLS pin. It never reaches the
website, proxy logs, or analytics. The native app accepts only this exact HTTPS
origin/path or the existing `openstrudel://connect` format, then asks the person
to confirm the destination. An invitation does not connect automatically.

The website and the app must both opt into universal links. Merge this entry
into the existing `applinks.details` array in the site's
`.well-known/apple-app-site-association`, preserving other apps and credentials:

```json
{
  "appIDs": ["R4A779QVVY.is.openstrudel.ios"],
  "components": [{"/": "/openstrudel/connect.html"}]
}
```

The iOS app entitlement includes `applinks:waiwai.is`. Its provisioning profiles
must also include Associated Domains. Apple caches website associations; verify
the signed build on a real device using Camera or a link in Notes. Entering the
URL into Safari's address bar is not a universal-link test. Old app versions and
browsers, including the Mac, fall back to this standalone page's explicit **Open
OpenStrudel** button. Pasting either format into the app works on both platforms.

The Android release uses the same HTTPS invitation route. Merge the statement in
`native/Android/assetlinks.json` into `.well-known/assetlinks.json`, preserving
other apps. Its certificate fingerprint must match the signed release APK.
Verify on a real Android device with `pm verify-app-links --re-verify
is.openstrudel.android` and `pm get-app-links is.openstrudel.android`; the result
must be `verified`, not a manually forced approval. Then open an HTTPS invitation
through an implicit browser intent and confirm that the native review appears.

The documented website origin is `root@65.108.215.2`:

- HTML: `/var/www/waiuni/apps/web/public/openstrudel/connect.html`
- Association: `/var/www/waiuni/apps/web/public/.well-known/apple-app-site-association`
- Android association: `/var/www/waiuni/apps/web/public/.well-known/assetlinks.json`
- Nginx include: `/var/www/waiuni/deploy/openstrudel/nginx-connect.conf`, included
  by `/etc/nginx/conf.d/wai-origin.conf`
- CDN sync: `systemctl start wai-web-showcase-push.service`

Inspect the current files, take timestamped backups, atomically replace changed
files, run `nginx -t`, and reload only if the configuration changed. Sync the
edge, check the public HTML and association JSON, and restore on failed checks.
No application rebuild or database change is needed. Never put a real invitation
in a test report, shell argument, tracked file or screenshot.
