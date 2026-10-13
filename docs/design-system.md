# OpenStrudel design system

A warm, quiet workspace where small strudel helpers do the work, and the conversation is the hero.

This is the contract for the Mac app, the iPhone and iPad app, and the local web UI. Every value here is deliberate. If a screen needs a value that is not listed, add it here first.

## Principles

1. **Content first, chrome steps back.** The transcript is the main area. The sidebar, toolbar and composer are quiet controls around it. Liquid Glass is only for controls, never for messages or cards.
2. **Native before custom.** System sidebar, toolbar, Settings window, grouped forms, alerts, menus and buttons. Custom drawing only where the product is unique: the transcript and the characters.
3. **One accent with three jobs:** the primary action, links, and selection or focus. Nothing else is plum. On macOS, system selection and focus show plum when the user's accent colour is Multicolor (the default).
4. **Hierarchy from weight and colour before size.** A screen uses at most four text sizes.
5. **Shared edges.** Text in a column starts on one vertical line. Control edges line up with the column edges.
6. **The characters carry the personality.** Everything around them stays plain.

## Type

One superfamily: SF Pro for the interface and reading, SF Pro Rounded for display, SF Mono for code. They are designed together, share metrics, and cover Latin, Cyrillic and Greek; Hebrew falls back automatically to SF Hebrew and SF Hebrew Rounded. No custom fonts.

| Role | Mac | iOS (Dynamic Type) | Web |
|---|---|---|---|
| Display: welcome, onboarding, empty conversation name | SF Rounded Semibold 28 | `.system(.title, design: .rounded, weight: .semibold)` | `--font-display` 590, 28/34 |
| Title: sheet and pane titles inside content | SF Semibold 17 (`.title2.weight(.semibold)`) | `.title3.weight(.semibold)` | 17/22 590 |
| Reading: messages, composer, instructions editor | SF 15, `lineSpacing(3)` = 15/22 | `.body`, `lineSpacing(4)` = 17/24 | 15/22 |
| Interface: rows, labels, buttons, settings | SF 13 (`.body`) | `.body` | 13/16 rows, 13/20 multi-line |
| Meta: time clusters, status, file sizes, captions | SF 11 (`.subheadline`) | `.footnote` | 12/16 |
| Code (blocks and inline) | SF Mono 13, `lineSpacing(4)` = 13/20 | `.subheadline.monospaced()`, `lineSpacing(5)` | `--font-mono` 13/20 |

- Settings descriptions may use the system Form footer style (12 on Mac). No other size exists.
- The chat screen uses 15, 13 and 11, plus 17 only when a reply has headings.
- Weights: Regular, Medium, Semibold. No Light or Thin.
- Markdown headings stay small: H1 and H2 are 17 Semibold, H3 to H6 are 15 Semibold (iOS: `.title3.weight(.semibold)` and `.headline`). 16 above a heading, 4 below.
- Tabular figures (`.monospacedDigit()`, `tabular-nums`) for times, counts, percentages and prices. No manual letter-spacing.
- Web stacks, zero downloads:
  - `--font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI Variable Text", "Segoe UI", Roboto, "Noto Sans", "Noto Sans Hebrew", "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji"`
  - `--font-display: ui-rounded, -apple-system, BlinkMacSystemFont, "Segoe UI Variable Display", "Segoe UI", Roboto, sans-serif`
  - `--font-mono: ui-monospace, Menlo, Consolas, "DejaVu Sans Mono", monospace`
  - Weights 400 / 510 / 590 so a browser on a Mac renders the same SF instances as the app. Safari renders the native faces exactly; Chrome and Firefox on a Mac render SF for text, SF (not Rounded) for display and Menlo for code.

## Space and shape

- Layout gaps: **4, 8, 12, 16, 24, 32, 48.** The Mac window edge is 20; iOS margins are 16. Line heights (16, 20, 22, 24) are not spacing.
- Text-box paddings are optical and listed per component below.
- Radii (always `.continuous`): **8** dense controls; **12** code blocks, file chips, cards, tables, images; **20** message bubbles; **24** composer. Web only: **6** inline code. Nested shapes are concentric: inner radius = outer radius minus padding.
- Avatars: **24** (toolbar, the helper), **32** (sidebar), **64** (details header), **96** (empty conversation, welcome).

## Colour

Warm low-chroma neutrals and a richer plum. Values are light / dark / light increased contrast / dark increased contrast. Every text token passes 4.5:1 on canvas, surface and user bubble in all four appearances (computed).

| Token | Values | Role |
|---|---|---|
| `CanvasColor` | `#F7F3EC` / `#1C1B1A` / `#FFFDF8` / `#121110` | main window background |
| `SurfaceColor` (new) | `#EEE9E1` / `#262422` / `#EFE9E1` / `#211F1D` | code blocks, file chips, cards, table header, multi-author messages |
| `UserBubbleColor` (new) | `#E7DAE9` / `#382E3A` / `#E2D2E5` / `#3E3341` | the person's message bubble |
| `SeparatorColor` (new) | `#DCD5CB` / `#3A3633` / `#8F887F` / `#77726D` | hairlines, table rules, quote rule, increased-contrast strokes. Never an input border |
| `AccentColor` | `#74407A` / `#8E5A98` / `#5E2C64` / `#865390` | fills, selection, focus, the send button. White on it: 7.6 / 5.2 / 10.4 / 5.8 |
| `AccentText` (new) | `#74407A` / `#D3A8DC` / `#5E2C64` / `#E8C9EE` | links and accent text on the canvas |
| `SecondaryText` | `#615B57` / `#ADA8A3` / `#45403C` / `#D2CEC9` | supporting text and meta |
| `WarningText` | `#865021` / `#DFB681` / `#6D3B12` / `#F6D3A3` | warnings |
| `DestructiveText` | `#A82029` / `#FF8A91` / `#850A12` / `#FFC7CB` | destructive text; destructive buttons use `role: .destructive` |

- `MetadataText` is removed; meta uses `SecondaryText` at the meta size.
- Primary text is the system `.primary`. Success is the accent plus a word or symbol. Colour is never the only signal of state.
- Increased contrast: the user bubble, code blocks, file chips and tables add a 1-pt `SeparatorColor` stroke.
- The canvas is the main window only. Sheets, the Settings window, popovers, menus and grouped forms keep system backgrounds.
- Web only: `--control-border` `#86808C` / `#7C7781` / `#6F6A74` / `#8F8A94` for inputs (≥ 3:1).

## Characters

- The main assistant is the brand bun from the app icon without its tile (`Agent-main`), so every row in the sidebar is a character. The app icon tile stays for the Dock, About and the menu bar.
- **The helper.** One character sits at the "now" edge of every conversation: 24 pt at the leading text edge, 12 below the last transcript item. Idle, it is still. While the employee works, it proofs like rising dough (scale x 1.03, y 0.95, anchored at the bottom, ease-in-out 0.9 s, repeating) beside "{Name} is working…" in meta style. When a reply lands, it plops once (scale y 0.86 over 90 ms, then a spring back, response 0.35, damping 0.55); iOS adds a soft haptic. The loop pauses when the window is inactive. Reduce Motion: no scale, a 150 ms fade of the words only.
- **Offline.** When an employee's device is offline, its character renders desaturated at 60 % opacity in the sidebar, toolbar and helper, and its preview reads "Offline". It returns over 0.4 s with the character spring.

## Mac structure

- **Window:** `NavigationSplitView` with the system glass sidebar and the conversation as detail. `.windowToolbarStyle(.unified(showsTitle: false))`; no hidden title bar. The canvas is set with `.containerBackground(AppTheme.canvas, for: .window)`. Minimum window 760 × 560. The per-device view identity lives on the detail column only, so switching devices never resets the sidebar.
- **Sidebar:** `List(selection:)` over a `SidebarItem` enum (main, draft, employee, Telegram group per device), `.listStyle(.sidebar)`, width min 220 / ideal 260 / max 340. Row: avatar 32, 8 gap, name 13 Medium over preview 13 Regular secondary, one line each; no row backgrounds, padding or separators (the system draws selection). Context menu via `contextMenu(forSelectionType:)`; Delete key via `onDeleteCommand` on the list. Section headers per device only when there are several. Search: `.searchable(placement: .sidebar)` with ⌘F; no results use `ContentUnavailableView.search`. New employee: sidebar toolbar `plus`, ⌘N. Bottom inset: the hidden-employees row (only when some are hidden) and one device row that opens the Settings window, aligned with the rows above.
- **Detail toolbar:** a navigation item with avatar 24 + name (13 Semibold, max width 240) that opens the employee's details (also ⌘I); the Telegram source menu as a primary action when the employee has Telegram chats. The system draws the glass. Content scrolls under the toolbar with the scroll-edge effect.
- **Transcript column:** centred, max width **560**, at least 24 from the detail edges (about 71 Russian or 82 English characters per line at 15 pt; the primary audience reads Russian).
- **Bars:** connection banner and OpenAI recovery notice in `safeAreaBar(edge: .top)`; Telegram hint, new-messages button and composer in `safeAreaBar(edge: .bottom)`. No custom fades or bar backgrounds.
- **Settings window (⌘,):** `TabView` with `Tab(_:systemImage:value:)` panes Devices, Accounts, Backups, General; the selected pane persists in `@AppStorage` so other screens can route to a pane and call `openSettings`. Each pane is a `Form` with `.formStyle(.grouped)`, width 600, height between 360 and 720. Row contract: one `Section` per group with an optional footer; switches as `.toggleStyle(.switch).controlSize(.mini)`; two to five exclusive options as `.pickerStyle(.radioGroup)`; read-only values as `LabeledContent` with the value in secondary; actions as their own rows; destructive actions last with `role: .destructive`; Help and Privacy as `Link` rows in one section. No cards, no hand-made dividers or headings.
- **Sheets:** multi-page sheets use `.presentationSizing(.form)` on the sheet's `NavigationStack` so pushes never resize them; single-page sheets use `.fitted`. Buttons go in `ToolbarItem(placement: .cancellationAction / .confirmationAction)`. Confirmations are `.alert` or `.confirmationDialog` with `role: .destructive`.

## iOS structure

The current navigation stays: conversation as the root of a `NavigationStack`, the employee list in its sheet, settings in its sheet with the existing identifiers. The principal toolbar item is the same avatar + name. The composer sits in `safeAreaBar(edge: .bottom)`. All tokens apply through text styles so Dynamic Type works to AX5. Hit targets 44.

## Transcript

- **The person (one-to-one):** trailing bubble, `UserBubbleColor`, radius 20, padding 16 × 9 (one line is a 40-pt capsule), max width 75 % of the column (420).
- **The employee:** open text on the canvas, leading-aligned, full column width. No bubble, no avatar per message, no author label.
- **Multi-author conversations** (imported history, Telegram groups): other people's messages are leading-aligned on `SurfaceColor`, radius 20, with "Anna · 12:04" above in meta style.
- **Rhythm:** 24 between turns, 8 between consecutive messages from the same side, 12 between paragraphs, 4 between list items, 16 above and 4 below a heading.
- **Time:** a centred cluster header in meta style when a new day starts or after a gap of 30 minutes or more ("Today, 12:02"; day only when a message has no time). Exact time: `.help` on Mac and `accessibilityValue` everywhere. Schedule and notice lines keep their time. Queued, failed and error states stay visible under their message.
- **Markdown:** lists use a fixed marker column so bullets and right-aligned tabular numbers share one text edge. Quotes: 2-pt `SeparatorColor` rule, 12 gap, secondary text. Links: `AccentText`, underlined at rest (underline at 40 % accent); only `https`, `http` and `mailto` stay links, natively and on the web. Inline code: SF Mono 13 on `SurfaceColor`. Code blocks: `SurfaceColor`, radius 12, padding 12, copy button on hover (Mac) or always (iOS). Tables: `SurfaceColor` header, hairline rules, a column whose cells are all numbers is trailing-aligned with tabular figures; horizontal scroll when wider than the column.
- **Files:** chips on `SurfaceColor`, radius 12, padding 12, icon 20, name 13 Medium, size in meta. Images radius 12, max 320 × 240.
- **Right to left:** each block aligns by the direction of its first strong letter, so English in the Hebrew interface stays left-aligned and Hebrew in the English interface is right-aligned. Directional symbols use `forward` and `backward` variants.

## Composer

Liquid Glass, radius 24, minimum height 48, growing to 8 lines and then scrolling. Its edges are the transcript column edges. Mac: 32-pt controls with 8 padding. iOS: 44-pt targets with 2 vertical padding. Leading `plus` menu; trailing microphone and send. The send button is the only tinted element: an accent circle with a white arrow when there is content, the system disabled state otherwise; with an empty field while the employee answers it becomes Stop. With text while the employee answers, the steer / after-the-reply menu sits before the microphone. The queue tray and attachment chips sit inside the glass above the text. Text uses the reading style with the same line spacing as the transcript. Placeholder: "Message {Name}". Drop target: 2-pt accent stroke at the same radius. No glass inside the composer.

## Empty states and onboarding

The character, one sentence, at most one action. Empty conversation: character 96 at 40 % of the height, the name in display, the role in at most two lines of 13 secondary within 360; the focused composer is the action. Welcome and onboarding: character 96, display title, body leading-aligned when it runs past two lines, one prominent capsule button. Optically centred at 40 % from the top.

## Motion

Layout: `.smooth(duration: 0.25)`, no bounce, under 300 ms. Characters only: springs with response 0.35 to 0.5 and damping 0.55 to 0.8. Press feedback on press. Reduce Motion: fades only.

## Web UI

Mirror the Mac layout and tokens at 1 pt = 1 px: CSS custom properties for every colour in light, dark and `prefers-contrast: more`; the same sidebar, transcript, helper and composer; the same type scale (meta raised to the 12 px floor). Markdown is rendered by a DOM-only renderer (never `innerHTML` for message content): raw HTML is text, only `https`, `http` and `mailto` links, images become links. Each message is one `<article>`. Follow the latest message only when the reader is near the bottom. SVG icons, no text glyphs. Form controls inherit the font. Logical properties and `dir="auto"` for right to left. `prefers-reduced-motion` and `prefers-reduced-transparency` respected. Modals: title, content, a bottom bar with Cancel first and one primary action last.

## File ownership (for parallel work)

`RootView.swift`, `Sidebar.swift`, `ConversationView.swift`, `Transcript.swift`, `Composer.swift`, `EmployeePicker.swift`, `EmployeeDetailsView.swift`, `Onboarding.swift` and `SharedViews.swift` replace `Views.swift`, so each surface has one owner file.
