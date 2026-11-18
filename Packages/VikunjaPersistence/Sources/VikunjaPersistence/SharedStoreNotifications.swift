import CoreFoundation
import CryptoKit
import Foundation

/// Darwin notifications carry no account data. They only invalidate local GRDB
/// observations; the database remains authoritative, including after missed
/// notifications while a process is suspended.
final class SharedStoreNotifications: Sendable {
    private static let registry = Registry()
    private let id: UUID
    private let name: String
    private let onChange: @Sendable () -> Void

    init(directory: URL, onChange: @escaping @Sendable () -> Void) {
        self.name = "viku.store." + SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.id = UUID()
        self.onChange = onChange
    }

    /// Snapshot-only widget processes post commits without starting observation
    /// work that could outlive a timeline or intent execution opportunity.
    func observe() {
        Self.registry.add(id: id, name: name, action: onChange)
    }

    deinit { Self.registry.remove(id: id, name: name) }

    func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true,
        )
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [String: [UUID: @Sendable () -> Void]] = [:]

        func add(id: UUID, name: String, action: @escaping @Sendable () -> Void) {
            lock.withLock {
                if actions[name] == nil {
                    CFNotificationCenterAddObserver(
                        CFNotificationCenterGetDarwinNotifyCenter(), nil,
                        { _, _, name, _, _ in
                            guard let name else { return }
                            SharedStoreNotifications.registry.receive(name.rawValue as String)
                        }, name as CFString, nil, .deliverImmediately,
                    )
                }
                actions[name, default: [:]][id] = action
            }
        }

        func remove(id: UUID, name: String) {
            lock.withLock {
                actions[name]?[id] = nil
                if actions[name]?.isEmpty == true {
                    actions[name] = nil
                    CFNotificationCenterRemoveObserver(
                        CFNotificationCenterGetDarwinNotifyCenter(), nil, CFNotificationName(name as CFString), nil,
                    )
                }
            }
        }

        func receive(_ name: String) {
            let callbacks = lock.withLock { Array(actions[name, default: [:]].values) }
            for callback in callbacks {
                callback()
            }
        }
    }
}
