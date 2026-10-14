# AgentMetal: direct checkout and resumable setup

This implementation is newer than the public build 42. The user chose AgentMetal first and deferred EQVPS, including its partner balance and resale model. DigitalOcean and existing-server SSH setup remain available. The other agent's merged design is reused without a separate redesign.

## Implemented flow

Connect a device → Get a server with AgentMetal → choose 1, 7 or 30 days → review the total → pay the provider in the browser → install OpenStrudel → connect ChatGPT through the existing account setup.

The app offers a compatible public IPv4 server from the live catalog, excluding shared-address plans that cannot expose Home. On 14 October the Small offer was 4 GB RAM, 80 GB storage and $2.20/day; the initial seven-day total was $15.40. The provider checkout uses its Ubuntu 24.04 image. Existing-server setup also supports Ubuntu 26.04 LTS, as described below. These are catalog observations, not a fixed future price promise.

Card details remain in Stripe. No provider account is required for checkout. The screen states that the rental is prepaid without automatic renewal and that the provider deletes an expired server after its two-hour grace period. Native rental extension is not implemented; the official provider documentation is linked. Do not describe this as indefinite hosting.

## Recovery and safety

- A durable request ID is saved before checkout; retrying an uncertain result reuses the same request and order. A changed quote is shown before payment can continue.
- Order details, the one-time private-key receipt, the SSH host key, installation recipe and verified Home connection live in Keychain. Completed orders are retained when another server is requested.
- Polling checks secure storage before consuming the provider's one-time response. If storage locks during the response, the receipt remains in memory until it can be saved; another provider request is not issued first.
- The first observed SSH key is pinned before commands. This is first-use trust, not an independently supplied provider fingerprint. The VM's self endpoint must match the paid server ID and IP before setup proceeds.
- The provider firewall opens only Home's HTTPS port 7789 and verifies the resulting rule by readback. Existing rules remain; unauthenticated port 8080 is not opened.
- Installation uses the existing pinned Home installer and resumes the same owner, key and installation ID after a retry. Closing a sheet saves progress. Erasing local app data prevents a late provider response from recreating credentials.
- A real UI check exposed competing first-open polling tasks and cancellation shown as a network error. The initial poll is now triggered once, and URLSession cancellation remains cancellation.

## Verified

- 46 native tests across AgentMetal, server setup, local erase and localization pass. Regressions were observed failing before fixes for locked storage, changing prices, canceled checks and Ubuntu 26.04 rejection.
- 54 installer/runtime/localization tests pass. The actual firewall Python runs against controlled HTTP fixtures: correct instance, expired instance, existing port, verified new rule and a write that is not reflected on readback.
- The native setup coordinator is exercised through an interrupted installation, app/client reconstruction, probe, exact-recipe retry, verified connection, and saved completion. No additional checkout or one-time key fetch occurs. This is a fixture, not a real provider VM.
- The signed Mac QA app reaches the live offer, displays the seven-day total, selects one day, opens a real Stripe checkout for $2.20, retains the order after closing/restarting and checks that same order again.
- The final polling correction was checked in the signed app after restart and after closing/reopening the sheet: the saved $2.20 order resumes polling without a false cancellation/network error. The exit action correctly stays “Continue later” when returning to an existing order. Screenshot: `.data/provider-acceptance/agentmetal-final-pending.png`.
- The native UI test opened a separate unpaid checkout. Its reference is retained privately; its extra browser tab was closed. The earlier intended API checkout is also retained. Neither is evidence of payment, and only one must be paid for the pilot.
- No EQVPS balance was funded and no paid EQVPS server was created.

## Existing-server Ubuntu versions

The SSH setup screen and error message now say Ubuntu 24.04 LTS or newer in all five interface languages. The native preflight and bundled installer accept LTS releases from 24.04, including 26.04, while retaining architecture, memory, storage, privilege, existing-data and runtime checks. Non-LTS releases are not advertised as supported.

Docker's repository suite is read from the server's validated OS release instead of always writing `noble`. Tests execute the actual shell functions for both `noble` and `resolute`, reject older/non-LTS/malformed releases, and preserve conflicting repository configuration. The new host check and repository rendering passed on the existing Ubuntu 26.04 server, with output written only to a temporary directory and removed. Existing Docker 29.7.2, Compose 5.4.0 and AppArmor were observed; production packages, containers and data were not changed. The final signed Mac QA app displays the updated English requirements without clipping (`.data/provider-acceptance/ubuntu26-setup.png`). A fresh end-to-end installation on an empty 26.04 VM is still unverified. [Docker's official Ubuntu installation guide](https://docs.docker.com/engine/install/ubuntu/) lists 26.04 LTS and uses the OS codename for the repository.

## Still required

The original intended checkout was still `pending`, without a server, at the latest API check. Card entry is a user step. Complete one payment and then verify the actual public VM, automatic installation, normal ChatGPT authorization, first real tool/chat request, app/server restart, and recovery. Record actual provider identity and expiry privately. Do not mark the full paid journey accepted from the fixture or the open Stripe page.

Build 42 and its design are already released independently. The new AgentMetal source can merge without claiming that its paid pilot or a new binary release is complete. Physical iPhone microphone/camera, an actual native drag gesture and fresh Google authorization retain the separate boundaries in the main work ledger.

Private receipts, screenshots and red/green logs: `.data/provider-acceptance/`. Public references: [AgentMetal documentation](https://agentmetal.dev/docs/), [expiry and renewal](https://agentmetal.dev/docs/#expiry), [API catalog](https://api.agentmetal.dev/v1/catalog). No checkout session, SSH private key or account credential belongs in Git.
