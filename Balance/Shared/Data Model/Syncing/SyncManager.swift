//
//  SyncManager.swift
//  Bal
//
//  Created by Benjamin Baron on 4/8/16.
//  Copyright © 2016 Balanced Software, Inc. All rights reserved.
//

import Foundation

class SyncManager: NSObject {
    
    let syncDefaults = SyncDefaults()
    var hasSyncedSinceLaunch = false // Ensure we always sync on launch
    
    fileprivate let tenYears: TimeInterval = 60 * 60 * 24 * 365 * 10
    
    var syncing: Bool {
        return syncer.syncing
    }
    
    var canceled: Bool {
        return syncer.canceled
    }
        
    fileprivate var syncer = debugging.useMockSyncing ? MockSyncer() : Syncer()
    
    override init() {
        super.init()
        
        currentExchangeRates.load()
        
        #if os(OSX)
        // Register for wake notification
        async {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.syncIfGreaterThanSyncInterval), name: NSWorkspace.didWakeNotification, object: nil)
        }
        #else
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(syncIfGreaterThanSyncInterval), name: .UIApplicationDidBecomeActive)
        #endif
        
        // Network status notifications
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(syncIfGreaterThanSyncInterval), name: Notifications.NetworkBecameReachable)
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(cancel), name: Notifications.NetworkBecameUnreachable)
    }
    
    deinit {
        #if os(OSX)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        #else
        NotificationCenter.removeObserverOnMainThread(self, name: .UIApplicationDidBecomeActive)
        #endif

        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.NetworkBecameReachable)
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.NetworkBecameUnreachable)
    }
    
    @objc func cancel() {
        guard syncer.syncing else {
            return
        }
        
        syncer.cancel()
    }
    
    @objc func automaticSync() {
        sync(userInitiated: false, validateReceipt: true, completion: nil)
    }
    
    @objc func syncIfGreaterThanSyncInterval() {        
        let lastSync = syncDefaults.lastSuccessfulSyncTime
        let performSync = !hasSyncedSinceLaunch || Date().timeIntervalSince(lastSync) > syncDefaults.syncInterval
        if performSync {
            sync(completion: nil)
        }
    }
    
    func sync(userInitiated: Bool = false, validateReceipt: Bool = true, completion: SuccessErrorsHandler? = nil) {
        guard !syncer.syncing && networkStatus.isReachable && Thread.isMainThread else {
            completion?(true, [])
            return
        }
        
        performSync(userInitiated: userInitiated, completion: completion)
    }
    
    fileprivate func performSync(userInitiated: Bool = false, completion: SuccessErrorsHandler? = nil) {
        // Cancel any automatic runs of this method in case it's called manually
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automaticSync), object: nil)
       
        hasSyncedSinceLaunch = true
        
        // Sync exchange rates
        currentExchangeRates.updateExchangeRates()
        
        // Start the sync
        log.debug("Performing full sync")
        self.syncer = debugging.useMockSyncing ? MockSyncer() : Syncer()
        self.syncer.sync(startDate: Date(timeIntervalSinceNow: -tenYears), pruneTransactions: true) { success, errors in
            // Set the last sync dates, record all syncs using the lastSyncTime keys for ease of use then record full syncs separately
            let now = Date()
            self.syncDefaults.lastSyncTime = now
            if success {
                self.syncDefaults.lastSuccessfulSyncTime = now
            }
            
            // Notify observers
            NotificationCenter.postOnMainThread(name: Notifications.SyncCompleted)
            
            // Always run every sync interval. If we were manually run, this will reset the sync interval.
            self.perform(#selector(self.automaticSync), with: nil, afterDelay: self.syncDefaults.syncInterval)
            
            // Call the originally passed completion block if it exists
            completion?(success, errors)
        }
    }
}
