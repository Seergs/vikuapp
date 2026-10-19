import Testing
import VikunjaCore

struct VikunjaErrorDisplayMessageTests {
    @Test
    func `a server error shows the server's own message when one was parsed`() {
        let message = "The default project must be a project you can write to."
        let error = VikunjaError.server(message: message, statusCode: 400)

        #expect(error.displayMessage == message)
    }

    @Test
    func `a server error with no parsed message falls back to the generic status text`() {
        let error = VikunjaError.server(message: "", statusCode: 500)

        #expect(error.displayMessage == "The server responded with an error (500).")
    }
}
