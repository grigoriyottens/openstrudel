# English metadata for the localized release

The metadata and screenshots below are prepared, not applied to the pending App Store submission. The localized iOS build 35 was uploaded, processed as `VALID`, and verified in the existing internal TestFlight group as `IN_BETA_TESTING`. App Store Connect was rechecked on 12 October after release validation: version 1.0 still selects build 34, remains `WAITING_FOR_REVIEW`, and that binary is `VALID`.

Keep the current submission in review. These screenshots and the language claim must ship with the localized binary, not with build 34. If build 34 is approved first, publish this work as an update. Do not replace descriptive fields in a way that makes the reviewed binary inaccurate.

## Name

OpenStrudel

## Subtitle

Your everyday assistants

## Promotional text

Assistants for writing, research and everyday tasks. Start on your Mac and continue on iPhone or iPad. Now in five languages, with local dictation.

## Keywords

assistant,writing,research,notes,files,tasks,planning,productivity,chat,personal,dictation

## Description

OpenStrudel is a free app for everyday tasks, writing and research. Create an editor, a researcher or a personal assistant. Give each one instructions and keep its conversations and files together.

Your assistants use language models to reply and work on tasks. They run on your own Mac or server. Connect your iPhone or iPad to continue the same conversations wherever you have access to that device.

WHAT YOU CAN DO

- Chat with your assistants and return to earlier conversations.
- Share photos and files, or dictate a message on your device.
- Create assistants and change their instructions.
- Connect services and schedule recurring tasks.
- Choose an available model and speed for all assistants or just one.
- Use assistants on several connected devices.
- See each ChatGPT account's plan, available limits, reset times and separate credit balance when the provider supplies them.

YOUR LANGUAGE

The app starts in English. Choose Russian, French, Spanish or Hebrew in settings, or before connecting your first device. Changing the interface language keeps your conversations and drafts. Hebrew uses a right-to-left interface.

LOCAL DICTATION

Dictation is optional. On first use, choose a spoken language and download its model if needed. Models already available on your device are reused. After setup, speech is transcribed locally, without an internet connection. Review the text before sending it. Availability depends on the language and device.

GETTING STARTED

Download the free Mac app from waiwai.is/openstrudel. Sign in to your own OpenAI account with access to Codex and create an assistant. In the Mac app's device settings, generate a connection link. Open it on your iPhone or iPad, or scan its QR code in the app, then confirm the connection.

You can also connect to your own server running OpenStrudel. You create the connection yourself. No company account, invitation from the developer or registration with OpenStrudel is required.

WHAT YOU NEED

Keep the Mac or server running and connected to the internet. On the same Wi-Fi network, your iPhone or iPad can connect directly to your Mac. Access from another network requires remote access to that Mac or server.

Model availability and usage limits depend on your separate OpenAI account. You do not need a separate OpenAI sign-in or API key on your iPhone or iPad.

YOUR DATA

Conversation history and files stay on the device where the assistant runs. With your permission, messages, selected files and relevant context are sent to OpenAI to generate replies. Other services are used only after you connect them. Local dictation does not send your recording to OpenAI.

FREE TO USE

OpenStrudel and all its features are free of charge. There are no subscriptions, in-app purchases or ads. Your model provider and any hosting provider you choose may charge separately for their services.

## What's new

Choose English, Russian, French, Spanish or Hebrew, with a right-to-left interface for Hebrew. Dictate locally after an optional model download. Account settings now separate subscription limits, reset times and credits, and show each account's plan.

## Review-note addition

The interface now defaults to English and offers Russian, French, Spanish and Hebrew. The App Store screenshots show the English interface with example conversations. The current smiling pastry icon is unchanged. The app remains a free public consumer app and requires no organization membership.

Dictation is optional. Its first-use screen explains the local language model and offers an explicit download when necessary. The microphone is requested only when the user starts recording. Reviewers can use all other features without microphone access. The existing private review connection remains the normal entry point for review; revalidate it against the uploaded build before submission.

## Screenshot evidence

Captured from the real app using disposable English example content. Both UI tests passed; all four screenshots were visually inspected. The icon, navigation and conversation content are current. These are original simulator captures, without generated interface elements.

- iPhone 17 Pro Max, iOS 26.2: 1320 × 2868, assistants and conversation.
- iPad Pro 13-inch (M4), iPadOS 26.2: 2064 × 2752, assistants and conversation.
- Local artifacts: `.data/localization-2026-10-12/store-screenshots/`; test result: `english-store.xcresult`.
- Capture command lives in `StorePreviewUITests.testPublicScreenshots`; example data lives in `tests/fixtures/store-preview.ts`.

Build 35 was archived, validated and uploaded; its packaged icon and five locales were inspected. Both private-review paths passed with the actual server on the iPhone Simulator: open the page in Safari, and paste the page URL in a fresh app installation. Each connected, received a real model reply and retained history after relaunch. The private connection page now defaults to English and supports all five languages. Replace screenshots and metadata together with the selected localized binary when preparing its public App Store submission. Physical-device dictation and camera scanning remain open checks.
