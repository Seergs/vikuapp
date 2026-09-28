import GRDB
import Testing

struct GRDBDependencyTests {
    @Test
    func `GRDB reads back what it writes in an in memory database`() throws {
        let dbQueue = try DatabaseQueue()

        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE item (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO item (name) VALUES (?)", arguments: ["test"])
        }

        let name = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM item WHERE id = 1")
        }

        #expect(name == "test")
    }
}
