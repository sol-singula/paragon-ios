import SwiftUI

struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @FocusState private var field: Field?
    enum Field { case email, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 10) {
                ParagonMark(size: 44)
                Text("Paragon").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
                Text("by solbuild").font(.meta).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                TextField("", text: $email, prompt: Text("Email").foregroundStyle(Theme.muted))
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($field, equals: .email).submitLabel(.next)
                    .onSubmit { field = .password }
                    .inputStyle()
                SecureField("", text: $password, prompt: Text("Password").foregroundStyle(Theme.muted))
                    .textContentType(.password)
                    .focused($field, equals: .password).submitLabel(.go)
                    .onSubmit(go)
                    .inputStyle()
                if let e = session.error {
                    Text(e).font(.meta).foregroundStyle(Theme.rose).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: go) {
                    HStack { if session.working { ProgressView().tint(.black) }; Text("Sign in").font(.uiMedium) }
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan))
                        .foregroundStyle(Color.black)
                }
                .disabled(email.isEmpty || password.isEmpty || session.working)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
            }
            .frame(maxWidth: 380)
            Spacer()
            Text("Use your Solbuild login.").font(.meta).foregroundStyle(Theme.muted).padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .onAppear { field = .email }
    }

    private func go() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await session.signIn(email: email, password: password) }
    }
}

struct NotMemberView: View {
    @Environment(Session.self) private var session
    let email: String

    var body: some View {
        VStack(spacing: 14) {
            ParagonMark(size: 36)
            Text("You're not on Paragon yet").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
            Text("\(email.isEmpty ? "This login" : email) isn't a Paragon member. An owner adds you in Paragon → Settings → People.")
                .font(.ui).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            Button("Sign out") { Task { await session.signOut() } }
                .font(.uiMedium).tint(Theme.cyan).padding(.top, 8)
        }
        .padding(32)
    }
}

/// The solbuild orb, Paragon's mark (owner, 2026-11-09: "just the solbuild logo").
struct ParagonMark: View {
    var size: CGFloat = 32
    var body: some View {
        Circle()
            .fill(LinearGradient(stops: [.init(color: Color(hex: 0x06B6D4), location: 0),
                                         .init(color: Color(hex: 0x0FB89A), location: 0.55),
                                         .init(color: Color(hex: 0x10B981), location: 1)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

private struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.ui).foregroundStyle(Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.input))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.inputBorder))
    }
}

extension View {
    func inputStyle() -> some View { modifier(InputStyle()) }
}
