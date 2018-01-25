//
//  AppDelegate.swift
//  balanceios
//
//  Created by Benjamin Baron on 5/25/17.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static fileprivate(set) var sharedInstance: AppDelegate!
    
    // Private
    private var rootViewController: RootViewController?
    
    // Internal
    var window: UIWindow?
    
    // MARK: Initialization
    
    override init() {
        super.init()
        
        // Swizzle all needed methods (can't use class initialize anymore since Swift 3.1)
        swizzleMethods()
        
        // Create a singleton reference
        AppDelegate.sharedInstance = self
        
        if (debugging.useMockSession) {
            URLProtocol.registerClass(PlaidDataMockingProtocol.self)
        }
    }
    
    // MARK: UIApplicationDelegate

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Background fetch
        let hourInSeconds = 60.0 * 60.0
        application.setMinimumBackgroundFetchInterval(hourInSeconds)
        
        //////////////////
        //benDebugging()
        //////////////////
        
        // Initialize singletons
        initializeSingletons()
        
        // Initialize logging
        logging.setupLogging()
        
        // Initialize UserDefaults
        defaults.setupDefaults()
        
        // Initialize database
        _ = database.create()
        
        // Initialyze crash logging and analytics
        analytics.setupAnalytics()
        
        // Access tokens and Realm syncing credentials for debugging (only Xcode builds)
        debugPrintInstitutionKeys()
        
        // Start monitoring network status
        networkStatus.startMonitoring()
        
        // Set first launch flag
        if defaults.firstLaunch {
            defaults.firstLaunch = false
        }
        
        // Window
        self.rootViewController = RootViewController()
        
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = self.rootViewController
        self.window?.backgroundColor = UIColor.white
        self.window?.makeKeyAndVisible()
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        
    }

    func applicationWillTerminate(_ application: UIApplication) {
        
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool
    {
        guard let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else
        {
            return false
        }
        
        // Coinbase callback
        if let queryItems = urlComponents.queryItems,
           urlComponents.host == "coinbase"
        {
            var code: String?
            var state: String?
            
            for queryItem in queryItems
            {
                switch queryItem.name
                {
                case "code":
                    code = queryItem.value
                case "state":
                    state = queryItem.value
                default:()
                }
            }
            
            if let unwrappedCode = code,
               let unwrappedState = state
            {
                let exitingInstitutionId = CoinbaseApi.existingInstitution?.institutionId
                
                CoinbaseApi.handleAuthenticationCallback(state: unwrappedState, code: unwrappedCode, completion: { (success, error) in
                    log.debug(success)
                    log.debug(error)
                    
                    let autenticationResult = CoinbaseAutenticationResult(succeeded: success,
                                                                          error: error,
                                                                          institutionId: exitingInstitutionId)
                    let coinbaseUserInfo: [AnyHashable: Any] = [
                        CoinbaseNotifications.key.auntenticationResult.rawValue: autenticationResult
                    ]
                    
                    NotificationCenter.default.post(name: CoinbaseNotifications.autenticationDidFinish,
                                                    object: nil,
                                                    userInfo: coinbaseUserInfo)
                    syncManager.sync()
                })
            }
        }
        
        return true
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        syncManager.sync(userInitiated: false, validateReceipt: false, skip: [.coinbase]) { (success, error) in
            let result: UIBackgroundFetchResult = success ? .newData : .failed
            completionHandler(result)
        }
    }
}
