import Foundation
import Testing
import VikunjaCore
@testable import VikunjaNetworking

struct CommentDTOTests {
    @Test
    func `decodes realistic comments payload`() throws {
        let dtos = try loadCommentDTOs()

        #expect(dtos.count == 2)
        #expect(dtos[0].comment == "<p>Looks good to me.</p>")
        #expect(dtos[0].author.username == "alex")
        #expect(dtos[1].author.name == nil)
    }

    @Test
    func `maps to domain via comment mapper`() throws {
        let dtos = try loadCommentDTOs()
        let comments = dtos.map(CommentMapper.toDomain)

        #expect(comments[0].id == 1)
        #expect(comments[0].author.username == "alex")
        #expect(!comments[0].isEdited)
        #expect(comments[1].isEdited)
        #expect(comments[1].updated > comments[1].created)
    }

    private func loadCommentDTOs() throws -> [CommentDTO] {
        let url = try #require(Bundle.module.url(forResource: "comments", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CommentDTO].self, from: data)
    }
}
