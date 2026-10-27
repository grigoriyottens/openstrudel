# App Review recovery — 27 October 2026

App Store Connect accepted iOS **1.0 (61)** for review at **05:18:20 UTC**.
Both the version and submission report `WAITING_FOR_REVIEW`; build 61 is `VALID`.
This is a submission receipt, not App Store approval.

Apple rejected build 34 because its review URL returned a connection error.
The 14 October host reinstall had removed the isolated review Home and HTTPS
route. The original URL and access identity were restored from the external
backup, without restoring the retired OpenClaw services.

- The [review deployment](../../deploy/review/README.md) keeps the data volume,
  setup code, TLS key and proxy route independent of Home image updates.
- A forced container recreation retained the original identity. A previously
  paired client authenticated, read its history and received a real model reply.
- The original public URL passed the external page, assets, invitation and TLS
  checks after recreation.
- Release build 61 passed `AppleReviewUITests.testPrivateReviewPageConnectsAndAnswers`
  on a physical iPhone 14 Pro Max with iOS 27.0.1: **1 passed, 0 failed, 0 skipped**.
  Safari → open app → connect → open assistants → data consent → real reply →
  relaunch with history. The iPhone 17 simulator passed the same scenario.
- The owner waived the separate iPad run. No iPad validation is claimed.
- Existing WAI monitors check the endpoint every five minutes from two servers
  and send confirmed failure/recovery notices to the owner's private Telegram.
- A quiesced backup of the review data and configuration was copied to the
  encrypted external repository and read back with a matching SHA-256.
- Public data notices and invitation lifetime were corrected and verified on
  the live website. App Store descriptions and review instructions were updated.

Apple received this reply:

> The review access link has been restored. We tested the connection and AI replies in build 61; both are working.

Private URLs, backups, account data, native test results and API receipts remain
under `.data/app-review-2026-10-27/`, outside Git.
