# External Telegram notifications

`POST /hooks/telegram` relays prepared text through the Home's existing Telegram
connection. It does not invoke an AI engine. The route is available on the local
HTTP listener and the remote HTTPS listener.

An operator enables it with the `telegram.notification_hook` setting:

```json
{"chatId":"<connected destination>","tokenHash":"<SHA-256 hex of a dedicated random token>"}
```

Keep the token with the sending service, separate from the Home owner token.
Requests need `Authorization: Bearer <token>`, a stable `Idempotency-Key` (up to
200 letters, digits, dots, underscores, colons or hyphens), and JSON containing
`text` (up to 32,000 characters). Extra fields cannot change the destination.
The destination must remain connected and enabled.

A 200 response contains the existing Telegram outbox receipt and confirmed
message IDs. Repeating an identity returns its stored receipt without sending
again; changing its text returns 409. Unconfirmed delivery returns 502 and is
never automatically resent under that identity. Inspect Telegram and the saved
receipt before any manual recovery. Removing the setting disables the endpoint.

Remote callers must verify TLS. For a Home using its self-signed certificate,
pin the SHA-256 digest of the DER-encoded public key (SPKI), obtained through
the trusted deployment connection. Do not disable TLS verification globally.
