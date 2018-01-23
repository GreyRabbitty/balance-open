//
//  Database.swift
//  Bal
//
//  Created by Benjamin Baron on 2/1/16.
//  Copyright © 2016 Balanced Software, Inc. All rights reserved.
//

#if os(OSX)
    import Foundation
#else
    import UIKit
#endif

private class FMDatabasePoolDelegate: NSObject {
    override func databasePool(_ pool: FMDatabasePool!, didAdd db: FMDatabase!) {
        // Decrypt the database
        db.executeStatements("PRAGMA key='\(database.password!)'")
        
        // Enable WAL mode for reads
        db.executeStatements("PRAGMA journal_mode=WAL")
    }
}

class Database {
    
    // MARK: - Properties -
    
    fileprivate let readPoolDelegate = FMDatabasePoolDelegate()
    
    fileprivate static let defaultDatabaseName = "balance.db"
    fileprivate let databaseName: String
    fileprivate let databasePath: String

    /// We're using WAL mode, so only writes need to be serialized. Reads can be multithreaded with no regard for writes.
    let read: FMDatabasePool
    
    /// Use a database queue to serialize writes. This allows multithreaded access.
    let write: FMDatabaseQueue
    
    fileprivate var password: String? {
        get {
            return keychain[KeychainAccounts.Database, KeychainKeys.Password]
        }
        set {
            keychain[KeychainAccounts.Database, KeychainKeys.Password] = newValue
        }
    }
        
    // MARK: - Lifecycle -
    
    init(databaseName: String = Database.defaultDatabaseName, pathPrefix: String? = nil) {
        let databasePathPrefix = (pathPrefix == nil ? appSupportPathUrl : URL(fileURLWithPath: pathPrefix!))
        let databasePath = databasePathPrefix.appendingPathComponent(databaseName).path
        
        self.databaseName = databaseName
        self.databasePath = databasePath
        
        self.read = FMDatabasePool(path: databasePath)
        self.write = FMDatabaseQueue(path: databasePath)
    }
    
    var debugEmailSendComplete = false
    var debugOkButtonPressed = false
    var debugCanCloseApp: Bool { return debugEmailSendComplete && debugOkButtonPressed }
    func create() -> Bool {
        // Generate a per-device database password, and store it in the keychain
        if password == nil {
            password = String.random(32)
        }
        
        // Check for keychain problem
        guard password != nil else {
            // It looks like we are unable to read from and write to the keychain. This issue seems to affect a small percentage of users.
            // At this point, rather than force unwrapping and crashing, let's show a message and send the logs.
            Feedback.send(email: "noreply@balancemy.money", comment: "Failed to read/write database password. Debug logs attached.", completion: { _, _ in
                self.debugEmailSendComplete = true
                if self.debugCanCloseApp {
                    fatalError()
                }
            })
            
            #if os(OSX)
                let alert = NSAlert()
                alert.addButton(withTitle: "OK")
                alert.messageText = "Unable to read database password"
                alert.informativeText = "It looks like we are unable to read from and write to the keychain. This issue seems to affect a small percentage of users. In previous betas, this would cause the app to crash on launch. We've added extra logging to debug the issue before the 1.0 release. We're uploading your logs now (don't worry, no API key or other sensitive information is included.\n\nThe app will close automatically when the logs finish uploading."
                alert.alertStyle = .informational
                if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
                    self.debugOkButtonPressed = true
                    if self.debugCanCloseApp {
                        fatalError()
                    }
                }
                return false
            #else
                let alert = UIAlertController(title: "Unable to read database password", message: "It looks like we are unable to read from and write to the keychain. This issue seems to affect a small percentage of users. In previous betas, this would cause the app to crash on launch. We've added extra logging to debug the issue before the 1.0 release. We're uploading your logs now (don't worry, no API key or other sensitive information is included.\n\nThe app will close automatically when the logs finish uploading.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    self.debugOkButtonPressed = true
                    if self.debugCanCloseApp {
                        fatalError()
                    }
                })
                async(after: 1.5) {
                    AppDelegate.sharedInstance.window?.rootViewController?.present(alert, animated: true)
                }
                return false
            #endif
        }
        
        #if DEBUG
        log.debug("\nsqlcipher \"\(self.databasePath)\" -cmd \"PRAGMA key='\(self.password!)';\"")
        #endif
            
        // Enable WAL mode for writes
        var success = true
        write.inDatabase { db in
            // Decrypt the database
            db.executeStatements("PRAGMA key='\(database.password!)'")
            
            // Enable WAL mode for reads
            success = db.executeStatements("PRAGMA journal_mode=WAL")
            if !success {
                log.severe("Unable to set WAL mode, error: \(db.lastError())")
            }
        }
        
        guard success else {
            log.severe("Resetting database and restarting")
            self.resetDatabase()
            return false
        }
        
        // Create default tables if needed
        write.inDatabase { db in
            var statements = [String]()
            
            // sources table
            statements.append("CREATE TABLE IF NOT EXISTS sources " +
                              "(sourceId INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
            statements.append("INSERT OR IGNORE INTO sources VALUES (1, \"Plaid\")")
            statements.append("INSERT OR IGNORE INTO sources VALUES (2, \"Coinbase\")")
            statements.append("INSERT OR IGNORE INTO sources VALUES (3, \"Poloniex\")")
            statements.append("INSERT OR IGNORE INTO sources VALUES (4, \"GDAX\")")
            statements.append("INSERT OR IGNORE INTO sources VALUES (5, \"Bitfinex\")")
            
            // institutions table
            statements.append("CREATE TABLE IF NOT EXISTS institutions " +
                              "(institutionId INTEGER PRIMARY KEY AUTOINCREMENT, sourceId INTEGER, sourceInstitutionId TEXT, " +
                              "name TEXT, nameBreak INTEGER, primaryColor TEXT, secondaryColor TEXT, logoData BLOB, passwordInvalid INTEGER, dateAdded INTEGER)")
            statements.append("CREATE INDEX IF NOT EXISTS institutions_sourceIdsourceInstitutionId " +
                              "ON institutions (sourceId, sourceInstitutionId)")
            
            // accountType table
            statements.append("CREATE TABLE IF NOT EXISTS accountTypes " +
                              "(accountTypeId INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
            
            // account table
            statements.append("CREATE TABLE IF NOT EXISTS accounts " +
                              "(accountId INTEGER PRIMARY KEY AUTOINCREMENT, institutionId INTEGER, sourceId INTEGER, " +
                              "sourceAccountId TEXT, sourceInstitutionId TEXT, accountTypeId INTEGER, accountSubTypeId INTEGER, " +
                               "name TEXT, currency TEXT, currentBalance INTEGER, availableBalance INTEGER, number TEXT, altCurrency TEXT, altCurrentBalance INTEGER, altAvailableBalance INTEGER)")
            if db.columnExists("decimals", inTableWithName: "accounts") {
                // Migrage to new accounts table format
                statements.append("DROP TABLE IF EXISTS accountsTemp")
                statements.append("CREATE TABLE accountsTemp " +
                                  "(accountId INTEGER PRIMARY KEY AUTOINCREMENT, institutionId INTEGER, sourceId INTEGER, " +
                                  "sourceAccountId TEXT, sourceInstitutionId TEXT, accountTypeId INTEGER, accountSubTypeId INTEGER, " +
                                  "name TEXT, currency TEXT, currentBalance INTEGER, availableBalance INTEGER, number TEXT, altCurrency TEXT, altCurrentBalance INTEGER, altAvailableBalance INTEGER)")
                statements.append("INSERT INTO accountsTemp " +
                                  "SELECT accountId, institutionId, sourceId, " +
                                  "sourceAccountId, sourceInstitutionId, accountTypeId, accountSubTypeId, " +
                                  "name, currency, currentBalance, availableBalance, number, altCurrency, altCurrentBalance, altAvailableBalance " +
                                  "FROM accounts")
                statements.append("DROP TABLE accounts")
                statements.append("ALTER TABLE accountsTemp RENAME TO accounts")
            }
            
            // category table
            statements.append("CREATE TABLE IF NOT EXISTS categories " +
                              "(categoryId INTEGER PRIMARY KEY AUTOINCREMENT, sourceId INTEGER, sourceCategoryId TEXT, " +
                              "name1 TEXT, name2 TEXT, name3 TEXT)")
            statements.append("CREATE UNIQUE INDEX IF NOT EXISTS categories_sourceIdsourceCategoryId " +
                              "ON categories (sourceId, sourceCategoryId)")
            statements.append("CREATE INDEX IF NOT EXISTS categories_sourceCategoryId " +
                              "ON categories (sourceCategoryId)")
            statements.append("CREATE INDEX IF NOT EXISTS categories_sourceIdNames " +
                              "ON categories (sourceId, name1, name2, name3)")
            
            // transaction table
            statements.append("CREATE TABLE IF NOT EXISTS transactions (transactionId INTEGER PRIMARY KEY AUTOINCREMENT, sourceId INTEGER, sourceTransactionId TEXT, accountId INTEGER, name TEXT, currency TEXT, amount INTEGER, date REAL, institutionId INTEGER NOT NULL, sourceInstitutionId TEXT, categoryId INTEGER)")
            
            for statement in statements {
                if !db.executeUpdate(statement, withArgumentsIn: nil) {
                    log.severe("DB Error: " + db.lastErrorMessage())
                }
            }
            
            // Update the database if needed
            self.updateDatabase(db)
        }
        
        read.maximumNumberOfDatabasesToCreate = 20
        read.delegate = readPoolDelegate
        
        #if DEBUG
        printCompileOptions()
        #endif
        
        return true
    }
    
    fileprivate func updateDatabase(_ db: FMDatabase) {
        var updatesAvailable = true
        
        while updatesAvailable {
            // Check database version
            let userVersion = db.intForQuery("PRAGMA user_version")
            
            // Apply database changes in sequence to bring db up to date
            if userVersion == 0 {
                // Clear the accounts sorting data if we have a new database
                defaults.accountsViewAccountsOrder = nil
                defaults.accountsViewInstitutionsOrder = nil
                
                var alterStatements = [String]()
                
                // Add credit card numbers to accouts table
                alterStatements.append("ALTER TABLE accounts ADD COLUMN number TEXT")
                
                // Update the user_version
                alterStatements.append("PRAGMA user_version=1")
                
                for statement in alterStatements {
                    if !db.executeUpdate(statement, withArgumentsIn: nil) {
                        log.severe("DB Error: " + db.lastErrorMessage())
                    }
                }
            } else if userVersion == 1 {
                var alterStatements = [String]()
                
                // Add institution id to accouts table
                alterStatements.append("ALTER TABLE accounts ADD COLUMN institutionId INTEGER")
                
                // Populate the new column
                alterStatements.append("UPDATE accounts SET institutionId = (SELECT institutionId FROM institutions WHERE accounts.sourceId = institutions.sourceId AND accounts.sourceInstitutionId = institutions.sourceInstitutionId)")
                
                // Update the user_version
                alterStatements.append("PRAGMA user_version=2")
                
                for statement in alterStatements {
                    if !db.executeUpdate(statement, withArgumentsIn: nil) {
                        log.severe("DB Error: " + db.lastErrorMessage())
                    }
                }
            } else if userVersion == 2 {
                var alterStatements = [String]()
                
                // Add passwordInvalid column to track connection problems
                alterStatements.append("ALTER TABLE institutions ADD COLUMN passwordInvalid INTEGER")
                
                // Set passwordInvalid column to false
                alterStatements.append("UPDATE institutions SET passwordInvalid = 0")
                
                // Update the user_version
                alterStatements.append("PRAGMA user_version=3")
                
                for statement in alterStatements {
                    if !db.executeUpdate(statement, withArgumentsIn: nil) {
                        log.severe("DB Error: " + db.lastErrorMessage())
                    }
                }
            } else if userVersion == 3 {
                var alterStatements = [String]()
                
                // Add dateAdded column to know when to ignore notifications
                alterStatements.append("ALTER TABLE institutions ADD COLUMN dateAdded INTEGER")
                
                // Set all dates to distant past
                alterStatements.append("UPDATE institutions SET dateAdded = 0")
                
                // Update the user_version
                alterStatements.append("PRAGMA user_version=4")
                
                for statement in alterStatements {
                    if !db.executeUpdate(statement, withArgumentsIn: nil) {
                        log.severe("DB Error: " + db.lastErrorMessage())
                    }
                }
            } else if userVersion == 4 {
                var alterStatements = [String]()
                
                // Add dateAdded column to know when to ignore notifications
                alterStatements.append("CREATE INDEX transactions_amount ON transactions (amount)")
                
                // Update the user_version
                alterStatements.append("PRAGMA user_version=5")
                
                for statement in alterStatements {
                    if !db.executeUpdate(statement, withArgumentsIn: nil) {
                        log.severe("DB Error: " + db.lastErrorMessage())
                    }
                }
            } else {
                updatesAvailable = false
            }
        }
    }
    
    // MARK: - Helper -
    
    fileprivate func resetDatabase() {
        write.close()
        read.releaseAllDatabases()
        do {
            try FileManager.default.removeItem(atPath: databasePath)
            #if os(OSX)
            AppDelegate.sharedInstance.relaunch()
            #else
            fatalError("Database was reset")
            #endif
        } catch {
            log.severe("Unable to remove database: \(error)")
        }
    }
    
    fileprivate func printCompileOptions() {
        read.inDatabase { db in
            do {
                log.debug("Sqlite version \(String(describing: db.stringForQuery("SELECT sqlite_version()"))) compile options:")
                let result = try db.executeQuery("PRAGMA compile_options")
                while result.next() {
                    log.debug("\(result.string(forColumnIndex: 0))")
                }
                result.close()
            } catch {
                log.severe("DB Error: " + db.lastErrorMessage())
            }
        }
    }
}
