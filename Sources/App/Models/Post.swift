//
//  Post.swift
//  App
//
//  Created by Austin Ellis on 12/23/19.
//

import FluentPostgreSQL
import Vapor

struct Post: PostgreSQLModel {
    typealias ID = Int
    var id: ID?
    var date: Date
    var content: String

    init(id: ID? = nil, date: Date, content: String) {
        self.id = id
        self.date = date
        self.content = content
    }
}
