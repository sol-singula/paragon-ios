import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Write to a channel. "@" offers the channel's people, Atlas (when it is
/// in the channel) and @everyone; photos and GIFs upload while you type.
/// The draft is kept per channel. Send never waits: the post shows in the
/// channel at once and the TeamOutbox uploads and posts it behind.
struct TeamComposer: View {
    let channel: TeamChannel
    let meId: String
    @Binding var replyTo: TeamMessage?
    /// Called the moment a post is handed over (to scroll to it).
    let onSent: () -> Void
    private struct Option: Identifiable { let id: String; let label: String; let insert: String; let sub: String? }

    @State private var model = TeamModel.shared
    @State private var text = ""
    @State private var pending: [TeamOutFile] = []
    @State private var picking = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var gifs = false
    @State private var emoji = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var draftKey: String { "paragon.team.draft.\(channel.id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = replyTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left").font(.system(size: 11))
                    (Text("Replying to ") + Text(model.first(r.author)).bold() + Text(": \(r.body.isEmpty ? (r.photos.isEmpty ? "" : "a photo") : r.body)"))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button { replyTo = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .accessibilityLabel("Cancel reply")
                }
                .font(.meta).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.hover.opacity(0.7)))
            }
            if !options.isEmpty { mentionList }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Theme.rose).lineLimit(2) }
            if !pending.isEmpty { tray }
            HStack(alignment: .bottom, spacing: 4) {
                Button { picking = true } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.secondary).frame(width: 32, height: 36)
                }
                .accessibilityLabel("Add photos or GIFs")
                Button { gifs = true } label: {
                    Text("GIF").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel("GIFs")
                Button { emoji.toggle() } label: {
                    Image(systemName: "face.smiling").font(.system(size: 18)).foregroundStyle(emoji ? Theme.cyan : Theme.secondary).frame(width: 30, height: 36)
                }
                .accessibilityLabel("Emoji")
                .popover(isPresented: $emoji) {
                    EmojiGrid(emoji: EmojiGrid.all) { text += $0 }.padding(10).presentationCompactAdaptation(.popover)
                }
                TextField("", text: $text, prompt: Text("Message \(channel.name)").foregroundStyle(Theme.muted), axis: .vertical)
                    .lineLimit(1...8)
                    .font(.ui).foregroundStyle(Theme.text)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.input))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? Theme.cyan.opacity(0.6) : Theme.inputBorder))
                Button { send() } label: {
                    ZStack {
                        Circle().fill(canSend ? Theme.teal : Theme.hover).frame(width: 34, height: 34)
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(canSend ? Color.white : Theme.muted)
                    }
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .photosPicker(isPresented: $picking, selection: $picks, maxSelectionCount: 10, matching: .images)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            picks = []
            for item in items { Task { await addPhoto(item) } }
        }
        .sheet(isPresented: $gifs) {
            GifSheet { a in addGif(a) } pickNew: { picking = true }
                .presentationDetents([.medium, .large])
        }
        .onAppear { text = UserDefaults.standard.string(forKey: draftKey) ?? "" }
        .onChange(of: text) { _, v in
            if v.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) } else { UserDefaults.standard.set(v, forKey: draftKey) }
        }
        .onChange(of: replyTo?.id) { _, id in if id != nil { focused = true } }
    }

    // MARK: Mentions

    /// "@ma" at the end of what's typed.
    private var query: String? {
        guard let re = try? NSRegularExpression(pattern: "(^|\\s)@([\\p{L}\\p{N}_]{0,20})$") else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 2))
    }

    private var options: [Option] {
        guard let q = query?.lowercased() else { return [] }
        var list: [Option] = (channel.members ?? []).filter { $0 != meId }.compactMap { (id: String) -> Option? in
            let name = model.name(id)
            return name == "Someone" ? nil : Option(id: id, label: name, insert: model.first(id), sub: nil)
        }
        if channel.atlasIn == true { list.append(Option(id: "atlas", label: "Atlas", insert: "Atlas", sub: "Not answering in Team yet")) }
        list.append(Option(id: "*", label: "everyone", insert: "everyone", sub: "Everyone in \(channel.name)"))
        return Array(list.filter { o in
            q.isEmpty || o.label.lowercased().hasPrefix(q) || o.label.lowercased().split(separator: " ").contains { $0.hasPrefix(q) }
        }.prefix(6))
    }

    private var mentionList: some View {
        VStack(spacing: 0) {
            ForEach(options) { o in
                Button { pick(o) } label: {
                    HStack(spacing: 8) {
                        if o.id == "*" {
                            Text("@").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary)
                                .frame(width: 26, height: 26).background(Circle().fill(Theme.hover))
                        } else {
                            MemberFace(id: o.id, name: o.label, url: model.photo(o.id), size: 26, ring: Theme.card)
                        }
                        Text(o.label).font(.ui).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 4)
                        if let s = o.sub { Text(s).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .card()
    }

    private func pick(_ o: Option) {
        guard let q = query else { return }
        text = String(text.dropLast(q.count + 1)) + "@\(o.insert) "
    }

    // MARK: Photos and GIFs

    private var tray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pending) { p in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let img = p.preview { Image(uiImage: img).resizable().scaledToFill() }
                            else if let a = p.existing { TeamPhoto(a: a, maxHeight: 64) }
                            else { Color.clear }
                        }
                        .frame(width: 64, height: 64)
                        .background(Theme.hover)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { pending.removeAll { $0.id == p.id } } label: {
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

    private func addPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { error = "That photo couldn't be read."; return }
        let mime = FileKind.sniff(data) ?? FileKind.mime(for: item.supportedContentTypes.first)
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "img"
        // The same checks the upload makes, now, so the post never fails on them.
        guard Storage.teamTypes.contains(mime) else { error = "That is not a photo or GIF."; return }
        guard data.count <= Storage.teamMax else { error = "That photo is over 10 MB."; return }
        pending.append(TeamOutFile(name: "photo.\(ext)", type: mime, data: data, preview: ImageInfo.image(data), existing: nil))
        error = nil
    }

    /// A GIF the team sent before: copied into this channel when the post goes.
    private func addGif(_ a: TeamAttachment) {
        pending.append(TeamOutFile(name: a.name ?? "gif", type: a.type ?? "image/gif", data: nil, preview: nil, existing: a))
    }

    // MARK: Sending

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty }

    /// Into the channel at once; the box is ready for the next one and the
    /// keyboard stays up.
    private func send() {
        guard canSend else { return }
        let body = text
        let ids = (channel.members ?? []).filter { $0 != meId && body.contains("@\(model.first($0))") }
        TeamOutbox.shared.post(channel: channel.id, body: body, files: pending, replyTo: replyTo, mentions: ids)
        text = ""; pending = []; replyTo = nil; error = nil; emoji = false
        onSent()
    }
}

/// GIFs without a search service: the ones the team sent lately, and any
/// GIF picked from Photos with the photo button.
private struct GifSheet: View {
    let onPick: (TeamAttachment) -> Void
    let pickNew: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var gifs: [TeamAttachment]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("GIFs the team sent lately. To send a new one, pick it from Photos.")
                        .font(.meta).foregroundStyle(Theme.muted)
                    if let gifs {
                        if gifs.isEmpty {
                            EmptyNote(title: "No GIFs yet", symbol: "sparkles")
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(gifs, id: \.path) { g in
                                    TeamPhoto(a: g, maxHeight: 120) { _ in onPick(g); dismiss() }
                                }
                            }
                        }
                    } else {
                        HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }.padding(30)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("From Photos") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pickNew() } }
                }
            }
        }
        .task { gifs = (try? await API.teamRecentGifs()) ?? [] }
    }
}
