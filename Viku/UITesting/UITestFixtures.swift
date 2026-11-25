#if DEBUG
import VikunjaCore

/// Catalog entries shared by the fake server's repositories.
nonisolated enum UITestFixtures {
    static let navigationLabel = Label(id: 1, title: "UI Test Navigation", hexColor: "4986A2")
    static let savedFilterProject = Project(id: -2, title: "UI Test Saved Filter")
}
#endif
