import Foundation
import GRDB

struct AccountSnapshot: Equatable, Sendable {
    let syncStates: [SyncStateRecord]
    let projects: [ProjectRecord]
    let tasks: [TaskRecord]
    let labels: [LabelRecord]
    let comments: [TaskCommentRecord]
    let filters: [SavedFilterRecord]
    let reminders: [TaskReminderRecord]
    let memberships: [VirtualProjectTaskRecord]
    let relations: [TaskRelationRecord]
    let kanbanViews: [KanbanViewRecord]
    let kanbanBuckets: [KanbanBucketRecord]
    let kanbanAssignments: [KanbanAssignmentRecord]
    let mutations: [MutationQueueRecord]

    init(accountID: UUID, db: Database, includeSyncStates: Bool = true) throws {
        self.syncStates = if includeSyncStates {
            try SyncStateRecord.filter(Column("accountID") == accountID).fetchAll(db)
        } else {
            []
        }
        self.kanbanViews = try KanbanViewRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.kanbanBuckets = try KanbanBucketRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.kanbanAssignments = try KanbanAssignmentRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.projects = try ProjectRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.tasks = try TaskRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.labels = try LabelRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.comments = try TaskCommentRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.filters = try SavedFilterRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.reminders = try TaskReminderRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.memberships = try VirtualProjectTaskRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.relations = try TaskRelationRecord.filter(Column("accountID") == accountID).fetchAll(db)
        self.mutations = try MutationQueueRecord.filter(Column("accountID") == accountID).fetchAll(db)
    }

    /// Seed only server-backed identities. Every value is subsequently downloaded again.
    func seedIdentities(db: Database) throws {
        let projects = projects.filter { $0.remoteID != nil }
        let projectIDs = Set(projects.map(\.localID))
        for var project in projects {
            project.parentProjectLocalID = nil
            try project.insert(db)
        }
        try insert(tasks.filter { $0.remoteID != nil && projectIDs.contains($0.projectLocalID) }, db: db)
        try insert(labels.filter { $0.remoteID != nil }, db: db)
    }

    func replace(accountID: UUID, db: Database) throws {
        // Children cascade from projects; explicit deletes also clear orphaned queue/state rows.
        try ProjectRecord.filter(Column("accountID") == accountID).deleteAll(db)
        try LabelRecord.filter(Column("accountID") == accountID).deleteAll(db)
        try MutationQueueRecord.filter(Column("accountID") == accountID).deleteAll(db)
        try SyncStateRecord.filter(Column("accountID") == accountID).deleteAll(db)
        for var project in projects {
            project.parentProjectLocalID = nil
            try project.insert(db)
        }
        for project in projects {
            try project.update(db)
        }
        try insert(tasks, db: db)
        try insert(labels, db: db)
        try insert(filters, db: db)
        try insert(comments, db: db)
        try insert(reminders, db: db)
        try insert(memberships, db: db)
        try insert(relations, db: db)
        try insert(kanbanViews, db: db)
        try insert(kanbanBuckets, db: db)
        try insert(kanbanAssignments, db: db)
        try insert(syncStates, db: db)
    }

    private func insert(_ records: [some PersistableRecord], db: Database) throws {
        for record in records {
            try record.insert(db)
        }
    }
}
