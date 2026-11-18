#if DEBUG
import VikunjaCore

/// Catalog entries shared by the fake server's task and label repositories.
nonisolated enum UITestFixtures {
    static let navigationLabel = Label(id: 1, title: "UI Test Navigation", hexColor: "4986A2")
}
#endif
