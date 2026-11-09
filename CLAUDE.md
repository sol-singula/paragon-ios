# Paragon for iPhone — working notes

Owner's brief (2026-11-09): "build a swift app for apple for a paragon app.
key things to consider are a matching ui to match our desktop app but also we
need to be able to ring the phone and send notifications".

- **Never behind the desktop** (founder, 2026-11-09: "ANYTIME we make changes
  to paragon, we update the site, ios app and web app. ALWAYS."). Every
  Paragon feature lands here too, in the same change: desktop release, the
  solbuild.net/paragon copy, and this app. If this app is behind, catch it up
  before calling the work done.
- **One contract.** The desktop app (repo `sol-singula/paragon`, web/src/lib/api.ts)
  is the reference for every function name, argument and shape. Add a screen by
  calling the same `public.paragon_*` function the desktop calls; never add
  rules here. Server changes go in the paragon repo (migrations, functions).
- **An outage never signs anyone out** (founder, 2026-11-09). Only a
  definitive auth answer (refresh token invalid, not found or revoked) ends
  the session; a network error, timeout or 5xx keeps it, `Session` retries
  with backoff and RootView shows "Reconnecting…". A failed data call never
  signs out. Same rule as the desktop's `web/src/lib/connection.ts`.
- **Look.** `Design/Theme.swift` is the desktop's dark theme colour for colour.
  Branch circles follow the desktop's `lib/branches.ts` (SO orange, SH green,
  JG blue, BS white, everything else purple). Atlas is always the violet ring.
- **Calls.** Identity = member id, same as the desktop, so both ring.
  CallManager owns CallKit, PushKit and Twilio Voice; every callback is on the
  main queue. A VoIP push must always be reported to CallKit (iOS kills the app
  otherwise), even one that turns out not to be a call.
- **Call sounds** (founder, 2026-11-09), the desktop's too: incoming rings
  "Low Classic" (`Sounds/ringtone-low-classic.caf`, CallKit's
  `ringtoneSound`); outgoing plays "Pulse" (`Sounds/ringback-pulse.caf`,
  AVAudioPlayer) from `callDidStartRinging` to connect or end. `Sounds/` is a
  resources entry in project.yml. 44.1 kHz mono PCM, one 6 s loop each.
- **Notifications.** paragon-push sends APNs for `paragon.notifications` rows
  and personal-line texts. No automatic texts to customers come from here:
  everything the app sends is a person pressing Send.
- **It is an Xcode project** (owner, 2026-11-09): `Paragon.xcodeproj` is
  committed and the owner opens it as it is. `project.yml` is its source:
  change targets and settings there, push, and CI regenerates and commits
  the project once it builds. Never hand-edit the .pbxproj. The config with
  the public anon key is committed so it opens with nothing to fill in.
- CI (`.github/workflows/build.yml`) builds for the simulator, unsigned. Check
  it after a push; nothing else here compiles Swift.
- Commits: no model names in messages.
- **Caught up 2026-11-09** with the desktop's 0.10.13: Team chat (tab, channels,
  paging, faces, @mentions, photos/GIFs in `paragon-team` through signed
  links, reactions on long-press, reply, edit/delete, the per-channel bell,
  DND), photos in and out of customer texts (`paragon-shared`, then
  `paragon-send` with `attachments`), emoji, faces on what we sent (by name
  from `paragon_team`, Atlas's ring for Atlas), presence (the desktop's
  Realtime channel `paragon-presence`, keyed by member id; green dot, red
  phone for `on_call`), the house photo full screen, "Founder" for the
  owner role (`Role.label`), and a read-only Costs for founders. Lines admin
  stays desktop only.
- Storage goes through Supabase Storage's REST endpoints (`Core/Storage.swift`),
  not the SDK, like every other request here. `muted_until` / `dnd_until` can
  be `"infinity"` (`TeamTime`). Team reads poll (4 s in a channel, 15 s for
  the overview) where the desktop uses Realtime.
- **Round 2, 2026-11-09** (desktop 0.10.14): previews are one line ending
  in "…" (`Preview.line`); hold an inbox or Personal row to Release
  (`paragon_thread_release`, `ReleaseSheet`); founders and managers tap a
  teammate's face in Team (or the Personal menu) to open their personal line
  (`paragon_personal(p_member)`, `Router.personalOf`); Contact info
  (`ContactInfoSheet`, `paragon_person` + `paragon_person_details`) from a
  conversation or a Personal thread; "Who is this?" (`WhoIsThisBar`) while
  `ask_type`, and a "New" tag on Personal rows. No owner's name anywhere:
  `threads[].owner` and `history[].owner` are not decoded.

- **Search and the hour's light, 2026-11-09**: the Inbox, Personal and Team
  lists sit on `DayGlow` (`Design/DayGlow.swift`, the desktop's `lib/phase.ts`
  phases and hues), a still gradient re-read every two minutes that
  crossfades once on a change; never a repeating animation or a blur (that
  is what made the Setter app slow). Inbox search is the desktop's: as you
  type (2+ characters, 300 ms) `global_search` plus `paragon_queue` with
  `p_search`, grouped, and every client or conversation has Text and Call
  (`SearchHitRow`). A lead with no conversation opens `NewMessageSheet`
  filled from `paragon_lead_contact`; Call starts the thread, then calls.

- **The mockup's look, 2026-11-09** (founder-approved `paragon-ios-screens`):
  the tab bar is ours (`Design/TabBar.swift`, `ParagonTabBar`): flat, full
  width, panel at 94% with a hairline, teal for the chosen tab, rose counts.
  The system bar is hidden on every screen (`hidesSystemTabBar()` on each
  tab root and each pushed screen), so iOS 26's glass pill never shows; the
  bar steps aside for the keyboard and inside a customer conversation. Tab
  roots and conversations draw their own top bar (`TopBar`,
  `ConversationHeader`) with the system navigation bar hidden; the edge
  swipe back is kept by the UINavigationController extension there. Section
  headers are `SectionLabel` / `Section(label:)`: small, uppercase,
  letter-spaced. Branch marks are solid circles with white letters (dark on
  Blackswan's white).

- **Instant send, 0.10.15 (build 2), 2026-11-09** (founder: "the second we
  hit send, it should go to the conversation"): Send never waits. Texts go
  to `Outbox` (`Core/Outbox.swift`), Team posts to `TeamOutbox`: the bubble
  shows at once with the local pictures, our face and "Sending…", the box
  clears and keeps the keyboard; uploads and `paragon-send` /
  `paragon_team_post` run behind, one at a time per thread so order holds.
  A text steps aside when the timeline has its `message_id` (or the same
  words out within two minutes); a Team post as soon as the post answers
  with the message. A failure stays rose, "Not sent · Tap to retry", with
  the server's reason, and Delete in its menu. The stores outlive the
  screen. Every rule is still the server's (line, locks, STOP). The build
  number goes up with every upload.

- **Promises and the one inbox, build 3, 2026-11-09** (the paragon repo's
  CLAUDE.md, "Promises and the one inbox", is the contract): hold an inbox
  or Personal row, or open the conversation's ⋯, for **Add promise…**
  (`Features/Promises/Promises.swift`, `PromiseSheet`): WHO from
  `paragon_promise_people` (me first, greyed with `why_not`), WHEN (In 1
  hour, 4 PM today, Tomorrow 9 AM, or the picker), WHAT (200 characters).
  A promise given to someone else takes the row off my inbox at once
  (`InboxModel.clear`) and `Toast` says "Promised to Ryan · due 9:00 am".
  The Atlas guide is gone: a row with `atlas` (or items) is a conversation
  row tinted violet with a thin violet edge and one who · when · what line
  (`QueueRow.itemLine`); its menu has Done, Not needed, Hand to…, Change…
  (promises through `paragon_promise_*`, other cards through
  `paragon_atlas_card_act`). Most urgent is the server's order
  (`sort_key`, plain code-unit compare); overdue is rose and relative to
  `due_at`. A conversation lists its open promises at the top
  (`OpenPromises`, `paragon_thread_promises`, never the owner's name). The
  tab's count is waiting rows plus my overdue promises. Every new queue
  field is optional, and items decode leniently (`LossyList`, `Lenient`).
