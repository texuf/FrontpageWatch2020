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
    var name: String
    var rank: Int64

    init(id: ID? = nil, name: String, rank: Int64) {
        self.id = id
        self.name = name
        self.rank = rank
    }
}
