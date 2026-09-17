import Onboarding
import SwiftUI
import VikunjaCore

/// Dev-only wrapper presenting `InstanceSetupView` over the running app so a
/// developer can see the first-launch screen without signing out — see
/// `RootView`'s `isPreviewingOnboarding`, toggled from Settings' Developer
/// section. Saving a connection here behaves exactly like real onboarding
/// (switches the active account); "Close" just dismisses without doing
/// anything.
struct OnboardingPreviewView: View {
    let container: AppContainer
    let onConnectionSaved: (InstanceAccount) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            InstanceSetupView(
                viewModel: container.makeInstanceSetupViewModel(),
                onConnectionSaved: onConnectionSaved,
            )
            .overlay(alignment: .topLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary, .tertiary)
                }
                .padding()
            }
        }
    }
}
