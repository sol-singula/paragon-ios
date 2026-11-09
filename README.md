# Paragon for iPhone

Paragon by solbuild on the phone: the inbox, Personal, notifications, and
calls that ring the phone like a phone. Same look as the desktop app (its dark
theme, branch circles, Atlas's violet ring), same server: every read and write
is a `public.paragon_*` function, texts go through `paragon-send`, calls
through `paragon-voice`. Nothing here has its own rules.

## Open it

**Open `Paragon.xcodeproj`** in Xcode. That's all: the project, the config
(`Config/Secrets.xcconfig`, the server and its public key) and the packages
(Supabase, TwilioVoice) are all in it. Xcode fetches the packages the first
time it opens.

1. Pick the **Paragon** target → **Signing & Capabilities** → your team.
   Bundle id `net.solbuild.paragon`.
2. Choose your iPhone (plugged in, or on the same Wi-Fi) and press Run, or
   Product → Archive for TestFlight.

Calls and notifications need a real iPhone; the simulator can't ring.

`project.yml` is where targets and settings are changed. Every push to
`main` is built on a Mac by GitHub Actions, and once it builds the
regenerated `Paragon.xcodeproj` is committed back, so pull before opening.

## Notifications (one-time, owner)

Every row Paragon adds to a member's notifications (missed call, a reply
clock running out, Atlas cards, promises), and every text in on their personal
line, is pushed to their iPhones by the `paragon-push` edge function.

1. developer.apple.com → Certificates, IDs & Profiles → **Keys** → new key with
   **Apple Push Notifications service (APNs)**. Download the `.p8` (once only).
2. Supabase → Edge Functions → Secrets:
   - `APNS_KEY_P8` — the whole `.p8` file's text
   - `APNS_KEY_ID` — the key's id (10 characters)
   - `APNS_TEAM_ID` — your team id (10 characters)

Until those exist `paragon-push` sends nothing. A phone signed in from Xcode
gets sandbox tokens, TestFlight/App Store ones production; the app tells the
server which.

## Calls (one-time, owner)

The phone rings through PushKit and CallKit: locked, in a pocket, or with the
app closed, it shows the iPhone's own incoming-call screen. Twilio sends that
push, so Twilio needs a VoIP certificate:

1. developer.apple.com → **Certificates** → new **VoIP Services Certificate**
   for `net.solbuild.paragon`. Download it, open it in Keychain Access, and
   export the certificate with its private key as a `.p12`.
2. Turn it into the two PEM blocks Twilio asks for:
   ```sh
   openssl pkcs12 -in voip.p12 -nokeys -out cert.pem -nodes -legacy
   openssl pkcs12 -in voip.p12 -nocerts -out key.pem -nodes -legacy
   openssl rsa -in key.pem -out key.pem
   ```
3. Twilio console → Voice → **Credentials** (Push Credentials) → new, type
   **VoIP Push Notification (APN)**, paste both. Tick **Use for sending to
   sandbox** only for the Xcode-built copy. Copy the `CR…` sid.
4. Save the sid for Paragon (an owner's session, or ask Claude to run it):
   `POST functions/v1/paragon-voice?op=ios_push_credential` with
   `{ "sid": "CR…" }` (add `"sandbox": true` for the sandbox credential).

Settings in the app shows whether this phone rings ("Calls ring this phone").
Desktop and iPhone ring together; whichever answers takes the call, and the
other stops ("answered elsewhere").

## Layout

```
Paragon/
  App/        ParagonApp, AppDelegate (APNs token, tapped notification), RootView + tabs
  Core/       Supa (auth only), API (PostgREST + edge functions), Models, Stamp (times), Session, Router
  Design/     Theme (the desktop's colours), BranchMark, AtlasRing, small components
  Features/   SignIn, Inbox (Waiting/All, Atlas guide), Conversation (timeline, composer),
              Personal, Alerts (the bell), Settings
  Calls/      CallManager (CallKit + PushKit + Twilio Voice), CallScreen, CallBar
  Push/       PushManager (permission, token → paragon_device_register)
```

Server pieces live in the paragon repo: `paragon.devices`,
`paragon_device_register` / `_unregister`, the notification and personal-text
triggers (migration `20261109120000_paragon_ios_devices_push.sql`), the
`paragon-push` function, and the `platform=ios` token in `paragon-voice`.
