//
//  QueryFrontpageCommand.swift
//  App
//
//  Created by Austin Ellis on 12/23/19.
//
import FluentPostgreSQL
import Vapor


struct QueryFrontpageCommand: Command {
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
        let env = (
            username: try Environment.require("REDDIT_USERNAME", with: context),
            password: try Environment.require("REDDIT_PASSWORD", with: context),
            clientID: try Environment.require("CLIENT_ID", with: context),
            clientSecret: try Environment.require("CLIENT_SECRET", with: context)
        )
        
        print("!!!! env \(env)")
        
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
        
        let future = context.container.newConnection(to: .psql).flatMap(to: Void.self) { conn in
            let posts = Post.query(on: conn).all().do { posts in
                print("posts future!!! \(posts)")
            }.catch { error in
                print("error! \(error)")
                //return []
            }.map { posts in
                print("posts2 !!! \(posts)")
            }
            print("posts!!! \(posts)")
            return posts
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
