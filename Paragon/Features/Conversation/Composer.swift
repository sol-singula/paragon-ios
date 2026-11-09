import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A file on its way into a text: uploaded to paragon-shared as soon as it
/// is picked, sent as a link (Quo sends text only), shown as a picture.
struct PendingFile: Identifiable {
    let id = UUID()
    let name: String
    let preview: UIImage?
    var file: SharedFile?
    var failed = false
}

/// The box at the bottom. The line it sends from is the server's
/// `send_label` ("Text as Solara Home · (385) 333-7711"), shown above it.
/// Photos, files and GIFs (founder, 2026-11-09) and an emoji button, as
/// the desktop's composer.
struct Composer: View {
    @Binding var draft: String
    let label: String?
    let sending: Bool
    let blocked: String?
    /// "Text Rachel".
    var placeholder = "Text…"
    /// Sends the words and the uploaded files; true when it went.
    let send: ([SharedFile]) async -> Bool

    @FocusState private var focused: Bool
    @State private var files: [PendingFile] = []
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
                        }
                        TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(Theme.muted), axis: .vertical)
                            .lineLimit(1...6)
                            .font(.ui).foregroundStyle(Theme.text)
                            .focused($focused)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.input))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focused ? Theme.teal.opacity(0.6) : Theme.inputBorder))
                        Button { go() } label: {
                            ZStack {
                                Circle().fill(canSend ? Theme.teal : Theme.hover).frame(width: 34, height: 34)
                                if sending { ProgressView().tint(.white) }
                                else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(canSend ? Color.white : Theme.muted) }
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
                        .overlay {
                            if f.file == nil && !f.failed { ZStack { Color.black.opacity(0.35); ProgressView().tint(.white) }.clipShape(RoundedRectangle(cornerRadius: 10)) }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(f.failed ? Theme.rose : .clear, lineWidth: 2))
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

    /// "Text Rachel", or "Text them" for a number with no name.
    static func placeholder(for name: String?, named: Bool = true) -> String {
        guard named, let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n.first?.isLetter == true else { return "Text them" }
        return "Text " + (n.split(separator: " ").first.map(String.init) ?? n)
    }

    /// The server's "Text as Solara · Utah" read as "Sends as Solara · Utah".
    static func sendsAs(_ label: String) -> String {
        for p in ["Text as ", "Texts as ", "Sending as "] where label.hasPrefix(p) {
            return "Sends as " + label.dropFirst(p.count)
        }
        return label
    }

    private var uploading: Bool { files.contains { $0.file == nil && !$0.failed } }
    private var ready: [SharedFile] { files.compactMap(\.file) }
    private var canSend: Bool {
        !sending && !uploading && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ready.isEmpty)
    }

    private func go() {
        let out = ready
        Task {
            if await send(out) { files = []; error = nil }
        }
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
        await upload(data: data, name: "\(kind)-\(stamp)-\(Int.random(in: 100...999)).\(ext)", type: mime)
    }

    private func addFile(_ url: URL) {
        let open = url.startAccessingSecurityScopedResource()
        defer { if open { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "\(url.lastPathComponent) couldn't be read."; return }
        let mime = FileKind.mime(for: UTType(filenameExtension: url.pathExtension)) == "application/octet-stream"
            ? (FileKind.sniff(data) ?? "application/octet-stream") : FileKind.mime(for: UTType(filenameExtension: url.pathExtension))
        Task { await upload(data: data, name: url.lastPathComponent, type: mime) }
    }

    private func upload(data: Data, name: String, type: String) async {
        guard files.count < Self.maxFiles else { return }
        guard data.count <= Self.maxBytes else { error = "\(name) is over 15 MB."; return }
        let preview = type.hasPrefix("image") ? UIImage(data: data) : nil
        let p = PendingFile(name: name, preview: preview)
        files.append(p)
        do {
            let f = try await Storage.uploadShared(data: data, name: name, type: type)
            if let i = files.firstIndex(where: { $0.id == p.id }) { files[i].file = f }
            error = nil
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
            files.removeAll { $0.id == p.id }
        }
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
