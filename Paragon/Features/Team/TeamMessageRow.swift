import SwiftUI
import UIKit

/// One message, Slack style: face and name on the first of a run, then just
/// the words. Every message carries its author's face (owner, 2026-11-09):
/// their Solbuild photo, Atlas's orb for Atlas, never a placeholder. Hold a
/// message to react, reply, copy, and (yours) edit or delete.
struct TeamMessageRow: View {
    let m: TeamMessage
    let meId: String
    let isFounder: Bool
    let compact: Bool
    let onUpdate: (TeamMessage) -> Void
    let onReply: (TeamMessage) -> Void
    let onEdit: (TeamMessage) -> Void
    let onOpenPhoto: (URL) -> Void
    let onError: (String) -> Void

    @State private var model = TeamModel.shared
    @State private var confirmDelete = false
    @State private var picking = false

    private var mine: Bool { m.author == meId }
    private var mentionsMe: Bool { !mine && ((m.mentions ?? []).contains(meId) || m.mentionAll == true) }

    var body: some View {
        if m.isDeleted {
            HStack(spacing: 10) {
                face.opacity(0.5)
                Text("This message was deleted.").font(.meta).italic().foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, compact ? 2 : 6)
        } else {
            content
                .padding(.horizontal, 16).padding(.top, compact ? 2 : 8).padding(.bottom, 2)
                .background(mentionsMe ? Theme.amber.opacity(0.07) : Color.clear)
                .contentShape(Rectangle())
                .contextMenu { menu }
                .confirmationDialog("Delete this message?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { remove() }
                } message: { Text("It is gone for everyone in the channel.") }
                .sheet(isPresented: $picking) {
                    ScrollView { EmojiGrid(emoji: EmojiGrid.all) { e in picking = false; react(e) }.padding(16) }
                        .background(Theme.bg)
                        .presentationDetents([.medium])
                }
        }
    }

    @ViewBuilder private var face: some View {
        if compact {
            Color.clear.frame(width: 36, height: 1)
        } else {
            MemberFace(id: m.author, name: model.name(m.author), url: model.photo(m.author), size: 36)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            face
            VStack(alignment: .leading, spacing: 3) {
                if !compact {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.name(m.author)).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(m.author == "atlas" ? Color(hex: 0xA78BFA) : Theme.text)
                        Text(time(m.createdAt)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
                if let r = m.replyTo {
                    HStack(spacing: 5) {
                        Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10))
                        Text(model.first(r.author)).fontWeight(.medium).foregroundStyle(Theme.secondary)
                        Text(r.deleted == true ? "deleted message" : (r.body?.isEmpty == false ? r.body! : ((r.photos ?? 0) > 0 ? "a photo" : "")))
                            .lineLimit(1)
                    }
                    .font(.meta).foregroundStyle(Theme.muted)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 2) }
                }
                if !m.body.isEmpty {
                    (Text(TeamRichText.render(m.body, meId: meId))
                     + Text(m.editedAt != nil ? "  (edited)" : "").font(.system(size: 11)).foregroundColor(Theme.muted))
                        .font(.ui).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(Theme.cyan)
                }
                if !m.photos.isEmpty { photos }
                if let rs = m.reactions, !rs.isEmpty { reactions(rs) }
            }
            Spacer(minLength: 0)
        }
    }

    private var photos: some View {
        let list = m.photos
        let cols = list.count == 1 ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(list, id: \.path) { a in
                TeamPhoto(a: a, maxHeight: list.count == 1 ? 300 : 160, onOpen: onOpenPhoto)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .padding(.top, 2)
    }

    private func reactions(_ rs: [TeamMessage.Reaction]) -> some View {
        FlowRow(spacing: 5) {
            ForEach(rs, id: \.emoji) { r in
                let me = r.by.contains(meId)
                Button { react(r.emoji) } label: {
                    HStack(spacing: 4) {
                        Text(r.emoji).font(.system(size: 14))
                        Text("\(r.by.count)").font(.system(size: 12)).monospacedDigit()
                    }
                    .foregroundStyle(me ? Theme.text : Theme.secondary)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(me ? Theme.cyan.opacity(0.12) : Theme.card))
                    .overlay(Capsule().strokeBorder(me ? Theme.cyan.opacity(0.5) : Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.by.map { $0 == meId ? "You" : model.first($0) }.joined(separator: ", ")) reacted \(r.emoji)")
            }
            Button { picking = true } label: {
                Image(systemName: "face.smiling").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(Capsule().fill(Theme.card)).overlay(Capsule().strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a reaction")
        }
        .padding(.top, 3)
    }

    @ViewBuilder private var menu: some View {
        ControlGroup {
            ForEach(EmojiGrid.quick.prefix(4), id: \.self) { e in
                Button { react(e) } label: { Text(e) }
            }
        }
        Button { picking = true } label: { Label("More reactions", systemImage: "face.smiling") }
        Button { onReply(m) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        if !m.body.isEmpty {
            Button { UIPasteboard.general.string = m.body } label: { Label("Copy text", systemImage: "doc.on.doc") }
        }
        if mine {
            Button { onEdit(m) } label: { Label("Edit", systemImage: "pencil") }
        }
        if mine || isFounder {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func react(_ emoji: String) {
        let on = !((m.reactions ?? []).first { $0.emoji == emoji }?.by.contains(meId) ?? false)
        Task {
            do { onUpdate(try await API.teamReact(message: m.id, emoji: emoji, on: on)) }
            catch { onError("Could not react: \(error.localizedDescription)") }
        }
    }

    private func remove() {
        Task {
            do {
                try await API.teamDelete(message: m.id)
                onUpdate(TeamMessage(id: m.id, channelId: m.channelId, author: m.author, body: "", mentions: m.mentions,
                                     mentionAll: m.mentionAll, mentionAtlas: m.mentionAtlas, attachments: [], createdAt: m.createdAt,
                                     editedAt: m.editedAt, deleted: true, replyTo: nil, reactions: []))
            } catch { onError("Not deleted: \(error.localizedDescription)") }
        }
    }

    private func time(_ s: String) -> String {
        guard let d = Stamp.date(s) else { return "" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"; f.amSymbol = "am"; f.pmSymbol = "pm"
        return f.string(from: d)
    }
}

/// A Team photo or GIF from the private bucket, through a signed link.
struct TeamPhoto: View {
    let a: TeamAttachment
    var maxHeight: CGFloat = 300
    var onOpen: (URL) -> Void = { _ in }
    @State private var url: URL?

    var body: some View {
        Button { if let url { onOpen(url) } } label: {
            Color.clear
                .aspectRatio(a.ratio, contentMode: .fit)
                .frame(maxHeight: maxHeight)
                .overlay { RemoteImage(url: url, fill: true) }
                .background(Theme.hover)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.name ?? "Photo")
        .task(id: a.path) { url = await Storage.teamURL(a.path) }
    }
}

/// Message words with @mentions lit (mine in amber, Atlas in violet, the
/// rest in cyan) and links that open, as the desktop's RichText.
enum TeamRichText {
    private typealias FG = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    private typealias BG = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    private typealias FontKey = AttributeScopes.SwiftUIAttributes.FontAttribute

    @MainActor
    static func render(_ body: String, meId: String) -> AttributedString {
        let model = TeamModel.shared
        var labels: [(label: String, id: String)] = []
        for p in model.people.values {
            labels.append((p.name, p.id))
            if let f = p.name.split(separator: " ").first { labels.append((String(f), p.id)) }
        }
        labels += [("Atlas", "atlas"), ("everyone", "*"), ("channel", "*"), ("here", "*")]
        labels.sort { $0.label.count > $1.label.count }

        var out = AttributedString(body)
        let ns = body as NSString

        // Links.
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for r in det.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                guard let url = r.url, let range = Range(r.range, in: body), let ar = Range(range, in: out) else { continue }
                out[ar].link = url
                out[ar][FG.self] = Theme.cyan
            }
        }

        // @mentions: the longest name that follows an @ and ends a word.
        var i = body.startIndex
        while let at = body[i...].firstIndex(of: "@") {
            let after = body.index(after: at)
            var matched: (String.Index, String)?
            for l in labels {
                guard let end = body.index(after, offsetBy: l.label.count, limitedBy: body.endIndex) else { continue }
                if body[after..<end].lowercased() == l.label.lowercased() {
                    if end < body.endIndex, let c = body[end].unicodeScalars.first,
                       CharacterSet.alphanumerics.contains(c) || c == "_" { continue }
                    matched = (end, l.id); break
                }
            }
            if let hit = matched, let ar = Range(at..<hit.0, in: out) {
                let id = hit.1
                let isMe = id == meId || id == "*"
                out[ar][FG.self] = isMe ? Theme.text : id == "atlas" ? Color(hex: 0xA78BFA) : Theme.cyan
                out[ar][BG.self] = isMe ? Theme.amber.opacity(0.22) : id == "atlas" ? Theme.violet.opacity(0.15) : Theme.cyan.opacity(0.13)
                out[ar][FontKey.self] = .system(size: 15, weight: .medium)
                i = hit.0
            } else {
                i = after
            }
            if i >= body.endIndex { break }
        }
        return out
    }
}

/// Lays its children out in rows, wrapping (reactions under a message).
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
