import SwiftUI
import VikunjaCore

/// The credential-mode chooser on both connection forms (`Onboarding` and
/// `Settings`): three stacked, collapsible cards — "API Token", "Username &
/// Password", "SSO / OpenID" — of which exactly one is expanded at a time.
///
/// Every card is always visible so the user can see up front which sign-in
/// methods exist. API token is offered by every Vikunja instance, so its card
/// is always enabled and expanded by default; the other two render dimmed and
/// non-interactive until a `/api/v1/info` probe confirms the server actually
/// enables them (`isPasswordEnabled` / `isOIDCEnabled`).
///
/// `expanded` is the `InstanceAccount.AuthMethod` whose card is open. Tapping a
/// disabled card does nothing; the binding only ever moves to an enabled one.
///
/// `currentMethod`, when set, tags that one card with a "Current" pill — used
/// by the edit form to show which method the saved connection already uses.
public struct AuthMethodAccordion<APIToken: View, Password: View, OIDC: View>: View {
    /// The fixed label/icon copy for one card.
    private struct Spec {
        let method: InstanceAccount.AuthMethod
        let icon: String
        let title: String
        let subtitle: String
    }

    private static var specs: [Spec] {
        [
            Spec(
                method: .apiToken,
                icon: "key.fill",
                title: "API Token",
                subtitle: "Paste a token generated on your instance.",
            ),
            Spec(
                method: .password,
                icon: "person.fill",
                title: "Username & Password",
                subtitle: "Sign in with your Vikunja credentials.",
            ),
            Spec(
                method: .oidc,
                icon: "globe",
                title: "SSO / OpenID",
                subtitle: "Sign in through your identity provider.",
            ),
        ]
    }

    @Binding private var expanded: InstanceAccount.AuthMethod
    private let isPasswordEnabled: Bool
    private let isOIDCEnabled: Bool
    private let currentMethod: InstanceAccount.AuthMethod?
    private let apiTokenContent: APIToken
    private let passwordContent: Password
    private let oidcContent: OIDC

    public init(
        expanded: Binding<InstanceAccount.AuthMethod>,
        isPasswordEnabled: Bool,
        isOIDCEnabled: Bool,
        currentMethod: InstanceAccount.AuthMethod? = nil,
        @ViewBuilder apiToken: () -> APIToken,
        @ViewBuilder password: () -> Password,
        @ViewBuilder oidc: () -> OIDC,
    ) {
        self._expanded = expanded
        self.isPasswordEnabled = isPasswordEnabled
        self.isOIDCEnabled = isOIDCEnabled
        self.currentMethod = currentMethod
        self.apiTokenContent = apiToken()
        self.passwordContent = password()
        self.oidcContent = oidc()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("Access method")
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)

            VStack(spacing: VikuSpacing.sm) {
                ForEach(Self.specs, id: \.method) { card($0) }
            }
            .animation(.smooth(duration: 0.3), value: isPasswordEnabled)
            .animation(.smooth(duration: 0.3), value: isOIDCEnabled)
        }
    }

    private func isEnabled(_ method: InstanceAccount.AuthMethod) -> Bool {
        switch method {
        case .apiToken: true
        case .password: isPasswordEnabled
        case .oidc: isOIDCEnabled
        }
    }

    @ViewBuilder
    private func content(for method: InstanceAccount.AuthMethod) -> some View {
        switch method {
        case .apiToken: apiTokenContent
        case .password: passwordContent
        case .oidc: oidcContent
        }
    }

    private func card(_ spec: Spec) -> some View {
        let enabled = isEnabled(spec.method)
        let isOpen = expanded == spec.method && enabled

        return VStack(spacing: 0) {
            Button {
                guard enabled, expanded != spec.method else { return }
                withAnimation(.snappy(duration: 0.22)) { expanded = spec.method }
            } label: {
                header(spec, isEnabled: enabled, isOpen: isOpen)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)

            if isOpen {
                content(for: spec.method)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                    .padding(.bottom, VikuSpacing.md)
                    .transition(.opacity)
            }
        }
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        .opacity(enabled ? 1 : 0.55)
    }

    private func header(_ spec: Spec, isEnabled: Bool, isOpen: Bool) -> some View {
        HStack(spacing: VikuSpacing.sm + VikuSpacing.xxs) {
            RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous)
                .fill(isOpen ? VikuColor.brandPrimary : VikuColor.Surface.card)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: spec.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isOpen ? .white : VikuColor.textSecondary)
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: VikuSpacing.xs + VikuSpacing.xxs) {
                    Text(spec.title)
                        .font(VikuFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isEnabled ? Color.primary : VikuColor.textTertiary)

                    if currentMethod == spec.method {
                        Text("Current")
                            .font(VikuFont.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(VikuColor.brandPrimary)
                            .padding(.horizontal, VikuSpacing.xs + VikuSpacing.xxs)
                            .padding(.vertical, 1)
                            .background(VikuColor.brandPrimary.opacity(0.14), in: Capsule())
                    }
                }

                Text(isEnabled ? spec.subtitle : "Not available on this server, or not confirmed yet.")
                    .font(VikuFont.caption)
                    .foregroundStyle(VikuColor.textTertiary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VikuColor.textTertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(VikuSpacing.sm + VikuSpacing.xxs)
        .contentShape(Rectangle())
    }
}
