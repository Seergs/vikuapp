#if DEBUG
import Foundation
import VikunjaCore

/// One writer owns each file. Commit the new state before acknowledging a mutation.
nonisolated struct UITestStateFile<Value: Codable & Sendable>: Sendable {
    let url: URL

    func load(seed: Value?) throws -> Value {
        if let seed {
            try save(seed)
            return seed
        }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func update<Result>(_ state: inout Value, _ change: (inout Value) throws -> Result) throws -> Result {
        var next = state
        let result = try change(&next)
        try save(next)
        state = next
        return result
    }

    private func save(_ value: Value) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

nonisolated struct UITestServerCollection<Record: Codable & Sendable>: Codable, Sendable {
    var records: [Record]
    var nextID = 100
}

extension EntityID {
    nonisolated func requiredUITestRemoteID() throws -> Int {
        guard let remoteValue else { throw UITestFixtureError.unsupported("Local ID sent to fake server") }
        return remoteValue
    }
}
#endif
