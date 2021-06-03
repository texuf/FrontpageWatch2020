//
//  QueryFrontpageCommand.swift
//  App
//
//  Created by Austin Ellis on 12/23/19.
//
import FluentPostgreSQL
import Vapor

enum FrontpageError: Error {
    case dbConnectionError
    case authError(message: String)
    case fetchError(message: String)
    case outOfScope
}

fileprivate struct URLs {
    static let accessToken = "https://www.reddit.com/api/v1/access_token"
    static func all(after: String?) -> String {
        let after = (after != nil) ? "&after=\(after!)" : ""
        return "https://oauth.reddit.com/r/all/hot.json?limit=100&g=GLOBAL\(after)"
    }
    static func info(for names: [String]) -> String {
        return "https://oauth.reddit.com/api/info.json?id=\(names.joined(separator: ","))"
    }
    static var submit = "https://oauth.reddit.com/api/submit"
}

struct QueryFrontpageCommand: Command {
    struct PostBody: Content {
        static let defaultContentType: MediaType = .urlEncodedForm
        let sr: String
        let kind: String
        let title: String
        let url: String
    }
    struct Env {
        let username: String
        let password: String
        let clientID: String
        let clientSecret: String
        let fetchPageCount: Int /// how many pages do we fetch (100 posts per page)
        let minPostRank: Int /// what's the min rank required to count it (longtail does 101->1000
        let maxPostRank: Int /// what's the max post rank (undelete does 1 - 100)
        let client: Client
        let testing: Bool
        let bDeleteOops: Bool
    }
    
    struct Initial {
        let connection: PostgreSQLConnection
        let posts: [Post]
    }
    
    struct Auth {
        let initial: Initial
        let token: String
    }
    
    struct Remote {
        let initial: Initial
        let token: String
        let currentPosts: [PostsResponseData]
    }
    
    struct Diff {
        let initial: Initial
        let token: String
        let newPosts: [Post]
        let updatedPosts: [Post]
        let removedPosts: [Post]
    }
    
    struct RemovedInfo {
        let diff: Diff
        let removedPosts: [(info: PostsResponseData.Child, post: Post)]
    }
    
    /// See `Command`
    var arguments: [CommandArgument] {
        return []
    }
    
    /// See `Command`
    var options: [CommandOption] {
        return [
            .env(name: "REDDIT_USERNAME", short: "u"),
            .env(name: "REDDIT_PASSWORD", short: "p"),
            .env(name: "CLIENT_ID", short: "c"),
            .env(name: "CLIENT_SECRET", short: "s"),
            .env(name: "testing", short: "t")
        ]
    }
    
    /// See `Command`
    var help: [String] {
        return ["Run front page watch scripts."]
    }
    
    /// See `Command`.
    func run(using context: CommandContext) throws -> Future<Void> {
        let env = Env(
            username: try Environment.require("REDDIT_USERNAME", with: context),
            password: try Environment.require("REDDIT_PASSWORD", with: context),
            clientID: try Environment.require("CLIENT_ID", with: context),
            clientSecret: try Environment.require("CLIENT_SECRET", with: context),
            fetchPageCount: Int(try Environment.require("FETCH_PAGE_COUNT", with: context)) ?? 1,
            minPostRank: Int(try Environment.require("MIN_POST_RANK", with: context)) ?? 0,
            maxPostRank: Int(try Environment.require("MAX_POST_RANK", with: context)) ?? Int.max,
            client: try context.container.client(),
            testing: context.options["testing"] == "true",
            bDeleteOops: context.options["DELETE_OOPS"] == "true"
        )
        
        let future = context.container.newConnection(to: .psql)
        .flatMap(to: Initial.self) { conn in
            print("!! connection made ")
            return Post.query(on: conn).all().map { posts in
                return Initial(connection: conn, posts: posts)
            }
        }
        .flatMap(to: Auth.self) { initial in
            print("!! posts initial: \(initial.posts.count)")
            return QueryFrontpageCommand.getAuth(context: context, initial: initial, env: env)
        }
        .flatMap(to: Remote.self) { auth in
            //print("!!fetching hot!!!")
            return QueryFrontpageCommand.fetchFrontpage(client: env.client, token: auth.token, max: env.fetchPageCount).map { responses in
                return Remote(
                    initial: auth.initial,
                    token: auth.token,
                    currentPosts: responses
                )
            }
        }
        .map(to: Diff.self) { remote in
            let currentPosts: [PostsResponseData.Child] = remote.currentPosts.flatMap { $0.children }
            let previousNames = Set(remote.initial.posts.map { $0.name })
            let currentNames = Set(currentPosts.map { $0.data.name })
            let removedPostNames = previousNames.subtracting(currentNames)
            let newNames = currentNames.subtracting(previousNames)
            // print("removed \(removedPostNames.count) added \(newNames.count)")
            return Diff(
                initial: remote.initial,
                token: remote.token,
                newPosts: currentPosts
                    .enumerated()
                    .filter { arg in newNames.contains(arg.element.data.name) }
                    .map { arg in Post(name: arg.element.data.name, rank: arg.offset.postRank )},
                updatedPosts: remote.initial.posts
                    .filter { currentNames.contains($0.name )}
                    .compactMap { post in
                        guard let newRank = currentPosts.firstIndex(where: { $0.data.name == post.name })?.postRank, newRank != post.rank else {
                            // new rank is the same, this item was not updated
                            return nil
                        }
                        // print("updating \(post.name) to \(newRank) was (\(post.rank))")
                        return Post(
                            id: post.id,
                            name: post.name,
                            rank: newRank
                        )
                    },
                removedPosts: remote.initial.posts
                    .filter { removedPostNames.contains($0.name)}
            )
        }
        .flatMap(to: Diff.self) { diff in
            print("saving \(diff.newPosts.count)")
            return diff.newPosts
                .map { $0.save(on: diff.initial.connection) }
                .flatten(on: context.container)
                .transform(to: diff)
        }
        .flatMap(to: Diff.self) { diff in
            print("updating \(diff.updatedPosts.count)")
            return diff.updatedPosts
                .map { $0.update(on: diff.initial.connection)}
                .flatten(on: context.container)
                .transform(to: diff)
        }
        .flatMap(to: RemovedInfo.self) { diff in
            print("checking removed \(diff.removedPosts.count)")
            return QueryFrontpageCommand.fetchInfo(client: env.client, token: diff.token, removed: diff.removedPosts).map {
                RemovedInfo(diff: diff, removedPosts: $0)
            }
        }
        .flatMap(to: RemovedInfo.self) { removedInfo in
            let didntget = Set(removedInfo.diff.removedPosts.map { $0.name }).subtracting(removedInfo.removedPosts.map({ $0.post.name }))
            print("got info for \(removedInfo.removedPosts.count) posts, didn't get: \(didntget)")
            
            let oops = env.bDeleteOops ? removedInfo.diff.removedPosts.filter({ didntget.contains($0.name) }) : []
            
            let removedWithoutCensorship = removedInfo.removedPosts.filter {
                $0.info.data.removed_by_category == nil
                || $0.info.data.removed_by_category == "deleted"
            }.map { $0.post }
            
            let removedAboveThreashold = removedInfo.removedPosts.filter { $0.info.data.removed_by_category != nil && $0.post.rank < env.minPostRank }.map { $0.post }
            
            let removedBelowThreashold = removedInfo.removedPosts.filter { $0.info.data.removed_by_category != nil && $0.post.rank > env.maxPostRank }.map { $0.post }
            
            print("deleting \(removedWithoutCensorship.count) uncensored posts, \(removedAboveThreashold.count) censored posts ranked < \(env.minPostRank), \(removedBelowThreashold.count) > \(env.maxPostRank), and \(oops.count) oops ")
            
            return (removedWithoutCensorship + removedAboveThreashold + removedBelowThreashold + oops).map {
                $0.delete(on: removedInfo.diff.initial.connection)
            }
            .flatten(on: context.container)
            .transform(to: removedInfo)
        }
        .flatMap(to: RemovedInfo.self) { removedInfo in
            let censored = removedInfo.removedPosts.filter {
                $0.info.data.removed_by_category != nil
                && $0.info.data.removed_by_category != "deleted"
                && $0.post.rank >= env.minPostRank
                && $0.post.rank <= env.maxPostRank
            }
            print("found \(censored.count) censored posts")
            return censored.enumerated().map { params in
                let censoredPost = params.element
                let promise = context.container.eventLoop.newPromise(Void.self)
                let data = censoredPost.info.data
                let title = "[#\(censoredPost.post.rank)|+\(data.ups)|\(data.num_comments)] \(data.title.truncate(length: 240 - data.subreddit_name_prefixed.count)) [\(data.subreddit_name_prefixed)]"
                let permalink = "reddit.com\(data.permalink)"
                let subreddit = censoredPost.post.rank < 100 ? "undelete" : "longtail"
                let postBody = PostBody(sr: subreddit, kind: "link", title: title, url: permalink)
                let headers: HTTPHeaders = [
                    "Authorization": "bearer \(removedInfo.diff.token)",
                    "User-Agent": "FrontpageWatch2020/0.1 by FrontpageWatch2020"
                ]
                let waitTime = 1 * Double(params.offset)
                DispatchQueue.global().asyncAfter(deadline: .now() + waitTime) {
                    print("posting \(title) after \(waitTime)s wait, reason: \(data.removed_by_category ?? "nil") ")
                    //let req = Request(http: httpReq, using: context.container)
                    _ = env.client.post(URLs.submit, headers: headers, beforeSend: { request in
                        try request.content.encode(postBody)
                    }).map { response in
                        print("!!!! submit post response \(response.content)")
                        _ = censoredPost.post.delete(on: removedInfo.diff.initial.connection).map {
                            promise.succeed()
                        }
                    }
                }
                return promise.futureResult
            }
            .flatten(on: context.container)
            .transform(to: removedInfo)
        }
        .map(to: Void.self) { value in
            print("!!!! close db!! \(value.diff.initial.connection)")
            value.diff.initial.connection.close()
        }
        
        //let posts = Post.query(on: req).all()
        
        // Creates a new connection to `.sqlite` db
        // let conn = try context.container.newConnection(to: .psql).wait()
        // Ensure the connection is closed when we exit this scope.
        // defer { conn.close() }
        
        //print("!!! items: \(Post.query(on: conn).all())")
        
        //return promise.futureResult.transform(to: .done(on: context.container))
        return future.transform(to: .done(on: context.container))
    }
    
    private static func getAuth(context: CommandContext, initial: Initial, env: Env) -> Future<Auth> {
        return AccessToken.query(on: initial.connection).all().flatMap(to: Auth.self) { tokens in
            // print("access token queried \(tokens)")
            let promise = context.container.eventLoop.newPromise(Auth.self)
            let now = Date()
            if let token = tokens.first, token.expiresAt > now {
                print("access token loaded")
                promise.succeed(result: Auth(initial: initial, token: token.accessToken))
            } else {
                let httpReq = HTTPRequest(
                    method: .POST,
                    url: URLs.accessToken,
                    version: .init(major: 1, minor: 1),
                    headers: [
                        "Authorization": "Basic " + "\(env.clientID):\(env.clientSecret)".toBase64(),
                        "User-Agent": "FrontpageWatch2020/0.1 by FrontpageWatch2020"
                    ],
                    body: "grant_type=password&username=\(env.username)&password=\(env.password)"
                )
                let req = Request(http: httpReq, using: context.container)
                _ = env.client.send(req).map { response in
                    if let error = try? response.content.syncGet(String.self, at: "error") {
                        throw FrontpageError.authError(message: error)
                    }
                    // print("\nwahahaah-\n \(response.content)")
                    let accessToken = try AccessToken(now: now, context: response.content)
                    _ = (tokens.isEmpty ? accessToken.create(on: initial.connection)  : accessToken.update(on: initial.connection)).map { _ in
                        print("access retreived and saved!!!")
                        promise.succeed(result: Auth(initial: initial, token: accessToken.accessToken))
                    }
                }
            }
            return promise.futureResult
        }
    }
    
    private static func fetchFrontpage(client: Client, token: String, responses: [PostsResponseData] = [], max: Int) -> Future<[PostsResponseData]> {
        print("fetch front page \(responses.count)")
        let httpReq = HTTPRequest(
           method: .GET,
           url: URLs.all(after: responses.last?.after),
           version: .init(major: 1, minor: 1),
           headers: [
               "Authorization": "bearer \(token)",
               "User-Agent": "FrontpageWatch2020/0.1 by FrontpageWatch2020"
           ]
       )

        let future: Future<[PostsResponseData]> = client.send(
            // URLs.all(after: responses.last?.after)
            Request(http: httpReq, using: client.container)
        ).map { response in
            if let error = try? response.content.syncGet(String.self, at: "error") {
                throw FrontpageError.fetchError(message: error)
            } else if let errorCode = try? response.content.syncGet(Int.self, at: "error") {
                let message = try? response.content.syncGet(String.self, at: "message")
                throw FrontpageError.fetchError(message: "error: \(errorCode) message: \(message ?? "")")
            }
            // print("!!! frontpage: \(response.content)")
            let responseData = try response.content.syncGet(PostsResponseData.self, at: "data")
            print("!!!! fetched: \(responseData.children.count) posts")
            return responses + [responseData]
        }
        
        if responses.count >= max - 1 || (!responses.isEmpty && responses.last!.after == nil) {
            // print("fetch!!! returning now!!!")
            return future
        } else {
            // print("queueing up next one now")
            return future.flatMap { responses in
                return QueryFrontpageCommand.fetchFrontpage(client: client, token: token, responses: responses, max: max)
            }
        }
    }
    
    private static func fetchInfo(client: Client, token: String, removed removedPosts: [Post]) -> Future<[(info: PostsResponseData.Child, post: Post)]> {
        guard !removedPosts.isEmpty else {
            print("Nothing to check!! returning empty future")
            return client.container.future([])
        }
        let chunkedPosts = removedPosts.chunked(into: 99)
        let fetched: Future<[[(info: PostsResponseData.Child, post: Post)]]> = chunkedPosts.map { chunk in
            let httpReq = HTTPRequest(
                method: .GET,
                url: URLs.info(for: chunk.map { $0.name }),
                version: .init(major: 1, minor: 1),
                headers: [
                    "Authorization": "bearer \(token)",
                    "User-Agent": "FrontpageWatch2020/0.1 by FrontpageWatch2020"
                ]
            )

            return client.send(
                //URLs.info(for: chunk.map { $0.name })
                Request(http: httpReq, using: client.container)
            ).map { response in
                if let error = try? response.content.syncGet(String.self, at: "error") {
                    throw FrontpageError.fetchError(message: error)
                } else if let errorCode = try? response.content.syncGet(Int.self, at: "error") {
                    let message = try? response.content.syncGet(String.self, at: "message")
                    throw FrontpageError.fetchError(message: "error: \(errorCode) message: \(message ?? "")")
                }
                let postResponseData = try response.content.syncGet(PostsResponseData.self, at: "data")
                let paired: [(info: PostsResponseData.Child, post: Post)] = postResponseData.children.compactMap { child in
                    guard let post = chunk.first(where: { $0.name == child.data.name }) else { return nil }
                    return (info: child, post: post)
                }
                return paired
            }
        }
        .flatten(on: client.container)
        
        
        return fetched.map { $0.flatMap { $0 } }
    }
}

extension AccessToken {
    init(now: Date, context: ContentContainer<Response>) throws {
        let expiresIn = try context.syncGet(Int.self, at: "expires_in")
        self.id = 1
        self.expiresAt = now.addingTimeInterval(TimeInterval(expiresIn))
        self.accessToken = try context.syncGet(String.self, at: "access_token")
        self.tokenType = try context.syncGet(String.self, at: "token_type")
        self.scope = try context.syncGet(String.self, at: "scope")
    }
}

extension Environment {
    /// check context then env for key, return value, throw if neither exists
    static func require(_ key: String, with context: CommandContext) throws -> String {
        do {
            return try context.requireOption(key)
        } catch {
            if let value = Environment.get(key) {
                return value
            }
            throw error
        }
    }
}

extension CommandOption {
    static func env(name: String, short: Character) -> CommandOption {
        return CommandOption.value(name: name, short: short, default: nil, help: helpFor(name: name, short: short))
    }
    
    private static func helpFor(name: String, short: Character) -> [String] {
        return ["`-\(short)` command line argument or `\(name)` environment variable required"]
    }
}

extension String {
    
    func toBase64() -> String {
        return Data(self.utf8).base64EncodedString()
    }
    /**
     Truncates the string to the specified length number of characters and appends an optional trailing string if longer.
     
     - Parameter length: A `String`.
     - Parameter trailing: A `String` that will be appended after the truncation.
    
     - Returns: A `String` object.
     */
    func truncate(length: Int, trailing: String = "…") -> String {
        if self.count > length {
            return String(self.prefix(length)) + trailing
        } else {
            return self
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Int {
    /// return 1 based int64 index of optional int
    var postRank: Int64 {
        return Int64(self + 1)
    }
}
