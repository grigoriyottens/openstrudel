# Mac composer recovery, 13 October 2026

Build 37 is a macOS-only follow-up to [release 36](2026-10-13-server-recovery.md). The iOS target remains build 36, already available in internal TestFlight. Home 36 does not change in this patch.

## Reproduced defect

During an actual remote file-read acceptance check, the isolated Mac QA app sent its message successfully but stopped responding afterward. The server completed the request and preserved the reply. A three-second process sample showed the main thread repeatedly running SwiftUI layout and `ComposerTextField.sizeThatFits`, including changes to the live text container. The process used about one CPU core; this is not evidence that the earlier 30–40 GB report has the same cause.

SwiftUI proposes several widths while measuring a view. The composer applied those proposals to the displayed `NSTextView` text container, changing its frame and triggering another layout. Measurement now uses a separate AppKit text layout, leaving the editor, selection and scroll state unchanged. The field still wraps, includes a trailing empty line, grows up to six lines and scrolls longer drafts.

## Verification

- The regression failed before the fix: proposed widths changed the live editor frame and container size (nine assertion failures).
- All 166 native tests in 25 suites passed after the fix, including non-mutating measurement, wrapping, clearing after sending, trailing newlines and finite width handling.
- A fresh, isolated QA client connected to the real disposable Home 36 server using an ordinary one-use, non-owner invitation. No old Keychain permission was changed or bypassed.
- Repeating the exact request that triggered the hang completed in the UI. The assistant used a tool to read the existing `server-check-20261012.txt` and returned its original contents.
- A 15-line draft with English, Russian, Hebrew, French and Spanish stayed editable. Four long/short replacement cycles followed by clearing returned the field to its compact state. The app remained responsive; afterward the observed process used 0% CPU and about 62 MiB RSS. This bounded observation is not a long-running memory guarantee.

Private evidence is under `.data/release/2026-10-13-36/composer-fix/`, with the process sample and before/after test logs alongside it. Signing, public delivery and installation receipts for the Mac patch belong under `.data/release/2026-10-13-37/`.
