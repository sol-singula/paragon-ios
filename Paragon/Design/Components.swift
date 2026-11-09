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

/// A two-way switch styled like the desktop's tab pair (Waiting / All).
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var badge: (T) -> AnyView? = { _ in nil }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button { selection = opt.0 } label: {
                    HStack(spacing: 6) {
                        Text(opt.1).font(.uiMedium)
                        if let b = badge(opt.0) { b }
                    }
                    .foregroundStyle(selection == opt.0 ? Theme.text : Theme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selection == opt.0 ? Theme.hover : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.input))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
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
