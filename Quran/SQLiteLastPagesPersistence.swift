//
//  SQLiteLastPagesPersistence.swift
//  Quran
//
//  Created by Mohamed Afifi on 11/5/16.
//  Copyright © 2016 Quran.com. All rights reserved.
//

import Foundation
import SQLite

private let maxNumberOfLastPages = 3

extension PersistenceKeyBase {
    fileprivate static let lastViewedPage = PersistenceKey<Int?>(key: "LastViewedPage", defaultValue: nil)
}

extension Queue {
    static let lastPages = Queue(queue: DispatchQueue(label: "com.quran.last_pages"))
}

struct SQLiteLastPagesPersistence: LastPagesPersistence, SQLitePersistence {

    let version: UInt = 1
    var filePath: String {
        return FileManager.default.documentsPath + "/last_pages.db"
    }

    let simplePersistence: SimplePersistence

    private struct LastPages {
        static let table = Table("last_page")
        static let id = Expression<Int64>("_ID")
        static let page = Expression<Int>("page")
        static let createdOn = Expression<Date>("added_date")
        static let modifiedOn = Expression<Date>("modified_date")
    }

    func onCreate(connection: Connection) throws {
        // Last Pages table
        try connection.run(LastPages.table.create { builder in
            builder.column(LastPages.id, primaryKey: .autoincrement)
            builder.column(LastPages.page, unique: true)
            builder.column(LastPages.createdOn)
            builder.column(LastPages.modifiedOn)
        })

        // migrate from old persistence.
        if let lastPage = simplePersistence.valueForKey(.lastViewedPage) {
            let insert = LastPages.table.insert(
                LastPages.page <- lastPage,
                LastPages.createdOn <- Date(),
                LastPages.modifiedOn <- Date())
            _ = try connection.run(insert)
            simplePersistence.removeValueForKey(.lastViewedPage)
        }
    }

    func retrieveAll() throws -> [LastPage] {
        return try run { connection in
            let query = LastPages.table.order(LastPages.modifiedOn.desc)
            let rows = try connection.prepare(query)
            let pages = convert(rowsToLastPages: rows)
            return pages
        }
    }

    func add(page: Int) throws -> LastPage {
        return try run { connection in
            let insert = LastPages.table.insert(
                or: .replace,
                LastPages.page <- page,
                LastPages.createdOn <- Date(),
                LastPages.modifiedOn <- Date())
            let rowId = try connection.run(insert)
            let rows = try connection.prepare(LastPages.table.filter(LastPages.id == rowId))

            // keep top maxNumberOfLastPages rows only
            let statement = "DELETE FROM last_page WHERE _ID NOT IN (SELECT _ID FROM last_page ORDER BY modified_date DESC LIMIT \(maxNumberOfLastPages))" // swiftlint:disable:this line_length
            try connection.run(statement)

            return convert(rowsToLastPages: rows)[0]
        }
    }

    func update(page: LastPage, toPage newPage: Int) throws -> LastPage {
        // update it if the same page, since it should upate the dates.

        return try run { connection in

            // delete conflict record for the new & old pages.
            let conflict = LastPages.table.filter([page.page, newPage].contains(LastPages.page))
            _ = try connection.run(conflict.delete())

            var updatedPage = page
            updatedPage.page = newPage
            updatedPage.modifiedOn = Date()
            updatedPage.createdOn = Date()

            // Insert or update the record
            let insert = LastPages.table.insert(
                LastPages.page <- updatedPage.page,
                LastPages.createdOn <- updatedPage.createdOn,
                LastPages.modifiedOn <- updatedPage.modifiedOn)
            _ = try connection.run(insert)
            return updatedPage
        }
    }

    private func convert(rowsToLastPages rows: AnySequence<Row>) -> [LastPage] {
        return rows.map { row in
            let page = row[LastPages.page]
            let createdOn = row[LastPages.createdOn]
            let modifiedOn = row[LastPages.modifiedOn]
            return LastPage(page: page, createdOn: createdOn, modifiedOn: modifiedOn)
        }
    }
}
