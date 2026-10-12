# Simple server setup

Requested on 12 October 2026. The existing-server flow is implemented and published in build 35. A disposable local Ubuntu VM was created for installation acceptance; no paid provider account, order, payment or production migration was performed. The integrated purchase proposal below remains dependent on provider access and an approved offer.

## Product decision

Keep one entry, **Connect a device**, with **Mac** and **Server**. Server offers two clear actions: **Set up my server** and **Get a server**. A server is another device where assistants run. There is no primary device and no personal/work requirement.

Ship the existing-server path first. It works with the user's choice of provider and does not depend on completing a new billing service. The app handles installation after the user provides access; it must not ask a nontechnical user to copy shell commands or installation JSON.

## Set up my server

1. Address, sign-in name, and **SSH key / Password**. Accept an IP address or hostname, suggest a common sign-in name without assuming it is correct, and place the port under additional settings. Offer a file picker for the key and a separate field only when its passphrase is needed.
2. **Check connection** is read-only. Confirm the SSH host identity, supported OS and resources, existing OpenStrudel installation, permissions and network reachability. Explain a failed check in the same screen and keep the entered address.
3. Show the detected server and the concrete installation action. Reuse a matching installation. Never overwrite a different installation, user data or a changed SSH host key silently.
4. **Install OpenStrudel** uses the existing pinned release and bootstrap protocol. Show confirmed stages: connecting, installing, starting, checking access. Only show a percentage for measurable work such as transferred bytes.
5. Add the device only after its authenticated HTTPS endpoint passes readiness and identity checks. Then open ChatGPT sign-in on that device and offer **Create an assistant here**.

Store a retained private key only in Keychain. Do not persist a password by default or place secrets in command arguments, URLs or logs. Closing the setup screen must leave a resumable installation record, not trigger a second installation. Do not open unrelated firewall ports or change the server's existing workloads.

## Get a server

Show one suitable offer with the full amount, currency, billing period, region and renewal terms. Offer the payment methods actually returned for that offer. The user should not need a separate infrastructure dashboard. Hosted payment can return to the saved order; returning from checkout is not proof of payment.

Resume the same order after a network failure or app restart. A paid order can still be installing. Show these states separately. Do not retry an unknown provisioning result as a fresh purchase. Make the device's expiry, renewal, export and deletion actions discoverable in its settings.

Keep the existing iOS release scope: connect to a prepared device. Any future iOS purchase flow needs its own product and store-policy decision.

## Provider recheck

| Option | Confirmed on 12 October | Decision |
| --- | --- | --- |
| WAI VDS / Kamatera | The live [OpenStrudel catalog](https://server.waiwai.is/api/v2/openstrudel/catalog) returns `live_gated`, `purchase_enabled: false` and `home_live_acceptance_pending`. The profile is 4 GiB / 30 GB / public IPv4; card and USDT amounts are null. | The integration exists, but there is no purchasable offer yet. Complete real Home acceptance before exposing checkout. A provider change alone does not remove this work. |
| EQVPS | The [reseller API](https://eqvps.com/en/docs/reseller) supports branded plans, client orders and `test: true` dry runs. Orders spend the reseller balance. The [payment guide](https://eqvps.com/en/docs/paying) describes crypto and an external card-to-crypto path. | Best next candidate to validate for an integrated alternative. Confirm SSH-key/bootstrap support, unknown-order recovery, full prices and payment/renewal behavior before selecting it. A dry run does not prove a running OpenStrudel device. |
| Vultr | The [official API](https://www.vultr.com/api/) provides instance creation, SSH keys and `user_data`. Its [billing documentation](https://docs.vultr.com/support/platform/billing/what-payment-methods-do-you-accept) lists card and digital-currency payments through BitPay. | A credible route for users bringing their own account. These capabilities do not by themselves provide an embedded OpenStrudel checkout. |
| DigitalOcean | The repository already has an OAuth/bootstrap path. It was not reprovisioned in this pass. | Preserve it while validating the simpler server setup. |

Do not choose a new production provider solely because it accepts crypto. The next comparison should measure successful setup, recoverable failures, support, total recurring cost and actual owner access. Obtain the current API schema and run the free EQVPS dry run first. A paid pilot needs a selected offer and spending limit.

## Acceptance

- Fresh supported server with a password, a key and an encrypted key; incorrect access and unavailable address.
- Existing installation, unsupported OS, insufficient resources, occupied ports and changed SSH identity.
- Sleep, app restart, dropped network and installation timeout; resume without a duplicate runtime or scheduler.
- Create an assistant on the server from the laptop, receive an actual model reply, reconnect after a server restart and verify persistent history.
- For purchases: declined, delayed and completed payment; duplicate notifications; expired offer; unknown provisioning result; renewal and confirmed deletion.

This brief extends [the earlier cloud work](easy-cloud.md) and [checkout contract](integrated-cloud-checkout.md); it does not describe those older checks as newly repeated.

Implementation update: the Mac address/password/SSH-key setup path and named DigitalOcean entry are published in build 35. See [current acceptance evidence](release-35-acceptance.md). The local VM installation, real SSH authentication, interrupted-installation resume, remote employee creation and archive export were verified. Paid provisioning and provider migration remain separate from this result.
