import SwiftUI
import UIKit
import Observation

/// The tab bar as the mockup draws it (`.tabs`), on every iOS version: flat
/// and full width, the panel colour at 94% with a hairline on top, 20pt
/// icons over small labels, muted, the chosen tab in teal with no pill, and
/// rose counts at the icon's top right. The system bar is hidden
/// (`hidesSystemTabBar()`), so iOS 26's floating glass pill never shows.
struct ParagonTabBar: View {
    struct Item: Identifiable {
        let tab: Router.Tab
        let title: String
        let symbol: String
        /// "4", "@", or nil for none.
        let badge: String?
        var id: Router.Tab { tab }
    }

    let items: [Item]
    @Binding var selection: Router.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let on = selection == item.tab
                Button { selection = item.tab } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 30, height: 24)
                            .overlay(alignment: .topTrailing) {
                                if let b = item.badge {
                                    Text(b)
                                        .font(.system(size: 10, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Capsule().fill(Theme.rose))
                                        .offset(x: 8, y: -4)
                                        .fixedSize()
                                }
                            }
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.teal : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.badge.map { $0 == "@" ? "Mentioned" : "\($0) new" } ?? "")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 4)
        .background {
            Theme.panel.opacity(0.94)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Whether the keyboard is up, so the bar can step aside the way the system
/// one does instead of riding on top of the keyboard.
@Observable
@MainActor
final class KeyboardWatcher {
    static let shared = KeyboardWatcher()
    private(set) var visible = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    private init() {
        let c = NotificationCenter.default
        tokens.append(c.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { n in
            let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            let screen = UIScreen.main.bounds
            // A hardware keyboard's shortcut bar is short; that is not "up".
            let up = end.height > 120 && end.minY < screen.maxY - 1
            MainActor.assumeIsolated { KeyboardWatcher.shared.visible = up }
        })
        tokens.append(c.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardWatcher.shared.visible = false }
        })
    }
}

extension View {
    /// Hides the system tab bar under this screen. Every tab's root and
    /// every screen pushed onto a tab says it, because the system decides
    /// per screen.
    func hidesSystemTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

/// Screens that draw their own bar (the tab roots, a conversation) hide the
/// system navigation bar, which also turns off the edge swipe back. This
/// keeps the swipe: it begins whenever there is a screen to go back to.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
