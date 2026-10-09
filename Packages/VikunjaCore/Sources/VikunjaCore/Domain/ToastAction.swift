/// What tapping a toast, instead of just dismissing it, should do.
/// `VikunjaCore` has no notion of navigation, so this only carries domain
/// data; the app's navigation layer (see `AppRoute` in `VikuNavigation`)
/// translates a case into whatever it needs to push.
public enum ToastAction: Equatable, Sendable {
    case taskDetail(VikunjaTask, Project)
}
