import Foundation
import Testing
@testable import VikunjaCore
@testable import VikunjaNetworking

struct SavedFilterDTOTests {
    @Test
    func `decodes a realistic saved filter payload including its nested query`() throws {
        let url = try #require(Bundle.module.url(forResource: "saved-filter", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(SavedFilterDTO.self, from: data)

        #expect(dto.id == 5)
        #expect(dto.title == "Overdue work")
        #expect(dto.filters?.filter == "priority >= 3 && done = false")
    }

    @Test
    func `maps the nested query into SavedFilterDetail verbatim`() throws {
        let url = try #require(Bundle.module.url(forResource: "saved-filter", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(SavedFilterDTO.self, from: data)

        let detail = SavedFilterMapper.toDomain(dto)

        #expect(detail.query == "priority >= 3 && done = false")
    }

    @Test
    func `maps a missing filters object to an empty query`() {
        let dto = SavedFilterDTO(id: 1, title: "No query", description: nil, isFavorite: nil, filters: nil)

        let detail = SavedFilterMapper.toDomain(dto)

        #expect(detail.query.isEmpty)
    }
}
