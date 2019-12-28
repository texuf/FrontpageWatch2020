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
            var id: String
            var name: String
            var removed_by_category: String?
            var num_comments: Int
            var score: Int
            var ups: Int
            var downs: Int
            var title: String
            var subreddit: String
            var subreddit_name_prefixed: String
            var permalink: String
        }
        var kind: String
        var data: Data
    }
    
    var modhash: String?
    var dist: Int
    var children: [Child]
    var before: String?
    var after: String?
}
