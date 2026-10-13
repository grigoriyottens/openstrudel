# Account consistency, 13 October 2026

Build 38 adds account names, duplicate sign-in consolidation and consistent account state across native settings, the menu bar and the web. The underlying email and subscription remain visible. Temporary provider failures retain the last known identity. The [account review](../account-review-2026-10-13.md) describes the reproduced defects, test coverage and remaining limits.

## Source and validation

PR [#21](https://github.com/mikwiseman/openstrudel/pull/21) merged into `main` at `d26800071ae267130bc7149ce70db8b946684922`. The release artifacts were built from `3551f9a2587a00f44b8961e630e37c0a02ab0782`, whose tree matches that merge. Later Mac build 39 changes follow this release; they are documented separately in [local-network access](2026-10-13-local-network.md).

- 36 focused runtime tests, four native account presentation tests and 20 account recovery tests passed, along with TypeScript typechecking and browser script syntax checks.
- Real Mac, browser and iPhone simulator interfaces were exercised against an isolated Home with simulated provider responses. Rename, duplicate and new-account sign-in completion, six-account presentation, unavailable state, recovery and changes arriving from another client were checked.
- The iPhone run exposed and verified a fix for autocorrection changing an account name on Save. No physical iPhone or new human OpenAI authorization was exercised in this release check.

## Distribution

The Developer ID-signed Mac app and DMG were accepted by Apple's notarization service, stapled and accepted by Gatekeeper. The signed Sparkle feed and stable Mac download were published as build 38. The Home archive and its stable alias were also published. Public downloads were fetched and their SHA256 values matched the release artifacts; the download page returned successfully.

| Artifact | SHA256 |
| --- | --- |
| [Mac 38 DMG](https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-38-arm64.dmg) | `fd6f6252b47cbb7456a755b93a389821023f4f7457e1ef5a48ed4caac2cc26de` |
| [Home 38 archive](https://waiwai.is/openstrudel/downloads/OpenStrudel-Home-1.0-38.tar.gz) | `23ed4a6b62fedad1d10505cb1960c625e16f52374eb012e2cb515650e35f23b5` |

The iOS archive was signed and uploaded to App Store Connect as build 38, ID `1f9b1295-d6c7-471c-a9e0-86e4481343a2`. Apple processing reached `VALID`. The build was assigned to the existing internal TestFlight group, and a subsequent API read confirmed `IN_BETA_TESTING`. English testing notes were saved. This is internal TestFlight availability, not a public App Store release or external beta approval.

## Production installation

Mac build 38 and Home 38 were installed on the Mini and MacBook after quiesced rollback snapshots. Runtime health and SQLite integrity checks passed. Both rollback snapshots were marked healthy after verification. The installed MacBook app was visually inspected while connected to the Mini; the Mini's native process was checked, but its window was not separately inspected.

On the Mini, four account rows became three unique accounts. All three connected identities were retained. The migration preserved six assistants, 15 conversations, 1,944 messages, three schedules, assistant account assignments and Telegram bindings. The MacBook's local records were also unchanged. Telegram was running on the Mini after restart with no connection error.

Private evidence is in `.data/account-identity-qa-2026-10-13/`: `release38-mini-receipts/` contains publication and Mini deployment checks, `release38-signed/local-deployment.json` records the MacBook update, and `release38-v2/ios-testflight.json` records the Apple build state and group relationship. Credentials and message contents are excluded from this document.
