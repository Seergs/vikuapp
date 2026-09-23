import Foundation
import Testing
@testable import VikunjaNetworking

struct APIv2EnvelopeTests {
    private struct ItemDTO: Decodable, Equatable {
        let id: Int
        let title: String
    }

    @Test
    func `decodes items alongside pagination metadata`() throws {
        let json = #"""
        {
          "items": [{"id": 1, "title": "one"}, {"id": 2, "title": "two"}],
          "total": 2,
          "page": 1,
          "per_page": 50,
          "total_pages": 1
        }
        """#

        let envelope = try JSONDecoder().decode(APIv2Envelope<ItemDTO>.self, from: Data(json.utf8))

        #expect(envelope.items == [ItemDTO(id: 1, title: "one"), ItemDTO(id: 2, title: "two")])
        #expect(envelope.total == 2)
        #expect(envelope.page == 1)
        #expect(envelope.perPage == 50)
        #expect(envelope.totalPages == 1)
    }

    @Test
    func `decodes an empty items page`() throws {
        let json = #"{"items": [], "total": 0, "page": 1, "per_page": 50, "total_pages": 0}"#

        let envelope = try JSONDecoder().decode(APIv2Envelope<ItemDTO>.self, from: Data(json.utf8))

        #expect(envelope.items.isEmpty)
    }
}
