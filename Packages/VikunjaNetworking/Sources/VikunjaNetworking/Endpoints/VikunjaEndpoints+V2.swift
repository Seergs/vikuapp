import Foundation

/// v2 endpoint builders, added one resource at a time per
/// `docs/API_V2_MIGRATION.md`'s migration order — kept in a sibling file
/// rather than growing `VikunjaEndpoints.swift` so a resource's v1 and v2
/// paths stay easy to tell apart at a glance.
extension VikunjaEndpoints {
    static func projectsV2() -> Endpoint {
        Endpoint(path: "/api/v2/projects")
    }

    static func projectV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(id)")
    }

    static func createProjectV2(dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/projects", method: .post, body: dto)
    }

    static func updateProjectV2(id: Int, dto: ProjectDTO) throws -> Endpoint {
        try .encoding(path: "/api/v2/projects/\(id)", method: .put, body: dto)
    }

    static func deleteProjectV2(id: Int) -> Endpoint {
        Endpoint(path: "/api/v2/projects/\(id)", method: .delete)
    }
}
