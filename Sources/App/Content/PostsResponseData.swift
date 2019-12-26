//
//  PostsResponse.swift
//  App
//
//  Created by Austin Ellis on 12/25/19.
//

import Vapor

struct PostsResponseData: Content {
    struct Child: Content {
        struct Data: Content {
            var name: String
        }
        var kind: String
        var data: Data
    }
    
    var modhash: String
    var dist: Int
    var children: [Child]
    var before: String?
    var after: String?
}
