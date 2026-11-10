import Foundation
import Observation

/// Changing a contact's name (founder, 2026-11-09: "we need functionality to
/// change contact name"), the desktop's `lib/renames.ts`. Instant: the new
/// name is on every row and header the moment Save is tapped, and
/// `paragon_person_rename` (audited `person.rename`, before and after) runs
/// behind it. A refusal puts the old name back and says why; "Renamed to X
/// · Undo" renames back through the same function.
@Observable
@MainActor
final class Renames {
    static let shared = Renames()

    private var names: [String: String] = [:]

    /// The name to show: what was just typed here, else the server's.
    func shown(_ personId: String?, _ serverName: String) -> String {
        guard let id = personId else { return serverName }
        return names[id] ?? serverName
    }

    /// Whether a name was just given here (hides "Name them" at once).
    func justNamed(_ personId: String?) -> Bool {
        guard let id = personId else { return false }
        return names[id] != nil
    }

    /// `from` is the name shown now (Undo goes back to it). `offerUndo`
    /// false for the Undo itself and for someone who had no name.
    func rename(_ personId: String, from: String, to: String, offerUndo: Bool = true, onSaved: (() -> Void)? = nil) {
        let v = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { Toast.shared.show("Give them a name.", error: true); return }
        guard v.count <= 120 else { Toast.shared.show("A name is at most 120 characters.", error: true); return }
        guard v != from.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        let before = names[personId]
        names[personId] = v
        if offerUndo {
            Toast.shared.show("Renamed to \(v)", action: (label: "Undo", run: { [weak self] in
                self?.rename(personId, from: v, to: from, offerUndo: false, onSaved: onSaved)
            }))
        } else {
            Toast.shared.show("Renamed to \(v)")
        }
        Task { @MainActor in
            do {
                try await API.personRename(personId, name: v)
                onSaved?()
                await InboxModel.shared.load()
                // The next reads carry it; let go of ours once they have, so
                // a teammate's later rename shows.
                try? await Task.sleep(for: .seconds(8))
                if names[personId] == v { names[personId] = nil }
            } catch {
                if names[personId] == v { names[personId] = before }
                Toast.shared.show("Could not rename them: \(error.localizedDescription)", error: true)
            }
        }
    }
}
