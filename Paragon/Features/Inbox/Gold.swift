import SwiftUI

/// Gold cards (founder, 2026-11-10: "add golden ones and it should be the
/// email forms ANYTIME we get a form request ... a conversation with a gold
/// background with MOST PRIORITY and its essentially just ready to call").
/// The desktop's `web/src/screens/inbox/Gold.tsx`, the same contract.
///
/// The server files one for every real website form (atlas_tasks kind
/// 'web_form'). It is never a promise: no hand, no violet, no WHO · WHEN ·
/// WHAT. A call that is not answered, or "Try again later", sets it for the
/// next try and the server brings it back; after the last try it is a normal
/// conversation. An older server sends no gold and nothing here shows.
enum Gold {
    /// They did not pick up: out of the inbox now, back for the next try.
    @MainActor
    static func later(_ item: RowItem, personId: String, name: String, changed: @escaping () -> Void) {
        guard !GoneIDs.shared.contains(item.id) else { return }
        GoneIDs.shared.hide(item.id)
        LaterMarks.shared.mark(thread: item.threadId, due: Date().addingTimeInterval(2 * 3600))
        Task {
            do {
                let r = try await API.webFormLater(item.id)
                if r.ended == true {
                    Toast.shared.show("\(first(name)): tried \(r.maxTries ?? 3) times. A normal conversation now.")
                } else if let d = Stamp.date(r.dueAt) {
                    Toast.shared.show("\(first(name)) comes back \(DueTime.label(d))")
                }
                changed()
            } catch {
                GoneIDs.shared.putBack(item.id)
                LaterMarks.shared.unmark(thread: item.threadId)
                Toast.shared.show(error.localizedDescription, error: true)
            }
        }
    }

    /// Gold no more: we talked, or it is not a lead.
    @MainActor
    static func done(_ item: RowItem, name: String, changed: @escaping () -> Void) {
        guard !GoneIDs.shared.contains(item.id) else { return }
        GoneIDs.shared.hide(item.id)
        Toast.shared.show("\(first(name)) is a normal conversation now")
        Task {
            do { try await API.webFormDone(item.id); changed() }
            catch { GoneIDs.shared.putBack(item.id); Toast.shared.show(error.localizedDescription, error: true) }
        }
    }

    private static func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
}

/// The top of a gold conversation: the form and a big Call.
struct GoldPanel: View {
    let item: RowItem
    let form: WebForm?
    let name: String
    let canCall: Bool
    let call: () -> Void
    let later: () -> Void
    let done: () -> Void

    private var f: WebForm.Form? { form?.form }
    /// "Just Glass · quote form".
    private var place: String {
        [form?.brand ?? f?.site, form?.formName.map { "\($0) form" }].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("NEW WEBSITE LEAD").font(.tag).tracking(0.6).foregroundStyle(Theme.goldText)
                if let w = form {
                    Text(w.label).font(.tag).foregroundStyle(Theme.goldText)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold.opacity(0.22)))
                }
                Spacer(minLength: 4)
                if let s = f?.submittedAt { Text("\(Stamp.span(s)) ago").font(.meta).foregroundStyle(Theme.muted) }
            }
            if !place.isEmpty { Text(place).font(.meta).foregroundStyle(Theme.secondary) }
            if let w = f?.wants, !w.isEmpty {
                Text(w).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
            }
            if let m = f?.message, !m.isEmpty, m != f?.wants {
                Text(m).font(.ui).foregroundStyle(Theme.secondary).lineLimit(3)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let p = f?.phone { detail("phone", p) }
                if let e = f?.email { detail("envelope", e) }
                if let a = f?.address { detail("mappin.and.ellipse", a) }
                ForEach(Array((f?.fields?.items ?? []).filter { $0.value != f?.wants }.prefix(6).enumerated()), id: \.offset) { _, x in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(x.label).font(.meta).foregroundStyle(Theme.muted)
                        Text(x.value).font(.meta).foregroundStyle(Theme.text).lineLimit(1)
                    }
                }
            }
            if f?.textsOk == false {
                Label("They did not agree to texts on the form: call or email.", systemImage: "exclamationmark.bubble")
                    .font(.meta).foregroundStyle(Theme.amber)
            }
            Button(action: call) {
                Label("Call \(name.split(separator: " ").first.map(String.init) ?? name)", systemImage: "phone.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.gold))
            }
            .buttonStyle(.plain)
            .disabled(!canCall).opacity(canCall ? 1 : 0.45)
            .accessibilityLabel("Call \(name)")
            HStack {
                Button("Try again later", action: later).font(.metaMedium).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Not gold any more", action: done).font(.meta).foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Theme.gold.opacity(0.22), Theme.gold.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.gold.opacity(0.45)))
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(width: 14)
            Text(text).font(.meta).foregroundStyle(Theme.secondary).lineLimit(1).textSelection(.enabled)
        }
    }
}
