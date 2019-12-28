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
        return "https://www.reddit.com/r/all/hot.json?limit=100&g=GLOBAL\(after)"
    }
    static func info(for names: [String]) -> String {
        return "https://old.reddit.com/api/info.json?id=\(names.joined(separator: ","))"
    }
}

struct QueryFrontpageCommand: Command {
    struct Env {
        let username: String
        let password: String
        let clientID: String
        let clientSecret: String
        let client: Client
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
        let removedPosts: [PostsResponseData]
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
            client: try context.container.client()
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
            return QueryFrontpageCommand.fetchFrontpage(client: env.client).map { responses in
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
                    .map { arg in Post(name: arg.element.data.name, rank: Int64(arg.offset) )},
                updatedPosts: remote.initial.posts
                    .filter { currentNames.contains($0.name )}
                    .compactMap { post in
                        let newRank = Int64(currentPosts.firstIndex(where: { $0.data.name == post.name }) ?? Int(post.rank))
                        guard post.rank != newRank else { return nil }
                        print("updating \(post.name) to \(newRank) was (\(post.rank))")
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
        .flatMap(to: Diff.self) { diff in
            print("checking removed \(diff.removedPosts.count)")
            
        }
        .map(to: Void.self) { value in
            print("!!!! close db!! \(value.initial.connection)")
            value.initial.connection.close()
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
            print("access token queried \(tokens)")
            let promise = context.container.eventLoop.newPromise(Auth.self)
            let now = Date()
            if let token = tokens.first, token.expiresAt > now {
                print("access token loaded \(token)")
                promise.succeed(result: Auth(initial: initial, token: token.accessToken))
            } else {
                let httpReq = HTTPRequest(
                    method: .POST,
                    url: URLs.accessToken,
                    version: .init(major: 1, minor: 1),
                    headers: [
                        "Authorization": "Basic " + "\(env.clientID):\(env.clientSecret)".toBase64()
                    ],
                    body: "grant_type=password&username=\(env.username)&password=\(env.password)"
                )
                let req = Request(http: httpReq, using: context.container)
                _ = env.client.send(req).map { response in
                    if let error = try? response.content.syncGet(String.self, at: "error") {
                        throw FrontpageError.authError(message: error)
                    }
                    print("\nwahahaah-\n \(response.content)")
                    let accessToken = try AccessToken(now: now, context: response.content)
                    _ = (tokens.isEmpty ? accessToken.create(on: initial.connection)  : accessToken.update(on: initial.connection)).map { _ in
                        print("access token saved!!!")
                        _ = AccessToken.query(on: initial.connection).all().map { xxx in
                            print("get tokens!!! \(xxx)")
                            promise.succeed(result: Auth(initial: initial, token: accessToken.accessToken))
                        }
                    }
                }
            }
            return promise.futureResult
        }
    }
    
    private static func fetchFrontpage(client: Client, responses: [PostsResponseData] = [], max: Int = 1) -> Future<[PostsResponseData]> {
        print("fetch front page \(responses.count)")
        let future: Future<[PostsResponseData]> = client.get(
            URLs.all(after: responses.last?.after)
        ).map { response in
            if let error = try? response.content.syncGet(String.self, at: "error") {
                throw FrontpageError.fetchError(message: error)
            }
            let responseData = try response.content.syncGet(PostsResponseData.self, at: "data")
            print("!!!! fetched: \(responseData.children.count) posts")
            return responses + [responseData]
        }
        
        if responses.count >= max - 1 || (!responses.isEmpty && responses.last!.after == nil) {
            print("fetch!!! returning now!!!")
            return future
        } else {
            print("queueing up next one now")
            return future.flatMap { responses in
                return QueryFrontpageCommand.fetchFrontpage(client: client, responses: responses)
            }
        }
    }
    
    private static func fetchInfo(client: Client, removed posts: [Post]) -> Future<[(info: PostsResponseData.Child, post: Post)]> {
        guard !posts.isEmpty else {
            return client.container.future([])
        }
        let posts = posts.chunked(into: 99)
        return posts.map {
            client.get(
                URLs.info(for: $0.map { $0.data.name })
            )
        }
    }
}



/*let promise = context.container.eventLoop.newPromise(Void.self)

/// Dispatch some work to happen on a background thread
DispatchQueue.global().async {
    /// Puts the background thread to sleep
    /// This will not affect any of the event loops
    sleep(5)

    /// When the "blocking work" has completed,
    /// complete the promise and its associated future.
    print("promise succeed!!!!")
    promise.succeed()
}*/

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
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
