//
//  QueryFrontpageCommand.swift
//  App
//
//  Created by Austin Ellis on 12/23/19.
//

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
        return .done(on: context.container)
    }
}
