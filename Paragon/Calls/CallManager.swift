import Foundation
import Observation
import AVFoundation
import CallKit
import PushKit
import TwilioVoice

/// Calls on the iPhone: the phone rings like a phone.
///
/// - **Ringing.** paragon-voice rings a member as `<Client><Identity>member
///   id</Identity>`, the same identity the desktop registers. This phone
///   registers that identity with Twilio against its PushKit (VoIP) token,
///   so Twilio's push wakes the app, even locked or closed, and CallKit shows
///   the system's incoming-call screen. Desktop and iPhone ring together;
///   whichever answers takes it. The VoIP token only reaches Twilio when the
///   server has the iPhone Push Credential (README, "Calls").
/// - **Placing.** `place(thread:)` starts a CallKit call and connects with
///   `thread_id`, exactly what the desktop sends; paragon-voice's `outbound`
///   picks the line.
/// - **Sounds** (founder, 2026-11-09). An incoming call rings "Low Classic"
///   (`Sounds/ringtone-low-classic.caf`, CallKit's `ringtoneSound`, which the
///   system loops until it is answered, declined or cancelled). An outgoing
///   call plays "Pulse" (`Sounds/ringback-pulse.caf`, looped by an
///   AVAudioPlayer) from `callDidStartRinging` until it connects or ends.
///   Nothing of ours plays once a call connects (the person who answered
///   could hear it). Levels (same day: rings were much louder than voices):
///   Pulse plays at `pulseVolume`, and Low Classic is mastered 6 dB quieter
///   (CallKit's ring follows the ringer volume, so the file is the lever).
///   The call's own voice is the system's: Twilio's DefaultAudioDevice puts
///   the session in playAndRecord / `.voiceChat`, and the volume buttons set it.
/// - **After a call** that connected, `ended` asks for a follow-up (the
///   founder's "Add promise" / "Follow up later"); the next call clears it.
///
/// Every CallKit/PushKit/Twilio callback arrives on the main queue (each is
/// set up that way below), so the nonisolated delegate methods step onto
/// the main actor with `MainActor.assumeIsolated`.
@Observable
@MainActor
final class CallManager: NSObject {
    static let shared = CallManager()

    enum Direction { case incoming, outgoing }
    enum Phase { case ringing, connecting, connected, reconnecting }

    struct Active: Equatable {
        let uuid: UUID
        let direction: Direction
        var name: String
        var brand: String?
        var thread: String
        var phase: Phase
        var connectedAt: Date?
        var muted = false
        var speaker = false
        /// The parent call's sid (the server's name for this call): the
        /// customer's leg on a call in, ours on a call out.
        var parent: String = ""
        /// The line on the call (the one the customer dialed on a call in).
        var line: String?
    }

    /// The branch's abbreviation first (founder, 2026-11-10: "WE MUST SHOW THE
    /// BRANCH ABBREVIATION SO WE KNOW HOW TO ANSWER"): "SH · Sonya Russell".
    static func callerName(_ name: String, brand: String?) -> String {
        guard let brand else { return name }
        return "\(Branch.of(brand).code) · \(name)"
    }

    /// Everyone added to the call (a conference), read every few seconds
    /// while connected so a teammate who was added sees the same list.
    private(set) var people: [CallPerson] = []
    private(set) var conference = false
    @ObservationIgnored private var peopleTask: Task<Void, Never>?

    private func watchPeople() {
        peopleTask?.cancel()
        peopleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let a = self.active, a.phase == .connected, !a.parent.isEmpty else { break }
                if let r = try? await API.callPeople(parent: a.parent) {
                    self.people = r.people ?? []
                    self.conference = r.conference ?? false
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Add a teammate or a number. Shows as "Joining…" at once.
    func add(member: String? = nil, number: String? = nil, name: String) {
        guard let a = active, !a.parent.isEmpty else { Toast.shared.show("The call is not connected yet", error: true); return }
        let tmp = CallPerson(key: "tmp-\(UUID().uuidString.prefix(6))", kind: member != nil ? "member" : "number", id: member ?? number ?? "", name: name, status: "joining", by: nil)
        people.append(tmp)
        conference = true
        Task {
            do {
                let r = try await API.callAdd(parent: a.parent, member: member, number: number)
                people = r.people ?? []
                conference = r.conference ?? true
            } catch {
                people.removeAll { $0.key == tmp.key }
                Toast.shared.show("Could not add \(name): \(error.localizedDescription)", error: true)
            }
        }
    }

    func remove(_ p: CallPerson) {
        guard let a = active, !p.key.hasPrefix("tmp-") else { return }
        Task {
            do { people = (try await API.callRemove(parent: a.parent, key: p.key)).people ?? people }
            catch { Toast.shared.show("Could not take them off: \(error.localizedDescription)", error: true) }
        }
    }

    /// Hand a call that came in to a teammate; our leg ends.
    func transfer(to t: CallTarget) {
        guard let a = active, a.direction == .incoming, !a.parent.isEmpty else { return }
        Task {
            do { try await API.voiceTransfer(parent: a.parent, to: t.id); Toast.shared.show("Handed to \(t.name.split(separator: " ").first.map(String.init) ?? t.name)") }
            catch { Toast.shared.show("Could not hand it over: \(error.localizedDescription)", error: true) }
        }
    }

    private(set) var active: Active?
    /// A connected call that just ended, for the follow-up banner.
    struct Ended: Equatable { let thread: String; let name: String; let at: Date }
    private(set) var ended: Ended?
    func clearEnded() { ended = nil }
    /// Pulse's player volume (about -9 dB).
    static let pulseVolume: Float = 0.35
    var showScreen = false
    private(set) var ringReady = false
    private(set) var ringStatus = "Checking…"
    private(set) var micGranted = AVAudioApplication.shared.recordPermission == .granted

    @ObservationIgnored private var provider: CXProvider?
    private let controller = CXCallController()
    @ObservationIgnored private var registry: PKPushRegistry?
    @ObservationIgnored private var voipToken: Data?
    @ObservationIgnored private var invites: [UUID: CallInvite] = [:]
    @ObservationIgnored private var calls: [UUID: Call] = [:]
    @ObservationIgnored private var outgoingThread: [UUID: String] = [:]
    @ObservationIgnored private var endedByUs: Set<UUID> = []
    @ObservationIgnored private var pushDone: (() -> Void)?
    @ObservationIgnored private var ringback: AVAudioPlayer?
    @ObservationIgnored private var endedClear: Task<Void, Never>?
    private let audioDevice = DefaultAudioDevice()

    // MARK: Start-up

    /// From application(_:didFinishLaunchingWithOptions:). PushKit must be
    /// listening before launch ends, or a call that woke the app is lost.
    func start() {
        guard provider == nil else { return }
        TwilioVoiceSDK.audioDevice = audioDevice

        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic, .phoneNumber]
        config.includesCallsInRecents = true
        config.ringtoneSound = "ringtone-low-classic.caf"
        let p = CXProvider(configuration: config)
        p.setDelegate(self, queue: nil)
        provider = p

        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r
    }

    /// Signed in (or the token changed): register this phone to ring.
    func signedIn() {
        micGranted = AVAudioApplication.shared.recordPermission == .granted
        Task { await registerForCalls() }
    }

    func askMic() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in CallManager.shared.micGranted = granted }
        }
    }

    private func registerForCalls() async {
        guard let device = voipToken else {
            ringStatus = "Waiting for iOS to give this phone a calling token…"
            return
        }
        do {
            let t = try await API.voiceToken()
            guard t.pushReady != false else {
                ringReady = false
                ringStatus = "Not set up yet. A founder saves the iPhone push credential (see the README)."
                return
            }
            let ok: Bool = await withCheckedContinuation { cont in
                TwilioVoiceSDK.register(accessToken: t.token, deviceToken: device) { error in
                    if let error { NSLog("Paragon: Twilio register failed: \(error.localizedDescription)") }
                    cont.resume(returning: error == nil)
                }
            }
            ringReady = ok
            ringStatus = ok ? "Your calls ring here and on the desktop." : "Twilio didn't accept this phone. Tap to try again."
            try? await API.registerDevice(token: device.hex, kind: "voip")
        } catch {
            ringReady = false
            ringStatus = error.localizedDescription
        }
    }

    /// Signing out: this phone stops ringing for that person.
    func unregister() async {
        guard let device = voipToken else { return }
        if let t = try? await API.voiceToken() {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                TwilioVoiceSDK.unregister(accessToken: t.token, deviceToken: device) { _ in cont.resume() }
            }
        }
        try? await API.unregisterDevice(token: device.hex)
        ringReady = false
        ringStatus = "Signed out."
    }

    // MARK: What the screens call

    func place(thread: String, name: String, brand: String?) {
        guard active == nil else { return }
        ended = nil
        if AVAudioApplication.shared.recordPermission == .undetermined { askMic() }
        let uuid = UUID()
        outgoingThread[uuid] = thread
        active = Active(uuid: uuid, direction: .outgoing, name: name, brand: brand, thread: thread, phase: .connecting)
        showScreen = true
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: name))
        controller.request(CXTransaction(action: action)) { error in
            Task { @MainActor in
                let me = CallManager.shared
                if let error {
                    NSLog("Paragon: start call refused: \(error.localizedDescription)")
                    me.cleanup(uuid)
                    return
                }
                let update = CXCallUpdate()
                update.remoteHandle = CXHandle(type: .generic, value: name)
                update.localizedCallerName = CallManager.callerName(name, brand: brand)
                update.hasVideo = false
                update.supportsDTMF = true
                update.supportsHolding = false
                update.supportsGrouping = false
                update.supportsUngrouping = false
                me.provider?.reportCall(with: uuid, updated: update)
            }
        }
    }

    /// Answer from inside the app (the system screen answers on its own).
    func answer() {
        guard let a = active, a.direction == .incoming else { return }
        controller.request(CXTransaction(action: CXAnswerCallAction(call: a.uuid))) { _ in }
    }

    func end() {
        guard let a = active else { return }
        endedByUs.insert(a.uuid)
        controller.request(CXTransaction(action: CXEndCallAction(call: a.uuid))) { error in
            if error != nil { Task { @MainActor in CallManager.shared.forceEnd(a.uuid) } }
        }
    }

    func toggleMute() {
        guard let a = active else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: a.uuid, muted: !a.muted))) { _ in }
    }

    func toggleSpeaker() {
        guard var a = active else { return }
        a.speaker.toggle()
        let on = a.speaker
        audioDevice.block = {
            DefaultAudioDevice.DefaultAVAudioSessionConfigurationBlock()
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
        }
        audioDevice.block()
        active = a
    }

    func digits(_ d: String) {
        guard let a = active else { return }
        controller.request(CXTransaction(action: CXPlayDTMFCallAction(call: a.uuid, digits: d, type: .singleTone))) { _ in }
    }

    /// Ringing: let Atlas take it (the desktop's "Send to Atlas").
    func sendToAtlas() {
        guard let a = active, a.direction == .incoming, let invite = invites[a.uuid],
              let parent = invite.customParameters?["parent"] else { return }
        Task {
            try? await API.voiceControl(action: "to_atlas", parent: parent)
            end()
        }
    }

    // MARK: Bookkeeping

    /// Pulse, while our call rings the other end. Plays in the call's audio
    /// session (CallKit activates it), so it follows speaker and route.
    private func startRingback() {
        if ringback == nil, let url = Bundle.main.url(forResource: "ringback-pulse", withExtension: "caf") {
            ringback = try? AVAudioPlayer(contentsOf: url)
            ringback?.numberOfLoops = -1
            ringback?.volume = Self.pulseVolume
            ringback?.prepareToPlay()
        }
        // A late 'ringing' after the answer must never start it.
        guard active?.phase != .connected, active?.connectedAt == nil else { return }
        guard let p = ringback, !p.isPlaying else { return }
        p.currentTime = 0
        p.play()
    }

    private func stopRingback() {
        ringback?.stop()
        ringback?.currentTime = 0
    }

    private func cleanup(_ uuid: UUID) {
        if active?.uuid == uuid { stopRingback() }
        if let a = active, a.uuid == uuid, a.connectedAt != nil, !a.thread.isEmpty {
            let e = Ended(thread: a.thread, name: a.name, at: Date())
            ended = e
            endedClear?.cancel()
            endedClear = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                if self?.ended == e { self?.ended = nil }
            }
        }
        invites[uuid] = nil
        calls[uuid] = nil
        outgoingThread[uuid] = nil
        endedByUs.remove(uuid)
        if active?.uuid == uuid {
            active = nil
            showScreen = false
            peopleTask?.cancel()
            people = []
            conference = false
        }
        if calls.isEmpty {
            audioDevice.block = { DefaultAudioDevice.DefaultAVAudioSessionConfigurationBlock() }
        }
    }

    private func forceEnd(_ uuid: UUID) {
        if let invite = invites[uuid] { invite.reject() }
        calls[uuid]?.disconnect()
        provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        cleanup(uuid)
    }

    private func set(_ uuid: UUID?, _ change: (inout Active) -> Void) {
        guard let uuid, var a = active, a.uuid == uuid else { return }
        change(&a)
        active = a
    }

    /// Put the person's name on the incoming-call screen once the card is in.
    private func nameIncoming(_ uuid: UUID, thread: String) async {
        let parent = active?.uuid == uuid ? active?.parent : nil
        guard !thread.isEmpty, let card = try? await API.callCard(thread, parent: parent) else { return }
        let update = CXCallUpdate()
        update.localizedCallerName = Self.callerName(card.name, brand: card.brand)
        provider?.reportCall(with: uuid, updated: update)
        set(uuid) { $0.name = card.name; $0.brand = card.brand; $0.line = card.line }
    }

    fileprivate func pushHandled() {
        pushDone?()
        pushDone = nil
    }
}

// MARK: - PushKit

extension CallManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        let token = credentials.token
        MainActor.assumeIsolated {
            self.voipToken = token
            Task { if (try? await Supa.client.auth.session) != nil { await self.registerForCalls() } }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        MainActor.assumeIsolated {
            self.voipToken = nil
            self.ringReady = false
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        MainActor.assumeIsolated {
            self.pushDone = completion
            if !TwilioVoiceSDK.handleNotification(dict, delegate: self, delegateQueue: nil) {
                // iOS ends an app that takes a VoIP push without reporting a
                // call, so a push that isn't a call is reported and ended.
                let uuid = UUID()
                let update = CXCallUpdate()
                update.remoteHandle = CXHandle(type: .generic, value: "Paragon")
                self.provider?.reportNewIncomingCall(with: uuid, update: update) { _ in
                    Task { @MainActor in
                        CallManager.shared.provider?.reportCall(with: uuid, endedAt: Date(), reason: .failed)
                        CallManager.shared.pushHandled()
                    }
                }
            }
        }
    }
}

// MARK: - Twilio: invites

extension CallManager: NotificationDelegate {
    nonisolated func callInviteReceived(callInvite: CallInvite) {
        MainActor.assumeIsolated {
            let uuid = callInvite.uuid
            let thread = callInvite.customParameters?["thread_id"] ?? ""
            self.invites[uuid] = callInvite
            let from = callInvite.from?.replacingOccurrences(of: "client:", with: "") ?? "Paragon"
            let update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: from.hasPrefix("+") ? .phoneNumber : .generic, value: from)
            update.localizedCallerName = from.hasPrefix("+") ? from : "Incoming call"
            update.hasVideo = false
            update.supportsDTMF = true
            update.supportsHolding = false
            update.supportsGrouping = false
            update.supportsUngrouping = false
            if self.active == nil {
                self.ended = nil
                var a = Active(uuid: uuid, direction: .incoming, name: from, brand: nil, thread: thread, phase: .ringing)
                a.parent = callInvite.customParameters?["parent"] ?? ""
                self.active = a
            }
            self.provider?.reportNewIncomingCall(with: uuid, update: update) { error in
                Task { @MainActor in
                    let me = CallManager.shared
                    if let error {
                        NSLog("Paragon: incoming call refused by iOS: \(error.localizedDescription)")
                        callInvite.reject()
                        me.cleanup(uuid)
                    } else {
                        await me.nameIncoming(uuid, thread: thread)
                    }
                    me.pushHandled()
                }
            }
        }
    }

    nonisolated func cancelledCallInviteReceived(cancelledCallInvite: CancelledCallInvite, error: Error) {
        let sid = cancelledCallInvite.callSid
        MainActor.assumeIsolated {
            // Answered on the desktop, or the caller hung up.
            guard let uuid = self.invites.first(where: { $0.value.callSid == sid })?.key else { return }
            self.provider?.reportCall(with: uuid, endedAt: Date(), reason: .answeredElsewhere)
            self.cleanup(uuid)
        }
    }
}

// MARK: - Twilio: a call in progress

extension CallManager: CallDelegate {
    nonisolated func callDidStartRinging(call: Call) {
        let uuid = call.uuid
        MainActor.assumeIsolated {
            self.set(uuid) { $0.phase = .ringing }
            if let uuid, self.active?.uuid == uuid, self.active?.direction == .outgoing { self.startRingback() }
        }
    }

    nonisolated func callDidConnect(call: Call) {
        let uuid = call.uuid
        let sid = call.sid
        MainActor.assumeIsolated {
            self.stopRingback()
            if let uuid, self.active?.direction == .outgoing { self.provider?.reportOutgoingCall(with: uuid, connectedAt: Date()) }
            self.set(uuid) { a in
                a.phase = .connected; a.connectedAt = Date()
                if a.direction == .outgoing, a.parent.isEmpty { a.parent = sid }
            }
            self.watchPeople()
        }
    }

    nonisolated func call(call: Call, isReconnectingWithError error: Error) {
        let uuid = call.uuid
        MainActor.assumeIsolated { self.set(uuid) { $0.phase = .reconnecting } }
    }

    nonisolated func callDidReconnect(call: Call) {
        let uuid = call.uuid
        MainActor.assumeIsolated { self.set(uuid) { $0.phase = .connected } }
    }

    /// An outgoing call that ends with Twilio's 31005 "General error" while it
    /// still rings, or within 10 s of the answer, is the far end hanging up
    /// (during the recording whisper, say): "Call ended", not a failure.
    /// No token, no mic, no network keep their own message.
    private func hungUpRightAway(_ uuid: UUID?, _ error: Error?) -> Bool {
        guard let error, let a = active, a.uuid == uuid else { return false }
        let code = (error as NSError).code
        guard code == 31005 || code == 31000 else { return false }
        if let at = a.connectedAt { return Date().timeIntervalSince(at) < 10 }
        return a.direction == .outgoing && a.phase == .ringing
    }

    nonisolated func callDidFailToConnect(call: Call, error: Error) {
        let uuid = call.uuid
        MainActor.assumeIsolated {
            NSLog("Paragon: call failed: \(error.localizedDescription)")
            self.stopRingback()
            guard let uuid else { return }
            let hungUp = self.hungUpRightAway(uuid, error)
            self.provider?.reportCall(with: uuid, endedAt: Date(), reason: hungUp ? .remoteEnded : .failed)
            Toast.shared.show(hungUp ? "Call ended · They hung up right away" : "Call problem: \(error.localizedDescription)", error: !hungUp)
            self.cleanup(uuid)
        }
    }

    nonisolated func callDidDisconnect(call: Call, error: Error?) {
        let uuid = call.uuid
        MainActor.assumeIsolated {
            self.stopRingback()
            guard let uuid else { return }
            let hungUp = self.hungUpRightAway(uuid, error)
            if !self.endedByUs.contains(uuid) {
                self.provider?.reportCall(with: uuid, endedAt: Date(), reason: error == nil || hungUp ? .remoteEnded : .failed)
            }
            if hungUp { Toast.shared.show("Call ended · They hung up right away") }
            self.cleanup(uuid)
        }
    }
}

// MARK: - CallKit

extension CallManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            self.stopRingback()
            self.audioDevice.isEnabled = false
            for (_, c) in self.calls { c.disconnect() }
            for (_, i) in self.invites { i.reject() }
            for u in Array(self.calls.keys) + Array(self.invites.keys) { self.cleanup(u) }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let uuid = action.callUUID
        MainActor.assumeIsolated {
            provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
            guard let thread = self.outgoingThread[uuid] else { action.fail(); self.cleanup(uuid); return }
            Task {
                do {
                    let t = try await API.voiceToken()
                    let options = ConnectOptions(accessToken: t.token) { b in
                        b.params = ["thread_id": thread]
                        b.uuid = uuid
                    }
                    self.calls[uuid] = TwilioVoiceSDK.connect(options: options, delegate: self)
                    action.fulfill()
                } catch {
                    NSLog("Paragon: no voice token: \(error.localizedDescription)")
                    action.fail()
                    self.cleanup(uuid)
                }
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let uuid = action.callUUID
        MainActor.assumeIsolated {
            guard let invite = self.invites[uuid] else { action.fail(); return }
            let options = AcceptOptions(callInvite: invite) { b in b.uuid = invite.uuid }
            self.calls[uuid] = invite.accept(options: options, delegate: self)
            self.invites[uuid] = nil
            self.set(uuid) { $0.phase = .connecting }
            self.showScreen = true
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let uuid = action.callUUID
        MainActor.assumeIsolated {
            self.endedByUs.insert(uuid)
            if let invite = self.invites[uuid] { invite.reject(); self.cleanup(uuid) }
            else if let call = self.calls[uuid] { call.disconnect() }
            else { self.cleanup(uuid) }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let uuid = action.callUUID, muted = action.isMuted
        MainActor.assumeIsolated {
            guard let call = self.calls[uuid] else { action.fail(); return }
            call.isMuted = muted
            self.set(uuid) { $0.muted = muted }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        let uuid = action.callUUID, digits = action.digits
        MainActor.assumeIsolated {
            guard let call = self.calls[uuid] else { action.fail(); return }
            call.sendDigits(digits)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fulfill()
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { self.audioDevice.isEnabled = true }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { self.audioDevice.isEnabled = false }
    }
}

extension Data {
    /// An APNs / PushKit token as the hex string servers expect.
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
