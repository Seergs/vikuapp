import SwiftUI
import VikuDesignSystem
import VikunjaCore

/// "Add a connection" screen. Purely presentational — all validation, probing
/// and persistence live in `InstanceSetupViewModel`, so future UI-only changes
/// (copy, styling, layout, button count) only ever touch this file.
public struct InstanceSetupView: View {
    @Bindable private var viewModel: InstanceSetupViewModel
    @State private var isTokenVisible = false
    @State private var isPasswordVisible = false
    private let onConnectionSaved: (InstanceAccount) -> Void

    public init(viewModel: InstanceSetupViewModel, onConnectionSaved: @escaping (InstanceAccount) -> Void) {
        self.viewModel = viewModel
        self.onConnectionSaved = onConnectionSaved
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: VikuSpacing.lg) {
                header
                fields

                if viewModel.credentialMode != .oidc {
                    testConnectionButton
                }

                if let statusText {
                    statusBanner(text: statusText, isSuccess: viewModel.validationState == .success)
                }

                if viewModel.credentialMode != .oidc {
                    saveButton
                }
            }
            .padding(VikuSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .hideNavigationBar()
        .task { await viewModel.loadSavedAccounts() }
        .task(id: viewModel.urlText) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await viewModel.checkLocalAuthAvailability()
        }
        .onChange(of: viewModel.savedAccount) { _, savedAccount in
            if let savedAccount {
                onConnectionSaved(savedAccount)
            }
        }
    }

    private var header: some View {
        VStack(spacing: VikuSpacing.md) {
            RoundedRectangle(cornerRadius: VikuRadius.lg, style: .continuous)
                .fill(VikuColor.brandPrimary)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(spacing: VikuSpacing.xs) {
                Text("Connect your instance")
                    .font(VikuFont.title2)
                    .fontWeight(.heavy)

                Text("This app connects to your own Vikunja server. Enter your instance's details to get started.")
                    .font(VikuFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(VikuColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, VikuSpacing.lg)
    }

    private var fields: some View {
        VStack(spacing: VikuSpacing.md) {
            OnboardingField(label: "Connection name", text: $viewModel.displayName, placeholder: "e.g. Office server")
                .autocapitalized(.words)

            OnboardingField(label: "Instance URL", text: $viewModel.urlText, placeholder: "https://tasks.example.com")
                .autocapitalized(.never)
                .autocorrectionDisabled()
                .keyboardTypeURL()

            if viewModel.urlUsesInsecureScheme {
                insecureConnectionToggle
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            AuthMethodAccordion(
                expanded: $viewModel.credentialMode,
                isPasswordEnabled: viewModel.localAuthAvailable,
                isOIDCEnabled: !viewModel.oidcProviders.isEmpty,
                apiToken: { apiTokenField },
                password: { passwordFields },
                oidc: { oidcProvidersSection },
            )
        }
        .animation(.smooth(duration: 0.28), value: viewModel.urlUsesInsecureScheme)
    }

    private var insecureConnectionToggle: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            Toggle(isOn: $viewModel.allowInsecureConnection) {
                Text("Allow insecure connection")
                    .font(VikuFont.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(VikuColor.textSecondary)
            }
            .tint(VikuColor.brandPrimary)

            if viewModel.allowInsecureConnection {
                HStack(alignment: .firstTextBaseline, spacing: VikuSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Traffic to this instance won't be encrypted. Only use http on a trusted local network.")
                }
                .font(VikuFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(VikuColor.Semantic.dangerText)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: viewModel.allowInsecureConnection)
    }

    private var oidcProvidersSection: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm) {
            Text("You'll be redirected to your provider's sign-in page to finish.")
                .font(VikuFont.caption)
                .foregroundStyle(VikuColor.textSecondary)

            ForEach(viewModel.oidcProviders) { provider in
                oidcProviderButton(provider)
            }
        }
    }

    private func oidcProviderButton(_ provider: OIDCProvider) -> some View {
        Button {
            Task { await viewModel.signInWithOIDC(provider) }
        } label: {
            Text("Continue with \(provider.name)")
                .font(VikuFont.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VikuSpacing.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .opacity(viewModel.canSignInWithOIDC ? 1 : 0.5)
        .disabled(!viewModel.canSignInWithOIDC)
    }

    private var apiTokenField: some View {
        OnboardingField(
            label: "API token",
            text: $viewModel.apiToken,
            placeholder: "vkj_...",
            isSecure: !isTokenVisible,
            hint: "Generate one on your Vikunja instance: Settings → API Tokens.",
            trailingSystemImage: isTokenVisible ? "eye.slash" : "eye",
            trailingAction: { isTokenVisible.toggle() },
        )
        .autocapitalized(.never)
        .autocorrectionDisabled()
    }

    private var passwordFields: some View {
        VStack(spacing: VikuSpacing.md) {
            OnboardingField(label: "Username", text: $viewModel.username, placeholder: "your-username")
                .autocapitalized(.never)
                .autocorrectionDisabled()

            OnboardingField(
                label: "Password",
                text: $viewModel.password,
                placeholder: "••••••••",
                isSecure: !isPasswordVisible,
                trailingSystemImage: isPasswordVisible ? "eye.slash" : "eye",
                trailingAction: { isPasswordVisible.toggle() },
            )
            .autocapitalized(.never)
            .autocorrectionDisabled()

            if viewModel.awaitingTOTP {
                OnboardingField(
                    label: "Two-factor code",
                    text: $viewModel.totpPasscode,
                    placeholder: "123456",
                    hint: "Enter the current code from your authenticator app.",
                )
                .autocapitalized(.never)
                .autocorrectionDisabled()
            }
        }
    }

    private var testConnectionButton: some View {
        Button {
            Task { await viewModel.testConnection() }
        } label: {
            HStack(spacing: VikuSpacing.sm) {
                if viewModel.isSaving {
                    ProgressView()
                }
                Text(viewModel.isSaving ? "Testing connection…" : "Test Connection")
                    .font(VikuFont.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VikuSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        .opacity(viewModel.canTestConnection ? 1 : 0.5)
        .disabled(!viewModel.canTestConnection || viewModel.isSaving)
    }

    private func statusBanner(text: String, isSuccess: Bool) -> some View {
        let backgroundTint = isSuccess ? VikuColor.Semantic.success : VikuColor.Semantic.danger
        let textTint = isSuccess ? VikuColor.Semantic.successText : VikuColor.Semantic.dangerText
        return HStack(spacing: VikuSpacing.sm) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(text)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
        }
        .foregroundStyle(textTint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VikuSpacing.md)
        .padding(.vertical, VikuSpacing.sm)
        .background(backgroundTint.opacity(0.12), in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.saveConnection() }
        } label: {
            Text("Save & Continue")
                .font(VikuFont.body)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VikuSpacing.md)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(VikuColor.brandPrimary, in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous))
        .opacity(viewModel.canSave ? 1 : 0.4)
        .disabled(!viewModel.canSave || viewModel.isSaving)
    }

    private var statusText: String? {
        switch viewModel.validationState {
        case .idle, .validating:
            nil
        case .success:
            "Connection successful."
        case let .failure(message):
            message
        }
    }
}

/// A single labeled input row: label above a rounded field-background box,
/// with an optional trailing icon button (e.g. show/hide the API token) and
/// an optional hint line below.
private struct OnboardingField: View {
    let label: String
    @Binding var text: String
    var placeholder: String
    var isSecure: Bool = false
    var hint: String?
    var trailingSystemImage: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.xs) {
            Text(label)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(VikuColor.textSecondary)

            HStack(spacing: VikuSpacing.sm) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(VikuFont.body)

                if let trailingSystemImage, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 14))
                            .foregroundStyle(VikuColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VikuSpacing.md)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))

            if let hint {
                Text(hint)
                    .font(VikuFont.caption)
                    .foregroundStyle(VikuColor.textSecondary)
            }
        }
    }
}

/// `textInputAutocapitalization`/`keyboardType` are iOS/watchOS-only, but this
/// package also builds for macOS to run its tests — these no-op there.
private extension View {
    @ViewBuilder
    func autocapitalized(_ style: TextInputAutocapitalizationStyle) -> some View {
        #if os(iOS)
        textInputAutocapitalization(style)
        #else
        self
        #endif
    }

    @ViewBuilder
    func keyboardTypeURL() -> some View {
        #if os(iOS)
        keyboardType(.URL)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hideNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

#if os(iOS)
private typealias TextInputAutocapitalizationStyle = TextInputAutocapitalization
#else
private enum TextInputAutocapitalizationStyle {
    case never
    case words
}
#endif
