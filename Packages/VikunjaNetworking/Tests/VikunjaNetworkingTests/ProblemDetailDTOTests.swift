import Foundation
import Testing
@testable import VikunjaNetworking

struct ProblemDetailDTOTests {
    @Test
    func `builds A message from title detail AND code`() {
        let json = #"""
        {"title":"Validation failed","status":422,"detail":"Title cannot be empty","code":4017}
        """#

        let message = ProblemDetailDTO.message(from: Data(json.utf8))

        #expect(message == "Validation failed: Title cannot be empty (4017)")
    }

    @Test
    func `omits the code suffix when code is absent`() {
        let json = #"{"title":"Validation failed","status":422,"detail":"Title cannot be empty"}"#

        #expect(ProblemDetailDTO.message(from: Data(json.utf8)) == "Validation failed: Title cannot be empty")
    }

    @Test
    func `falls back to title alone when detail is absent`() {
        let json = #"{"title":"Validation failed","status":422}"#

        #expect(ProblemDetailDTO.message(from: Data(json.utf8)) == "Validation failed")
    }

    @Test
    func `falls back to detail alone when title is absent`() {
        let json = #"{"status":422,"detail":"Title cannot be empty"}"#

        #expect(ProblemDetailDTO.message(from: Data(json.utf8)) == "Title cannot be empty")
    }

    @Test
    func `returns nil when neither title nor detail is present`() {
        let json = #"{"status":422}"#

        #expect(ProblemDetailDTO.message(from: Data(json.utf8)) == nil)
    }

    @Test
    func `returns nil for malformed json`() {
        #expect(ProblemDetailDTO.message(from: Data("not json".utf8)) == nil)
    }
}
