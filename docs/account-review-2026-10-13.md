# Account consistency and follow-up decisions, 13 October 2026

## Reproduced and fixed

The existing Mini had two connections with the same OpenAI user subject and workspace. Adding a duplicate now refreshes the retained account, preserving its name, priority and assistant assignments. Different workspaces under the same email remain separate. Consolidation waits for active work and pending sign-in; it never calls provider logout. Credentials and provider identity claims are not returned to clients.

Native settings cleared their login state before awaiting the account refresh. That canceled the SwiftUI task performing the refresh, leaving the menu updated but settings stale. Completion now applies the refreshed list first. Open settings poll for changes made from another client. Overlapping reads cannot publish an earlier identity or account catalogue.

Accounts can be renamed from their action menu. Their actual email remains visible below the chosen name. Personal/workspace subscription information stays separate from that user-defined name. Subscription limits, reset dates and credits are available in an expandable section, with no device picker when there is only one device.

Provider outages retain the last known identity and show an unavailable state. The reported disappearance of one of five real accounts was not reproduced exactly. The fixes cover stale reads and lost identity presentation; they are not proof of the historical cause of that incident.

## Verification

- 36 focused TypeScript tests pass: duplicate merge, different people/workspaces, missing claims, active-run deferral, an in-flight token refresh, repeated completed-login polling, catalogue races, five-account outage/recovery, owner-only rename routes and conversation-context preservation. Typecheck and browser syntax check pass.
- Four native account presentation tests and 20 account recovery tests pass. One run hit a temporary file-protection error in the unchanged pending-message test; the complete recovery suite passed on rerun.
- The real Mac UI was driven against an isolated Home using simulated OpenAI responses: rename, duplicate sign-in with no added row, new-account sign-in appearing without reopening settings, six-account list, limits/credits, unavailable state and automatic recovery. A web rename propagated into the already open Mac settings.
- The browser UI was driven through its owner invitation and account settings; rename, compact sections and email/plan presentation were inspected. Browser console had no errors or warnings. The invitation overlay now closes when an invitation is accepted in an already open tab.
- Build 38 was installed and driven on an iPhone 17e simulator running iOS 27: onboarding, account settings, rename, retained email/plan, weekly limits, reset date, credits and extra resets. An initial run reproduced keyboard autocorrection replacing a typed account name when Save was pressed. Autocorrection is now disabled for that field; the rebuilt app preserved the exact typed name. A physical iPhone was not tested in this run.
- Installed production Mac build 38 was inspected against the updated Mini Home. All three unique accounts and the Rename account action were visible. The duplicate migration preserved the six assistants, 15 conversations, 1,944 messages and three schedules, including assistant account assignments and Telegram bindings.
- Synthetic sign-in proves the local completion and merge paths, not a fresh human OAuth authorization. Production credentials were inspected only for equality; their contents are not included here.

Private screenshots and logs are under `.data/account-identity-qa-2026-10-13/` and the scoped `/tmp/openstrudel-account*` test logs. The [build 38 delivery record](releases/2026-10-13-account-consistency.md) distinguishes the public Mac update, production installations and internal TestFlight availability.

## WAI Core Team

Read-only inspection of the Mini confirmed that the Telegram integration was running, the group binding was enabled and approved, and incoming messages on 13 October were processed. The sampled recent messages completed with the configured no-reply outcome; no failed messages were recorded since 12 October. No new test message was sent to the working group. This is not a claim that every connected service has been exercised.

## Next cloud connection

Keep **Create server** as the primary action. Before payment, show the provider, its current price and the fact that the server is billed separately. Open the provider's own authorization/billing page, return to OpenStrudel, then provision, install, connect and finish with ChatGPT sign-in. Never ask a nontechnical user to copy an API key in the primary path or collect their raw card details in OpenStrudel.

| Provider | Integration and payment | Decision |
| --- | --- | --- |
| DigitalOcean | Native OAuth with PKCE and dynamic client registration is already implemented. Provider billing supports cards and several wallets; new accounts may still need verification or a billing setup step. | Complete the existing route; describe it as guided setup, not an unconditional one-click purchase. |
| Vultr | Official OAuth supports third-party apps and scoped access. Provider payment methods include cards and crypto. General availability requires a funded developer account, HTTPS callback, requested scopes and Vultr's app approval. The client secret belongs on a backend, not in the native binary. | Best next direct-provider candidate. Prepare registration and an allowlisted test first; do not ship an unavailable button before approval. |
| Hetzner | The documented Cloud API setup asks the user to create and copy a project API token. Card, PayPal and bank payment options exist. | Useful for existing customers through the server/SSH route, but not the next simplest consumer onboarding. |
| WAI VDS | The current hosting service takes payment for a managed WAI offer, then provisions underlying capacity. | This is a managed resale, not a payment forwarded directly to an independent provider. Label it accordingly if offered. |

Suggested copy: “Hosted and billed by DigitalOcean. OpenStrudel is free. Manage your server subscription with DigitalOcean.” Use the actual provider name and live quote. Avoid promising a final price from an old cost estimate.

Official sources checked on 13 October 2026: [DigitalOcean OAuth](https://docs.digitalocean.com/reference/api/oauth/), [DigitalOcean billing](https://docs.digitalocean.com/platform/billing/pay-bills/), [Vultr third-party OAuth](https://docs.vultr.com/platform/iam/oauth/access-tokens/how-to-integrate-a-third-party-app-with-vultr-oauth), [Vultr payments](https://docs.vultr.com/platform/billing/make-account-payments.md), [Hetzner API tokens](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/), [Hetzner payments](https://docs.hetzner.com/general/billing-and-account-management/billing-at-hetzner/payment-overview/).

## OpenRamble: current implementation

The composer microphone still uses Apple's on-device speech framework. Telegram voice messages on Mac use the installed OpenRamble CLI; both supported executable paths are present on the Mini. Linux Home uses bundled whisper.cpp. Windows composer dictation and an embedded cross-platform OpenRamble engine have not shipped.

The [dictation direction](dictation-direction-2026-10-12.md) remains a proposal: a model downloaded on first microphone use, recognition on the speaking device, partial decoding while recording, then text in the current draft. Installing or linking a second app should not be required. The model must cover Hebrew as well as English, Russian, French and Spanish; the current Parakeet model alone does not. A natural-speech comparison is required before claiming a quality improvement.
