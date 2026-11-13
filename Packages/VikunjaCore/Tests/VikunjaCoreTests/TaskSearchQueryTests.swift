import Foundation
import Testing
@testable import VikunjaCore

struct TaskSearchQueryTests {
    private let bug = Label(id: 1, title: "Bug", hexColor: "")
    private let urgent = Label(id: 2, title: "Urgent", hexColor: "")

    @Test(arguments: [QuickAddSyntax.vikunja, .todoist])
    func `search shares dialect tokens while leaving dates and assignees as text`(syntax: QuickAddSyntax) {
        let input = "\(syntax.labelSigil)Bug \(syntax.projectSigil)\"My Project\" \(syntax.priorityPrefix)3 login tomorrow"
        let query = QuickAddParser.searchQuery(input, syntax: syntax)
        #expect(query.text == "login tomorrow")
        #expect(query.labelNames == ["Bug"])
        #expect(query.projectName == "My Project")
        #expect(query.priority == syntax.priority(forLevel: 3))
        #expect(QuickAddParser.searchQuery("login @alice", syntax: .vikunja).text == "login @alice")
    }

    @Test func `disabled syntax keeps the entire search literal`() {
        let query = QuickAddParser.searchQuery("  *Bug +Work !3 tomorrow  ", syntax: nil)
        #expect(query == TaskSearchQuery(text: "*Bug +Work !3 tomorrow"))
    }

    @Test func `escapes quotes and incomplete tokens follow quick add recognition`() {
        let query = QuickAddParser.searchQuery(#"\*Bug *“Needs review” +"My Project" login"#, syntax: .vikunja)
        #expect(query.text == "*Bug login")
        #expect(query.labelNames == ["Needs review"])
        #expect(query.projectName == "My Project")
        #expect(QuickAddParser.searchQuery(#"*"unfinished !9 a*b"#, syntax: .vikunja).text == #"*"unfinished !9 a*b"#)
    }

    @Test func `first project and priority take precedence`() {
        let query = QuickAddParser.searchQuery("+One +Two !3 !4 *Bug *Urgent", syntax: .vikunja)
        #expect(query.text.isEmpty)
        #expect(query.projectName == "One")
        #expect(query.priority == .high)
        #expect(query.labelNames == ["Bug", "Urgent"])
    }

    @Test func `labels combine with OR while project priority and title restrict results`() {
        let tasks = [
            VikunjaTask(id: 1, title: "Login bug", priority: .high, projectID: 1, labels: [bug]),
            VikunjaTask(id: 2, title: "LOGIN urgent", priority: .high, projectID: 1, labels: [urgent]),
            VikunjaTask(id: 3, title: "Login both", priority: .high, projectID: 1, labels: [bug, urgent]),
            VikunjaTask(id: 4, title: "Login other project", priority: .high, projectID: 2, labels: [bug]),
            VikunjaTask(id: 5, title: "Login low", priority: .low, projectID: 1, labels: [bug]),
            VikunjaTask(id: 6, title: "Other", priority: .high, projectID: 1, labels: [bug]),
            VikunjaTask(id: 7, title: "Login unlabeled", priority: .high, projectID: 1),
        ]
        let query = QuickAddParser.searchQuery("*Bug *Urgent +Work !3 login", syntax: .vikunja)
        let results = query.filter(tasks: tasks, projects: [Project(id: 1, title: "Work")], labels: [bug, urgent])
        #expect(results.map(\.id) == [1, 2, 3])
    }

    @Test func `unknown names are removed and ignored including a query with only unknown names`() {
        let tasks = [VikunjaTask(id: 1, title: "Login", projectID: 1, labels: [bug])]
        for input in ["*Bgu +Missing login", "*Bgu", "*Bug *Bgu login"] {
            let query = QuickAddParser.searchQuery(input, syntax: .vikunja)
            #expect(query.filter(tasks: tasks, projects: [], labels: [bug]) == tasks)
        }
        let other = VikunjaTask(id: 2, title: "Login", projectID: 1)
        let query = QuickAddParser.searchQuery("*Bug *Bgu login", syntax: .vikunja)
        #expect(query.filter(tasks: tasks + [other], projects: [], labels: [bug]) == tasks)
    }

    @Test func `duplicate folded names include all identities including local creations`() {
        let localProject = EntityID.local(UUID())
        let localLabel = Label(id: .local(UUID()), title: "BÚG", hexColor: "")
        let projects = [Project(id: 1, title: "Compras"), Project(id: localProject, title: "Cómpras")]
        let tasks = [
            VikunjaTask(id: 1, title: "Milk", projectID: 1, labels: [bug]),
            VikunjaTask(id: .local(UUID()), title: "Milk", projectID: localProject, labels: [localLabel]),
        ]
        let query = QuickAddParser.searchQuery("+compras *Bug", syntax: .vikunja)
        #expect(query.filter(tasks: tasks, projects: projects, labels: [bug, localLabel]) == tasks)
    }

    @Test func `text search does not match descriptions or parse natural dates`() {
        let task = VikunjaTask(id: 1, title: "Tomorrow login", description: "Other text", projectID: 1)
        let descriptionMatches = TaskSearchQuery(text: "other").filter(tasks: [task], projects: [], labels: [])
        #expect(descriptionMatches.isEmpty)
        let query = QuickAddParser.searchQuery("tomorrow", syntax: .vikunja)
        #expect(query.filter(tasks: [task], projects: [], labels: []) == [task])
    }
}
