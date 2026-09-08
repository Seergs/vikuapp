import SwiftUI
import VikuDesignSystem
import VikuNavigation
import VikunjaCore

/// The add/edit connection screen: name, instance URL, API token, a "Test
/// Connection" probe, and — only in edit mode — a "Delete Connection" action.
/// Pushed onto the Settings tab's own stack (from `ConnectionsListView`)
/// rather than presented as a sheet, since it's a step within that stack
/// rather than an independent flow.
struct ConnectionFormView: View {
    @State private var viewModel: ConnectionFormViewModel
    let router: Router<SettingsRoute>
    @State private var isTokenVisible = false
    @State private var isPasswordVisible = false
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool

    /// Takes a factory rather than an already-built view model — see
    /// `ConnectionsListView.init`'s doc comment for why this has to be
    /// `@State`-owned instead of a plain `@Bindable` property.
    init(makeViewModel: @escaping () -> ConnectionFormViewModel, router: Router<SettingsRoute>) {
        _viewModel = State(initialValue: makeViewModel())
        self.router = router
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VikuSpacing.lg) {
                VStack(alignment: .leading, spacing: VikuSpacing.md) {
                    FormField(label: "Connection Name", placeholder: "e.g. Office Server", text: $viewModel.displayName)
                        .focused($isNameFocused)

                    FormField(label: "Instance URL", placeholder: "https://tasks.yourcompany.com", text: $viewModel.urlText)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()

                    if viewModel.urlUsesInsecureScheme {
                        insecureConnectionToggle
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    AuthMethodAccordion(
                        expanded: $viewModel.credentialMode,
                        isPasswordEnabled: viewModel.localAuthAvailable,
                        isOIDCEnabled: !viewModel.oidcProviders.isEmpty,
                        currentMethod: viewModel.currentMethod,
                        apiToken: { tokenField },
                        password: { passwordFields },
                        oidc: { oidcProvidersSection },
                    )
                }
                .animation(.smooth(duration: 0.28), value: viewModel.urlUsesInsecureScheme)

                if viewModel.credentialMode != .oidc {
                    testConnectionButton
                }

                if case let .failure(message) = viewModel.validationState {
                    StatusBanner(style: .danger, message: message)
                } else if viewModel.validationState == .success {
                    StatusBanner(
                        style: .success,
                        message: viewModel.savedAccount != nil ? "Saved" : "Connection successful",
                    )
                }

                if viewModel.credentialMode != .oidc {
                    saveButton
                }

                if viewModel.isEditing {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Text("Delete Connection")
                            .font(VikuFont.body)
                            .fontWeight(.bold)
                            .foregroundStyle(VikuColor.Semantic.danger)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VikuSpacing.sm)
                }
            }
            .padding(VikuSpacing.md)
        }
        .navigationTitle(viewModel.isEditing ? "Edit Connection" : "New Connection")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.load()
            isNameFocused = viewModel.displayName.isEmpty
        }
        .task(id: viewModel.urlText) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await viewModel.checkLocalAuthAvailability()
        }
        .onChange(of: viewModel.savedAccount) { _, savedAccount in
            if savedAccount != nil {
                router.pop()
            }
        }
        .confirmationDialog(
            "Remove this connection?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible,
        ) {
            Button("Remove Connection", role: .destructive) {
                Task {
                    if await viewModel.deleteConnection() {
                        router.pop()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var insecureConnectionToggle: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Toggle(isOn: $viewModel.allowInsecureConnection) {
                FieldLabel("Allow Insecure Connection")
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
                .font(VikuFont.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                .background(
                    VikuColor.Surface.field,
                    in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSignInWithOIDC)
        .opacity(viewModel.canSignInWithOIDC ? 1 : 0.5)
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.md) {
            FormField(label: "Username", placeholder: "your-username", text: $viewModel.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            passwordField

            if viewModel.awaitingTOTP {
                FormField(label: "Two-Factor Code", placeholder: "123456", text: $viewModel.totpPasscode)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel("Password")

            HStack(spacing: VikuSpacing.sm) {
                Group {
                    if isPasswordVisible {
                        TextField("••••••••", text: $viewModel.password)
                    } else {
                        SecureField("••••••••", text: $viewModel.password)
                    }
                }
                .font(VikuFont.body)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(VikuColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel("API Token")

            HStack(spacing: VikuSpacing.sm) {
                Group {
                    if isTokenVisible {
                        TextField("vkj_...", text: $viewModel.apiToken)
                    } else {
                        SecureField("vkj_...", text: $viewModel.apiToken)
                    }
                }
                .font(VikuFont.body)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                Button {
                    isTokenVisible.toggle()
                } label: {
                    Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                        .foregroundStyle(VikuColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTokenVisible ? "Hide token" : "Show token")
            }
            .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))

            Text("Generate it on your Vikunja instance: Settings → API Tokens.")
                .font(VikuFont.caption)
                .foregroundStyle(VikuColor.textTertiary)
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
                    .font(VikuFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
            .background(VikuColor.Surface.field, in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canTestConnection)
        .opacity(viewModel.canTestConnection ? 1 : 0.5)
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            Text(viewModel.isEditing ? "Save Connection" : "Save and Connect")
                .font(VikuFont.body)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xs)
                .background(
                    VikuColor.brandPrimary,
                    in: RoundedRectangle(cornerRadius: VikuRadius.md, style: .continuous),
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .opacity(viewModel.canSave ? 1 : 0.4)
    }
}

private struct FieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(VikuFont.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(VikuColor.textSecondary)
    }
}

/// A labeled single-line text field in a rounded field surface — the shared
/// shape behind "Connection Name" and "Instance URL".
private struct FormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            FieldLabel(label)
            TextField(placeholder, text: $text)
                .font(VikuFont.body)
                .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
                .padding(.vertical, VikuSpacing.sm + VikuSpacing.xxs)
                .background(
                    VikuColor.Surface.field,
                    in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous),
                )
        }
    }
}

/// Same tinted-card language as `Projects`' `CreateProjectSheetView` save
/// error banner — duplicated rather than shared since the design system has
/// no reusable banner component yet, and this one also covers a success
/// state theirs doesn't need.
private struct StatusBanner: View {
    enum Style { case success, danger }

    let style: Style
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: VikuSpacing.sm - VikuSpacing.xxs) {
            Image(systemName: style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(foreground)
            Text(message)
                .font(VikuFont.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(foreground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VikuSpacing.md - VikuSpacing.xxs)
        .padding(.vertical, VikuSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background.opacity(0.12), in: RoundedRectangle(cornerRadius: VikuRadius.sm, style: .continuous))
    }

    private var foreground: Color {
        style == .success ? VikuColor.Semantic.successText : VikuColor.Semantic.dangerText
    }

    private var background: Color {
        style == .success ? VikuColor.Semantic.success : VikuColor.Semantic.danger
    }
}
