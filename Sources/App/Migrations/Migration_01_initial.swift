//
//  Migration_01_initial.swift
//  App
//
//  Created by Austin Ellis on 12/24/19.
//

import FluentPostgreSQL


extension Post: PostgreSQLMigration {}
extension AccessToken: PostgreSQLMigration {}
