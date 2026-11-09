import SwiftUI

/// Costs (founders, read only on the phone): today's thinking against the
/// daily budget, the range's totals for thinking and Twilio, a bar a day,
/// and the breakdowns by model, client and line, from the same
/// `paragon_costs` the desktop's Settings → Costs reads. The budget is
/// changed on the desktop.
struct CostsView: View {
    @State private var days = 30
    @State private var c: Costs?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Theme.bg)
            }
            if let e = error {
                ErrorBanner(message: e) { Task { await load() } }.listRowBackground(Theme.bg)
            }
            if let c {
                let budget = c.budgetUsd?.value ?? 0, today = c.todayThinkingUsd?.value ?? 0
                let pct = budget > 0 ? min(1, today / budget) : 0
                let thinking = c.totals?.thinking?.value ?? 0
                let calls = c.totals?.twilioCalls?.value ?? 0, texts = c.totals?.twilioTexts?.value ?? 0, other = c.totals?.twilioOther?.value ?? 0
                let twilio = calls + texts + other

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .lastTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thinking today").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                Text(usd(today)).font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                            }
                            Spacer()
                            Text("of \(usd(budget, 0)) a day").font(.meta).foregroundStyle(Theme.muted)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.hover)
                                Capsule().fill(pct > 0.85 ? Color(hex: 0xE5484D) : Theme.violet).frame(width: g.size.width * pct)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int((pct * 100).rounded()))% of the daily budget. At the budget Atlas stops reading until tomorrow.")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)

                Section(label: "This range") {
                    row("Everything", usd(thinking + twilio), color: Theme.text)
                    row("Thinking", usd(thinking), color: Theme.violet)
                    row("Twilio", usd(twilio), color: Color(hex: 0x10B981))
                    row("  Calls", usd(calls), color: Theme.secondary)
                    row("  Texts", usd(texts), color: Theme.secondary)
                    row("  Numbers, recordings & more", usd(other), color: Theme.secondary)
                }
                .listRowBackground(Theme.card)

                if let byDay = c.byDay, !byDay.isEmpty {
                    Section(label: "By day") {
                        DayBars(days: byDay).frame(height: 120).padding(.vertical, 6)
                        HStack(spacing: 12) {
                            legend("Thinking", Theme.violet)
                            legend("Twilio", Color(hex: 0x10B981))
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                if let models = c.byModel, !models.isEmpty {
                    Section(label: "Thinking by model") {
                        ForEach(models, id: \.model) { m in row(modelLabel(m.model), usd(m.usd.value), sub: m.n.map { "\($0) reads" }) }
                    }
                    .listRowBackground(Theme.card)
                }

                if let clients = c.byClient, !clients.isEmpty {
                    Section(label: "Top clients") {
                        ForEach(Array(clients.prefix(15).enumerated()), id: \.offset) { _, x in row(x.name, usd(x.usd.value), sub: x.n.map { "\($0) reads" }) }
                        if let none = c.noClientUsd?.value, none > 0 { row("Not about a client", usd(none), color: Theme.muted) }
                    }
                    .listRowBackground(Theme.card)
                }

                if let lines = c.twilioByLine, !lines.isEmpty {
                    Section(label: "Twilio by line") {
                        ForEach(lines, id: \.line) { l in
                            row(l.line, usd(l.usd.value), sub: "\(l.calls ?? 0) calls · \(l.texts ?? 0) texts")
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Text(twilioNote(c)).font(.meta).foregroundStyle(c.twilioError != nil ? Theme.amber : Theme.muted)
                    Text("The daily budget and the full graph are on the desktop app, Settings → Costs.").font(.meta).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.bg)
            } else if error == nil {
                HStack { Spacer(); ProgressView().tint(Theme.muted); Spacer() }.listRowBackground(Theme.bg)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Costs")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: days) { c = nil; await load() }
    }

    private func load() async {
        do { c = try await API.costs(days: days); error = nil }
        catch { self.error = "Could not load the costs: \(error.localizedDescription)" }
    }

    private func twilioNote(_ c: Costs) -> String {
        if let e = c.twilioError, !e.isEmpty { return "Twilio couldn't be read: \(e)" }
        if let at = c.twilioSyncedAt { return "Twilio read \(Stamp.when(at)). It is the whole Twilio account." }
        return "Twilio is read every hour."
    }

    private func row(_ label: String, _ value: String, sub: String? = nil, color: Color = Theme.text) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.ui).foregroundStyle(color).lineLimit(1)
                if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            Text(value).font(.ui).monospacedDigit().foregroundStyle(Theme.text)
        }
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    /// The server's model id, in words ("x-name-4-5" → "X Name 4.5").
    private func modelLabel(_ m: String) -> String {
        if m == "unknown" { return "Unknown model" }
        var parts: [String] = []
        for p in m.split(separator: "-") {
            if let last = parts.last, last.allSatisfy(\.isNumber), p.allSatisfy(\.isNumber) { parts[parts.count - 1] = "\(last).\(p)" }
            else { parts.append(p.prefix(1).uppercased() + p.dropFirst()) }
        }
        return parts.joined(separator: " ")
    }
}

func usd(_ v: Double, _ digits: Int = 2) -> String {
    if v >= 1000 { return "$" + NumberFormatter.localizedString(from: NSNumber(value: v.rounded()), number: .decimal) }
    return "$" + String(format: "%.\(digits)f", v)
}

/// Thinking and Twilio stacked, one bar a day.
private struct DayBars: View {
    let days: [Costs.ByDay]

    var body: some View {
        let max = Swift.max(0.01, days.map { $0.thinking.value + $0.twilio.value }.max() ?? 0)
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: days.count > 40 ? 1 : 2) {
                ForEach(days, id: \.day) { d in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(Color(hex: 0x10B981)).frame(height: g.size.height * d.twilio.value / max)
                        Rectangle().fill(Theme.violet).frame(height: g.size.height * d.thinking.value / max)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(d.day): \(usd(d.thinking.value + d.twilio.value))")
                }
            }
        }
    }
}
