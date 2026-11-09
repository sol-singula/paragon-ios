# Paragon for iPhone — working notes

Owner's brief (2026-11-09): "build a swift app for apple for a paragon app.
key things to consider are a matching ui to match our desktop app but also we
need to be able to ring the phone and send notifications".

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
- XcodeGen: `project.yml` is the project. The .xcodeproj is generated and
  gitignored. Config/Secrets.xcconfig is gitignored.
- CI (`.github/workflows/build.yml`) builds for the simulator, unsigned. Check
  it after a push; nothing else here compiles Swift.
- Commits: no model names in messages.
