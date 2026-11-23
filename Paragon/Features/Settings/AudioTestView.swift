import AVFoundation
import AVKit
import SwiftUI

/// Settings → Microphone & speaker (owner, 2026-11-23: "click something in our personal settings to adjust/test mic.
/// or even adjust the source"). The desktop's Settings → Microphone & speaker on the iPhone: pick the microphone
/// (the phone's own, a wired or Bluetooth headset), a live level, record five seconds and hear it back, and the
/// system's route picker for where sound plays. The choice is this phone's (`AudioPrefs`) and calls use it
/// (`CallManager`'s audio block). Not offered during a call: the call owns the audio then.
enum AudioPrefs {
    private static let key = "paragon.audio.input"

    /// The chosen microphone's port UID, or nil for the iPhone's default.
    static var inputUID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Points the session at the chosen microphone when it is plugged in; otherwise leaves the default.
    static func applyInput() {
        let s = AVAudioSession.sharedInstance()
        guard let uid = inputUID, let port = s.availableInputs?.first(where: { $0.uid == uid }) else { return }
        try? s.setPreferredInput(port)
    }
}

struct AudioTestView: View {
    @Environment(CallManager.self) private var calls
    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var chosen: String? = AudioPrefs.inputUID
    @State private var level: Float = 0
    @State private var phase: Phase = .idle
    @State private var left = 0
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var meter: Timer?
    @State private var denied = false

    enum Phase { case idle, listening, recording, playing }
    private let seconds = 5
    private var file: URL { FileManager.default.temporaryDirectory.appendingPathComponent("paragon-mic-test.m4a") }

    var body: some View {
        List {
                if calls.active != nil {
                    Section {
                        Text("You are on a call. Test your microphone when the call ends.")
                            .font(.meta).foregroundStyle(Theme.amber)
                    }
                    .listRowBackground(Theme.card)
                }
                if denied {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paragon can't use the microphone").font(.uiMedium).foregroundStyle(Theme.text)
                                Text("Tap to open Settings and turn Microphone on for Paragon.").font(.meta).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section(label: "Microphone") {
                    Button { pick(nil) } label: { inputRow("iPhone default", sub: "Whatever iOS picks", on: chosen == nil) }
                    ForEach(inputs, id: \.uid) { p in
                        Button { pick(p.uid) } label: { inputRow(p.portName, sub: kind(p.portType), on: chosen == p.uid) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(phase == .idle ? "Level" : "Talk: the bars move when it hears you").font(.meta).foregroundStyle(Theme.muted)
                            Spacer()
                            if phase == .recording { Text("Recording… \(left)").font(.metaMedium).foregroundStyle(Theme.rose) }
                            if phase == .playing { Text("Playing back").font(.metaMedium).foregroundStyle(Theme.cyan) }
                        }
                        LevelBars(level: level)
                    }
                    .padding(.vertical, 6)
                    HStack(spacing: 10) {
                        Button(phase == .listening ? "Stop" : "Test microphone") {
                            phase == .listening ? stop() : listen()
                        }
                        .buttonStyle(.bordered).tint(Theme.teal)
                        .disabled(calls.active != nil || phase == .recording || phase == .playing)
                        Button("Record \(seconds) s and play back") { record() }
                            .buttonStyle(.borderedProminent).tint(Theme.teal)
                            .disabled(calls.active != nil || phase == .recording || phase == .playing)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)

                Section(label: "Speaker") {
                    HStack(spacing: 12) {
                        RoutePicker().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where sound plays").font(.ui).foregroundStyle(Theme.text)
                            Text("iPhone, speaker, AirPods or a Bluetooth headset. During a call, use Speaker on the call screen.")
                                .font(.meta).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)
            }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Microphone & speaker")
        .navigationBarTitleDisplayMode(.inline)
        .task { prepare() }
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in refreshInputs() }
    }

    private func inputRow(_ title: String, sub: String, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Theme.teal : Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui).foregroundStyle(Theme.text)
                Text(sub).font(.meta).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private func kind(_ t: AVAudioSession.Port) -> String {
        switch t {
        case .builtInMic: return "On this iPhone"
        case .headsetMic: return "Wired headset"
        case .bluetoothHFP: return "Bluetooth headset"
        case .usbAudio: return "USB"
        case .carAudio: return "Car"
        default: return "Microphone"
        }
    }

    private func prepare() {
        guard calls.active == nil else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try? s.setActive(true)
        refreshInputs()
        denied = AVAudioApplication.shared.recordPermission == .denied
    }

    private func refreshInputs() {
        inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        if let c = chosen, !inputs.contains(where: { $0.uid == c }) { chosen = nil }
    }

    private func pick(_ uid: String?) {
        chosen = uid
        AudioPrefs.inputUID = uid
        let s = AVAudioSession.sharedInstance()
        if let uid, let p = s.availableInputs?.first(where: { $0.uid == uid }) { try? s.setPreferredInput(p) }
        else { try? s.setPreferredInput(nil) }
        if phase == .listening { stop(); listen() }
    }

    /// Asks for the microphone if needed, then runs `go`.
    private func withMic(_ go: @escaping () -> Void) {
        AVAudioApplication.requestRecordPermission { ok in
            DispatchQueue.main.async {
                denied = !ok
                if ok { go() }
            }
        }
    }

    private func startRecorder() -> Bool {
        prepare()
        AudioPrefs.applyInput()
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
        guard let r = try? AVAudioRecorder(url: file, settings: settings) else { return false }
        r.isMeteringEnabled = true
        guard r.record() else { return false }
        recorder = r
        meter?.invalidate()
        meter = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let r = recorder else { return }
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)          // -160 … 0
            level = max(0, min(1, (db + 55) / 50))
        }
        return true
    }

    private func listen() {
        withMic {
            if startRecorder() { phase = .listening }
        }
    }

    private func record() {
        withMic {
            stop()
            guard startRecorder() else { return }
            phase = .recording
            left = seconds
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                left -= 1
                if left <= 0 { t.invalidate(); playBack() }
            }
        }
    }

    private func playBack() {
        recorder?.stop(); recorder = nil
        meter?.invalidate(); meter = nil
        level = 0
        guard let p = try? AVAudioPlayer(contentsOf: file) else { phase = .idle; return }
        player = p
        p.play()
        phase = .playing
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.2) { if phase == .playing { phase = .idle } }
    }

    private func stop() {
        recorder?.stop(); recorder = nil
        player?.stop(); player = nil
        meter?.invalidate(); meter = nil
        level = 0
        phase = .idle
    }
}

private struct LevelBars: View {
    let level: Float
    private let bars = 20
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Float(i) < level * Float(bars) ? (i > Int(Double(bars) * 0.85) ? Theme.amber : Theme.teal) : Theme.hover)
                    .frame(height: 10 + CGFloat(i) * 0.9)
            }
        }
        .frame(height: 28, alignment: .bottom)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// The system's output picker (iPhone, speaker, AirPods, Bluetooth).
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.secondary)
        v.activeTintColor = UIColor(Theme.teal)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
