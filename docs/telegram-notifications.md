# External Telegram notifications

`POST /hooks/telegram` relays prepared text through the Home's existing Telegram
connection. It does not invoke an AI engine. The route is available on the local
HTTP listener and the remote HTTPS listener.

An operator enables it with the `telegram.notification_hook` setting:

```json
{"chatIds":["<connected destination>","<another connected destination>"],"tokenHash":"<SHA-256 hex of a dedicated random token>"}
```

`chatIds` is a list of 1 to 10 distinct destinations. The Home still accepts the
earlier form with a single `"chatId":"<connected destination>"`.

Keep the token with the sending service, separate from the Home owner token.
Requests need `Authorization: Bearer <token>`, a stable `Idempotency-Key` (up to
200 letters, digits, dots, underscores, colons or hyphens), and JSON containing
`text` (up to 32,000 characters). Extra fields cannot change the destinations.
Every destination must remain connected and enabled. If one of them is not, the
Home rejects the request with a 400 error and sends nothing to any destination.

The Home keeps a separate delivery identity for each destination under the same
`Idempotency-Key`. When the sender repeats a request, the Home reuses the stored
receipt of each chat it already tried under that identity and never sends to
that chat again. If the sender repeats an identity with changed text, the Home
returns 409.

A 200 response means that Telegram confirmed delivery to every destination. With
one destination, the response contains the existing Telegram outbox receipt and
confirmed message IDs. With several destinations, it contains `sent`, `status`,
the first destination's `chatId`, and `deliveries`, which holds one such receipt
per destination in the configured order:

```json
{
  "sent": true,
  "status": "delivered",
  "chatId": "<connected destination>",
  "deliveries": [
    {"sent": true, "status": "delivered", "chatId": "<connected destination>", "title": "...", "messageId": "...", "telegramMessageIds": ["..."]},
    {"sent": true, "status": "delivered", "chatId": "<another connected destination>", "title": "...", "messageId": "...", "telegramMessageIds": ["..."]}
  ]
}
```

If Telegram does not confirm delivery to one or more destinations, the Home
returns 502 and never resends those deliveries automatically under that identity.
The 502 body has an `error` message. With several destinations, it also has
`sent` set to false, the receipts in `deliveries`, and a combined `status`:

- `unknown` means the Home cannot tell whether at least one destination received the text.
- `pending` means an earlier request is still sending to at least one destination.
- `partial` means some destinations received the text and Telegram refused the others.
- `not_sent` means Telegram refused every destination.

Inspect Telegram and the saved receipts before any manual recovery. Removing the
setting disables the endpoint.

Remote callers must verify TLS. For a Home using its self-signed certificate,
pin the SHA-256 digest of the DER-encoded public key (SPKI), obtained through
the trusted deployment connection. Do not disable TLS verification globally.
