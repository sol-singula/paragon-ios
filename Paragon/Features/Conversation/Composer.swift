import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The box at the bottom. The line it sends from is the server's
/// `send_label` ("Text as Solara Home · (385) 333-7711"), shown above it.
/// Photos, files and GIFs (founder, 2026-11-09) and an emoji button, as
/// the desktop's composer. Send never waits (founder, 2026-11-09): the
/// words and files go to the Outbox, which shows them in the thread at once
/// and uploads (to paragon-shared, sent as links) and sends behind it; the
/// box clears and stays open for the next one.
struct Composer: View {
    @Binding var draft: String
    let label: String?
    let blocked: String?
    /// "Text Rachel".
    var placeholder = "Text…"
    /// Opens Add promise for this conversation (founder, 2026-11-10: a
    /// promise or a follow up without a call first).
    var promise: (() -> Void)? = nil
    /// Focus the box when it appears (a conversation just started from the
    /// search's line picker, founder 2026-11-10).
    var autoFocus = false
    /// Hands over the words and the picked files; it returns at once.
    let send: (String, [OutFile]) -> Void

    @FocusState private var focused: Bool
    @State private var files: [OutFile] = []
    @State private var picking = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var importTypes: [UTType] = [.item]
    @State private var emoji = false
    @State private var error: String?

    private static let maxFiles = 10
    private static let maxBytes = 15 * 1024 * 1024

    var body: some View {
        VStack(spacing: 0) {
            if blocked == nil, let label {
                // "Sends as Solara · Utah", centred over the composer.
                Text(Self.sendsAs(label)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 5)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let blocked {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                        Text(blocked).font(.meta)
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                } else {
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.rose).lineLimit(2) }
                    if !files.isEmpty { tray }
                    HStack(alignment: .bottom, spacing: 6) {
                        HStack(spacing: 2) {
                            attachMenu
                            Button { importTypes = [.gif]; importing = true } label: {
                                Text("GIF").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted)
                                    .frame(width: 30, height: 36)
                            }
                            .disabled(files.count >= Self.maxFiles)
                            .accessibilityLabel("Add a GIF")
                            Button { emoji.toggle() } label: {
                                Image(systemName: "face.smiling").font(.system(size: 18)).foregroundStyle(emoji ? Theme.teal : Theme.muted)
                                    .frame(width: 30, height: 36)
                            }
                            .accessibilityLabel("Emoji")
                            .popover(isPresented: $emoji) {
                                EmojiGrid(emoji: EmojiGrid.texting) { draft += $0 }
                                    .padding(10)
                                    .presentationCompactAdaptation(.popover)
                            }
                            if let promise {
                                Button(action: promise) {
                                    Image(systemName: "hand.raised").font(.system(size: 16)).foregroundStyle(Theme.muted)
                                        .frame(width: 30, height: 36)
                                }
                                .accessibilityLabel("Add a promise or follow up")
                            }
                        }
                        TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(Theme.muted), axis: .vertical)
                            // One line until you type, then it grows to 8 and scrolls (founder, 2026-11-10).
                            .lineLimit(1...8)
                            .font(.ui).foregroundStyle(Theme.text)
                            .focused($focused)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.input))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focused ? Theme.teal.opacity(0.6) : Theme.inputBorder))
                        Button { go() } label: {
                            ZStack {
                                Circle().fill(canSend ? Theme.teal : Theme.hover).frame(width: 34, height: 34)
                                Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(canSend ? Color.white : Theme.muted)
                            }
                            .padding(.bottom, 1)
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send")
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 8)
            .background(Theme.panel.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .onChange(of: autoFocus, initial: true) { _, on in
            guard on else { return }
            Task { try? await Task.sleep(for: .milliseconds(450)); focused = true }
        }
        .photosPicker(isPresented: $picking, selection: $picks, maxSelectionCount: max(1, Self.maxFiles - files.count), matching: .any(of: [.images, .videos]))
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            for item in items { Task { await addPhoto(item) } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { for u in urls.prefix(Self.maxFiles - files.count) { addFile(u) } }
        }
    }

    private var attachMenu: some View {
        Menu {
            Button { picking = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
            Button { importTypes = [.item]; importing = true } label: { Label("Files", systemImage: "doc") }
            Button { importTypes = [.gif]; importing = true } label: { Label("GIF", systemImage: "sparkles.rectangle.stack") }
        } label: {
            Image(systemName: "paperclip").font(.system(size: 17)).foregroundStyle(Theme.muted)
                .frame(width: 30, height: 36)
        }
        .disabled(files.count >= Self.maxFiles)
        .accessibilityLabel("Add a photo, file or GIF")
    }

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files) { f in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let p = f.preview { Image(uiImage: p).resizable().scaledToFill() }
                            else {
                                VStack(spacing: 4) {
                                    Image(systemName: "doc.fill").foregroundStyle(Theme.secondary)
                                    Text(f.name).font(.system(size: 9)).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.center)
                                }.padding(4)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(Theme.hover)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { files.removeAll { $0.id == f.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Circle().fill(.black.opacity(0.65)))
                        }
                        .padding(3)
                        .accessibilityLabel("Remove")
                    }
                }
            }
        }
    }

    /// The empty box reads "Message".
    static func placeholder(for name: String?, named: Bool = true) -> String {
        // Plain, like the desktop's (founder, 2026-11-09: no suggested wording).
        "Message"
    }

    /// The server's "Text as Solara · Utah" read as "Sends as Solara · Utah".
    static func sendsAs(_ label: String) -> String {
        for p in ["Text as ", "Texts as ", "Sending as "] where label.hasPrefix(p) {
            return "Sends as " + label.dropFirst(p.count)
        }
        return label
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty
    }

    /// Out of the box and into the thread, and the box is ready again. The
    /// keyboard stays up.
    private func go() {
        guard canSend else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = files
        draft = ""; files = []; error = nil; emoji = false
        send(body, out)
    }

    // MARK: Picking

    private func addPhoto(_ item: PhotosPickerItem) async {
        guard var data = try? await item.loadTransferable(type: Data.self) else { error = "That photo couldn't be read."; return }
        let t = item.supportedContentTypes.first
        var mime = FileKind.sniff(data) ?? FileKind.mime(for: t)
        var ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? t?.preferredFilenameExtension ?? "bin"
        // A customer's phone may not open a HEIC: it goes as a JPEG.
        if mime == "image/heic" || mime == "image/heif", let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) {
            data = jpg; mime = "image/jpeg"; ext = "jpg"
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let kind = mime.hasPrefix("video") ? "video" : "photo"
        add(data: data, name: "\(kind)-\(stamp)-\(Int.random(in: 100...999)).\(ext)", type: mime)
    }

    private func addFile(_ url: URL) {
        let open = url.startAccessingSecurityScopedResource()
        defer { if open { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "\(url.lastPathComponent) couldn't be read."; return }
        let mime = FileKind.mime(for: UTType(filenameExtension: url.pathExtension)) == "application/octet-stream"
            ? (FileKind.sniff(data) ?? "application/octet-stream") : FileKind.mime(for: UTType(filenameExtension: url.pathExtension))
        add(data: data, name: url.lastPathComponent, type: mime)
    }

    /// Held until Send; the Outbox uploads it with the text.
    private func add(data: Data, name: String, type: String) {
        guard files.count < Self.maxFiles else { return }
        guard data.count <= Self.maxBytes else { error = "\(name) is over 15 MB."; return }
        let preview = type.hasPrefix("image") ? UIImage(data: data) : nil
        files.append(OutFile(name: name, type: type, data: data, preview: preview))
        error = nil
    }
}

/// A grid of emoji; tapping one hands it back.
struct EmojiGrid: View {
    let emoji: [String]
    let pick: (String) -> Void

    static let texting = ["👍", "🙏", "😊", "😂", "❤️", "🎉", "👏", "🔥", "✅", "👋", "😀", "😉",
                          "🙂", "😅", "🤝", "💪", "🏠", "🪟", "☀️", "📅", "⏰", "📞", "👀", "💯"]
    static let quick = ["👍", "❤️", "😂", "🎉", "🙏", "🔥", "👀", "✅"]
    static let all = ["👍", "👎", "❤️", "😂", "🤣", "😊", "😍", "🥳", "🎉", "🙏", "🔥", "👀", "✅", "❌", "💯", "🙌",
                      "👏", "💪", "🤝", "👋", "😮", "😢", "😡", "🤔", "😅", "😬", "🙄", "😴", "🤯", "😎", "🤩", "😇",
                      "💰", "🏠", "🪟", "☀️", "⚡", "📞", "📅", "⏰", "🚀", "🎯", "⭐", "🏆", "🍕", "☕", "🍻", "❓"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 2), count: 6), spacing: 2) {
            ForEach(emoji, id: \.self) { e in
                Button { pick(e) } label: { Text(e).font(.system(size: 24)).frame(width: 38, height: 38) }
                    .buttonStyle(.plain)
            }
        }
    }
}
