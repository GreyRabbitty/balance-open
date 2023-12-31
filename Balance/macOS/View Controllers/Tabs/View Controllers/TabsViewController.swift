//
//  TabsViewController.swift
//  Bal
//
//  Created by Benjamin Baron on 2/3/16.
//  Copyright © 2016 Balanced Software, Inc. All rights reserved.
//

import Cocoa
import SnapKit

enum Tab: Int {
    case none           = -1
    case accounts       = 0
    case transactions   = 1
    case priceTicker    = 2
}

class TabsViewController: NSViewController {
    
    //
    // MARK: - Properties -
    //
    
    // MARK: Header
    let headerView = View()
    let buttonBackground = PaintCodeView()
    let accountsButton = PaintCodeButton()
    let transactionsButton = PaintCodeButton()
    let priceTickerButton = PaintCodeButton()
    var tabButtons = [PaintCodeButton]()
    
    let addAccountButton = Button()
    let preferencesButton = Button()
    
    
    // MARK: Tabs
    let tabContainerView = View()
    let accountsViewController = AccountsTabViewController()
    let transactionsViewController = TransactionsTabViewController()
    let priceTickerViewController = PriceTickerTabViewController()
    var feedbackViewController: EmailIssueController?
    var tabControllers = [NSViewController]()
    let tabSwitchDelay = 1.0
    let summaryFooterView = View()
    var currentTableViewController: NSViewController?
    var currentVisibleTab = Tab.none
    var defaultTab = Tab.accounts
    
    //
    // MARK: - Lifecycle -
    //
    
    init(defaultTab: Tab = Tab.accounts) {
        super.init(nibName: nil, bundle: nil)
        
        self.defaultTab = defaultTab
        
        tabButtons = [accountsButton, transactionsButton, priceTickerButton]
        tabControllers = [accountsViewController, transactionsViewController, priceTickerViewController]
        
        registerForNotifications()
        addShortcutMonitor()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        currentTableViewController?.viewWillAppear()
    }
    
    deinit {
        unregisterForNotifications()
        removeShortcutMonitor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("unsupported")
    }

    //
    // MARK: - View Creation -
    //
    
    override func loadView() {
        self.view = View()
        
        // Create the UI
        createHeader()
        
        tabContainerView.layerBackgroundColor = NSColor.clear
        self.view.addSubview(tabContainerView)
        tabContainerView.snp.makeConstraints { make in
            make.left.equalTo(self.view)
            make.right.equalTo(self.view)
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalToSuperview()
        }
        
        if debugging.defaultToTransactionsTab {
            showTab(tabIndex: Tab.transactions.rawValue)
        } else {
            showTab(tabIndex: defaultTab.rawValue)
        }
        
        // Preload the transaction views
        let _ = transactionsViewController.view
    }
    
    func createHeader() {
        self.view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.width.equalToSuperview()
            make.height.equalTo(49)
            make.left.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        buttonBackground.drawingBlock = TabButtons.drawBackground
        headerView.addSubview(buttonBackground)
        
        accountsButton.textDrawingFunction = TabButtons.drawAccounts
        accountsButton.buttonText = "Accounts"
        accountsButton.target = self
        accountsButton.action = #selector(tabAction(_:))
        accountsButton.tag = Tab.accounts.rawValue
        headerView.addSubview(accountsButton)
        accountsButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.width.equalTo(99)
            make.height.equalTo(29)
        }
        
        transactionsButton.textDrawingFunction = TabButtons.drawTransactions
        transactionsButton.buttonText = "Transactions"
        transactionsButton.target = self
        transactionsButton.action = #selector(tabAction(_:))
        transactionsButton.tag = Tab.transactions.rawValue
        headerView.addSubview(transactionsButton)
        transactionsButton.snp.makeConstraints { make in
            make.left.equalTo(accountsButton.snp.right)
            make.centerY.equalToSuperview()
            make.width.equalTo(120)
            make.height.equalTo(29)
        }
        
        priceTickerButton.textDrawingFunction = TabButtons.drawPrices
        priceTickerButton.buttonText = "Prices"
        priceTickerButton.target = self
        priceTickerButton.action = #selector(tabAction(_:))
        priceTickerButton.tag = Tab.priceTicker.rawValue
        headerView.addSubview(priceTickerButton)
        priceTickerButton.snp.makeConstraints { make in
            make.left.equalTo(transactionsButton.snp.right)
            make.centerY.equalToSuperview()
            make.width.equalTo(79)
            make.height.equalTo(29)
        }
        
        preferencesButton.target = self
        preferencesButton.action = #selector(showSettingsMenu(_:))
        preferencesButton.image = CurrentTheme.tabs.header.preferencesIcon
        preferencesButton.setButtonType(.momentaryChange)
        preferencesButton.setAccessibilityLabel("Preferences")
        preferencesButton.isBordered = false
        headerView.addSubview(preferencesButton)
        preferencesButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-10)
            make.width.equalTo(16)
            make.height.equalTo(16)
        }
        
        addAccountButton.target = self
        addAccountButton.action = #selector(showAddAccount)
        addAccountButton.image = CurrentTheme.tabs.header.addAccountIcon
        addAccountButton.setButtonType(.momentaryChange)
        addAccountButton.setAccessibilityLabel("Add Account")
        addAccountButton.isBordered = false
        headerView.addSubview(addAccountButton)
        addAccountButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(preferencesButton.snp.left).offset(-10)
            make.width.equalTo(16)
            make.height.equalTo(16)
        }
    }
    
    //
    // MARK: - Actions -
    //
    
    var spinAnimation: CABasicAnimation?
    
    @objc func showSettingsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let versionItem = NSMenuItem(title: appVersionString, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Add an Account          ", action: #selector(showAddAccount), keyEquivalent: "")
        menu.items.first?.isEnabled = networkStatus.isReachable
        menu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Send Feedback", action: #selector(sendFeedback), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates", action: #selector(checkForUpdates(sender:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Balance", action: #selector(quitApp), keyEquivalent: "q")
        
        let event = NSApplication.shared.currentEvent ?? NSEvent()
        NSMenu.popUpContextMenu(menu, with: event, for: sender)
    }
    
    @objc func showAddAccount() {
        NotificationCenter.postOnMainThread(name: Notifications.ShowAddAccount)
    }
    
    @objc func showPreferences() {
        AppDelegate.sharedInstance.showPreferences()
    }
    
    @objc func checkForUpdates(sender: Any) {
        AppDelegate.sharedInstance.checkForUpdates(sender: sender)
    }
    
    @objc func sendFeedback() {
        guard let superview = self.view.superview, let currentTableViewController = currentTableViewController, feedbackViewController == nil else {
            let urlString = "mailto:support@balancemy.money?Subject=Balance%20Feedback"
            _ = try? NSWorkspace.shared.open(URL(string: urlString)!, options: [], configuration: [:])
            return
        }
            
        feedbackViewController = EmailIssueController {
            currentTableViewController.viewWillAppear()
            self.feedbackViewController!.viewWillDisappear()
            superview.replaceSubview(self.feedbackViewController!.view, with: self.view, animation: .slideInFromLeft) {
                currentTableViewController.viewDidAppear()
                self.feedbackViewController!.viewDidDisappear()
                self.feedbackViewController = nil
            }
        }
        
        currentTableViewController.viewWillDisappear()
        feedbackViewController!.viewWillAppear()
        superview.replaceSubview(self.view, with: feedbackViewController!.view, animation: .slideInFromRight) {
            self.feedbackViewController!.viewDidAppear()
            currentTableViewController.viewDidDisappear()
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    func showTab(tabIndex: Int) {
        guard currentVisibleTab.rawValue != tabIndex && feedbackViewController == nil else {
            return
        }
        
        // Move the button background
        let button = tabButtons[tabIndex]
        buttonBackground.snp.removeConstraints()
        buttonBackground.snp.makeConstraints { make in
            make.left.equalTo(button)
            make.centerY.equalToSuperview()
            make.width.equalTo(button)
            make.height.equalTo(button)
        }
        
        // Analytics
        var contentName = ""
        switch tabIndex {
        case Tab.accounts.rawValue:     contentName = "Accounts tab selected"
        case Tab.transactions.rawValue: contentName = "Transactions tab selected"
        case Tab.priceTicker.rawValue:  contentName = "Price Ticker tab selected"
        default: break
        }
        analytics.trackEvent(withName: contentName)
        
        // Constraints
        let constraints: (ConstraintMaker) -> Void = { make in
            make.left.equalTo(self.tabContainerView)
            make.right.equalTo(self.tabContainerView)
            make.top.equalTo(self.tabContainerView)
            make.bottom.equalTo(self.tabContainerView)
        }
        
        let controller = tabControllers[tabIndex]
        
        // Fade between tabs
        if let currentTableViewController = currentTableViewController {
            currentTableViewController.viewWillDisappear()
            controller.viewWillAppear()
            tabContainerView.replaceSubview(currentTableViewController.view, with: controller.view, animation: .none, duration: 0, constraints: constraints) {
                controller.viewDidAppear()
                currentTableViewController.viewDidDisappear()
            }
        } else {
            controller.viewWillAppear()
            tabContainerView.addSubview(controller.view)
            controller.view.snp.makeConstraints(constraints)
            controller.viewDidAppear()
        }
        
        currentTableViewController = controller
        currentVisibleTab = Tab(rawValue: tabIndex)!
        self.view.window?.makeFirstResponder(currentTableViewController)
        
        for button in tabButtons {
            if button.tag == tabIndex {
                button.state = .on
            } else {
                button.state = .off
            }
        }
    }
    
    @objc fileprivate func tabAction(_ sender: Button) {
        showTab(tabIndex: sender.tag)
    }
    
    //
    // MARK: - Notifications -
    //
    
    fileprivate func registerForNotifications() {
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(performSearch(_:)), name: Notifications.PerformSearch)
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(showSearch(_:)), name: Notifications.ShowSearch)
        NotificationCenter.addObserverOnMainThread(self, selector: #selector(showTabIndex(_:)), name: Notifications.ShowTabIndex)
    }
    
    fileprivate func unregisterForNotifications() {
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.PerformSearch)
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.ShowSearch)
        NotificationCenter.removeObserverOnMainThread(self, name: Notifications.ShowTabIndex)
    }

    @objc fileprivate func performSearch(_ notification: Notification) {
        if let searchString = notification.userInfo?[Notifications.Keys.SearchString] as? String {
            if currentVisibleTab != .transactions {
                showTab(tabIndex: Tab.transactions.rawValue)
            }
            transactionsViewController.performSearch(searchString)
        }
    }
    
    @objc fileprivate func showSearch(_ notification: Notification) {
        if currentVisibleTab != .transactions {
            showTab(tabIndex: Tab.transactions.rawValue)
        }
        
        async(after: 0.25) {
            self.transactionsViewController.showSearch()
        }
    }
    
    @objc fileprivate func showTabIndex(_ notification: Notification) {
        if let tabIndex = notification.userInfo?[Notifications.Keys.TabIndex] as? Int {
            showTab(tabIndex: tabIndex)
        }
    }
    
    //
    // MARK: - Keyboard Shortcuts -
    //
    
    fileprivate var shortcutMonitor: Any?
    
    // Command + [1 - 4] to select tabs
    //
    // Command + , to open preferences
    // NOTE: This is needed because there is some hook for this installed automatically and it's incorrectly opening the preferences window
    //
    // Command + R to reload
    //
    func addShortcutMonitor() {
        if shortcutMonitor == nil {
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) { event -> NSEvent? in
                // Specific check for preferences window when locked, otherwise the built in
                // shortcut will take over even though I disabled it in the mainMenu.xib :/
                if appLock.locked {
                    if let characters = event.charactersIgnoringModifiers {
                        if event.modifierFlags.contains(NSEvent.ModifierFlags.command) && characters.count == 1 {
                            if characters == "," {
                                // Return nil to eat the event
                                return nil
                            } else if characters == "h" {
                                NotificationCenter.postOnMainThread(name: Notifications.HidePopover)
                                return nil
                            }
                        }
                    }
                }
                
                let tabButtonKeyCode = 48
                if !appLock.locked && event.window == self.view.window {
                    if let characters = event.charactersIgnoringModifiers {
                        if event.modifierFlags.contains(NSEvent.ModifierFlags.command) && characters.count == 1 {
                            if let intValue = Int(characters), intValue > 0 && intValue <= self.tabButtons.count {
                                // Select tab
                                let tabIndex = intValue - 1
                                self.showTab(tabIndex: tabIndex)
                                return nil
                            } else if characters == "," {
                                // Show Preferences
                                self.showPreferences()
                                return nil
                            } else if characters == "r" {
                                // Reload
                                syncManager.sync()
                                return nil
                            } else if characters == "h" {
                                NotificationCenter.postOnMainThread(name: Notifications.HidePopover)
                            }
                        } else if event.keyCode == tabButtonKeyCode {
                            // Cycle through the tabs
                            var tabIndex = self.currentVisibleTab.rawValue + 1
                            if tabIndex >= self.tabButtons.count {
                                tabIndex = 0
                            }
                            self.showTab(tabIndex: tabIndex)
                            return nil
                        }
                    }
                }
                
                return event
            }
        }
    }
    
    func removeShortcutMonitor() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }
}
