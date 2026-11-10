import SwiftUI

/// The round initials the desktop shows for a person with no photo.
struct Initials: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        Text(letters.isEmpty ? "?" : letters)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.hover))
    }
}

/// "3 late": the rose count on the Waiting tab.
struct CountPill: View {
    let text: String
    var color: Color = Theme.rose

    var body: some View {
        Text(text)
            .font(.tag)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// The full-width switch under the greeting (the mockup's `.seg`): equal
/// segments on the panel colour, the chosen one raised and semibold.
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var badge: (T) -> AnyView? = { _ in nil }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let on = selection == opt.0
                Button { selection = opt.0 } label: {
                    HStack(spacing: 5) {
                        Text(opt.1).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
                        if let b = badge(opt.0) { b }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Theme.hover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.panel))
    }
}

/// A section header everywhere in the app (the mockup's `.sec`): small,
/// uppercase, semibold, muted, letter-spaced.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
            Spacer(minLength: 8)
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.63)
        .foregroundStyle(Theme.muted)
        .textCase(nil)
    }
}

/// A main tab's bar (the mockup's `.nav`): a quiet icon either side, the
/// title centred, no glass and no fill, so the hour's light shows through.
struct TopBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 64)
            HStack(spacing: 14) {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
        .font(.system(size: 18))
        .tint(Theme.secondary)
        .foregroundStyle(Theme.secondary)
        .frame(height: 44)
        .padding(.horizontal, 16)
    }
}

extension TopBar where Leading == EmptyView {
    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = EmptyView()
        self.trailing = trailing()
    }
}

extension TopBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }
}

/// The search field under a main tab's title (the mockup's `.search`): the
/// system's grey fill, a magnifier, and Cancel while it is in use.
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    /// Return on the keyboard (`false`), or Cmd+Return on a hardware keyboard
    /// (`true`): a typed number is texted or called (founder, 2026-11-10).
    var onSubmit: ((Bool) -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.muted)
                TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { onSubmit?(false) }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command), let onSubmit else { return .ignored }
                        onSubmit(true)
                        return .handled
                    }
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.24)))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if focused || !text.isEmpty {
                Button("Cancel") { text = ""; focused = false }
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.teal)
                    .buttonStyle(.plain)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: focused || !text.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// A small pill button beside a row or in a header (the mockup's `.act`
/// and `.callb`): grey for Text and ⓘ, green-tinted for Call.
struct PillButton: View {
    enum Tone { case plain, call }
    let label: String
    var symbol: String?
    var tone: Tone = .plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                if !label.isEmpty { Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1) }
            }
            .foregroundStyle(tone == .call ? Theme.green : Theme.text)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tone == .call ? Theme.green.opacity(0.16) : Theme.hover))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

/// A count on a tab, a channel or a segment: rose for what needs you
/// (an @, a wait), grey for plain unread.
struct CountBadge: View {
    let text: String
    var quiet = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(quiet ? Theme.secondary : .white)
            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
            .background(Capsule().fill(quiet ? Theme.hover : Theme.rose))
    }
}

/// A quiet message in the middle of an empty screen.
struct EmptyNote: View {
    let title: String
    var detail: String?
    var symbol = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Theme.muted)
            Text(title).font(.uiMedium).foregroundStyle(Theme.secondary)
            if let detail { Text(detail).font(.meta).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// A one-line error banner with a retry.
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(message).font(.meta).foregroundStyle(Theme.secondary).lineLimit(2)
            Spacer(minLength: 0)
            if let retry { Button("Retry", action: retry).font(.metaMedium).tint(Theme.cyan) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.amber.opacity(0.3)))
    }
}

/// A list preview on one line: line breaks become spaces, so a long one
/// ends in "…" where the row ends (founder, 2026-11-09: "a little too
/// abruptly cut off").
enum Preview {
    static func line(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

extension Section where Parent == SectionLabel, Content: View, Footer == EmptyView {
    /// A section under the app's small uppercase header.
    init(label: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionLabel(label) })
    }
}

extension Section where Parent == SectionLabel, Content: View, Footer: View {
    init(label: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { SectionLabel(label) }, footer: footer)
    }
}
