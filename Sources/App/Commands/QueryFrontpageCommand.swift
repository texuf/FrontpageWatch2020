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
        return []
    }
    
    /// See `Command`
    var help: [String] {
        return ["Run front page watch scripts."]
    }
    
    /// See `Command`.
    func run(using context: CommandContext) throws -> Future<Void> {
        let message = "whoo"
        /// We can use requireOption here since both options have default values
        let eyes = "hoo"
        let tongue = "boo"
        let padding = String(repeating: "-", count: message.count)
        let text: String = """
          \(padding)
        < \(message) >
          \(padding)
                  \\   ^__^
                   \\  (\(eyes)\\_______
                      (__)\\       )\\/\\
                        \(tongue)  ||----w |
                           ||     ||
        """
        context.console.print(text)
        
        
        print("!!!!! run !!!! \(context.container)")
        
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
