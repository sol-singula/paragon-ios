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
- **Look.** `Design/Theme.swift` is the desktop's dark theme colour for colour.
  Branch circles follow the desktop's `lib/branches.ts` (SO orange, SH green,
  JG blue, BS white, everything else purple). Atlas is always the violet ring.
- **Calls.** Identity = member id, same as the desktop, so both ring.
  CallManager owns CallKit, PushKit and Twilio Voice; every callback is on the
  main queue. A VoIP push must always be reported to CallKit (iOS kills the app
  otherwise), even one that turns out not to be a call.
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
