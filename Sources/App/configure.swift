import FluentPostgreSQL
import Vapor

/// Called before your application initializes.
///
/// [Learn More →](https://docs.vapor.codes/3.0/getting-started/structure/#configureswift)
public func configure(
    _ config: inout Config,
    _ env: inout Environment,
    _ services: inout Services
) throws {
    print("!!!!!! configure!!! ")
    try services.register(FluentPostgreSQLProvider())
    
    var migrations = MigrationConfig()
    migrations.add(model: Post.self, database: .psql)
    services.register(migrations)
    
    /// Create a `CommandConfig` with default commands.
    var commandConfig = CommandConfig.default()
    /// Add the `CowsayCommand`.
    commandConfig.use(QueryFrontpageCommand(), as: "query")
    /// Register this `CommandConfig` to services.
    services.register(commandConfig)
    
    // Register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)

    // Configure the rest of your application here
}
