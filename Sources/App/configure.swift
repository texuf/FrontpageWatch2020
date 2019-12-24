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
    print("!!!!!! configure name: \(env.name) isRelease: \(env.isRelease) has db: \(Environment.get("DATABASE_URL") != nil)")
    
    
    try services.register(FluentPostgreSQLProvider())
    
    // Configure a PostgreSQL database
    let postgreSQLConfig : PostgreSQLDatabaseConfig

    print("config 1")
    if let url = Environment.get("DATABASE_URL") {
        postgreSQLConfig = PostgreSQLDatabaseConfig(url: url)!
    } else {
        postgreSQLConfig = try PostgreSQLDatabaseConfig.default()
    }
    
    let postgreSQL = PostgreSQLDatabase(config: postgreSQLConfig)
    print("config 2")
    // Register the configured PostreSQL database to the database config.
    var databases = DatabasesConfig()
    databases.add(database: postgreSQL, as: .psql)
    services.register(databases)
    
    print("config 3")
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
