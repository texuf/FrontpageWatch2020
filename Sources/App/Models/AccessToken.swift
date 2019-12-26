//
//  AccessToken.swift
//  App
//
//  Created by Austin Ellis on 12/25/19.
//

import FluentPostgreSQL
import Vapor

struct AccessToken: PostgreSQLModel {
    typealias ID = Int
    var id: ID?
    var expiresAt: Date
    var accessToken: String
    var tokenType: String
    var scope: String
    
    init(id: ID? = 1, expiresAt: Date, accessToken: String, tokenType: String, scope: String) {
        self.id = id
        self.expiresAt = expiresAt
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
    }
}

