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

extension VikunjaErrorDisplayMessageTests {
    @Test func `completion capacity copy identifies the action column and project`() {
        let error = VikunjaError.bucketCapacity(column: "Por hacer", project: "Trabajo")
        #expect(error.completionFailureMessage(isDone: false) ==
            "Couldn’t mark as pending. Column “Por hacer” in the “Trabajo” Kanban board is full.")
        #expect(error.completionFailureMessage(isDone: true) ==
            "Couldn’t complete. Column “Por hacer” in the “Trabajo” Kanban board is full.")
        #expect(error.completionFailureMessage(isDone: false, isBulk: true) ==
            "No tasks were changed. Column “Por hacer” in the “Trabajo” Kanban board cannot fit the selection.")
        #expect(error.displayMessage == "Column “Por hacer” in the “Trabajo” Kanban board has reached its task limit.")
    }

    @Test func `server capacity errors explain the Kanban destination without inventing names`() {
        #expect(VikunjaError.bucketFull.completionFailureMessage(isDone: false) ==
            "Couldn’t mark as pending. A destination column in this task’s Kanban board is full.")
        #expect(VikunjaError.bucketFull.completionFailureMessage(isDone: true, isBulk: true) ==
            "No tasks were changed. A destination column in the Kanban board cannot fit the selection.")
        #expect(VikunjaError.offline.completionFailureMessage(isDone: false) == VikunjaError.offline.displayMessage)
    }
}
