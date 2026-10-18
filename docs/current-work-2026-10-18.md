# OpenStrudel — memory incident and long recordings

## Memory incident, 18 October

The owner supplied the macOS application-memory warning showing OpenStrudel at
19.59 GB. The matching system CPU report is for **1.0 (49)**, PID 61168, on
macOS 26.4 (25E246). At 22:59–23:00 MSK on 17 October, the GUI used one full CPU
core and its footprint grew from 647.97 MB to 1342.77 MB in 85.47 sampled seconds.
The app was not frontmost and the user was idle. Most sampled work is on the
main thread in SwiftUI graph transactions, including lazy-row phase/layout
updates. This implicates UI rendering; it does **not** yet identify an exact
source-level trigger or prove an operating-system defect.

The public Sparkle feed and installed app both report 49. Main is `4d52874`,
with Apple/Home release source `de19fd0`; there is no newer published memory
fix. Do not report this incident fixed by updating or restarting.

The original GUI had already exited before inspection. Home PID 61189 remained
running. A bounded diagnostic GUI launch (PID 38892) stayed around 154–172 MB
through background observation, scrolling, resizing, switching employees and
a real arithmetic answer. A subsequent 24-paragraph response also completed,
with observed footprint around 170–171 MB. Neither test reproduced the runaway
growth. No speculative application patch or production restart was made.

Private evidence: `.data/memory-2026-10-18/` contains the system report, live
sample, bounded-run scripts and measurement JSONL. A further check after
restoring the background transcript and resizing its long reply measured a
168.3 MB footprint (185.7 MB peak), without reproducing the incident.
After the bounded investigation, the task's own diagnostic GUI was quit through
its normal menu. PID 38892 exited; the pre-existing Home PID 61189 remained
running and `/health` still returned `ok: true`. No user application, remote
access service or other task's process was terminated.

**Latest monitoring instruction:** the owner explicitly cancelled the
12-hour schedule again. Both the original `mac-mini` automation and its later
replacement `mac-mini-openstrudel` have confirmed deletion. Check resources
only during active work, especially before expensive operations; do not
recreate a heartbeat. The owner allows pausing the parallel `wai remote` task
if resources are actually insufficient, but its working remote-access service
must not be stopped. No such intervention was needed in this investigation.

Native cache pruning found no eligible caches. The parallel AiGid task cleaned
its confirmed idle Sparkle extraction cache; do not repeat that cleanup or
claim it as an OpenStrudel intervention. No heavy build was started during its
archive. After AiGid finished, WAI Remote was told that OpenStrudel currently
needs no native build, so the heavy-operation queue is available to it. The
original release archives, dSYM, user state and other chats' work remain preserved.

## Added: long voice recordings

Wai Reflections message 1679289 is the owner's 10:54 recording on 18 October;
WaiClaw replied in 1679290 that only five minutes are accepted. The personal
Telegram MCP confirms these messages. Earlier 135-second message 1679144 failed
with the local recognizer's timeout; it was already successfully transcribed
through ElevenLabs during build-48 testing.

Current source has the five-minute guard in the **local Linux recognizer**
(`src/voice.ts`), not in the ElevenLabs branch of `transcribeRecording`.
Mini and Wolf were verified on ElevenLabs, but the previous handoff explicitly
left WaiClaw/CLO's upgrade and speech configuration unverified because SSH
access was rejected. Recheck that deployment before assuming a new UI or
ElevenLabs change fixes the actual user's bot.

### Verified full recording

The original Telegram file was downloaded through the personal Telegram MCP's
`get_files` operation. It is a complete 2,395,764-byte Opus/Ogg file; parsing all
657 Ogg pages verifies 654.354 seconds of audio. SHA-256:
`59e09b3a2aa77b91a853a6f41ab3b6559c3dc74c8091ced92cce0b9659c4df99`.

The **installed Mini Home 49**, configured for ElevenLabs/Scribe v2, accepted
the entire file at `/v1/speech/transcribe` and returned text in **18.04 seconds**.
The private transcript and receipt are in `.data/voice-2026-10-18/`. No file was
shortened or split, no Telegram message was sent, and no application source
change was needed for this result. This proves the full-file transcription path
on Mini, not WaiClaw's deployment or perfect word accuracy.

The current ElevenLabs branch bypasses the local Linux recognizer's five-minute
guard. The documented WaiClaw/CLO root SSH login still rejects Mini's existing
key. The 1Password desktop integration also times out, preventing retrieval of
another saved credential through that route. No keys, passwords, host pins or
access rules were changed. WaiClaw's actual provider/build still needs direct
verification and an end-to-end reply after access is restored.

In progress:
- Restore documented access to WaiClaw and inspect its installed build/provider;
  deploy/configure ElevenLabs there, with backup and health checks.
- Remove avoidable duration limits with bounded decoding/memory where needed;
  distinguish provider/Telegram file limits from arbitrary app limits.
- Verify transcript-before-answer and delivery in the real personal flow.
- Validate, back up, deploy only verified changes, and check health afterwards.
- Keep the GUI-memory incident open until its trigger and correction are proven.

Preserve the 17 October handoff's unrelated unfinished acceptance items and all
other chats' work. Do not restore the intentionally deleted employees.
